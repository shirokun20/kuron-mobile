import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_detail_screen.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_list_screen.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_store_contract.dart';

class _MockAnomalyStore extends Mock implements AnomalyStoreContract {}

void main() {
  late _MockAnomalyStore store;

  setUp(() {
    store = _MockAnomalyStore();
  });

  final testRecordIneligible = AnomalyRecord(
    fingerprint: 'fp_123',
    sourceId: 'nhentai',
    feature: 'reader-empty',
    kind: 'images array 0',
    count: 1,
    lastSeen: DateTime(2026, 11, 12, 12, 0),
    eligible: false,
    configVersion: '1.0.2',
    context: const {'chapterId': '12345'},
  );

  final testRecordEligible = AnomalyRecord(
    fingerprint: 'fp_456',
    sourceId: 'komikindo',
    feature: 'tag-nav',
    kind: 'explicitMappingFailed',
    count: 2,
    lastSeen: DateTime(2026, 11, 12, 14, 0),
    eligible: true,
    configVersion: '2.1.0',
    context: const {'tag': 'Action'},
  );

  group('AnomalyListScreen', () {
    testWidgets('shows empty state when no anomaly records exist', (tester) async {
      when(() => store.records()).thenAnswer((_) async => <AnomalyRecord>[]);

      await tester.pumpWidget(MaterialApp(
        home: AnomalyListScreen(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada anomali source'), findsOneWidget);
    });

    testWidgets('shows list of records with count, status, and metadata', (tester) async {
      when(() => store.records())
          .thenAnswer((_) async => [testRecordIneligible, testRecordEligible]);

      await tester.pumpWidget(MaterialApp(
        home: AnomalyListScreen(store: store),
      ));
      await tester.pumpAndSettle();

      expect(find.text('nhentai'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      expect(find.text('Pending (1×)'), findsOneWidget);
      expect(find.text('reader-empty — images array 0'), findsOneWidget);

      expect(find.text('komikindo'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      expect(find.text('Eligible'), findsOneWidget);
      expect(find.text('tag-nav — explicitMappingFailed'), findsOneWidget);
    });

    testWidgets('deletes record after confirmation dialog', (tester) async {
      when(() => store.records())
          .thenAnswer((_) async => [testRecordIneligible]);
      when(() => store.deleteRecord('fp_123')).thenAnswer((_) async {});

      await tester.pumpWidget(MaterialApp(
        home: AnomalyListScreen(store: store),
      ));
      await tester.pumpAndSettle();

      // Tap delete icon
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Hapus Anomali'), findsOneWidget);

      // When confirmed, next load returns empty list
      when(() => store.records()).thenAnswer((_) async => <AnomalyRecord>[]);

      // Confirm delete
      await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await tester.pumpAndSettle();

      verify(() => store.deleteRecord('fp_123')).called(1);
      expect(find.text('Tidak ada anomali source'), findsOneWidget);
    });
  });

  group('AnomalyDetailScreen', () {
    testWidgets('displays details and does NOT show report button when ineligible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        home: AnomalyDetailScreen(
          record: testRecordIneligible,
          store: store,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Detail Anomali'), findsOneWidget);
      expect(find.text('Belum Eligible'), findsOneWidget);
      expect(find.text('fp_123'), findsOneWidget);
      expect(find.text('1.0.2'), findsOneWidget);

      // Report button MUST NOT be present
      expect(find.byKey(const Key('report_anomaly_button')), findsNothing);
      expect(
        find.textContaining('Tombol lapor belum aktif: anomaly butuh 2 kejadian'),
        findsOneWidget,
      );
    });

    testWidgets('displays details and shows report button when eligible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool reportCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: AnomalyDetailScreen(
          record: testRecordEligible,
          store: store,
          onReport: (context, record) {
            reportCalled = true;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Eligible untuk Lapor'), findsOneWidget);
      expect(find.text('fp_456'), findsOneWidget);

      // Report button MUST be present
      final reportBtn = find.byKey(const Key('report_anomaly_button'));
      expect(reportBtn, findsOneWidget);

      await tester.tap(reportBtn);
      await tester.pumpAndSettle();

      expect(reportCalled, isTrue);
    });
  });
}
