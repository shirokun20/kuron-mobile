import 'package:logger/logger.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/user_data_repository.dart';
import '../datasources/local/local_data_source.dart';
import '../models/download_status_model.dart';
import '../models/history_model.dart';
import '../../core/utils/storage_settings.dart';

// Implementation of UserDataRepository for local data management (simplified)
class UserDataRepositoryImpl implements UserDataRepository {
  UserDataRepositoryImpl({
    required this.localDataSource,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final LocalDataSource localDataSource;
  final Logger _logger;

  // ==================== FAVORITES ====================

  @override
  Future<void> addToFavorites({
    required String id,
    required String sourceId,
    required String coverUrl,
    String? title,
  }) async {
    try {
      _logger.i('Adding content $id to favorites');
      await localDataSource.addToFavorites(
        id: id,
        sourceId: sourceId,
        coverUrl: coverUrl,
        title: title,
      );
      _logger.d('Successfully added to favorites');
    } catch (e, stackTrace) {
      _logger.e('Failed to add to favorites', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> removeFromFavorites(String id, {String? sourceId}) async {
    try {
      _logger.i('Removing content $id from favorites');
      await localDataSource.removeFromFavorites(id, sourceId: sourceId);
      _logger.d('Successfully removed from favorites');
    } catch (e, stackTrace) {
      _logger.e('Failed to remove from favorites',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getFavorites({
    int page = 1,
    int limit = 20,
    String? collectionId,
  }) async {
    try {
      _logger.i('Getting favorites, page: $page, limit: $limit');
      final favorites = await localDataSource.getFavorites(
        page: page,
        limit: limit,
        collectionId: collectionId,
      );
      _logger.d('Retrieved ${favorites.length} favorites');
      return favorites;
    } catch (e, stackTrace) {
      _logger.e('Failed to get favorites', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<bool> isFavorite(String id, {String? sourceId}) async {
    try {
      return await localDataSource.isFavorited(id, sourceId: sourceId);
    } catch (e, stackTrace) {
      _logger.e('Failed to check if favorite',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  @override
  Future<int> getFavoritesCount({String? collectionId}) async {
    try {
      return await localDataSource.getFavoritesCount(
          collectionId: collectionId);
    } catch (e, stackTrace) {
      _logger.e('Failed to get favorites count',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllFavoritesForExport() async {
    try {
      _logger.i('Getting all favorites for export');
      // Query all favorites at once (no pagination for export)
      final favorites = await localDataSource.getAllFavorites();
      _logger.d('Retrieved ${favorites.length} favorites for export');
      return favorites;
    } catch (e, stackTrace) {
      _logger.e('Failed to get all favorites for export',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<FavoriteCollection> createFavoriteCollection({
    required String name,
    String? collectionId,
  }) async {
    try {
      return await localDataSource.createFavoriteCollection(
        name: name,
        collectionId: collectionId,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to create favorite collection',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> renameFavoriteCollection({
    required String collectionId,
    required String name,
  }) async {
    try {
      await localDataSource.renameFavoriteCollection(
        collectionId: collectionId,
        name: name,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to rename favorite collection',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> deleteFavoriteCollection(String collectionId) async {
    try {
      await localDataSource.deleteFavoriteCollection(collectionId);
    } catch (e, stackTrace) {
      _logger.e('Failed to delete favorite collection',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<FavoriteCollection>> getFavoriteCollections() async {
    try {
      return await localDataSource.getFavoriteCollections();
    } catch (e, stackTrace) {
      _logger.e('Failed to get favorite collections',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<List<String>> getFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
  }) async {
    try {
      return await localDataSource.getFavoriteCollectionIds(
        favoriteId: favoriteId,
        sourceId: sourceId,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to get favorite collection ids',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> setFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
    required List<String> collectionIds,
  }) async {
    try {
      await localDataSource.setFavoriteCollectionIds(
        favoriteId: favoriteId,
        sourceId: sourceId,
        collectionIds: collectionIds,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to set favorite collection ids',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<FavoriteCollection>> getFavoriteCollectionsForExport() async {
    return getFavoriteCollections();
  }

  @override
  Future<List<Map<String, dynamic>>>
      getFavoriteCollectionMembershipsForExport() async {
    try {
      return await localDataSource.getFavoriteCollectionMembershipsForExport();
    } catch (e, stackTrace) {
      _logger.e('Failed to export favorite collection memberships',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // ==================== CONTENT TAGS (recommendation seeds) ====================

  @override
  Future<void> saveContentTags(List<ContentTag> tags) async {
    try {
      await localDataSource.saveContentTags(tags);
    } catch (e, stackTrace) {
      _logger.e('Failed to save content tags',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<Set<String>> getTagNamesForContent(
    String contentId, {
    String? sourceId,
  }) async {
    return localDataSource.getTagNamesForContent(contentId,
        sourceId: sourceId);
  }

  // ==================== RECOMMENDATION HISTORY ====================

  @override
  Future<void> recordRecommendationShown(String contentId,
      {String? sourceId}) async {
    await localDataSource.recordRecommendationShown(contentId, sourceId);
  }

  @override
  Future<void> recordRecommendationTapped(String contentId,
      {String? sourceId}) async {
    await localDataSource.recordRecommendationTapped(contentId, sourceId);
  }

  @override
  Future<void> recordRecommendationDismissed(String contentId,
      {String? sourceId}) async {
    await localDataSource.recordRecommendationDismissed(contentId, sourceId);
  }

  @override
  Future<List<Map<String, dynamic>>> getRecommendationHistoryRows() async {
    return localDataSource.getRecommendationHistoryRows();
  }

  // ==================== DOWNLOADS ====================

  @override
  Future<void> saveDownloadStatus(DownloadStatus status) async {
    try {
      _logger.d('Saving download status for: ${status.contentId}');

      // Create model with additional info if available
      final statusModel = DownloadStatusModel.fromEntity(status);
      await localDataSource.saveDownloadStatus(statusModel);
    } catch (e, stackTrace) {
      _logger.e('Failed to save download status',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<DownloadStatus?> getDownloadStatus(String id) async {
    try {
      final statusModel = await localDataSource.getDownloadStatus(id);
      return statusModel?.toEntity();
    } catch (e, stackTrace) {
      _logger.e('Failed to get download status',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<List<DownloadStatus>> getAllDownloads({
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    try {
      // _logger.i('Getting all downloads - state: $state, limit: $limit, offset: $offset, orderBy: $orderBy');

      final statusModels = await localDataSource.getAllDownloads(
        state: state,
        sourceId: sourceId,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        descending: descending,
      );

      final downloads = statusModels.map((model) => model.toEntity()).toList();
      // _logger.d('Retrieved ${downloads.length} downloads');
      return downloads;
    } catch (e, stackTrace) {
      _logger.e('Failed to get all downloads',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> deleteDownloadStatus(String id) async {
    try {
      _logger.i('Deleting download status: $id');
      await localDataSource.deleteDownloadStatus(id);
      _logger.d('Download status deleted');
    } catch (e, stackTrace) {
      _logger.e('Failed to delete download status',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<int> getDownloadsCount(
      {DownloadState? state, String? sourceId}) async {
    try {
      return await localDataSource.getDownloadsCount(
          state: state, sourceId: sourceId);
    } catch (e, stackTrace) {
      _logger.e('Failed to get downloads count',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  @override
  Future<int> getTotalDownloadSize(
      {DownloadState? state, String? sourceId}) async {
    try {
      return await localDataSource.getTotalDownloadSize(
          state: state, sourceId: sourceId);
    } catch (e, stackTrace) {
      _logger.e('Failed to get total download size',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchDownloads({
    required String query,
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    try {
      _logger.i(
          'Searching downloads for query: $query, limit: $limit, offset: $offset');
      return await localDataSource.searchDownloads(
        query: query,
        state: state,
        sourceId: sourceId,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        descending: descending,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to search downloads', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<int> getSearchCount({
    required String query,
    DownloadState? state,
    String? sourceId,
  }) async {
    try {
      return await localDataSource.getSearchCount(
        query: query,
        state: state,
        sourceId: sourceId,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to get search count', error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  @override
  Future<int> getSearchDownloadSize({
    required String query,
    DownloadState? state,
    String? sourceId,
  }) async {
    try {
      return await localDataSource.getSearchDownloadSize(
        query: query,
        state: state,
        sourceId: sourceId,
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to get search download size',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  // ==================== HISTORY ====================

  @override
  Future<void> saveHistory(History history) async {
    try {
      _logger.d('Saving history for: ${history.contentId}');

      // Create model with additional info if available
      final historyModel = HistoryModel.fromEntity(
        history,
        coverUrl: history.coverUrl,
        title: history.title,
      );
      await localDataSource.saveHistory(historyModel);
    } catch (e, stackTrace) {
      _logger.e('Failed to save history', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<History>> getHistory({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      _logger.i('Getting history - page: $page, limit: $limit');

      final historyModels = await localDataSource.getAllHistory(
        page: page,
        limit: limit,
      );

      final history = historyModels.map((model) => model.toEntity()).toList();
      _logger.d('Retrieved ${history.length} history entries');
      return history;
    } catch (e, stackTrace) {
      _logger.e('Failed to get history', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<History?> getHistoryEntry(String id) async {
    try {
      final historyModel = await localDataSource.getHistory(id);
      _logger
          .w('isi file dari getHistoryEntry db: ${historyModel?.toEntity()}');
      return historyModel?.toEntity();
    } catch (e, stackTrace) {
      _logger.e('Failed to get history entry',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<History?> getChapterHistoryEntry(String id, String chapterId) async {
    try {
      final historyModel =
          await localDataSource.getChapterHistory(id, chapterId);
      return historyModel?.toEntity();
    } catch (e, stackTrace) {
      _logger.e('Failed to get chapter history entry',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<List<History>> getAllChapterHistory(String id) async {
    try {
      final historyModels = await localDataSource.getContentChaptersHistory(id);
      return historyModels.map((model) => model.toEntity()).toList();
    } catch (e, stackTrace) {
      _logger.e('Failed to get all chapter history',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> removeFromHistory(String id) async {
    try {
      _logger.i('Removing from history: $id');
      await localDataSource.deleteHistory(id);
      _logger.d('Removed from history');
    } catch (e, stackTrace) {
      _logger.e('Failed to remove from history',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      _logger.i('Clearing all history');
      await localDataSource.clearHistory();
      _logger.d('History cleared');
    } catch (e, stackTrace) {
      _logger.e('Failed to clear history', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<int> getHistoryCount() async {
    try {
      return await localDataSource.getHistoryCount();
    } catch (e, stackTrace) {
      _logger.e('Failed to get history count',
          error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  // ==================== PREFERENCES ====================

  @override
  Future<void> saveUserPreferences(UserPreferences preferences) async {
    try {
      _logger.i('Saving user preferences');
      await localDataSource.saveUserPreferences(preferences);
      _logger.d('User preferences saved');
    } catch (e, stackTrace) {
      _logger.e('Failed to save user preferences',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<UserPreferences> getUserPreferences() async {
    try {
      // Get preferences from local DB
      var userPrefs = await localDataSource.getUserPreferences();

      // Ensure customStorageRoot is synced with StorageSettings (Source of Truth)
      try {
        final customRoot = await StorageSettings.getCustomRootPath();
        if (customRoot != null && customRoot.isNotEmpty) {
          if (userPrefs.customStorageRoot != customRoot) {
            _logger.d(
                'Syncing customStorageRoot from StorageSettings: $customRoot');
            userPrefs = userPrefs.copyWith(customStorageRoot: customRoot);

            // Optional: Sync back to DB if needed, but for now just returning correct value is enough
            // saveUserPreferences(userPrefs);
          }
        }
      } catch (e) {
        _logger.w('Failed to sync customStorageRoot from StorageSettings: $e');
      }

      return userPrefs;
    } catch (e, stackTrace) {
      _logger.e('Failed to get user preferences',
          error: e, stackTrace: stackTrace);
      // ignore: prefer_const_constructors
      return UserPreferences(); // Return default preferences
    }
  }

  @override
  Future<void> savePreference(String key, String value) async {
    try {
      _logger.d('Saving preference: $key = $value');
      await localDataSource.savePreference(key, value);
    } catch (e, stackTrace) {
      _logger.e('Failed to save preference', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<String?> getPreference(String key) async {
    try {
      return await localDataSource.getPreference(key);
    } catch (e, stackTrace) {
      _logger.e('Failed to get preference', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // ==================== SEARCH HISTORY ====================

  @override
  Future<void> addSearchHistory(String query) async {
    try {
      _logger.d('Adding search history: $query');
      await localDataSource.addSearchHistory(query);
    } catch (e, stackTrace) {
      _logger.e('Failed to add search history',
          error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<List<String>> getSearchHistory({int limit = 20}) async {
    try {
      return await localDataSource.getSearchHistory(limit: limit);
    } catch (e, stackTrace) {
      _logger.e('Failed to get search history',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> clearSearchHistory() async {
    try {
      _logger.i('Clearing search history');
      await localDataSource.clearSearchHistory();
      _logger.d('Search history cleared');
    } catch (e, stackTrace) {
      _logger.e('Failed to clear search history',
          error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> deleteSearchHistory(String query) async {
    try {
      _logger.d('Deleting search history: $query');
      await localDataSource.deleteSearchHistory(query);
    } catch (e, stackTrace) {
      _logger.e('Failed to delete search history',
          error: e, stackTrace: stackTrace);
    }
  }

  // ==================== UTILITIES ====================

  @override
  Future<Map<String, int>> getDatabaseStats() async {
    try {
      return await localDataSource.getDatabaseStats();
    } catch (e, stackTrace) {
      _logger.e('Failed to get database stats',
          error: e, stackTrace: stackTrace);
      return {};
    }
  }

  @override
  Future<void> cleanupOldData() async {
    try {
      _logger.i('Cleaning up old data');
      await localDataSource.cleanupOldData();
      _logger.d('Old data cleaned up');
    } catch (e, stackTrace) {
      _logger.e('Failed to cleanup old data', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> clearAllData() async {
    try {
      _logger.i('Clearing all data');
      await localDataSource.clearAllData();
      _logger.d('All data cleared');
    } catch (e, stackTrace) {
      _logger.e('Failed to clear all data', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ==================== SEARCH STATE PERSISTENCE ====================

  @override
  Future<void> saveSearchFilter(String sourceId, SearchFilter filter) async {
    try {
      _logger.d('Saving search filter state for $sourceId');
      await localDataSource.saveSearchFilter(sourceId, filter.toJson());
      _logger.d('Search filter state saved');
    } catch (e, stackTrace) {
      _logger.e('Failed to save search filter',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<SearchFilter?> getLastSearchFilter(String sourceId) async {
    try {
      final filterData = await localDataSource.getLastSearchFilter(sourceId);
      if (filterData != null) {
        return SearchFilter.fromJson(filterData);
      }
      return null;
    } catch (e, stackTrace) {
      _logger.e('Failed to get last search filter',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<void> clearSearchFilter(String sourceId) async {
    try {
      _logger.d('Clearing search filter state for $sourceId');
      await localDataSource.removeLastSearchFilter(sourceId);
      _logger.d('Search filter state cleared');
    } catch (e, stackTrace) {
      _logger.e('Failed to clear search filter',
          error: e, stackTrace: stackTrace);
    }
  }

  // ==================== SORTING PREFERENCES ====================

  @override
  Future<void> saveSortingPreference(SortOption sortBy) async {
    try {
      _logger.d('Saving sorting preference: ${sortBy.name}');
      await localDataSource.savePreference('sorting_preference', sortBy.name);
      _logger.d('Sorting preference saved');
    } catch (e, stackTrace) {
      _logger.e('Failed to save sorting preference',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<SortOption> getSortingPreference() async {
    try {
      final sortName =
          await localDataSource.getPreference('sorting_preference');
      if (sortName != null) {
        return SortOption.values.firstWhere(
          (e) => e.name == sortName,
          orElse: () => SortOption.newest,
        );
      }
      return SortOption.newest; // Default sort option
    } catch (e, stackTrace) {
      _logger.e('Failed to get sorting preference',
          error: e, stackTrace: stackTrace);
      return SortOption.newest; // Default sort option
    }
  }

  // ==================== OFFLINE SYNC ====================

  @override
  Future<void> syncOfflineData() async {
    try {
      _logger.i('Starting offline data sync');

      final pendingItems = await getPendingSyncItems();
      if (pendingItems.isEmpty) {
        _logger.d('No pending sync items found');
        return;
      }

      _logger.i('Found ${pendingItems.length} items to sync');

      // For now, just clear the sync queue since we don't have a remote server
      // In a real implementation, this would sync with a remote server
      await clearSyncQueue();

      _logger.i('Offline data sync completed');
    } catch (e, stackTrace) {
      _logger.e('Failed to sync offline data',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> markForSync(
      String dataType, String operation, String contentId) async {
    try {
      _logger.d('Marking for sync: $dataType $operation $contentId');

      // Store sync operation in preferences for simplicity
      // In a real implementation, this would use a dedicated sync table
      final syncData = {
        'dataType': dataType,
        'operation': operation,
        'contentId': contentId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await localDataSource.savePreference(
        'sync_${dataType}_${contentId}_$operation',
        syncData.toString(),
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to mark for sync', error: e, stackTrace: stackTrace);
      // Don't rethrow - sync marking is not critical
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    try {
      // For simplicity, return empty list
      // In a real implementation, this would query a sync table
      return [];
    } catch (e, stackTrace) {
      _logger.e('Failed to get pending sync items',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> clearSyncQueue() async {
    try {
      _logger.d('Clearing sync queue');
      // For simplicity, do nothing
      // In a real implementation, this would clear the sync table
    } catch (e, stackTrace) {
      _logger.e('Failed to clear sync queue', error: e, stackTrace: stackTrace);
    }
  }
}
