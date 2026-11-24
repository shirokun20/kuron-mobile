import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:dio/dio.dart';

// Internal class for memory cache data
class _CachedImageData {
  final File file;
  final DateTime cachedAt;
  final int size;

  _CachedImageData({
    required this.file,
    required this.cachedAt,
    required this.size,
  });
}

// Service for caching images to improve loading performance and reduce network usage
// Provides memory and disk caching with TTL (Time To Live) support
class ImageCacheService {
  static const String _cacheMetadataKey = 'image_cache_metadata';
  static const String _cacheVersion = '1.0.0';
  static const Duration _defaultCacheDuration = Duration(hours: 24); // 24 hours
  static const int _maxCacheSizeMB = 100; // 100MB max cache size
  static const int _maxMemoryEntries = 100; // max entries in memory cache

  final Logger _logger = getIt<Logger>();

  // In-memory cache for fast access with LRU eviction
  final Map<String, _CachedImageData> _memoryCache = {};

  // Global gate for static animated previews: full GIF/WebP decode inflates
  // ALL frames (hundreds of MB transient per file). Duplicate widgets + fast
  // scrolling used to spawn one isolate per request. Same-source requests
  // share one future; at most 2 decodes run concurrently, the rest queue.
  static const int _maxConcurrentStaticDecodes = 2;
  static int _activeStaticDecodes = 0;
  static final List<Completer<void>> _staticDecodeWaiters = [];
  static final Map<String, Future<File?>> _staticDecodeInFlight = {};

  // Fallback client for direct network fetches when DI Dio is unavailable
  // (e.g. isolated tests). Production reuses `getIt<Dio>()` (Cronet + native DNS).
  static Dio? _fallbackFetchClient;

  static Dio _resolveFetchClient() {
    if (getIt.isRegistered<Dio>()) {
      return getIt<Dio>();
    }
    return _fallbackFetchClient ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        maxRedirects: 5,
        responseType: ResponseType.bytes,
      ),
    );
  }

  /// Fetches raw bytes for a remote image URL (throws on failure).
  static Future<Uint8List> _fetchNetworkBytes(
    String url, [
    Map<String, String>? headers,
  ]) async {
    final response = await _resolveFetchClient().get<List<int>>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('Empty response body for $url');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }
  // Get cached image data by URL
  // If [isStaticGif] is true, it looks for the processed static version of the GIF
  Future<File?> getCachedImage(String imageUrl,
      {bool isStaticGif = false}) async {
    try {
      final cacheKey = _generateCacheKey(imageUrl, isStaticGif: isStaticGif);

      // Check memory cache first
      final memoryData = _memoryCache[cacheKey];
      if (memoryData != null && !_isExpired(memoryData.cachedAt)) {
        _logger.d('Image cache hit (memory): $imageUrl (static: $isStaticGif)');
        return memoryData.file;
      }

      // Check disk cache
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('${cacheDir.path}/$cacheKey');

      if (await cacheFile.exists()) {
        // Check if cache is expired
        final metadata = await _getCacheMetadata();
        final cacheEntry = metadata[cacheKey];

        if (cacheEntry != null && !_isExpired(cacheEntry['cachedAt'])) {
          // Load into memory cache for faster future access
          _memoryCache[cacheKey] = _CachedImageData(
            file: cacheFile,
            cachedAt: DateTime.parse(cacheEntry['cachedAt']),
            size: await cacheFile.length(),
          );
          _evictMemoryCacheIfNeeded();

          _logger.d('Image cache hit (disk): $imageUrl (static: $isStaticGif)');
          return cacheFile;
        } else {
          // Remove expired cache
          await cacheFile.delete();
          await _removeFromMetadata(cacheKey);
          _logger.d('Removed expired image cache: $imageUrl');
        }
      }

      _logger.d('Image cache miss: $imageUrl (static: $isStaticGif)');
      return null;
    } catch (e) {
      _logger.w('Error getting cached image for $imageUrl: $e');
      return null;
    }
  }

  // Get or process a static image from a GIF URL
  // Returns a cached File of the static JPG
  Future<File?> getOrProcessStaticGif(
      String url, Map<String, String>? headers) async {
    return getOrProcessStaticImage(url, headers: headers);
  }

  // Get or process a static first-frame preview for a remote or local image.
  ///
  // This is primarily used for thumbnail surfaces where animated payloads
  // should stay lightweight and deterministic.
  Future<File?> getOrProcessStaticImage(
    String source, {
    Map<String, String>? headers,
    bool isLocalFile = false,
  }) {
    final key = '$source|$headers|$isLocalFile';
    return _staticDecodeInFlight.putIfAbsent(key, () async {
      await _acquireStaticDecodeSlot();
      try {
        return await _processStaticImage(source,
            headers: headers, isLocalFile: isLocalFile);
      } finally {
        _releaseStaticDecodeSlot();
        _staticDecodeInFlight.remove(key);
      }
    });
  }

  static Future<void> _acquireStaticDecodeSlot() async {
    while (_activeStaticDecodes >= _maxConcurrentStaticDecodes) {
      final waiter = Completer<void>();
      _staticDecodeWaiters.add(waiter);
      await waiter.future;
    }
    _activeStaticDecodes++;
  }

  static void _releaseStaticDecodeSlot() {
    _activeStaticDecodes--;
    if (_staticDecodeWaiters.isNotEmpty) {
      _staticDecodeWaiters.removeAt(0).complete();
    }
  }

  Future<File?> _processStaticImage(
    String source, {
    Map<String, String>? headers,
    bool isLocalFile = false,
  }) async {
    try {
      // 1. Check if we already have the static version cached
      final cachedFile = await getCachedImage(source, isStaticGif: true);
      if (cachedFile != null) return cachedFile;

      // 2. Read the original bytes from local disk or network.
      // (Previously via flutter_cache_manager; retired in favour of a
      // direct fetch — the static preview is cached in our own store below.)
      final Uint8List bytes;
      if (isLocalFile) {
        bytes = await File(source).readAsBytes();
      } else {
        bytes = await _fetchNetworkBytes(source, headers);
      }

      // 3. Convert to a static JPG in isolate
      final staticBytes = await compute(_decodeImageToStaticImage, bytes);
      if (staticBytes == null) return null;

      // 4. Cache the result
      await cacheImage(source, staticBytes, isStaticGif: true);

      // 5. Return the newly cached file
      return await getCachedImage(source, isStaticGif: true);
    } catch (e) {
      _logger.e('Error processing static image preview: $e');
      return null;
    }
  }

  // Static function for isolate processing
  static Future<Uint8List?> _decodeImageToStaticImage(Uint8List bytes) async {
    try {
      // Decode the image (GIF/WebP/AVIF/etc.) and keep only the first frame.
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Encode as optimized JPEG (static image)
      // This strips animation frames and returns just the first frame
      return Uint8List.fromList(img.encodeJpg(image, quality: 85));
    } catch (e) {
      getIt<Logger>().w('Error decoding static image preview in isolate: $e');
      return null;
    }
  }

  // Cache image data
  Future<void> cacheImage(String imageUrl, List<int> imageData,
      {bool isStaticGif = false}) async {
    try {
      final cacheKey = _generateCacheKey(imageUrl, isStaticGif: isStaticGif);
      final cacheDir = await _getCacheDirectory();
      final cacheFile = File('${cacheDir.path}/$cacheKey');

      // Write image data to file
      await cacheFile.writeAsBytes(imageData);

      final cachedAt = DateTime.now();
      final fileSize = imageData.length;

      // Add to memory cache
      _memoryCache[cacheKey] = _CachedImageData(
        file: cacheFile,
        cachedAt: cachedAt,
        size: fileSize,
      );
      _evictMemoryCacheIfNeeded();

      // Update metadata
      await _addToMetadata(cacheKey, cachedAt, fileSize);

      // Clean up old entries if cache size exceeds limit
      await _cleanupIfNeeded();

      _logger.d('Cached image: $imageUrl (${_formatBytes(fileSize)})');
    } catch (e) {
      _logger.w('Error caching image for $imageUrl: $e');
    }
  }

  // Check if image is cached
  Future<bool> isImageCached(String imageUrl) async {
    final cachedFile = await getCachedImage(imageUrl);
    return cachedFile != null;
  }

  // Clear cache for specific content ID
  Future<void> clearContentCache(String contentId) async {
    try {
      final metadata = await _getCacheMetadata();
      final keysToRemove = <String>[];

      // Find all cache entries for this content
      metadata.forEach((key, value) {
        final url = value['url'] as String?;
        if (url != null && url.contains('/galleries/$contentId/')) {
          keysToRemove.add(key);
        }
      });

      // Remove files and metadata
      final cacheDir = await _getCacheDirectory();
      for (final key in keysToRemove) {
        final cacheFile = File('${cacheDir.path}/$key');
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        await _removeFromMetadata(key);
        _memoryCache.remove(key);
      }

      _logger.i(
          'Cleared image cache for content: $contentId (${keysToRemove.length} files)');
    } catch (e) {
      _logger.w('Error clearing content cache for $contentId: $e');
    }
  }

  // Clear all cached images
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();

      // Delete all cache files
      final files = cacheDir.listSync();
      for (final file in files) {
        if (file is File) {
          await file.delete();
        }
      }

      // Clear metadata and memory cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheMetadataKey);
      _memoryCache.clear();

      _logger.i('Cleared all image cache');
    } catch (e) {
      _logger.w('Error clearing all image cache: $e');
    }
  }

  // Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final metadata = await _getCacheMetadata();
      int totalSize = 0;
      final int totalFiles = metadata.length;

      for (final entry in metadata.values) {
        totalSize += entry['size'] as int? ?? 0;
      }

      return {
        'totalFiles': totalFiles,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).round(),
        'memoryCacheSize': _memoryCache.length,
        'cacheVersion': _cacheVersion,
      };
    } catch (e) {
      _logger.w('Error getting cache stats: $e');
      return {'error': e.toString()};
    }
  }

  // Generate cache key from URL
  String _generateCacheKey(String url, {bool isStaticGif = false}) {
    // Use SHA-256 hash of URL as cache key
    final bytes = utf8.encode(url);
    final hash = sha256.convert(bytes);
    return isStaticGif ? '${hash}_static' : hash.toString();
  }

  // Get cache directory
  Future<Directory> _getCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final imageCacheDir = Directory('${cacheDir.path}/images');

    if (!await imageCacheDir.exists()) {
      await imageCacheDir.create(recursive: true);
    }

    return imageCacheDir;
  }

  // Check if cache entry is expired
  bool _isExpired(dynamic cachedAt) {
    if (cachedAt is String) {
      final date = DateTime.parse(cachedAt);
      return DateTime.now().difference(date) > _defaultCacheDuration;
    } else if (cachedAt is DateTime) {
      return DateTime.now().difference(cachedAt) > _defaultCacheDuration;
    }
    return true; // Consider expired if format is unknown
  }

  // Get cache metadata from SharedPreferences
  Future<Map<String, dynamic>> _getCacheMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final metadataJson = prefs.getString(_cacheMetadataKey);

    if (metadataJson == null) return {};

    try {
      return Map<String, dynamic>.from(json.decode(metadataJson));
    } catch (e) {
      _logger.w('Error parsing cache metadata: $e');
      return {};
    }
  }

  // Add entry to metadata
  Future<void> _addToMetadata(
      String cacheKey, DateTime cachedAt, int size) async {
    final metadata = await _getCacheMetadata();
    metadata[cacheKey] = {
      'cachedAt': cachedAt.toIso8601String(),
      'size': size,
      'url': '', // Could be stored for debugging but increases metadata size
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheMetadataKey, json.encode(metadata));
  }

  // Remove entry from metadata
  Future<void> _removeFromMetadata(String cacheKey) async {
    final metadata = await _getCacheMetadata();
    metadata.remove(cacheKey);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheMetadataKey, json.encode(metadata));
  }

  // Clean up old entries if cache size exceeds limit
  Future<void> _cleanupIfNeeded() async {
    try {
      final metadata = await _getCacheMetadata();
      int totalSize = 0;

      // Calculate total cache size
      for (final entry in metadata.values) {
        totalSize += entry['size'] as int? ?? 0;
      }

      const maxSizeBytes = _maxCacheSizeMB * 1024 * 1024;

      if (totalSize > maxSizeBytes) {
        _logger.i(
            'Cache size exceeded limit (${_formatBytes(totalSize)}), cleaning up...');

        // Sort by cached date (oldest first)
        final sortedEntries = metadata.entries.toList()
          ..sort((a, b) {
            final dateA = DateTime.parse(a.value['cachedAt']);
            final dateB = DateTime.parse(b.value['cachedAt']);
            return dateA.compareTo(dateB);
          });

        // Remove oldest entries until we're under the limit
        final cacheDir = await _getCacheDirectory();
        int removedSize = 0;

        for (final entry in sortedEntries) {
          if (totalSize - removedSize <= maxSizeBytes * 0.8) {
            break; // Keep 80% of limit
          }

          final cacheKey = entry.key;
          final cacheFile = File('${cacheDir.path}/$cacheKey');

          if (await cacheFile.exists()) {
            await cacheFile.delete();
            removedSize += entry.value['size'] as int? ?? 0;
          }

          await _removeFromMetadata(cacheKey);
          _memoryCache.remove(cacheKey);
        }

        _logger.i('Cleaned up ${_formatBytes(removedSize)} from image cache');
      }
    } catch (e) {
      _logger.w('Error during cache cleanup: $e');
    }
  }

  // Evict oldest entries from memory cache when over limit
  void _evictMemoryCacheIfNeeded() {
    while (_memoryCache.length > _maxMemoryEntries) {
      final oldestKey = _memoryCache.keys.first;
      _memoryCache.remove(oldestKey);
      _logger.d('Evicted oldest memory cache entry: $oldestKey');
    }
  }

  // Format bytes to human readable format
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
