import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_contract.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_screen.dart';

class _MockErrorLog extends Mock implements ErrorLogContract {}

void main() {
  late _MockErrorLog store;

  setUp(() {
    store = _MockErrorLog();
  });

  final sampleEntries = [
    ErrorLogEntry(
      id: 1,
      createdAt: DateTime(2026, 11, 12, 15, 30),
      sourceId: 'nhentai',
      feature: 'getChapterImages',
      statusCode: 502,
      message: 'Bad Gateway from upstream',
      urlPath: '/api/gallery/123/images',
    ),
    ErrorLogEntry(
      id: 2,
      createdAt: DateTime(2026, 11, 12, 16, 00),
      sourceId: 'komikindo',
      feature: 'fetchDetail',
      statusCode: null,
      message: 'SocketException: Connection timed out',
      urlPath: '/manga/one-piece',
    ),
  ];

  Widget buildTestWidget({
    void Function(BuildContext, ErrorLogEntry)? onReport,
    Future<void> Function(String)? textExporter,
  }) {
    return MaterialApp(
      home: ErrorLogScreen(
        store: store,
        onReport: onReport,
        textExporter: textExporter,
      ),
    );
  }

  testWidgets('displays toggle switch with current logging state', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => false);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => <ErrorLogEntry>[]);
    when(() => store.setEnabled(true)).thenAnswer((_) async {});

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Rekam Error Respons'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isFalse);

    // Toggle switch on
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    verify(() => store.setEnabled(true)).called(1);
  });

  testWidgets('displays list of error log entries', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => true);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleEntries);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('nhentai'), findsOneWidget);
    expect(find.text('HTTP 502'), findsOneWidget);
    expect(find.text('getChapterImages — Bad Gateway from upstream'), findsOneWidget);
    expect(find.text('/api/gallery/123/images'), findsOneWidget);

    expect(find.text('komikindo'), findsOneWidget);
    expect(find.text('fetchDetail — SocketException: Connection timed out'), findsOneWidget);
    expect(find.text('/manga/one-piece'), findsOneWidget);
  });

  testWidgets('displays empty state when no error log entries', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => false);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => <ErrorLogEntry>[]);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada catatan error'), findsOneWidget);
  });

  testWidgets('deletes an entry when delete icon is tapped', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => true);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => [sampleEntries.first]);
    when(() => store.deleteEntry(1)).thenAnswer((_) async {});

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap delete icon on card
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    verify(() => store.deleteEntry(1)).called(1);
  });

  testWidgets('clears all entries with confirmation dialog', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => true);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleEntries);
    when(() => store.clearAll()).thenAnswer((_) async {});

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap clear all icon on AppBar
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Hapus Semua Log Error'), findsOneWidget);

    // Confirm
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus Semua'));
    await tester.pumpAndSettle();

    verify(() => store.clearAll()).called(1);
  });

  testWidgets('exports text when export button is tapped', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => true);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleEntries);
    when(() => store.exportText())
        .thenAnswer((_) async => 'EXPORTED_LOG_STRING');

    String? exported;
    await tester.pumpWidget(buildTestWidget(
      textExporter: (text) async {
        exported = text;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();

    verify(() => store.exportText()).called(1);
    expect(exported, 'EXPORTED_LOG_STRING');
  });

  testWidgets('tapping Lapor button on entry triggers onReport callback', (tester) async {
    when(() => store.isEnabled()).thenAnswer((_) async => true);
    when(() => store.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => [sampleEntries.first]);

    ErrorLogEntry? reported;
    await tester.pumpWidget(buildTestWidget(
      onReport: (context, entry) {
        reported = entry;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Lapor'));
    await tester.pumpAndSettle();

    expect(reported?.id, 1);
    expect(reported?.sourceId, 'nhentai');
  });
}
