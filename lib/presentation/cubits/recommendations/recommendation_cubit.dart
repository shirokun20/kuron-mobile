import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/domain/usecases/recommendations/recommendations_usecases.dart';
import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

part 'recommendation_state.dart';

// Home ("Recommended for You") + detail ("Similar to This") recommendations.
// One instance per screen (registered as factory): home and detail never
// share item lists, but share the engine cache underneath.
class RecommendationCubit extends BaseCubit<RecommendationState> {
  RecommendationCubit({
    required GetRecommendationsUseCase getRecommendationsUseCase,
    required GetSimilarContentUseCase getSimilarContentUseCase,
    required RecordRecommendationEventUseCase recordEventUseCase,
    required super.logger,
  })  : _getRecommendations = getRecommendationsUseCase,
        _getSimilar = getSimilarContentUseCase,
        _recordEvent = recordEventUseCase,
        super(initialState: const RecommendationInitial());

  final GetRecommendationsUseCase _getRecommendations;
  final GetSimilarContentUseCase _getSimilar;
  final RecordRecommendationEventUseCase _recordEvent;

  Set<String> _lastExcludeIds = const {};

  Future<void> loadRecommendations({
    Set<String> excludeIds = const {},
    bool forceRefresh = false,
  }) async {
    _lastExcludeIds = excludeIds;
    final current = state;
    final hasItems =
        current is RecommendationLoaded && current.items.isNotEmpty;
    if (!hasItems) emit(const RecommendationLoading());
    if (current is RecommendationLoaded) {
      emit(current.copyWith(isLoading: true, error: () => null));
    }
    try {
      final items = await _getRecommendations(
        GetRecommendationsParams(
            limit: 10, excludeIds: excludeIds, forceRefresh: forceRefresh),
      );
      emit(RecommendationLoaded(
        items: items,
        similarByContent: current is RecommendationLoaded
            ? current.similarByContent
            : const {},
      ));
      logInfo('Loaded ${items.length} recommendations');
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'loadRecommendations');
      final fallbackItems =
          current is RecommendationLoaded ? current.items : const [];
      if (fallbackItems.isEmpty) {
        emit(RecommendationError(e.toString()));
      } else {
        emit((current as RecommendationLoaded)
            .copyWith(isLoading: false, error: () => e.toString()));
      }
    }
  }

  /// Recompute honoring the last exclude set (refresh triggers call this).
  Future<void> refresh() =>
      loadRecommendations(excludeIds: _lastExcludeIds, forceRefresh: true);

  Future<void> loadSimilarContent(String contentId, {String? sourceId}) async {
    final current = state;
    final loaded = current is RecommendationLoaded
        ? current
        : const RecommendationLoaded();
    if (current is! RecommendationLoaded) emit(const RecommendationLoading());
    emit(loaded.copyWith(isLoadingSimilar: true));
    try {
      final items = await _getSimilar(
        GetSimilarContentParams(
            contentId: contentId, sourceId: sourceId, limit: 6),
      );
      emit(loaded.copyWith(
        similarByContent: {...loaded.similarByContent, contentId: items},
        isLoadingSimilar: false,
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'loadSimilarContent');
      emit(loaded.copyWith(isLoadingSimilar: false));
    }
  }

  /// Long-press dismiss: record + drop from the active list (no recompute).
  Future<void> dismissRecommendation(String contentId,
      {String? sourceId}) async {
    final current = state;
    if (current is! RecommendationLoaded) return;
    try {
      await _recordEvent(RecordRecommendationEventParams(
        contentId: contentId,
        event: RecommendationEvent.dismissed,
        sourceId: sourceId,
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'dismissRecommendation');
    }
    emit(current.copyWith(
      items: current.items.where((r) => r.contentId != contentId).toList(),
      similarByContent: {
        for (final e in current.similarByContent.entries)
          e.key: e.value.where((r) => r.contentId != contentId).toList(),
      },
    ));
  }

  /// Called after cards are displayed (feeds the 24h shown window).
  Future<void> markShown(List<Recommendation> shown) async {
    for (final r in shown) {
      try {
        await _recordEvent(RecordRecommendationEventParams(
          contentId: r.contentId,
          event: RecommendationEvent.shown,
          sourceId: r.sourceId,
        ));
      } catch (e, stackTrace) {
        handleError(e, stackTrace, 'markShown');
      }
    }
  }

  /// Card tap hook (future feedback signal; navigation is handled by UI).
  Future<void> markTapped(Recommendation item) async {
    try {
      await _recordEvent(RecordRecommendationEventParams(
        contentId: item.contentId,
        event: RecommendationEvent.tapped,
        sourceId: item.sourceId,
      ));
    } catch (e, stackTrace) {
      handleError(e, stackTrace, 'markTapped');
    }
  }
}
