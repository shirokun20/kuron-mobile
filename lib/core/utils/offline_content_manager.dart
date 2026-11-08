import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/domain/extensions/content_extensions.dart';
import '../../domain/entities/download_status.dart';
import '../../domain/repositories/user_data_repository.dart';
import '../constants/app_constants.dart';
import 'directory_utils.dart';
import 'download_storage_utils.dart';
import 'reader_image_repair_utils.dart';
import 'capped_map.dart';

class OfflineContentManager {
  OfflineContentManager({
    required this._userDataRepository,
    Logger? logger,
  })  : _logger = logger ?? Logger();

  final UserDataRepository _userDataRepository;
  final Logger _logger;

  // Cache for offline content IDs with TTL
  List<String>? _cachedOfflineIds;
  DateTime? _offlineIdsCacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Cache for content metadata
  final Map<String, Map<String, dynamic>> _metadataCache =
      CappedMap<String, Map<String, dynamic>>(100);
  final Map<String, DateTime> _metadataCacheTime =
      CappedMap<String, DateTime>(100);
  static const Duration _metadataCacheDuration = Duration(minutes: 10);

  // 🚀 OPTIMIZATION: Cache for content paths and image URLs to reduce I/O
  final Map<String, String> _pathCache = CappedMap<String, String>(100);
  final Map<String, DateTime> _pathMissCacheTime =
      CappedMap<String, DateTime>(100);
  final Map<String, DateTime> _pathMissLogTime =
      CappedMap<String, DateTime>(100);
  final Map<String, List<String>> _imageUrlsCache =
      CappedMap<String, List<String>>(100);
  final Map<String, DateTime> _imageUrlsCacheTime =
      CappedMap<String, DateTime>(100);
  final Map<String, Future<void>> _chapterMetadataWriteQueue = {};

  static const Duration _urlCacheDuration = Duration(minutes: 5);
  static const Duration _pathMissCacheDuration = Duration(seconds: 45);
  static const Duration _pathMissLogThrottle = Duration(minutes: 1);

  // Localization callback
  String Function(String key, {Map<String, dynamic>? args})? _localize;

  // Call this whenever a download is removed, cancelled, or deleted so the
  // reader does not serve stale offline paths or image URL lists.
  void invalidateCacheFor(String contentId) {
    _pathCache.remove(contentId);
    _pathMissCacheTime.remove(contentId);
    _pathMissLogTime.remove(contentId);
    _imageUrlsCache.remove(contentId);
    _imageUrlsCacheTime.remove(contentId);
    _metadataCache.remove(contentId);
    _metadataCacheTime.remove(contentId);
    // Also bust the global offline-IDs list so the next check re-queries the DB.
    _cachedOfflineIds = null;
    _offlineIdsCacheTime = null;
    _logger.d('🗑️ Invalidated offline cache for $contentId');
  }

  Future<bool> isContentAvailableOffline(String contentId) async {
    // _logger.d("🔍 Checking offline availability for $contentId");
    try {
      // 1. Check DB first (fastest)
      final downloadStatus =
          await _userDataRepository.getDownloadStatus(contentId);

      if (downloadStatus?.state == DownloadState.completed) {
        // _logger.d("✅ Content $contentId is marked as COMPLETED in DB");
        return true;
      }

      // 🐛 FIX Bug A: If the download is actively in-progress (queued/downloading/paused),
      // do NOT fall through to the filesystem scan.  Partial files already exist on disk
      // and would cause the reader to enter offline mode with an incomplete page set.
      if (downloadStatus != null &&
          (downloadStatus.state == DownloadState.downloading ||
              downloadStatus.state == DownloadState.queued ||
              downloadStatus.state == DownloadState.paused)) {
        _logger.d(
            '⏳ Content $contentId is ${downloadStatus.state} — skipping filesystem fallback');
        return false;
      }

      // _logger.d("⚠️ Content $contentId not COMPLETED in DB (status: ${downloadStatus?.state}), checking filesystem...");

      // 2. Fallback: Check filesystem directly
      // This handles cases where DB might be out of sync or content was manually restored
      final contentPath = await getOfflineContentPath(contentId);
      if (contentPath == null) {
        _logger.w('❌ No offline path found for $contentId');
        return false;
      }

      final contentDir = Directory(contentPath);
      if (!await contentDir.exists()) {
        _logger.w('❌ Directory does not exist for $contentId: $contentPath');
        return false;
      }

      // Check if at least one image file exists
      // Check images subdirectory first (new structure)
      final imagesDir = Directory(path.join(contentPath, 'images'));
      if (await imagesDir.exists() &&
          (await imagesDir.list().isEmpty) == false) {
        final files = await imagesDir.list().toList();
        if (files.any((f) => f is File && _isImageFile(f.path))) {
          // _logger.d("✅ Found images in subfolder for $contentId");
          return true;
        }
      }

      // Check root directory (legacy)
      final files = await contentDir.list().toList();
      final imageFiles = files
          .where((file) => file is File && _isImageFile(file.path))
          .toList();

      if (imageFiles.isNotEmpty) {
        // _logger.d("✅ Found images in root folder for $contentId");
        return true;
      }

      _logger.w('❌ No images found in $contentPath for $contentId');
      return false;
    } catch (e, stackTrace) {
      _logger.e('Error checking offline availability for $contentId',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<String?> getOfflineContentPath(String contentId) async {
    // 🚀 OPTIMIZATION: Check cache first
    if (_pathCache.containsKey(contentId)) {
      final cachedPath = _pathCache[contentId]!;
      // verify it still exists occasionally? No, assume it persists for session to be fast.
      // validation is expensive.
      return cachedPath;
    }

    // Negative-cache misses to avoid repeated strict scans for missing content.
    final missCachedAt = _pathMissCacheTime[contentId];
    if (missCachedAt != null &&
        DateTime.now().difference(missCachedAt) <= _pathMissCacheDuration) {
      return null;
    }

    try {
      final downloadStatus =
          await _userDataRepository.getDownloadStatus(contentId);

      // First, try to get path from database
      if (downloadStatus?.downloadPath != null) {
        // Verify if the DB path actually exists
        final dbPath = downloadStatus!.downloadPath!;
        if (await Directory(dbPath).exists()) {
          return dbPath;
        }
        _logger.w(
            '⚠️ Path from DB does not exist: $dbPath. Searching alternatives...');
      }

      // Fallback: try to find the content in multiple possible locations
      final possiblePaths = await _getPossibleDownloadPaths(contentId);
      // _logger.d("🔍 Scanning ${possiblePaths.length} possible paths for $contentId");

      for (final contentPath in possiblePaths) {
        if (await Directory(contentPath).exists()) {
          _logger
              .i('✅ Found offline content path for $contentId: $contentPath');
          // 🚀 OPTIMIZATION: Update cache
          _pathCache[contentId] = contentPath;
          _pathMissCacheTime.remove(contentId);
          _pathMissLogTime.remove(contentId);
          return contentPath;
        }
      }

      _pathMissCacheTime[contentId] = DateTime.now();
      final missLoggedAt = _pathMissLogTime[contentId];
      if (missLoggedAt == null ||
          DateTime.now().difference(missLoggedAt) > _pathMissLogThrottle) {
        _pathMissLogTime[contentId] = DateTime.now();
        _logger.w(
            '❌ No offline content path found for $contentId after strict scan');
      }
      return null;
    } catch (e, stackTrace) {
      _logger.e('Error getting offline content path for $contentId',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<List<String>> _getPossibleDownloadPaths(String contentId,
      {String? sourceId}) async {
    final paths = <String>[];
    // final effectiveSourceId = sourceId ?? AppStorage.defaultSourceId; // Removed unused variable

    try {
      // Try the smart detection first
      final downloadsPath = await _getDownloadsDirectory();

      // List of source IDs to check: either specific one or all known ones
      final sourcesToCheck = sourceId != null
          ? [sourceId]
          : [...AppStorage.knownSources, AppStorage.defaultSourceId];
      // Deduplicate
      final distinctSources = sourcesToCheck.toSet().toList();

      final safeContentId = DownloadStorageUtils.getSafeContentId(contentId);
      // Note: safeContentId IS elegantId now, but we keep variable for clarity vs legacy checks below

      for (final sId in distinctSources) {
        // NEW: Source-based paths (nhasix/{source}/{contentId}/)
        paths.add(path.join(downloadsPath, 'nhasix', sId, contentId));

        // NEW: Source-based ELEGANT/SAFE paths
        if (safeContentId != contentId) {
          paths.add(path.join(downloadsPath, 'nhasix', sId, safeContentId));
        }

        // LEGACY CHECK: Truncated "Safe" ID (Interim format)
        // We need to re-generate the old truncated hash format to check for it
        if (contentId.length > 50) {
          final bytes = utf8.encode(contentId);
          final digest = sha1.convert(bytes);
          final hash = digest.toString().substring(0, 8);
          final truncatedId = '${contentId.substring(0, 40)}_$hash';

          if (truncatedId != safeContentId) {
            paths.add(path.join(downloadsPath, 'nhasix', sId, truncatedId));
          }
        }
      }

      // LEGACY: Direct paths (nhasix/{contentId}/)
      paths.add(path.join(downloadsPath, 'nhasix', contentId));
      if (safeContentId != contentId) {
        paths.add(path.join(downloadsPath, 'nhasix', safeContentId));
      }

      // Try app documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      for (final sId in distinctSources) {
        paths.add(path.join(
            documentsDir.path, 'downloads', 'nhasix', sId, contentId));
        if (safeContentId != contentId) {
          paths.add(path.join(
              documentsDir.path, 'downloads', 'nhasix', sId, safeContentId));
        }
      }
      paths.add(path.join(documentsDir.path, 'downloads', 'nhasix', contentId));

      // Try external storage directory directly
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final externalRoot = externalDir.path.split('/Android')[0];
          // Try common download folder names
          final folderNames = ['Download', 'Downloads', 'Unduhan', 'Descargas'];
          for (final folderName in folderNames) {
            for (final sId in distinctSources) {
              // NEW: Source-based paths
              paths.add(path.join(
                  externalRoot, folderName, 'nhasix', sId, contentId));
              if (safeContentId != contentId) {
                paths.add(path.join(
                    externalRoot, folderName, 'nhasix', sId, safeContentId));
              }
            }
            // LEGACY: Direct paths
            paths.add(path.join(externalRoot, folderName, 'nhasix', contentId));
          }
        }
      } catch (e) {
        _logger.w('Failed to get external storage paths: $e');
      }

      // Try hardcoded paths
      for (final sId in distinctSources) {
        paths.addAll([
          '/storage/emulated/0/Download/nhasix/$sId/$contentId',
          '/storage/emulated/0/Downloads/nhasix/$sId/$contentId',
          '/storage/emulated/0/Unduhan/nhasix/$sId/$contentId',
          '/sdcard/Download/nhasix/$sId/$contentId',
          '/sdcard/Downloads/nhasix/$sId/$contentId',
        ]);

        if (safeContentId != contentId) {
          paths.addAll([
            '/storage/emulated/0/Download/nhasix/$sId/$safeContentId',
            '/storage/emulated/0/Downloads/nhasix/$sId/$safeContentId',
            '/storage/emulated/0/Unduhan/nhasix/$sId/$safeContentId',
            '/sdcard/Download/nhasix/$sId/$safeContentId',
            '/sdcard/Downloads/nhasix/$sId/$safeContentId',
          ]);
        }
      }

      paths.addAll([
        '/storage/emulated/0/Download/nhasix/$contentId',
        '/storage/emulated/0/Downloads/nhasix/$contentId',
        '/storage/emulated/0/Unduhan/nhasix/$contentId',
        '/sdcard/Download/nhasix/$contentId',
        '/sdcard/Downloads/nhasix/$contentId',
      ]);
    } catch (e) {
      _logger.w('Error getting possible download paths: $e');
    }

    return paths;
  }

  Future<String?> _findContentInFilesystem(String contentId) async {
    try {
      final possiblePaths = await _getPossibleDownloadPaths(contentId);

      for (final contentPath in possiblePaths) {
        final dir = Directory(contentPath);
        if (await dir.exists()) {
          _logger.i('Found content in filesystem: $contentPath');
          return contentPath;
        }
      }

      _logger
          .w('Content $contentId not found in any known filesystem location');
      return null;
    } catch (e) {
      _logger.e('Error scanning filesystem for $contentId: $e');
      return null;
    }
  }

  static const String kFailedPagePrefix = '__failed__:';

  // Returns true if [url] is a failed-page placeholder injected by
  // [getOfflineImageUrls] for a page that was skipped during download.
  static bool isFailedPagePlaceholder(String url) =>
      url.startsWith(kFailedPagePrefix);

  static String? extractOriginalUrlFromPlaceholder(String url) {
    if (!isFailedPagePlaceholder(url)) return null;
    return url.substring(kFailedPagePrefix.length);
  }

  Future<List<String>> getOfflineImageUrls(String contentId) async {
    try {
      // 🚀 OPTIMIZATION: Check cache first
      if (_imageUrlsCache.containsKey(contentId) &&
          _imageUrlsCacheTime.containsKey(contentId) &&
          DateTime.now().difference(_imageUrlsCacheTime[contentId]!) <
              _urlCacheDuration) {
        return _imageUrlsCache[contentId]!;
      }

      final contentPath = await getOfflineContentPath(contentId);
      if (contentPath == null) return [];

      final contentDir = Directory(contentPath);
      if (!await contentDir.exists()) return [];

      // First, try to find images in the 'images' subdirectory (new structure)
      final imagesDir = Directory(path.join(contentPath, 'images'));
      List<File> imageFiles = [];

      if (await imagesDir.exists()) {
        // New structure: images are in images/ subdirectory
        final files = await imagesDir.list().toList();
        imageFiles = files
            .where((file) => file is File && _isImageFile(file.path))
            .cast<File>()
            .toList();
      }

      // Fallback: if no images found in images/ directory, check content directory directly
      if (imageFiles.isEmpty) {
        final files = await contentDir.list().toList();
        imageFiles = files
            .where((file) =>
                file is File &&
                _isImageFile(file.path) &&
                path.basename(file.path) != 'metadata.json')
            .cast<File>()
            .toList();
      }

      // Sort by filename to maintain page order
      imageFiles.sort((a, b) =>
          _extractPageNumber(a.path).compareTo(_extractPageNumber(b.path)));

      final diskUrls = imageFiles.map((file) => file.path).toList();

      // Read failed_pages from metadata.json and inject placeholders so the
      // reader shows a retry card at the correct position.
      final urls = await _injectFailedPagePlaceholders(
        contentPath: contentPath,
        diskUrls: diskUrls,
      );

      // 🚀 OPTIMIZATION: Update cache
      if (urls.isNotEmpty) {
        _imageUrlsCache[contentId] = urls;
        _imageUrlsCacheTime[contentId] = DateTime.now();
      }

      return urls;
    } catch (e, stackTrace) {
      _logger.e('Error getting offline image URLs for $contentId',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<String>> _injectFailedPagePlaceholders({
    required String contentPath,
    required List<String> diskUrls,
  }) async {
    try {
      final metadataFile = File(path.join(contentPath, 'metadata.json'));
      if (!await metadataFile.exists()) return diskUrls;

      final raw = json.decode(await metadataFile.readAsString());
      if (raw is! Map<String, dynamic>) return diskUrls;

      final totalPages = (raw['total_pages'] as num?)?.toInt();
      final isRangeDownload = raw['is_range_download'] == true;
      final rangeStart = (raw['start_page'] as num?)?.toInt() ?? 1;
      final rangeEnd = (raw['end_page'] as num?)?.toInt() ?? totalPages;
      final effectiveStartPage = isRangeDownload ? rangeStart : 1;
      final effectiveEndPage = isRangeDownload ? rangeEnd : totalPages;
      final expectedVisiblePages = switch (effectiveEndPage) {
        final int end when end >= effectiveStartPage =>
          end - effectiveStartPage + 1,
        _ => totalPages,
      };
      final failedPagesRaw = raw['failed_pages'];
      if (expectedVisiblePages == null ||
          expectedVisiblePages <= diskUrls.length ||
          failedPagesRaw == null ||
          diskUrls.isEmpty) {
        // all-failed: no images to show
        return diskUrls;
      }

      // Parse failed_pages: [{page: 14, url: "..."}]
      final failedMap = <int, String>{}; // 1-based page → original URL
      if (failedPagesRaw is List) {
        for (final entry in failedPagesRaw) {
          if (entry is Map) {
            final page = entry['page'] as int?;
            final url = entry['url'] as String?;
            if (page != null && url != null && url.isNotEmpty) {
              failedMap[page] = url;
            }
          }
        }
      }

      if (failedMap.isEmpty) return diskUrls;

      // Create a set of physically downloaded page numbers to avoid injecting placeholders
      // if the page has actually been redownloaded but metadata.json wasn't updated yet.
      final downloadedPages =
          diskUrls.map((url) => _extractPageNumber(url)).toSet();

      // Rebuild the full list by interleaving disk files and placeholders
      // at their correct positions. Range downloads keep original gallery page
      // numbers in metadata, but the reader should only render the selected
      // slice (`start_page..end_page`).
      final result = <String>[];
      var diskIndex = 0;
      for (var pageNum = effectiveStartPage;
          pageNum <= effectiveEndPage!;
          pageNum++) {
        if (failedMap.containsKey(pageNum) &&
            !downloadedPages.contains(pageNum)) {
          result.add('$kFailedPagePrefix${failedMap[pageNum]}');
        } else if (diskIndex < diskUrls.length) {
          result.add(diskUrls[diskIndex++]);
        }
      }
      // Append any remaining disk files (safety net)
      while (diskIndex < diskUrls.length) {
        result.add(diskUrls[diskIndex++]);
      }

      _logger.d(
          '📋 Injected ${failedMap.length} failed-page placeholder(s) for content at $contentPath');
      return result;
    } catch (e) {
      _logger.w('Failed to inject failed-page placeholders: $e');
      return diskUrls;
    }
  }

  Future<void> removeFailedPageFromMetadata(String contentId, int pageNumber) {
    return reconcileChapterMetadataPage(
      contentId: contentId,
      pageNumber: pageNumber,
    );
  }

  Future<void> rewriteMetadataForConvertedLocalPage({
    required String contentId,
    required int pageNumber,
    required String originalLocalPath,
    required String convertedLocalPath,
  }) async {
    if (pageNumber <= 0) {
      return;
    }

    final normalizedOriginalPath = originalLocalPath.trim();
    final normalizedConvertedPath = convertedLocalPath.trim();
    if (normalizedOriginalPath.isEmpty || normalizedConvertedPath.isEmpty) {
      return;
    }

    final contentPath = await getOfflineContentPath(contentId);
    if (contentPath == null || contentPath.trim().isEmpty) {
      return;
    }

    final metadataPath = path.join(contentPath, 'metadata.json');
    await _serializeChapterMetadataWrite(
      metadataPath,
      () async {
        final metadata = await _readMetadataJson(metadataPath);
        if (metadata == null) {
          return;
        }

        final originalFileName = path.basename(normalizedOriginalPath);
        final convertedFileName = path.basename(normalizedConvertedPath);
        if (originalFileName.isEmpty || convertedFileName.isEmpty) {
          return;
        }

        final targetBaseName =
            path.basenameWithoutExtension(convertedFileName).toLowerCase();
        var changed = false;

        List<dynamic>? rewriteStringList(dynamic rawList) {
          if (rawList is! List) {
            return null;
          }

          final next = <dynamic>[];
          for (final entry in rawList) {
            if (entry is! String) {
              next.add(entry);
              continue;
            }

            final rewritten = _rewriteMetadataLocalImageReference(
              value: entry,
              originalFileName: originalFileName,
              convertedFileName: convertedFileName,
              targetBaseName: targetBaseName,
            );
            if (rewritten != entry) {
              changed = true;
            }
            next.add(rewritten);
          }
          return next;
        }

        final rewrittenFiles = rewriteStringList(metadata['files']);
        if (rewrittenFiles != null) {
          metadata['files'] = rewrittenFiles;
        }

        final rewrittenImageUrls = rewriteStringList(metadata['imageUrls']);
        if (rewrittenImageUrls != null) {
          metadata['imageUrls'] = rewrittenImageUrls;
        }

        if (!changed) {
          return;
        }

        await File(metadataPath).writeAsString(json.encode(metadata));
        _logger.i(
          'Rewrote metadata image extension for $contentId '
          'page=$pageNumber ($originalFileName -> $convertedFileName)',
        );
      },
    );
    invalidateCacheFor(contentId);
  }

  Future<void> reconcileChapterMetadataPage({
    required String contentId,
    required int pageNumber,
    String? sourceUrl,
  }) async {
    if (pageNumber <= 0) {
      return;
    }

    final contentPath = await getOfflineContentPath(contentId);
    if (contentPath == null || contentPath.trim().isEmpty) {
      return;
    }

    await _reconcileChapterMetadataAtPath(
      contentPath: contentPath,
      touchedPages: <int>{pageNumber},
      sourceUrlByPage: sourceUrl == null || sourceUrl.trim().isEmpty
          ? const <int, String>{}
          : <int, String>{pageNumber: sourceUrl.trim()},
    );
    invalidateCacheFor(contentId);
  }

  Future<void> reconcileChapterMetadataForCompletedDownload({
    required String contentId,
    String? contentPath,
  }) async {
    final resolvedContentPath = (contentPath != null && contentPath.isNotEmpty)
        ? contentPath
        : await getOfflineContentPath(contentId);
    if (resolvedContentPath == null || resolvedContentPath.trim().isEmpty) {
      return;
    }

    final metadataPath = path.join(resolvedContentPath, 'metadata.json');
    final metadata = await _readMetadataJson(metadataPath);
    if (metadata == null) {
      return;
    }

    final touchedPages = <int>{};
    final failedPages = metadata['failed_pages'];
    if (failedPages is List) {
      for (final entry in failedPages) {
        if (entry is Map) {
          final dynamic rawPage = entry['page'];
          final page = rawPage is num
              ? rawPage.toInt()
              : int.tryParse(rawPage?.toString() ?? '');
          if (page != null && page > 0) {
            touchedPages.add(page);
          }
        }
      }
    }

    if (touchedPages.isEmpty) {
      return;
    }

    await _reconcileChapterMetadataAtPath(
      contentPath: resolvedContentPath,
      touchedPages: touchedPages,
      sourceUrlByPage: const <int, String>{},
    );
    invalidateCacheFor(contentId);
  }

  Future<void> _reconcileChapterMetadataAtPath({
    required String contentPath,
    required Set<int> touchedPages,
    required Map<int, String> sourceUrlByPage,
  }) async {
    if (touchedPages.isEmpty) {
      return;
    }

    final metadataPath = path.join(contentPath, 'metadata.json');
    await _serializeChapterMetadataWrite(
      metadataPath,
      () async {
        final metadata = await _readMetadataJson(metadataPath);
        if (metadata == null) {
          return;
        }

        final failedRaw = metadata['failed_pages'];
        final originalFailed = failedRaw is List
            ? failedRaw
                .map((entry) => entry is Map
                    ? Map<String, dynamic>.from(
                        entry.map(
                          (key, value) => MapEntry(key.toString(), value),
                        ),
                      )
                    : <String, dynamic>{'raw': entry})
                .toList()
            : <Map<String, dynamic>>[];

        final mergedByPage = <int, Map<String, dynamic>>{};
        for (final entry in originalFailed) {
          final dynamic rawPage = entry['page'];
          final page = rawPage is num
              ? rawPage.toInt()
              : int.tryParse(rawPage?.toString() ?? '');
          if (page != null && page > 0) {
            mergedByPage[page] = entry;
          }
        }

        for (final page in touchedPages) {
          final hasValidPage = await _hasValidPageFile(
            contentPath: contentPath,
            pageNumber: page,
          );
          if (hasValidPage) {
            mergedByPage.remove(page);
            continue;
          }

          final sourceUrl = sourceUrlByPage[page];
          if (sourceUrl != null && sourceUrl.isNotEmpty) {
            mergedByPage[page] = <String, dynamic>{
              'page': page,
              'url': sourceUrl,
            };
          }
        }

        final nextFailedPages = mergedByPage.values.toList()
          ..sort((a, b) {
            final left = (a['page'] as num?)?.toInt() ?? 0;
            final right = (b['page'] as num?)?.toInt() ?? 0;
            return left.compareTo(right);
          });

        final changed =
            !_failedPagesEquivalent(originalFailed, nextFailedPages);
        if (!changed) {
          return;
        }

        metadata['failed_pages'] = nextFailedPages;
        await File(metadataPath).writeAsString(json.encode(metadata));
        _logger.i(
          'Reconciled metadata failed_pages for chapter at $contentPath '
          '(pages: ${touchedPages.toList()..sort()})',
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _readMetadataJson(String metadataPath) async {
    final metadataFile = File(metadataPath);
    if (!await metadataFile.exists()) {
      return null;
    }

    final decoded = json.decode(await metadataFile.readAsString());
    if (decoded is! Map) {
      return null;
    }

    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String _rewriteMetadataLocalImageReference({
    required String value,
    required String originalFileName,
    required String convertedFileName,
    required String targetBaseName,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return value;
    }

    final isLocalPath = isLocalReaderImagePath(trimmed);
    final normalizedValue =
        trimmed.startsWith('file://') ? trimmed.substring(7) : trimmed;
    final basename = path.basename(normalizedValue);
    if (basename.isEmpty) {
      return value;
    }

    final sameBaseName =
        path.basenameWithoutExtension(basename).toLowerCase() == targetBaseName;
    final shouldRewrite = basename == originalFileName || sameBaseName;
    if (!shouldRewrite) {
      return value;
    }

    // Safety: avoid rewriting remote metadata URLs unless they are explicit
    // local paths (absolute, file://, or non-http pseudo-local strings).
    if (!isLocalPath) {
      return value;
    }

    final directoryPath = path.dirname(normalizedValue);
    final replacedPath = directoryPath == '.'
        ? convertedFileName
        : path.join(directoryPath, convertedFileName);

    if (trimmed.startsWith('file://')) {
      return 'file://$replacedPath';
    }
    return replacedPath;
  }

  bool _failedPagesEquivalent(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      final leftEntry = left[index];
      final rightEntry = right[index];
      final leftPage = (leftEntry['page'] as num?)?.toInt() ??
          int.tryParse(leftEntry['page']?.toString() ?? '');
      final rightPage = (rightEntry['page'] as num?)?.toInt() ??
          int.tryParse(rightEntry['page']?.toString() ?? '');
      final leftUrl = leftEntry['url']?.toString() ?? '';
      final rightUrl = rightEntry['url']?.toString() ?? '';

      if (leftPage != rightPage || leftUrl != rightUrl) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _hasValidPageFile({
    required String contentPath,
    required int pageNumber,
  }) async {
    final pageCandidates = <String>[
      path.join(contentPath, 'images'),
      contentPath,
    ];

    for (final directoryPath in pageCandidates) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        continue;
      }

      await for (final entity in directory.list()) {
        if (entity is! File) {
          continue;
        }

        if (_extractPageNumber(entity.path) != pageNumber) {
          continue;
        }

        final extension = path.extension(entity.path).toLowerCase();
        if (!kReaderRepairSupportedImageExtensions.contains(extension)) {
          continue;
        }

        try {
          if (await entity.length() <= 0) {
            continue;
          }
          final bytes = await entity.openRead(0, 16).fold<List<int>>(
            <int>[],
            (acc, value) => acc..addAll(value),
          );
          final inferred = inferImageExtension(bytes: bytes);
          if (inferred != null && inferred.isNotEmpty) {
            return true;
          }
        } catch (_) {
          continue;
        }
      }
    }

    return false;
  }

  Future<void> _serializeChapterMetadataWrite(
    String metadataPath,
    Future<void> Function() action,
  ) {
    final previous = _chapterMetadataWriteQueue[metadataPath];
    final chained = (previous ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => action());

    _chapterMetadataWriteQueue[metadataPath] = chained;
    return chained.whenComplete(() {
      final queued = _chapterMetadataWriteQueue[metadataPath];
      if (identical(queued, chained)) {
        _chapterMetadataWriteQueue.remove(metadataPath);
      }
    });
  }

  Future<String?> getOfflineFirstImagePath(String contentId,
      {String? downloadPath}) async {
    try {
      final contentPath =
          downloadPath ?? await getOfflineContentPath(contentId);
      if (contentPath == null) return null;

      // Try images subdirectory first (new structure)
      final imagesDir = path.join(contentPath, 'images');

      // Common first page patterns
      final patterns = [
        '001.jpg',
        '001.png',
        '001.webp',
        '001.avif',
        '001.jpeg',
        '1.jpg',
        '1.png',
        '1.webp',
        '1.avif',
        '1.jpeg',
        '0001.jpg',
        '0001.png',
        '0001.webp',
        '0001.avif',
      ];

      // Try new structure first
      for (final pattern in patterns) {
        final imagePath = path.join(imagesDir, pattern);
        if (await File(imagePath).exists()) {
          return imagePath;
        }
      }

      // Fallback: try old structure (images directly in content folder)
      for (final pattern in patterns) {
        final imagePath = path.join(contentPath, pattern);
        if (await File(imagePath).exists()) {
          return imagePath;
        }
      }

      // Last resort: scan directory (but only return first)
      final imageUrls = await getOfflineImageUrls(contentId);
      return imageUrls.isNotEmpty ? imageUrls.first : null;
    } catch (e) {
      _logger.e('Error getting first offline image for $contentId: $e');
      return null;
    }
  }

  Future<bool> isImageDownloaded(String imageUrl) async {
    try {
      // If it's already a local file path, check directly
      if (imageUrl.startsWith('/') || imageUrl.contains('/downloads/')) {
        final file = File(imageUrl);
        return await file.exists() && await file.length() > 0;
      }

      // For online URLs, we need to find the corresponding offline path
      // Extract content ID from URL pattern (assuming URL contains content ID)
      final contentId = _extractContentIdFromUrl(imageUrl);
      if (contentId == null) return false;

      final contentPath = await getOfflineContentPath(contentId);
      if (contentPath == null) return false;

      // Extract filename from URL
      final uri = Uri.parse(imageUrl);
      final filename = path.basename(uri.path);

      // First, try to find the file in the 'images' subdirectory (new structure)
      final imagesDirPath = path.join(contentPath, 'images');
      final imagesDir = Directory(imagesDirPath);

      if (await imagesDir.exists()) {
        final offlineImagePath = path.join(imagesDirPath, filename);
        final file = File(offlineImagePath);
        if (await file.exists() && await file.length() > 0) {
          return true;
        }
      }

      // Fallback: check directly in content directory (old structure)
      final offlineImagePath = path.join(contentPath, filename);
      final file = File(offlineImagePath);
      return await file.exists() && await file.length() > 0;
    } catch (e, stackTrace) {
      _logger.e('Error checking if image is downloaded: $imageUrl',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<List<String>> getOfflineContentIds() async {
    try {
      // Check cache first
      if (_cachedOfflineIds != null &&
          _offlineIdsCacheTime != null &&
          DateTime.now().difference(_offlineIdsCacheTime!) < _cacheDuration) {
        _logger.d('Using cached offline content IDs');
        return _cachedOfflineIds!;
      }

      final downloads = await _getAllCompletedDownloadsFromDb();

      final offlineIds = <String>[];

      for (final download in downloads) {
        if (await isContentAvailableOffline(download.contentId)) {
          offlineIds.add(download.contentId);
        }
      }

      // Update cache
      _cachedOfflineIds = offlineIds;
      _offlineIdsCacheTime = DateTime.now();

      return offlineIds;
    } catch (e, stackTrace) {
      _logger.e('Error getting offline content IDs',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<DownloadStatus>> _getAllCompletedDownloadsFromDb() async {
    const batchSize = 500;
    var offset = 0;
    final allDownloads = <DownloadStatus>[];

    while (true) {
      final page = await _userDataRepository.getAllDownloads(
        state: DownloadState.completed,
        limit: batchSize,
        offset: offset,
      );

      if (page.isEmpty) {
        break;
      }

      allDownloads.addAll(page);
      if (page.length < batchSize) {
        break;
      }
      offset += batchSize;
    }

    return allDownloads;
  }

  String _extractSourceIdFromPath(String contentPath) {
    try {
      final segments = contentPath.split(path.separator);
      final nhasixIndex = segments.indexOf('nhasix');
      if (nhasixIndex != -1 && nhasixIndex + 1 < segments.length) {
        final potentialSource = segments[nhasixIndex + 1];
        // Only return if it's a known source (not a content ID)
        if (AppStorage.knownSources.contains(potentialSource)) {
          return potentialSource;
        }
      }
    } catch (e) {
      _logger.w('Error extracting sourceId from path: $e');
    }
    return AppStorage.defaultSourceId;
  }

  String _extractSourceIdFromMetadataOrPath(
    Map<String, dynamic>? metadata,
    String contentPath,
  ) {
    final metadataSourceId =
        DownloadStorageUtils.getSourceIdFromMetadata(metadata);
    if (metadataSourceId != null && metadataSourceId.isNotEmpty) {
      return metadataSourceId;
    }

    // Fallback to path extraction
    return _extractSourceIdFromPath(contentPath);
  }

  Future<List<String>> searchOfflineContent(String query) async {
    try {
      if (query.trim().isEmpty) return [];

      final offlineIds = await getOfflineContentIds();
      final matchingIds = <String>[];

      // Get favorites and history for additional metadata
      final favorites =
          await _userDataRepository.getFavorites(limit: AppLimits.maxBatchSize);
      final history =
          await _userDataRepository.getHistory(limit: AppLimits.maxBatchSize);

      final favoriteMap = {for (var fav in favorites) fav['id']: fav};
      final historyMap = {for (var hist in history) hist.contentId: hist};

      for (final contentId in offlineIds) {
        // Search in content ID
        if (contentId.toLowerCase().contains(query.toLowerCase())) {
          matchingIds.add(contentId);
          continue;
        }

        // Search in favorite title if available
        final favorite = favoriteMap[contentId];
        if (favorite != null) {
          final title = favorite['title'] as String?;
          if (title != null &&
              title.toLowerCase().contains(query.toLowerCase())) {
            matchingIds.add(contentId);
            continue;
          }
        }

        // Search in history title if available
        final historyEntry = historyMap[contentId];
        if (historyEntry != null) {
          final title = historyEntry.title;
          if (title != null &&
              title.toLowerCase().contains(query.toLowerCase())) {
            matchingIds.add(contentId);
            continue;
          }
        }
      }

      return matchingIds;
    } catch (e, stackTrace) {
      _logger.e('Error searching offline content',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<Map<String, dynamic>?> getOfflineContentMetadata(
      String contentId) async {
    try {
      // Check cache first
      if (_metadataCache.containsKey(contentId) &&
          _metadataCacheTime.containsKey(contentId) &&
          DateTime.now().difference(_metadataCacheTime[contentId]!) <
              _metadataCacheDuration) {
        _logger.d('Using cached metadata for $contentId');
        return _metadataCache[contentId];
      }

      // Try to get from favorites first
      final favorites =
          await _userDataRepository.getFavorites(limit: AppLimits.maxBatchSize);
      final favorite =
          favorites.where((fav) => fav['id'] == contentId).firstOrNull;
      _logger.i(_getLocalized('offlineContentMetadata',
          args: {'contentId': contentId, 'source': 'favorites'},
          fallback: 'apakah data dari favorite? ${favorite != null}'));
      if (favorite != null) {
        final metadata = {
          'id': contentId,
          'title': favorite['title'] ?? 'Unknown Title',
          'coverUrl': favorite['cover_url'] ?? '',
          'source': 'favorites',
        };
        // Cache the result
        _metadataCache[contentId] = metadata;
        _metadataCacheTime[contentId] = DateTime.now();
        return metadata;
      }

      // Try to get from history
      final historyEntry = await _userDataRepository.getHistoryEntry(contentId);
      _logger.i(_getLocalized('offlineContentMetadata',
          args: {'contentId': contentId, 'source': 'history'},
          fallback: 'apakah data dari history? ${historyEntry != null}'));
      _logger.i('isi file history nya: $historyEntry');
      if (historyEntry != null) {
        final metadata = {
          'id': contentId,
          'title': historyEntry.title ?? 'Unknown Title',
          'coverUrl': historyEntry.coverUrl ?? '',
          'source': 'history',
        };
        // Cache the result
        _metadataCache[contentId] = metadata;
        _metadataCacheTime[contentId] = DateTime.now();
        return metadata;
      }

      // Fallback: Try reading from metadata.json file
      final contentPath = await getOfflineContentPath(contentId);
      if (contentPath != null) {
        final metadataFile = File(path.join(contentPath, 'metadata.json'));
        if (await metadataFile.exists()) {
          try {
            final metadataContent = await metadataFile.readAsString();
            final decoded = json.decode(metadataContent);
            if (decoded is! Map<String, dynamic>) return null;
            final fileMetadata = decoded;
            final metadata = {
              'id': contentId,
              'title': DownloadStorageUtils.getSafeTitleFromMetadata(
                fileMetadata,
                contentId,
              ),
              'coverUrl':
                  fileMetadata['coverUrl'] ?? fileMetadata['cover_url'] ?? '',
              'source': 'metadata_file',
              'sourceId':
                  DownloadStorageUtils.getSourceIdFromMetadata(fileMetadata) ??
                      SourceType.nhentai.id,
            };
            // Cache the result
            _metadataCache[contentId] = metadata;
            _metadataCacheTime[contentId] = DateTime.now();
            _logger.d('Got metadata from file for $contentId');
            return metadata;
          } catch (e) {
            _logger.w('Error reading metadata.json for $contentId: $e');
          }
        }
      }

      // Final fallback to basic info
      final metadata = {
        'id': contentId,
        'title': contentId,
        'coverUrl': '',
        'source': 'offline',
      };
      // Cache the result
      _metadataCache[contentId] = metadata;
      _metadataCacheTime[contentId] = DateTime.now();
      return metadata;
    } catch (e, stackTrace) {
      _logger.e('Error getting offline content metadata for $contentId',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<int> getOfflineStorageUsage() async {
    try {
      // 1. Try to get total size from DB (fastest)
      final totalSize = await _userDataRepository.getTotalDownloadSize(
        state: DownloadState.completed,
      );

      if (totalSize > 0) {
        return totalSize;
      }

      // 2. Fallback: Only iterate filesystem if DB returns 0 (e.g. migration needed or clean install)
      // This is still slow but should rarely happen for existing users with data
      _logger
          .w('⚠️ DB download size is 0, falling back to slow filesystem scan');
      final offlineIds = await getOfflineContentIds();
      int fsTotalSize = 0;

      for (final contentId in offlineIds) {
        final contentPath = await getOfflineContentPath(contentId);
        if (contentPath != null) {
          final contentDir = Directory(contentPath);
          if (await contentDir.exists()) {
            await for (final file in contentDir.list(recursive: true)) {
              if (file is File) {
                final stat = await file.stat();
                fsTotalSize += stat.size;
              }
            }
          }
        }
      }

      return fsTotalSize;
    } catch (e, stackTrace) {
      _logger.e('Error calculating offline storage usage',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  Future<List<Content>> getAllOfflineContentFromFileSystem(
      String loadPath) async {
    return await scanBackupFolder(loadPath);
  }

  Future<void> cleanupOrphanedFiles() async {
    try {
      _logger.i(_getLocalized('cleanupOrphanedFilesStarted',
          fallback: 'Starting cleanup of orphaned offline files'));

      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory(path.join(appDir.path, 'downloads'));

      if (!await downloadsDir.exists()) return;

      final validDownloads = await _getAllCompletedDownloadsFromDb();

      final validPaths = validDownloads
          .map((d) => d.downloadPath)
          .where((p) => p != null)
          .cast<String>()
          .toSet();

      await for (final entity in downloadsDir.list()) {
        if (entity is Directory) {
          if (!validPaths.contains(entity.path)) {
            _logger.d('Removing orphaned directory: ${entity.path}');
            await entity.delete(recursive: true);
          }
        }
      }

      _logger.i(_getLocalized('cleanupOrphanedFilesCompleted',
          fallback: 'Cleanup of orphaned offline files completed'));
    } catch (e, stackTrace) {
      _logger.e('Error during cleanup of orphaned files',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<Content?> createOfflineContent(String contentId) async {
    try {
      final contentPath = await getOfflineContentPath(contentId);
      if (contentPath == null) return null;

      final contentDir = Directory(contentPath);
      if (!await contentDir.exists()) return null;

      // Try to read metadata.json first
      String title = contentId;
      Map<String, dynamic>? metadata;
      try {
        final metadataFile = File(path.join(contentPath, 'metadata.json'));
        if (await metadataFile.exists()) {
          final metadataContent = await metadataFile.readAsString();
          metadata = json.decode(metadataContent) as Map<String, dynamic>;
          title = DownloadStorageUtils.getSafeTitleFromMetadata(
            metadata,
            contentId,
          );
        }
      } catch (e) {
        _logger.w('Error reading metadata for $contentId: $e');
      }

      // Extract sourceId from metadata or path
      final sourceId =
          _extractSourceIdFromMetadataOrPath(metadata, contentPath);

      // Get image files
      final imageUrls = await getOfflineImageUrls(contentId);
      if (imageUrls.isEmpty) return null;

      final coverUrl = await _resolveOfflineCoverUrl(
        contentPath: contentPath,
        imageUrls: imageUrls,
      );

      return Content(
        sourceId: sourceId,
        id: contentId,
        title: title,
        coverUrl: coverUrl,
        tags: [],
        artists: [],
        characters: [],
        parodies: [],
        groups: [],
        language: '',
        pageCount: imageUrls.length,
        imageUrls: imageUrls,
        uploadDate: DateTime.now(),
        favorites: 0,
        englishTitle: null,
        japaneseTitle: null,
      );
    } catch (e, stackTrace) {
      _logger.e('Error creating offline content for $contentId',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<String> _resolveOfflineCoverUrl({
    required String contentPath,
    required List<String> imageUrls,
  }) async {
    final preferredNames = <String>[
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
      'cover.webp',
      'cover.avif',
      'thumbnail.jpg',
      'thumbnail.jpeg',
      'thumbnail.png',
      'thumbnail.webp',
      'thumbnail.avif',
      'thumb.jpg',
      'thumb.jpeg',
      'thumb.png',
      'thumb.webp',
      'thumb.avif',
    ];

    final candidates = <String>[
      for (final name in preferredNames) path.join(contentPath, name),
      for (final name in preferredNames) path.join(contentPath, 'images', name),
      ...imageUrls.take(2),
    ];

    for (final candidate in candidates) {
      if (await _isValidOfflineCoverCandidate(candidate)) {
        return candidate;
      }
    }

    return '';
  }

  Future<bool> _isValidOfflineCoverCandidate(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<Content>> searchOfflineContentFromFileSystem(
      String backupPath, String query) async {
    try {
      final backupDir = Directory(backupPath);

      if (!await backupDir.exists()) {
        _logger.w('Backup folder does not exist: $backupPath');
        return [];
      }

      final matchingWithTimes = <MapEntry<Content, DateTime>>[];
      final queryLower = query.toLowerCase();

      // Known source identifiers to check for nested structure
      final knownSources = AppStorage.knownSources;

      await for (final entity in backupDir.list()) {
        if (entity is Directory) {
          final folderName = path.basename(entity.path);

          // Check if this is a source folder (e.g., nhentai/, crotpedia/)
          if (knownSources.contains(folderName)) {
            // Search inside source folder
            _logger.d('Searching in source folder: $folderName');
            final sourceResults =
                await _searchInFolder(entity.path, queryLower);
            matchingWithTimes.addAll(sourceResults);
          } else {
            // Legacy: Could be a content folder directly
            final result =
                await _searchContentFolder(entity, folderName, queryLower);
            if (result != null) {
              matchingWithTimes.add(result);
            }
          }
        }
      }

      // Sort by modification time descending (newest first)
      matchingWithTimes.sort((a, b) => b.value.compareTo(a.value));
      final matchingContents = matchingWithTimes.map((e) => e.key).toList();

      _logger.i(
          'Found ${matchingContents.length} matching content items for query: $query');
      return matchingContents;
    } catch (e, stackTrace) {
      _logger.e('Error searching offline content from file system',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<MapEntry<Content, DateTime>>> _searchInFolder(
      String folderPath, String queryLower) async {
    final results = <MapEntry<Content, DateTime>>[];
    final folderDir = Directory(folderPath);

    if (!await folderDir.exists()) return results;

    await for (final entity in folderDir.list()) {
      if (entity is Directory) {
        final contentId = path.basename(entity.path);
        final result =
            await _searchContentFolder(entity, contentId, queryLower);
        if (result != null) {
          results.add(result);
        }
      }
    }

    return results;
  }

  Future<MapEntry<Content, DateTime>?> _searchContentFolder(
      FileSystemEntity entity, String contentId, String queryLower) async {
    try {
      // Search in content ID
      final contentIdMatch = contentId.toLowerCase().contains(queryLower);

      // Try to read title from metadata.json
      String title = contentId;
      bool titleMatch = false;
      String sourceId = 'offline'; // Default sourceId

      try {
        final metadataFile = File(path.join(entity.path, 'metadata.json'));
        Map<String, dynamic>? metadata;
        if (await metadataFile.exists()) {
          final metadataContent = await metadataFile.readAsString();
          metadata = json.decode(metadataContent) as Map<String, dynamic>;
          title = DownloadStorageUtils.getSafeTitleFromMetadata(
            metadata,
            contentId,
          );
          titleMatch = title.toLowerCase().contains(queryLower);
        }
        // Store metadata for later use
        sourceId = _extractSourceIdFromMetadataOrPath(metadata, entity.path);
      } catch (e) {
        _logger.w('Error reading metadata for search in $contentId: $e');
      }

      // If matches, load full content data
      if (!contentIdMatch && !titleMatch) {
        return null;
      }

      final imagesDir = Directory(path.join(entity.path, 'images'));
      List<File> imageFiles = [];

      if (await imagesDir.exists()) {
        imageFiles = await imagesDir
            .list(recursive: true)
            .where((f) => f is File && _isImageFile(f.path))
            .cast<File>()
            .toList();
      }

      // Fallback: check contentId directory directly
      if (imageFiles.isEmpty) {
        final contentEntities = await Directory(entity.path).list().toList();
        final directImageFiles = contentEntities
            .where((f) =>
                f is File &&
                _isImageFile(f.path) &&
                path.basename(f.path) != 'metadata.json')
            .cast<File>()
            .toList();
        if (directImageFiles.isNotEmpty) {
          imageFiles.addAll(directImageFiles);
        }
      }

      if (imageFiles.isEmpty) return null;

      // Sort images by page number
      imageFiles.sort((a, b) =>
          _extractPageNumber(a.path).compareTo(_extractPageNumber(b.path)));

      final imageUrls = imageFiles.map((f) => f.path).toList();

      final coverUrl = await _resolveOfflineCoverUrl(
        contentPath: entity.path,
        imageUrls: imageUrls,
      );

      final content = Content(
        sourceId: sourceId,
        id: contentId,
        title: title,
        coverUrl: coverUrl,
        tags: [],
        artists: [],
        characters: [],
        parodies: [],
        groups: [],
        language: '',
        pageCount: imageUrls.length,
        imageUrls: imageUrls,
        uploadDate: DateTime.now(),
        favorites: 0,
        englishTitle: null,
        japaneseTitle: null,
      );

      // Get folder modification time
      final folderStat = await entity.stat();
      final modifiedTime = folderStat.modified;

      _logger.d(
          'Found matching content: $contentId - $title (${imageUrls.length} pages)');

      return MapEntry(content, modifiedTime);
    } catch (e) {
      return null;
    }
  }

  Future<List<Content>> scanBackupFolder(String backupPath) async {
    try {
      final backupDir = Directory(backupPath);

      if (!await backupDir.exists()) {
        _logger.w('Backup folder does not exist: $backupPath');
        return [];
      }

      final contents = <Content>[];
      final contentWithTimes = <MapEntry<Content, DateTime>>[];

      // Known source identifiers to check for nested structure
      final knownSources = AppStorage.knownSources;

      await for (final entity in backupDir.list()) {
        if (entity is Directory) {
          final folderName = path.basename(entity.path);

          // Check if this is a source folder (e.g., nhentai/, crotpedia/)
          if (knownSources.contains(folderName)) {
            // Scan content inside source folder
            _logger.d('Scanning source folder: $folderName');
            final sourceContents = await _scanContentFolder(entity.path);
            contentWithTimes.addAll(sourceContents);
          } else {
            // Could be legacy content folder, try to scan it directly
            final contentResult =
                await _tryParseContentFolder(entity, folderName);
            if (contentResult != null) {
              contentWithTimes.add(contentResult);
            }
          }
        }
      }

      // Sort by modification time descending (newest first)
      contentWithTimes.sort((a, b) => b.value.compareTo(a.value));
      contents.addAll(contentWithTimes.map((e) => e.key));

      _logger.i('Found ${contents.length} backup content items');
      return contents;
    } catch (e, stackTrace) {
      _logger.e('Error scanning backup folder: $backupPath',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<MapEntry<Content, DateTime>>> _scanContentFolder(
      String folderPath) async {
    final folderDir = Directory(folderPath);
    final results = <MapEntry<Content, DateTime>>[];

    if (!await folderDir.exists()) return results;

    await for (final entity in folderDir.list()) {
      if (entity is Directory) {
        final contentId = path.basename(entity.path);

        // Check for v1 metadata in v2 structure and fix it
        try {
          final metadataFile = File(path.join(entity.path, 'metadata.json'));
          if (await metadataFile.exists()) {
            final content = await metadataFile.readAsString();
            if (!content.contains('schemaVersion')) {
              // Found v1 metadata in source folder - UPGRADE IT
              final jsonMap = jsonDecode(content) as Map<String, dynamic>;
              final sourceName = path.basename(folderPath); // e.g., 'nhentai'

              // Use proper migration constructor from ContentMetadata
              // Note: We need a temporary import or just manual map manipulation here
              // Since we can't easily import ContentMetadata here without circular deps if not already imported
              // We'll do manual map manipulation for safety

              final newMetadata = Map<String, dynamic>.from(jsonMap);
              newMetadata['schemaVersion'] = '2.0';
              newMetadata['source'] = sourceName;

              // Handle tags string to map conversion if needed
              if (newMetadata['tags'] is List &&
                  newMetadata['tags'].isNotEmpty &&
                  newMetadata['tags'][0] is String) {
                newMetadata['tags'] = (newMetadata['tags'] as List)
                    .map((t) => {
                          'name': t.toString(),
                          'type': 'tag',
                          'count': 0,
                          'url': ''
                        })
                    .toList();
              }

              await metadataFile.writeAsString(jsonEncode(newMetadata));
              _logger.i(
                  'Auto-upgraded metadata for $contentId to v2 in $sourceName folder');
            }
          }
        } catch (e) {
          _logger.w('Failed to check/upgrade metadata for $contentId: $e');
        }

        final contentResult = await _tryParseContentFolder(entity, contentId);
        if (contentResult != null) {
          results.add(contentResult);
        }
      }
    }
    return results;
  }

  Future<MapEntry<Content, DateTime>?> _tryParseContentFolder(
      FileSystemEntity entity, String contentId) async {
    try {
      final imagesDir = Directory(path.join(entity.path, 'images'));
      List<File> imageFiles = [];

      if (await imagesDir.exists()) {
        try {
          final files = await imagesDir.list(recursive: true).toList();
          imageFiles = files
              .where((f) => f is File && _isImageFile(f.path))
              .cast<File>()
              .toList();
        } catch (e) {
          // ignore
        }
      }

      // Fallback: check contentId directory directly
      if (imageFiles.isEmpty) {
        try {
          final contentDir = Directory(entity.path);
          final contentEntities = await contentDir.list().toList();
          final directImageFiles = contentEntities
              .where((f) =>
                  f is File &&
                  _isImageFile(f.path) &&
                  path.basename(f.path) != 'metadata.json')
              .cast<File>()
              .toList();

          if (directImageFiles.isNotEmpty) {
            imageFiles.addAll(directImageFiles);
          }
        } catch (e) {
          // ignore
        }
      }

      if (imageFiles.isEmpty) return null;

      // Sort images by page number
      imageFiles.sort((a, b) =>
          _extractPageNumber(a.path).compareTo(_extractPageNumber(b.path)));

      final imageUrls = imageFiles.map((f) => f.path).toList();

      // Try to read title AND ID from metadata.json
      String title = contentId;
      String actualContentId = contentId; // Default to folder name
      Map<String, dynamic>? metadata;
      bool metadataExists = false;

      try {
        final metadataFile = File(path.join(entity.path, 'metadata.json'));
        if (await metadataFile.exists()) {
          metadataExists = true;
          final metadataContent = await metadataFile.readAsString();
          metadata = json.decode(metadataContent) as Map<String, dynamic>;

          title = DownloadStorageUtils.getSafeTitleFromMetadata(
            metadata,
            contentId,
          );

          actualContentId =
              DownloadStorageUtils.getOriginalContentIdFromMetadata(
            metadata,
            fallbackContentId: contentId,
          );
        }
      } catch (e) {
        _logger.w('Error reading metadata for $contentId: $e');
      }

      // Extract sourceId from metadata or path
      final sourceId =
          _extractSourceIdFromMetadataOrPath(metadata, entity.path);

      // AUTO-GENERATE metadata.json for manually placed content (e.g., from external sources)
      // This ensures content works properly even if placed without metadata
      if (!metadataExists && imageFiles.isNotEmpty) {
        try {
          _logger.i(
              'Auto-generating metadata.json for manually imported content: $contentId');
          await DownloadStorageUtils.saveLocalMetadata(
            contentId: actualContentId,
            sourceId: sourceId,
            title: title,
            savePath: entity.path,
            coverUrl: imageFiles.first.path,
            totalImages: imageFiles.length,
            extraData: {
              'autoGenerated': true,
              'importedAt': DateTime.now().toIso8601String(),
            },
          );
        } catch (e) {
          _logger.w('Failed to auto-generate metadata for $contentId: $e');
        }
      }

      final coverUrl = await _resolveOfflineCoverUrl(
        contentPath: entity.path,
        imageUrls: imageUrls,
      );

      final content = Content(
        sourceId: sourceId,
        id: actualContentId, // Use the resolved ID (from metadata or folder name)
        title: title,
        coverUrl: coverUrl,
        tags: [],
        artists: [],
        characters: [],
        parodies: [],
        groups: [],
        language: '',
        pageCount: imageUrls.length,
        imageUrls: imageUrls,
        uploadDate: DateTime.now(),
        favorites: 0,
        englishTitle: null,
        japaneseTitle: null,
      );

      // Get folder modification time
      final folderStat = await entity.stat();
      final modifiedTime = folderStat.modified;

      return MapEntry(content, modifiedTime);
    } catch (e) {
      return null;
    }
  }

  bool _isImageFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp']
        .contains(extension);
  }

  int _extractPageNumber(String filePath) {
    final filename = path.basenameWithoutExtension(filePath);
    final match = RegExp(r'(\d+)').firstMatch(filename);
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  String? _extractContentIdFromUrl(String imageUrl) {
    try {
      // Try different URL patterns to extract content ID
      final uri = Uri.parse(imageUrl);

      // Special handling for nhentai URLs: https://i.nhentai.net/galleries/[contentId]/[page].jpg
      if (uri.host == 'i.nhentai.net' && uri.pathSegments.length >= 3) {
        if (uri.pathSegments[0] == 'galleries' &&
            uri.pathSegments.length >= 2) {
          final contentId = uri.pathSegments[1];
          if (RegExp(r'^\d+$').hasMatch(contentId)) {
            return contentId;
          }
        }
      }

      // Pattern 1: URL contains content ID in path segments
      // e.g., https://example.com/content/12345/page/1.jpg
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2) {
        // Look for numeric content ID
        for (final segment in pathSegments) {
          if (RegExp(r'^\d+$').hasMatch(segment)) {
            return segment;
          }
        }
      }

      // Pattern 2: Content ID in query parameters
      // e.g., https://example.com/image.jpg?contentId=12345
      final contentIdParam = uri.queryParameters['contentId'];
      if (contentIdParam != null && contentIdParam.isNotEmpty) {
        return contentIdParam;
      }

      // Pattern 3: Content ID in hostname or subdomain
      // e.g., https://12345.example.com/image.jpg
      final hostParts = uri.host.split('.');
      for (final part in hostParts) {
        if (RegExp(r'^\d+$').hasMatch(part)) {
          return part;
        }
      }

      // Pattern 4: Extract from filename if it contains content ID
      // e.g., https://example.com/12345_001.jpg
      final filename = path.basenameWithoutExtension(uri.path);
      final filenameMatch = RegExp(r'^(\d+)').firstMatch(filename);
      if (filenameMatch != null) {
        return filenameMatch.group(1);
      }

      return null;
    } catch (e) {
      _logger.w('Error extracting content ID from URL: $imageUrl, error: $e');
      return null;
    }
  }

  static String formatStorageSize(int bytes) {
    if (bytes == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  void clearCache() {
    _cachedOfflineIds = null;
    _offlineIdsCacheTime = null;
    _pathCache.clear();
    _pathMissCacheTime.clear();
    _pathMissLogTime.clear();
    _metadataCache.clear();
    _metadataCacheTime.clear();
    _logger.d('Offline content cache cleared');
  }

  void clearContentCache(String contentId) {
    _pathCache.remove(contentId);
    _pathMissCacheTime.remove(contentId);
    _pathMissLogTime.remove(contentId);
    _metadataCache.remove(contentId);
    _metadataCacheTime.remove(contentId);
    _logger.d('Cache cleared for content: $contentId');
  }

  Future<String> _getDownloadsDirectory() async {
    return DirectoryUtils.getDownloadsDirectory();
  }

  // Returns map with 'synced' (new items) and 'updated' (fixed paths) counts
  // [onProgress] - Optional callback (processed, total)
  Future<Map<String, int>> syncBackupToDatabase(
    String backupPath, {
    String? sourceId,
    void Function(int processed, int total)? onProgress,
  }) async {
    final scanPath = _resolveBackupScanPath(backupPath, sourceId);
    final scanDir = Directory(scanPath);

    if (sourceId != null && !await scanDir.exists()) {
      _logger.w('Source folder does not exist for sync: $scanPath');
      return {'synced': 0, 'updated': 0};
    }

    if (sourceId == null) {
      // NEW: Auto-migrate legacy content before scanning root backup folder.
      try {
        final backupDir = Directory(backupPath);
        if (await backupDir.exists()) {
          await for (final entity in backupDir.list()) {
            if (entity is Directory) {
              final folderName = path.basename(entity.path);
              if (!AppStorage.knownSources.contains(folderName)) {
                // Potential legacy content - attempt migration
                // This moves nhasix/{id} -> nhasix/nhentai/{id}
                final migrated =
                    await DownloadStorageUtils.migrateToSourceFolder(
                  folderName,
                  sourceId:
                      AppStorage.defaultSourceId, // Default for legacy content
                );
                if (migrated) {
                  _logger.i(
                      'Auto-migrated legacy content $folderName to nhentai source');
                }
              }
            }
          }
        }
      } catch (e) {
        _logger.w('Auto-migration check failed: $e');
      }
    }

    final completedCount = await _userDataRepository.getDownloadsCount(
      state: DownloadState.completed,
      sourceId: sourceId,
    );

    if (completedCount > 0) {
      final existingDownloads = await _userDataRepository.getAllDownloads(
        state: DownloadState.completed,
        sourceId: sourceId,
        limit: completedCount,
        offset: 0,
        orderBy: 'created_at',
        descending: true,
      );

      for (final download in existingDownloads) {
        await _userDataRepository.deleteDownloadStatus(download.contentId);
      }

      final scopeLabel =
          sourceId == null ? 'all sources' : sourceId.toLowerCase();
      _logger.i(
        'Cleared $completedCount completed $scopeLabel records before resync',
      );
    }

    final contents = await scanBackupFolder(scanPath);
    int syncedCount = 0;
    int updatedCount = 0;
    final int total = contents.length;
    int processed = 0;

    // Report initial progress (0/total)
    onProgress?.call(0, total);

    for (final content in contents) {
      // Use derived content path from entity (replaces duplicated logic)
      final contentDir = content.derivedContentPath;
      final existing = await _userDataRepository.getDownloadStatus(content.id);
      int fileSize = 0;
      if (content.imageUrls.isNotEmpty) {
        for (final imgPath in content.imageUrls) {
          final file = File(imgPath);
          if (await file.exists()) fileSize += await file.length();
        }
      }

      if (existing == null) {
        // NEW: ID not in database - create entry
        final status = DownloadStatus.completed(
          content.id,
          content.pageCount,
          contentDir ?? '',
          fileSize,
          title: content.title,
          sourceId: content.sourceId,
          coverUrl: content.coverUrl,
        );
        await _userDataRepository.saveDownloadStatus(status);
        syncedCount++;
        _logger.i('Synced new content: ${content.id}');
      } else if (existing.downloadPath != null) {
        // DUPLICATE/EXISTING: Check for updates or path fixes
        final existingDir = Directory(existing.downloadPath!);
        bool needsUpdate = false;
        var updatedStatus = existing;

        // Check 1: Path broken?
        if (!await existingDir.exists() && contentDir != null) {
          updatedStatus = updatedStatus.copyWith(downloadPath: contentDir);
          needsUpdate = true;
          _logger.i('Updated broken path for: ${content.id}');
        }

        // Check 2: Missing Metadata? (Title/SourceId/CoverUrl)
        if ((existing.title == null || existing.title!.isEmpty) &&
            content.title.isNotEmpty) {
          updatedStatus = updatedStatus.copyWith(title: content.title);
          needsUpdate = true;
        }

        if ((existing.sourceId == null ||
                existing.sourceId!.isEmpty ||
                existing.sourceId == 'nhentai') &&
            content.sourceId.isNotEmpty &&
            content.sourceId != 'nhentai') {
          updatedStatus = updatedStatus.copyWith(sourceId: content.sourceId);
          needsUpdate = true;
        }

        if ((existing.coverUrl == null || existing.coverUrl!.isEmpty) &&
            content.coverUrl.isNotEmpty) {
          updatedStatus = updatedStatus.copyWith(coverUrl: content.coverUrl);
          needsUpdate = true;
        }

        if (needsUpdate) {
          await _userDataRepository.saveDownloadStatus(updatedStatus);
          updatedCount++;
          _logger.i('Updated existing entry metadata/path for: ${content.id}');
        }
      }

      processed++;
      onProgress?.call(processed, total);

      // Small yield to not block UI/thread too much during heavy sync
      if (processed % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    _logger.i('Sync complete: $syncedCount new, $updatedCount updated');
    return {'synced': syncedCount, 'updated': updatedCount};
  }

  String _resolveBackupScanPath(String backupPath, String? sourceId) {
    if (sourceId == null || sourceId.trim().isEmpty) {
      return backupPath;
    }

    final normalizedBackupPath = path.normalize(backupPath);
    final backupBase = path.basename(normalizedBackupPath);
    if (backupBase.toLowerCase() == sourceId.toLowerCase()) {
      return normalizedBackupPath;
    }

    return path.join(backupPath, sourceId);
  }

  // [contentPath] - optional direct path to content directory (for backup items)
  // Returns true if deletion was successful (idempotent - returns true if either DB or filesystem deleted)
  Future<bool> deleteOfflineContent(String contentId,
      {String? contentPath}) async {
    try {
      _logger.i('Deleting offline content: $contentId');

      // Use provided path or try to find it
      String? pathToDelete = contentPath;
      pathToDelete ??= await getOfflineContentPath(contentId);

      // NEW: If path still not found, try filesystem scan as fallback
      if (pathToDelete == null) {
        _logger.i('Path not in DB, scanning filesystem for $contentId');
        pathToDelete = await _findContentInFilesystem(contentId);
      }

      bool filesystemDeleted = false;
      bool dbDeleted = false;

      // Delete filesystem if path found
      if (pathToDelete != null) {
        final contentDir = Directory(pathToDelete);
        if (await contentDir.exists()) {
          await contentDir.delete(recursive: true);
          _logger.i('Deleted content directory: $pathToDelete');
          filesystemDeleted = true;
        } else {
          _logger.w('Content directory does not exist: $pathToDelete');
        }
      }

      // Remove from metadata cache
      _metadataCache.remove(contentId);
      _metadataCacheTime.remove(contentId);

      // Clear offline IDs cache to force refresh
      _cachedOfflineIds = null;
      _offlineIdsCacheTime = null;

      // Delete from database - this is critical for sync
      try {
        await _userDataRepository.deleteDownloadStatus(contentId);
        _logger.i('Removed download status from DB for $contentId');
        dbDeleted = true;
      } catch (e) {
        _logger.e('CRITICAL: Failed to remove download status from DB: $e');
        // Even if filesystem was deleted, we need DB to be cleaned too
        // Log but continue - at least filesystem is cleaned
      }

      // Return true if at least one operation succeeded (idempotent behavior)
      final success = filesystemDeleted || dbDeleted;
      if (!success) {
        _logger.w(
            'Delete failed: content $contentId not found in filesystem or DB');
      }
      return success;
    } catch (e, stackTrace) {
      _logger.e('Error deleting offline content for $contentId',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  String _getLocalized(String key,
      {Map<String, dynamic>? args, String? fallback}) {
    try {
      return _localize?.call(key, args: args) ?? fallback ?? key;
    } catch (e) {
      _logger.w('Failed to get localized string for key: $key, error: $e');
      return fallback ?? key;
    }
  }
}
