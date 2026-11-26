import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// MR2: slider thumb anchoring + the progress/download leading edge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  test('thumbRectOf maps the value fraction to the thumb center', () {
    const track = Rect.fromLTWH(100, 200, 200, 8);
    final min = KuronFx.thumbRectOf(track, 0);
    final mid = KuronFx.thumbRectOf(track, 0.5);
    final max = KuronFx.thumbRectOf(track, 1);

    expect(min.center.dx, 110);
    expect(mid.center.dx, 200);
    expect(max.center.dx, 290);
    for (final rect in <Rect>[min, mid, max]) {
      expect(rect.center.dy, track.center.dy);
      expect(rect.width, 20);
      expect(rect.height, 20);
    }
    // Out-of-range values clamp to the track ends.
    expect(KuronFx.thumbRectOf(track, 2).center.dx, max.center.dx);
    expect(KuronFx.thumbRectOf(track, -1).center.dx, min.center.dx);
    // Custom range and thumb size are honored.
    final custom = KuronFx.thumbRectOf(
      track,
      5,
      min: 0,
      max: 10,
      thumbSize: 30,
    );
    expect(custom.center.dx, 200);
    expect(custom.width, 30);
  });

  testWidgets('sliderFling bakes accented CAIR! above the thumb', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    const track = Rect.fromLTWH(60, 300, 240, 8);
    final thumb = KuronFx.thumbRectOf(track, 0.75);
    final context = tester.element(find.byType(Scaffold));

    // The caller only fires on a fast release; triggerOn anchors on the
    // thumb center handed over here.
    KuronFx.triggerOn(context, rect: thumb, kind: KuronFxKind.sliderFling);
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.targetRect, thumb);
    expect(painter.wordSpec?.word.name, 'CAIR!');
    expect(painter.wordSpec?.accent, isTrue);
    expect(painter.wordSpec?.life, 0.75);
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

  testWidgets('progressComplete finish staging and quiet no-op', (
    tester,
  ) async {
    final injected = await pumpFxApp(tester, mode: KuronFxMode.standard);
    const rect = Rect.fromLTWH(20, 40, 200, 48);
    final context = tester.element(find.byType(Scaffold));
    KuronFx.triggerOn(context, rect: rect, kind: KuronFxKind.progressComplete);
    await tester.pump();
    final painter = painterOf(tester);
    expect(painter.wordSpec?.word.name, 'JEDER!');
    expect(painter.wordSpec?.sizeFactor, 1.2);
    expect(painter.wordSpec?.life, 1.05);
    expect(painter.targetRect, rect);
    await settleAndClose(tester, injected);

    final quiet = await pumpFxApp(tester, mode: KuronFxMode.quiet);
    KuronFx.triggerOn(
      tester.element(find.byType(Scaffold)),
      rect: rect,
      kind: KuronFxKind.progressComplete,
    );
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, quiet);
  });
}
