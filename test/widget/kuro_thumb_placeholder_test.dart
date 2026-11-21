import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

void main() {
  testWidgets('thumb placeholder paints static Kuro without tickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.square(dimension: 120, child: KuroThumbPlaceholder()),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    // Static painter: no ticker-based KuroMascot in subtree (the shimmer
    // wash itself owns one controller, the cat paints zero).
    expect(find.byType(KuroMascot), findsNothing);
  });
}
