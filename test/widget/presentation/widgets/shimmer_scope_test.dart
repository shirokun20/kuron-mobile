import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

void main() {
  testWidgets('N KuronShimmer in ShimmerScope share single animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShimmerScope(
            child: Column(
              children: [
                KuronShimmer(child: SizedBox(width: 100, height: 20)),
                KuronShimmer(child: SizedBox(width: 100, height: 20)),
                KuronShimmer(child: SizedBox(width: 100, height: 20)),
              ],
            ),
          ),
        ),
      ),
    );

    // Verify exactly one ShimmerControllerScope exists
    expect(find.byType(ShimmerControllerScope), findsOneWidget);

    // Verify 3 KuronShimmer widgets render without error
    expect(find.byType(KuronShimmer), findsNWidgets(3));

    // Pump a tick and verify no exception
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListShimmer wraps list in ShimmerScope', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ListShimmer(itemCount: 4))),
    );

    expect(find.byType(ShimmerScope), findsOneWidget);
    expect(find.byType(ShimmerControllerScope), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
