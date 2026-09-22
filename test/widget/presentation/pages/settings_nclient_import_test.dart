import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/usecases/imports/import_nclient_backup_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_nclient_import.dart';

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('preview shows counts, cancel pops false', (tester) async {
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => NclientPreviewDialog(
        counts: const {
          'favorites': 2,
          'collections': 1,
          'memberships': 3,
          'history': 5,
          'positions': 0,
        },
        labels: const {
          'favorites': 'Favorites',
          'collections': 'Collections',
          'memberships': 'Items',
          'history': 'History',
          'positions': 'Positions',
        },
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Favorites: 2'), findsOneWidget);
    expect(find.text('Positions: 0'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('summary shows per-category rows', (tester) async {
    const NclientImportSummary summary = {
      'favorites': (success: 1, skipped: 2, failed: 0),
      'history': (success: 0, skipped: 0, failed: 1),
    };
    await tester.pumpWidget(wrap(const NclientSummaryDialog(
      summary: summary,
      labels: {'favorites': 'Favorites', 'history': 'History'},
    )));
    await tester.pumpAndSettle();
    expect(
        find.text('Favorites: 1 added, 2 skipped, 0 failed'), findsOneWidget);
    expect(find.text('History: 0 added, 0 skipped, 1 failed'), findsOneWidget);
  });
}
