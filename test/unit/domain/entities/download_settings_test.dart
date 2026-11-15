import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/settings/download_settings.dart' as domain;
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';

void main() {
  group('DownloadSettings Entity & State', () {
    test('domain.DownloadSettings defaults pauseOnOnlineReaderOnly to true', () {
      const settings = domain.DownloadSettings(
        maxConcurrentDownloads: 3,
        autoRetryFailed: true,
        wifiOnlyDownload: false,
        deleteAfterReading: false,
      );
      expect(settings.pauseOnOnlineReaderOnly, isTrue);
    });

    test('DownloadSettings defaults pauseOnOnlineReaderOnly to true', () {
      final settings = DownloadSettings.defaultSettings();
      expect(settings.pauseOnOnlineReaderOnly, isTrue);
    });

    test('DownloadSettings.copyWith modifies pauseOnOnlineReaderOnly', () {
      final settings = DownloadSettings.defaultSettings();
      final updated = settings.copyWith(pauseOnOnlineReaderOnly: false);
      expect(updated.pauseOnOnlineReaderOnly, isFalse);
      expect(updated.maxConcurrentDownloads, settings.maxConcurrentDownloads);

      final reverted = updated.copyWith(pauseOnOnlineReaderOnly: true);
      expect(reverted.pauseOnOnlineReaderOnly, isTrue);
    });
  });

  group('UserPreferences Serialization', () {
    test('UserPreferences defaults pauseOnOnlineReaderOnly to true', () {
      const prefs = UserPreferences();
      expect(prefs.pauseOnOnlineReaderOnly, isTrue);
    });

    test('UserPreferences toJson and fromJson round-trip preserves pauseOnOnlineReaderOnly', () {
      const prefs = UserPreferences(pauseOnOnlineReaderOnly: false);
      final json = prefs.toJson();
      expect(json['pauseOnOnlineReaderOnly'], isFalse);

      final restored = UserPreferences.fromJson(json);
      expect(restored.pauseOnOnlineReaderOnly, isFalse);
    });

    test('UserPreferences copyWith updates pauseOnOnlineReaderOnly', () {
      const prefs = UserPreferences(pauseOnOnlineReaderOnly: true);
      final updated = prefs.copyWith(pauseOnOnlineReaderOnly: false);
      expect(updated.pauseOnOnlineReaderOnly, isFalse);
    });

    test('DownloadSettingsUpdateEvent props include pauseOnOnlineReaderOnly', () {
      const event1 = DownloadSettingsUpdateEvent(pauseOnOnlineReaderOnly: true);
      const event2 = DownloadSettingsUpdateEvent(pauseOnOnlineReaderOnly: true);
      const event3 = DownloadSettingsUpdateEvent(pauseOnOnlineReaderOnly: false);

      expect(event1, equals(event2));
      expect(event1, isNot(equals(event3)));
    });
  });
}
