import '../../entities/reader_position.dart';
import '../../repositories/reader_repository.dart';
import '../base_usecase.dart';

// Use case for fetching reader position
class GetReaderPositionUseCase extends UseCase<ReaderPosition?, String> {
  GetReaderPositionUseCase({required this._readerRepository});

  final ReaderRepository _readerRepository;

  @override
  Future<ReaderPosition?> call(String params) {
    return _readerRepository.getReaderPosition(params);
  }
}
