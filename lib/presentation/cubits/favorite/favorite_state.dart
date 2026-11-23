part of 'favorite_cubit.dart';

// Base state for FavoriteCubit
abstract class FavoriteState extends BaseCubitState {
  const FavoriteState();
}

// Initial state
class FavoriteInitial extends FavoriteState {
  const FavoriteInitial();

  @override
  List<Object?> get props => [];
}

// Loading state
class FavoriteLoading extends FavoriteState {
  const FavoriteLoading();

  @override
  List<Object?> get props => [];
}

// Loaded state with favorites data
class FavoriteLoaded extends FavoriteState {
  const FavoriteLoaded({
    required this.favorites,
    required this.collections,
    required this.currentPage,
    required this.hasMore,
    required this.totalCount,
    required this.lastUpdated,
    this.isLoadingMore = false,
    this.isBatchOperating = false,
    this.activeCollectionId,
    this.searchQuery,
    this.totalAllCount = 0,
    this.uncategorizedCount = 0,
  });

  final List<Map<String, dynamic>> favorites;
  final List<FavoriteCollection> collections;
  final int currentPage;
  final bool hasMore;
  final int totalCount;
  final DateTime lastUpdated;
  final bool isLoadingMore;
  final bool isBatchOperating;
  final String? activeCollectionId;
  final String? searchQuery;

  /// Total favorites across all collections (for the "All" strip chip).
  final int totalAllCount;

  /// Favorites in no collection (for the "Uncategorized" strip chip).
  final int uncategorizedCount;

  @override
  List<Object?> get props => [
        favorites,
        collections,
        currentPage,
        hasMore,
        totalCount,
        lastUpdated,
        isLoadingMore,
        isBatchOperating,
        activeCollectionId,
        searchQuery,
        totalAllCount,
        uncategorizedCount,
      ];

  FavoriteLoaded copyWith({
    List<Map<String, dynamic>>? favorites,
    List<FavoriteCollection>? collections,
    int? currentPage,
    bool? hasMore,
    int? totalCount,
    DateTime? lastUpdated,
    bool? isLoadingMore,
    bool? isBatchOperating,
    String? activeCollectionId,
    String? searchQuery,
    int? totalAllCount,
    int? uncategorizedCount,
  }) {
    return FavoriteLoaded(
      favorites: favorites ?? this.favorites,
      collections: collections ?? this.collections,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      totalCount: totalCount ?? this.totalCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isBatchOperating: isBatchOperating ?? this.isBatchOperating,
      activeCollectionId: activeCollectionId ?? this.activeCollectionId,
      searchQuery: searchQuery ?? this.searchQuery,
      totalAllCount: totalAllCount ?? this.totalAllCount,
      uncategorizedCount: uncategorizedCount ?? this.uncategorizedCount,
    );
  }

  // Check if favorites list is empty
  bool get isEmpty => favorites.isEmpty;

  // Check if currently searching
  bool get isSearching => searchQuery != null && searchQuery!.isNotEmpty;

  // Get display message for empty state
  String getEmptyMessage(AppLocalizations? localizations) {
    if (localizations == null) {
      return _getFallbackEmptyMessage();
    }

    if (isSearching) {
      return 'No favorites found for "$searchQuery"'; // Keep dynamic for now
    }
    return localizations.noFavoritesYet;
  }

  String _getFallbackEmptyMessage() {
    if (isSearching) {
      return 'No favorites found for "$searchQuery"';
    }
    return 'No favorites yet. Start adding content to your favorites!';
  }

  // Get favorites for current page only
  List<Map<String, dynamic>> get currentPageFavorites {
    final startIndex = (currentPage - 1) * 20;
    final endIndex = startIndex + 20;

    if (startIndex >= favorites.length) return [];

    return favorites.sublist(
      startIndex,
      endIndex > favorites.length ? favorites.length : endIndex,
    );
  }
}

// Error state
class FavoriteError extends FavoriteState {
  const FavoriteError({
    required this.message,
    required this.errorType,
    required this.canRetry,
    this.stackTrace,
  });

  final String message;
  final String errorType;
  final bool canRetry;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [
        message,
        errorType,
        canRetry,
        stackTrace,
      ];

  FavoriteError copyWith({
    String? message,
    String? errorType,
    bool? canRetry,
    StackTrace? stackTrace,
  }) {
    return FavoriteError(
      message: message ?? this.message,
      errorType: errorType ?? this.errorType,
      canRetry: canRetry ?? this.canRetry,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  // Get user-friendly error message
  String getUserMessage(AppLocalizations? localizations) {
    if (localizations == null) {
      return _getFallbackUserMessage();
    }

    switch (errorType) {
      case 'network':
        return localizations.networkError;
      case 'server':
        return localizations.serverError;
      case 'cache':
        return 'Storage error. Please check your device storage.'; // Fallback since no specific key exists
      case 'validation':
        return 'Invalid data. Please try again.'; // Fallback since no specific key exists
      case 'notFound':
        return 'Favorites not found.'; // Fallback since no specific key exists
      case 'unknown':
      default:
        return localizations.unknownError;
    }
  }

  String _getFallbackUserMessage() {
    switch (errorType) {
      case 'network':
        return 'No internet connection. Please check your network and try again.';
      case 'server':
        return 'Server error. Please try again later.';
      case 'cache':
        return 'Storage error. Please check your device storage.';
      case 'validation':
        return 'Invalid data. Please try again.';
      case 'notFound':
        return 'Favorites not found.';
      case 'unknown':
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // Check if error is recoverable
  bool get isRecoverable {
    return canRetry && errorType != 'validation';
  }
}
