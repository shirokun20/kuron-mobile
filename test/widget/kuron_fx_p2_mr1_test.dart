import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// MR1 foundation: the seven new kinds, the explicit-rect [KuronFx.triggerOn]
/// path, the LOCKED word map, and the shared quiet/reduced-motion gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  test('kind allow-list carries all seven P2 beats', () {
    expect(
      KuronFxKind.values.toSet(),
      containsAll(<KuronFxKind>{
        KuronFxKind.toggleOn,
        KuronFxKind.toggleOff,
        KuronFxKind.sliderFling,
        KuronFxKind.tabSwitch,
        KuronFxKind.toastLand,
        KuronFxKind.tooltipPop,
        KuronFxKind.progressComplete,
      }),
    );
    // The four original beats remain for backwards compatibility.
    expect(KuronFxKind.values.length, 11);
  });

  testWidgets('triggerOn anchors on the explicit rect and bakes JEDER!', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    const rect = Rect.fromLTWH(80, 120, 120, 40);
    final context = tester.element(find.byType(Scaffold));

    KuronFx.triggerOn(context, rect: rect, kind: KuronFxKind.progressComplete);
    await tester.pump();

    final controller = KuronFx.activeController!;
    expect(controller.activeEntryCount, 1);
    expect(controller.activeTimerCount, 1);
    final painter = painterOf(tester);
    expect(painter.targetRect, rect);
    expect(painter.kind, KuronFxKind.progressComplete);
    expect(painter.wordSpec?.word.name, 'JEDER!');
    expect(painter.wordSpec?.sizeFactor, 1.2);
    // Off-loop bake lands without a second overlay entry.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(painterOf(tester).wordImage, isNotNull);
    expect(controller.activeEntryCount, 1);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('wordless P2 kinds carry no word and no sticker', (tester) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.satire);
    final context = tester.element(find.byType(Scaffold));
    const rect = Rect.fromLTWH(40, 60, 48, 48);

    for (final kind in <KuronFxKind>[
      KuronFxKind.toggleOn,
      KuronFxKind.toggleOff,
      KuronFxKind.tabSwitch,
    ]) {
      KuronFx.triggerOn(context, rect: rect, kind: kind);
      await tester.pump();
      final painter = painterOf(tester);
      expect(painter.wordSpec, isNull);
      expect(painter.sticker, isNull);
      expect(painter.wordImage, isNull);
      expect(KuronFx.activeController!.activeEntryCount, 1);
    }
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('quiet mode and reduced motion make triggerOn a no-op', (
    tester,
  ) async {
    for (final reduced in <bool>[false, true]) {
      final injected = await pumpFxApp(
        tester,
        mode: reduced ? KuronFxMode.standard : KuronFxMode.quiet,
        reducedMotion: reduced,
      );
      final context = tester.element(find.byType(Scaffold));
      KuronFx.triggerOn(
        context,
        rect: const Rect.fromLTWH(10, 10, 40, 40),
        kind: KuronFxKind.toastLand,
      );
      await tester.pump();
      expect(KuronFx.activeController!.activeEntryCount, 0);
      expect(KuronFx.activeController!.activeTimerCount, 0);
      expect(maybePainterOf(tester), isNull);
      await settleAndClose(tester, injected);
    }
  });

  testWidgets('one overlay entry and timer self-clean at the TTL', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    final context = tester.element(find.byType(Scaffold));
    KuronFx.triggerOn(
      context,
      rect: const Rect.fromLTWH(20, 30, 90, 32),
      kind: KuronFxKind.tooltipPop,
    );
    await tester.pump();
    final controller = KuronFx.activeController!;
    expect(controller.activeEntryCount, 1);
    expect(controller.activeTimerCount, 1);

    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    expect(controller.activeEntryCount, 0);
    expect(controller.activeTimerCount, 0);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });
}
