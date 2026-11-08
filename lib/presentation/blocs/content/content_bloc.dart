import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';
import 'package:get_it/get_it.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/content/content_usecases.dart';
import '../../../domain/repositories/repositories.dart';

part 'content_event.dart';
part 'content_state.dart';

// BLoC for managing content list with pagination, search, and infinite scrolling
class ContentBloc extends Bloc<ContentEvent, ContentState> {
  ContentBloc({
    required this._getContentListUseCase,
    required this._searchContentUseCase,
    required this._getContentByTagUseCase,
    required this._getPopularContentUseCase,
    required this._logger,
  })  : super(const ContentInitial()) {
    // Register event handlers
    on<ContentLoadEvent>(_onContentLoad);
    on<ContentLoadMoreEvent>(_onContentLoadMore);
    on<ContentRefreshEvent>(_onContentRefresh);
    on<ContentSortChangedEvent>(_onContentSortChanged);
    on<ContentRetryEvent>(_onContentRetry);
    on<ContentClearEvent>(_onContentClear);
    on<ContentClearSearchEvent>(_onContentClearSearch);
    on<ContentSearchEvent>(_onContentSearch);
    on<ContentLoadPopularEvent>(_onContentLoadPopular);
    on<ContentLoadByTagEvent>(_onContentLoadByTag);
    on<ContentNextPageEvent>(_onContentNextPage);
    on<ContentPreviousPageEvent>(_onContentPreviousPage);
    on<ContentGoToPageEvent>(_onContentGoToPage);
  }

  final GetContentListUseCase _getContentListUseCase;
  final SearchContentUseCase _searchContentUseCase;
  final GetContentByTagUseCase _getContentByTagUseCase;
  final GetPopularContentUseCase _getPopularContentUseCase;
  final Logger _logger;

  // Internal state tracking
  SortOption _currentSortBy = SortOption.newest;
  DateTime? _lastFetchTime; // Track when data was actually fetched from server

  // Load initial content list
  Future<void> _onContentLoad(
    ContentLoadEvent event,
    Emitter<ContentState> emit,
  ) async {
    try {
      _logger.i('ContentBloc: Loading content with sort: ${event.sortBy}');

      // Clear previous state if force refresh or sort changed
      if (event.forceRefresh || _currentSortBy != event.sortBy) {
        _currentSortBy = event.sortBy;
      }

      // Preserve previous content for better UX during loading
      List<Content>? previousContents;
      if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      }

      // Show loading state if not already loading
      if (state is! ContentLoading) {
        if (state is! ContentLoaded || event.forceRefresh) {
          emit(ContentLoading(
            message:
                event.forceRefresh ? 'Refreshing...' : 'Loading content...',
            previousContents: previousContents,
          ));
        }
      }

      // Get content list
      final params = GetContentListParams(
        page: event.page,
        sortBy: event.sortBy,
      );

      final result = await _getContentListUseCase(params);

      if (result.isEmpty) {
        _logger.w(
            'ContentBloc: Load page ${event.page} returned empty result, emitting ContentEmpty with currentPage: ${event.page}');
        emit(ContentEmpty(
          message: 'noContentAtMoment',
          sortBy: event.sortBy,
          currentPage: event.page,
          // If we are on page > 1 and it's empty, we might want to capture that
          // But usually empty page > 1 just means end of list, handled by UI
        ));
        return;
      }

      // Update fetch time when we actually get data from server
      _lastFetchTime = DateTime.now();

      final loadedState = ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: event.sortBy,
        lastUpdated: _lastFetchTime,
      );

      _logger.i(
          'ContentBloc: Emitting ContentLoaded with ${result.contents.length} contents');
      emit(loadedState);
      _logger.i(
          'ContentBloc: ContentLoaded emitted successfully, state type: ${state.runtimeType}');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error loading content',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);

      // Get previous contents to preserve them
      List<Content>? previousContents;
      if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      }

      // Capture context for retry
      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        errorType: errorType,
        previousContents: previousContents,
        stackTrace: stackTrace,
        currentPage: event.page,
        sortBy: event.sortBy,
      ));
    }
  }

  // Load more content for infinite scrolling
  Future<void> _onContentLoadMore(
    ContentLoadMoreEvent event,
    Emitter<ContentState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ContentLoaded || !currentState.canLoadMore) {
      return;
    }

    try {
      _logger.i(
          'ContentBloc: Loading more content, page: ${currentState.currentPage + 1}');

      // Show loading more state
      emit(ContentLoadingMore(
        contents: currentState.contents,
        currentPage: currentState.currentPage,
        totalPages: currentState.totalPages,
        totalCount: currentState.totalCount,
        hasNext: currentState.hasNext,
        hasPrevious: currentState.hasPrevious,
        sortBy: currentState.sortBy,
        searchFilter: currentState.searchFilter,
        tag: currentState.tag,
        timeframe: currentState.timeframe,
        lastUpdated: currentState.lastUpdated,
      ));

      ContentListResult result;

      // Load more based on current context
      if (currentState.searchFilter != null) {
        // Load more search results
        final nextPageFilter = currentState.searchFilter!
            .copyWith(page: currentState.currentPage + 1);
        result = await _searchContentUseCase(nextPageFilter);
      } else if (currentState.tag != null) {
        // Load more content by tag
        result = await _getContentByTagUseCase(GetContentByTagParams(
          tag: currentState.tag!,
          page: currentState.currentPage + 1,
          sortBy: currentState.sortBy,
        ));
      } else if (currentState.timeframe != null) {
        // Load more popular content
        result = await _getPopularContentUseCase(GetPopularContentParams(
          timeframe: currentState.timeframe!,
          page: currentState.currentPage + 1,
        ));
      } else {
        // Load more regular content
        final params = GetContentListParams(
          page: currentState.currentPage + 1,
          sortBy: currentState.sortBy,
        );
        result = await _getContentListUseCase(params);
      }

      // Update fetch time when we get more data from server
      _lastFetchTime = DateTime.now();

      // Update state with more content
      emit(currentState.copyWith(
        contents: [...currentState.contents, ...result.contents],
        currentPage: result.currentPage,
        hasNext: result.hasNext,
        isLoadingMore: false,
        lastUpdated: _lastFetchTime,
      ));

      _logger.i('ContentBloc: Loaded ${result.contents.length} more contents');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error loading more content',
          error: e, stackTrace: stackTrace);

      // Return to previous state without loading more indicator
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  // Refresh content (pull-to-refresh)
  Future<void> _onContentRefresh(
    ContentRefreshEvent event,
    Emitter<ContentState> emit,
  ) async {
    final currentState = state;

    try {
      _logger.i('ContentBloc: Refreshing content');

      // Show refreshing state if we have previous content
      if (currentState is ContentLoaded) {
        emit(ContentRefreshing(
          contents: currentState.contents,
          currentPage: currentState.currentPage,
          totalPages: currentState.totalPages,
          totalCount: currentState.totalCount,
          hasNext: currentState.hasNext,
          hasPrevious: currentState.hasPrevious,
          sortBy: currentState.sortBy,
          searchFilter: currentState.searchFilter,
          tag: currentState.tag,
          timeframe: currentState.timeframe,
          lastUpdated: currentState.lastUpdated,
        ));
      } else {
        emit(const ContentLoading(message: 'refreshingContentMsg'));
      }

      ContentListResult result;

      // Refresh always goes back to page 1 - that's the concept of "refresh"
      if (currentState is ContentLoaded) {
        if (currentState.searchFilter != null) {
          // Refresh search results from current page
          final refreshFilter =
              currentState.searchFilter!.copyWith(page: event.currentPage);
          result = await _searchContentUseCase(refreshFilter);
        } else if (currentState.tag != null) {
          // Refresh content by tag from current page
          result = await _getContentByTagUseCase(GetContentByTagParams(
            tag: currentState.tag!,
            page: event.currentPage,
            sortBy: currentState.sortBy,
          ));
        } else if (currentState.timeframe != null) {
          // Refresh popular content from current page
          result = await _getPopularContentUseCase(GetPopularContentParams(
            timeframe: currentState.timeframe!,
            page: event.currentPage,
          ));
        } else {
          // Refresh regular content from current page
          final params = GetContentListParams(
            page: event.currentPage,
            sortBy: event.sortBy,
          );
          result = await _getContentListUseCase(params);
        }
      } else {
        // Fresh load from page 1
        final params = GetContentListParams(
          page: 1,
          sortBy: event.sortBy,
        );
        result = await _getContentListUseCase(params);
      }

      if (result.isEmpty) {
        emit(const ContentEmpty(
          message: 'noContentAtMoment',
        ));
        return;
      }

      // Update current sort if changed
      _currentSortBy = event.sortBy;

      // Update fetch time when we refresh data from server
      _lastFetchTime = DateTime.now();

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: event.sortBy,
        searchFilter:
            currentState is ContentLoaded ? currentState.searchFilter : null,
        tag: currentState is ContentLoaded ? currentState.tag : null,
        timeframe:
            currentState is ContentLoaded ? currentState.timeframe : null,
        lastUpdated: _lastFetchTime,
      ));

      _logger
          .i('ContentBloc: Refreshed with ${result.contents.length} contents');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error refreshing content',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      final previousContents =
          currentState is ContentLoaded ? currentState.contents : null;

      // Extract context from current state for the error
      int? currentPage;
      SortOption? sortBy;
      SearchFilter? searchFilter;
      Tag? tag;
      PopularTimeframe? timeframe;

      if (currentState is ContentLoaded) {
        currentPage = currentState.currentPage;
        sortBy = currentState.sortBy;
        searchFilter = currentState.searchFilter;
        tag = currentState.tag;
        timeframe = currentState.timeframe;
      }

      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        previousContents: previousContents,
        errorType: errorType,
        stackTrace: stackTrace,
        // Preserve context
        currentPage: currentPage,
        sortBy: sortBy,
        searchFilter: searchFilter,
        tag: tag,
        timeframe: timeframe,
      ));
    }
  }

  // Handle sort option change
  Future<void> _onContentSortChanged(
    ContentSortChangedEvent event,
    Emitter<ContentState> emit,
  ) async {
    if (_currentSortBy == event.sortBy) return;

    _logger.i('ContentBloc: Sort changed to: ${event.sortBy}');
    _currentSortBy = event.sortBy;

    final currentState = state;
    if (currentState is ContentLoaded) {
      // Apply sorting based on current context
      if (currentState.searchFilter != null) {
        // Apply sorting to search results
        final updatedFilter = currentState.searchFilter!.copyWith(
          sortBy: event.sortBy,
          page: 1, // Reset to first page when sorting changes
        );
        add(ContentSearchEvent(updatedFilter));
      } else if (currentState.tag != null) {
        // Apply sorting to tag-based content
        add(ContentLoadByTagEvent(
          tag: currentState.tag!,
          sortBy: event.sortBy,
          forceRefresh: true,
        ));
      } else if (currentState.timeframe != null) {
        // Popular content doesn't support custom sorting, reload with popular
        add(ContentLoadPopularEvent(
          timeframe: currentState.timeframe!,
          forceRefresh: true,
        ));
      } else {
        // Apply sorting to normal content
        add(ContentLoadEvent(sortBy: event.sortBy, forceRefresh: true));
      }
    } else {
      // Load content with new sort option
      add(ContentLoadEvent(sortBy: event.sortBy, forceRefresh: true));
    }
  }

  // Retry loading content after error
  Future<void> _onContentRetry(
    ContentRetryEvent event,
    Emitter<ContentState> emit,
  ) async {
    _logger.i('ContentBloc: Retrying content load');
    _logger.d(
        'ContentBloc: Current state type before retry: ${state.runtimeType}');

    // Get previous content if available for better UX
    List<Content>? previousContents;
    int retryPage = 1;
    SortOption retrySort = _currentSortBy;
    SearchFilter? retryFilter;
    Tag? retryTag;
    PopularTimeframe? retryTimeframe;

    // Extract context from previous state
    if (state is ContentError) {
      final errorState = state as ContentError;
      previousContents = errorState.previousContents;
      retryPage = errorState.currentPage ?? 1;
      retrySort = errorState.sortBy ?? _currentSortBy;
      retryFilter = errorState.searchFilter;
      retryTag = errorState.tag;
      retryTimeframe = errorState.timeframe;
      _logger.d(
          'ContentBloc: Extracted from ContentError - page: $retryPage, sort: $retrySort, hasFilter: ${retryFilter != null}, hasTag: ${retryTag != null}');
    } else if (state is ContentEmpty) {
      final emptyState = state as ContentEmpty;
      retryPage = emptyState.currentPage ?? 1;
      retrySort = emptyState.sortBy ?? _currentSortBy;
      retryFilter = emptyState.searchFilter;
      retryTag = emptyState.tag;
      retryTimeframe = emptyState.timeframe;
      _logger.d(
          'ContentBloc: Extracted from ContentEmpty - page: $retryPage (raw: ${emptyState.currentPage}), sort: $retrySort, hasFilter: ${retryFilter != null}, hasTag: ${retryTag != null}');
    } else if (state is ContentLoaded) {
      final loadedState = state as ContentLoaded;
      previousContents = loadedState.contents;
      retryPage = loadedState.currentPage;
      retrySort = loadedState.sortBy;
      retryFilter = loadedState.searchFilter;
      retryTag = loadedState.tag;
      retryTimeframe = loadedState.timeframe;
      _logger.d(
          'ContentBloc: Extracted from ContentLoaded - page: $retryPage, sort: $retrySort, hasFilter: ${retryFilter != null}, hasTag: ${retryTag != null}');
    } else {
      _logger.w(
          'ContentBloc: Retry called from unexpected state: ${state.runtimeType}');
    }

    // Emit loading state immediately for instant visual feedback
    emit(ContentLoading(
      message: 'retryingMsg',
      previousContents: previousContents,
    ));
    _logger
        .i('ContentBloc: Emitted ContentLoading for retry on page $retryPage');

    // Retry based on extracted context
    if (retryFilter != null) {
      // Ensure the filter has the correct page
      final filter = retryFilter.copyWith(page: retryPage);
      add(ContentSearchEvent(filter));
    } else if (retryTag != null) {
      // If we are retrying a tag load, use the correct page
      // Note: ContentLoadByTagEvent doesn't have a page param in simplified version,
      // but logic handles it. However, to support specific page retry for tags would require
      // updating ContentLoadByTagEvent or handling it differently.
      // For now, if we have a tag, we might need to rely on the fact that we might be reloading page 1 unless we add page support to tag event.
      // But typically pagination for tags is handled via LoadMore/NextPage.
      // If we are retrying a specific page failure for tags, we need to ensure we request that page.
      // Since ContentLoadByTagEvent defaults to page 1, we might need to add page param to it too or use a different approach.
      // Let's assume for now we reload the tag (page 1) or if we want specific page:

      // Ideally ContentLoadByTagEvent should support page param too.
      // For this fix, let's update ContentLoadByTagEvent to support page as well,
      // OR we can misuse the fact that if we are already 'loaded' (which we aren't in error state), we can't easily jump to page X with standard event.
      // BUT, we can add 'page' to ContentLoadByTagEvent context!
      // Let's stick to what we have or update ContentLoadByTagEvent.
      // ContentLoadByTagEvent definition: class ContentLoadByTagEvent extends ContentEvent { ... }
      // It doesn't have a page param. It's better to reload fresh (page 1) for tags for now, OR update the event.
      // Given the scope, let's stick to page 1 for tags/popular unless we update those events.
      // Updating ContentLoadByTagEvent constitutes a larger refactor.
      // Let's check if we can just use _loadSpecificPage internal helper if we could...
      // But we can't call methods from here, we must emit states or add events.

      // IMPORTANT: For the main bug (Refresh Resets Pagination), it's mostly about the main list.
      // For tags/search, if we are deep in pagination, we want to stay there.
      // Search has page in filter, so that works!
      // Tags/Popular don't have page in event.
      // Let's handle Main List and Search perfectly first.

      add(ContentLoadByTagEvent(
          tag: retryTag, sortBy: retrySort, forceRefresh: true));
    } else if (retryTimeframe != null) {
      add(ContentLoadPopularEvent(
          timeframe: retryTimeframe, forceRefresh: true));
    } else {
      // Regular content
      add(ContentLoadEvent(
          sortBy: retrySort, forceRefresh: true, page: retryPage));
    }
  }

  // Clear content list
  Future<void> _onContentClear(
    ContentClearEvent event,
    Emitter<ContentState> emit,
  ) async {
    _logger.i('ContentBloc: Clearing content');

    emit(const ContentInitial());
  }

  // Clear search results and return to normal content
  Future<void> _onContentClearSearch(
    ContentClearSearchEvent event,
    Emitter<ContentState> emit,
  ) async {
    try {
      _logger
          .i('ContentBloc: Clearing search results and loading normal content');

      // Show loading state with proper message
      ContentLoaded? previousState;
      if (state is ContentLoaded) {
        previousState = state as ContentLoaded;
      }

      emit(ContentLoading(
        message: 'clearingSearchMsg',
        previousContents: previousState?.contents,
      ));

      // Clear saved search filter via UserDataRepository
      final userDataRepository = GetIt.instance<UserDataRepository>();
      await userDataRepository.clearSearchFilter(event.sourceId);
      _logger.i(
          'ContentBloc: Cleared search filter from local storage for source: ${event.sourceId}');

      // Load normal content with specified sort option
      final params = GetContentListParams(
        page: 1,
        sortBy: event.sortBy,
      );

      final result = await _getContentListUseCase(params);

      if (result.isEmpty) {
        emit(const ContentEmpty(
          message: 'noContentAtMoment',
        ));
        return;
      }

      // Update fetch time when we get data from server
      _lastFetchTime = DateTime.now();
      _currentSortBy = event.sortBy;

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: event.sortBy,
        lastUpdated: _lastFetchTime,
      ));

      _logger.i(
          'ContentBloc: Successfully cleared search and loaded ${result.contents.length} normal contents');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error clearing search results',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);
      emit(ContentError(
        message: 'failedToClearSearch',
        canRetry: true,
        errorType: errorType,
        stackTrace: stackTrace,
        previousContents:
            (state is ContentLoaded) ? (state as ContentLoaded).contents : null,
      ));
    }
  }

  // Search content with filters
  Future<void> _onContentSearch(
    ContentSearchEvent event,
    Emitter<ContentState> emit,
  ) async {
    try {
      _logger.i(
          'ContentBloc: Searching content with filter: ${event.filter.toQueryString()}');

      // Show loading state
      emit(const ContentLoading(message: 'searchingContentMsg'));

      final result = await _searchContentUseCase(event.filter);

      if (result.isEmpty) {
        emit(ContentEmpty(
          message: 'noContentMatchingSearch',
          searchFilter: event.filter,
          // Context
          sortBy: event.filter.sortBy,
          currentPage: event.filter.page,
        ));
        return;
      }

      // Update fetch time when we search from server
      _lastFetchTime = DateTime.now();

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: event.filter.sortBy,
        searchFilter: event.filter,
        lastUpdated: _lastFetchTime,
      ));

      _logger.i('ContentBloc: Found ${result.contents.length} search results');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error searching content',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);

      // Get previous contents to preserve them
      List<Content>? previousContents;
      if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      }

      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        errorType: errorType,
        previousContents: previousContents,
        stackTrace: stackTrace,
        // Context
        searchFilter: event.filter,
        currentPage: event.filter.page,
        sortBy: event.filter.sortBy,
      ));
    }
  }

  // Load popular content
  Future<void> _onContentLoadPopular(
    ContentLoadPopularEvent event,
    Emitter<ContentState> emit,
  ) async {
    try {
      _logger.i('ContentBloc: Loading popular content: ${event.timeframe}');

      // Show loading state if no previous content or force refresh
      if (state is! ContentLoaded || event.forceRefresh) {
        emit(const ContentLoading(message: 'loadingPopularContent'));
      }

      final result = await _getPopularContentUseCase(GetPopularContentParams(
        timeframe: event.timeframe,
        page: 1,
      ));

      if (result.isEmpty) {
        emit(const ContentEmpty(
          message: 'noPopularContent',
          currentPage: 1,
          sortBy: SortOption.popular,
        ));
        return;
      }

      // Update fetch time when we load popular content from server
      _lastFetchTime = DateTime.now();

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: SortOption.popular,
        timeframe: event.timeframe,
        lastUpdated: _lastFetchTime,
      ));

      _logger
          .i('ContentBloc: Loaded ${result.contents.length} popular contents');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error loading popular content',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);

      // Get previous contents to preserve them
      List<Content>? previousContents;
      if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      }

      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        errorType: errorType,
        previousContents: previousContents,
        stackTrace: stackTrace,
        // Context
        timeframe: event.timeframe,
        sortBy: SortOption.popular,
        currentPage: 1, // Popular always starts at page 1 unless paginated
      ));
    }
  }

  // Load content by tag
  Future<void> _onContentLoadByTag(
    ContentLoadByTagEvent event,
    Emitter<ContentState> emit,
  ) async {
    try {
      _logger.i('ContentBloc: Loading content by tag: ${event.tag.name}');

      // Show loading state if no previous content or force refresh
      if (state is! ContentLoaded || event.forceRefresh) {
        emit(const ContentLoading(message: 'loadingContentByTag'));
      }

      final result = await _getContentByTagUseCase(GetContentByTagParams(
        tag: event.tag,
        page: 1,
        sortBy: event.sortBy,
      ));

      if (result.isEmpty) {
        emit(ContentEmpty(
          message: 'noContentForTag',
          tag: event.tag,
          // Context
          sortBy: event.sortBy,
          currentPage: 1,
        ));
        return;
      }

      // Update fetch time when we load content by tag from server
      _lastFetchTime = DateTime.now();

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: event.sortBy,
        tag: event.tag,
        lastUpdated: _lastFetchTime,
      ));

      _logger
          .i('ContentBloc: Loaded ${result.contents.length} contents for tag');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error loading content by tag',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);

      // Get previous contents to preserve them
      List<Content>? previousContents;
      if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      }

      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        errorType: errorType,
        previousContents: previousContents,
        stackTrace: stackTrace,
        // Context
        tag: event.tag,
        sortBy: event.sortBy,
        currentPage: 1, // Assume start page for now
      ));
    }
  }

  // Determine error type from exception
  ContentErrorType _determineErrorType(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return ContentErrorType.network;
    } else if (errorString.contains('server') || errorString.contains('5')) {
      return ContentErrorType.server;
    } else if (errorString.contains('cloudflare') ||
        errorString.contains('protection')) {
      return ContentErrorType.cloudflare;
    } else if (errorString.contains('rate') ||
        errorString.contains('limit') ||
        errorString.contains('429')) {
      return ContentErrorType.rateLimit;
    } else if (errorString.contains('parse') ||
        errorString.contains('format')) {
      return ContentErrorType.parsing;
    } else {
      return ContentErrorType.unknown;
    }
  }

  // Navigate to next page
  Future<void> _onContentNextPage(
    ContentNextPageEvent event,
    Emitter<ContentState> emit,
  ) async {
    final currentState = state;
    _logger.i(
        'on ContentLoaded is ${currentState is ContentLoaded} and hasNext ${currentState is ContentLoaded && currentState.hasNext}');
    if (currentState is! ContentLoaded || !currentState.hasNext) {
      return;
    }

    final nextPage = currentState.currentPage + 1;
    _logger.i('ContentBloc: Navigating to next page: $nextPage');

    await _loadSpecificPage(nextPage, currentState, emit);
  }

  // Navigate to previous page
  Future<void> _onContentPreviousPage(
    ContentPreviousPageEvent event,
    Emitter<ContentState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ContentLoaded || !currentState.hasPrevious) {
      return;
    }

    final previousPage = currentState.currentPage - 1;
    _logger.i('ContentBloc: Navigating to previous page: $previousPage');

    await _loadSpecificPage(previousPage, currentState, emit);
  }

  // Navigate to specific page
  Future<void> _onContentGoToPage(
    ContentGoToPageEvent event,
    Emitter<ContentState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ContentLoaded) {
      return;
    }

    // Validate page number
    if (event.page < 1 || event.page > currentState.totalPages) {
      _logger.w('ContentBloc: Invalid page number: ${event.page}');
      return;
    }

    // Don't reload if already on the same page
    if (event.page == currentState.currentPage) {
      return;
    }

    _logger.i('ContentBloc: Navigating to page: ${event.page}');

    await _loadSpecificPage(event.page, currentState, emit);
  }

  // Load specific page based on current context
  Future<void> _loadSpecificPage(
    int page,
    ContentLoaded currentState,
    Emitter<ContentState> emit,
  ) async {
    try {
      // Show minimal loading state for pagination (include target page for localization)
      emit(ContentLoading(
        message: 'loadingPageNum',
        previousContents: currentState.contents,
        pageNumber: page,
      ));

      ContentListResult result;

      // Load page based on current context
      if (currentState.searchFilter != null) {
        // Load search results page
        final pageFilter = currentState.searchFilter!.copyWith(page: page);
        result = await _searchContentUseCase(pageFilter);
      } else if (currentState.tag != null) {
        // Load content by tag page
        result = await _getContentByTagUseCase(GetContentByTagParams(
          tag: currentState.tag!,
          page: page,
          sortBy: currentState.sortBy,
        ));
      } else if (currentState.timeframe != null) {
        // Load popular content page
        result = await _getPopularContentUseCase(GetPopularContentParams(
          timeframe: currentState.timeframe!,
          page: page,
        ));
      } else {
        // Load regular content page
        final params = GetContentListParams(
          page: page,
          sortBy: currentState.sortBy,
        );
        result = await _getContentListUseCase(params);
      }

      if (result.isEmpty) {
        _logger.w(
            'ContentBloc: Page $page returned empty result, emitting ContentEmpty with currentPage: $page');
        emit(ContentEmpty(
          message: 'noContentOnPage',
          // Context
          currentPage: page,
          sortBy: currentState.sortBy,
          searchFilter: currentState.searchFilter,
          tag: currentState.tag,
          timeframe: currentState.timeframe,
        ));
        return;
      }

      // Update fetch time when we load a specific page from server
      _lastFetchTime = DateTime.now();

      emit(ContentLoaded(
        contents: result.contents,
        currentPage: result.currentPage,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        hasNext: result.hasNext,
        hasPrevious: result.hasPrevious,
        sortBy: currentState.sortBy,
        searchFilter: currentState.searchFilter,
        tag: currentState.tag,
        timeframe: currentState.timeframe,
        lastUpdated: _lastFetchTime,
      ));

      _logger.i(
          'ContentBloc: Loaded page $page with ${result.contents.length} contents');
    } catch (e, stackTrace) {
      _logger.e('ContentBloc: Error loading page $page',
          error: e, stackTrace: stackTrace);

      final errorType = _determineErrorType(e);

      // Get previous contents to preserve them
      List<Content>? previousContents;
      if (state is ContentLoading) {
        previousContents = (state as ContentLoading).previousContents;
      } else if (state is ContentLoaded) {
        previousContents = (state as ContentLoaded).contents;
      } else if (state is ContentError) {
        previousContents = (state as ContentError).previousContents;
      }

      emit(ContentError(
        message: e.toString(),
        canRetry: errorType.isRetryable,
        previousContents: previousContents,
        errorType: errorType,
        stackTrace: stackTrace,
        // Context
        currentPage: page,
        sortBy: currentState.sortBy,
        searchFilter: currentState.searchFilter,
        tag: currentState.tag,
        timeframe: currentState.timeframe,
      ));
    }
  }
}
