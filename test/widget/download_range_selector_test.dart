import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/download_range_selector.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// Range-input jank (ehentai detail page): the slider used one division
/// per page (`divisions: totalPages - 1`), painting O(n) tick marks per
/// frame, and every keystroke in the manual fields rebuilt the whole
/// dialog (slider + SliderTheme + tick repaint) during the keyboard-show
/// resize animation. These tests assert the structural fixes — capped
/// divisions and debounced/submitted text→slider sync — without any
/// wall-time assertions.
void main() {
  Widget harness({required int totalPages}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DownloadRangeSelector(
          totalPages: totalPages,
          contentTitle: 'test gallery',
          onRangeSelected: (_, _) {},
        ),
      ),
    );
  }

  RangeValues sliderOf(WidgetTester tester) =>
      tester.widget<RangeSlider>(find.byType(RangeSlider)).values;

  int? divisionsOf(WidgetTester tester) =>
      tester.widget<RangeSlider>(find.byType(RangeSlider)).divisions;

  group('slider divisions', () {
    testWidgets('large gallery caps divisions at 200', (tester) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();
      expect(divisionsOf(tester), 200);
    });

    testWidgets('small gallery keeps one division per page', (tester) async {
      await tester.pumpWidget(harness(totalPages: 50));
      await tester.pumpAndSettle();
      expect(divisionsOf(tester), 49);
    });
  });

  group('text to slider sync', () {
    testWidgets('keystrokes echo without rebuilding the slider', (
      tester,
    ) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();
      expect(sliderOf(tester), const RangeValues(1, 1500));

      await tester.enterText(find.byType(TextField).at(0), '10');
      await tester.pump();

      // Controller echoes the keystrokes, but the debounced slider sync
      // has not fired yet — no per-keystroke dialog rebuild.
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        '10',
      );
      expect(sliderOf(tester), const RangeValues(1, 1500));
    });

    testWidgets('slider syncs after input goes idle', (tester) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '10');
      await tester.pump();
      expect(sliderOf(tester), const RangeValues(1, 1500));

      await tester.pump(const Duration(milliseconds: 400));
      expect(sliderOf(tester), const RangeValues(10, 1500));
    });

    testWidgets('submit applies the range immediately', (tester) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '20');
      await tester.pump();
      expect(sliderOf(tester), const RangeValues(1, 1500));

      tester.widget<TextField>(find.byType(TextField).at(0)).onSubmitted!('20');
      await tester.pump();
      expect(sliderOf(tester), const RangeValues(20, 1500));
    });

    testWidgets('invalid input never touches the slider', (tester) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();

      // start > end is invalid: even after idle + submit the slider stays.
      await tester.enterText(find.byType(TextField).at(0), '1400');
      await tester.enterText(find.byType(TextField).at(1), '100');
      await tester.pump(const Duration(milliseconds: 400));
      tester.widget<TextField>(find.byType(TextField).at(1)).onSubmitted!(
        '100',
      );
      await tester.pump();
      expect(sliderOf(tester), const RangeValues(1, 1500));
    });
  });

  group('slider to text sync', () {
    testWidgets('drag still syncs the manual fields', (tester) async {
      await tester.pumpWidget(harness(totalPages: 1500));
      await tester.pumpAndSettle();

      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(5, 100),
      );
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
        '5',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
        '100',
      );
    });
  });

  group('slider fx', () {
    setUp(setUpFxChannel);
    tearDown(tearDownFxChannel);

    testWidgets('a fling above the katalog threshold mounts CAIR!', (
      tester,
    ) async {
      final injected = await pumpFxApp(
        tester,
        mode: KuronFxMode.standard,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DownloadRangeSelector(
            totalPages: 1500,
            contentTitle: 'test gallery',
            onRangeSelected: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 4000 px/s over the sheet's ~240 px usable track is well above the
      // katalog |peak| > 1.3 release beat; a real finger fling reaches this.
      await tester.fling(find.byType(RangeSlider), const Offset(180, 0), 4000);
      await tester.pump();

      final painter = painterOf(tester);
      expect(painter.kind, KuronFxKind.sliderFling);
      expect(painter.wordSpec?.word.name, 'CAIR!');
      expect(KuronFx.activeController!.activeEntryCount, 1);
      expect(tester.takeException(), isNull);

      await settleAndClose(tester, injected);
    });
  });
}
