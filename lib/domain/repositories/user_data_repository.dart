import '../entities/entities.dart';

abstract class UserDataRepository {
  // ==================== FAVORITES ====================

  Future<void> addToFavorites({
    required String id,
    required String sourceId,
    required String coverUrl,
    String? title,
  });

  Future<void> removeFromFavorites(String id, {String? sourceId});

  Future<List<Map<String, dynamic>>> getFavorites({
    int page = 1,
    int limit = 20,
    String? collectionId,
  });

  Future<bool> isFavorite(String id, {String? sourceId});

  Future<int> getFavoritesCount({String? collectionId});

  Future<List<Map<String, dynamic>>> getAllFavoritesForExport();

  // ==================== CONTENT TAGS (recommendation seeds) ====================

  /// Replace all tag rows for one content. Best-effort derived data.
  Future<void> saveContentTags(List<ContentTag> tags);

  /// Tag names stored for one content (empty set when none/unknown).
  Future<Set<String>> getTagNamesForContent(
    String contentId, {
    String? sourceId,
  });

  // ==================== RECOMMENDATION HISTORY ====================

  /// Shown/tapped/dismissed bookkeeping for recommendation dedup windows.
  /// Recording never throws — failures are logged and swallowed.
  Future<void> recordRecommendationShown(String contentId, {String? sourceId});
  Future<void> recordRecommendationTapped(String contentId, {String? sourceId});
  Future<void> recordRecommendationDismissed(String contentId,
      {String? sourceId});

  /// Raw dedup rows (content_id, source_id, shown_at, tapped_at,
  /// dismissed, dismissed_at). Small bounded table.
  Future<List<Map<String, dynamic>>> getRecommendationHistoryRows();

  Future<FavoriteCollection> createFavoriteCollection({
    required String name,
    String? collectionId,
  });

  Future<void> renameFavoriteCollection({
    required String collectionId,
    required String name,
  });

  Future<void> deleteFavoriteCollection(String collectionId);

  Future<List<FavoriteCollection>> getFavoriteCollections();

  Future<List<String>> getFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
  });

  Future<void> setFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
    required List<String> collectionIds,
  });

  Future<List<FavoriteCollection>> getFavoriteCollectionsForExport();

  Future<List<Map<String, dynamic>>>
      getFavoriteCollectionMembershipsForExport();

  // ==================== DOWNLOADS ====================

  Future<void> saveDownloadStatus(DownloadStatus status);

  Future<DownloadStatus?> getDownloadStatus(String id);

  Future<List<DownloadStatus>> getAllDownloads({
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  });

  Future<void> deleteDownloadStatus(String id);

  Future<int> getDownloadsCount({
    DownloadState? state,
    String? sourceId,
  });

  Future<int> getTotalDownloadSize({
    DownloadState? state,
    String? sourceId,
  });

  Future<List<Map<String, dynamic>>> searchDownloads({
    required String query,
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  });

  Future<int> getSearchCount({
    required String query,
    DownloadState? state,
    String? sourceId,
  });

  Future<int> getSearchDownloadSize({
    required String query,
    DownloadState? state,
    String? sourceId,
  });

  // ==================== HISTORY ====================

  Future<void> saveHistory(History history);

  Future<List<History>> getHistory({
    int page = 1,
    int limit = 50,
  });

  Future<History?> getHistoryEntry(String id);

  Future<History?> getChapterHistoryEntry(String id, String chapterId);

  Future<List<History>> getAllChapterHistory(String id);

  Future<void> removeFromHistory(String id);

  Future<void> clearHistory();

  Future<int> getHistoryCount();

  // ==================== PREFERENCES ====================

  Future<void> saveUserPreferences(UserPreferences preferences);

  Future<UserPreferences> getUserPreferences();

  Future<void> savePreference(String key, String value);

  Future<String?> getPreference(String key);

  // ==================== SEARCH HISTORY ====================

  Future<void> addSearchHistory(String query);

  Future<List<String>> getSearchHistory({int limit = 20});

  Future<void> clearSearchHistory();

  Future<void> deleteSearchHistory(String query);

  // ==================== SEARCH STATE PERSISTENCE ====================

  Future<void> saveSearchFilter(String sourceId, SearchFilter filter);

  Future<SearchFilter?> getLastSearchFilter(String sourceId);

  Future<void> clearSearchFilter(String sourceId);

  // ==================== SORTING PREFERENCES ====================

  Future<void> saveSortingPreference(SortOption sortBy);

  Future<SortOption> getSortingPreference();

  // ==================== OFFLINE SYNC ====================

  Future<void> syncOfflineData();

  Future<void> markForSync(String dataType, String operation, String contentId);

  Future<List<Map<String, dynamic>>> getPendingSyncItems();

  Future<void> clearSyncQueue();

  // ==================== UTILITIES ====================

  Future<Map<String, int>> getDatabaseStats();

  Future<void> cleanupOldData();

  Future<void> clearAllData();
}
