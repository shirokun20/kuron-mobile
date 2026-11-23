import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/domain/usecases/recommendations/recommendations_usecases.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_cubit.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_refresh_bus.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/recommended_section.dart';

class _MockGetRecommendations extends Mock
    implements GetRecommendationsUseCase {}

class _MockGetSimilar extends Mock implements GetSimilarContentUseCase {}

class _MockRecordEvent extends Mock
    implements RecordRecommendationEventUseCase {}

class _MockRegistry extends Mock implements ContentSourceRegistry {}

Recommendation _rec(String id) => Recommendation(
      contentId: id,
      sourceId: 'nhentai',
      score: 0.5,
      reason: 'Because you read X',
      contributorTitle: 'X',
      contributorRelation: 'read',
    );

Widget _harness(Set<String> excludeIds) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: RecommendedSection(excludeIds: excludeIds),
          ),
        ],
      ),
    ),
  );
}

// Explicit pumps only: the carousel autoplay timer and shimmer tickers
// are perpetual, so pumpAndSettle would never terminate.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late _MockGetRecommendations getRecs;

  setUpAll(() {
    registerFallbackValue(const GetRecommendationsParams());
    registerFallbackValue(const GetSimilarContentParams(contentId: 'x'));
    registerFallbackValue(const RecordRecommendationEventParams(
      contentId: 'x',
      event: RecommendationEvent.shown,
    ));
    final registry = _MockRegistry();
    when(() => registry.getSource(any())).thenReturn(null);
    GetIt.instance.registerSingleton<ContentSourceRegistry>(registry);
    GetIt.instance.registerSingleton<RecommendationRefreshBus>(
      RecommendationRefreshBus(),
    );
  });

  tearDownAll(() {
    GetIt.instance.unregister<ContentSourceRegistry>();
    GetIt.instance.unregister<RecommendationRefreshBus>();
  });

  setUp(() {
    getRecs = _MockGetRecommendations();
    when(() => getRecs(any())).thenAnswer((_) async => [_rec('a')]);
    when(() => getRecs.isCacheValid).thenReturn(false);
    GetIt.instance.registerFactory<RecommendationCubit>(
      () => RecommendationCubit(
        getRecommendationsUseCase: getRecs,
        getSimilarContentUseCase: _MockGetSimilar(),
        recordEventUseCase: _MockRecordEvent(),
        logger: Logger(level: Level.off),
      ),
    );
  });

  tearDown(() {
    GetIt.instance.unregister<RecommendationCubit>();
  });

  testWidgets(
    'rebuild with equal ids does not reload (setEquals fix)',
    (tester) async {
      await tester.pumpWidget(_harness({'a'}));
      await _flush(tester);
      verify(() => getRecs(any())).called(1);

      // Same ids in a brand-new Set instance: identity comparison used to
      // retrigger a reload on every home rebuild; value comparison must not.
      // (verify counts only unverified calls, so this asserts zero NEW loads.)
      await tester.pumpWidget(_harness({'a'}));
      await _flush(tester);
      verifyNever(() => getRecs(any()));

      // Genuinely changed ids still trigger exactly one more load.
      await tester.pumpWidget(_harness({'a', 'b'}));
      await _flush(tester);
      verify(() => getRecs(any())).called(1);
    },
  );

  testWidgets(
    'loaded items render the autoplay carousel',
    (tester) async {
      await tester.pumpWidget(_harness({'a'}));
      await _flush(tester);
      expect(find.text('Because you read X'), findsWidgets);
    },
  );
}
