import 'dart:io';

import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:path/path.dart' as path;

import 'package:logger/logger.dart';

import '../utils/directory_utils.dart';
import '../utils/download_storage_utils.dart';
import 'notification_service.dart';
import 'native_pdf_service.dart';

// Service yang menangani konversi PDF di background dengan fitur splitting dan notifikasi
// Handles background PDF conversion with splitting, progress tracking, and notifications
class PdfConversionService {
  PdfConversionService({
    required this._notificationService,
    required this._nativePdfService,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final NotificationService _notificationService;
  final NativePdfService _nativePdfService;
  final Logger _logger;

  // Localization callback
  String Function(String key, {Map<String, dynamic>? args})? _localize;

  // Test method untuk verify apakah notification service bisa menampilkan notification
  // Test method to verify if notification service can display notifications
  Future<bool> testPdfNotification({
    String testContentId = 'test-pdf-123',
    String testTitle = 'PDF Notification Test',
  }) async {
    try {
      _logger.i('PDF_NOTIFICATION: testPdfNotification - STARTING test');
      await _ensureNotificationServiceReady();

      await _notificationService.showPdfConversionStarted(
        contentId: testContentId,
        title: testTitle,
      );

      await Future.delayed(const Duration(seconds: 2));

      await _notificationService.showPdfConversionCompleted(
        contentId: testContentId,
        title: testTitle,
        pdfPaths: ['/test/path/test.pdf'],
        partsCount: 1,
      );
      return true;
    } catch (e) {
      _logger.i('PDF_NOTIFICATION: testPdfNotification - EXCEPTION: $e');
      return false;
    }
  }

  static Future<void> quickTestPdfNotifications() async {
    try {
      final service = getIt<PdfConversionService>();
      await service.testPdfNotification();
    } catch (e) {
      getIt<Logger>().i(
        'PDF_NOTIFICATION: quickTestPdfNotifications - FAILED: $e',
      );
    }
  }

  Future<void> _ensureNotificationServiceReady() async {
    try {
      await _notificationService.initialize();
    } catch (e) {
      _logger.w(
        'PdfConversionService: Failed to re-initialize notification service',
        error: e,
      );
    }
  }

  // Mengkonversi images download menjadi PDF di background menggunakan native generator
  // Converts downloaded images to PDF in background using native generator
  ///
  // Parameters:
  // - contentId: ID konten yang akan dikonversi
  // - title: Judul konten untuk nama file PDF
  // - imagePaths: List path gambar yang sudah di-download
  // - outputDir: Direktori output (optional, default: nhasix-generate/pdf/)
  // - maxPagesPerFile: Deprecated - native handles all pages in single file
  Future<void> convertToPdfInBackground({
    required String contentId,
    required String title,
    required List<String> imagePaths,
    String? sourceId,
    String? outputDir,
    int maxPagesPerFile = 50,
    void Function(int progress, String message)?
    onProgress, // NEW: group notification callback
  }) async {
    try {
      _logger.i(
        'PDF_NOTIFICATION: convertToPdfInBackground - STARTED for contentId=$contentId, title=$title, sourceId=$sourceId, images=${imagePaths.length}',
      );

      _logger.i(
        'PdfConversionService: Starting NATIVE PDF conversion for $contentId',
      );

      if (imagePaths.isEmpty) {
        throw Exception(
          _getLocalized(
            'pdfNoImagesProvided',
            fallback: 'No images provided for PDF conversion',
          ),
        );
      }

      await _ensureNotificationServiceReady();

      // Create output directory for PDFs
      final pdfOutputDir = await _createPdfOutputDirectory(
        outputDir,
        contentId,
        sourceId,
      );

      _logger.d(
        'PdfConversionService: Output directory created: ${pdfOutputDir.path}',
      );

      // Log strategy
      final int imageCount = imagePaths.length;
      _logger.i('========================================');
      _logger.i('🚀 PDF GENERATION - NATIVE ONLY');
      _logger.i('Total images: $imageCount');
      _logger.i('Engine: Android Native PDF Generator');
      _logger.i('Performance: ~5x faster than Flutter');
      _logger.i('========================================');

      // Generate PDF using native implementation
      await _generatePdfNative(
        contentId: contentId,
        title: title,
        imagePaths: imagePaths,
        sourceId: sourceId,
        pdfOutputDir: pdfOutputDir,
        onProgress: onProgress,
      );

      _logger.i(
        'PdfConversionService: PDF conversion completed successfully for $contentId',
      );
    } catch (e, stackTrace) {
      // Handle unexpected errors during conversion process
      _logger.e(
        'PdfConversionService: Unexpected error during PDF conversion for $contentId',
        error: e,
        stackTrace: stackTrace,
      );

      _logger.i(
        'PDF_NOTIFICATION: convertToPdfInBackground - ERROR occurred: ${e.toString()}',
      );

      // Ensure notification service is ready for error notification
      await _ensureNotificationServiceReady();

      _logger.i(
        'PDF_NOTIFICATION: convertToPdfInBackground - Calling showPdfConversionError',
      );

      await _notificationService.showPdfConversionError(
        contentId: contentId,
        title: title,
        error: 'Conversion failed: ${e.toString()}',
      );

      _logger.i(
        'PDF_NOTIFICATION: convertToPdfInBackground - showPdfConversionError completed',
      );
    }
  }

  // Generate PDF using native high-performance implementation
  ///
  // Uses Android native PDF generator for ~5x speedup on large webtoon sets.
  // This method handles progress updates and notification management.
  Future<void> _generatePdfNative({
    required String contentId,
    required String title,
    required List<String> imagePaths,
    String? sourceId,
    required Directory pdfOutputDir,
    void Function(int progress, String message)? onProgress,
  }) async {
    _logger.i('Starting NATIVE PDF generation...');

    // Create output path (use simple sanitization here)
    final safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final pdfPath = path.join(
      pdfOutputDir.path,
      '${DownloadStorageUtils.safePathSegment(contentId)}_$safeTitle.pdf',
    );
    try {
      // Track last update to throttle notifications
      int lastProgress = -1;
      DateTime lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);

      // Call native service with progress callbacks
      final result = await _nativePdfService.generatePdfNative(
        imagePaths: imagePaths,
        outputPath: pdfPath,
        title: title,
        onProgress: (progress, message) async {
          final now = DateTime.now();
          // Update if:
          // 1. Progress changed significantly (>= 5%)
          // 2. OR enough time passed (>= 500ms)
          // 3. OR it's start (0%) or completion (100%)
          if (progress == 0 ||
              progress == 100 ||
              (progress - lastProgress).abs() >= 5 ||
              now.difference(lastUpdateTime).inMilliseconds >= 500) {
            lastProgress = progress;
            lastUpdateTime = now;

            // Update notification with real-time progress from native
            onProgress?.call(progress, message);
            _logger.d('Native progress: $progress% - $message');
          }
        },
      );

      if (result['success'] == true) {
        _logger.i('========================================');
        _logger.i('✨ NATIVE PDF GENERATION SUCCESS!');
        _logger.i('📁 Path: ${result['pdfPath']}');
        _logger.i('📄 Pages: ${result['pageCount']}');
        final fileSize = result['fileSize'] as int;
        final sizeStr = fileSize < 1024 * 1024
            ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
            : '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        _logger.i('💾 Size: $sizeStr');
        _logger.i('========================================');

        // Show completion notification
        await _notificationService.showPdfConversionCompleted(
          contentId: contentId,
          title: title,
          pdfPaths: [result['pdfPath'] as String],
          partsCount: 1,
        );
      } else {
        throw Exception('Native PDF generation returned unsuccessful result');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Native PDF generation error',
        error: e,
        stackTrace: stackTrace,
      );

      // Show error notification
      await _notificationService.showPdfConversionError(
        contentId: contentId,
        title: title,
        error: 'Native generation failed: ${e.toString()}',
      );

      rethrow; // Propagate to trigger fallback
    }
  }

  // Membuat direktori output untuk file PDF
  // Creates output directory for PDF files
  ///
  // Returns: Directory object untuk menyimpan PDF
  Future<Directory> _createPdfOutputDirectory(
    String? customOutputDir, [
    String? contentId,
    String? sourceId,
  ]) async {
    try {
      Directory outputDir;

      if (customOutputDir != null) {
        // Gunakan direktori custom yang diberikan user
        // Use custom directory provided by user
        outputDir = Directory(customOutputDir);
      } else {
        // Gunakan smart Downloads directory detection (sama dengan DownloadService)
        // Use smart Downloads directory detection (same as DownloadService)
        final downloadsPath = await DirectoryUtils.getDownloadsDirectory();

        if (contentId != null) {
          if (sourceId != null) {
            // New structure: Downloads/nhasix/[sourceId]/[contentId]/pdf/
            // FIX: Use Safe ID for folder creation to handle long titles
            final safeContentId = DownloadStorageUtils.getSafeContentId(
              contentId,
            );
            outputDir = Directory(
              path.join(
                downloadsPath,
                'nhasix',
                sourceId,
                safeContentId,
                'pdf',
              ),
            );
          } else {
            // Legacy/Fallback: Downloads/nhasix/[contentId]/pdf/
            // FIX: Use Safe ID for folder creation
            final safeContentId = DownloadStorageUtils.getSafeContentId(
              contentId,
            );
            outputDir = Directory(
              path.join(downloadsPath, 'nhasix', safeContentId, 'pdf'),
            );
          }
        } else {
          // Fallback ke folder umum: Downloads/nhasix-generate/pdf/
          // Fallback to general folder: Downloads/nhasix-generate/pdf/
          outputDir = Directory(
            path.join(downloadsPath, 'nhasix-generate', 'pdf'),
          );
        }
      }

      // Buat direktori jika belum ada (recursive: true untuk membuat parent dirs)
      // Create directory if it doesn't exist (recursive: true to create parent dirs)
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
        _logger.i(
          _getLocalized(
            'pdfOutputDirectoryCreated',
            args: {'path': outputDir.path},
            fallback:
                'PdfConversionService: Created PDF output directory: ${outputDir.path}',
          ),
        );
      }

      return outputDir;
    } catch (e) {
      _logger.e(
        'PdfConversionService: Failed to create PDF output directory',
        error: e,
      );

      /*
      // Fallback ke app documents directory jika gagal akses external storage
      // Fallback to app documents directory if external storage access fails
      final documentsDir = await getApplicationDocumentsDirectory();
      final fallbackDir = Directory(path.join(documentsDir.path, 'nhasix-pdf'));

      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }

      _logger.w(_getLocalized('pdfUsingFallbackDirectory',
          args: {'path': fallbackDir.path},
          fallback:
              'PdfConversionService: Using fallback directory: ${fallbackDir.path}'));
      return fallbackDir;
      */
      throw Exception(
        'Failed to create PDF output directory in custom storage. Please check storage permissions and settings.',
      );
    }
  }

  // Cek apakah PDF sudah pernah dibuat untuk konten tertentu
  // Check if PDF has been created for specific content
  ///
  // Returns: true jika PDF sudah ada, false jika belum
  Future<bool> isPdfExistForContent(
    String contentId, {
    String? outputDir,
    String? sourceId,
  }) async {
    try {
      // 1. Check Primary (Elegant/Safe) Path
      final pdfDir = await _createPdfOutputDirectory(
        outputDir,
        contentId,
        sourceId,
      );

      // Cek apakah ada file PDF dengan prefix contentId
      // Check if PDF files with contentId prefix exist in primary location
      if (await _hasPdfInDirectory(pdfDir, contentId)) {
        _logger.d('PDF found in primary location: ${pdfDir.path}');
        return true;
      }

      // 2. Check Legacy Path (Original ID) if different
      // Only if we are using default storage (outputDir is null) and have a sourceId
      if (outputDir == null && sourceId != null) {
        final safeId = DownloadStorageUtils.getSafeContentId(contentId);
        if (safeId != contentId) {
          // Reconstruct legacy path manually to avoid _createPdfOutputDirectory using safeId
          final downloadsPath = await DirectoryUtils.getDownloadsDirectory();
          final legacyPdfDir = Directory(
            path.join(downloadsPath, 'nhasix', contentId, 'pdf'),
          );

          if (await _hasPdfInDirectory(legacyPdfDir, contentId)) {
            _logger.d('PDF found in legacy location: ${legacyPdfDir.path}');
            return true;
          }
        }
      }

      _logger.d(
        _getLocalized(
          'pdfExistsForContent',
          args: {'contentId': contentId, 'exists': 'false'},
          fallback: 'PdfConversionService: PDF NOT found for $contentId',
        ),
      );
      return false;
    } catch (e) {
      _logger.e(
        'PdfConversionService: Error checking PDF existence for $contentId',
        error: e,
      );
      return false;
    }
  }

  // Helper untuk cek existensi PDF dalam direktori
  Future<bool> _hasPdfInDirectory(Directory dir, String contentId) async {
    try {
      if (!await dir.exists()) return false;
      final files = await dir.list().toList();
      return files.any(
        (file) =>
            file is File &&
            path.basename(file.path).startsWith('${contentId}_') &&
            path.extension(file.path).toLowerCase() == '.pdf',
      );
    } catch (e) {
      _logger.e(
        'PdfConversionService: Error checking PDF existence for $contentId',
        error: e,
      );
      return false;
    }
  }

  // Dapatkan daftar file PDF untuk konten tertentu
  // Get list of PDF files for specific content
  ///
  // Returns: List path file PDF yang ditemukan
  Future<List<String>> getPdfPathsForContent(
    String contentId, {
    String? outputDir,
  }) async {
    try {
      // 1. Check Primary (Elegant/Safe) Path
      final pdfDir = await _createPdfOutputDirectory(outputDir, contentId);
      var pdfPaths = await _getPdfsInDirectory(pdfDir, contentId);

      // 2. Check Legacy Path (Original ID) if found nothing in primary
      if (pdfPaths.isEmpty && outputDir == null) {
        final safeId = DownloadStorageUtils.getSafeContentId(contentId);
        if (safeId != contentId) {
          final downloadsPath = await DirectoryUtils.getDownloadsDirectory();
          final legacyPdfDir = Directory(
            path.join(downloadsPath, 'nhasix', contentId, 'pdf'),
          );

          final legacyPaths = await _getPdfsInDirectory(
            legacyPdfDir,
            contentId,
          );
          if (legacyPaths.isNotEmpty) {
            _logger.d('PDFs found in legacy location: ${legacyPdfDir.path}');
            pdfPaths = legacyPaths;
          }
        }
      }

      // Sort berdasarkan nama file untuk urutan part yang benar
      // Sort by filename for correct part order
      pdfPaths.sort();

      _logger.d(
        _getLocalized(
          'pdfFoundFiles',
          args: {'contentId': contentId, 'count': pdfPaths.length},
          fallback:
              'PdfConversionService: Found ${pdfPaths.length} PDF file(s) for $contentId',
        ),
      );
      return pdfPaths;
    } catch (e) {
      _logger.e(
        'PdfConversionService: Error getting PDF paths for $contentId',
        error: e,
      );
      return [];
    }
  }

  // Helper untuk mendapatkan list PDF dalam direktori
  Future<List<String>> _getPdfsInDirectory(
    Directory dir,
    String contentId,
  ) async {
    final pdfPaths = <String>[];
    if (!await dir.exists()) return pdfPaths;

    final files = await dir.list().toList();
    for (final file in files) {
      if (file is File &&
          path.basename(file.path).startsWith('${contentId}_') &&
          path.extension(file.path).toLowerCase() == '.pdf') {
        pdfPaths.add(file.path);
      }
    }
    return pdfPaths;
  }

  // Delete all PDF files for specific content
  ///
  // Returns: true jika berhasil dihapus, false jika gagal
  Future<bool> deletePdfsForContent(
    String contentId, {
    String? outputDir,
  }) async {
    try {
      final pdfPaths = await getPdfPathsForContent(
        contentId,
        outputDir: outputDir,
      );

      if (pdfPaths.isEmpty) {
        _logger.d(
          'PdfConversionService: No PDF files to delete for $contentId',
        );
        return true;
      }

      // Hapus semua file PDF yang ditemukan
      // Delete all found PDF files
      for (final pdfPath in pdfPaths) {
        final file = File(pdfPath);
        if (await file.exists()) {
          await file.delete();
          _logger.d('PdfConversionService: Deleted PDF file: $pdfPath');
        }
      }

      _logger.i(
        _getLocalized(
          'pdfDeletedFiles',
          args: {'contentId': contentId, 'count': pdfPaths.length},
          fallback:
              'PdfConversionService: Successfully deleted ${pdfPaths.length} PDF file(s) for $contentId',
        ),
      );
      return true;
    } catch (e) {
      _logger.e(
        'PdfConversionService: Error deleting PDF files for $contentId',
        error: e,
      );
      return false;
    }
  }

  // Dapatkan total ukuran file PDF untuk konten tertentu
  // Get total file size of PDF files for specific content
  ///
  // Returns: Total ukuran dalam bytes
  Future<int> getTotalPdfSizeForContent(
    String contentId, {
    String? outputDir,
  }) async {
    try {
      final pdfPaths = await getPdfPathsForContent(
        contentId,
        outputDir: outputDir,
      );
      int totalSize = 0;

      // Hitung total ukuran semua file PDF
      // Calculate total size of all PDF files
      for (final pdfPath in pdfPaths) {
        final file = File(pdfPath);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      }

      _logger.d(
        _getLocalized(
          'pdfTotalSize',
          args: {'contentId': contentId, 'sizeBytes': totalSize},
          fallback:
              'PdfConversionService: Total PDF size for $contentId: $totalSize bytes',
        ),
      );
      return totalSize;
    } catch (e) {
      _logger.e(
        'PdfConversionService: Error calculating PDF size for $contentId',
        error: e,
      );
      return 0;
    }
  }

  // Format ukuran file untuk display ke user
  // Format file size for user display
  ///
  // Parameters:
  // - bytes: Ukuran dalam bytes
  ///
  // Returns: String format yang user-friendly (e.g., "2.5 MB")
  String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  // Cleanup file PDF lama berdasarkan umur atau kriteria tertentu
  // Cleanup old PDF files based on age or specific criteria
  ///
  // Parameters:
  // - maxAge: Umur maksimal file dalam hari (default: 30 hari)
  // - outputDir: Direktori yang akan dibersihkan (optional)
  ///
  // Returns: Jumlah file yang berhasil dihapus
  Future<int> cleanupOldPdfs({int maxAge = 30, String? outputDir}) async {
    try {
      final pdfDir = await _createPdfOutputDirectory(outputDir);
      final cutoffDate = DateTime.now().subtract(Duration(days: maxAge));
      int deletedCount = 0;

      _logger.i(
        _getLocalized(
          'pdfCleanupStarted',
          args: {'maxAge': maxAge},
          fallback:
              'PdfConversionService: Starting PDF cleanup, deleting files older than $maxAge days',
        ),
      );

      // Scan semua file PDF di direktori
      // Scan all PDF files in directory
      final files = await pdfDir.list().toList();

      for (final file in files) {
        if (file is File && path.extension(file.path).toLowerCase() == '.pdf') {
          final stat = await file.stat();

          // Hapus file jika lebih tua dari cutoff date
          // Delete file if older than cutoff date
          if (stat.modified.isBefore(cutoffDate)) {
            await file.delete();
            deletedCount++;
            _logger.d(
              'PdfConversionService: Deleted old PDF: ${path.basename(file.path)}',
            );
          }
        }
      }

      _logger.i(
        _getLocalized(
          'pdfCleanupCompleted',
          args: {'deletedCount': deletedCount},
          fallback:
              'PdfConversionService: Cleanup completed, deleted $deletedCount old PDF files',
        ),
      );
      return deletedCount;
    } catch (e) {
      _logger.e('PdfConversionService: Error during PDF cleanup', error: e);
      return 0;
    }
  }

  // Dapatkan statistik PDF di direktori output
  // Get PDF statistics in output directory
  ///
  // Returns: Map dengan informasi statistik
  Future<Map<String, dynamic>> getPdfStatistics({String? outputDir}) async {
    try {
      final pdfDir = await _createPdfOutputDirectory(outputDir);
      final files = await pdfDir.list().toList();

      int totalPdfFiles = 0;
      int totalSize = 0;
      final Map<String, int> contentCounts = {};

      // Analisis semua file PDF
      // Analyze all PDF files
      for (final file in files) {
        if (file is File && path.extension(file.path).toLowerCase() == '.pdf') {
          totalPdfFiles++;

          final fileSize = await file.length();
          totalSize += fileSize;

          // Extract content ID dari nama file
          // Extract content ID from filename
          final fileName = path.basenameWithoutExtension(file.path);
          final parts = fileName.split('_');
          if (parts.isNotEmpty) {
            final contentId = parts[0];
            contentCounts[contentId] = (contentCounts[contentId] ?? 0) + 1;
          }
        }
      }

      final statistics = {
        'totalPdfFiles': totalPdfFiles,
        'totalSizeBytes': totalSize,
        'totalSizeFormatted': formatFileSize(totalSize),
        'uniqueContents': contentCounts.length,
        'averageFilesPerContent': contentCounts.isNotEmpty
            ? (totalPdfFiles / contentCounts.length).round()
            : 0,
        'directoryPath': pdfDir.path,
      };

      _logger.d('PdfConversionService: PDF statistics - $statistics');
      return statistics;
    } catch (e) {
      _logger.e('PdfConversionService: Error getting PDF statistics', error: e);
      return {
        'totalPdfFiles': 0,
        'totalSizeBytes': 0,
        'totalSizeFormatted': '0 B',
        'uniqueContents': 0,
        'averageFilesPerContent': 0,
        'directoryPath': 'Unknown',
      };
    }
  }

  // Set localization callback for getting localized strings
  void setLocalizationCallback(
    String Function(String key, {Map<String, dynamic>? args}) localize,
  ) {
    _localize = localize;
    _logger.i('PdfConversionService: Localization callback set');
  }

  // Get localized string with fallback
  String _getLocalized(
    String key, {
    Map<String, dynamic>? args,
    String? fallback,
  }) {
    try {
      return _localize?.call(key, args: args) ?? fallback ?? key;
    } catch (e) {
      _logger.w('Failed to get localized string for key: $key, error: $e');
      return fallback ?? key;
    }
  }
}

// Result object untuk tracking hasil konversi PDF dengan multiple parts
// Result object for tracking PDF conversion result with multiple parts
class PdfConversionResult {
  const PdfConversionResult({
    required this.success,
    required this.pdfPaths,
    required this.pageCount,
    required this.partsCount,
    required this.fileSize,
    this.error,
  });

  // Apakah konversi berhasil
  // Whether conversion was successful
  final bool success;

  // List path file PDF yang dibuat (bisa multiple jika di-split)
  // List of PDF file paths created (can be multiple if split)
  final List<String> pdfPaths;

  // Total jumlah halaman dari semua PDF
  // Total number of pages across all PDFs
  final int pageCount;

  // Jumlah file PDF yang dibuat (1 untuk single file, >1 untuk split)
  // Number of PDF files created (1 for single file, >1 for split)
  final int partsCount;

  // Total ukuran file semua PDF dalam bytes
  // Total file size of all PDFs in bytes
  final int fileSize;

  // Error message jika konversi gagal
  // Error message if conversion failed
  final String? error;

  // Convenience getter untuk mendapatkan path PDF pertama
  // Convenience getter to get first PDF path
  String? get pdfPath => pdfPaths.isNotEmpty ? pdfPaths.first : null;

  // Apakah PDF di-split menjadi multiple files
  // Whether PDF was split into multiple files
  bool get isSplit => partsCount > 1;
}
