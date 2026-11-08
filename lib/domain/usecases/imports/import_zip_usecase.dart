import 'dart:io';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:path/path.dart' as path;
import 'package:kuron_native/kuron_native.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/download_storage_utils.dart';
import '../../../domain/repositories/user_data_repository.dart';
import '../../../domain/entities/download_status.dart';

// Parameters for importing a ZIP file
class ImportZipParams {
  // Optional progress callback: (fileIndex, totalFiles, processed, total, imageCount, currentFile)
  final void Function(int fileIndex, int totalFiles, int processed, int total,
      int imageCount, String currentFile)? onProgress;
  final Future<void> Function(int totalFiles)? onStarted;

  const ImportZipParams({this.onProgress, this.onStarted});
}

// UseCase for importing ZIP files containing doujin/manga content
///
// This handles:
// 1. Picking one or more ZIP files using native file picker
// 2. Extracting the ZIP natively with progress notifications
// 3. Auto-generating metadata.json
// 4. Registering the content in the database
class ImportZipUseCase {
  final KuronNative _kuronNative;
  final UserDataRepository _userDataRepository;
  final Logger _logger = getIt<Logger>();

  ImportZipUseCase({
    required this._kuronNative,
    required this._userDataRepository,
  });

  // Executes the ZIP import flow using native extraction with progress notifications
  ///
  // Returns a map with:
  // - 'success': bool
  // - 'contentId': String (if successful)
  // - 'error': String (if failed)
  Future<Map<String, dynamic>> call(ImportZipParams params) async {
    try {
      _logger.i('Starting native ZIP import flow');

      final zipUris = await _pickZipUris();
      if (zipUris.isEmpty) {
        _logger.i('User cancelled ZIP file selection');
        return {'success': false, 'error': 'Cancelled'};
      }

      if (zipUris.length > 1) {
        _logger.i('ZIP files selected: ${zipUris.join(', ')}');
      } else {
        _logger.i('ZIP file selected: ${zipUris.first}');
      }

      if (params.onStarted != null) {
        await params.onStarted!(zipUris.length);
      }

      final importedResults = <Map<String, dynamic>>[];
      final failedResults = <Map<String, dynamic>>[];

      for (int i = 0; i < zipUris.length; i++) {
        final zipUri = zipUris[i];
        final result =
            await _importSingleZip(zipUri, params, i + 1, zipUris.length);
        if (result['success'] == true) {
          importedResults.add(result);
        } else {
          failedResults.add(result);
        }
      }

      if (importedResults.isEmpty) {
        return {
          'success': false,
          'error': failedResults.isNotEmpty
              ? (failedResults.first['error'] as String? ?? 'Extraction failed')
              : 'Extraction failed',
        };
      }

      return {
        'success': true,
        'contentId': importedResults.first['contentId'],
        'contentIds': importedResults
            .map((result) => result['contentId'] as String)
            .toList(growable: false),
        'imageCount': importedResults.fold<int>(
          0,
          (sum, result) => sum + (result['imageCount'] as int? ?? 0),
        ),
        'importedCount': importedResults.length,
        'failedCount': failedResults.length,
        if (failedResults.isNotEmpty)
          'errors': failedResults
              .map(
                  (result) => result['error'] as String? ?? 'Extraction failed')
              .toList(growable: false),
      };
    } catch (e, stackTrace) {
      _logger.e('Error importing ZIP file', error: e, stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<List<String>> _pickZipUris() async {
    try {
      final zipUris = await _kuronNative.pickZipFiles();
      if (zipUris != null) {
        return zipUris;
      }
    } catch (_) {
      // Fallback to single picker on platforms without multi-select support.
    }

    final singleZipUri = await _kuronNative.pickZipFile();
    if (singleZipUri == null || singleZipUri.trim().isEmpty) {
      return const [];
    }

    return [singleZipUri];
  }

  Future<Map<String, dynamic>> _importSingleZip(
    String zipUri,
    ImportZipParams params,
    int fileIndex,
    int totalFiles,
  ) async {
    final zipDisplayName = await _kuronNative.getZipDisplayName(zipUri);
    final zipFileName =
        (zipDisplayName != null && zipDisplayName.trim().isNotEmpty)
            ? zipDisplayName.trim()
            : _extractFileNameFromUri(zipUri);
    final baseContentId = _sanitizeContentId(zipFileName);
    final contentId =
        await _ensureUniqueContentId(baseContentId, sourceId: 'local');

    _logger.i('Content ID: $contentId');

    final destDir = await DownloadStorageUtils.getNewContentDirectory(
      contentId,
      sourceId: 'local',
    );

    _logger.i('Destination directory: $destDir');

    final imagesDir = Directory(path.join(destDir, AppStorage.imagesSubfolder));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    _logger.i('Starting native ZIP extraction with progress callbacks');

    final extractionResult = await _kuronNative.extractZipFile(
      contentUri: zipUri,
      destinationPath: imagesDir.path,
      onProgress: (processed, total, imageCount, currentFile) {
        _logger.d(
          'Extraction progress: $processed/$total, images: $imageCount, current: $currentFile',
        );
        params.onProgress?.call(
            fileIndex, totalFiles, processed, total, imageCount, currentFile);
      },
    );

    if (extractionResult == null || extractionResult['success'] != true) {
      _logger.e('Extraction failed: ${extractionResult?['error']}');
      if (await Directory(destDir).exists()) {
        await Directory(destDir).delete(recursive: true);
      }
      return {
        'success': false,
        'error': extractionResult?['error'] ?? 'Extraction failed',
      };
    }

    final imageCount = extractionResult['imageCount'] as int;
    _logger.i('Extracted $imageCount images natively');

    final imageFiles = await imagesDir.list(recursive: true).toList();
    final imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.avif',
      '.bmp',
    ];

    final sortedImages = imageFiles
        .whereType<File>()
        .where(
          (f) => imageExtensions.contains(path.extension(f.path).toLowerCase()),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final coverUrl = sortedImages.isNotEmpty ? sortedImages.first.path : '';

    int totalFileSize = 0;
    for (final file in sortedImages) {
      if (await file.exists()) {
        totalFileSize += await file.length();
      }
    }
    _logger.i('Total file size: ${_formatBytes(totalFileSize)}');

    await DownloadStorageUtils.saveLocalMetadata(
      contentId: contentId,
      sourceId: 'local',
      title: _formatTitle(contentId),
      savePath: destDir,
      coverUrl: coverUrl,
      totalImages: imageCount,
      extraData: {
        'autoGenerated': true,
        'importedAt': DateTime.now().toIso8601String(),
        'importedFrom': 'zip',
        'originalFileName': zipFileName,
        'extractedNatively': true,
      },
    );

    _logger.i('Metadata.json generated');

    final downloadStatus = DownloadStatus(
      contentId: contentId,
      state: DownloadState.completed,
      totalPages: imageCount,
      downloadPath: destDir,
      title: _formatTitle(contentId),
      sourceId: 'local',
      coverUrl: coverUrl,
      downloadedPages: imageCount,
      fileSize: totalFileSize,
    );

    await _userDataRepository.saveDownloadStatus(downloadStatus);

    _logger.i('Content registered in database');

    return {
      'success': true,
      'contentId': contentId,
      'imageCount': imageCount,
    };
  }

  // Extracts file name from URI and decodes URL encoding
  String _extractFileNameFromUri(String uri) {
    // First decode URL encoding (e.g., %3A -> :, %2F -> /)
    final String decoded = Uri.decodeComponent(uri);

    // Handle content:// URIs
    if (decoded.contains('/')) {
      final segments = decoded.split('/');
      for (int i = segments.length - 1; i >= 0; i--) {
        if (segments[i].isNotEmpty && !segments[i].contains(':')) {
          return segments[i];
        }
      }
    }
    return decoded;
  }

  // Sanitizes content ID (removes .zip extension, special chars)
  String _sanitizeContentId(String fileName) {
    var cleaned = fileName;

    // Remove .zip extension
    if (cleaned.toLowerCase().endsWith('.zip')) {
      cleaned = cleaned.substring(0, cleaned.length - 4);
    }

    // Replace spaces and special characters with hyphens
    cleaned = cleaned
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();

    return cleaned.isNotEmpty
        ? cleaned
        : 'imported-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _ensureUniqueContentId(
    String baseContentId, {
    required String sourceId,
  }) async {
    var candidate = baseContentId;
    var suffix = 2;

    while (true) {
      final existingStatus = await _userDataRepository.getDownloadStatus(
        candidate,
      );
      if (existingStatus != null) {
        final existingSourceId = existingStatus.sourceId?.toLowerCase();
        if (existingSourceId == sourceId.toLowerCase()) {
          final existingDir = await DownloadStorageUtils.getContentDirectory(
            candidate,
            sourceId: sourceId,
          );
          if (await Directory(existingDir).exists()) {
            await Directory(existingDir).delete(recursive: true);
          }
          await _userDataRepository.deleteDownloadStatus(candidate);
          return candidate;
        }

        candidate = '$baseContentId-$suffix';
        suffix++;
        continue;
      }

      final existingDir = await DownloadStorageUtils.getContentDirectory(
          candidate,
          sourceId: sourceId);
      if (!await Directory(existingDir).exists()) {
        return candidate;
      }
      candidate = '$baseContentId-$suffix';
      suffix++;
    }
  }

  // Formats content ID into a readable title
  String _formatTitle(String contentId) {
    return contentId
        .split('-')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ')
        .trim();
  }

  // Formats bytes into human-readable string
  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }
}
