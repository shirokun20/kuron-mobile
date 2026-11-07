import 'package:nhasixapp/domain/usecases/combined_home/get_combined_home_usecase.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';
import 'combined_home_state.dart';

// Home "Semua" combined-feed cubit.
//
// Owns the presentation-level "Semua" mode flag plus the ranked cross-source
// list. Single-source mode is untouched: picking one source routes through
// [SourceCubit] and only clears [CombinedHomeState.isCombinedSelected].
class CombinedHomeCubit extends BaseCubit<CombinedHomeState> {
  CombinedHomeCubit({
    required GetCombinedHomeUseCase getCombinedHomeUseCase,
    required super.logger,
  })  : _getCombinedHome = getCombinedHomeUseCase,
        super(initialState: const CombinedHomeState());

  /// Sentinel id for the "Semua" row in the Home source picker. It is a UI
  /// option only and never reaches the source registry (design decision 4).
  static const String combinedId = 'semua';

  final GetCombinedHomeUseCase _getCombinedHome;

  /// Enter "Semua" mode and load the combined feed (no-op reload safe).
  Future<void> enterCombined({bool forceRefresh = false}) async {
    if (!state.isCombinedSelected) {
      emit(state.copyWith(isCombinedSelected: true));
    }
    await load(forceRefresh: forceRefresh);
  }

  /// Leave "Semua" mode; the loaded list is kept for instant re-entry.
  void exitCombined() {
    if (state.isCombinedSelected) {
      emit(state.copyWith(isCombinedSelected: false));
    }
  }

  /// Load (or reload) the combined feed for the current state.
  Future<void> load({bool forceRefresh = false}) async {
    if (state.status == CombinedHomeStatus.loading) return;
    emit(state.copyWith(
      status: CombinedHomeStatus.loading,
      errorMessage: null,
    ));
    try {
      final feed = await _getCombinedHome(
        GetCombinedHomeParams(forceRefresh: forceRefresh),
      );
      emit(state.copyWith(
        status: CombinedHomeStatus.loaded,
        contents: feed.contents,
        sourceIds: feed.sourceIds,
        isFallback: feed.isFallback,
        fallbackSourceId: feed.fallbackSourceId,
        errorMessage: null,
      ));
      logInfo(
        'Loaded combined home: ${feed.contents.length} items '
        'from ${feed.sourceIds} (fallback=${feed.isFallback})',
      );
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'loadCombinedHome');
      final cached = state.contents;
      emit(state.copyWith(
        status: cached.isEmpty
            ? CombinedHomeStatus.error
            : CombinedHomeStatus.loaded,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Pull-to-refresh entry point: bypass the 15-minute repository cache.
  Future<void> refresh() => load(forceRefresh: true);
}
