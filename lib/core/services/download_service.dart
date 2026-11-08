import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:path/path.dart' as path;
import 'package:logger/logger.dart';

import 'package:kuron_core/kuron_core.dart'; // NEW: For ContentSourceRegistry

import '../../domain/entities/entities.dart';
import '../../domain/value_objects/image_url.dart' as img;
import 'notification_service.dart';
import 'download_manager.dart';
import '../utils/permission_helper.dart';
import '../utils/storage_settings.dart';
import '../constants/app_constants.dart' as app_constants;
import '../utils/directory_utils.dart';

// Service untuk handle actual file download
class DownloadService {
  DownloadService({
    required this._httpClient,
    required this._notificationService,
    required this._sourceRegistry, // NEW
    Logger? logger,
  })  : _logger = logger ?? Logger();

  final Dio _httpClient;
  final NotificationService _notificationService;
  final ContentSourceRegistry _sourceRegistry; // NEW
  final Logger _logger;

  // Localization callback
  String Function(String key, {Map<String, dynamic>? args})? _localize;

  // Download content dengan progress tracking dan notification
  Future<DownloadResult> downloadContent({
    required Content content,
    required Function(DownloadProgress) onProgress,
    CancelToken? cancelToken,
    String imageQuality = 'high', // Default to high quality
    Duration? timeoutDuration, // Optional timeout override
    int? startPage, // NEW: Start page for range download (1-based)
    int? endPage, // NEW: End page for range download (1-based)
    Map<String, String>? cookies, // NEW: Optional cookies for authentication
    String? savePath, // NEW: Explicit save path
  }) async {
    try {
      _logger.i('Starting download for content: ${content.id}');

      // Check permissions
      await _checkPermissions();

      // Create download directory
      Directory downloadDir;
      if (savePath != null && savePath.isNotEmpty) {
        // Appending 'images' for consistency with _createDownloadDirectory structure
        downloadDir = Directory(
            path.join(savePath, app_constants.AppStorage.imagesSubfolder));
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
      } else {
        downloadDir =
            await _createDownloadDirectory(content.id, content.source);
      }

      // Calculate actual page range to download
      final actualStartPage = startPage ?? 1;
      final actualEndPage = endPage ?? content.imageUrls.length;

      // Validate range
      if (actualStartPage < 1 ||
          actualEndPage > content.imageUrls.length ||
          actualStartPage > actualEndPage) {
        throw ArgumentError(_getLocalized('invalidPageRange',
            args: {
              'start': actualStartPage,
              'end': actualEndPage,
              'total': content.imageUrls.length
            },
            fallback:
                'Invalid page range: $actualStartPage-$actualEndPage (total: ${content.imageUrls.length})'));
      }

      final isRangeDownload = startPage != null || endPage != null;
      final pagesToDownload = actualEndPage - actualStartPage + 1;

      _logger.i(
          'Download range: pages $actualStartPage-$actualEndPage ($pagesToDownload pages)${isRangeDownload ? ' [RANGE]' : ' [FULL]'}');

      // ✅ FIXED: Check existing downloaded files for proper resume
      final existingFiles = await _getExistingDownloadedFiles(downloadDir);
      final totalImages =
          isRangeDownload ? pagesToDownload : content.imageUrls.length;

      // ✅ FIX: Initialize to 0 to prevent double-counting
      // The loop will count both existing and newly downloaded files
      var downloadedCount = 0;

      _logger.i(
          'Found ${existingFiles.length} existing files, will verify in loop');

      // Show start notification with range info
      final rangeText =
          isRangeDownload ? ' (Pages $actualStartPage-$actualEndPage)' : '';
      await _notificationService.showDownloadStarted(
        contentId: content.id,
        title: '${content.title}$rangeText',
      );

      final downloadedFiles = <String>[];

      // Add existing files to the list if doing full download
      if (!isRangeDownload) {
        downloadedFiles.addAll(existingFiles);
      }

      // Download each image in the specified range
      for (int pageNum = actualStartPage; pageNum <= actualEndPage; pageNum++) {
        final i = pageNum - 1; // Convert to 0-based index for imageUrls array

        // Check for cancellation
        if (cancelToken?.isCancelled == true) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }

        // Check for pause state - wait until resumed or cancelled
        while (DownloadManager().isPaused(content.id)) {
          await Future.delayed(const Duration(seconds: 1));
          // Check if cancelled while paused
          if (DownloadManager().isCancelled(content.id) ||
              cancelToken?.isCancelled == true) {
            throw DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.cancel,
            );
          }
        }

        final imageUrl = content.imageUrls[i];

        // Apply image quality setting
        final optimizedImageUrl = _getOptimizedImageUrl(imageUrl, imageQuality);

        final fileName = 'page_${pageNum.toString().padLeft(3, '0')}.jpg';
        final filePath = path.join(downloadDir.path, fileName);

        // ✅ FIXED: Skip if file already exists (for proper resume)
        if (await File(filePath).exists()) {
          _logger.d('Skipping existing file: $fileName');

          // Add to downloaded files list if not already present
          if (!downloadedFiles.contains(filePath)) {
            downloadedFiles.add(filePath);
          }

          // ✅ FIX: Count existing files in the loop (no double-counting)
          downloadedCount++;
          final rawProgress = downloadedCount / totalImages;
          final progressPercentage = (rawProgress * 90).toInt(); // Cap at 90%

          onProgress(DownloadProgress(
            contentId: content.id,
            downloadedPages: progressPercentage,
            totalPages: 100,
            currentFileName: '$fileName (cached)',
          ));

          continue;
        }

        try {
          // Download single image with optimized URL
          await _downloadSingleImage(
            sourceId: content.sourceId, // NEW: Pass source ID
            imageUrl: optimizedImageUrl,
            filePath: filePath,
            cancelToken: cancelToken,
            timeoutDuration: timeoutDuration,
            cookies: cookies, // NEW: Pass cookies for authentication
          );

          downloadedFiles.add(filePath);
          downloadedCount++;

          // ✅ FIXED: Phase 1 - File Downloads (0-90%)
          // Progress is capped at 90% during file downloads
          // Reserve 90-100% for verification, metadata, and completion phases
          final rawProgress = downloadedCount / totalImages;
          final progressPercentage = (rawProgress * 90).toInt(); // Cap at 90%

          final progress = DownloadProgress(
            contentId: content.id,
            downloadedPages: progressPercentage,
            totalPages: 100,
            currentFileName: fileName,
          );

          onProgress(progress);

          _logger.d(
              'Download progress: $progressPercentage% ($downloadedCount/$totalImages files)');
        } catch (e, stackTrace) {
          _logger.e('Failed to download page $pageNum: $e and $stackTrace');
          // Continue with next image instead of failing completely,
          // but we will catch the discrepancy at the end.
          continue;
        }
      }

      // ✅ Phase 2: File Verification (90-95%)
      // CRITICAL: Strict file-by-file existence check
      _logger.i('Starting strict file verification phase...');

      // Emit -2 to signal verification start to DownloadBloc
      onProgress(DownloadProgress(
        contentId: content.id,
        downloadedPages: -2, // SIGNAL: Verification Start
        totalPages: 0, // 0% verification progress
        currentFileName: 'Verifying files...',
      ));

      // We expect (actualEndPage - actualStartPage + 1) images for this batch
      final expectedBatchCount = actualEndPage - actualStartPage + 1;

      // ✅ FIX: Explicit file-by-file verification
      // Don't just compare counts - verify EVERY page exists
      final missingPages = <int>[];
      for (int pageNum = actualStartPage; pageNum <= actualEndPage; pageNum++) {
        final fileName = 'page_${pageNum.toString().padLeft(3, '0')}.jpg';
        final filePath = path.join(downloadDir.path, fileName);

        if (!await File(filePath).exists()) {
          missingPages.add(pageNum);
          _logger.w('Missing file: $fileName (page $pageNum)');
        }

        // Report verification progress every 20 files or so to avoid spamming
        if (pageNum % 20 == 0) {
          final verifyProgress =
              ((pageNum - actualStartPage) / expectedBatchCount * 100).toInt();
          onProgress(DownloadProgress(
            contentId: content.id,
            downloadedPages: -2, // SIGNAL: Verification Progress
            totalPages: verifyProgress, // 0-100% verification
            currentFileName: 'Verifying files...',
          ));
        }
      }

      // If any pages are missing, throw explicit error with details
      if (missingPages.isNotEmpty) {
        final missingPagesStr = missingPages.join(', ');
        final errorMsg =
            'Download incomplete: ${missingPages.length} pages missing ($downloadedCount/$expectedBatchCount files downloaded). Missing pages: $missingPagesStr';

        _logger.e(errorMsg);
        throw Exception(errorMsg);
      }

      // Update verification to 100%
      onProgress(DownloadProgress(
        contentId: content.id,
        downloadedPages: -2,
        totalPages: 100, // 100% verification
        currentFileName: 'Verifying files...',
      ));

      _logger.i(
          'File verification complete: All $expectedBatchCount files verified (pages $actualStartPage-$actualEndPage)');

      // ✅ Phase 3: Metadata Generation (95-98%)
      _logger.i('Starting metadata generation phase...');
      // No specific notification for metadata, just log it

      // Save metadata with range information
      await _saveDownloadMetadata(content, downloadDir, downloadedFiles,
          actualStartPage, actualEndPage);

      _logger.i('Metadata generation complete');

      // ✅ Phase 4: Completion (100%)
      // Emit normal completion event
      onProgress(DownloadProgress(
        contentId: content.id,
        downloadedPages: 100,
        totalPages: 100,
        currentFileName: 'Completed',
      ));

      // NOTE: Notification is handled by DownloadBloc._onStart() to avoid duplication

      _logger.i(
          'Download completed for content: ${content.id}${isRangeDownload ? " (range: $actualStartPage-$actualEndPage)" : ""}');

      return DownloadResult(
        success: true,
        downloadPath: downloadDir.parent.path,
        downloadedFiles: downloadedFiles,
        totalFiles: downloadedFiles.length,
      );
    } catch (e) {
      _logger.e('Download failed for content: ${content.id}', error: e);

      // Show error notification
      await _notificationService.showDownloadError(
        contentId: content.id,
        title: content.title,
        error: e.toString(),
      );

      return DownloadResult(
        success: false,
        error: e.toString(),
        downloadPath: null,
        downloadedFiles: [],
        totalFiles: 0,
      );
    }
  }

  // Download single image file
  Future<void> _downloadSingleImage({
    required String sourceId, // NEW: Source ID for header lookup
    required String imageUrl,
    required String filePath,
    CancelToken? cancelToken,
    Duration? timeoutDuration,
    Map<String, String>? cookies, // NEW: Optional cookies
  }) async {
    // Create dio instance with custom timeout if provided
    final dio = timeoutDuration != null
        ? Dio(BaseOptions(
            connectTimeout: timeoutDuration,
            receiveTimeout: timeoutDuration,
            sendTimeout: timeoutDuration,
          ))
        : _httpClient;
    if (timeoutDuration != null) {
      dio.httpClientAdapter = NativeAdapter();
    }

    // Build headers with cookies if provided
    final headers = _getHeadersForSource(sourceId, imageUrl, cookies: cookies);

    final response = await dio.get<List<int>>(
      imageUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers, // Use headers with cookies
      ),
      cancelToken: cancelToken,
    );

    if (response.data != null) {
      final file = File(filePath);
      await file.writeAsBytes(response.data!);
    } else {
      throw Exception(_getLocalized('noDataReceived',
          args: {'url': imageUrl},
          fallback: 'No data received for image: $imageUrl'));
    }
  }

  // Get headers for source based on source ID
  ///
  // NEW: Uses ContentSource.getImageDownloadHeaders() instead of hardcoded logic
  /// Fetch remote image bytes with source headers (referer/cookie/UA).
  /// Used by reader AI pipeline (page capture) — no disk write.
  Future<Uint8List?> fetchRemoteImageBytes(
    String sourceId,
    String imageUrl, {
    Duration sendTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 60),
  }) async {
    try {
      final headers = _getHeadersForSource(sourceId, imageUrl);
      final response = await _httpClient.get<List<int>>(
        imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
      return response.data == null ? null : Uint8List.fromList(response.data!);
    } catch (e) {
      _logger.w('Failed to fetch remote image bytes: $e');
      return null;
    }
  }

  Map<String, dynamic> _getHeadersForSource(
    String sourceId,
    String imageUrl, {
    Map<String, String>? cookies,
  }) {
    try {
      // Get source from registry
      final source = _sourceRegistry.getSource(sourceId);

      // Null check - should not happen but fallback if it does
      if (source == null) {
        throw Exception('Source $sourceId not found in registry');
      }

      // Use source's method to get headers
      final headers = source.getImageDownloadHeaders(
        imageUrl: imageUrl,
        cookies: cookies,
      );

      _logger
          .d('Got headers from source $sourceId: ${headers.keys.join(", ")}');
      return headers;
    } catch (e) {
      // Fallback if source not found
      _logger.w('Failed to get headers from source $sourceId: $e');
      return {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };
    }
  }

  // ✅ NEW: Get existing downloaded files for proper resume
  Future<List<String>> _getExistingDownloadedFiles(
      Directory downloadDir) async {
    try {
      if (!await downloadDir.exists()) {
        return [];
      }

      final files = await downloadDir
          .list()
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.jpg') ||
                  entity.path.endsWith('.jpeg') ||
                  entity.path.endsWith('.png') ||
                  entity.path.endsWith('.webp') ||
                  entity.path.endsWith('.avif')))
          .cast<File>()
          .toList();

      // Sort files by name to maintain page order
      files.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      final filePaths = files.map((f) => f.path).toList();
      _logger.d('Found ${filePaths.length} existing downloaded files');

      return filePaths;
    } catch (e) {
      _logger.w('Error checking existing files: $e');
      return [];
    }
  }

  // Create download directory structure
  Future<Directory> _createDownloadDirectory(
      String contentId, String sourceId) async {
    // Use smart Downloads directory detection
    final downloadsPath = await _getDownloadsDirectory();
    final nhasixDir = Directory(
        path.join(downloadsPath, app_constants.AppStorage.backupFolderName));

    // Use source-based path
    final sourceDir = Directory(path.join(nhasixDir.path, sourceId));

    final contentDir = Directory(path.join(sourceDir.path, contentId));
    final imagesDir = Directory(
        path.join(contentDir.path, app_constants.AppStorage.imagesSubfolder));

    // Create directories if they don't exist
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 🔒 PRIVACY: Create .nomedia file
    await _createNoMediaFile(nhasixDir);

    return imagesDir;
  }

  // Create .nomedia file to prevent media scanning
  // This hides images from Android Gallery/Photos apps for privacy
  Future<void> _createNoMediaFile(Directory directory) async {
    try {
      final nomediaFile = File(path.join(directory.path, '.nomedia'));

      if (!await nomediaFile.exists()) {
        await nomediaFile.writeAsString(
            '# This file prevents Android Media Scanner from indexing this folder\n'
            '# Images in this folder and subfolders will not appear in Gallery apps\n'
            '# Created by Kuron for privacy protection\n');
        _logger.i(_getLocalized('createdNoMediaFile',
            args: {'path': nomediaFile.path},
            fallback:
                'Created .nomedia file for privacy: ${nomediaFile.path}'));
      }
    } catch (e) {
      _logger.w('Failed to create .nomedia file: $e');
      // Don't throw error - this is not critical for download functionality
    }
  }

  // 🔒 UTILITY: Add .nomedia file to existing downloads for privacy protection
  // Call this to retrofit existing downloads that don't have .nomedia file
  Future<void> ensurePrivacyProtection() async {
    try {
      final downloadsPath = await _getDownloadsDirectory();
      final nhasixDir = Directory(
          path.join(downloadsPath, app_constants.AppStorage.backupFolderName));

      if (await nhasixDir.exists()) {
        await _createNoMediaFile(nhasixDir);
        _logger.i(_getLocalized('privacyProtectionEnsured',
            fallback: 'Privacy protection ensured for existing downloads'));
      }
    } catch (e) {
      _logger.e('Error ensuring privacy protection: $e');
    }
  }

  // Smart Downloads directory detection
  // Tries multiple possible Downloads folder names and locations
  Future<String> _getDownloadsDirectory() async {
    try {
      // 0. Check for custom storage root first
      if (await StorageSettings.hasCustomRoot()) {
        final customPath = await StorageSettings.getCustomRootPath();
        if (customPath != null && customPath.isNotEmpty) {
          return customPath;
        }
      }

      // Fallback to DirectoryUtils
      return await DirectoryUtils.getDownloadsDirectory();
    } catch (e) {
      _logger.e('Error detecting Downloads directory: $e');
      rethrow;
    }
  }

  // Save download metadata
  Future<void> _saveDownloadMetadata(
    Content content,
    Directory downloadDir,
    List<String> downloadedFiles,
    int startPage,
    int endPage,
  ) async {
    final isRangeDownload = startPage > 1 || endPage < content.pageCount;
    final metadata = {
      'schemaVersion': '2.1', // V2.1 Schema (simplified, added URL)
      'source': content.source,
      'content_id': content.id,
      'title': content.title,
      'url': content.url, // NEW: For reader navigation
      'download_date': DateTime.now().toIso8601String(),
      'total_pages': content.pageCount,
      'downloaded_files': downloadedFiles.length,
      'files': downloadedFiles.map((f) => path.basename(f)).toList(),
      'language': content.language,
      'cover_url': content.coverUrl,
      // Range download information
      'is_range_download': isRangeDownload,
      'start_page': startPage,
      'end_page': endPage,
      'pages_downloaded': endPage - startPage + 1,
    };

    final metadataFile = File(path.join(
        downloadDir.parent.path, app_constants.AppStorage.metadataFileName));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  // Check and request necessary permissions
  Future<void> _checkPermissions() async {
    final hasPermission = await PermissionHelper.hasStoragePermission();
    if (!hasPermission) {
      throw Exception(_getLocalized('storagePermissionRequired',
          fallback:
              'Storage permission is required for downloads. Please grant storage permission in app settings.'));
    }
  }

  // Get download directory path for content
  Future<String?> getDownloadPath(String contentId) async {
    try {
      final downloadsPath = await _getDownloadsDirectory();
      final nhasixDir = Directory(
          path.join(downloadsPath, app_constants.AppStorage.backupFolderName));

      if (!await nhasixDir.exists()) return null;

      // 1. Check legacy path first (nhasix/{id})
      final legacyDir = Directory(path.join(nhasixDir.path, contentId));
      if (await legacyDir.exists()) {
        return legacyDir.path;
      }

      // 2. Scan all subdirectories (sources) for the contentId
      try {
        await for (final entity in nhasixDir.list()) {
          if (entity is Directory) {
            // Check if this source directory contains the contentId
            final contentDir = Directory(path.join(entity.path, contentId));
            if (await contentDir.exists()) {
              return contentDir.path;
            }
          }
        }
      } catch (e) {
        _logger.w('Error scanning source directories: $e');
      }

      return null;
    } catch (e) {
      _logger.e('Error getting download path: $e');
      return null;
    }
  }

  // Delete downloaded by content id tapi hanya delete isi dari folder contentid
  Future<void> deleteDownloadedContent(String contentId) async {
    try {
      final downloadPath = await getDownloadPath(contentId);
      if (downloadPath != null) {
        // ini akan muncul path apa?
        final contentDir = Directory(downloadPath);
        if (await contentDir.exists()) {
          await contentDir.delete(recursive: true);
        }
      }
    } catch (e) {
      _logger.e('Error deleting downloaded content: $e');
    }
  }

  // Check if content is already downloaded
  Future<bool> isContentDownloaded(String contentId) async {
    final downloadPath = await getDownloadPath(contentId);
    if (downloadPath == null) return false;

    final imagesDir = Directory(
        path.join(downloadPath, app_constants.AppStorage.imagesSubfolder));
    if (!await imagesDir.exists()) return false;

    final files = await imagesDir.list().toList();
    return files.isNotEmpty;
  }

  // Get downloaded files for content
  Future<List<String>> getDownloadedFiles(String contentId) async {
    try {
      final downloadPath = await getDownloadPath(contentId);
      if (downloadPath == null) return [];

      final imagesDir = Directory(
          path.join(downloadPath, app_constants.AppStorage.imagesSubfolder));
      if (!await imagesDir.exists()) return [];

      final files = await imagesDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      // Sort files by name to maintain page order
      files.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      return files.map((f) => f.path).toList();
    } catch (e) {
      _logger.e('Error getting downloaded files: $e');
      return [];
    }
  }

  // Set localization callback for getting localized strings
  void setLocalizationCallback(
      String Function(String key, {Map<String, dynamic>? args}) localize) {
    _localize = localize;
    _logger.i('DownloadService: Localization callback set');
  }

  // Get localized string with fallback
  String _getLocalized(String key,
      {Map<String, dynamic>? args, String? fallback}) {
    try {
      return _localize?.call(key, args: args) ?? fallback ?? key;
    } catch (e) {
      _logger.w('Failed to get localized string for key: $key, error: $e');
      return fallback ?? key;
    }
  }

  // Get optimized image URL based on quality setting
  String _getOptimizedImageUrl(String originalUrl, String imageQuality) {
    // Convert string quality to ImageQuality enum
    img.ImageQuality quality;
    switch (imageQuality.toLowerCase()) {
      case 'low':
        quality = img.ImageQuality.low;
        break;
      case 'medium':
        quality = img.ImageQuality.medium;
        break;
      case 'high':
        quality = img.ImageQuality.high;
        break;
      case 'original':
        quality = img.ImageQuality.original;
        break;
      default:
        quality = img.ImageQuality.high; // Default to high quality
    }

    // Create ImageUrl object and get optimized version
    final imageUrl = img.ImageUrl(originalUrl);
    final optimizedUrl = imageUrl.getOptimized(quality);

    return optimizedUrl.value;
  }

  // Count actual downloaded files in the folder
  Future<int> countDownloadedFiles(String contentId) async {
    try {
      final downloadPath = await getDownloadPath(contentId);
      if (downloadPath == null) return 0;

      final imagesDir = Directory(path.join(downloadPath, 'images'));

      _logger.d('Checking directories for content $contentId:');
      _logger.d('Content dir: $downloadPath');
      _logger.d(
          'Images dir: ${imagesDir.path} (exists: ${await imagesDir.exists()})');

      // Use the same logic as _createDownloadDirectory - images dir is primary
      if (!await imagesDir.exists()) {
        _logger.w('Images directory does not exist: ${imagesDir.path}');
        return 0;
      }

      // List all files in the directory for debugging
      final allEntities = await imagesDir.list().toList();
      _logger.d('All entities in ${imagesDir.path}:');
      for (final entity in allEntities) {
        _logger.d('  - ${entity.path} (is File: ${entity is File})');
      }

      final files = await imagesDir
          .list()
          .where((entity) =>
              entity is File &&
              (entity.path.endsWith('.jpg') ||
                  entity.path.endsWith('.jpeg') ||
                  entity.path.endsWith('.png') ||
                  entity.path.endsWith('.webp') ||
                  entity.path.endsWith('.avif')))
          .length;

      _logger.i(
          'Found $files downloaded image files for content $contentId in ${imagesDir.path}');
      return files;
    } catch (e) {
      _logger.e('Error counting downloaded files for $contentId: $e');
      return 0;
    }
  }

  // Verify and update download status based on actual files
  Future<Map<String, dynamic>> verifyDownloadStatus(String contentId) async {
    try {
      final actualCount = await countDownloadedFiles(contentId);
      final downloadPath = await getDownloadPath(contentId);

      // If path not found but count > 0 (should not happen normally) or just return empty
      if (downloadPath == null) {
        return {
          'actualCount': actualCount,
          'expectedCount': null,
          'isRangeDownload': false,
        };
      }

      final metadataPath = path.join(downloadPath, 'metadata.json');

      _logger.d('Verifying download status for $contentId:');
      _logger.d('Actual file count: $actualCount');
      _logger.d('Metadata path: $metadataPath');

      if (await File(metadataPath).exists()) {
        final metadataContent = await File(metadataPath).readAsString();
        final metadata = json.decode(metadataContent) as Map<String, dynamic>;

        _logger.d('Metadata content: $metadata');

        // Get expected count based on range or total
        // Use snake_case keys as saved in _saveDownloadMetadata
        final isRangeDownload = metadata['is_range_download'] == true;
        final int expectedCount;

        if (isRangeDownload) {
          final startPage = metadata['start_page'] ?? 1;
          final endPage = metadata['end_page'] ?? metadata['total_pages'];
          expectedCount = endPage - startPage + 1;
          _logger.d(
              'Range download: $startPage-$endPage, expected: $expectedCount');
        } else {
          // Use snake_case key as saved in metadata
          final totalPagesFromMeta = metadata['total_pages'] ?? 0;
          expectedCount = totalPagesFromMeta;
          _logger.d(
              'Full download: total_pages=${metadata['total_pages']}, expected: $expectedCount');
        }

        final result = {
          'actualCount': actualCount,
          'expectedCount': expectedCount,
          'isRangeDownload': isRangeDownload,
          'rangeStart': metadata['start_page'],
          'rangeEnd': metadata['end_page'],
          'totalPages': metadata['total_pages'],
        };

        _logger.d('Verification result: $result');
        return result;
      }

      _logger.w('Metadata file not found, falling back to database values');
      // For downloads without metadata, return null to indicate fallback needed
      return {
        'actualCount': actualCount,
        'expectedCount': null, // Indicates to fall back to database values
        'isRangeDownload': false,
      };
    } catch (e) {
      _logger.e('Error verifying download status for $contentId: $e');
      return {
        'actualCount': 0,
        'expectedCount': null, // Indicates to fall back to database values
        'isRangeDownload': false,
      };
    }
  }
}

// Result of download operation
class DownloadResult {
  const DownloadResult({
    required this.success,
    required this.downloadedFiles,
    required this.totalFiles,
    this.downloadPath,
    this.error,
  });

  final bool success;
  final String? downloadPath;
  final List<String> downloadedFiles;
  final int totalFiles;
  final String? error;
}

// Progress information for download
class DownloadProgress {
  const DownloadProgress({
    required this.contentId,
    required this.downloadedPages,
    required this.totalPages,
    this.currentFileName,
    this.speed,
    this.estimatedTimeRemaining,
  });

  final String contentId;
  final int downloadedPages;
  final int totalPages;
  final String? currentFileName;
  final double? speed; // bytes per second
  final Duration? estimatedTimeRemaining;

  double get progressPercentage =>
      totalPages > 0 ? (downloadedPages / totalPages * 100) : 0;

  bool get isCompleted => downloadedPages >= totalPages;
}
