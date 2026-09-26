import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_banner.dart';

class _MockRegistry extends Mock implements ContentSourceRegistry {}

Content _content(String id) => Content(
      id: id,
      sourceId: 'nhentai',
      title: 'Banner Title $id',
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
    reason: 'Because you read X',
    contributorTitle: 'X',
    contributorRelation: 'read',
    content: c,
  );
}

Widget _harness({
  required List<Recommendation> items,
  ValueChanged<Recommendation>? onTap,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: RecommendationBannerCarousel(
        items: items,
        onTap: onTap ?? (_) {},
      ),
    ),
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

  testWidgets('banner shows title overlay on first slide', (tester) async {
    await tester.pumpWidget(
        _harness(items: [_rec('a'), _rec('b'), _rec('c')]));

    expect(find.text('Banner Title a'), findsOneWidget);
    expect(find.text('Because you read X'), findsWidgets);
    expect(find.byType(BannerDots), findsOneWidget);
  });

  testWidgets('explore slide chips the source id without prefix', (tester) async {
    final c = _content('x');
    final explore = Recommendation(
      contentId: 'x',
      sourceId: 'nhentai',
      score: 0,
      reason: 'Similar to X',
      contributorTitle: 'X',
      contributorRelation: RecommendationRelation.similar,
      content: c,
    );
    await tester.pumpWidget(_harness(items: [explore]));

    expect(find.text('nhentai'), findsOneWidget);
    expect(find.textContaining('Jelajahi'), findsNothing);
    expect(find.textContaining('Explore'), findsNothing);
  });

  testWidgets('ghost rank numbers mark slide position', (tester) async {
    await tester.pumpWidget(
        _harness(items: [_rec('a'), _rec('b'), _rec('c')]));

    // PageView builds the active slide plus cached neighbors.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('autoplay progress shows for many, hidden for single',
      (tester) async {
    await tester.pumpWidget(
        _harness(items: [_rec('a'), _rec('b')]));
    expect(
      find.byKey(const ValueKey('autoplay-progress')),
      findsOneWidget,
    );

    await tester.pumpWidget(_harness(items: [_rec('a')]));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('autoplay-progress')),
      findsNothing,
    );
  });

  testWidgets('tap opens the visible recommendation', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(_harness(
      items: [_rec('a'), _rec('b')],
      onTap: (r) => tapped.add(r.contentId),
    ));

    await tester.tap(find.text('Banner Title a'));
    expect(tapped, ['a']);
  });

  testWidgets('manual swipe moves to next slide', (tester) async {
    await tester.pumpWidget(
        _harness(items: [_rec('a'), _rec('b')]));

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    // No pumpAndSettle: the autoplay progress animation is perpetual.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Banner Title b'), findsOneWidget);
  });

  testWidgets('autoplay advances after interval', (tester) async {
    await tester.pumpWidget(
        _harness(items: [_rec('a'), _rec('b')]));

    expect(find.text('Banner Title a'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    // No pumpAndSettle: the autoplay progress animation is perpetual.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Banner Title b'), findsOneWidget);
  });
}
