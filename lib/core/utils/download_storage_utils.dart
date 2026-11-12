import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';

import 'package:kuron_core/kuron_core.dart'; // Import ContentMetadata

import 'directory_utils.dart';

// Extracted from DownloadBloc to reduce complexity and promote reusability.
// Contains methods for directory detection, file management, and metadata reading.
class DownloadStorageUtils {
  DownloadStorageUtils._();

  static final Logger _logger = getIt<Logger>();

  // Delegates to [DirectoryUtils.getDownloadsDirectory]
  // Kept for backward compatibility; prefer DirectoryUtils directly.
  static Future<String> getDownloadsDirectory() async {
    return DirectoryUtils.getDownloadsDirectory();
  }

  static Future<int> getDirectorySize(Directory directory) async {
    int size = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      _logger.w('Error calculating directory size: $e');
    }
    return size;
  }

  // Deletes files ending with .tmp, .temp, .part, or starting with .
  static Future<void> cleanupTempFiles(Directory directory) async {
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          // Delete temporary files
          if (fileName.endsWith('.tmp') ||
              fileName.endsWith('.temp') ||
              fileName.endsWith('.part') ||
              fileName.startsWith('.')) {
            try {
              await entity.delete();
              _logger.d('Deleted temp file: ${entity.path}');
            } catch (e) {
              _logger.w(
                'Failed to delete temp file: ${entity.path}, error: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      _logger.w('Error cleaning temp files in: ${directory.path}, error: $e');
    }
  }

  static Future<Map<String, dynamic>?> readLocalMetadata(
    String contentId, {
    String? sourceId,
  }) async {
    try {
      _logger.d('Reading local metadata for content: $contentId');

      File? metadataFile;

      if (sourceId != null && sourceId.isNotEmpty) {
        final contentDir = await getContentDirectory(
          contentId,
          sourceId: sourceId,
        );
        final candidate = File(
          path.join(contentDir, AppStorage.metadataFileName),
        );
        if (await candidate.exists()) {
          metadataFile = candidate;
        }
      } else {
        for (final knownSourceId in AppStorage.knownSources) {
          final contentDir = await getContentDirectory(
            contentId,
            sourceId: knownSourceId,
          );
          final candidate = File(
            path.join(contentDir, AppStorage.metadataFileName),
          );
          if (await candidate.exists()) {
            metadataFile = candidate;
            break;
          }
        }
      }

      // Fallback to legacy path: nhasix/{contentId}/metadata.json
      if (metadataFile == null) {
        final downloadsPath = await getDownloadsDirectory();
        final legacyCandidate = File(
          path.join(
            downloadsPath,
            AppStorage.backupFolderName,
            contentId,
            AppStorage.metadataFileName,
          ),
        );
        if (await legacyCandidate.exists()) {
          metadataFile = legacyCandidate;
        }
      }

      // Check if metadata file exists
      if (metadataFile == null || !await metadataFile.exists()) {
        _logger.w('Metadata file does not exist for content: $contentId');
        return null;
      }

      // Read and parse metadata
      final metadataContent = await metadataFile.readAsString();
      final metadata = jsonDecode(metadataContent) as Map<String, dynamic>;

      _logger.i('Successfully read local metadata for $contentId');
      _logger.d('Metadata title: ${metadata['title']}');

      return metadata;
    } catch (e) {
      _logger.e('Error reading local metadata for $contentId: $e');
      return null;
    }
  }

  // Critical for metadata sync operations where title field might be missing or corrupt (e.g. KomikTap ciphertext bug).
  static String getSafeTitleFromMetadata(
    Map<String, dynamic>? metadata,
    String contentId,
  ) {
    String formatSlug(String slug) {
      if (slug.isEmpty || !slug.contains('-')) return slug;
      return slug
          .split('-')
          .map((word) {
            if (word.isEmpty) return '';
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          })
          .join(' ');
    }

    if (metadata == null) return formatSlug(contentId);

    final title = metadata['title'] as String? ?? '';
    final originalId = getOriginalContentIdFromMetadata(
      metadata,
      fallbackContentId: contentId,
    );

    // If title is genuinely empty, convert slug to human-readable title
    if (title.isEmpty) {
      return formatSlug(originalId);
    }

    // Fallback for ciphertext bug (Cloudflare encryption output: very long, no spaces)
    if (title.length > 50 && !title.contains(' ')) {
      return formatSlug(originalId);
    }

    return title;
  }

  static String getOriginalContentIdFromMetadata(
    Map<String, dynamic>? metadata, {
    required String fallbackContentId,
  }) {
    if (metadata == null) {
      return fallbackContentId;
    }

    final rawId = metadata['id']?.toString().trim() ?? '';
    if (rawId.isNotEmpty) {
      return rawId;
    }

    final rawContentId = metadata['content_id']?.toString().trim() ?? '';
    if (rawContentId.isNotEmpty) {
      return rawContentId;
    }

    return fallbackContentId;
  }

  static String? getSourceIdFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) {
      return null;
    }

    for (final key in ['sourceId', 'source_id', 'source']) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  // This is CRITICAL for the Safe ID strategy.
  // The metadata.json file acts as the "decoder key" to identify content
  // when the folder name is a hashed "Safe ID".
  static Future<void> saveLocalMetadata({
    required String contentId,
    required String sourceId,
    required String title,
    required String savePath,
    String? coverUrl,
    String? url,
    String? language,
    int? totalImages,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final metadataPath = path.join(savePath, AppStorage.metadataFileName);
      final file = File(metadataPath);

      // Create directory if not exists
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      final metadata = {
        'id': contentId,
        'sourceId': sourceId,
        'source': sourceId, // v2 compatibility
        'title': title,
        'url': url ?? '',
        'coverUrl': coverUrl ?? '',
        'language': language ?? '',
        'totalImages': totalImages ?? 0,
        'downloadedAt': DateTime.now().toIso8601String(),
        'schemaVersion': 2,
        ...?extraData,
      };

      await file.writeAsString(jsonEncode(metadata));
      _logger.i('💾 Saved local metadata for $contentId at $metadataPath');
    } catch (e) {
      _logger.e('Failed to save local metadata for $contentId: $e');
    }
  }

  // Returns sorted list of image file paths from the download directory
  static Future<List<String>> getDownloadedImagePaths(
    String contentId, {
    String? sourceId,
  }) async {
    try {
      _logger.d('Getting image paths for content: $contentId');

      final contentDir = await getContentDirectory(
        contentId,
        sourceId: sourceId,
      );
      final imagesDir = Directory(
        path.join(contentDir, AppStorage.imagesSubfolder),
      );

      // Check if directory exists
      if (!await imagesDir.exists()) {
        _logger.w('Images directory does not exist: ${imagesDir.path}');
        return <String>[];
      }

      // List all files in the images directory
      final files = await imagesDir.list().toList();

      // Filter only image files and sort them
      final imagePaths = files
          .whereType<File>()
          .where((file) {
            final extension = path.extension(file.path).toLowerCase();
            return [
              '.jpg',
              '.jpeg',
              '.png',
              '.gif',
              '.webp',
              '.avif',
            ].contains(extension);
          })
          .map((file) => file.path)
          .toList();

      // Sort by filename to maintain page order
      imagePaths.sort();

      _logger.i(
        'Found ${imagePaths.length} image files for content: $contentId',
      );

      if (imagePaths.isEmpty) {
        _logger.w(
          'No downloaded images found for content: $contentId, folder: ${imagesDir.path}',
        );
      } else {
        _logger.d(
          'Image files: ${imagePaths.take(5).join(', ')}${imagePaths.length > 5 ? '...' : ''}',
        );
      }

      return imagePaths;
    } catch (e) {
      _logger.e('Error getting downloaded image paths: $e');
      return <String>[];
    }
  }

  // Uses SHA-1 hash converted to Base36 for short, filesystem-safe folder names.
  // Example: "very-long-title..." -> "a1b2c3d4"
  static String getElegantId(String contentId) {
    if (contentId.length <= 20 &&
        RegExp(r'^[a-zA-Z0-9.\-_]+$').hasMatch(contentId)) {
      return contentId; // Keep short, safe IDs as is (e.g. nhentai numbers)
    }

    final bytes = utf8.encode(contentId);
    final digest = sha1.convert(bytes);

    // Convert first 6 bytes of hash to Base36 (alphanumeric)
    // 6 bytes = 48 bits, enough to avoid collisions for this use case
    // while keeping string very short (approx 8-10 chars max)
    final bigInt = BigInt.parse(
      digest.bytes
          .sublist(0, 6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      radix: 16,
    );

    return bigInt.toRadixString(36);
  }

  // UPDATE: Now uses "Elegant ID" strategy (Base36 Hash)
  // Legacy strategy (Truncate + Hash) is deprecated but supported for readout.
  static String getSafeContentId(String contentId) {
    return getElegantId(contentId);
  }

  /// Maps a raw content/chapter id to a single safe filesystem segment.
  ///
  /// Some sources (e.g. Komikcast) use raw hrefs like `/series/<slug>/<ch>`
  /// as chapter ids. `package:path` discards every segment before an
  /// absolute one, so `path.join(dir, '/series/...', ...)` escapes the app
  /// dir and `create(recursive: true)` dies with FileSystemException.
  /// Centralize ALL contentId-to-path-segment mapping here so every path
  /// (reader cache, downloads, pdf, offline lookups) stays consistent.
  ///
  /// Side effect: locations for ids containing `/` MOVE to the sanitized
  /// form. Clean ids are returned unchanged (identity), so existing
  /// libraries are untouched. Orphan dirs from the old layout, if any, are
  /// ignored here; the periodic sweeper/expiry reclaims them.
  static String safePathSegment(String contentId) {
    var segment = contentId.trim().replaceAll(RegExp(r'^/+'), '');
    segment = segment.replaceAll('/', '__');
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ArgumentError.value(
        contentId,
        'contentId',
        'must not be empty or a bare relative-path token',
      );
    }
    return segment;
  }

  // This checks locations in the following order:
  // 1. Elegant ID (New Standard)
  // 2. Safe ID (Truncated - Migration Interim)
  // 3. Original ID (Legacy)
  static Future<String> getContentDirectory(
    String contentId, {
    String? sourceId,
  }) async {
    final downloadsDir = await getDownloadsDirectory();
    final effectiveSourceId = sourceId ?? AppStorage.defaultSourceId;

    // 1. Check Elegant ID Path (New Standard)
    final elegantId = getElegantId(contentId);
    final elegantPath = path.join(
      downloadsDir,
      AppStorage.backupFolderName,
      effectiveSourceId,
      elegantId,
    );
    if (await Directory(elegantPath).exists()) {
      return elegantPath;
    }

    // 2. Check Truncated "Safe" ID Path (Interim Strategy)
    // We construct this manually here to check for it
    if (contentId.length > 50) {
      final bytes = utf8.encode(contentId);
      final digest = sha1.convert(bytes);
      final hash = digest.toString().substring(0, 8);
      final truncatedId = '${contentId.substring(0, 40)}_$hash';

      final truncatedPath = path.join(
        downloadsDir,
        AppStorage.backupFolderName,
        effectiveSourceId,
        truncatedId,
      );
      if (await Directory(truncatedPath).exists()) {
        return truncatedPath; // Found interim folder
      }
    }

    // 3. Check Original ID Path (Legacy / Standard for short IDs)
    if (elegantId != contentId) {
      final originalPath = path.join(
        downloadsDir,
        AppStorage.backupFolderName,
        effectiveSourceId,
        contentId,
      );
      if (await Directory(originalPath).exists()) {
        return originalPath;
      }
    }

    // 4. Check Legacy Safe Path (No Source ID, if applicable)
    // ... skipped for brevity, prioritizing source-based structure ...

    // Default to the Elegant ID path for new content
    return elegantPath;
  }

  static Future<String> getNewContentDirectory(
    String contentId, {
    String? sourceId,
  }) async {
    final downloadsDir = await getDownloadsDirectory();
    final effectiveSourceId = sourceId ?? AppStorage.defaultSourceId;
    final safeId = getSafeContentId(contentId);

    return path.join(
      downloadsDir,
      AppStorage.backupFolderName,
      effectiveSourceId,
      safeId,
    );
  }

  static Future<String> getSourceDirectory({String? sourceId}) async {
    final downloadsPath = await getDownloadsDirectory();
    final effectiveSourceId = sourceId ?? AppStorage.defaultSourceId;

    return path.join(
      downloadsPath,
      AppStorage.backupFolderName,
      effectiveSourceId,
    );
  }

  static Future<bool> isContentDownloaded(
    String contentId, {
    String? sourceId,
  }) async {
    final imagePaths = await getDownloadedImagePaths(
      contentId,
      sourceId: sourceId,
    );
    return imagePaths.isNotEmpty;
  }

  static Future<bool> migrateToSourceFolder(
    String contentId, {
    String sourceId = 'nhentai',
  }) async {
    try {
      final downloadsPath = await getDownloadsDirectory();

      // Check if legacy path exists
      final legacyPath = path.join(
        downloadsPath,
        AppStorage.backupFolderName,
        contentId,
      );
      final legacyDir = Directory(legacyPath);

      if (!await legacyDir.exists()) {
        return false; // Nothing to migrate
      }

      // Check if it's actually a content folder (has metadata.json or images)
      final hasMetadata = await File(
        path.join(legacyPath, AppStorage.metadataFileName),
      ).exists();
      final hasImages = await Directory(
        path.join(legacyPath, AppStorage.imagesSubfolder),
      ).exists();

      if (!hasMetadata && !hasImages) {
        return false; // Not a content folder (could be source folder)
      }

      // Create source directory if needed
      final sourceDir = Directory(
        path.join(downloadsPath, AppStorage.backupFolderName, sourceId),
      );
      if (!await sourceDir.exists()) {
        await sourceDir.create(recursive: true);
      }

      // New path
      final newPath = path.join(
        downloadsPath,
        AppStorage.backupFolderName,
        sourceId,
        contentId,
      );

      // Update metadata.json to v2 if it exists
      final metadataFile = File(
        path.join(legacyPath, AppStorage.metadataFileName),
      );
      if (await metadataFile.exists()) {
        try {
          final metadataContent = await metadataFile.readAsString();
          final jsonMap = jsonDecode(metadataContent) as Map<String, dynamic>;

          // Migrate using ContentMetadata model
          // This automatically handles v1 -> v2 migration (adds source='nhentai', schemaVersion='2.0')
          final metadata = ContentMetadata.fromJson(jsonMap);

          // Force source to be the target sourceId of migration and upgrade schema version
          final updatedMetadata = metadata.copyWith(
            source: sourceId,
            schemaVersion: MetadataVersion.v2,
          );

          // Write back updated metadata
          await metadataFile.writeAsString(
            jsonEncode(updatedMetadata.toJson()),
          );
          _logger.d('Upgraded metadata for $contentId to v2');
        } catch (e) {
          _logger.w('Failed to upgrade metadata for $contentId: $e');
          // Start migration anyway, metadata will be readable as v1 fallback
        }
      }

      // Move folder
      await legacyDir.rename(newPath);
      _logger.i('Migrated content $contentId to $sourceId folder');

      return true;
    } catch (e) {
      _logger.e('Error migrating content $contentId: $e');
      return false;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }
}
