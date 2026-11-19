import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/utils/native_theme_helper.dart';

/// Thrown when a native PDF conversion is cancelled via [CancelToken] or
/// [NativePdfService.cancelConvertPdf]. Callers must swallow this silently
/// (no error notification) — cancellation is user intent, not failure.
class PdfConversionCancelledException implements Exception {
  const PdfConversionCancelledException([
    this.message = 'PDF conversion cancelled',
  ]);

  final String message;

  @override
  String toString() => 'PdfConversionCancelledException: $message';
}

class NativePdfService {
  final Logger _logger = getIt<Logger>();

  // Generate PDF using native high-performance implementation
  ///
  // This is ~5x faster than Flutter for large webtoon sets
  ///
  // **Parameters**:
  // - [imagePaths]: List of absolute paths to image files
  // - [outputPath]: Absolute path where PDF should be saved
  // - [title]: Title for the PDF
  // - [onProgress]: Callback for progress updates (progress: 0-100, message: status)
  // - [cancelToken]: Optional Dio token. Cancelling it routes a
  //   `cancelConvertPdf` call to the native side, which stops rendering at
  //   the next page boundary and completes the pending channel call with
  //   `PDF_CONVERSION_CANCELLED` instead of hanging until full conversion.
  ///
  // **Returns**:
  // - Map with: `success`, `pdfPath`, `pageCount`, `fileSize`
  ///
  // **Throws**: [PdfConversionCancelledException] when [cancelToken] is
  // cancelled. Callers must not surface this as an error.
  Future<Map<String, dynamic>> generatePdfNative({
    required List<String> imagePaths,
    required String outputPath,
    required String title,
    required Function(int progress, String message) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const PdfConversionCancelledException(
        'PDF conversion cancelled before start',
      );
    }

    // The convertImagesToPdf channel call cannot be aborted mid-flight, so a
    // separate cancelConvertPdf call tells Kotlin to stop at the next page
    // boundary (mirrors request_deduplication_service token wiring).
    cancelToken?.whenCancel.then((_) => cancelConvertPdf()).ignore();

    try {
      _logger.i('🚀 Calling native PDF generator (via KuronNative)...');
      _logger.i('Images: ${imagePaths.length} files');

      final result = await KuronNative.instance.convertImagesToPdf(
        imagePaths: imagePaths,
        outputPath: outputPath,
        onProgress: onProgress,
      );

      if (result == null) {
        throw Exception('Native PDF generation returned null');
      }

      _logger.i('✅ Native PDF completed: ${result['pageCount']} pages');

      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PDF_CONVERSION_CANCELLED' ||
          cancelToken?.isCancelled == true) {
        _logger.i('🚫 Native PDF conversion cancelled');
        throw PdfConversionCancelledException(
          e.message ?? 'PDF conversion cancelled',
        );
      }
      _logger.e('Native PDF generation failed: $e');
      throw Exception('Native PDF generation failed: $e');
    } catch (e) {
      if (e is PdfConversionCancelledException ||
          cancelToken?.isCancelled == true) {
        _logger.i('🚫 Native PDF conversion cancelled');
        throw const PdfConversionCancelledException();
      }
      _logger.e('Native PDF generation failed: $e');
      throw Exception('Native PDF generation failed: $e');
    }
  }

  /// Best-effort cancel of in-flight native PDF conversion(s).
  ///
  /// When [outputPath] is given only that conversion is cancelled, otherwise
  /// every in-flight PDF convert is aborted. Cancelled converts complete
  /// with `PDF_CONVERSION_CANCELLED` so [generatePdfNative] unblocks
  /// instead of hanging until the full conversion finishes.
  Future<void> cancelConvertPdf({String? outputPath}) {
    return KuronNative.instance.cancelConvertPdf(outputPath: outputPath);
  }

  // Open PDF in native high-performance reader (Activity)
  ///
  // This launches a separate Android Activity for 120Hz smooth reading
  Future<void> openPdf({
    required String path,
    required String title,
    int startPage = 0,
  }) async {
    try {
      await KuronNative.instance.openPdf(
        filePath: path,
        title: title,
        startPage: startPage,
        backgroundColor: NativeThemeHelper.readerBackgroundColorHex,
        textColor: NativeThemeHelper.readerTextColorHex,
      );
    } catch (e) {
      _logger.e('Failed to open PDF via KuronNative: $e');
      throw Exception('Failed to open PDF: $e');
    }
  }
}
