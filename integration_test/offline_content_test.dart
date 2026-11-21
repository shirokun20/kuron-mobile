import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nhasixapp/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Offline content management e2e test', (
    WidgetTester tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate to Library (typically index 1 or 2 in nav bar)
    // Assuming Icon(Icons.download) is the library tab
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);

    // Verify segments if present (Downloads / History?)
    // This depends on implementation, usually TabBar

    // Check if there are any downloaded items
    final hasDownloads =
        find.byType(ListTile).evaluate().isNotEmpty ||
        find.byType(Card).evaluate().isNotEmpty;

    if (hasDownloads) {
      // Tap on the first item to go to details or reader
      final firstItem = find.byType(ListTile).first;
      // If using GridView with Cards
      // final firstItem = find.byType(Card).first;

      // We assume ListTile here for list view
      await tester.tap(firstItem);
      await tester.pumpAndSettle();

      // Verify we are in details/reader
      // ...

      // Go back
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      // If empty, verify "Empty" state widget/text
      // expect(find.text('No downloads'), findsOneWidget);
    }
  });
}
