import 'package:kuron_core/kuron_core.dart';
import '../../repositories/content_repository.dart';
import '../../value_objects/value_objects.dart';
import '../base_usecase.dart';

// Use case for fetching related content
class GetRelatedContentUseCase
    extends UseCase<List<Content>, GetRelatedContentParams> {
  GetRelatedContentUseCase({required ContentRepository contentRepository})
      : _contentRepository = contentRepository;

  final ContentRepository _contentRepository;

  @override
  Future<List<Content>> call(GetRelatedContentParams params) {
    return _contentRepository.getRelatedContent(
      contentId: params.contentId,
      limit: params.limit,
      sourceId: params.sourceId,
    );
  }
}

class GetRelatedContentParams extends UseCaseParams {
  const GetRelatedContentParams({
    required this.contentId,
    this.limit = 10,
    this.sourceId,
  });

  final ContentId contentId;
  final int limit;
  final String? sourceId;

  @override
  List<Object?> get props => [contentId, limit, sourceId];
}
