import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/entities/settings/settings.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/settings_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/exports/export_kuron_backup_usecase.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_serializer.dart';
import 'package:nhasixapp/domain/usecases/exports/restore_kuron_backup_usecase.dart';

/// End-to-end round trip of the `kuron-full-backup` feature against the REAL
/// repositories and the real SQLite database: seed device A, export a ZIP, wipe
/// everything to simulate a fresh install (device B), then restore and verify.
///
/// Run it on a device or emulator (there is no desktop/web target):
///   fvm flutter test integration_test/kuron_backup_roundtrip_test.dart -d `DEVICE_ID`
///
/// It wipes favorites, collections, history, positions and the nine backed-up
/// settings keys on the device it runs on, so use a throwaway device/emulator.
const _sourceId = 'nhentai';
const _favoriteId = 'roundtrip-favorite-1';
const _historyId = 'roundtrip-history-1';
const _positionId = 'roundtrip-position-1';
const _collectionName = 'RoundTrip Collection';
const _epoch = 1700000000000;

/// Mirrors `SettingsRepositoryImpl._rawSettingsKeys` (the keys the backup
/// carries). Kept as literals because the impl constants are private.
const _settingsKeys = <String>[
  'user_preferences',
  'theme_settings',
  'reader_settings',
  'download_settings',
  'privacy_settings',
  'network_settings',
  'backup_settings',
  'advanced_settings',
  'custom_themes',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'backup from a seeded device restores on a wiped device, device wins on re-restore',
    (tester) async {
      await setupLocator();

      final userData = GetIt.I<UserDataRepository>();
      final reader = GetIt.I<ReaderRepository>();
      final settings = GetIt.I<SettingsRepository>();
      final exporter = GetIt.I<ExportKuronBackupUseCase>();
      final restorer = GetIt.I<RestoreKuronBackupUseCase>();

      // ---------- device A: seed ----------
      await _wipe(userData, settings);

      await userData.addToFavorites(
        id: _favoriteId,
        sourceId: _sourceId,
        coverUrl: 'https://example.test/roundtrip-cover.jpg',
        title: 'RoundTrip Favorite',
      );
      final collection =
          await userData.createFavoriteCollection(name: _collectionName);
      await userData.setFavoriteCollectionIds(
        favoriteId: _favoriteId,
        sourceId: _sourceId,
        collectionIds: [collection.id],
      );
      await userData.saveHistory(History(
        contentId: _historyId,
        sourceId: _sourceId,
        lastViewed: DateTime.fromMillisecondsSinceEpoch(_epoch),
        lastPage: 7,
        totalPages: 20,
        title: 'RoundTrip History',
        coverUrl: 'https://example.test/roundtrip-history.jpg',
      ));
      await reader.saveReaderPosition(ReaderPosition.create(
        contentId: _positionId,
        currentPage: 5,
        totalPages: 20,
        readingTimeMinutes: 42,
        title: 'RoundTrip Position',
        coverUrl: 'https://example.test/roundtrip-position.jpg',
      ));
      await settings.updatePrivacySettings(const PrivacySettings(
        hideFromRecents: true,
        requireAuthentication: false,
        blurInBackground: true,
        incognitoMode: true,
      ));

      final deviceASettings = await settings.exportSettingsKeys();
      expect(deviceASettings.keys, contains('privacy_settings'));

      // ---------- device A: export ----------
      final bytes = await exporter.export();
      expect(bytes, isNotEmpty);
      expect(
        KuronBackupSerializer.fileName(
            DateTime.fromMillisecondsSinceEpoch(_epoch)),
        'KuronBackup_$_epoch.zip',
      );

      // ---------- device B: fresh install ----------
      await _wipe(userData, settings);
      expect(await userData.getFavoritesCount(), 0);
      expect(await userData.getHistoryCount(), 0);
      expect(await reader.getAllReaderPositions(), isEmpty);
      expect(await userData.getFavoriteCollections(), isEmpty);

      // ---------- device B: restore ----------
      final backup = await restorer.parseBytesAsync(
        bytes,
        fileName: 'KuronBackup_$_epoch.zip',
      );
      final preview = restorer.preview(backup);
      expect(preview['favorites'], 1);
      expect(preview['collections'], 1);
      expect(preview['memberships'], 1);
      expect(preview['history'], 1);
      expect(preview['positions'], 1);
      expect(preview['settings'], isNot(0));

      final summary = await restorer.restore(backup);
      expect(summary['favorites']!.success, 1);
      expect(summary['favorites']!.failed, 0);
      expect(summary['collections']!.success, 1);
      expect(summary['collections']!.failed, 0);
      expect(summary['history']!.success, 1);
      expect(summary['history']!.failed, 0);
      expect(summary['positions']!.success, 1);
      expect(summary['positions']!.failed, 0);
      expect(summary['malformed']!.failed, 0);

      expect(
          await userData.isFavorite(_favoriteId, sourceId: _sourceId), isTrue);
      final restoredCollections = await userData.getFavoriteCollections();
      expect(restoredCollections.map((c) => c.name), contains(_collectionName));
      expect(
        await userData.getFavoriteCollectionIds(
          favoriteId: _favoriteId,
          sourceId: _sourceId,
        ),
        hasLength(1),
      );
      final restoredHistory = await userData.getHistoryEntry(_historyId);
      expect(restoredHistory?.lastPage, 7);
      expect(restoredHistory?.totalPages, 20);
      final restoredPosition = await reader.getReaderPosition(_positionId);
      expect(restoredPosition?.currentPage, 5);
      expect(restoredPosition?.totalPages, 20);
      expect(await settings.exportSettingsKeys(), equals(deviceASettings));
      expect((await settings.getPrivacySettings()).incognitoMode, isTrue);

      // ---------- device B: restore again, device must win ----------
      final second = await restorer.restore(backup);
      expect(second['favorites']!.success, 0);
      expect(second['favorites']!.skipped, 1);
      expect(second['collections']!.success, 0);
      expect(second['history']!.success, 0);
      expect(second['history']!.skipped, 1);
      expect(second['positions']!.success, 0);
      expect(second['positions']!.skipped, 1);
      expect(second['settings']!.success, 0);
      expect(second['settings']!.skipped, greaterThan(0));

      expect(await userData.getFavoritesCount(), 1);
      expect(await userData.getHistoryCount(), 1);
      expect(await reader.getAllReaderPositions(), hasLength(1));

      await _wipe(userData, settings);
    },
  );
}

/// `clearAllData` already drops history, favorites, collections, memberships
/// and reader positions in one FK-safe batch; settings live in SharedPreferences
/// and are removed per key.
Future<void> _wipe(
  UserDataRepository userData,
  SettingsRepository settings,
) async {
  await userData.clearAllData();
  for (final key in _settingsKeys) {
    await settings.removePreference(key);
  }
}
