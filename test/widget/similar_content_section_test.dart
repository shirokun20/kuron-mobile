import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_cubit.dart';
import 'package:nhasixapp/presentation/cubits/recommendations/recommendation_refresh_bus.dart';
import 'package:nhasixapp/presentation/pages/detail/widgets/similar_content_section.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_card.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

class _MockCubit extends Mock implements RecommendationCubit {}

class _MockRegistry extends Mock implements ContentSourceRegistry {}

Content _content(String id) => Content(
      id: id,
      sourceId: 'nhentai',
      title: 'Title $id',
      coverUrl: 'http://cover/$id',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: 10,
      imageUrls: const [],
      uploadDate: DateTime(2026, 1, 1),
    );

Recommendation _rec(String id) {
  final c = _content(id);
  return Recommendation(
    contentId: id,
    sourceId: 'nhentai',
    score: 0.5,
    reason: 'Similar to this',
    contributorRelation: 'similar',
    content: c,
  );
}

Widget _harness() {
  return const MaterialApp(
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('en')],
    home: Scaffold(
      body: SimilarContentSection(
        contentId: 'c1',
        sourceId: 'nhentai',
        onTap: _noop,
      ),
    ),
  );
}

void _noop(Content _) {}

void main() {
  late _MockCubit cubit;
  late StreamController<RecommendationState> states;

  setUpAll(() {
    registerFallbackValue(const Recommendation(
      contentId: 'x',
      sourceId: 'nhentai',
      score: 0,
      reason: 'x',
    ));
    final registry = _MockRegistry();
    when(() => registry.getSource(any())).thenReturn(null);
    GetIt.instance.registerSingleton<ContentSourceRegistry>(registry);
    GetIt.instance
        .registerLazySingleton<RecommendationRefreshBus>(
            () => RecommendationRefreshBus());
  });

  tearDownAll(() {
    GetIt.instance
      ..unregister<ContentSourceRegistry>()
      ..unregister<RecommendationCubit>()
      ..unregister<RecommendationRefreshBus>();
  });

  setUp(() {
    cubit = _MockCubit();
    states = StreamController<RecommendationState>.broadcast();
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.loadSimilarContent(any(), sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async {});
    when(() => cubit.dismissRecommendation(any(),
            sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async {});
    when(() => cubit.markTapped(any())).thenAnswer((_) async {});
    when(() => cubit.close()).thenAnswer((_) async {});
    when(() => cubit.state).thenReturn(const RecommendationInitial());
    if (GetIt.instance.isRegistered<RecommendationCubit>()) {
      GetIt.instance.unregister<RecommendationCubit>();
    }
    GetIt.instance.registerFactory<RecommendationCubit>(() => cubit);
  });

  tearDown(() async {
    await states.close();
  });

  testWidgets('9.9 loading shows shimmer', (tester) async {
    when(() => cubit.state).thenReturn(const RecommendationLoading());
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.byType(KuronShimmer), findsWidgets);
  });

  testWidgets('9.9 populated shows similar cards', (tester) async {
    when(() => cubit.state).thenReturn(RecommendationLoaded(
      items: const [],
      similarByContent: {
        'c1': [_rec('s1'), _rec('s2')]
      },
    ));
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.byType(RecommendationCard), findsNWidgets(2));
    verify(() => cubit.loadSimilarContent('c1', sourceId: 'nhentai'))
        .called(1);
  });

  testWidgets('9.9 empty collapses', (tester) async {
    when(() => cubit.state).thenReturn(const RecommendationLoaded());
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.byType(RecommendationCard), findsNothing);
    expect(find.text('Similar to This'), findsNothing);
  });
}
