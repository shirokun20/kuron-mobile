import 'package:kuron_core/kuron_core.dart';

import '../base_usecase.dart';
import '../../repositories/repositories.dart';

// Use case for getting user's favorite content (simplified)
class GetFavoritesUseCase
    extends UseCase<List<Map<String, dynamic>>, GetFavoritesParams> {
  GetFavoritesUseCase(
    this._userDataRepository,
    this._contentSourceRegistry,
  );

  final UserDataRepository _userDataRepository;
  final ContentSourceRegistry _contentSourceRegistry;

  @override
  Future<List<Map<String, dynamic>>> call(GetFavoritesParams params) async {
    try {
      // Validate parameters
      if (params.page < 1) {
        throw const ValidationException('Page number must be greater than 0');
      }

      if (params.limit < 1) {
        throw const ValidationException('Limit must be greater than 0');
      }

      // Get favorites from repository (simplified)
      final result = await _userDataRepository.getFavorites(
        page: params.page,
        limit: params.limit,
        collectionId: params.collectionId,
        uncategorizedOnly: params.uncategorizedOnly,
      );

      // Filter out favorites from non-installed sources
      final installedSourceIds = _contentSourceRegistry.sourceIds.toSet();
      final filteredResult = result.where((favorite) {
        final sourceId = favorite['source_id'] as String?;
        return sourceId != null && installedSourceIds.contains(sourceId);
      }).toList();

      return filteredResult;
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to get favorites: ${e.toString()}');
    }
  }
}

// Parameters for GetFavoritesUseCase (simplified)
class GetFavoritesParams extends UseCaseParams {
  const GetFavoritesParams({
    this.page = 1,
    this.limit = 20,
    this.collectionId,
    this.uncategorizedOnly = false,
  });

  final int page;
  final int limit;
  final String? collectionId;

  /// When true, only favorites in no collection are returned
  /// (virtual "Uncategorized" filter); [collectionId] is ignored.
  final bool uncategorizedOnly;

  @override
  List<Object?> get props =>
      [page, limit, collectionId, uncategorizedOnly];

  GetFavoritesParams copyWith({
    int? page,
    int? limit,
    String? collectionId,
    bool? uncategorizedOnly,
  }) {
    return GetFavoritesParams(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      collectionId: collectionId ?? this.collectionId,
      uncategorizedOnly: uncategorizedOnly ?? this.uncategorizedOnly,
    );
  }

  // Create params for first page
  factory GetFavoritesParams.firstPage(
      {int limit = 20,
      String? collectionId,
      bool uncategorizedOnly = false}) {
    return GetFavoritesParams(
        page: 1,
        limit: limit,
        collectionId: collectionId,
        uncategorizedOnly: uncategorizedOnly);
  }

  // Create params for specific page
  factory GetFavoritesParams.page(int page,
      {int limit = 20,
      String? collectionId,
      bool uncategorizedOnly = false}) {
    return GetFavoritesParams(
      page: page,
      limit: limit,
      collectionId: collectionId,
      uncategorizedOnly: uncategorizedOnly,
    );
  }

  // Create params for next page
  GetFavoritesParams nextPage() {
    return copyWith(page: page + 1);
  }

  // Create params for previous page
  GetFavoritesParams previousPage() {
    return copyWith(page: page > 1 ? page - 1 : 1);
  }
}
