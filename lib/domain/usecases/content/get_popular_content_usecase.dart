import 'package:kuron_core/kuron_core.dart' show OnCancelRegister;
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
      onCancel: params.onCancel,
    );
  }
}

class GetPopularContentParams extends UseCaseParams {
  const GetPopularContentParams({
    this.timeframe = PopularTimeframe.allTime,
    this.page = 1,
    this.onCancel,
  });

  final PopularTimeframe timeframe;
  final int page;

  /// Cancellation hook for this fetch. Excluded from [props] (closure
  /// identity would break value equality of otherwise identical params).
  final OnCancelRegister? onCancel;

  @override
  List<Object?> get props => [timeframe, page];
}
