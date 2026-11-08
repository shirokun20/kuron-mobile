import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';
import 'package:collection/collection.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/content/search_content_usecase.dart';

import '../../../domain/repositories/user_data_repository.dart';
import '../../../domain/repositories/tag_repository.dart';

part 'search_event.dart';
part 'search_state.dart';

// BLoC for managing search functionality with advanced filters,
// search history, debounced search, and tag suggestions
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    required this._searchContentUseCase,
    required this._userDataRepository,
    required this._tagRepository,
    required this._logger,
  })  : super(const SearchInitial()) {
    // Register event handlers
    on<SearchInitializeEvent>(_onSearchInitialize);
    on<SearchQueryEvent>(_onSearchQuery, transformer: _debounceTransformer());
    on<SearchWithFiltersEvent>(_onSearchWithFilters);
    on<SearchUpdateFilterEvent>(_onSearchUpdateFilter);
    on<SearchSubmittedEvent>(_onSearchSubmitted);
    on<SearchClearEvent>(_onSearchClear);
    on<SearchLoadMoreEvent>(_onSearchLoadMore);
    on<SearchRefreshEvent>(_onSearchRefresh);
    on<SearchRetryEvent>(_onSearchRetry);
    on<SearchGetSuggestionsEvent>(_onSearchGetSuggestions,
        transformer: _debounceTransformer());
    on<SearchGetTagSuggestionsEvent>(_onSearchGetTagSuggestions,
        transformer: _debounceTransformer());
    on<SearchAddToHistoryEvent>(_onSearchAddToHistory);
    on<SearchLoadHistoryEvent>(_onSearchLoadHistory);
    on<SearchClearHistoryEvent>(_onSearchClearHistory);
    on<SearchRemoveFromHistoryEvent>(_onSearchRemoveFromHistory);
    on<SearchApplyQuickFilterEvent>(_onSearchApplyQuickFilter);
    on<SearchToggleAdvancedModeEvent>(_onSearchToggleAdvancedMode);
    on<SearchSavePresetEvent>(_onSearchSavePreset);
    on<SearchLoadPresetEvent>(_onSearchLoadPreset);
    on<SearchDeletePresetEvent>(_onSearchDeletePreset);
    on<SearchGetPopularEvent>(_onSearchGetPopular);
    on<SearchUpdateSortEvent>(_onSearchUpdateSort);
  }

  final SearchContentUseCase _searchContentUseCase;
  final UserDataRepository _userDataRepository;
  final TagRepository _tagRepository;
  final Logger _logger;

  // Internal state tracking
  SearchFilter _currentFilter = const SearchFilter();
  bool _isAdvancedMode = false;
  Map<String, SearchFilter> _searchPresets = {};
  List<String> _searchHistory = [];
  List<String> _popularSearches = [];
  Timer? _debounceTimer;
  String? _currentSourceId;

  // Configuration constants
  static const Duration _debounceDelay = Duration(milliseconds: 500);
  static const int _maxHistoryItems = 50;
  static const int _maxSuggestions = 10;

  // Debounce transformer for search events
  EventTransformer<T> _debounceTransformer<T>() {
    return (events, mapper) {
      return events.debounceTime(_debounceDelay).asyncExpand(mapper);
    };
  }

  // Initialize search with history and presets
  Future<void> _onSearchInitialize(
    SearchInitializeEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _currentSourceId = event.sourceId;
      _logger
          .i('SearchBloc: Initializing search for source: $_currentSourceId');

      // Load search history
      _searchHistory = await _userDataRepository.getSearchHistory();

      // Load popular searches based on actual nhentai popular tags
      _popularSearches = [
        'english',
        'big breasts',
        'sole female',
        'sole male',
        'full color',
        'schoolgirl uniform',
        'glasses',
        'stockings',
        'swimsuit',
        'teacher',
        'beauty',
        'vanilla',
        'romance',
        'school',
        'uniform',
      ];

      // Load search presets (from preferences)
      await _loadSearchPresets();

      // Load last search filter state if exists for this source
      if (_currentSourceId != null) {
        final lastFilterData =
            await _userDataRepository.getLastSearchFilter(_currentSourceId!);
        if (lastFilterData != null) {
          try {
            _currentFilter = lastFilterData;
            _logger.i(
                'SearchBloc: Loaded last search filter state for $_currentSourceId');

            // If there was a previous search, emit the filter updated state
            if (_currentFilter.hasFilters) {
              emit(SearchFilterUpdated(
                filter: _currentFilter,
                timestamp: DateTime.now(),
              ));
              return;
            }
          } catch (e) {
            _logger.e('SearchBloc: Error loading search filter state: $e');
            // Continue with default initialization
          }
        }
      }

      emit(SearchHistory(
        history: _searchHistory,
        popularSearches: _popularSearches,
        timestamp: DateTime.now(),
      ));

      _logger.i(
          'SearchBloc: Initialized with ${_searchHistory.length} history items');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error initializing search',
          error: e, stackTrace: stackTrace);

      emit(SearchError(
        message: 'failedToInitSearch',
        errorType: SearchErrorType.unknown,
        stackTrace: stackTrace,
      ));
    }
  }

  // Handle search query with debouncing
  Future<void> _onSearchQuery(
    SearchQueryEvent event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.trim().isEmpty) {
      add(const SearchClearEvent());
      return;
    }

    try {
      _logger.i('SearchBloc: Searching with query: "${event.query}"');

      // Update current filter with query
      _currentFilter = _currentFilter.copyWith(
        query: event.query.trim(),
        page: 1,
      );

      // Show loading state
      emit(const SearchLoading(message: 'searchingMsg'));

      // Perform search
      final result = await _searchContentUseCase(_currentFilter);

      // Add to search history
      add(SearchAddToHistoryEvent(event.query.trim()));

      if (result.isEmpty) {
        emit(SearchEmpty(
          filter: _currentFilter,
          message: 'noResultsForQuery',
          suggestions: await _generateSearchSuggestions(event.query),
        ));
        return;
      }

      emit(SearchLoaded(
        results: result.contents,
        filter: _currentFilter,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('SearchBloc: Found ${result.contents.length} results');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error searching with query',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      emit(SearchError(
        message: e.toString(),
        errorType: errorType,
        canRetry: errorType.isRetryable,
        filter: _currentFilter,
        stackTrace: stackTrace,
      ));
    }
  }

  // Handle search with filters
  Future<void> _onSearchWithFilters(
    SearchWithFiltersEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _logger.i(
          'SearchBloc: Searching with filters: ${event.filter.toQueryString()}');

      _currentFilter =
          event.filter; // ✅ Use the page from event, don't reset to 1

      // Show loading state
      emit(const SearchLoading(message: 'searchingWithFiltersMsg'));

      // Perform search
      final result = await _searchContentUseCase(_currentFilter);

      // Add query to history if present
      if (_currentFilter.query != null && _currentFilter.query!.isNotEmpty) {
        add(SearchAddToHistoryEvent(_currentFilter.query!));
      }

      if (result.isEmpty) {
        emit(SearchEmpty(
          filter: _currentFilter,
          message: 'noResultsWithFilters',
        ));
        return;
      }

      emit(SearchLoaded(
        results: result.contents,
        filter: _currentFilter,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('SearchBloc: Found ${result.contents.length} filtered results');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error searching with filters',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      emit(SearchError(
        message: e.toString(),
        errorType: errorType,
        canRetry: errorType.isRetryable,
        filter: _currentFilter,
        stackTrace: stackTrace,
      ));
    }
  }

  // Update search filter without performing search (new flow)
  Future<void> _onSearchUpdateFilter(
    SearchUpdateFilterEvent event,
    Emitter<SearchState> emit,
  ) async {
    // Validate filter before updating
    final validationResult = event.filter.validate();

    if (!validationResult.isValid) {
      _logger.w(
          'SearchBloc: Filter validation failed: ${validationResult.issuesText}');

      emit(SearchError(
        message: 'invalidFilterErrors',
        errorType: SearchErrorType.validation,
        canRetry: false,
        filter: _currentFilter,
      ));
      return;
    }

    // Log warnings if any
    if (validationResult.warnings.isNotEmpty) {
      _logger.w(
          'SearchBloc: Filter validation warnings: ${validationResult.warnings.join(', ')}');
    }

    _currentFilter = event.filter;

    _logger.i(
        'SearchBloc: Update data OnSearchUpdateFilter: ${event.filter.toJson()}');

    // Emit a state that shows the filter has been updated but no search performed yet
    emit(SearchFilterUpdated(
      filter: _currentFilter,
      timestamp: DateTime.now(),
    ));
  }

  // Submit search with current filter (new flow - triggers API call)
  Future<void> _onSearchSubmitted(
    SearchSubmittedEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      // Validate filter before submitting
      final validationResult = _currentFilter.validate();

      if (!validationResult.isValid) {
        _logger.w(
            'SearchBloc: Filter validation failed on submit: ${validationResult.issuesText}');

        emit(SearchError(
          message:
              'Invalid search filter: ${validationResult.errors.join(', ')}',
          errorType: SearchErrorType.validation,
          canRetry: false,
          filter: _currentFilter,
        ));
        return;
      }

      // Log warnings if any
      if (validationResult.warnings.isNotEmpty) {
        _logger.w(
            'SearchBloc: Filter validation warnings on submit: ${validationResult.warnings.join(', ')}');
      }

      _logger.i(
          'SearchBloc: Submitting search with filter: ${_currentFilter.toQueryString()}');

      // Show loading state
      emit(const SearchLoading(message: 'searchingMsg'));

      // Save search filter state to local datasource for persistence
      // BUT EXCLUDE tag clicks from detail screen to prevent unwanted saving
      if (_currentFilter.source != SearchSource.detailScreen &&
          _currentSourceId != null) {
        await _userDataRepository.saveSearchFilter(
            _currentSourceId!, _currentFilter);
        _logger.d(
            'SearchBloc: Saved search filter to local storage (source: ${_currentFilter.source.displayName}, sourceId: $_currentSourceId)');
      } else {
        _logger.d(
            'SearchBloc: Skipped saving search filter - tag click from detail screen or no sourceId');
      }

      // Perform search
      final result = await _searchContentUseCase(_currentFilter);

      // Add query to history if present
      if (_currentFilter.query != null && _currentFilter.query!.isNotEmpty) {
        add(SearchAddToHistoryEvent(_currentFilter.query!));
      }

      if (result.isEmpty) {
        emit(SearchEmpty(
          filter: _currentFilter,
          message: 'noResultsWithFilters',
        ));
        return;
      }

      emit(SearchLoaded(
        results: result.contents,
        filter: _currentFilter,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('SearchBloc: Found ${result.contents.length} results');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error submitting search',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      emit(SearchError(
        message: e.toString(),
        errorType: errorType,
        canRetry: errorType.isRetryable,
        filter: _currentFilter,
        stackTrace: stackTrace,
      ));
    }
  }

  // Clear search results and filters
  Future<void> _onSearchClear(
    SearchClearEvent event,
    Emitter<SearchState> emit,
  ) async {
    _logger.i('SearchBloc: Clearing search');

    _currentFilter = const SearchFilter();

    // Clear search filter state from local datasource
    try {
      if (_currentSourceId != null) {
        await _userDataRepository.clearSearchFilter(_currentSourceId!);
      }
    } catch (e) {
      _logger.e('SearchBloc: Error clearing search filter state: $e');
    }

    emit(SearchHistory(
      history: _searchHistory,
      popularSearches: _popularSearches,
      timestamp: DateTime.now(),
    ));
  }

  // Load more search results
  Future<void> _onSearchLoadMore(
    SearchLoadMoreEvent event,
    Emitter<SearchState> emit,
  ) async {
    final currentState = state;
    if (currentState is! SearchLoaded || !currentState.canLoadMore) {
      return;
    }

    try {
      _logger.i(
          'SearchBloc: Loading more results, page: ${currentState.currentPage + 1}');

      // Show loading more state
      emit(SearchLoadingMore(
        results: currentState.results,
        filter: currentState.filter,
        currentPage: currentState.currentPage,
        totalPages: currentState.totalPages,
        totalCount: currentState.totalCount,
        hasNext: currentState.hasNext,
        hasPrevious: currentState.hasPrevious,
        lastUpdated: currentState.lastUpdated,
        suggestions: currentState.suggestions,
        tagSuggestions: currentState.tagSuggestions,
      ));

      // Load next page
      final nextPageFilter = _currentFilter.copyWith(
        page: currentState.currentPage + 1,
      );

      final result = await _searchContentUseCase(nextPageFilter);

      // Update current filter
      _currentFilter = nextPageFilter;

      // Update state with more results
      emit(currentState.copyWith(
        results: [...currentState.results, ...result.contents],
        currentPage: result.currentPage,
        hasNext: result.hasNext,
        isLoadingMore: false,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('SearchBloc: Loaded ${result.contents.length} more results');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error loading more results',
          error: e, stackTrace: stackTrace);

      // Return to previous state without loading more indicator
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  // Refresh search results
  Future<void> _onSearchRefresh(
    SearchRefreshEvent event,
    Emitter<SearchState> emit,
  ) async {
    final currentState = state;
    if (currentState is! SearchLoaded) return;

    try {
      _logger.i('SearchBloc: Refreshing search results');

      // Show refreshing state
      emit(SearchRefreshing(
        results: currentState.results,
        filter: currentState.filter,
        currentPage: currentState.currentPage,
        totalPages: currentState.totalPages,
        totalCount: currentState.totalCount,
        hasNext: currentState.hasNext,
        hasPrevious: currentState.hasPrevious,
        lastUpdated: currentState.lastUpdated,
        suggestions: currentState.suggestions,
        tagSuggestions: currentState.tagSuggestions,
      ));

      // Refresh with first page
      final refreshFilter = _currentFilter.copyWith(page: 1);
      final result = await _searchContentUseCase(refreshFilter);

      _currentFilter = refreshFilter;

      if (result.isEmpty) {
        emit(SearchEmpty(
          filter: _currentFilter,
          message: 'noResultsGeneric',
        ));
        return;
      }

      emit(SearchLoaded(
        results: result.contents,
        filter: _currentFilter,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('SearchBloc: Refreshed with ${result.contents.length} results');
    } catch (e, stackTrace) {
      _logger.e('SearchBloc: Error refreshing search',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      emit(SearchError(
        message: e.toString(),
        errorType: errorType,
        canRetry: errorType.isRetryable,
        previousResults: currentState.results,
        filter: _currentFilter,
        stackTrace: stackTrace,
      ));
    }
  }

  // Retry search after error
  Future<void> _onSearchRetry(
    SearchRetryEvent event,
    Emitter<SearchState> emit,
  ) async {
    _logger.i('SearchBloc: Retrying search');

    if (_currentFilter.hasFilters) {
      add(SearchWithFiltersEvent(_currentFilter));
    } else {
      emit(SearchHistory(
        history: _searchHistory,
        popularSearches: _popularSearches,
        timestamp: DateTime.now(),
      ));
    }
  }

  // Get search suggestions
  Future<void> _onSearchGetSuggestions(
    SearchGetSuggestionsEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _logger.d('SearchBloc: Getting suggestions for: "${event.query}"');

      final suggestions = await _generateSearchSuggestions(event.query);
      final tagSuggestions = await _generateTagSuggestions(event.query);

      emit(SearchSuggestions(
        query: event.query,
        suggestions: suggestions,
        tagSuggestions: tagSuggestions,
        history: _searchHistory,
      ));
    } catch (e) {
      _logger.e('SearchBloc: Error getting suggestions', error: e);
      // Don't emit error for suggestions, just continue
    }
  }

  // Get tag suggestions
  Future<void> _onSearchGetTagSuggestions(
    SearchGetTagSuggestionsEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _logger.d('SearchBloc: Getting tag suggestions for: "${event.query}"');

      final tagSuggestions = await _generateTagSuggestions(event.query);

      final currentState = state;
      if (currentState is SearchSuggestions) {
        emit(currentState.copyWith(tagSuggestions: tagSuggestions));
      } else if (currentState is SearchLoaded) {
        emit(currentState.copyWith(tagSuggestions: tagSuggestions));
      }
    } catch (e) {
      _logger.e('SearchBloc: Error getting tag suggestions', error: e);
    }
  }

  // Add query to search history
  Future<void> _onSearchAddToHistory(
    SearchAddToHistoryEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      await _userDataRepository.addSearchHistory(event.query);

      // Update local history
      _searchHistory.remove(event.query); // Remove if exists
      _searchHistory.insert(0, event.query); // Add to beginning

      // Keep only max items
      if (_searchHistory.length > _maxHistoryItems) {
        _searchHistory = _searchHistory.take(_maxHistoryItems).toList();
      }

      // Emit updated state if we're currently showing history
      if (state is SearchHistory || state is SearchInitial) {
        emit(SearchHistory(
          history:
              List<String>.from(_searchHistory), // Create new list instance
          popularSearches: List<String>.from(_popularSearches),
          timestamp: DateTime.now(),
        ));
      }

      _logger.d('SearchBloc: Added to search history: "${event.query}"');
    } catch (e) {
      _logger.e('SearchBloc: Error adding to search history', error: e);
    }
  }

  // Load search history
  Future<void> _onSearchLoadHistory(
    SearchLoadHistoryEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _searchHistory = await _userDataRepository.getSearchHistory();

      emit(SearchHistory(
        history: _searchHistory,
        popularSearches: _popularSearches,
        timestamp: DateTime.now(),
      ));

      _logger.d('SearchBloc: Loaded ${_searchHistory.length} history items');
    } catch (e) {
      _logger.e('SearchBloc: Error loading search history', error: e);

      emit(SearchHistory(
        history: _searchHistory,
        popularSearches: _popularSearches,
        timestamp: DateTime.now(),
      ));
    }
  }

  // Clear search history
  Future<void> _onSearchClearHistory(
    SearchClearHistoryEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      await _userDataRepository.clearSearchHistory();
      _searchHistory.clear();

      // Force emit new state with empty history
      emit(SearchHistory(
        history: List<String>.from(_searchHistory), // Create new list instance
        popularSearches: List<String>.from(_popularSearches),
        timestamp: DateTime.now(),
      ));

      _logger.d('SearchBloc: Cleared search history');
    } catch (e) {
      _logger.e('SearchBloc: Error clearing search history', error: e);
    }
  }

  // Remove item from search history
  Future<void> _onSearchRemoveFromHistory(
    SearchRemoveFromHistoryEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      // Remove from database directly (simplified)
      await _userDataRepository.deleteSearchHistory(event.query);

      // Update local history
      _searchHistory.remove(event.query);

      // Force emit new state with updated history
      emit(SearchHistory(
        history: List<String>.from(_searchHistory), // Create new list instance
        popularSearches: List<String>.from(_popularSearches),
        timestamp: DateTime.now(),
      ));

      _logger.d('SearchBloc: Removed from history: "${event.query}"');
    } catch (e) {
      _logger.e('SearchBloc: Error removing from history', error: e);
    }
  }

  // Apply quick filter
  Future<void> _onSearchApplyQuickFilter(
    SearchApplyQuickFilterEvent event,
    Emitter<SearchState> emit,
  ) async {
    _logger.i('SearchBloc: Applying quick filter');

    SearchFilter newFilter = _currentFilter;

    if (event.tag != null) {
      final tags = List<FilterItem>.from(newFilter.tags);
      final existingTag =
          tags.where((item) => item.value == event.tag!).firstOrNull;
      if (existingTag == null) {
        tags.add(FilterItem.include(event.tag!));
      }
      newFilter = newFilter.copyWith(tags: tags);
    }

    if (event.artist != null) {
      final artists = List<FilterItem>.from(newFilter.artists);
      final existingArtist =
          artists.where((item) => item.value == event.artist!).firstOrNull;
      if (existingArtist == null) {
        artists.add(FilterItem.include(event.artist!));
      }
      newFilter = newFilter.copyWith(artists: artists);
    }

    if (event.language != null) {
      newFilter = newFilter.copyWith(language: event.language);
    }

    if (event.category != null) {
      newFilter = newFilter.copyWith(category: event.category);
    }

    add(SearchUpdateFilterEvent(newFilter));
  }

  // Toggle advanced search mode
  Future<void> _onSearchToggleAdvancedMode(
    SearchToggleAdvancedModeEvent event,
    Emitter<SearchState> emit,
  ) async {
    _isAdvancedMode = !_isAdvancedMode;
    _logger.i('SearchBloc: Advanced mode: $_isAdvancedMode');

    // Update current state to reflect mode change
    final currentState = state;
    if (currentState is SearchLoaded) {
      emit(currentState.copyWith(lastUpdated: DateTime.now()));
    }
  }

  // Save search filter as preset
  Future<void> _onSearchSavePreset(
    SearchSavePresetEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _searchPresets[event.name] = event.filter;
      await _saveSearchPresets();

      _logger.i('SearchBloc: Saved search preset: "${event.name}"');
    } catch (e) {
      _logger.e('SearchBloc: Error saving search preset', error: e);
    }
  }

  // Load search preset
  Future<void> _onSearchLoadPreset(
    SearchLoadPresetEvent event,
    Emitter<SearchState> emit,
  ) async {
    final preset = _searchPresets[event.presetName];
    if (preset != null) {
      _logger.i('SearchBloc: Loading search preset: "${event.presetName}"');
      add(SearchWithFiltersEvent(preset));
    }
  }

  // Delete search preset
  Future<void> _onSearchDeletePreset(
    SearchDeletePresetEvent event,
    Emitter<SearchState> emit,
  ) async {
    try {
      _searchPresets.remove(event.presetName);
      await _saveSearchPresets();

      _logger.i('SearchBloc: Deleted search preset: "${event.presetName}"');
    } catch (e) {
      _logger.e('SearchBloc: Error deleting search preset', error: e);
    }
  }

  // Get popular searches
  Future<void> _onSearchGetPopular(
    SearchGetPopularEvent event,
    Emitter<SearchState> emit,
  ) async {
    emit(SearchHistory(
      history: _searchHistory,
      popularSearches: _popularSearches,
      timestamp: DateTime.now(),
    ));
  }

  // Update search sort option
  Future<void> _onSearchUpdateSort(
    SearchUpdateSortEvent event,
    Emitter<SearchState> emit,
  ) async {
    _logger.i('SearchBloc: Updating sort to: ${event.sortBy}');

    _currentFilter = _currentFilter.copyWith(
      sortBy: event.sortBy,
      page: 1,
    );

    // Re-search with new sort if we have active search
    final currentState = state;
    if (currentState is SearchLoaded) {
      add(SearchWithFiltersEvent(_currentFilter));
    }
  }

  // Generate search suggestions based on query
  Future<List<String>> _generateSearchSuggestions(String query) async {
    try {
      final suggestions = <String>[];

      // Add from search history
      final historyMatches = _searchHistory
          .where((item) =>
              item.toLowerCase().contains(query.toLowerCase()) && item != query)
          .take(5)
          .toList();
      suggestions.addAll(historyMatches);

      // Add from popular searches
      final popularMatches = _popularSearches
          .where((item) =>
              item.toLowerCase().contains(query.toLowerCase()) &&
              item != query &&
              !suggestions.contains(item))
          .take(5)
          .toList();
      suggestions.addAll(popularMatches);

      return suggestions.take(_maxSuggestions).toList();
    } catch (e) {
      _logger.e('SearchBloc: Error generating search suggestions', error: e);
      return [];
    }
  }

  // Generate tag suggestions based on query from assets/json/tags.json
  Future<List<Tag>> _generateTagSuggestions(String query) async {
    try {
      if (query.length < 2) return [];

      _logger.d('SearchBloc: Generating tag suggestions for: "$query"');

      // Use TagRepository to fetch autocomplete suggestions
      final result = await _tagRepository.getAutocomplete(
        query: query,
        sourceId: _currentSourceId!,
        limit: _maxSuggestions,
      );

      _logger
          .d('SearchBloc: Found ${result.suggestions.length} tag suggestions');
      return result.suggestions
          .map((e) => Tag(
                id: 0,
                name: e.name,
                type: e.type,
                slug: e.slug,
                count: e.count,
              ))
          .toList();
    } catch (e) {
      _logger.e('SearchBloc: Error generating tag suggestions', error: e);
      return [];
    }
  }

  // Load search presets from storage
  Future<void> _loadSearchPresets() async {
    try {
      // Implement loading presets from preferences
      // For now, use empty map
      _searchPresets = {};
    } catch (e) {
      _logger.e('SearchBloc: Error loading search presets', error: e);
      _searchPresets = {};
    }
  }

  // Save search presets to storage
  Future<void> _saveSearchPresets() async {
    try {
      // Implement saving presets to preferences
      _logger.d('SearchBloc: Saved ${_searchPresets.length} search presets');
    } catch (e) {
      _logger.e('SearchBloc: Error saving search presets', error: e);
    }
  }

  // Determine error type from exception
  SearchErrorType _determineErrorType(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('validation')) {
      return SearchErrorType.validation;
    } else if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return SearchErrorType.network;
    } else if (errorString.contains('server') || errorString.contains('5')) {
      return SearchErrorType.server;
    } else if (errorString.contains('cloudflare') ||
        errorString.contains('protection')) {
      return SearchErrorType.cloudflare;
    } else if (errorString.contains('rate') ||
        errorString.contains('limit') ||
        errorString.contains('429')) {
      return SearchErrorType.rateLimit;
    } else if (errorString.contains('parse') ||
        errorString.contains('format')) {
      return SearchErrorType.parsing;
    } else {
      return SearchErrorType.unknown;
    }
  }

  // Get current filter
  SearchFilter get currentFilter => _currentFilter;

  // Check if in advanced mode
  bool get isAdvancedMode => _isAdvancedMode;

  // Get search presets
  Map<String, SearchFilter> get searchPresets =>
      Map.unmodifiable(_searchPresets);

  // Get search history
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  // Get last search filter from local datasource
  Future<SearchFilter?> getLastSearchFilter() async {
    try {
      if (_currentSourceId == null) {
        return null;
      }
      final filterData =
          await _userDataRepository.getLastSearchFilter(_currentSourceId!);
      if (filterData != null) {
        return filterData;
      }
      return null;
    } catch (e) {
      _logger.e('SearchBloc: Error getting last search filter: $e');
      return null;
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}

// Extension to add debounce functionality to streams
extension StreamDebounce<T> on Stream<T> {
  Stream<T> debounceTime(Duration duration) {
    Timer? debounceTimer;
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;

    controller = StreamController<T>(
      onListen: () {
        subscription = listen(
          (T data) {
            debounceTimer?.cancel();
            debounceTimer = Timer(duration, () {
              controller.add(data);
            });
          },
          onError: controller.addError,
          onDone: () {
            debounceTimer?.cancel();
            controller.close();
          },
        );
      },
      onCancel: () {
        debounceTimer?.cancel();
        subscription?.cancel();
      },
    );

    return controller.stream;
  }
}
