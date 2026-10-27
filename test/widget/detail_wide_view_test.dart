import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/detail/widgets/detail_wide_view.dart';

Widget _harness({
  bool isOfflineMode = false,
  List<Widget> infoWidgets = const [Text('info-title')],
  List<Widget> contentWidgets = const [Text('chapter-list')],
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
      body: DetailWideView(
        rightScrollController: ScrollController(),
        isOfflineMode: isOfflineMode,
        headerImageUrl: '',
        contentId: 'c1',
        onBack: () {},
        onGoOnline: () {},
        appBarActions: const [Icon(Icons.share)],
        infoWidgets: infoWidgets,
        contentWidgets: contentWidgets,
      ),
    ),
  );
}

void main() {
  setUp(() {
    // ProgressiveImageWidget resolves Logger via GetIt in initState.
    if (!GetIt.instance.isRegistered<Logger>()) {
      GetIt.instance.registerSingleton<Logger>(Logger());
    }
  });
  tearDown(GetIt.instance.reset);
  group('DetailWideView', () {
    testWidgets('renders cover hero, info rail, and right-pane content',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('info-title'), findsOneWidget);
      expect(find.text('chapter-list'), findsOneWidget);
      // Same Hero tag as the narrow header so card flights keep a destination.
      expect(find.byType(Hero), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    testWidgets('offline mode shows the offline banner', (tester) async {
      await tester.pumpWidget(_harness(isOfflineMode: true));
      await tester.pump();

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('dragging the divider resizes the info rail', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      final panes = find.byType(SingleChildScrollView);
      expect(panes, findsNWidgets(2));
      expect(tester.getSize(panes.first).width, 360);

      // Divider sits right after the 360-wide rail (9dp hit area). A long
      // drag must clamp at the max rail width regardless of gesture slop.
      await tester.dragFrom(const Offset(364, 400), const Offset(1000, 0));
      // Let the double-tap recognizer's timeout expire so no timer is
      // pending at teardown.
      await tester.pump(const Duration(seconds: 1));

      expect(tester.getSize(panes.first).width, DetailWideView.maxRailWidth);
    });
  });
}
