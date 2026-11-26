import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_slider_fling.dart';

import 'kuron_fx_p2_support.dart';

/// The one-line `.withKuronSliderFx()` extension must make a real finger fling
/// mount CAIR! above the thumb; a slow drag / quiet mode stay decoration-free.
class _SliderHost extends StatefulWidget {
  const _SliderHost({this.isReader = false});

  final bool isReader;

  @override
  State<_SliderHost> createState() => _SliderHostState();
}

class _SliderHostState extends State<_SliderHost> {
  double _value = 0.5;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 300,
      child: Slider(
        value: _value,
        onChanged: (v) => setState(() => _value = v),
      ).withKuronSliderFx(isReader: widget.isReader),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  testWidgets('a fling above the katalog release threshold mounts CAIR!', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(body: _SliderHost()),
    );
    final sliderRect = tester.getRect(find.byType(Slider));

    // 4000 px/s over a ~280 px usable track ≈ 14 ranges/s, well above the
    // katalog |peak| > 1.3 release beat; a real finger fling reaches this.
    await tester.fling(find.byType(Slider), const Offset(180, 0), 4000);
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.sliderFling);
    expect(painter.wordSpec?.word.name, 'CAIR!');
    expect(painter.wordSpec?.accent, isTrue);
    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(KuronFx.activeController!.activeTimerCount, 1);
    // Thumb anchor is inside the slider box, not the screen center.
    expect(
      painter.targetRect!.center.dx,
      greaterThanOrEqualTo(sliderRect.left),
    );
    expect(painter.targetRect!.center.dx, lessThanOrEqualTo(sliderRect.right));
    expect(
      painter.targetRect!.center.dy,
      moreOrLessEquals(sliderRect.center.dy, epsilon: 1),
    );
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('a slow drag does not fire the release beat', (tester) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(body: _SliderHost()),
    );
    await tester.drag(find.byType(Slider), const Offset(20, 0));
    await tester.pump();
    expect(maybePainterOf(tester), isNull);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('the fling is a no-op in quiet mode', (tester) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.quiet,
      home: const Scaffold(body: _SliderHost()),
    );
    await tester.fling(find.byType(Slider), const Offset(180, 0), 4000);
    await tester.pump();
    expect(maybePainterOf(tester), isNull);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('fling left sets negative direction on painter', (tester) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(body: _SliderHost()),
    );
    await tester.fling(find.byType(Slider), const Offset(-180, 0), 4000);
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.sliderFling);
    expect(painter.direction, -1.0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('fast mid-drag mounts wordless sliderDrag trail', (tester) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(body: _SliderHost()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(
      const Offset(120, 0),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.sliderDrag);
    expect(painter.wordSpec, isNull);
    expect(painter.direction, 1.0);
    expect(tester.takeException(), isNull);

    await gesture.up();
    await settleAndClose(tester, injected);
  });

  testWidgets('reader slider stays hard-off even in standard mode', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(body: _SliderHost(isReader: true)),
    );
    await tester.fling(find.byType(Slider), const Offset(180, 0), 4000);
    await tester.pump();
    expect(maybePainterOf(tester), isNull);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });
}
