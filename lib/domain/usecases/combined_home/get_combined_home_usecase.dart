import '../base_usecase.dart';
import '../../entities/entities.dart';
import '../../repositories/combined_home_repository.dart';

// Home "Semua" entry point: ranked cross-source feed, or — on cold start
// (no reads, no downloads) — the default source's list flagged as fallback.
class GetCombinedHomeUseCase
    extends UseCase<CombinedHomeFeed, GetCombinedHomeParams> {
  GetCombinedHomeUseCase(this._repository);

  final CombinedHomeRepository _repository;

  @override
  Future<CombinedHomeFeed> call(GetCombinedHomeParams params) async {
    if (params.limit < 1) {
      throw const ValidationException('Limit must be greater than 0');
    }
    try {
      return await _repository.getCombinedFeed(
        limit: params.limit,
        forceRefresh: params.forceRefresh,
      );
    } catch (e) {
      throw CacheException('Failed to get combined home feed: ${e.toString()}');
    }
  }
}

class GetCombinedHomeParams extends UseCaseParams {
  const GetCombinedHomeParams({
    this.limit = CombinedHomeRepository.defaultLimit,
    this.forceRefresh = false,
  });

  final int limit;

  /// Bypass the 15-minute repository cache (pull-to-refresh).
  final bool forceRefresh;

  @override
  List<Object?> get props => [limit, forceRefresh];
}
