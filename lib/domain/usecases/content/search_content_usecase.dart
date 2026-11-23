import 'package:kuron_core/kuron_core.dart' show OnCancelRegister;
import '../base_usecase.dart';
import '../../entities/entities.dart';
import '../../repositories/repositories.dart';

// Use case for searching content with advanced filters
class SearchContentUseCase extends UseCase<ContentListResult, SearchFilter> {
  SearchContentUseCase(this._contentRepository);

  final ContentRepository _contentRepository;

  /// [onCancel] is an optional override parameter (legal on overrides):
  /// existing callers keep passing just the filter.
  @override
  Future<ContentListResult> call(
    SearchFilter filter, {
    OnCancelRegister? onCancel,
  }) async {
    try {
      // Validate parameters
      if (filter.page < 1) {
        throw const ValidationException('Page number must be greater than 0');
      }

      // Validate search query if provided
      if (filter.query != null && filter.query!.trim().isEmpty) {
        throw const ValidationException('Search query cannot be empty');
      }

      // Search content using repository
      final result = await _contentRepository.searchContent(
        filter,
        onCancel: onCancel,
      );

      return result;
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw NetworkException('Failed to search content: ${e.toString()}');
    }
  }
}

// Parameters for SearchContentUseCase
class SearchContentParams extends UseCaseParams {
  const SearchContentParams({
    required this.filter,
    this.requireFilters = false,
  });

  final SearchFilter filter;
  final bool requireFilters;

  @override
  List<Object> get props => [filter, requireFilters];

  SearchContentParams copyWith({
    SearchFilter? filter,
    bool? requireFilters,
  }) {
    return SearchContentParams(
      filter: filter ?? this.filter,
      requireFilters: requireFilters ?? this.requireFilters,
    );
  }

  // Create params with updated filter
  SearchContentParams withFilter(SearchFilter newFilter) {
    return copyWith(filter: newFilter);
  }

  // Create params for next page
  SearchContentParams nextPage() {
    return copyWith(filter: filter.nextPage());
  }

  // Create params for previous page
  SearchContentParams previousPage() {
    return copyWith(filter: filter.previousPage());
  }

  // Create params for first page
  SearchContentParams firstPage() {
    return copyWith(filter: filter.resetPage());
  }

  // Create params with query
  factory SearchContentParams.withQuery(
    String query, {
    SortOption sortBy = SortOption.newest,
    bool requireFilters = false,
  }) {
    return SearchContentParams(
      filter: SearchFilter(
        query: query,
        sortBy: sortBy,
      ),
      requireFilters: requireFilters,
    );
  }

  // Create params with tags
  factory SearchContentParams.withTags(
    List<String> tags, {
    SortOption sortBy = SortOption.newest,
    bool requireFilters = false,
  }) {
    return SearchContentParams(
      filter: SearchFilter(
        tags: tags.map((tag) => FilterItem.include(tag)).toList(),
        sortBy: sortBy,
      ),
      requireFilters: requireFilters,
    );
  }

  // Create params with artist
  factory SearchContentParams.withArtist(
    String artist, {
    SortOption sortBy = SortOption.newest,
    bool requireFilters = false,
  }) {
    return SearchContentParams(
      filter: SearchFilter(
        artists: [FilterItem.include(artist)],
        sortBy: sortBy,
      ),
      requireFilters: requireFilters,
    );
  }
}
