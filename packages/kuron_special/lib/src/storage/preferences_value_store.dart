import 'package:kuron_core/kuron_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Plaintext [SecureValueStore] backed by SharedPreferences
// (NSUserDefaults on macOS, which needs no keychain entitlement).
//
// Intended ONLY as the [FallbackSecureValueStore.fallback] for clearance
// tokens on platforms where the secure primary is unavailable (unsigned
// macOS dev builds throw -34018 on every keychain access). On signed builds
// and Android the secure primary never throws, so this store is never
// touched — no production secret ever lands in plaintext prefs.
class PreferencesValueStore implements SecureValueStore {
  PreferencesValueStore({required this._prefs});

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
}
