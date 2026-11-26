import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/download_range/download_range_screen.dart';

void main() {
  Widget harness({
    required int totalPages,
    required void Function((int, int)?) onResult,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final res = await Navigator.of(context).push<(int, int)>(
                  MaterialPageRoute(
                    builder: (_) => DownloadRangeScreen(
                      totalPages: totalPages,
                      contentTitle: 'E-Hentai Gallery',
                    ),
                  ),
                );
                onResult(res);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('numpad edits start/end pages without TextField and pops range', (
    tester,
  ) async {
    (int, int)? result;
    await tester.pumpWidget(
      harness(totalPages: 395, onResult: (r) => result = r),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    // Default active field is End Page (395). Tap 1, 2, 0 -> 120.
    await tester.tap(find.byKey(const ValueKey('numpad-1')));
    await tester.tap(find.byKey(const ValueKey('numpad-2')));
    await tester.tap(find.byKey(const ValueKey('numpad-0')));
    await tester.pump();
    expect(find.text('120'), findsWidgets);

    // Switch to Start Page and enter 25.
    await tester.tap(find.text('Start Page'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('numpad-2')));
    await tester.tap(find.byKey(const ValueKey('numpad-5')));
    await tester.pump();

    // Confirm returns (25, 120).
    await tester.tap(find.byKey(const ValueKey('download-range-confirm')));
    await tester.pumpAndSettle();

    expect(result, (25, 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick chip First 10 updates range and confirms (1, 10)', (
    tester,
  ) async {
    (int, int)? result;
    await tester.pumpWidget(
      harness(totalPages: 395, onResult: (r) => result = r),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final first10 = find.text('First 10');
    await tester.ensureVisible(first10);
    await tester.tap(first10);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('download-range-confirm')));
    await tester.pumpAndSettle();

    expect(result, (1, 10));
    expect(tester.takeException(), isNull);
  });
}
