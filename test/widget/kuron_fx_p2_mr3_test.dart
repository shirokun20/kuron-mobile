import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// MR3: wordless toggle (procedural knob/flood/splash) and tab (ticks/puffs)
/// beats, reusing painter primitives without words or images.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  test('toggle pacing follows katalog 43-frame ON / 12-frame OFF', () {
    // 43 frames @30 fps ≈ 1.433 s; OFF = 12 frames = 0.4 s backward.
    expect(
      KuronFxController.animationDurationFor(KuronFxKind.toggleOn),
      const Duration(milliseconds: 1433),
    );
    expect(
      KuronFxController.animationDurationFor(KuronFxKind.toggleOff),
      const Duration(milliseconds: 400),
    );
    expect(
      KuronFxController.animationDurationFor(KuronFxKind.tabSwitch),
      KuronFxController.maxDuration - const Duration(milliseconds: 80),
    );
    // Gallery toggle.js: ON=[0..42] at 30 fps; OFF=[11..0] backward only.
    expect(KuronFxOverlayPainter.toggleOnFrames, 43);
    expect(KuronFxOverlayPainter.toggleOffFrames, 12);
    expect(KuronFxOverlayPainter.toggleFrameFor(KuronFxKind.toggleOn, 0), 0);
    expect(KuronFxOverlayPainter.toggleFrameFor(KuronFxKind.toggleOn, 0.5), 21);
    expect(KuronFxOverlayPainter.toggleFrameFor(KuronFxKind.toggleOn, 1), 42);
    expect(KuronFxOverlayPainter.toggleFrameFor(KuronFxKind.toggleOff, 0), 11);
    expect(KuronFxOverlayPainter.toggleFrameFor(KuronFxKind.toggleOff, 1), 0);
    // OFF never reaches the splash/flood/glint frames (> 11).
    for (var p = 0; p <= 10; p++) {
      expect(
        KuronFxOverlayPainter.toggleFrameFor(
          KuronFxKind.toggleOff,
          p / 10,
        ),
        lessThanOrEqualTo(11),
      );
    }
  });

  testWidgets('toggleOn/toggleOff are wordless and anchored on the tile', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    const rect = Rect.fromLTWH(16, 250, 320, 72);
    final context = tester.element(find.byType(Scaffold));

    for (final kind in <KuronFxKind>[
      KuronFxKind.toggleOn,
      KuronFxKind.toggleOff,
    ]) {
      KuronFx.triggerOn(context, rect: rect, kind: kind);
      await tester.pump();
      final painter = painterOf(tester);
      expect(painter.kind, kind);
      expect(painter.targetRect, rect);
      expect(painter.wordSpec, isNull);
      expect(painter.wordImage, isNull);
      expect(find.byType(Image), findsNothing); // no words, no webp sheet
      expect(KuronFx.activeController!.activeEntryCount, 1);
      expect(
        KuronFx.activeController!.duration,
        KuronFxController.animationDurationFor(kind),
      );
      // Procedural frames advance without throwing or stacking entries.
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump(const Duration(milliseconds: 90));
      expect(KuronFx.activeController!.activeEntryCount, 1);
      expect(tester.takeException(), isNull);
    }
    await settleAndClose(tester, injected);
  });

  testWidgets('reduced motion jumps to the toggle end state (no overlay)', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      reducedMotion: true,
    );
    KuronFx.triggerOn(
      tester.element(find.byType(Scaffold)),
      rect: const Rect.fromLTWH(16, 250, 320, 72),
      kind: KuronFxKind.toggleOn,
    );
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
    expect(maybePainterOf(tester), isNull);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('tabSwitch draws ticks/puffs only, with a quiet no-op', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    const label = Rect.fromLTWH(18, 600, 64, 32);
    final context = tester.element(find.byType(Scaffold));
    KuronFx.triggerOn(context, rect: label, kind: KuronFxKind.tabSwitch);
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.tabSwitch);
    expect(painter.targetRect, label);
    expect(painter.wordSpec, isNull);
    expect(find.byType(Image), findsNothing);
    expect(KuronFx.activeController!.activeEntryCount, 1);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);

    final quiet = await pumpFxApp(tester, mode: KuronFxMode.quiet);
    KuronFx.triggerOn(
      tester.element(find.byType(Scaffold)),
      rect: label,
      kind: KuronFxKind.tabSwitch,
    );
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
    await settleAndClose(tester, quiet);
  });
}
