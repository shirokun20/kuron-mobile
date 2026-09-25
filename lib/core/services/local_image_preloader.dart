import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../utils/storage_settings.dart';

// Enhanced Local Image Preloader Service
///
// Provides progressive image loading with priority:
// 1. Downloaded content (`nhasix/[id]/images/`)
// 2. Local cache
// 3. Network fallback
///
// Supports metadata.json validation for downloaded content
class LocalImagePreloader {
  static const String _baseLocalPath = 'nhasix';
  static const String _cacheSubPath = 'cache';
  static const Duration _cacheExpiryDuration =
      Duration(hours: 6); // Cache expires in 6 hours
  static final Logger _logger = getIt<Logger>();
  static bool _didLogDownloadDirectorySelection = false;

  // Get all possible base paths where images might be stored
  // Priority: External Download -> Internal Cache (with expiry) -> Internal App Documents
  static Future<List<String>> _getPossibleBasePaths() async {
    final List<String> basePaths = [];

    try {
      // Priority 1: External storage Download folder (permanently downloaded files)
      final downloadPaths = await _getDownloadDirectories();
      for (final downloadPath in downloadPaths) {
        final downloadDir = Directory(path.join(downloadPath, _baseLocalPath));
        if (await downloadDir.exists()) {
          basePaths.add(path.join(downloadPath, _baseLocalPath));
          _logger.d(
              '🐛 Found external storage: ${path.join(downloadPath, _baseLocalPath)}');
        }
      }

      // Priority 2: Internal cache directory (temporary files with expiry)
      final cacheDir = await _getInternalCacheDirectory();
      if (cacheDir != null) {
        basePaths.add(cacheDir);
        _logger.d('🐛 Added internal cache: $cacheDir');

        // Trigger cache cleanup in background
        await _cleanupExpiredCache();
      }

      // Priority 3: Internal app documents directory (fallback storage)
      final appDir = await getApplicationDocumentsDirectory();
      final internalPath = path.join(appDir.path, _baseLocalPath);
      basePaths.add(internalPath);
      _logger.d('🐛 Added internal storage: $internalPath');
    } catch (e) {
      _logger.e('Error getting possible base paths: $e');
      // Fallback to internal storage only
      final appDir = await getApplicationDocumentsDirectory();
      basePaths.add(path.join(appDir.path, _baseLocalPath));
    }

    return basePaths;
  }

  // Get Downloads directories using smart detection similar to download_service.dart
  // Reference implementation from download_service.dart _getDownloadsDirectory()
  static Future<List<String>> _getDownloadDirectories() async {
    final List<String> downloadPaths = [];
    final bool shouldLog = !_didLogDownloadDirectorySelection;

    try {
      // Prefer app-managed custom storage root when available.
      final customRoot = await StorageSettings.getCustomRootPath();
      if (customRoot != null && customRoot.trim().isNotEmpty) {
        final rootDir = Directory(customRoot);
        if (await rootDir.exists()) {
          downloadPaths.add(customRoot);
          if (shouldLog) {
            _logger.d('🐛 Using custom storage root for images: $customRoot');
          }
        } else {
          _logger.w(
              'Custom storage root is set but not accessible for images: $customRoot');
        }
      }

      // App-specific external storage is safer than public Downloads on Android.
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final appExternalDownloads = path.join(externalDir.path, 'downloads');
        final appExternalDir = Directory(appExternalDownloads);
        if (!await appExternalDir.exists()) {
          await appExternalDir.create(recursive: true);
        }
        if (!downloadPaths.contains(appExternalDownloads)) {
          downloadPaths.add(appExternalDownloads);
          if (shouldLog) {
            _logger.d(
                '🐛 Using app-specific external storage: $appExternalDownloads');
          }
        }
      }

      // Internal app documents fallback is always writable.
      final appDir = await getApplicationDocumentsDirectory();
      final internalDownloads = path.join(appDir.path, 'downloads');
      final internalDir = Directory(internalDownloads);
      if (!await internalDir.exists()) {
        await internalDir.create(recursive: true);
      }
      if (!downloadPaths.contains(internalDownloads)) {
        downloadPaths.add(internalDownloads);
        if (shouldLog) {
          _logger.d('🐛 Using app documents storage: $internalDownloads');
        }
      }
      _didLogDownloadDirectorySelection = true;
    } catch (e) {
      _logger.e('Error detecting Downloads directories: $e');
    }

    return downloadPaths;
  }

  // Get internal cache directory for temporary image storage
  // Files here expire after _cacheExpiryDuration and can be auto-cleaned
  static Future<String?> _getInternalCacheDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir =
          Directory(path.join(appDir.path, _cacheSubPath, _baseLocalPath));

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
        _logger.d('🐛 Created internal cache directory: ${cacheDir.path}');
      }

      return cacheDir.path;
    } catch (e) {
      _logger.e('Error getting internal cache directory: $e');
      return null;
    }
  }

  // Clean up expired cache files in background
  static Future<void> _cleanupExpiredCache() async {
    try {
      final cacheDir = await _getInternalCacheDirectory();
      if (cacheDir == null) return;

      final baseCacheDir = Directory(cacheDir);
      if (!await baseCacheDir.exists()) return;

      final now = DateTime.now();
      int cleanedFiles = 0;
      int cleanedDirs = 0;

      // Process each content directory in cache
      await for (final entity in baseCacheDir.list()) {
        if (entity is Directory) {
          final contentId = path.basename(entity.path);
          final cacheMetadataFile =
              File(path.join(entity.path, 'cache_metadata.json'));

          bool shouldDelete = false;

          if (await cacheMetadataFile.exists()) {
            try {
              final metadataContent = await cacheMetadataFile.readAsString();
              final metadata =
                  jsonDecode(metadataContent) is Map<String, dynamic>
                      ? jsonDecode(metadataContent) as Map<String, dynamic>
                      : <String, dynamic>{};
              final cacheTime = DateTime.parse(metadata['cached_at'] as String);

              if (now.difference(cacheTime) > _cacheExpiryDuration) {
                shouldDelete = true;
                _logger.d(
                    '🐛 Cache expired for $contentId: ${now.difference(cacheTime)} > $_cacheExpiryDuration');
              }
            } catch (e) {
              // Invalid metadata, delete the cache
              shouldDelete = true;
              _logger.w(
                  '🐛 Invalid cache metadata for $contentId, marking for deletion: $e');
            }
          } else {
            // No metadata, check file modification time
            final imagesDir = Directory(path.join(entity.path, 'images'));
            if (await imagesDir.exists()) {
              final stat = await imagesDir.stat();
              if (now.difference(stat.modified) > _cacheExpiryDuration) {
                shouldDelete = true;
                _logger.d(
                    '🐛 Cache expired by file time for $contentId: ${now.difference(stat.modified)} > $_cacheExpiryDuration');
              }
            }
          }

          if (shouldDelete) {
            try {
              await entity.delete(recursive: true);
              cleanedDirs++;
              _logger.d('🐛 Cleaned expired cache directory: ${entity.path}');
            } catch (e) {
              _logger.w(
                  '🐛 Failed to delete expired cache directory ${entity.path}: $e');
            }
          }
        } else if (entity is File) {
          // Clean up loose files that might be expired
          final stat = await entity.stat();
          if (now.difference(stat.modified) > _cacheExpiryDuration) {
            try {
              await entity.delete();
              cleanedFiles++;
              _logger.d('🐛 Cleaned expired cache file: ${entity.path}');
            } catch (e) {
              _logger.w(
                  '🐛 Failed to delete expired cache file ${entity.path}: $e');
            }
          }
        }
      }

      if (cleanedFiles > 0 || cleanedDirs > 0) {
        _logger.i(
            '🐛 Cache cleanup completed: $cleanedFiles files, $cleanedDirs directories removed');
      }
    } catch (e) {
      _logger.e('Error during cache cleanup: $e');
    }
  }

  // Save image to internal cache with metadata
  static Future<String?> _saveToInternalCache(
      String contentId, int pageNumber, List<int> imageBytes) async {
    try {
      final cacheDir = await _getInternalCacheDirectory();
      if (cacheDir == null) return null;

      final contentCacheDir =
          Directory(path.join(cacheDir, contentId, 'images'));
      if (!await contentCacheDir.exists()) {
        await contentCacheDir.create(recursive: true);
      }

      final fileName = 'page_${pageNumber.toString().padLeft(3, '0')}.jpg';
      final filePath = path.join(contentCacheDir.path, fileName);
      final file = File(filePath);

      await file.writeAsBytes(imageBytes);

      // Save cache metadata
      final metadataFile =
          File(path.join(contentCacheDir.parent.path, 'cache_metadata.json'));
      final metadata = {
        'content_id': contentId,
        'cached_at': DateTime.now().toIso8601String(),
        'expiry_hours': _cacheExpiryDuration.inHours,
      };
      await metadataFile.writeAsString(jsonEncode(metadata));

      _logger.d('🐛 Saved image to cache: $filePath');
      return filePath;
    } catch (e) {
      _logger.e('Error saving image to cache: $e');
      return null;
    }
  }

  // Get only external download paths (excluding cache)
  static Future<List<String>> _getExternalDownloadPaths() async {
    final List<String> externalPaths = [];

    try {
      // Only external storage Download folder (permanently downloaded files)
      final downloadPaths = await _getDownloadDirectories();
      for (final downloadPath in downloadPaths) {
        final downloadDir = Directory(path.join(downloadPath, _baseLocalPath));
        if (await downloadDir.exists()) {
          externalPaths.add(path.join(downloadPath, _baseLocalPath));
          // _logger.d(
          //     '🐛 External download path: ${path.join(downloadPath, _baseLocalPath)}');
        }
      }
    } catch (e) {
      _logger.e('Error getting external download paths: $e');
    }

    return externalPaths;
  }

  // Check if content is downloaded with metadata validation
  // Only checks external download folders, not cache
  static Future<bool> isContentDownloaded(String contentId) async {
    try {
      final basePaths = await _getExternalDownloadPaths();

      for (final basePath in basePaths) {
        final metadataPath = path.join(basePath, contentId, 'metadata.json');
        final metadataFile = File(metadataPath);

        if (await metadataFile.exists()) {
          _logger.d('Found metadata at: $metadataPath');
          return true;
        }

        // Also check if images directory exists (even without metadata)
        final imagesDir = Directory(path.join(basePath, contentId, 'images'));
        if (await imagesDir.exists()) {
          final files = await imagesDir.list().toList();
          final imageFiles = files
              .where((file) => file is File && _isImageFile(file.path))
              .toList();
          if (imageFiles.isNotEmpty) {
            _logger.d(
                'Found images directory at: ${imagesDir.path} with ${imageFiles.length} images');
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      _logger.e('Error checking if content is downloaded for $contentId: $e');
      return false;
    }
  }

  // Get local image path with priority: downloaded > internal cache > network cache > null
  static Future<String?> getLocalImagePath(
      String contentId, int pageNumber) async {
    try {
      final basePaths = await _getPossibleBasePaths();
      final primaryPatterns = _pageFilePatterns(pageNumber);

      // Check all possible base paths for downloaded content
      for (final basePath in basePaths) {
        for (final pattern in primaryPatterns) {
          final altPath = path.join(basePath, contentId, 'images', pattern);
          final altFile = File(altPath);
          if (await altFile.exists()) {
            _logger.d('🐛 Found downloaded image with alt pattern: $altPath');
            return altPath;
          }
        }

        // Priority 2: Check if file exists in images folder (scan directory)
        final imagesDir = Directory(path.join(basePath, contentId, 'images'));
        if (await imagesDir.exists()) {
          final files = await imagesDir.list().toList();
          final imageFiles = files
              .where((file) => file is File && _isImageFile(file.path))
              .cast<File>()
              .toList();

          // Sort by filename to maintain page order
          imageFiles.sort((a, b) =>
              _extractPageNumber(a.path).compareTo(_extractPageNumber(b.path)));

          // Return the image for the requested page number (1-indexed)
          if (pageNumber > 0 && pageNumber <= imageFiles.length) {
            final targetFile = imageFiles[pageNumber - 1];
            _logger.d('🐛 Found image by directory scan: ${targetFile.path}');
            return targetFile.path;
          }
        }
      }

      // Priority 3: Check CachedNetworkImage cache (legacy cache system)
      final cachePath = await _getCachedImagePath(contentId, pageNumber);
      if (cachePath != null && await File(cachePath).exists()) {
        _logger.d('🐛 Found legacy cached image: $cachePath');
        return cachePath;
      }

      return null; // Fallback to network
    } catch (e) {
      _logger.e(
          'Error getting local image path for $contentId page $pageNumber: $e');
      return null;
    }
  }

  // Get local thumbnail/cover path with priority: downloads > internal cache > legacy cache
  static Future<String?> getLocalThumbnailPath(String contentId) async {
    try {
      final basePaths = await _getPossibleBasePaths();

      // Check downloaded cover patterns in all base paths
      final downloadedCoverPatterns = [
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
        '1.jpg', // First page as cover
        '1.jpeg',
        '1.png',
        '1.webp',
        '1.avif',
        'page_1.jpg',
        'page_1.jpeg',
        'page_1.png',
        'page_1.webp',
        'page_1.avif',
        'page_001.jpg',
        'page_001.jpeg',
        'page_001.png',
        'page_001.webp',
        'page_001.avif',
      ];

      for (final basePath in basePaths) {
        for (final pattern in downloadedCoverPatterns) {
          final coverPath = path.join(basePath, contentId, pattern);
          if (await File(coverPath).exists()) {
            _logger.d('🐛 Found downloaded cover: $coverPath');
            return coverPath;
          }

          // Also check in images folder
          final coverInImagesPath =
              path.join(basePath, contentId, 'images', pattern);
          if (await File(coverInImagesPath).exists()) {
            _logger.d(
                '🐛 Found downloaded cover in images folder: $coverInImagesPath');
            return coverInImagesPath;
          }
        }
      }

      // Check legacy cached thumbnail
      final cachedCover = await _getCachedThumbnailPath(contentId);
      if (cachedCover != null && await File(cachedCover).exists()) {
        _logger.d('🐛 Found legacy cached thumbnail: $cachedCover');
        return cachedCover;
      }

      return null;
    } catch (e) {
      _logger.e('Error getting local thumbnail path for $contentId: $e');
      return null;
    }
  }

  // Read metadata for validation
  static Future<Map<String, dynamic>?> getDownloadedMetadata(
      String contentId) async {
    try {
      final basePaths = await _getPossibleBasePaths();

      for (final basePath in basePaths) {
        final metadataPath = path.join(basePath, contentId, 'metadata.json');
        final file = File(metadataPath);

        if (await file.exists()) {
          final jsonString = await file.readAsString();
          final metadata = jsonDecode(jsonString) is Map<String, dynamic>
              ? jsonDecode(jsonString) as Map<String, dynamic>
              : <String, dynamic>{};
          _logger.d(
              'Successfully read metadata for $contentId from $metadataPath');
          return metadata;
        }
      }

      _logger.d('Metadata file not found for $contentId in any base path');
      return null;
    } catch (e) {
      _logger.e('Error reading metadata for $contentId: $e');
      return null;
    }
  }

  // Progressive loading: downloaded > internal cache > network
  // Also saves network images to internal cache for future use
  static ImageProvider getProgressiveImageProvider(
      String networkUrl, String? localPath) {
    if (localPath != null && File(localPath).existsSync()) {
      _logger.d('🐛 Using local image provider: $localPath');
      return FileImage(File(localPath));
    }

    _logger
        .d('🐛 Using network image provider with cache fallback: $networkUrl');
    return CachedNetworkImageProvider(networkUrl);
  }

  // Download and cache image from network to internal cache
  // This method can be called when loading network images to cache them locally
  static Future<String?> downloadAndCacheImage(
    String networkUrl,
    String contentId,
    int pageNumber, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      // First check if already exists in cache to avoid duplicate downloads
      final existingPath = await getLocalImagePath(contentId, pageNumber);
      if (existingPath != null) {
        _logger.d('🐛 Image already exists locally: $existingPath');
        return existingPath;
      }

      // Check if networkUrl is actually a local file path
      if (!networkUrl.startsWith('http') &&
          (networkUrl.startsWith('/') || networkUrl.startsWith('file://'))) {
        final path = networkUrl.replaceFirst('file://', '');
        final file = File(path);
        if (await file.exists()) {
          _logger.d('🐛 Provided URL is actually a local file: $path');
          return path;
        }
      }

      // Download from network using Dio (supports cancellation)
      final dio = getIt<Dio>();
      final response = await dio.get<List<int>>(
        networkUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent': 'AppleWebKit/537.36',
            'Referer': 'https://nhentai.net/',
            ...?headers,
          },
        ),
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200 && response.data != null) {
        // Save to internal cache
        final cachedPath =
            await _saveToInternalCache(contentId, pageNumber, response.data!);
        return cachedPath;
      } else {
        _logger.w('🐛 Failed to download image: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.e('🐛 Error downloading and caching image: $e');
      return null;
    }
  }

  // Streaming download variant (memory-friendly, download-first pipeline).
  //
  // Unlike [downloadAndCacheImage] (which buffers the whole file in memory via
  // `ResponseType.bytes`), this streams bytes straight to the canonical disk
  // location and atomically renames a `.part` temp file. Memory per download is
  // bounded regardless of image size, and the result is immediately found by
  // [getLocalImagePath] on the next pass (no duplicated network fetch).
  static Future<String?> downloadAndCacheImageStreaming(
    String networkUrl,
    String contentId,
    int pageNumber, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final existingPath = await getLocalImagePath(contentId, pageNumber);
      if (existingPath != null) {
        _logger.d('🐛 [stream] Image already exists locally: $existingPath');
        return existingPath;
      }

      if (!networkUrl.startsWith('http') &&
          (networkUrl.startsWith('/') || networkUrl.startsWith('file://'))) {
        final p = networkUrl.replaceFirst('file://', '');
        if (await File(p).exists()) {
          _logger.d('🐛 [stream] Provided URL is a local file: $p');
          return p;
        }
      }

      final imagesDir = Directory(await getImagesFolderPath(contentId));
      await imagesDir.create(recursive: true);
      final targetPath =
          path.join(imagesDir.path, _pageFilePatterns(pageNumber).first);
      final tmpPath = '$targetPath.part';

      final dio = getIt<Dio>();
      await dio.download(
        networkUrl,
        tmpPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent': 'AppleWebKit/537.36',
            'Referer': 'https://nhentai.net/',
            ...?headers,
          },
        ),
      );

      if (!await File(tmpPath).exists() || await File(tmpPath).length() == 0) {
        _logger.w('🐛 [stream] Empty download: $networkUrl');
        return null;
      }
      // Atomic publish: replace any existing target before rename.
      if (await File(targetPath).exists()) {
        await File(targetPath).delete();
      }
      await File(tmpPath).rename(targetPath);

      _logger.d('🐛 [stream] Cached image to canonical path: $targetPath');
      return targetPath;
    } catch (e) {
      // Best-effort cleanup of the partial file.
      try {
        final partial = path.join(
          await getImagesFolderPath(contentId),
          '${_pageFilePatterns(pageNumber).first}.part',
        );
        if (await File(partial).exists()) {
          await File(partial).delete();
        }
      } catch (_) {}
      _logger.e('🐛 [stream] Error streaming image $networkUrl: $e');
      return null;
    }
  }

  // Get all downloaded content IDs
  static Future<List<String>> getDownloadedContentIds() async {
    try {
      final basePaths = await _getPossibleBasePaths();
      final contentIds = <String>{}; // Use Set to avoid duplicates

      for (final basePath in basePaths) {
        final baseDir = Directory(basePath);

        if (!await baseDir.exists()) {
          continue;
        }

        await for (final entity in baseDir.list()) {
          if (entity is Directory) {
            final contentId = path.basename(entity.path);
            if (await isContentDownloaded(contentId)) {
              contentIds.add(contentId);
            }
          }
        }
      }

      final resultList = contentIds.toList();
      _logger.i(
          'Found ${resultList.length} downloaded contents across all storage locations');
      return resultList;
    } catch (e) {
      _logger.e('Error getting downloaded content IDs: $e');
      return [];
    }
  }

  // Get image count for downloaded content
  static Future<int> getDownloadedImageCount(String contentId) async {
    try {
      final basePaths = await _getPossibleBasePaths();

      for (final basePath in basePaths) {
        final imagesDir = Directory(path.join(basePath, contentId, 'images'));

        if (await imagesDir.exists()) {
          final files = await imagesDir.list().toList();
          final imageFiles = files
              .where((file) => file is File && _isImageFile(file.path))
              .toList();

          if (imageFiles.isNotEmpty) {
            _logger.d(
                'Found ${imageFiles.length} images for $contentId in $basePath');
            return imageFiles.length;
          }
        }
      }

      return 0;
    } catch (e) {
      _logger.e('Error getting downloaded image count for $contentId: $e');
      return 0;
    }
  }

  // Validate downloaded content integrity
  static Future<bool> validateDownloadedContent(String contentId) async {
    try {
      final metadata = await getDownloadedMetadata(contentId);
      if (metadata == null) return false;

      final expectedPageCount = metadata['pageCount'] as int?;
      if (expectedPageCount == null) return false;

      final actualImageCount = await getDownloadedImageCount(contentId);

      final isValid = actualImageCount >= expectedPageCount;
      _logger.d(
          'Content $contentId validation: $actualImageCount/$expectedPageCount images - ${isValid ? 'VALID' : 'INVALID'}');

      return isValid;
    } catch (e) {
      _logger.e('Error validating downloaded content $contentId: $e');
      return false;
    }
  }

  // Private helper methods

  // Get cached image path (simulate cache directory)
  static Future<String?> _getCachedImagePath(
      String contentId, int pageNumber) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cachePath = path.join(
          appDir.path, 'cache', 'images', contentId, 'page_$pageNumber.jpg');

      // Check if cached version exists
      if (await File(cachePath).exists()) {
        return cachePath;
      }

      // Check CachedNetworkImage cache directory if available
      // This is a simplified approach - actual implementation might need CachedNetworkImage's cache manager
      return null;
    } catch (e) {
      _logger.e('Error getting cached image path: $e');
      return null;
    }
  }

  // Get cached thumbnail path
  static Future<String?> _getCachedThumbnailPath(String contentId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cachePath =
          path.join(appDir.path, 'cache', 'thumbnails', '$contentId.jpg');

      if (await File(cachePath).exists()) {
        return cachePath;
      }

      return null;
    } catch (e) {
      _logger.e('Error getting cached thumbnail path: $e');
      return null;
    }
  }

  // Clear image cache for specific content (useful for debugging)
  static Future<void> clearContentCache(String contentId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Clear internal cache images
      final cacheImagesDir =
          Directory(path.join(appDir.path, 'cache', 'images', contentId));
      if (await cacheImagesDir.exists()) {
        await cacheImagesDir.delete(recursive: true);
        _logger.i('🗑️ Cleared internal cache images for: $contentId');
      }

      // Clear internal cache thumbnail
      final cacheThumbnailPath =
          path.join(appDir.path, 'cache', 'thumbnails', '$contentId.jpg');
      final thumbnailFile = File(cacheThumbnailPath);
      if (await thumbnailFile.exists()) {
        await thumbnailFile.delete();
        _logger.i('🗑️ Cleared internal cache thumbnail for: $contentId');
      }
    } catch (e) {
      _logger.e('Error clearing content cache for $contentId: $e');
    }
  }

  // Clear all internal image cache (emergency reset)
  static Future<void> clearAllImageCache() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Clear all cached images
      final cacheDir = Directory(path.join(appDir.path, 'cache'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        _logger.i('🗑️ Cleared all internal image cache');
      }
    } catch (e) {
      _logger.e('Error clearing all image cache: $e');
    }
  }

  // Helper method to check if file is an image
  static bool _isImageFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.bmp']
        .contains(extension);
  }

  static List<String> _pageFilePatterns(int pageNumber) {
    final padded = pageNumber.toString().padLeft(3, '0');
    final extensions = ['jpg', 'jpeg', 'png', 'webp', 'avif', 'gif', 'bmp'];
    final patterns = <String>[];

    for (final ext in extensions) {
      patterns.add('page_$pageNumber.$ext');
      patterns.add('page_$padded.$ext');
      patterns.add('$padded.$ext');
      patterns.add('$pageNumber.$ext');
      patterns.add('image_$pageNumber.$ext');
    }

    return patterns.toSet().toList();
  }

  // Helper method to extract page number from filename
  static int _extractPageNumber(String filePath) {
    final filename = path.basenameWithoutExtension(filePath);
    final match = RegExp(r'(\d+)').firstMatch(filename);
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  // Get base local path for content
  static Future<String> getBaseLocalPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, _baseLocalPath);
  }

  // Get content folder path
  static Future<String> getContentFolderPath(String contentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, _baseLocalPath, contentId);
  }

  // Get images folder path
  static Future<String> getImagesFolderPath(String contentId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, _baseLocalPath, contentId, 'images');
  }
}
