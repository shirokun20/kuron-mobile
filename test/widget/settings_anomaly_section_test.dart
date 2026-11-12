import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_list_screen.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_store_contract.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_contract.dart';
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_screen.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_anomaly_widgets.dart';

class _MockAnomalyStore extends Mock implements AnomalyStoreContract {}
class _MockErrorLog extends Mock implements ErrorLogContract {}

void main() {
  late _MockAnomalyStore anomalyStore;
  late _MockErrorLog errorLog;

  setUp(() {
    anomalyStore = _MockAnomalyStore();
    errorLog = _MockErrorLog();
    when(() => anomalyStore.records()).thenAnswer((_) async => <AnomalyRecord>[]);
    when(() => errorLog.isEnabled()).thenAnswer((_) async => false);
    when(() => errorLog.entries(limit: any(named: 'limit')))
        .thenAnswer((_) async => <ErrorLogEntry>[]);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: SingleChildScrollView(
              child: buildAnomalySection(
                context,
                theme,
                l10n,
                anomalyStore: anomalyStore,
                errorLogStore: errorLog,
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets('renders section header, anomaly tile, and error log tile', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('DIAGNOSTIK & ANOMALI SOURCE'), findsOneWidget);
    expect(find.text('Anomali Source'), findsOneWidget);
    expect(find.text('Log Error Respons'), findsOneWidget);
    expect(find.text('Lihat'), findsOneWidget);
    expect(find.text('Buka'), findsOneWidget);
  });

  testWidgets('tapping Lihat navigates to AnomalyListScreen', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat'));
    await tester.pumpAndSettle();

    expect(find.byType(AnomalyListScreen), findsOneWidget);
  });

  testWidgets('tapping Buka navigates to ErrorLogScreen', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorLogScreen), findsOneWidget);
  });
}
