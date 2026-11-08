import 'package:kuron_core/kuron_core.dart';
import '../../repositories/content_repository.dart';
import '../../value_objects/value_objects.dart';
import '../base_usecase.dart';

// Use case for fetching content chapters
class GetContentChaptersUseCase
    extends UseCase<List<Chapter>, GetContentChaptersParams> {
  GetContentChaptersUseCase({required this._contentRepository});

  final ContentRepository _contentRepository;

  @override
  Future<List<Chapter>> call(GetContentChaptersParams params) {
    return _contentRepository.getContentChapters(
      params.contentId,
      sourceId: params.sourceId,
      language: params.language,
      scanGroup: params.scanGroup,
      page: params.page,
      offset: params.offset,
    );
  }
}

class GetContentChaptersParams extends UseCaseParams {
  const GetContentChaptersParams({
    required this.contentId,
    this.sourceId,
    this.language,
    this.scanGroup,
    this.page,
    this.offset,
  });

  final ContentId contentId;
  final String? sourceId;
  final String? language;
  final String? scanGroup;
  final int? page;
  final int? offset;

  @override
  List<Object?> get props =>
      [contentId, sourceId, language, scanGroup, page, offset];
}
