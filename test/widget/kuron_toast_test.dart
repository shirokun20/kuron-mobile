import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_toast.dart';

import 'kuron_fx_p2_support.dart';

/// Kuron's custom toast: streak-in → land (BYAR! dotted) → hold → shrink-out,
/// with plain SnackBar / no-op fallbacks under every KuronMotionPolicy gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(() {
    KuronToast.dismiss();
    tearDownFxChannel();
  });

  testWidgets('standard mode streaks in, lands BYAR! and shrinks out', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    final context = tester.element(find.byType(Scaffold));
    KuronToast.show(context, message: 'Unduhan dimulai');
    await tester.pump();
    expect(find.text('Unduhan dimulai'), findsOneWidget);
    expect(KuronToast.isActive, isTrue);

    // Land (0.5 s): the shared KuronFx burst carries the dotted BYAR! word.
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    final fx = painterOf(tester);
    expect(fx.kind, KuronFxKind.toastLand);
    expect(fx.wordSpec?.word.name, 'BYAR!');
    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(tester.takeException(), isNull);

    // Hold then shrink out; the single toast entry self-cleans at 3.7 s.
    await tester.pump(KuronToast.totalDuration);
    expect(KuronToast.isActive, isFalse);
    expect(find.text('Unduhan dimulai'), findsNothing);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('quiet mode keeps the message as a plain snack bar', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.quiet);
    KuronToast.show(
      tester.element(find.byType(Scaffold)),
      message: 'quiet toast',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('quiet toast'), findsOneWidget);
    expect(KuronToast.isActive, isFalse);
    expect(maybePainterOf(tester), isNull);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('reduced motion and reader keep state, drop the decoration', (
    tester,
  ) async {
    for (final reduced in <bool>[true, false]) {
      final injected = await pumpFxApp(
        tester,
        mode: KuronFxMode.standard,
        reducedMotion: reduced,
      );
      KuronToast.show(
        tester.element(find.byType(Scaffold)),
        message: reduced ? 'reduced toast' : 'reader toast',
        isReader: !reduced,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text(reduced ? 'reduced toast' : 'reader toast'), findsOneWidget);
      expect(KuronToast.isActive, isFalse);
      expect(maybePainterOf(tester), isNull);
      expect(KuronFx.activeController!.activeEntryCount, 0);
      expect(tester.takeException(), isNull);
      await settleAndClose(tester, injected);
    }
  });
}
