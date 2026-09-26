import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/imports/import_nclient_backup_usecase.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup.dart';
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
  // backup_flow logs import failures via GetIt<Logger>.
  setUpAll(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    }
  });

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

  // The progress dialog is barrierDismissible:false, so a throwing import used
  // to leave the user stuck on a dialog that could never close.
  testWidgets('import failure closes the progress dialog and reports it',
      (tester) async {
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              runNclientImport(context, useCase: _ThrowingUseCase()),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // preview -> confirm -> import throws
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('successful import ends in the summary dialog', (tester) async {
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => runNclientImport(context, useCase: _OkUseCase()),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Favorites: 1 added'), findsOneWidget);
    expect(find.text('Unreadable rows: 0 added, 0 skipped, 2 failed'),
        findsOneWidget);
  });
}

class _FakeUseCase extends ImportNclientBackupUseCase {
  _FakeUseCase()
      : super(
          kuronNative: _MockNative(),
          userDataRepository: _MockUserData(),
          readerRepository: _MockReader(),
        );

  @override
  Future<NclientBackup?> pickAndParse() async => const NclientBackup(
        galleries: [
          NclientGallery(idGallery: 1, titlePretty: 'G1', mediaId: 11)
        ],
      );

  @override
  Future<NclientImportSummary> import(
    NclientBackup backup, {
    NclientImportProgress? onProgress,
  }) async {
    onProgress?.call('favorites', 1, 1);
    return {
      'favorites': (success: 1, skipped: 0, failed: 0),
      'malformed': (success: 0, skipped: 0, failed: 2),
    };
  }
}

class _OkUseCase extends _FakeUseCase {}

class _ThrowingUseCase extends _FakeUseCase {
  @override
  Future<NclientImportSummary> import(
    NclientBackup backup, {
    NclientImportProgress? onProgress,
  }) async =>
      throw StateError('boom');
}

class _MockNative extends Mock implements KuronNative {}

class _MockUserData extends Mock implements UserDataRepository {}

class _MockReader extends Mock implements ReaderRepository {}
