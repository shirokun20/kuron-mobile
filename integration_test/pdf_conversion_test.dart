import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nhasixapp/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PDF conversion e2e test', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate to Library
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    // Check if we have items
    final hasItems = find.byType(ListTile).evaluate().isNotEmpty;

    if (hasItems) {
      // Long press or tap to open menu?
      // Or go to details -> Export PDF

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      // Look for "Export PDF" or similar action
      final pdfIcon = find.byIcon(Icons.picture_as_pdf);
      if (pdfIcon.evaluate().isNotEmpty) {
        await tester.tap(pdfIcon);
        await tester.pumpAndSettle();

        // Verify dialog or process start
      }
    }
  });
}
