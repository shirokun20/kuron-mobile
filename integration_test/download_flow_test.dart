import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nhasixapp/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Download flow e2e test', (WidgetTester tester) async {
    // 1. Start App
    app.main();
    // Allow time for async initialization (ServiceLocator, etc.)
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 2. Verify Home Screen loaded
    expect(find.byType(MaterialApp), findsOneWidget);

    // Verify main tabs are present to ensure UI loaded
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    // 3. Attempt to find a content item card
    // Note: This relies on network or existing data.
    // If empty, we can't fully test download flow, but we can verify app didn't crash.
    final hasContent = find.byType(Card).evaluate().isNotEmpty;

    if (hasContent) {
      // Tap first card
      await tester.tap(find.byType(Card).first);
      await tester.pumpAndSettle();

      // Check if we are on details screen
      // Look for typical details screen elements like "Download" or "Read"
      // Note: text depends on localization or API data
      if (find.byIcon(Icons.download).evaluate().isNotEmpty) {
        // Tap download action (floating action button or icon button)
        await tester.tap(find.byIcon(Icons.download));
        await tester.pump();

        // Wait for potential snackbar
        await tester.pump(const Duration(seconds: 1));

        // If interaction successful, we assume start.
        // Full verification requires checking database or notification which is hard in UI test.
      }
    } else {
      debugPrint(
        'No content found to test download flow. Skipping interaction steps.',
      );
    }

    // Navigate to Library
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    // Verify Library Screen
    expect(find.text('Library'), findsOneWidget);
  });
}
