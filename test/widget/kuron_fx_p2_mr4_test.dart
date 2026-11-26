import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_snack_bar_content.dart';
import 'package:nhasixapp/presentation/widgets/kuron_tooltip.dart';

import 'kuron_fx_p2_support.dart';

/// MR4: snack-bar toast landing and the custom tooltip bubble.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  testWidgets('KuronSnackBarContent anchors BYAR! below the message', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).showSnackBar(
      const SnackBar(
        content: KuronSnackBarContent(child: Text('unduhan selesai')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final contentRect = tester.getRect(find.text('unduhan selesai'));
    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.toastLand);
    expect(painter.targetRect, isNotNull);
    // Below-content anchor: the burst box starts under the message box and
    // is horizontally centered on it.
    expect(painter.targetRect!.top, greaterThanOrEqualTo(contentRect.bottom));
    expect(
      painter.targetRect!.center.dx,
      moreOrLessEquals(contentRect.center.dx, epsilon: 1),
    );
    expect(painter.wordSpec?.word.name, 'BYAR!');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(painterOf(tester).wordImage, isNotNull);
    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(KuronFx.activeController!.activeTimerCount, 1);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('KuronTooltip draws its own bubble and fires KLIK! ring', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(
        body: Center(
          child: KuronTooltip(
            message: 'Info privat',
            child: IconButton(onPressed: null, icon: Icon(Icons.info)),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(IconButton));
    await tester.pump();
    expect(find.text('Info privat'), findsOneWidget);
    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.tooltipPop);
    expect(painter.wordSpec?.word.name, 'KLIK!');
    expect(
      (painter.targetRect!.center - tester.getCenter(find.byType(IconButton)))
          .distance,
      lessThan(1),
    );
    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(tester.takeException(), isNull);

    // The bubble auto-hides and disposes its single entry/timer.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Info privat'), findsNothing);
    await settleAndClose(tester, injected);
  });

  testWidgets('toast landing is a no-op in quiet mode but the snack shows', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.quiet);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).showSnackBar(
      const SnackBar(content: KuronSnackBarContent(child: Text('quiet toast'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('quiet toast'), findsOneWidget);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
    expect(maybePainterOf(tester), isNull);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });
}
