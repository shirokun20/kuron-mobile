import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import '../../domain/entities/reader_position.dart';
import '../../domain/repositories/reader_repository.dart';
import '../datasources/local/local_data_source.dart';
import '../models/reader_position_model.dart';

// Implementation of ReaderRepository for local storage
// Handles reader position persistence using SQLite database
class ReaderRepositoryImpl implements ReaderRepository {
  final LocalDataSource _localDataSource;
  final Logger _logger = getIt<Logger>();

  ReaderRepositoryImpl({
    required this._localDataSource,
  });

  @override
  Future<void> saveReaderPosition(ReaderPosition position) async {
    try {
      final model = ReaderPositionModel.fromEntity(position);
      await _localDataSource.saveReaderPosition(model);
      _logger.d(
          'Saved reader position for ${position.contentId} at page ${position.currentPage}');
    } catch (e) {
      _logger.e('Failed to save reader position: $e');
      rethrow;
    }
  }

  @override
  Future<ReaderPosition?> getReaderPosition(String contentId) async {
    try {
      final model = await _localDataSource.getReaderPosition(contentId);
      if (model == null) return null;

      final position = model.toEntity();
      _logger.d(
          'Retrieved reader position for $contentId at page ${position.currentPage}');
      return position;
    } catch (e) {
      _logger.e('Failed to get reader position for $contentId: $e');
      return null;
    }
  }

  @override
  Future<List<ReaderPosition>> getAllReaderPositions({
    int limit = 50,
    int page = 1,
  }) async {
    try {
      final models = await _localDataSource.getAllReaderPositions(
        limit: limit,
        page: page,
      );

      final positions = models.map((model) => model.toEntity()).toList();
      _logger.d('Retrieved ${positions.length} reader positions');
      return positions;
    } catch (e) {
      _logger.e('Failed to get all reader positions: $e');
      return [];
    }
  }

  @override
  Future<void> deleteReaderPosition(String contentId) async {
    try {
      await _localDataSource.deleteReaderPosition(contentId);
      _logger.d('Deleted reader position for $contentId');
    } catch (e) {
      _logger.e('Failed to delete reader position for $contentId: $e');
      rethrow;
    }
  }

  @override
  Future<void> clearAllReaderPositions() async {
    try {
      await _localDataSource.clearAllReaderPositions();
      _logger.d('Cleared all reader positions');
    } catch (e) {
      _logger.e('Failed to clear all reader positions: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateReadingTime(
      String contentId, int additionalMinutes) async {
    try {
      // Get current position
      final currentPosition = await getReaderPosition(contentId);
      if (currentPosition == null) {
        _logger
            .w('Cannot update reading time: no position found for $contentId');
        return;
      }

      // Update with additional reading time
      final updatedPosition = currentPosition.copyWith(
        readingTimeMinutes:
            currentPosition.readingTimeMinutes + additionalMinutes,
        lastAccessed: DateTime.now(),
      );

      await saveReaderPosition(updatedPosition);
      _logger.d(
          'Updated reading time for $contentId: +${additionalMinutes}m (total: ${updatedPosition.readingTimeMinutes}m)');
    } catch (e) {
      _logger.e('Failed to update reading time for $contentId: $e');
      rethrow;
    }
  }

  @override
  Future<List<String>> getRecentlyReadContentIds({int limit = 10}) async {
    try {
      final models = await _localDataSource.getAllReaderPositions(
        limit: limit,
        page: 1,
      );

      final contentIds = models.map((model) => model.contentId).toList();
      _logger.d('Retrieved ${contentIds.length} recently read content IDs');
      return contentIds;
    } catch (e) {
      _logger.e('Failed to get recently read content IDs: $e');
      return [];
    }
  }

  @override
  Future<bool> hasReaderPosition(String contentId) async {
    try {
      final position = await _localDataSource.getReaderPosition(contentId);
      return position != null;
    } catch (e) {
      _logger.e('Failed to check reader position for $contentId: $e');
      return false;
    }
  }

  @override
  Future<void> updateReaderPage({
    required String contentId,
    required int currentPage,
    required int totalPages,
  }) async {
    try {
      // Get existing position or create new one
      final ReaderPosition position = await getReaderPosition(contentId) ??
          ReaderPosition.initial(
            contentId: contentId,
            totalPages: totalPages,
          );

      // Update with new page
      final updatedPosition = position.copyWith(
        currentPage: currentPage,
        totalPages: totalPages,
        lastAccessed: DateTime.now(),
        readingProgress:
            ReaderPosition.calculateProgress(currentPage, totalPages),
      );

      await saveReaderPosition(updatedPosition);
      _logger
          .d('Updated reader page for $contentId to $currentPage/$totalPages');
    } catch (e) {
      _logger.e('Failed to update reader page for $contentId: $e');
      rethrow;
    }
  }
}
