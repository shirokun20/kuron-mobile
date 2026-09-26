import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_card.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_row.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

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

Recommendation _rec(String id, {String relation = 'read'}) {
  final c = _content(id);
  return Recommendation(
    contentId: id,
    sourceId: 'nhentai',
    score: 0.5,
    reason: 'Because you read X',
    contributorTitle: 'X',
    contributorRelation: relation,
    content: c,
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() {
    final registry = _MockRegistry();
    when(() => registry.getSource(any())).thenReturn(null);
    GetIt.instance.registerSingleton<ContentSourceRegistry>(registry);
  });

  tearDownAll(() {
    GetIt.instance.unregister<ContentSourceRegistry>();
  });

  group('9.8 RecommendationRow', () {
    testWidgets('loading state shows shimmer', (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: const [],
        isLoading: true,
        isColdStart: false,
        onTap: (_) {},
      )));

      expect(find.byType(KuronShimmer), findsWidgets);
    });

    testWidgets('banner loading matches carousel size', (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: const [],
        isLoading: true,
        isColdStart: false,
        bannerLoading: true,
        onTap: (_) {},
      )));

      expect(find.byType(KuronShimmer), findsWidgets);
      // Card-style horizontal list is NOT used for banner loading.
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('cold start shows placeholder message', (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: const [],
        isLoading: false,
        isColdStart: true,
        onTap: (_) {},
        onBrowse: () {},
      )));

      expect(
        find.text(
            'Start reading to get personalized recommendations'),
        findsOneWidget,
      );
      expect(find.text('Browse content'), findsOneWidget);
    });

    testWidgets('populated shows cards with reason badges', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: [_rec('a'), _rec('b', relation: 'favorite')],
        isLoading: false,
        isColdStart: false,
        onTap: (r) => tapped.add(r.contentId),
      )));

      expect(find.text('Because you read X'), findsOneWidget);
      expect(find.text('Because you favorited X'), findsOneWidget);

      await tester.tap(find.text('Title a'));
      expect(tapped, ['a']);
    });

    testWidgets('error/empty collapses to nothing', (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: const [],
        isLoading: false,
        isColdStart: false,
        onTap: (_) {},
      )));

      expect(find.byType(RecommendationRow), findsOneWidget);
      // Collapsed: no title, no placeholder, no shimmer.
      expect(find.text('Recommended for You'), findsNothing);
      expect(find.byType(KuronShimmer), findsNothing);
    });
  });

  group('refresh affordance + badge polish', () {
    testWidgets('refresh button calls onRefresh', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: [_rec('a')],
        isLoading: false,
        isColdStart: false,
        onTap: (_) {},
        onRefresh: () => refreshed++,
      )));

      await tester.tap(find.byType(IconButton));
      expect(refreshed, 1);
    });

    testWidgets('no refresh button without callback', (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'Recommended for You',
        items: [_rec('a')],
        isLoading: false,
        isColdStart: false,
        onTap: (_) {},
      )));

      expect(find.byType(IconButton), findsNothing);
    });

    test('shortTitle truncates long contributor titles', () {
      expect(RecommendationCard.shortTitle('Action'), 'Action');
      expect(
        RecommendationCard.shortTitle('(C105) [Ringo no Naru Ki (Kise Itsuki)]'),
        '(C105) [Ringo no Naru Ki …',
      );
    });
  });

  group('9.10 reason badge fallback', () {
    testWidgets('missing contributor title falls back to content id',
        (tester) async {
      await tester.pumpWidget(_harness(RecommendationRow(
        title: 'T',
        items: const [
          Recommendation(
            contentId: 'g9',
            sourceId: 'nhentai',
            score: 1,
            reason: 'x',
          ),
        ],
        isLoading: false,
        isColdStart: false,
        onTap: (_) {},
      )));

      expect(find.text('Because you read g9'), findsOneWidget);
    });
  });
}
