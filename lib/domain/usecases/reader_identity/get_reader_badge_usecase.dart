import 'package:kuron_core/kuron_core.dart';

import '../../entities/reader_badge.dart';
import '../../repositories/user_data_repository.dart';
import '../base_usecase.dart';

// Assembles the reader identity badge from on-device aggregates.
// NoParams: the badge always reflects the whole local library.
class GetReaderBadgeUseCase extends NoParamsUseCase<ReaderBadge> {
  GetReaderBadgeUseCase({
    required UserDataRepository userDataRepository,
    required ContentSourceRegistry sourceRegistry,
  })  : _userData = userDataRepository,
        _registry = sourceRegistry;

  final UserDataRepository _userData;
  final ContentSourceRegistry _registry;

  @override
  Future<ReaderBadge> call() async {
    final completed = await _userData.getCompletedHistoryCount();
    final top = await _userData.getTopDownloadSource();
    final topSourceId = top?.sourceId;
    return ReaderBadge(
      tier: readerTierFor(
        completedCount: completed,
        topSourceId: topSourceId,
      ),
      completedCount: completed,
      topSourceId: topSourceId,
      topSourceDisplayName: topSourceId == null
          ? ''
          : (_registry.getSource(topSourceId)?.displayName ?? topSourceId),
      topSourceDownloads: top?.count ?? 0,
    );
  }
}
