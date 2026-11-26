import 'package:flutter_test/flutter_test.dart';

import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

void main() {
  test('fx mode defaults to quiet and round-trips through preferences', () {
    const defaults = UserPreferences();
    expect(defaults.kuronFxMode, 'quiet');

    for (final mode in KuronFxMode.values) {
      final prefs = defaults.copyWith(kuronFxMode: mode.storageValue);
      expect(prefs.kuronFxMode, mode.storageValue);
      final restored = UserPreferences.fromJson(prefs.toJson());
      expect(restored.kuronFxMode, mode.storageValue);
    }

    // Unknown/legacy values degrade to quiet.
    expect(
      UserPreferences.fromJson({'kuronFxMode': 'wild'}).kuronFxMode,
      KuronFxMode.quiet.storageValue,
    );
    expect(KuronFxModeStorage.fromStorage(null), KuronFxMode.quiet);
  });
}
