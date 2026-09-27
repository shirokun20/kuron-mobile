import 'dart:io';
import 'dart:math';

import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/offline_content_manager.dart';
import '../../../core/utils/download_storage_utils.dart';
import 'package:kuron_core/kuron_core.dart';
import '../../../domain/entities/download_status.dart';
import '../../../domain/repositories/user_data_repository.dart';
import '../../../domain/repositories/reader_repository.dart';
import '../../../core/di/service_locator.dart';

import '../base/base_cubit.dart';
import '../../models/content_group.dart';
import '../../widgets/content_list_widget.dart';
import '../../../core/utils/title_parser_utils.dart';

part 'offline_search_state.dart';

class OfflineSearchCubit extends BaseCubit<OfflineSearchState> {
  OfflineSearchCubit({
    required OfflineContentManager offlineContentManager,
    required UserDataRepository userDataRepository,
    required SharedPreferences prefs,
    required super.logger,
  })  : _offlineContentManager = offlineContentManager,
        _userDataRepository = userDataRepository,
        _prefs = prefs,
        super(
          initialState: const OfflineSearchInitial(),
        );

  final OfflineContentManager _offlineContentManager;
  final UserDataRepository _userDataRepository;
  final SharedPreferences _prefs;
  final Map<String, int> _sizeBytesByContentId = {};

  /// Groups consumed from the front of the full grouped list (pagination
  /// cursor). May exceed visible results when groups are dropped for
  /// missing covers; reset on every fresh (non-loadMore) load.
  int _consumedGroupCount = 0;
  static const String _keySelectedSourceFilter =
      'offline_selected_source_filter';
  static const String _keyIsListMode = 'offline_is_list_mode';

  /// Groups shown per page (group-level pagination).
  static const int groupPageSize = 20;

  /// Max rows fetched per load for in-memory group-then-slice. Offline
  /// libraries are typically < 2k rows; a warning is logged when truncated.
  static const int fetchLimit = 10000;

  Future<int> _getDirectorySize(Directory directory) async {
    int size = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      logInfo('Error calculating directory size: $e');
    }
    return size;
  }

  Future<Map<String, String>> _calculateContentSizes(
      List<Content> contents) async {
    final sizes = <String, String>{};

    for (final content in contents) {
      try {
        // Use the centralized directory lookup which handles Elegant IDs
        final dirPath = await DownloadStorageUtils.getContentDirectory(
            content.id,
            sourceId: content.sourceId);

        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final sizeInBytes = await _getDirectorySize(dir);
          sizes[content.id] =
              OfflineContentManager.formatStorageSize(sizeInBytes);
        } else {
          if (content.imageUrls.isNotEmpty) {
            final firstImagePath = content.imageUrls.first;
            final file = File(firstImagePath);
            final parentDir = file.parent;
            if (await parentDir.exists()) {
              final sizeInBytes = await _getDirectorySize(parentDir);
              sizes[content.id] =
                  OfflineContentManager.formatStorageSize(sizeInBytes);
            }
          }
        }
      } catch (e) {
        logInfo('Unable to calculate size for content ${content.id}: $e');
      }
    }

    return sizes;
  }

  Future<void> filterBySource(String? sourceId) async {
    logInfo('Filtering offline content by source: $sourceId');

    if (sourceId != null) {
      await _prefs.setString(_keySelectedSourceFilter, sourceId);
    } else {
      await _prefs.remove(_keySelectedSourceFilter);
    }

    final currentState = state;
    String currentQuery = '';

    if (currentState is OfflineSearchLoaded) {
      currentQuery = currentState.query;
      emit(currentState.copyWith(
        selectedSourceId: sourceId,
        clearSourceId: sourceId == null,
        // Reset pagination when filter changes
        results: [],
        totalResults: 0,
        offlineSizes: {},
        storageUsage: 0,
        formattedStorageUsage: '0 B',
        currentPage: 1,
        totalPages: 1,
        hasMore: false,
      ));
    } else if (currentState is OfflineSearchEmpty) {
      currentQuery = currentState.query;
    } else if (currentState is OfflineSearchError) {
      currentQuery = currentState.query;
    }

    if (currentQuery.isNotEmpty) {
      await searchOfflineContent(currentQuery, sourceId: sourceId);
    } else {
      await getAllOfflineContent(sourceId: sourceId);
    }
  }

  Future<void> changeSorting(
      {required String orderBy, required bool descending}) async {
    final currentState = state;
    if (currentState is! OfflineSearchLoaded) return;

    emit(currentState.copyWith(
      orderBy: orderBy,
      descending: descending,
      // Clear results to trigger a fresh load
      results: [],
    ));

    if (currentState.query.isNotEmpty) {
      await searchOfflineContent(currentState.query);
    } else {
      await getAllOfflineContent();
    }
  }

  // Toggle List/Grid View Mode
  Future<void> toggleViewMode() async {
    final currentState = state;
    if (currentState is OfflineSearchLoaded) {
      final newMode = !currentState.isListMode;
      await _prefs.setBool(_keyIsListMode, newMode);
      emit(currentState.copyWith(isListMode: newMode));
    }
  }

  // Search in offline content - DATABASE ONLY (optimized)
  Future<void> searchOfflineContent(
    String query, {
    bool loadMore = false,
    String? sourceId,
  }) async {
    try {
      if (query.trim().isEmpty) {
        // preserve filter if any
        if (state is OfflineSearchLoaded) {
          await getAllOfflineContent(
              sourceId: (state as OfflineSearchLoaded).selectedSourceId);
        } else {
          emit(const OfflineSearchInitial());
        }
        return;
      }

      String? effectiveSourceId = sourceId;
      if (effectiveSourceId == null && state is OfflineSearchLoaded) {
        effectiveSourceId = (state as OfflineSearchLoaded).selectedSourceId;
      }

      // Determine sorting BEFORE state changes to loading
      String currentOrderBy = 'created_at';
      bool currentDescending = true;
      if (state is OfflineSearchLoaded) {
        currentOrderBy = (state as OfflineSearchLoaded).orderBy;
        currentDescending = (state as OfflineSearchLoaded).descending;
      }

      // Buckets must be captured BEFORE the loading emit below, otherwise the
      // state is OfflineSearchLoading and a filtered load loses the source list.
      final previousBuckets = state is OfflineSearchLoaded
          ? (state as OfflineSearchLoaded).availableSourceIds
          : const <String>[];

      if (loadMore) {
        final currentState = state;
        if (currentState is! OfflineSearchLoaded) {
          logInfo('Cannot load more: not in loaded state');
          return;
        }
        if (!currentState.hasMore) {
          logInfo('No more search results to load');
          return;
        }
        if (currentState.isLoadingMore) {
          logInfo('Already loading more search results');
          return;
        }

        // Verify we're still searching the same query
        if (currentState.query != query) {
          logInfo('Query changed, ignoring load more');
          return;
        }

        emit(currentState.copyWith(isLoadingMore: true));
      } else {
        logInfo(
            'Searching offline content for: $query (source: $effectiveSourceId)');
        emit(const OfflineSearchLoading());
      }

      // Group-level pagination: fetch all filtered rows, group in memory,
      // then slice groupPageSize groups per page. Counts are group-based.
      final searchResults = await _userDataRepository.searchDownloads(
        query: query,
        state: DownloadState.completed,
        sourceId: effectiveSourceId,
        limit: fetchLimit,
        offset: 0,
        orderBy: currentOrderBy,
        descending: currentDescending,
      );

      if (isClosed) return;

      if (searchResults.length >= fetchLimit) {
        logWarning(
            'searchOfflineContent: rows truncated at $fetchLimit; group pages may be incomplete');
      }

      // Phase 1 (cheap, all rows): lightweight conversion + full grouping.
      // Cover resolution and reader positions are file/DB I/O — deferred to
      // phase 2 for the visible window only (3000+ row libraries).
      final pathById = <String, String?>{};
      final lightContents = <Content>[];
      final allOfflineSizes = <String, String>{};
      final allSizeBytes = <String, int>{};
      var totalStorageUsage = 0;

      for (final row in searchResults) {
        final contentId = row['id'] as String;
        final sourceId = row['source_id'] as String? ?? 'nhentai';
        final title = row['title'] as String? ?? contentId;
        // coverUrl from DB not used - resolved per visible item in phase 2
        final fileSize = row['file_size'] as int? ?? 0;
        final pageCount = row['total_pages'] as int? ?? 0;
        pathById[contentId] = row['download_path'] as String?;

        lightContents.add(Content(
          sourceId: sourceId,
          id: contentId,
          title: title,
          coverUrl: '',
          tags: [],
          artists: [],
          characters: [],
          parodies: [],
          groups: [],
          language: '',
          pageCount: pageCount,
          imageUrls: [], // Empty - loaded on-demand in reader
          uploadDate: DateTime.now(),
          favorites: 0,
          englishTitle: null,
          japaneseTitle: null,
        ));

        allOfflineSizes[contentId] =
            OfflineContentManager.formatStorageSize(fileSize);
        allSizeBytes[contentId] = fileSize;
        totalStorageUsage += fileSize;
      }

      if (isClosed) return;

      _sizeBytesByContentId
        ..clear()
        ..addAll(allSizeBytes);

      final List<ContentGroup> allGroups = await _groupContent(
        lightContents,
        itemSizes: _sizeBytesByContentId,
        includeReaderPositions: false,
      );

      // Phase 2 (I/O, visible window only): resolve covers + reader
      // positions. loadMore continues from the consumed cursor so visible
      // groups are never re-resolved.
      final startIndex = loadMore && state is OfflineSearchLoaded
          ? max(_consumedGroupCount,
              (state as OfflineSearchLoaded).results.length)
          : 0;
      final window = await _enrichGroupWindow(
        allGroups,
        startIndex,
        groupPageSize,
        downloadPathOf: (id) => pathById[id],
      );
      _consumedGroupCount = startIndex + window.consumed;

      final groupedResults = loadMore && state is OfflineSearchLoaded
          ? [...(state as OfflineSearchLoaded).results, ...window.groups]
          : window.groups;

      final currentPage = _consumedGroupCount == 0
          ? 1
          : ((_consumedGroupCount - 1) ~/ groupPageSize) + 1;
      final totalPages =
          allGroups.isEmpty ? 1 : ((allGroups.length - 1) ~/ groupPageSize) + 1;
      final hasMore = _consumedGroupCount < allGroups.length;

      // Buckets reflect the whole store: refresh on unfiltered loads,
      // otherwise keep the previously known buckets.
      final availableSourceIds = effectiveSourceId == null
          ? _distinctBucketIds(searchResults
              .map((r) => (r['source_id'] as String?) ?? 'nhentai'))
          : previousBuckets;

      if (groupedResults.isEmpty && !loadMore) {
        emit(OfflineSearchEmpty(query: query));
        return;
      }

      emit(OfflineSearchLoaded(
        query: query,
        results: groupedResults,
        totalResults: allGroups.length,
        offlineSizes: allOfflineSizes,
        storageUsage: totalStorageUsage,
        formattedStorageUsage:
            OfflineContentManager.formatStorageSize(totalStorageUsage),
        currentPage: currentPage,
        totalPages: totalPages,
        hasMore: hasMore,
        isLoadingMore: false,
        selectedSourceId: effectiveSourceId,
        availableSourceIds: availableSourceIds,
        orderBy: currentOrderBy,
        descending: currentDescending,
        isListMode: _prefs.getBool(_keyIsListMode) ?? false,
      ));

      logInfo(
          'Search complete: ${groupedResults.length}/${allGroups.length} groups for "$query" (source: $effectiveSourceId) '
          '(page $currentPage/$totalPages, hasMore: $hasMore)');
    } catch (e, stackTrace) {
      if (isClosed) return;
      handleError(e, stackTrace, 'search offline content');

      if (loadMore && state is OfflineSearchLoaded) {
        emit((state as OfflineSearchLoaded).copyWith(isLoadingMore: false));
      } else {
        emit(OfflineSearchError(
          message: 'failedSearchOffline',
          query: query,
        ));
      }
    }

    if (query.isNotEmpty && !loadMore) {
      try {
        await _userDataRepository.addSearchHistory(query);
      } catch (e) {
        logInfo('Error saving search history: $e');
      }
    }
  }

  Future<String?> findNhasixBackupFolder() async {
    try {
      final downloadsDir = await getApplicationDocumentsDirectory();
      // Try external storage path first
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final externalRoot = externalDir.path.split('/Android')[0];
        final nhasixPath = '$externalRoot/Download/nhasix';
        final nhasixDir = Directory(nhasixPath);
        if (await nhasixDir.exists()) {
          return nhasixPath;
        }
      }
      // Fallback to app documents
      final appNhasixPath = '${downloadsDir.path}/downloads/nhasix';
      final appNhasixDir = Directory(appNhasixPath);
      if (await appNhasixDir.exists()) {
        return appNhasixPath;
      }
      return null;
    } catch (e) {
      logInfo('Error finding nhasix backup folder: $e');
      return null;
    }
  }

  // Load more search results (pagination)
  ///
  // This is a convenience method for infinite scroll in search
  Future<void> loadMoreSearchResults() async {
    final currentState = state;
    if (currentState is OfflineSearchLoaded && currentState.query.isNotEmpty) {
      await searchOfflineContent(currentState.query, loadMore: true);
    }
  }

  // Get all offline content from DATABASE (primary source)
  // Falls back to file scan only if no database entries exist
  Future<void> getAllOfflineContent({
    String? backupPath,
    bool loadMore = false,
    String? sourceId,
  }) async {
    try {
      String? effectiveSourceId = sourceId;
      if (effectiveSourceId == null && state is OfflineSearchLoaded) {
        // If in loaded state, preserve current filter
        effectiveSourceId = (state as OfflineSearchLoaded).selectedSourceId;
      } else {
        effectiveSourceId ??= _prefs.getString(_keySelectedSourceFilter);
      }

      // Determine sorting BEFORE state changes to loading
      String currentOrderBy = 'created_at';
      bool currentDescending = true;
      if (state is OfflineSearchLoaded) {
        currentOrderBy = (state as OfflineSearchLoaded).orderBy;
        currentDescending = (state as OfflineSearchLoaded).descending;
      }

      // Buckets must be captured BEFORE the loading emit below, otherwise the
      // state is OfflineSearchLoading and a filtered load loses the source list.
      final previousBuckets = state is OfflineSearchLoaded
          ? (state as OfflineSearchLoaded).availableSourceIds
          : const <String>[];

      if (loadMore) {
        final currentState = state;
        if (currentState is! OfflineSearchLoaded) {
          logInfo('Cannot load more: not in loaded state');
          return;
        }
        if (!currentState.hasMore) {
          logInfo('No more content to load');
          return;
        }
        if (currentState.isLoadingMore) {
          logInfo('Already loading more content');
          return;
        }

        emit(currentState.copyWith(isLoadingMore: true));
      } else {
        logInfo(
            'Loading all offline content from database (page 1) source: $effectiveSourceId');
        emit(const OfflineSearchLoading());
      }

      // Group-level pagination: fetch all filtered rows, group in memory,
      // then slice groupPageSize groups per page. Counts are group-based.
      final downloads = await _userDataRepository.getAllDownloads(
        state: DownloadState.completed,
        sourceId: effectiveSourceId,
        limit: fetchLimit,
        offset: 0,
        orderBy: currentOrderBy,
        descending: currentDescending,
      );

      if (isClosed) return;

      if (downloads.length >= fetchLimit) {
        logWarning(
            'getAllOfflineContent: rows truncated at $fetchLimit; group pages may be incomplete');
      }

      if (downloads.isEmpty && !loadMore) {
        // Only trigger empty if NO source filter is applied.
        // If filter is applied, just show empty (filtered) state, don't fallback to FS
        if (effectiveSourceId == null) {
          // Enforce DB First: Do NOT auto-scan filesystem.
          // If DB is empty, user must explicitly trigger "Sync" or "Import".
          logInfo('No downloads in database. Waiting for user to sync/import.');
          emit(const OfflineSearchEmpty(query: ''));
          return;
        }
      }

      // Phase 1 (cheap, all rows): lightweight conversion + full grouping.
      // Cover resolution and reader positions are file/DB I/O — deferred to
      // phase 2 for the visible window only (3000+ row libraries).
      final rowById = <String, DownloadStatus>{
        for (final d in downloads) d.contentId: d,
      };
      final lightContents = <Content>[];
      final allOfflineSizes = <String, String>{};
      final allSizeBytes = <String, int>{};
      var totalStorageUsage = 0;

      for (final download in downloads) {
        lightContents.add(Content(
          sourceId: download.sourceId ?? 'nhentai',
          id: download.contentId,
          title: download.title ?? download.contentId,
          coverUrl: '', // Resolved per visible item in phase 2
          tags: [],
          artists: [],
          characters: [],
          parodies: [],
          groups: [],
          language: '',
          pageCount: download.totalPages,
          imageUrls: [], // Empty - loaded on-demand in reader
          uploadDate: DateTime.now(),
          favorites: 0,
          englishTitle: download.title, // Store original title
          japaneseTitle: null,
        ));

        allOfflineSizes[download.contentId] = download.formattedFileSize;
        allSizeBytes[download.contentId] = download.fileSize;
        totalStorageUsage += download.fileSize;
      }

      if (isClosed) return;

      _sizeBytesByContentId
        ..clear()
        ..addAll(allSizeBytes);

      final List<ContentGroup> allGroups = await _groupContent(
        lightContents,
        itemSizes: _sizeBytesByContentId,
        includeReaderPositions: false,
      );

      // Phase 2 (I/O, visible window only): resolve covers + reader
      // positions. loadMore continues from the consumed cursor so visible
      // groups are never re-resolved.
      final startIndex = loadMore && state is OfflineSearchLoaded
          ? max(_consumedGroupCount,
              (state as OfflineSearchLoaded).results.length)
          : 0;
      final window = await _enrichGroupWindow(
        allGroups,
        startIndex,
        groupPageSize,
        downloadPathOf: (id) => rowById[id]?.downloadPath,
      );
      _consumedGroupCount = startIndex + window.consumed;

      final groupedResults = loadMore && state is OfflineSearchLoaded
          ? [...(state as OfflineSearchLoaded).results, ...window.groups]
          : window.groups;

      final currentPage = _consumedGroupCount == 0
          ? 1
          : ((_consumedGroupCount - 1) ~/ groupPageSize) + 1;
      final totalPages =
          allGroups.isEmpty ? 1 : ((allGroups.length - 1) ~/ groupPageSize) + 1;
      final hasMore = _consumedGroupCount < allGroups.length;

      // Buckets reflect the whole store: refresh on unfiltered loads,
      // otherwise keep the previously known buckets.
      final availableSourceIds = effectiveSourceId == null
          ? _distinctBucketIds(downloads.map((d) => d.sourceId ?? 'nhentai'))
          : previousBuckets;

      if (groupedResults.isEmpty) {
        // If filtered and empty, we should still show the filtered state, not generic empty
        emit(OfflineSearchLoaded(
          query: '',
          results: [],
          totalResults: 0,
          offlineSizes: {},
          storageUsage: 0,
          formattedStorageUsage: '0 B',
          currentPage: 1,
          totalPages: 1,
          hasMore: false,
          isLoadingMore: false,
          selectedSourceId: effectiveSourceId,
          availableSourceIds: availableSourceIds,
          isListMode: _prefs.getBool(_keyIsListMode) ?? false,
        ));
        return;
      }

      emit(OfflineSearchLoaded(
        query: '',
        results: groupedResults,
        totalResults: allGroups.length,
        offlineSizes: allOfflineSizes,
        storageUsage: totalStorageUsage,
        formattedStorageUsage:
            OfflineContentManager.formatStorageSize(totalStorageUsage),
        currentPage: currentPage,
        totalPages: totalPages,
        hasMore: hasMore,
        isLoadingMore: false,
        selectedSourceId: effectiveSourceId,
        availableSourceIds: availableSourceIds,
        orderBy: currentOrderBy,
        descending: currentDescending,
        isListMode: _prefs.getBool(_keyIsListMode) ?? false,
      ));

      logInfo(
          'Loaded ${groupedResults.length}/${allGroups.length} groups (source: $effectiveSourceId) '
          '(page $currentPage/$totalPages, hasMore: $hasMore)');
    } catch (e, stackTrace) {
      if (isClosed) return;
      handleError(e, stackTrace, 'get all offline content');

      if (loadMore && state is OfflineSearchLoaded) {
        emit((state as OfflineSearchLoaded).copyWith(isLoadingMore: false));
      } else {
        emit(const OfflineSearchError(
          message: 'failedLoadOfflineContent',
          query: '',
        ));
      }
    }
  }

  // Manual Import/Sync: Load from file system and populate database
  // This is now EXPLICITLY triggered by the user (not automatic)
  Future<void> importFromBackup([String? backupPath]) async {
    String? loadPath = backupPath;
    if (loadPath == null) {
      final nhasixPath = await findNhasixBackupFolder();
      if (nhasixPath == null) {
        emit(const OfflineSearchEmpty(query: ''));
        return;
      }
      loadPath = nhasixPath;
    }

    final syncSourceId = state is OfflineSearchLoaded
        ? (state as OfflineSearchLoaded).selectedSourceId
        : _prefs.getString(_keySelectedSourceFilter);

    final scanPath = _resolveBackupSourcePath(loadPath, syncSourceId);

    final contents =
        await _offlineContentManager.getAllOfflineContentFromFileSystem(
      scanPath,
    );

    if (contents.isEmpty) {
      emit(const OfflineSearchEmpty(query: ''));
      return;
    }

    final offlineSizes = await _calculateContentSizes(contents);

    int totalStorageUsage = 0;
    for (final content in contents) {
      if (content.imageUrls.isNotEmpty) {
        try {
          final file = File(content.imageUrls.first);
          final dirPath = file.parent.path;
          totalStorageUsage += await _getDirectorySize(Directory(dirPath));
        } catch (e) {
          getIt<Logger>().e("OfflineSearch storage calc failed", error: e);
        }
      }
    }

    final List<ContentGroup> groupedResults = await _groupContent(contents);

    emit(OfflineSearchLoaded(
      query: '',
      results: groupedResults,
      totalResults: contents.length,
      offlineSizes: offlineSizes,
      storageUsage: totalStorageUsage,
      formattedStorageUsage:
          OfflineContentManager.formatStorageSize(totalStorageUsage),
      isListMode: _prefs.getBool(_keyIsListMode) ?? false,
    ));

    logInfo(
        'Loaded ${contents.length} offline content items from file system (fallback)');

    // Auto-sync: rebuild DB after clear app data
    try {
      logInfo(
          'Auto-syncing ${contents.length} items from filesystem to database...');
      final syncResult = await _offlineContentManager.syncBackupToDatabase(
        scanPath,
        sourceId: syncSourceId,
      );
      final synced = syncResult['synced'] ?? 0;
      final updated = syncResult['updated'] ?? 0;
      ContentDownloadCache.clearCache();
      logInfo('Auto-sync complete: $synced new, $updated updated');
    } catch (e) {
      logInfo('Auto-sync failed (non-blocking): $e');
      // Don't throw - content is already displayed, sync is best-effort
    }
  }

  // Load more offline content (pagination)
  ///
  // This smart method calls either searchOfflineContent or getAllOfflineContent
  // depending on whether a search query is active.
  Future<void> loadMoreContent() async {
    final currentState = state;
    if (currentState is OfflineSearchLoaded && currentState.query.isNotEmpty) {
      await searchOfflineContent(currentState.query, loadMore: true);
    } else {
      await getAllOfflineContent(loadMore: true);
    }
  }

  // Force reload content from database
  // Call this after sync operations to ensure UI is up to date
  Future<void> forceRefresh({String? backupPath}) async {
    try {
      logInfo('Force refreshing offline content from database');

      _offlineContentManager.clearCache();
      ContentDownloadCache.clearCache();

      await getAllOfflineContent(backupPath: backupPath);
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'force refresh');
    }
  }

  void clearSearch() {
    emit(const OfflineSearchInitial());
  }

  String _resolveBackupSourcePath(String backupPath, String? sourceId) {
    if (sourceId == null || sourceId.trim().isEmpty) {
      return backupPath;
    }

    final normalizedBackupPath = path.normalize(backupPath);
    final backupBase = path.basename(normalizedBackupPath);
    if (backupBase.toLowerCase() == sourceId.toLowerCase()) {
      return normalizedBackupPath;
    }

    return path.join(backupPath, sourceId);
  }

  // Set loading state (for external triggers like import operations)
  void setLoadingState() {
    emit(const OfflineSearchLoading());
  }

  // Get offline storage statistics
  ///
  // Returns stats based on current state:
  // - When OfflineSearchLoaded (any query): calculate from loaded results
  // - When Initial/Loading/Empty/Error: get from database
  Future<Map<String, dynamic>> getOfflineStats() async {
    try {
      int storageUsage = 0;
      int totalCount = 0;
      bool isSearchResult = false;

      if (state is OfflineSearchLoaded) {
        final loadedState = state as OfflineSearchLoaded;
        if (loadedState.query.isNotEmpty) {
          isSearchResult = true;
          totalCount = loadedState.totalResults;

          // Use optimized DB query for search result size
          storageUsage = await _userDataRepository.getSearchDownloadSize(
            query: loadedState.query,
            state: DownloadState.completed,
          );
        }
      }

      if (!isSearchResult) {
        storageUsage = await _offlineContentManager.getOfflineStorageUsage();
        totalCount = await _userDataRepository.getDownloadsCount(
          state: DownloadState.completed,
        );
      }

      return {
        'totalContent': totalCount,
        'storageUsage': storageUsage,
        'formattedSize': OfflineContentManager.formatStorageSize(storageUsage),
        'isSearchResult': isSearchResult,
      };
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'get offline stats');
      return {
        'totalContent': 0,
        'storageUsage': 0,
        'formattedSize': '0 B',
        'isSearchResult': false,
      };
    }
  }

  Future<void> cleanupOfflineFiles() async {
    try {
      logInfo('Starting cleanup of orphaned offline files');
      await _offlineContentManager.cleanupOrphanedFiles();
      _offlineContentManager.clearCache();
      logInfo('Cleanup completed successfully');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'cleanup offline files');
      rethrow;
    }
  }

  Future<void> scanBackupContent(String backupPath) async {
    try {
      logInfo('Scanning backup folder: $backupPath');
      emit(const OfflineSearchLoading());

      final backupContents =
          await _offlineContentManager.scanBackupFolder(backupPath);

      if (backupContents.isEmpty) {
        emit(const OfflineSearchEmpty(query: ''));
        return;
      }

      final offlineSizes = await _calculateContentSizes(backupContents);

      int totalStorageUsage = 0;
      for (final content in backupContents) {
        if (content.imageUrls.isNotEmpty) {
          try {
            final file = File(content.imageUrls.first);
            final dirPath = file.parent.path;
            totalStorageUsage += await _getDirectorySize(Directory(dirPath));
          } catch (e) {
            getIt<Logger>().e("OfflineSearch storage calc failed", error: e);
          }
        }
      }

      final List<ContentGroup> groupedResults =
          await _groupContent(backupContents);

      emit(OfflineSearchLoaded(
        query: '',
        results: groupedResults,
        totalResults: backupContents.length,
        offlineSizes: offlineSizes,
        storageUsage: totalStorageUsage,
        formattedStorageUsage:
            OfflineContentManager.formatStorageSize(totalStorageUsage),
        isListMode: _prefs.getBool(_keyIsListMode) ?? false,
      ));

      logInfo('Found ${backupContents.length} backup content items');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'scan backup content');
      emit(const OfflineSearchError(
        message: 'failedScanBackup',
        query: '',
      ));
    }
  }

  Future<List<String>> getSearchHistory() async {
    try {
      return await _userDataRepository.getSearchHistory(limit: 10);
    } catch (e) {
      logInfo('Error getting search history: $e');
      return [];
    }
  }

  Future<void> deleteSearchHistory(String query) async {
    try {
      await _userDataRepository.deleteSearchHistory(query);
    } catch (e) {
      logInfo('Error deleting search history: $e');
    }
  }

  Future<void> deleteOfflineContent(String contentId) async {
    try {
      logInfo('Deleting offline content: $contentId');

      final deleted =
          await _offlineContentManager.deleteOfflineContent(contentId);
      if (!deleted) {
        throw StateError('Offline content not found: $contentId');
      }
      _sizeBytesByContentId.remove(contentId);

      if (state is OfflineSearchLoaded) {
        final query = (state as OfflineSearchLoaded).query;
        if (query.isNotEmpty) {
          await searchOfflineContent(query);
        } else {
          await getAllOfflineContent();
        }
      } else {
        await getAllOfflineContent();
      }

      logInfo('Deleted content $contentId');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'delete offline content');
      rethrow;
    }
  }

  Future<void> bulkDeleteOfflineContent(List<String> contentIds) async {
    try {
      for (final id in contentIds) {
        final deleted = await _offlineContentManager.deleteOfflineContent(id);
        if (deleted) _sizeBytesByContentId.remove(id);
      }
      if (state is OfflineSearchLoaded) {
        final query = (state as OfflineSearchLoaded).query;
        if (query.isNotEmpty) {
          await searchOfflineContent(query);
        } else {
          await getAllOfflineContent();
        }
      } else {
        await getAllOfflineContent();
      }
      logInfo('Bulk deleted ${contentIds.length} contents');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'bulk delete offline content');
    }
  }

  /// Distinct, sorted source buckets from fetched rows. Empty/blank ids
  /// are dropped; callers pass unfiltered rows so the buckets reflect the
  /// whole store rather than the active filter.
  List<String> _distinctBucketIds(Iterable<String?> sourceIds) {
    final ids = <String>{};
    for (final id in sourceIds) {
      final normalized = (id ?? '').trim();
      if (normalized.isNotEmpty) ids.add(normalized);
    }
    return ids.toList()..sort();
  }

  /// Enriches a window of lightweight groups starting at [startIndex]:
  /// resolves covers (file I/O) and reader positions (DB) for up to
  /// [targetCount] displayable groups. Groups whose items all lack covers
  /// are skipped and the window tops up from later groups.
  ///
  /// Returns the enriched groups plus how many input groups were consumed
  /// ([consumed] >= groups.length when drops occurred).
  Future<({List<ContentGroup> groups, int consumed})> _enrichGroupWindow(
    List<ContentGroup> allGroups,
    int startIndex,
    int targetCount, {
    required String? Function(String contentId) downloadPathOf,
  }) async {
    final visible = <ContentGroup>[];
    var cursor = startIndex.clamp(0, allGroups.length);
    while (visible.length < targetCount && cursor < allGroups.length) {
      if (isClosed) break;
      final light = allGroups[cursor];
      cursor++;
      final enrichedItems = <Content>[];
      for (final item in light.items) {
        if (isClosed) break;
        final cover = await _offlineContentManager.getOfflineFirstImagePath(
          item.id,
          downloadPath: downloadPathOf(item.id),
        );
        if (cover == null) continue;
        enrichedItems.add(item.copyWith(coverUrl: cover));
      }
      if (enrichedItems.isEmpty) continue;
      final enriched = await _groupContent(
        enrichedItems,
        itemSizes: _sizeBytesByContentId,
      );
      visible.addAll(enriched);
    }
    return (groups: visible, consumed: cursor - startIndex);
  }

  // Groups a flat list of Content into ContentGroup based on sourceId + baseTitle.
  // Reader positions are per-item DB reads — pass [includeReaderPositions]
  // false for the cheap full-library grouping pass, true when enriching the
  // visible window only.
  Future<List<ContentGroup>> _groupContent(
    List<Content> flatItems, {
    Map<String, int> itemSizes = const {},
    bool includeReaderPositions = true,
  }) async {
    final Map<String, List<Content>> groupedMap = {};
    for (final item in flatItems) {
      final baseTitle = TitleParserUtils.getBaseTitle(item.title);
      final groupKey = '${item.sourceId}:::$baseTitle';
      groupedMap.putIfAbsent(groupKey, () => []).add(item);
    }

    dynamic readerPosRepo;
    if (includeReaderPositions) {
      try {
        readerPosRepo = getIt<ReaderRepository>();
      } catch (_) {}
    }

    final List<ContentGroup> groups = [];
    for (final entry in groupedMap.entries) {
      final items = ContentGroup.dedupeItems(entry.value);
      if (items.isEmpty) continue;

      final baseTitle = TitleParserUtils.getBaseTitle(items.first.title);
      final totalSize = items.fold<int>(
        0,
        (sum, item) => sum + (itemSizes[item.id] ?? 0),
      );
      final groupItemSizes = {
        for (final item in items) item.id: itemSizes[item.id] ?? 0,
      };
      double maxProgress = 0.0;
      bool isRead = false;
      bool isReading = false;

      if (includeReaderPositions) {
        for (final item in items) {
          try {
            if (readerPosRepo != null) {
              final position = await readerPosRepo.getReaderPosition(item.id);
              if (position != null && position.totalPages > 0) {
                final double progress =
                    position.currentPage / position.totalPages;
                if (progress > maxProgress) maxProgress = progress;
                if (position.currentPage >= position.totalPages - 1) {
                  isRead = true;
                } else if (position.currentPage > 1) {
                  isReading = true;
                }
              }
            }
          } catch (e) {
            logInfo('Error getting reader position for ${item.id}: $e');
          }
        }
      }

      groups.add(ContentGroup(
        baseTitle: baseTitle,
        items: items,
        totalSize: totalSize,
        itemSizes: groupItemSizes,
        readProgress: maxProgress > 1.0 ? 1.0 : maxProgress,
        isRead: isRead,
        isReading: isReading,
      ));
    }
    return groups;
  }
}
