import 'package:kuron_core/kuron_core.dart' show OnCancelRegister;
import '../base_usecase.dart';
import '../../value_objects/value_objects.dart';
import '../../repositories/repositories.dart';
import '../../entities/entities.dart';

// Use case for getting chapter images
class GetChapterImagesUseCase
    extends UseCase<ChapterData, GetChapterImagesParams> {
  GetChapterImagesUseCase(this._contentRepository);

  final ContentRepository _contentRepository;

  @override
  Future<ChapterData> call(GetChapterImagesParams params) async {
    return await _contentRepository.getChapterImages(
      params.chapterId,
      sourceId: params.sourceId,
      onCancel: params.onCancel,
    );
  }
}

// Parameters for GetChapterImagesUseCase
class GetChapterImagesParams extends UseCaseParams {
  const GetChapterImagesParams({
    required this.chapterId,
    this.sourceId,
    this.onCancel,
  });

  final ContentId chapterId;
  final String? sourceId;

  /// Cancellation hook for this fetch. Excluded from [props] (closure
  /// identity would break value equality of otherwise identical params).
  final OnCancelRegister? onCancel;

  @override
  List<Object?> get props => [chapterId, sourceId];

  factory GetChapterImagesParams.fromString(String chapterId,
      {String? sourceId}) {
    return GetChapterImagesParams(
      chapterId: ContentId.fromString(chapterId),
      sourceId: sourceId,
    );
  }
}
