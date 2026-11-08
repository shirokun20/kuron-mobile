import '../../repositories/content_repository.dart';
import '../../entities/entities.dart';
import '../base_usecase.dart';

// Use case for fetching content by tag
class GetContentByTagUseCase
    extends UseCase<ContentListResult, GetContentByTagParams> {
  GetContentByTagUseCase({required this._contentRepository});

  final ContentRepository _contentRepository;

  @override
  Future<ContentListResult> call(GetContentByTagParams params) {
    return _contentRepository.getContentByTag(
      tag: params.tag,
      page: params.page,
      sortBy: params.sortBy,
    );
  }
}

class GetContentByTagParams extends UseCaseParams {
  const GetContentByTagParams({
    required this.tag,
    this.page = 1,
    this.sortBy = SortOption.newest,
  });

  final Tag tag;
  final int page;
  final SortOption sortBy;

  @override
  List<Object?> get props => [tag, page, sortBy];
}
