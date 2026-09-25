import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/native_backup_service.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:nhasixapp/data/repositories/settings_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockNativeBackupService extends Mock implements NativeBackupService {}

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

/// Audit parity between the legacy whole-blob exporter/importer and the
/// per-key backup path the `kuron-full-backup` change uses: every key the
/// exporter produces must round-trip, existing device values must win, and
/// unknown keys must be skipped instead of failing the restore.
void main() {
  late SharedPreferences prefs;
  late SettingsRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_preferences': '{"theme":"system","defaultLanguage":"ind"}',
      'theme_settings': '{"mode":"dark"}',
      'reader_settings': '{"mode":"scroll"}',
      'download_settings': '{"maxConcurrent":3}',
      'privacy_settings': '{"blur":true}',
      'network_settings': '{"dns":"doh"}',
      'backup_settings': '{"auto":false}',
      'advanced_settings': '{"hive":true}',
      'custom_themes': '[{"id":"x"}]',
    });
    prefs = await SharedPreferences.getInstance();
    repo = SettingsRepositoryImpl(
      sharedPreferences: prefs,
      nativeBackupService: _MockNativeBackupService(),
      databaseHelper: _MockDatabaseHelper(),
    );
  });

  test('export covers every section the legacy exporter writes', () async {
    final keys = await repo.exportSettingsKeys();

    expect(
        keys.keys,
        containsAll(<String>[
          'user_preferences',
          'theme_settings',
          'reader_settings',
          'download_settings',
          'privacy_settings',
          'network_settings',
          'backup_settings',
          'advanced_settings',
          'custom_themes',
        ]));
    // Raw JSON per key, not a re-serialized blob.
    expect(keys['theme_settings'], '{"mode":"dark"}');
  });

  test('round trip into an empty device reproduces every value', () async {
    final keys = await repo.exportSettingsKeys();
    // Simulate a fresh device: no settings stored at all.
    for (final key in keys.keys) {
      await prefs.remove(key);
    }

    final applied = await repo.importSettingsKeys(keys, onlyIfAbsent: true);
    expect(applied.applied, keys.length);
    expect(applied.skipped, 0);

    final after = await repo.exportSettingsKeys();
    expect(after, keys);
  });

  test('device value wins per key (onlyIfAbsent)', () async {
    // Only theme_settings exists on this device.
    await prefs.remove('download_settings');

    final applied = await repo.importSettingsKeys(
      {
        'theme_settings': '{"mode":"light"}',
        'download_settings': '{"maxConcurrent":9}',
      },
      onlyIfAbsent: true,
    );

    expect(applied, (applied: 1, skipped: 1));
    expect(prefs.getString('theme_settings'), '{"mode":"dark"}'); // device wins
    expect(
      prefs.getString('download_settings'),
      '{"maxConcurrent":9}',
    ); // was absent -> applied
  });

  test('overwrite mode replaces the device value', () async {
    final applied = await repo.importSettingsKeys(
      {'theme_settings': '{"mode":"light"}'},
      onlyIfAbsent: false,
    );

    expect(applied, (applied: 1, skipped: 0));
    expect(prefs.getString('theme_settings'), '{"mode":"light"}');
  });

  test('unknown keys are skipped, never failed', () async {
    final applied = await repo.importSettingsKeys(
      {
        'theme_settings': '{"mode":"light2"}',
        'from_a_newer_app': '{"x":1}',
        'content_filter_settings': '{"y":2}',
      },
      onlyIfAbsent: false,
    );

    // content_filter_settings and from_a_newer_app are both outside the
    // exported key set, so both count as skipped.
    expect(applied, (applied: 1, skipped: 2));
    expect(prefs.getString('content_filter_settings'), isNull);
  });

  test('only keys the device actually holds are exported', () async {
    await prefs.remove('custom_themes');
    await prefs.remove('advanced_settings');
    final keys = await repo.exportSettingsKeys();
    expect(keys.containsKey('custom_themes'), isFalse);
    expect(keys.containsKey('advanced_settings'), isFalse);
  });
}
