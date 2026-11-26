import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

void main() {
  test('floatY and sobX scale with mascot size', () {
    expect(kuroScaledFloatY(38), closeTo(-7.125, 0.001));
    expect(kuroScaledFloatY(44), closeTo(-8.25, 0.001));
    expect(kuroScaledFloatY(64), -12);
    expect(kuroScaledFloatY(200), -12);
    expect(kuroScaledSobX(200), 3);
    expect(kuroScaledSobX(38), closeTo(0.57, 0.001));
  });

  test('huff only affects repaint for tsundere', () {
    expect(kuroHuffAffectsRepaint(KuroMood.tsundere), isTrue);
    for (final mood in [
      KuroMood.happy,
      KuroMood.reader,
      KuroMood.ghost,
      KuroMood.waiting,
    ]) {
      expect(kuroHuffAffectsRepaint(mood), isFalse);
    }
  });

  test('thumb placeholder follows 48/56/64 ladder', () {
    expect(kuroThumbSizeForSlot(120, 120), 64);
    expect(kuroThumbSizeForSlot(60, 60), 56);
    expect(kuroThumbSizeForSlot(50, 50), 48);
    expect(kuroThumbSizeForSlot(36, 36), 28);
    expect(kuroThumbSizeForSlot(double.infinity, double.infinity), 48);
  });

  testWidgets('thumb placeholder sizes its cat to the available slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.square(dimension: 120, child: KuroThumbPlaceholder()),
        ),
      ),
    );
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(
      paints.any((paint) => paint.size == const Size.square(64)),
      isTrue,
      reason: 'a 120px slot should paint the 64px ladder step',
    );
  });

  testWidgets('shimmer stops under reduced motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 120,
              child: KuroThumbPlaceholder(),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ShaderMask), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.square(dimension: 120, child: KuroThumbPlaceholder()),
        ),
      ),
    );
    expect(find.byType(ShaderMask), findsWidgets);
  });

  testWidgets('mascot painter stays identical with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: KuroMascot(mood: KuroMood.tsundere, size: 64)),
        ),
      ),
    );
    final before = tester
        .widget<CustomPaint>(find.byType(CustomPaint).first)
        .painter;
    await tester.pump(const Duration(milliseconds: 500));
    final after = tester
        .widget<CustomPaint>(find.byType(CustomPaint).first)
        .painter;
    expect(identical(before, after), isTrue);
  });
}
