import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/pdf_conversion_queue_manager.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/usecases/reader/get_reader_position_usecase.dart';

class OfflineSeriesDetailService {
  final OfflineContentManager _offlineManager;
  final GetReaderPositionUseCase _getReaderPositionUseCase;
  final PdfConversionQueueManager _queueManager;
  final RemoteConfigService _remoteConfigService;
  final Logger _logger;

  OfflineSeriesDetailService({
    required this._offlineManager,
    required this._getReaderPositionUseCase,
    required this._queueManager,
    required this._remoteConfigService,
    required this._logger,
  });

  Future<int> calculateDirectorySize(String path) async {
    int size = 0;
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (_) {}
    return size;
  }

  Future<String?> findPdfPath(String contentId) async {
    try {
      final firstImagePath =
          await _offlineManager.getOfflineFirstImagePath(contentId);
      if (firstImagePath != null) {
        final contentDir = File(firstImagePath).parent.parent.path;
        final pdfDir = Directory(p.join(contentDir, 'pdf'));
        if (await pdfDir.exists()) {
          final files = await pdfDir.list().toList();
          final pdfFile = files.cast<File?>().firstWhere(
            (f) => f?.path.toLowerCase().endsWith('.pdf') ?? false,
            orElse: () => null,
          );
          return pdfFile?.path;
        }
      }
    } catch (e) {
      _logger.e('Error finding PDF path: $e');
    }
    return null;
  }

  Future<bool> checkPdfExists(String contentId) async {
    final path = await findPdfPath(contentId);
    return path != null;
  }

  Future<double?> getReadingProgress(String contentId) async {
    try {
      final position = await _getReaderPositionUseCase(contentId);
      if (position != null && position.totalPages > 0) {
        return (position.currentPage / position.totalPages).clamp(0.0, 1.0);
      }
    } catch (_) {}
    return null;
  }

  /// Page-semantic read state (matches legacy rules): read when
  /// `currentPage >= totalPages - 1`, reading when `currentPage > 1`.
  /// Ratio-based [getReadingProgress] stays for progress bars.
  Future<({bool isRead, bool isReading, double? progress})> getReadingState(
      String contentId) async {
    try {
      final position = await _getReaderPositionUseCase(contentId);
      if (position != null && position.totalPages > 0) {
        final isRead = position.currentPage >= position.totalPages - 1;
        final progress =
            (position.currentPage / position.totalPages).clamp(0.0, 1.0);
        return (
          isRead: isRead,
          isReading: !isRead && position.currentPage > 1,
          progress: progress,
        );
      }
    } catch (_) {}
    return (isRead: false, isReading: false, progress: null);
  }

  bool isPdfGenerationEnabled(String sourceId) {
    return _remoteConfigService.isFeatureEnabled(
      sourceId,
      (f) => f.generatePdf,
    );
  }

  Future<void> queuePdfConversion({
    required String contentId,
    required String title,
    required List<String> imagePaths,
    required String sourceId,
  }) async {
    await _queueManager.queueConversion(
      contentId: contentId,
      title: title,
      imagePaths: imagePaths,
      sourceId: sourceId,
    );
  }

  Future<List<String>> getOfflineContentIds() =>
      _offlineManager.getOfflineContentIds();

  Future<Content?> createOfflineContent(String id) =>
      _offlineManager.createOfflineContent(id);

  Future<Content?> getOfflineContent(String id) =>
      _offlineManager.createOfflineContent(id);

  Future<String?> getOfflineContentPath(String id) =>
      _offlineManager.getOfflineContentPath(id);

  Future<String?> getOfflineFirstImagePath(String id) =>
      _offlineManager.getOfflineFirstImagePath(id);

  Future<List<String>> getOfflineImageUrls(String id) =>
      _offlineManager.getOfflineImageUrls(id);
}
