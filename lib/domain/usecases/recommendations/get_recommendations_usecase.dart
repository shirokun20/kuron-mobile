import '../base_usecase.dart';
import '../../entities/recommendation.dart';
import '../../repositories/recommendation_repository.dart';

// Fetches top-N personalized recommendations from the local engine.
class GetRecommendationsUseCase
    extends UseCase<List<Recommendation>, GetRecommendationsParams> {
  GetRecommendationsUseCase(this._repository);

  final RecommendationRepository _repository;

  @override
  Future<List<Recommendation>> call(GetRecommendationsParams params) async {
    try {
      return await _repository.getRecommendations(
        limit: params.limit,
        excludeIds: params.excludeIds,
        forceRefresh: params.forceRefresh,
      );
    } catch (e) {
      throw CacheException('Failed to get recommendations: ${e.toString()}');
    }
  }

  /// Passthrough for [RecommendationRepository.isCacheValid] so presentation
  /// can skip no-op reloads without importing the data layer.
  bool get isCacheValid => _repository.isCacheValid;
}

class GetRecommendationsParams extends UseCaseParams {
  const GetRecommendationsParams({
    this.limit = 20,
    this.excludeIds = const {},
    this.forceRefresh = false,
  });

  final int limit;
  final Set<String> excludeIds;

  /// Bypass the 1-hour repository cache (refresh triggers).
  final bool forceRefresh;

  @override
  List<Object?> get props => [limit, excludeIds, forceRefresh];
}
