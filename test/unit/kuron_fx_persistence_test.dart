import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

/// Regression guard for the live-app bug: `kuronFxMode` was emitted by
/// [SettingsCubit] but never written/read by [PreferencesService], so a
/// `standard`/`satire` selection silently degraded back to `quiet` on restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final quietLogger = Logger(level: Level.off);

  Future<PreferencesService> freshService() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs, logger: quietLogger);
  }

  Future<SettingsCubit> freshCubit() async {
    final cubit = SettingsCubit(
      preferencesService: await freshService(),
      logger: quietLogger,
    );
    await cubit.stream.firstWhere((state) => state is SettingsLoaded);
    return cubit;
  }

  for (final mode in KuronFxMode.values) {
    test('PreferencesService round-trips kuronFxMode=$mode', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = await freshService();
      await writer.saveUserPreferences(
        const UserPreferences().copyWith(kuronFxMode: mode.storageValue),
      );

      // A fresh service instance == a fresh app launch.
      final reader = await freshService();
      final loaded = await reader.getUserPreferences();
      expect(loaded.kuronFxMode, mode.storageValue);
    });
  }

  test('individual setters/getter persist an unknown value safely', () async {
    SharedPreferences.setMockInitialValues({'kuron_fx_mode': 'legacy'});
    final service = await freshService();
    expect(
      (await service.getUserPreferences()).kuronFxMode,
      KuronFxMode.quiet.storageValue,
    );

    await service.setKuronFxMode(KuronFxMode.satire.storageValue);
    final reloaded = await freshService();
    expect(
      (await reloaded.getUserPreferences()).kuronFxMode,
      KuronFxMode.satire.storageValue,
    );
  });

  test('SettingsCubit emits immediately AND survives a full restart', () async {
    SharedPreferences.setMockInitialValues({});
    final cubit = await freshCubit();

    for (final mode in [
      KuronFxMode.standard,
      KuronFxMode.satire,
      KuronFxMode.quiet,
    ]) {
      await cubit.updateKuronFxMode(mode.storageValue);
      final emitted = cubit.state;
      expect(emitted, isA<SettingsLoaded>());
      expect(
        (emitted as SettingsLoaded).preferences.kuronFxMode,
        mode.storageValue,
        reason: 'Settings must emit the new FX mode immediately',
      );

      final restarted = await freshCubit();
      expect(
        (restarted.state as SettingsLoaded).preferences.kuronFxMode,
        mode.storageValue,
        reason: 'FX mode must survive a fresh SettingsCubit / preferences read',
      );
      await restarted.close();
    }
    await cubit.close();
  });
}
