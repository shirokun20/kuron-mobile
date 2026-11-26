part of 'content_bloc.dart';

// Base class for all content states
abstract class ContentState extends Equatable {
  const ContentState();

  @override
  List<Object?> get props => [];
}

// Initial state when bloc is created
class ContentInitial extends ContentState {
  const ContentInitial();
}

// State when content is being loaded for the first time
class ContentLoading extends ContentState {
  const ContentLoading({
    this.message = 'Loading content...',
    this.previousContents,
    this.pageNumber,
    this.progress = 0.2,
  });

  final String message;
  final List<Content>? previousContents;
  final int? pageNumber;
  final double progress;

  @override
  List<Object?> get props => [message, previousContents, pageNumber, progress];
}

// State when content is successfully loaded
class ContentLoaded extends ContentState {
  const ContentLoaded({
    required this.contents,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.hasNext,
    required this.hasPrevious,
    required this.sortBy,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.searchFilter,
    this.tag,
    this.timeframe,
    this.lastUpdated,
  });

  final List<Content> contents;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasNext;
  final bool hasPrevious;
  final SortOption sortBy;
  final bool isLoadingMore;
  final bool isRefreshing;
  final SearchFilter? searchFilter;
  final Tag? tag;
  final PopularTimeframe? timeframe;
  final DateTime? lastUpdated;

  @override
  List<Object?> get props => [
    contents,
    currentPage,
    totalPages,
    totalCount,
    hasNext,
    hasPrevious,
    sortBy,
    isLoadingMore,
    isRefreshing,
    searchFilter,
    tag,
    timeframe,
    lastUpdated,
  ];

  // Check if content list is empty
  bool get isEmpty => contents.isEmpty;

  // Check if content list is not empty
  bool get isNotEmpty => contents.isNotEmpty;

  // Get content count
  int get count => contents.length;

  // Check if can load more content
  bool get canLoadMore => hasNext && !isLoadingMore;

  // Check if currently loading or refreshing
  bool get isLoading => isLoadingMore || isRefreshing;

  // Get loading state message
  String get loadingMessage {
    if (isRefreshing) return 'Refreshing content...';
    if (isLoadingMore) return 'Loading more content...';
    return 'Loading content...';
  }

  // Create copy with updated values
  ContentLoaded copyWith({
    List<Content>? contents,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? hasNext,
    bool? hasPrevious,
    SortOption? sortBy,
    bool? isLoadingMore,
    bool? isRefreshing,
    SearchFilter? searchFilter,
    Tag? tag,
    PopularTimeframe? timeframe,
    DateTime? lastUpdated,
  }) {
    return ContentLoaded(
      contents: contents ?? this.contents,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasNext: hasNext ?? this.hasNext,
      hasPrevious: hasPrevious ?? this.hasPrevious,
      sortBy: sortBy ?? this.sortBy,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      searchFilter: searchFilter ?? this.searchFilter,
      tag: tag ?? this.tag,
      timeframe: timeframe ?? this.timeframe,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  // Create copy with additional content (for pagination)
  ContentLoaded copyWithMoreContent(List<Content> moreContents) {
    return copyWith(
      contents: [...contents, ...moreContents],
      isLoadingMore: false,
    );
  }

  // Create copy with refreshed content
  ContentLoaded copyWithRefreshedContent(ContentListResult result) {
    return ContentLoaded(
      contents: result.contents,
      currentPage: result.currentPage,
      totalPages: result.totalPages,
      totalCount: result.totalCount,
      hasNext: result.hasNext,
      hasPrevious: result.hasPrevious,
      sortBy: sortBy,
      isLoadingMore: false,
      isRefreshing: false,
      searchFilter: searchFilter,
      tag: tag,
      timeframe: timeframe,
      lastUpdated: DateTime.now(),
    );
  }

  // Create copy with updated content item
  ContentLoaded copyWithUpdatedContent(Content updatedContent) {
    final updatedContents = contents.map((content) {
      return content.id == updatedContent.id ? updatedContent : content;
    }).toList();

    return copyWith(contents: updatedContents, lastUpdated: DateTime.now());
  }

  // Create copy with removed content
  ContentLoaded copyWithRemovedContent(String contentId) {
    final filteredContents = contents
        .where((content) => content.id != contentId)
        .toList();

    return copyWith(
      contents: filteredContents,
      totalCount: totalCount - 1,
      lastUpdated: DateTime.now(),
    );
  }

  // Get content type description
  String get contentTypeDescription {
    if (searchFilter != null) {
      return 'Search Results';
    } else if (tag != null) {
      return 'Tag: ${tag!.name}';
    } else if (timeframe != null) {
      return 'Popular (${timeframe!.displayName})';
    } else {
      return 'Latest Content';
    }
  }
}

// State when loading more content (infinite scroll)
class ContentLoadingMore extends ContentLoaded {
  const ContentLoadingMore({
    required super.contents,
    required super.currentPage,
    required super.totalPages,
    required super.totalCount,
    required super.hasNext,
    required super.hasPrevious,
    required super.sortBy,
    super.searchFilter,
    super.tag,
    super.timeframe,
    super.lastUpdated,
  }) : super(isLoadingMore: true);
}

// State when refreshing content (pull-to-refresh)
class ContentRefreshing extends ContentLoaded {
  const ContentRefreshing({
    required super.contents,
    required super.currentPage,
    required super.totalPages,
    required super.totalCount,
    required super.hasNext,
    required super.hasPrevious,
    required super.sortBy,
    super.searchFilter,
    super.tag,
    super.timeframe,
    super.lastUpdated,
  }) : super(isRefreshing: true);
}

// State when content loading fails
class ContentError extends ContentState {
  const ContentError({
    required this.message,
    required this.canRetry,
    this.previousContents,
    this.errorType = ContentErrorType.network,
    this.stackTrace,
    // Context preservation
    this.currentPage,
    this.totalPages,
    this.totalCount,
    this.sortBy,
    this.searchFilter,
    this.tag,
    this.timeframe,
  });

  final String message;
  final bool canRetry;
  final List<Content>? previousContents;
  final ContentErrorType errorType;
  final StackTrace? stackTrace;

  // Context fields
  final int? currentPage;
  final int? totalPages;
  final int? totalCount;
  final SortOption? sortBy;
  final SearchFilter? searchFilter;
  final Tag? tag;
  final PopularTimeframe? timeframe;

  @override
  List<Object?> get props => [
    message,
    canRetry,
    previousContents,
    errorType,
    stackTrace,
    currentPage,
    totalPages,
    totalCount,
    sortBy,
    searchFilter,
    tag,
    timeframe,
  ];

  // Check if has previous content to show
  bool get hasPreviousContent =>
      previousContents != null && previousContents!.isNotEmpty;

  // Get error icon based on error type
  String get errorIcon {
    switch (errorType) {
      case ContentErrorType.network:
        return '🌐';
      case ContentErrorType.server:
        return '🔧';
      case ContentErrorType.parsing:
        return '📄';
      case ContentErrorType.cloudflare:
        return '🛡️';
      case ContentErrorType.rateLimit:
        return '⏱️';
      case ContentErrorType.unknown:
        return '❌';
    }
  }

  // Get user-friendly error message
  String get userFriendlyMessage {
    switch (errorType) {
      case ContentErrorType.network:
        return 'No internet connection. Please check your network and try again.';
      case ContentErrorType.server:
        return 'Server is temporarily unavailable. Please try again later.';
      case ContentErrorType.parsing:
        return 'Failed to load content. The website structure may have changed.';
      case ContentErrorType.cloudflare:
        return 'Cloudflare protection detected. Please wait and try again.';
      case ContentErrorType.rateLimit:
        return 'Too many requests. Please wait a moment before trying again.';
      case ContentErrorType.unknown:
        return message;
    }
  }
}

// State when no content is found
class ContentEmpty extends ContentState {
  const ContentEmpty({
    required this.message,
    this.searchFilter,
    this.tag,
    this.canRetry = true,
    // Context preservation
    this.currentPage,
    this.totalPages,
    this.totalCount,
    this.sortBy,
    this.timeframe,
  });

  final String message;
  final SearchFilter? searchFilter;
  final Tag? tag;
  final bool canRetry;

  // Context fields
  final int? currentPage;
  final int? totalPages;
  final int? totalCount;
  final SortOption? sortBy;
  final PopularTimeframe? timeframe;

  @override
  List<Object?> get props => [
    message,
    searchFilter,
    tag,
    canRetry,
    currentPage,
    totalPages,
    totalCount,
    sortBy,
    timeframe,
  ];

  // Get appropriate empty message based on context (returns l10n key)
  String get contextualMessage {
    if (searchFilter != null && searchFilter!.hasFilters) {
      return 'noContentMatchingSearch';
    } else if (tag != null) {
      return 'noContentForTag';
    } else {
      return message;
    }
  }

  // Get suggestions for empty state (returns l10n keys)
  List<String> get suggestions {
    if (searchFilter != null && searchFilter!.hasFilters) {
      return [
        'tryAdjustingFilters',
        'tryBrowsingOtherTags',
        'checkPopularContent',
      ];
    } else if (tag != null) {
      return [
        'tryBrowsingOtherTags',
        'checkPopularContent',
        'tryADifferentSearchTerm',
      ];
    } else {
      return [
        'checkInternetConnectionSuggestion',
        'tryADifferentSearchTerm',
        'checkPopularContent',
      ];
    }
  }
}

// Types of content errors
enum ContentErrorType {
  network,
  server,
  parsing,
  cloudflare,
  rateLimit,
  unknown,
}

// Extension for ContentErrorType
extension ContentErrorTypeExtension on ContentErrorType {
  String get displayName {
    switch (this) {
      case ContentErrorType.network:
        return 'Network Error';
      case ContentErrorType.server:
        return 'Server Error';
      case ContentErrorType.parsing:
        return 'Parsing Error';
      case ContentErrorType.cloudflare:
        return 'Cloudflare Protection';
      case ContentErrorType.rateLimit:
        return 'Rate Limited';
      case ContentErrorType.unknown:
        return 'Unknown Error';
    }
  }

  bool get isRetryable {
    switch (this) {
      case ContentErrorType.network:
      case ContentErrorType.server:
      case ContentErrorType.cloudflare:
      case ContentErrorType.rateLimit:
        return true;
      case ContentErrorType.parsing:
      case ContentErrorType.unknown:
        return false;
    }
  }
}
