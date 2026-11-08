import 'package:kuron_core/kuron_core.dart';
import '../../repositories/content_repository.dart';
import '../base_usecase.dart';

// Use case for fetching random content galleries
class GetRandomGalleriesUseCase
    extends UseCase<List<Content>, GetRandomGalleriesParams> {
  GetRandomGalleriesUseCase({required this._contentRepository});

  final ContentRepository _contentRepository;

  @override
  Future<List<Content>> call(GetRandomGalleriesParams params) {
    return _contentRepository.getRandomGalleries(
      sourceId: params.sourceId,
      count: params.count,
    );
  }
}

class GetRandomGalleriesParams extends UseCaseParams {
  const GetRandomGalleriesParams({this.sourceId, this.count = 1});

  final String? sourceId;
  final int count;

  @override
  List<Object?> get props => [sourceId, count];
}
