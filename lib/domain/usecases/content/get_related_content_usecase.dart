import 'package:kuron_core/kuron_core.dart';
import '../../repositories/content_repository.dart';
import '../../value_objects/value_objects.dart';
import '../base_usecase.dart';

// Use case for fetching related content
class GetRelatedContentUseCase
    extends UseCase<List<Content>, GetRelatedContentParams> {
  GetRelatedContentUseCase({required this._contentRepository});

  final ContentRepository _contentRepository;

  @override
  Future<List<Content>> call(GetRelatedContentParams params) {
    return _contentRepository.getRelatedContent(
      contentId: params.contentId,
      limit: params.limit,
      sourceId: params.sourceId,
      onCancel: params.onCancel,
    );
  }
}

class GetRelatedContentParams extends UseCaseParams {
  const GetRelatedContentParams({
    required this.contentId,
    this.limit = 10,
    this.sourceId,
    this.onCancel,
  });

  final ContentId contentId;
  final int limit;
  final String? sourceId;

  /// Cancellation hook for this fetch. Excluded from [props] (closure
  /// identity would break value equality of otherwise identical params).
  final OnCancelRegister? onCancel;

  @override
  List<Object?> get props => [contentId, limit, sourceId];
}
