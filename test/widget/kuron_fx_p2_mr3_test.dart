import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// MR3: wordless toggle (procedural knob/flood/splash) and tab (ticks/puffs)
/// beats, reusing painter primitives without words, stickers or images.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

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
      expect(painter.sticker, isNull);
      expect(KuronFx.activeController!.activeEntryCount, 1);
      // Procedural frames advance without throwing or stacking entries.
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump(const Duration(milliseconds: 90));
      expect(KuronFx.activeController!.activeEntryCount, 1);
      expect(tester.takeException(), isNull);
    }
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
