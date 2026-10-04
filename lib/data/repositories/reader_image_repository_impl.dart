import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

import 'package:nhasixapp/core/utils/reader_image_repair_utils.dart';
import 'package:nhasixapp/core/services/local_image_preloader.dart';
import 'package:nhasixapp/core/services/request_deduplication_service.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/repositories/reader_image_repository.dart';

/// Signature for a streaming network image download that returns the canonical
/// local path on success, or null on failure/cancellation.
typedef ReaderImageNetworkDownload = Future<String?> Function({
  required String url,
  required String contentId,
  required int pageNumber,
  Map<String, String>? headers,
  CancelToken? cancelToken,
});

/// Signature for a legacy-cache lookup that returns a file path or null.
typedef ReaderImageLegacyLookup = Future<String?> Function(String url);

/// Signature for a local preloader-cache lookup returning a file path or null.
typedef ReaderImageLocalLookup = Future<String?> Function(
    String contentId, int pageNumber);

/// Default streaming download implementation — writes to the canonical cache
/// slot (same location [LocalImagePreloader.getLocalImagePath] scans), so the
/// very next pass reads from disk with zero network.
Future<String?> _defaultStreamingDownload({
  required String url,
  required String contentId,
  required int pageNumber,
  Map<String, String>? headers,
  CancelToken? cancelToken,
}) {
  return LocalImagePreloader.downloadAndCacheImageStreaming(
    url,
    contentId,
    pageNumber,
    headers: headers,
    cancelToken: cancelToken,
  );
}

/// Default legacy lookup — reads the old flutter_cache_manager cache (kept for
/// lazy migration so users do not lose their existing cache after an update).
Future<String?> _defaultLegacyLookup(String url) async {
  try {
    final file = await DefaultCacheManager().getSingleFile(url);
    if (file.existsSync()) return file.path;
  } catch (_) {}
  return null;
}

/// Default local lookup — scans the downloaded/preloader cache slots.
Future<String?> _defaultLocalLookup(String contentId, int pageNumber) {
  return LocalImagePreloader.getLocalImagePath(contentId, pageNumber);
}

/// Download-first resolver for reader page images.
///
/// Deterministic resolution order (mode-agnostic, no cross-session in-memory
/// routing state):
///   1. offline download / preloader cache
///   2. cache-manager legacy (lazily migrated to the canonical location)
///   3. network download, streamed straight to the canonical location
/// Plus a per-URL in-flight dedup gate shared across all subsystems.
class ReaderImageRepositoryImpl implements ReaderImageRepository {
  ReaderImageRepositoryImpl({
    required Logger logger,
    RequestDeduplicationService? dedup,
    ReaderImageNetworkDownload? networkDownload,
    ReaderImageLegacyLookup? legacyLookup,
    ReaderImageLocalLookup? localLookup,
  })  : _logger = logger,
        _dedup = dedup ?? RequestDeduplicationService(),
        _networkDownload = networkDownload ?? _defaultStreamingDownload,
        _legacyLookup = legacyLookup ?? _defaultLegacyLookup,
        _localLookup = localLookup ?? _defaultLocalLookup;

  final Logger _logger;
  final RequestDeduplicationService _dedup;
  final ReaderImageNetworkDownload _networkDownload;
  final ReaderImageLegacyLookup _legacyLookup;
  final ReaderImageLocalLookup _localLookup;

  @override
  Future<PageImageResult> resolvePage({
    required String url,
    required String contentId,
    required int pageNumber,
    String? sourceId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return FailedPage(reason: 'cancelled', originalUrl: url);
    }
    // 0) The URL is already a local file path — nothing to resolve.
    if (!url.startsWith('http') &&
        (url.startsWith('/') || url.startsWith('file://'))) {
      final localPath = url.replaceFirst('file://', '');
      final file = File(localPath);
      if (await _fileExists(file)) {
        return ReadyFromDisk(path: localPath);
      }
      return FailedPage(
          reason: 'local file not found: $localPath', originalUrl: url);
    }

    // 1) Offline download / preloader cache (header-sniffed: a corrupt slot
    // never returns ReadyFromDisk; it is evicted and resolution falls through
    // to legacy/network instead of looping on the same bytes).
    try {
      final localPath = await _localLookup(contentId, pageNumber);
      if (localPath != null && await _fileExists(File(localPath))) {
        if (await _hasInvalidImagePayload(localPath)) {
          _logger.w('[ReaderImage] corrupt disk hit, evicting $localPath');
          try {
            await File(localPath).delete();
          } catch (_) {}
          await LocalImagePreloader.evictCorruptPage(contentId, pageNumber);
        } else {
          _logger.i(
              '[ReaderImage] disk hit content=$contentId page=$pageNumber -> $localPath');
          return ReadyFromDisk(path: localPath);
        }
      }
    } catch (e) {
      _logger.w('[ReaderImage] preloader lookup failed: $e');
    }

    // 2) Legacy cache manager (lazy migration).
    try {
      final legacyPath = await _legacyLookup(url);
      if (legacyPath != null && await _fileExists(File(legacyPath))) {
        final migrated = await _migrateToCanonical(
          legacyPath: legacyPath,
          contentId: contentId,
          pageNumber: pageNumber,
        );
        _logger.i('[ReaderImage] legacy migrated -> ${migrated ?? legacyPath}');
        return ReadyFromDisk(path: migrated ?? legacyPath, legacy: true);
      }
    } catch (e) {
      _logger.w('[ReaderImage] legacy lookup failed: $e');
    }

    // 3) Network download (deduped + streamed to canonical).
    final requestKey = 'pageimg:$url';
    final deduped = _dedup.deduplicate<String?>(
      requestKey,
      () => _networkDownload(
        url: url,
        contentId: contentId,
        pageNumber: pageNumber,
        headers: headers,
        cancelToken: cancelToken,
      ),
      cancelToken: cancelToken,
    );

    try {
      final path = await deduped.timeout(const Duration(seconds: 45));
      if (path != null && await _fileExists(File(path))) {
        _logger.i('[ReaderImage] network OK -> $path');
        return ReadyFresh(path: path);
      }
      return FailedPage(
          reason: 'download produced no file for $url', originalUrl: url);
    } catch (e) {
      _logger.w('[ReaderImage] network fail $url: $e');
      return FailedPage(reason: e, originalUrl: url);
    }
  }

  /// Same header sniff the reader widget uses: native decode rejects files
  /// whose first bytes match no known image magic. Reads at most 64 bytes;
  /// unreadable files count as valid so lookup errors stay non-fatal.
  Future<bool> _hasInvalidImagePayload(String localPath) async {
    try {
      final file = File(localPath);
      final length = await file.length();
      if (length <= 0) return true;
      final raf = await file.open(mode: FileMode.read);
      try {
        final sample = await raf.read(length < 64 ? length : 64);
        return inferImageExtension(bytes: sample) == null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Copies a legacy cache file into the canonical cache slot so the next
  /// resolution is a disk hit. Non-fatal on any copy error.
  Future<String?> _migrateToCanonical({
    required String legacyPath,
    required String contentId,
    required int pageNumber,
  }) async {
    try {
      final imagesDir =
          Directory(await LocalImagePreloader.getImagesFolderPath(contentId));
      await imagesDir.create(recursive: true);
      final extension = p.extension(legacyPath);
      final target = '${imagesDir.path}/page_$pageNumber$extension';
      if (legacyPath != target && !await _fileExists(File(target))) {
        await File(legacyPath).copy(target);
      }
      return await _fileExists(File(target)) ? target : null;
    } catch (e) {
      _logger.w('[ReaderImage] lazy migration failed: $e');
      return null;
    }
  }
}

/// Async file-existence helper (keeps the resolver free of repeated try/catch).
Future<bool> _fileExists(File file) async {
  try {
    return await file.exists();
  } catch (_) {
    return false;
  }
}
