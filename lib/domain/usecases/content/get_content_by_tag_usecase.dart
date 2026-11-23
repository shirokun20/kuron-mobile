import 'package:kuron_core/kuron_core.dart' show OnCancelRegister;
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
      onCancel: params.onCancel,
    );
  }
}

class GetContentByTagParams extends UseCaseParams {
  const GetContentByTagParams({
    required this.tag,
    this.page = 1,
    this.sortBy = SortOption.newest,
    this.onCancel,
  });

  final Tag tag;
  final int page;
  final SortOption sortBy;

  /// Cancellation hook for this fetch. Excluded from [props] (closure
  /// identity would break value equality of otherwise identical params).
  final OnCancelRegister? onCancel;

  @override
  List<Object?> get props => [tag, page, sortBy];
}
