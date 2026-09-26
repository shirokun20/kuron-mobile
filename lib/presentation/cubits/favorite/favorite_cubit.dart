import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/favorites/favorites_usecases.dart';
import '../../../domain/usecases/favorites/get_favorite_collections_usecase.dart';
import '../../../domain/usecases/favorites/create_favorite_collection_usecase.dart';
import '../../../domain/usecases/favorites/rename_favorite_collection_usecase.dart';
import '../../../domain/usecases/favorites/delete_favorite_collection_usecase.dart';
import '../../../domain/usecases/favorites/add_to_favorite_collection_usecase.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../l10n/app_localizations.dart';
import '../base/base_cubit.dart';
import '../recommendations/recommendation_refresh_bus.dart';

part 'favorite_state.dart';

// Cubit for managing favorites with simple CRUD operations
// Handles favorites list, categories, and batch operations
class FavoriteCubit extends BaseCubit<FavoriteState> {
  FavoriteCubit({
    required AddToFavoritesUseCase addToFavoritesUseCase,
    required GetFavoritesUseCase getFavoritesUseCase,
    required RemoveFromFavoritesUseCase removeFromFavoritesUseCase,
    required GetFavoriteCollectionsUseCase getFavoriteCollectionsUseCase,
    required CreateFavoriteCollectionUseCase createFavoriteCollectionUseCase,
    required RenameFavoriteCollectionUseCase renameFavoriteCollectionUseCase,
    required DeleteFavoriteCollectionUseCase deleteFavoriteCollectionUseCase,
    required AddToFavoriteCollectionUseCase addToFavoriteCollectionUseCase,
    required UserDataRepository userDataRepository,
    required super.logger,
    this.localizations,
  })  : _addToFavoritesUseCase = addToFavoritesUseCase,
        _getFavoritesUseCase = getFavoritesUseCase,
        _removeFromFavoritesUseCase = removeFromFavoritesUseCase,
        _getFavoriteCollectionsUseCase = getFavoriteCollectionsUseCase,
        _createFavoriteCollectionUseCase = createFavoriteCollectionUseCase,
        _renameFavoriteCollectionUseCase = renameFavoriteCollectionUseCase,
        _deleteFavoriteCollectionUseCase = deleteFavoriteCollectionUseCase,
        _addToFavoriteCollectionUseCase = addToFavoriteCollectionUseCase,
        _userDataRepository = userDataRepository,
        super(
          initialState: const FavoriteInitial(),
        );

  final AddToFavoritesUseCase _addToFavoritesUseCase;
  final GetFavoritesUseCase _getFavoritesUseCase;
  final RemoveFromFavoritesUseCase _removeFromFavoritesUseCase;
  final GetFavoriteCollectionsUseCase _getFavoriteCollectionsUseCase;
  final CreateFavoriteCollectionUseCase _createFavoriteCollectionUseCase;
  final RenameFavoriteCollectionUseCase _renameFavoriteCollectionUseCase;
  final DeleteFavoriteCollectionUseCase _deleteFavoriteCollectionUseCase;
  final AddToFavoriteCollectionUseCase _addToFavoriteCollectionUseCase;
  final UserDataRepository _userDataRepository;
  final AppLocalizations? localizations;

  // Current page for pagination
  int _currentPage = 1;
  static const int _itemsPerPage = 20;
  String? _activeCollectionId;

  List<Map<String, dynamic>> _dedupeFavorites(
    Iterable<Map<String, dynamic>> favorites,
  ) {
    final deduped = <String, Map<String, dynamic>>{};

    for (final favorite in favorites) {
      final id = favorite['id']?.toString() ?? '';
      final sourceId = favorite['source_id']?.toString() ?? '';
      final key = '$sourceId::$id';
      if (id.isEmpty || sourceId.isEmpty) {
        continue;
      }
      deduped[key] = favorite;
    }

    return deduped.values.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _loadSearchBaseFavorites() async {
    final totalCount = await _userDataRepository.getFavoritesCount(
      collectionId: _activeCollectionId,
    );
    if (totalCount <= 0) {
      return const [];
    }

    final params = GetFavoritesParams.firstPage(
      limit: totalCount,
      collectionId: _activeCollectionId,
    );

    return _dedupeFavorites(await _getFavoritesUseCase(params));
  }

  // Load favorites list
  Future<void> loadFavorites({
    bool refresh = false,
    String? collectionId,
  }) async {
    try {
      if (collectionId != _activeCollectionId) {
        _activeCollectionId = collectionId;
        _currentPage = 1;
      }

      if (refresh) {
        _currentPage = 1;
        logInfo('Refreshing favorites list');
        emit(const FavoriteLoading());
      } else if (state is FavoriteInitial) {
        logInfo('Loading favorites list');
        emit(const FavoriteLoading());
      }

      final collections = await _getFavoriteCollectionsUseCase();
      final params = GetFavoritesParams.page(
        _currentPage,
        limit: _itemsPerPage,
        collectionId: _activeCollectionId,
      );
      final favorites = _dedupeFavorites(await _getFavoritesUseCase(params));
      final totalCount = await _userDataRepository.getFavoritesCount(
        collectionId: _activeCollectionId,
      );

      final hasMore = favorites.length == _itemsPerPage;

      emit(FavoriteLoaded(
        favorites: favorites,
        collections: collections,
        currentPage: _currentPage,
        hasMore: hasMore,
        totalCount: totalCount,
        lastUpdated: DateTime.now(),
        activeCollectionId: _activeCollectionId,
      ));

      logInfo('Successfully loaded ${favorites.length} favorites '
          '(page $_currentPage, collection=${_activeCollectionId ?? 'all'})');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'load favorites');

      final errorType = determineErrorType(e);
      emit(FavoriteError(
        message: localizations?.failedToLoadFavorites(e.toString()) ??
            'Failed to load favorites: ${e.toString()}',
        errorType: errorType,
        canRetry: isRetryableError(errorType),
      ));
    }
  }

  // Load more favorites (pagination)
  Future<void> loadMoreFavorites() async {
    final currentState = state;
    if (currentState is! FavoriteLoaded ||
        !currentState.hasMore ||
        currentState.isLoadingMore ||
        currentState.isSearching) {
      return;
    }

    try {
      logInfo('Loading more favorites (page ${_currentPage + 1})');
      emit(currentState.copyWith(isLoadingMore: true));

      _currentPage++;
      final params = GetFavoritesParams.page(
        _currentPage,
        limit: _itemsPerPage,
        collectionId: _activeCollectionId,
      );
      final newFavorites = _dedupeFavorites(await _getFavoritesUseCase(params));

      final allFavorites = _dedupeFavorites([
        ...currentState.favorites,
        ...newFavorites,
      ]);
      final hasMore = newFavorites.length == _itemsPerPage;

      emit(currentState.copyWith(
        favorites: allFavorites,
        collections: currentState.collections,
        currentPage: _currentPage,
        hasMore: hasMore,
        isLoadingMore: false,
        lastUpdated: DateTime.now(),
        activeCollectionId: _activeCollectionId,
      ));

      logInfo('Successfully loaded ${newFavorites.length} more favorites');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'load more favorites');

      // Revert page increment on error
      _currentPage--;

      final currentState = state;
      if (currentState is FavoriteLoaded) {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    }
  }

  // Add content to favorites
  Future<void> addToFavorites(Content content) async {
    try {
      logInfo('Adding content to favorites: ${content.title}');

      final params = AddToFavoritesParams.create(content);
      await _addToFavoritesUseCase(params);

      if (_activeCollectionId != null) {
        await loadFavorites(refresh: true, collectionId: _activeCollectionId);
        logInfo(
            'Favorite added while collection filter active; list refreshed');
        return;
      }

      // Update current state if loaded
      final currentState = state;
      if (currentState is FavoriteLoaded) {
        // Add to beginning of list
        final newFavorite = {
          'id': content.id,
          'source_id': content.sourceId,
          'title': content.title,
          'cover_url': content.coverUrl,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        };

        final updatedFavorites = _dedupeFavorites([
          newFavorite,
          ...currentState.favorites,
        ]);

        emit(currentState.copyWith(
          favorites: updatedFavorites,
          totalCount: currentState.totalCount + 1,
          lastUpdated: DateTime.now(),
        ));
      }

      logInfo('Successfully added to favorites: ${content.title}');
      RecommendationRefreshBus.requestGlobalRefresh();
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'add to favorites');
      rethrow; // Let the calling widget handle the error
    }
  }

  // Remove content from favorites
  Future<void> removeFromFavorites(String contentId, {String? sourceId}) async {
    try {
      logInfo('Starting removal of content from favorites: $contentId');

      // First check if content exists in favorites
      final isFavorite = await _userDataRepository.isFavorite(
        contentId,
        sourceId: sourceId,
      );
      if (!isFavorite) {
        logWarning('Content $contentId is not in favorites, skipping removal');
        return;
      }

      final params = RemoveFromFavoritesParams.fromString(
        contentId,
        sourceId: sourceId,
      );
      logInfo('Calling removeFromFavoritesUseCase with params: $params');

      await _removeFromFavoritesUseCase(params);
      logInfo('Successfully called removeFromFavoritesUseCase');

      // Update current state if loaded
      final currentState = state;
      if (currentState is FavoriteLoaded) {
        logInfo(
            'Updating favorites list in state, removing contentId: $contentId');

        final beforeCount = currentState.favorites.length;
        final updatedFavorites = currentState.favorites
            .where((favorite) =>
                favorite['id'] != contentId ||
                (sourceId != null && favorite['source_id'] != sourceId))
            .toList();
        final afterCount = updatedFavorites.length;

        logInfo('Favorites count: before=$beforeCount, after=$afterCount');

        emit(currentState.copyWith(
          favorites: updatedFavorites,
          totalCount: currentState.totalCount - 1,
          lastUpdated: DateTime.now(),
        ));

        logInfo('State updated successfully');
      } else {
        logWarning(
            'Current state is not FavoriteLoaded, state type: ${state.runtimeType}');
      }

      logInfo('Successfully removed from favorites: $contentId');
      RecommendationRefreshBus.requestGlobalRefresh();
    } catch (e, stackTrace) {
      logWarning('Error removing content $contentId from favorites: $e');
      handleError(e, stackTrace, 'remove from favorites');
      rethrow; // Let the calling widget handle the error
    }
  }

  // Check if content is favorited
  Future<bool> isFavorited(String contentId, {String? sourceId}) async {
    try {
      return await _userDataRepository.isFavorite(
        contentId,
        sourceId: sourceId,
      );
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'check if favorited');
      return false;
    }
  }

  // Remove multiple favorites (batch operation)
  Future<void> removeBatchFavorites(List<String> contentIds) async {
    if (contentIds.isEmpty) return;

    try {
      logInfo('Removing ${contentIds.length} favorites in batch');

      // Show loading state
      final currentState = state;
      if (currentState is FavoriteLoaded) {
        emit(currentState.copyWith(isBatchOperating: true));
      }

      // Remove each favorite
      for (final contentId in contentIds) {
        final params = RemoveFromFavoritesParams.fromString(contentId);
        await _removeFromFavoritesUseCase(params);
      }

      // Update current state if loaded
      if (currentState is FavoriteLoaded) {
        final updatedFavorites = currentState.favorites
            .where((favorite) => !contentIds.contains(favorite['id']))
            .toList();

        emit(currentState.copyWith(
          favorites: updatedFavorites,
          totalCount: currentState.totalCount - contentIds.length,
          isBatchOperating: false,
          lastUpdated: DateTime.now(),
        ));
      }

      logInfo('Successfully removed ${contentIds.length} favorites in batch');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'batch remove favorites');

      // Reset batch operating state
      final currentState = state;
      if (currentState is FavoriteLoaded) {
        emit(currentState.copyWith(isBatchOperating: false));
      }

      rethrow;
    }
  }

  // Search within favorites
  Future<void> searchFavorites(String query) async {
    final currentState = state;
    if (currentState is! FavoriteLoaded) {
      return;
    }

    try {
      logInfo('Searching favorites with query: $query');

      if (query.isEmpty) {
        // Reset to show all favorites
        await loadFavorites(refresh: true, collectionId: _activeCollectionId);
        return;
      }

      // Search against the full favorites dataset from DB, not only the
      // currently paginated items.
      final searchBaseFavorites = await _loadSearchBaseFavorites();

      final lowerQuery = query.toLowerCase();
      final filteredFavorites = searchBaseFavorites.where((favorite) {
        final id = favorite['id']?.toString().toLowerCase() ?? '';
        final title = favorite['title']?.toString().toLowerCase() ?? '';
        final sourceId = favorite['source_id']?.toString().toLowerCase() ?? '';
        return id.contains(lowerQuery) ||
            title.contains(lowerQuery) ||
            sourceId.contains(lowerQuery);
      }).toList(growable: false);

      emit(currentState.copyWith(
        favorites: _dedupeFavorites(filteredFavorites),
        currentPage: 1,
        hasMore: false,
        searchQuery: query,
        lastUpdated: DateTime.now(),
      ));

      logInfo('Found ${filteredFavorites.length} favorites matching query');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'search favorites');
    }
  }

  // Clear search and show all favorites
  Future<void> clearSearch() async {
    logInfo('Clearing favorites search');
    await loadFavorites(refresh: true, collectionId: _activeCollectionId);
  }

  Future<void> selectCollection(String? collectionId) async {
    if (_activeCollectionId == collectionId && state is FavoriteLoaded) {
      return;
    }

    await loadFavorites(refresh: true, collectionId: collectionId);
  }

  Future<void> createCollection(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Collection name cannot be empty');
    }

    await _createFavoriteCollectionUseCase(trimmedName);
    await loadFavorites(refresh: true, collectionId: _activeCollectionId);
  }

  Future<void> renameCollection({
    required String collectionId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Collection name cannot be empty');
    }

    await _renameFavoriteCollectionUseCase(
      collectionId: collectionId,
      name: trimmedName,
    );
    await loadFavorites(refresh: true, collectionId: _activeCollectionId);
  }

  Future<void> deleteCollection(String collectionId) async {
    await _deleteFavoriteCollectionUseCase(collectionId);
    if (_activeCollectionId == collectionId) {
      _activeCollectionId = null;
    }
    await loadFavorites(refresh: true, collectionId: _activeCollectionId);
  }

  Future<List<String>> getFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
  }) {
    return _userDataRepository.getFavoriteCollectionIds(
      favoriteId: favoriteId,
      sourceId: sourceId,
    );
  }

  Future<void> setFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
    required List<String> collectionIds,
  }) async {
    await _addToFavoriteCollectionUseCase(
      favoriteId: favoriteId,
      sourceId: sourceId,
      collectionIds: collectionIds,
    );
    await loadFavorites(refresh: true, collectionId: _activeCollectionId);
  }

  // Export favorites data
  Future<Map<String, dynamic>> exportFavorites() async {
    try {
      logInfo('Exporting favorites data');

      // Get all favorites at once (no pagination - much faster!)
      final allFavorites = await _userDataRepository.getAllFavoritesForExport();
      final collections =
          await _userDataRepository.getFavoriteCollectionsForExport();
      final collectionItems =
          await _userDataRepository.getFavoriteCollectionMembershipsForExport();

      final exportData = {
        'version': '2.0',
        'exported_at': DateTime.now().toIso8601String(),
        'total_count': allFavorites.length,
        'favorites': allFavorites,
        'collections': collections.map((item) => item.toJson()).toList(),
        'collection_items': collectionItems,
      };

      logInfo('Successfully exported ${allFavorites.length} favorites');
      return exportData;
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'export favorites');
      rethrow;
    }
  }

  // Import favorites data
  Future<void> importFavorites(Map<String, dynamic> data) async {
    try {
      logInfo('Importing favorites data');

      final favorites = data['favorites'] is List
          ? data['favorites'] as List<dynamic>
          : <dynamic>[];
      final collectionMaps = data['collections'] is List
          ? data['collections'] as List<dynamic>
          : <dynamic>[];
      final collectionItems = data['collection_items'] is List
          ? data['collection_items'] as List<dynamic>
          : <dynamic>[];
      int importedCount = 0;
      final importedCollectionIdsBySource = <String, String>{};

      for (final favoriteData in favorites) {
        try {
          final id = favoriteData['id']?.toString();
          final coverUrl = favoriteData['cover_url']?.toString();
          final sourceId = favoriteData['source_id']?.toString() ?? 'nhentai';
          final title = favoriteData['title']?.toString();

          if (id != null && coverUrl != null) {
            await _userDataRepository.addToFavorites(
              id: id,
              sourceId: sourceId,
              coverUrl: coverUrl,
              title: title,
            );
            importedCount++;
          }
        } catch (e) {
          logWarning('Failed to import favorite: $e');
          // Continue with next favorite
        }
      }

      for (final collectionData in collectionMaps) {
        try {
          final rawMap = Map<String, dynamic>.from(
            (collectionData as Map).cast<String, dynamic>(),
          );
          final collection = FavoriteCollection.fromJson(rawMap);
          final created = await _userDataRepository.createFavoriteCollection(
            name: collection.name,
            collectionId: collection.id,
          );
          importedCollectionIdsBySource[collection.id] = created.id;
        } catch (e) {
          logWarning('Failed to import favorite collection: $e');
        }
      }

      for (final membershipData in collectionItems) {
        try {
          final rawMap = Map<String, dynamic>.from(
            (membershipData as Map).cast<String, dynamic>(),
          );
          final favoriteId = rawMap['favorite_id']?.toString();
          final sourceId = rawMap['source_id']?.toString() ?? 'nhentai';
          final importedCollectionId = importedCollectionIdsBySource[
              rawMap['collection_id']?.toString()];

          if (favoriteId == null || importedCollectionId == null) {
            continue;
          }

          final existingIds =
              await _userDataRepository.getFavoriteCollectionIds(
            favoriteId: favoriteId,
            sourceId: sourceId,
          );
          await _userDataRepository.setFavoriteCollectionIds(
            favoriteId: favoriteId,
            sourceId: sourceId,
            collectionIds: [...existingIds, importedCollectionId],
          );
        } catch (e) {
          logWarning('Failed to import favorite collection membership: $e');
        }
      }

      // Refresh favorites list
      await loadFavorites(refresh: true);

      logInfo('Successfully imported $importedCount favorites');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'import favorites');
      rethrow;
    }
  }

  // Get favorites statistics
  Future<Map<String, int>> getFavoritesStats() async {
    try {
      final totalCount = await _userDataRepository.getFavoritesCount();

      return {
        'total_favorites': totalCount,
        'current_page': _currentPage,
        'items_per_page': _itemsPerPage,
      };
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'get favorites stats');
      return {};
    }
  }

  // Retry loading after error
  Future<void> retryLoading() async {
    logInfo('Retrying favorites loading');
    await loadFavorites(refresh: true);
  }

  // Refresh favorites
  Future<void> refresh() async {
    logInfo('Refreshing favorites');
    await loadFavorites(refresh: true);
  }

  // Get current favorites list
  List<Map<String, dynamic>> get currentFavorites {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.favorites;
    }
    return [];
  }

  // Get current favorites count
  int get favoritesCount {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.totalCount;
    }
    return 0;
  }

  // Check if has more favorites to load
  bool get hasMoreFavorites {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.hasMore;
    }
    return false;
  }

  // Check if currently loading more
  bool get isLoadingMore {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.isLoadingMore;
    }
    return false;
  }

  // Check if currently performing batch operation
  bool get isBatchOperating {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.isBatchOperating;
    }
    return false;
  }

  // Get current search query
  String? get currentSearchQuery {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.searchQuery;
    }
    return null;
  }

  String? get activeCollectionId {
    final currentState = state;
    if (currentState is FavoriteLoaded) {
      return currentState.activeCollectionId;
    }
    return _activeCollectionId;
  }
}
