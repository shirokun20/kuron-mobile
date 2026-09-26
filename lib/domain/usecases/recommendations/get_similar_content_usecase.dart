import '../base_usecase.dart';
import '../../entities/recommendation.dart';
import '../../repositories/recommendation_repository.dart';

// Fetches content most similar to one item (detail screen).
class GetSimilarContentUseCase
    extends UseCase<List<Recommendation>, GetSimilarContentParams> {
  GetSimilarContentUseCase(this._repository);

  final RecommendationRepository _repository;

  @override
  Future<List<Recommendation>> call(GetSimilarContentParams params) async {
    try {
      if (params.contentId.isEmpty) {
        throw const ValidationException('Content ID cannot be empty');
      }
      return await _repository.getSimilarContent(
        contentId: params.contentId,
        sourceId: params.sourceId,
        limit: params.limit,
      );
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to get similar content: ${e.toString()}');
    }
  }
}

class GetSimilarContentParams extends UseCaseParams {
  const GetSimilarContentParams({
    required this.contentId,
    this.sourceId,
    this.limit = 6,
  });

  final String contentId;
  final String? sourceId;
  final int limit;

  @override
  List<Object?> get props => [contentId, sourceId, limit];
}
