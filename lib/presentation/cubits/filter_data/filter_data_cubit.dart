import '../../../domain/entities/entities.dart';
import '../../../domain/entities/tags/tag_entity.dart';
import '../../../domain/usecases/tags/get_tag_autocomplete_usecase.dart';
import '../../../domain/usecases/tags/get_tags_by_type_usecase.dart';
import '../../../core/utils/tag_data_manager.dart';
import '../base/base_cubit.dart';

part 'filter_data_state.dart';

// Cubit for managing filter data screen state
class FilterDataCubit extends BaseCubit<FilterDataState> {
  FilterDataCubit({
    required this._tagDataManager,
    required this._getTagsByTypeUseCase,
    required this._getTagAutocompleteUseCase,
    required super.logger,
  })  : super(initialState: const FilterDataInitial());

  final TagDataManager _tagDataManager;
  final GetTagsByTypeUseCase _getTagsByTypeUseCase;
  final GetTagAutocompleteUseCase _getTagAutocompleteUseCase;

  // Whether this source should fetch tags from API v2 instead of local JSON
  bool _shouldUseApi(String sourceId) {
    const apiSources = {'nhentai'};
    return apiSources.contains(sourceId);
  }

  // Convert API TagEntity to kuron_core Tag for compatibility
  Tag _tagEntityToTag(TagEntity entity) => Tag(
        id: entity.id,
        name: entity.name,
        type: entity.type,
        count: entity.count,
        url: entity.url ?? '',
        slug: entity.slug,
      );

  // Internal state
  String _currentFilterType = 'tag';
  String _currentSourceId = 'nhentai';
  List<FilterItem> _selectedFilters = [];
  List<Tag> _filteredTags = [];
  String _searchQuery = '';

  // Initialize filter data screen
  Future<void> initialize({
    required String filterType,
    String sourceId = 'nhentai',
    required List<FilterItem> selectedFilters,
  }) async {
    try {
      logger.i(
          'FilterDataCubit: Initializing with type: $filterType, source: $sourceId');

      _currentFilterType = filterType;
      _currentSourceId = sourceId;
      _selectedFilters = List<FilterItem>.from(selectedFilters);
      emit(FilterDataLoading(state));

      if (_shouldUseApi(_currentSourceId)) {
        // Use API v2 for sources with live tag endpoints
        final entities = await _getTagsByTypeUseCase(
          GetTagsByTypeParams(
            tagType: filterType,
            sourceId: _currentSourceId,
            page: 1,
            perPage: 50,
          ),
        );
        _filteredTags = entities.map(_tagEntityToTag).toList();
      } else {
        // Use local JSON via TagDataManager for offline-capable sources
        if (!_tagDataManager.hasTags(_currentSourceId)) {
          await _tagDataManager.initialize(source: _currentSourceId);
        }
        _filteredTags = await _tagDataManager.getTagsByType(
          filterType,
          limit: 100,
          source: _currentSourceId,
        );
      }

      emit(
        state.copyWith(
          filterType: _currentFilterType,
          searchResults: _filteredTags,
          selectedFilters: _selectedFilters,
          searchQuery: _searchQuery,
          isSearching: false,
          lastUpdated: DateTime.now(),
          message: null,
        ),
      );

      emit(FilterDataLoaded(state));
      logger.i(
          'FilterDataCubit: Loaded ${_filteredTags.length} tags for type: $filterType');
    } catch (e, stackTrace) {
      logger.e('FilterDataCubit: Error initializing',
          error: e, stackTrace: stackTrace);
      emit(state.copyWith(
        message: 'failedInitFilterData',
        filterType: _currentFilterType,
        selectedFilters: _selectedFilters,
      ));
      emit(FilterDataError(state));
    }
  }

  // Search filter data by query
  Future<void> searchFilterData(String query) async {
    try {
      _searchQuery = query.trim();

      if (_searchQuery.isEmpty) {
        // No query — fetch default page from API or local cache
        if (_shouldUseApi(_currentSourceId)) {
          final entities = await _getTagsByTypeUseCase(
            GetTagsByTypeParams(
              tagType: _currentFilterType,
              sourceId: _currentSourceId,
              page: 1,
              perPage: 50,
            ),
          );
          _filteredTags = entities.map(_tagEntityToTag).toList();
        } else {
          _filteredTags = await _tagDataManager.getTagsByType(
            _currentFilterType,
            limit: 100,
            source: _currentSourceId,
          );
        }
      } else {
        // Query — use autocomplete API or local search
        if (_shouldUseApi(_currentSourceId)) {
          final result = await _getTagAutocompleteUseCase(
            GetTagAutocompleteParams(
              query: _searchQuery,
              sourceId: _currentSourceId,
              tagType: _currentFilterType,
              limit: 30,
            ),
          );
          _filteredTags = result.suggestions.map(_tagEntityToTag).toList();
        } else {
          _filteredTags = await _tagDataManager.searchTags(
            _searchQuery,
            type: _currentFilterType,
            limit: 50,
            source: _currentSourceId,
          );
        }
      }

      emit(state.copyWith(
        filterType: _currentFilterType,
        searchResults: _filteredTags,
        selectedFilters: _selectedFilters,
        searchQuery: _searchQuery,
        isSearching: false,
        lastUpdated: DateTime.now(),
      ));

      emit(FilterDataLoaded(state));

      logger.d(
          'FilterDataCubit: Search results: ${_filteredTags.length} tags for query: "$_searchQuery"');
    } catch (e) {
      logger.e('FilterDataCubit: Error searching filter data', error: e);
      // Don't emit error for search, just continue with current state
    }
  }

  // Switch filter type (tag, artist, character, etc.)
  Future<void> switchFilterType(String filterType) async {
    try {
      logger.i('FilterDataCubit: Switching to filter type: $filterType');

      _currentFilterType = filterType;
      _searchQuery = '';

      emit(FilterDataLoading(state));

      if (_shouldUseApi(_currentSourceId)) {
        final entities = await _getTagsByTypeUseCase(
          GetTagsByTypeParams(
            tagType: filterType,
            sourceId: _currentSourceId,
            page: 1,
            perPage: 50,
          ),
        );
        _filteredTags = entities.map(_tagEntityToTag).toList();
      } else {
        _filteredTags = await _tagDataManager.getTagsByType(
          filterType,
          limit: 100,
          source: _currentSourceId,
        );
      }

      emit(state.copyWith(
        filterType: _currentFilterType,
        searchResults: _filteredTags,
        selectedFilters: _selectedFilters,
        searchQuery: _searchQuery,
        isSearching: false,
        lastUpdated: DateTime.now(),
        message: null,
      ));

      emit(FilterDataLoaded(state));

      logger.i(
          'FilterDataCubit: Switched to ${_filteredTags.length} tags for type: $filterType');
    } catch (e, stackTrace) {
      logger.e('FilterDataCubit: Error switching filter type',
          error: e, stackTrace: stackTrace);
      emit(state.copyWith(
        message: 'failedSwitchFilterType',
        filterType: _currentFilterType,
        selectedFilters: _selectedFilters,
      ));
      emit(FilterDataError(state));
    }
  }

  // Toggle filter item selection
  void toggleFilterItem(Tag tag, {bool? forceExclude}) {
    try {
      final existingIndex = _selectedFilters.indexWhere(
        (item) =>
            (item.tagId != null && item.tagId == tag.id) ||
            item.value == tag.name,
      );

      if (existingIndex >= 0) {
        final existingItem = _selectedFilters[existingIndex];

        if (existingItem.isExcluded) {
          // Currently excluded, remove it
          _selectedFilters.removeAt(existingIndex);
          logger.d('FilterDataCubit: Removed filter item: ${tag.name}');
        } else {
          // Currently included, switch to excluded
          _selectedFilters[existingIndex] = FilterItem.exclude(
            tag.name,
            tagId: tag.id,
            tagType: tag.type,
            tagName: tag.name,
            tagSlug: tag.slug,
          );
          logger.d('FilterDataCubit: Switched to exclude: ${tag.name}');
        }
      } else {
        // Not selected, add as include or exclude based on forceExclude
        final newItem = forceExclude == true
            ? FilterItem.exclude(
                tag.name,
                tagId: tag.id,
                tagType: tag.type,
                tagName: tag.name,
                tagSlug: tag.slug,
              )
            : FilterItem.include(
                tag.name,
                tagId: tag.id,
                tagType: tag.type,
                tagName: tag.name,
                tagSlug: tag.slug,
              );
        _selectedFilters.add(newItem);
        logger.d(
            'FilterDataCubit: Added filter item: ${tag.name} (${newItem.isExcluded ? 'exclude' : 'include'})');
      }

      // Force emit new state by creating completely new instance
      final currentState = state;
      // if (currentState is FilterDataLoaded) {
      // Create completely new state instance
      logger.d(
          'FilterDataCubit: Force emitting new state with ${_selectedFilters.length} selected filters');
      emit(state.copyWith(
        filterType: currentState.filterType,
        searchResults: currentState.searchResults,
        selectedFilters: List<FilterItem>.from(_selectedFilters),
        searchQuery: currentState.searchQuery,
        isSearching: currentState.isSearching,
        lastUpdated: DateTime.now(),
      ));

      emit(FilterDataLoaded(state));
      // }
    } catch (e) {
      logger.e('FilterDataCubit: Error toggling filter item', error: e);
    }
  }

  // Add filter item as include
  void addIncludeFilter(Tag tag) {
    toggleFilterItem(tag, forceExclude: false);
  }

  // Add filter item as exclude
  void addExcludeFilter(Tag tag) {
    toggleFilterItem(tag, forceExclude: true);
  }

  // Remove filter item
  void removeFilterItem(String value) {
    try {
      final removedCount = _selectedFilters.length;
      _selectedFilters.removeWhere((item) => item.value == value);
      final newCount = _selectedFilters.length;

      if (removedCount != newCount) {
        // Force emit new state by creating completely new instance
        final currentState = state;
        // if (currentState is FilterDataLoaded) {
        logger.d(
            'FilterDataCubit: Force emitting new state after removing $value, ${_selectedFilters.length} filters remaining');
        emit(state.copyWith(
          filterType: currentState.filterType,
          searchResults: currentState.searchResults,
          selectedFilters: List<FilterItem>.from(_selectedFilters),
          searchQuery: currentState.searchQuery,
          isSearching: currentState.isSearching,
          lastUpdated: DateTime.now(),
        ));

        emit(FilterDataLoaded(state));
        // }
        logger.d('FilterDataCubit: Removed filter item: $value');
      }
    } catch (e) {
      logger.e('FilterDataCubit: Error removing filter item', error: e);
    }
  }

  // Clear all selected filters
  void clearAllFilters() {
    try {
      final hadFilters = _selectedFilters.isNotEmpty;
      _selectedFilters.clear();

      if (hadFilters) {
        // Force emit new state by creating completely new instance
        final currentState = state;
        // if (currentState is FilterDataLoaded) {
        logger.d(
            'FilterDataCubit: Force emitting new state after clearing all filters');
        emit(
          state.copyWith(
            filterType: currentState.filterType,
            searchResults: currentState.searchResults,
            selectedFilters: <FilterItem>[],
            searchQuery: currentState.searchQuery,
            isSearching: currentState.isSearching,
            lastUpdated: DateTime.now(),
          ),
        );
        emit(FilterDataLoaded(state));
        // }
        logger.i('FilterDataCubit: Cleared all filter items');
      }
    } catch (e) {
      logger.e('FilterDataCubit: Error clearing filters', error: e);
    }
  }

  // Get selected filters
  List<FilterItem> getSelectedFilters() {
    return List<FilterItem>.from(_selectedFilters);
  }

  // Check if tag is selected
  FilterItem? getSelectedFilterItem(String tagName) {
    try {
      return _selectedFilters.firstWhere((item) => item.value == tagName);
    } catch (e) {
      return null;
    }
  }

  // Check if tag is selected as include
  bool isIncluded(String tagName) {
    final item = getSelectedFilterItem(tagName);
    return item != null && !item.isExcluded;
  }

  // Check if tag is selected as exclude
  bool isExcluded(String tagName) {
    final item = getSelectedFilterItem(tagName);
    return item != null && item.isExcluded;
  }

  // Get current filter type
  String get currentFilterType => _currentFilterType;

  // Get search query
  String get searchQuery => _searchQuery;
}
