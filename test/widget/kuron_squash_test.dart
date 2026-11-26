import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_squash.dart';

/// Press-feel port of the gallery `squashy()`: squash down while pressed,
/// overshoot with a tilt on release, then settle — without swallowing the
/// inner button/card gestures.
void main() {
  double scaleYOf(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(KuronSquash),
        matching: find.byType(Transform),
      ),
    );
    return transform.transform.entry(1, 1);
  }

  testWidgets('press squashes down, release overshoots then settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: KuronSquash(child: SizedBox(width: 100, height: 50)),
          ),
        ),
      ),
    );
    expect(scaleYOf(tester), moreOrLessEquals(1.0));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KuronSquash)),
    );
    // Flush the pointer-down event first: the squash animation only starts
    // once onTapDown fires, so the timed assertion below needs its own pump.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final pressed = scaleYOf(tester);
    // Squash-down toward low=0.72, volume kept on X.
    expect(pressed, lessThan(1.0));
    expect(pressed, greaterThan(0.5));

    await gesture.up();
    var peak = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = math.max(peak, scaleYOf(tester));
    }
    // Spring release overshoots past rest before settling.
    expect(peak, greaterThan(1.01));
    await tester.pumpAndSettle();
    expect(scaleYOf(tester), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('release without press never leaves the child transformed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KuronSquash(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scaleYOf(tester), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('reduced motion renders the child untouched', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: KuronSquash(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(KuronSquash),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}
