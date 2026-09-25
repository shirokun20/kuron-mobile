import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_serializer.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/backup_flow.dart';

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
  testWidgets('restore flow: preview -> confirm -> progress -> summary',
      (tester) async {
    var ran = false;

    await tester.pumpWidget(wrap(Builder(
      builder: (context) {
        final labels = backupCategoryLabels(AppLocalizations.of(context)!);
        return TextButton(
          onPressed: () async {
            await runBackupImportFlow(
              context: context,
              counts: const {
                'favorites': 2,
                'collections': 1,
                'memberships': 3,
                'history': 5,
                'positions': 4,
                'settings': 8,
              },
              labels: labels,
              run: (onProgress) async {
                ran = true;
                onProgress('favorites', 1, 2);
                onProgress('favorites', 2, 2);
                return const {
                  'favorites': (success: 2, skipped: 0, failed: 0),
                  'settings': (success: 8, skipped: 0, failed: 0),
                };
              },
              previewTitle: 'Restore preview',
              resultTitle: 'Restore result',
            );
          },
          child: const Text('open'),
        );
      },
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Preview lists every category the restore will write.
    expect(find.text('Restore preview'), findsOneWidget);
    expect(find.textContaining('Favorites: 2'), findsOneWidget);
    expect(find.textContaining('Settings: 8'), findsOneWidget);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(ran, isTrue);
    expect(find.text('Restore result'), findsOneWidget);
    expect(
      find.textContaining('Favorites: 2 added, 0 skipped, 0 failed'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the preview writes nothing', (tester) async {
    var ran = false;
    late AppLocalizations l10n;

    await tester.pumpWidget(wrap(Builder(
      builder: (context) {
        l10n = AppLocalizations.of(context)!;
        return TextButton(
          onPressed: () async {
            await runBackupImportFlow(
              context: context,
              counts: const {'favorites': 2},
              labels: backupCategoryLabels(l10n),
              run: (onProgress) async {
                ran = true;
                return const {};
              },
            );
          },
          child: const Text('open'),
        );
      },
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(ran, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a failing restore closes the dialog and reports the error',
      (tester) async {
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () => runBackupImportFlow(
          context: context,
          counts: const {'favorites': 1},
          labels: backupCategoryLabels(AppLocalizations.of(context)!),
          run: (onProgress) async => throw StateError('boom'),
        ),
        child: const Text('open'),
      ),
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  test('exported ZIP name is the documented one', () {
    expect(
      KuronBackupSerializer.fileName(DateTime.fromMillisecondsSinceEpoch(42)),
      'KuronBackup_42.zip',
    );
  });
}
