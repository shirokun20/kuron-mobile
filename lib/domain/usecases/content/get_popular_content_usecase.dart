import '../../repositories/content_repository.dart';
import '../base_usecase.dart';

// Use case for fetching popular content
class GetPopularContentUseCase
    extends UseCase<ContentListResult, GetPopularContentParams> {
  GetPopularContentUseCase({required this._contentRepository});

  final ContentRepository _contentRepository;

  @override
  Future<ContentListResult> call(GetPopularContentParams params) {
    return _contentRepository.getPopularContent(
      timeframe: params.timeframe,
      page: params.page,
    );
  }
}

class GetPopularContentParams extends UseCaseParams {
  const GetPopularContentParams({
    this.timeframe = PopularTimeframe.allTime,
    this.page = 1,
  });

  final PopularTimeframe timeframe;
  final int page;

  @override
  List<Object?> get props => [timeframe, page];
}
