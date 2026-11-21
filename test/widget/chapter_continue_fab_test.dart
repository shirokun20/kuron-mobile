import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/detail/widgets/chapter_continue_fab.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

Chapter _chapter(String id) =>
    Chapter(id: id, title: 'Chapter $id', url: '/chapter/$id');

ChapterContinueTarget _target(ChapterContinueMode mode) =>
    ChapterContinueTarget(
      chapter: _chapter('c1'),
      page: mode == ChapterContinueMode.resume ? 12 : 1,
      mode: mode,
      chapterNumber: mode == ChapterContinueMode.nextChapter ? 2 : 1,
    );

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

Future<void> _pumpFab(
  WidgetTester tester,
  ChapterContinueMode mode, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    _harness(ChapterContinueFab(target: _target(mode), onTap: onTap ?? () {})),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('resume mode shows the chapter title and page subtitle', (
    tester,
  ) async {
    await _pumpFab(tester, ChapterContinueMode.resume);

    expect(find.text('Continue from chapter 1'), findsOneWidget);
    expect(find.text('Page 12'), findsOneWidget);
    expect(
      tester.widget<KuroMascot>(find.byType(KuroMascot)).mood,
      KuroMood.reader,
    );
  });

  testWidgets('next-chapter mode shows the next chapter title', (tester) async {
    await _pumpFab(tester, ChapterContinueMode.nextChapter);

    expect(find.text('Continue to chapter 2'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(
      tester.widget<KuroMascot>(find.byType(KuroMascot)).mood,
      KuroMood.reader,
    );
  });

  testWidgets('restart mode shows the happy mascot and restart label', (
    tester,
  ) async {
    await _pumpFab(tester, ChapterContinueMode.restart);

    expect(find.text('Go to First Page'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(
      tester.widget<KuroMascot>(find.byType(KuroMascot)).mood,
      KuroMood.happy,
    );
  });

  testWidgets('tap and drag still fire the callback', (tester) async {
    var taps = 0;
    await _pumpFab(tester, ChapterContinueMode.resume, onTap: () => taps++);

    final pill = find.text('Continue from chapter 1');
    await tester.tap(pill);
    await tester.pump(const Duration(milliseconds: 16));
    expect(taps, 1);

    // Drag far past the edges — must clamp, not throw, and stay tappable.
    await tester.drag(pill, const Offset(-4000, -4000));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(pill, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 16));
    expect(taps, 2);
  });
}
