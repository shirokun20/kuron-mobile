import '../base_usecase.dart';
import '../../repositories/recommendation_repository.dart';

// Records shown/tapped/dismissed events for recommendation dedup windows.
class RecordRecommendationEventUseCase
    extends UseCase<void, RecordRecommendationEventParams> {
  RecordRecommendationEventUseCase(this._repository);

  final RecommendationRepository _repository;

  @override
  Future<void> call(RecordRecommendationEventParams params) async {
    try {
      if (params.contentId.isEmpty) {
        throw const ValidationException('Content ID cannot be empty');
      }
      switch (params.event) {
        case RecommendationEvent.shown:
          await _repository.recordShown(params.contentId,
              sourceId: params.sourceId);
        case RecommendationEvent.tapped:
          await _repository.recordTapped(params.contentId,
              sourceId: params.sourceId);
        case RecommendationEvent.dismissed:
          await _repository.recordDismissed(params.contentId,
              sourceId: params.sourceId);
      }
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw CacheException(
          'Failed to record recommendation event: ${e.toString()}');
    }
  }
}

enum RecommendationEvent { shown, tapped, dismissed }

class RecordRecommendationEventParams extends UseCaseParams {
  const RecordRecommendationEventParams({
    required this.contentId,
    required this.event,
    this.sourceId,
  });

  final String contentId;
  final RecommendationEvent event;
  final String? sourceId;

  @override
  List<Object?> get props => [contentId, event, sourceId];
}
