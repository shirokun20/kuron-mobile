import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/domain/usecases/recommendations/recommendations_usecases.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_cubit.dart';

class _MockGetRecommendations extends Mock
    implements GetRecommendationsUseCase {}

class _MockGetSimilar extends Mock implements GetSimilarContentUseCase {}

class _MockRecordEvent extends Mock
    implements RecordRecommendationEventUseCase {}

Recommendation _rec(String id) => Recommendation(
      contentId: id,
      sourceId: 'nhentai',
      score: 0.5,
      reason: 'Because you read X',
      contributorTitle: 'X',
      contributorRelation: 'read',
    );

void main() {
  late _MockGetRecommendations getRecs;
  late _MockGetSimilar getSimilar;
  late _MockRecordEvent recordEvent;
  late RecommendationCubit cubit;

  setUpAll(() {
    registerFallbackValue(const GetRecommendationsParams());
    registerFallbackValue(
        const GetSimilarContentParams(contentId: 'x'));
    registerFallbackValue(const RecordRecommendationEventParams(
        contentId: 'x', event: RecommendationEvent.shown));
  });

  setUp(() {
    getRecs = _MockGetRecommendations();
    getSimilar = _MockGetSimilar();
    recordEvent = _MockRecordEvent();
    cubit = RecommendationCubit(
      getRecommendationsUseCase: getRecs,
      getSimilarContentUseCase: getSimilar,
      recordEventUseCase: recordEvent,
      logger: Logger(level: Level.off),
    );
  });

  tearDown(() => cubit.close());

  test('4.3 loadRecommendations emits Loading then Loaded', () async {
    when(() => getRecs(any())).thenAnswer((_) async => [_rec('a')]);

    final states = <RecommendationState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.loadRecommendations();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(states.first, isA<RecommendationLoading>());
    final loaded = states.last as RecommendationLoaded;
    expect(loaded.items.map((r) => r.contentId), ['a']);
    verify(() => getRecs(any(
        that: isA<GetRecommendationsParams>().having(
            (p) => p.limit, 'limit', 10)))).called(1);
  });

  test('load failure with no cache emits Error', () async {
    when(() => getRecs(any())).thenThrow(Exception('db gone'));

    final states = <RecommendationState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.loadRecommendations();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(states.last, isA<RecommendationError>());
  });

  test('4.5 loadSimilarContent stores per-content list', () async {
    when(() => getSimilar(any())).thenAnswer((_) async => [_rec('s1')]);

    await cubit.loadSimilarContent('c1');
    final loaded = cubit.state as RecommendationLoaded;

    expect(loaded.similarByContent['c1']!.map((r) => r.contentId), ['s1']);
    expect(loaded.isLoadingSimilar, isFalse);
  });

  test('4.7 dismiss records event and drops the card without recompute',
      () async {
    when(() => getRecs(any()))
        .thenAnswer((_) async => [_rec('a'), _rec('b')]);
    when(() => recordEvent(any())).thenAnswer((_) async {});
    await cubit.loadRecommendations();

    await cubit.dismissRecommendation('a', sourceId: 'nhentai');

    final loaded = cubit.state as RecommendationLoaded;
    expect(loaded.items.map((r) => r.contentId), ['b']);
    verify(() => recordEvent(any(
        that: isA<RecordRecommendationEventParams>()
            .having((p) => p.event, 'event', RecommendationEvent.dismissed)
            .having((p) => p.contentId, 'contentId', 'a')))).called(1);
    // No recompute: exactly the one initial load call.
    verify(() => getRecs(any())).called(1);
  });
}
