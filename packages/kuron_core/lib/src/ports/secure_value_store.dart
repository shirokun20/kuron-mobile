// Platform port for secret persistence (key-value string secrets).
//
// Lives in kuron_core so pure-Dart packages can depend on the contract
// without importing Flutter-only plugins. The production implementation
// (Keystore-backed) lives in kuron_special; tests use
// [InMemorySecureValueStore].
library;

/// Minimal key-value secret storage contract.
abstract class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Primary/fallback [SecureValueStore] pair.
///
/// Reads try [primary] first and fall back to [fallback] only when [primary]
/// throws; writes/deletes try [primary] first and use [fallback] only on
/// failure. On platforms where the primary works (signed builds, Android
/// keystore) the fallback is never touched.
///
/// Motivating case: unsigned macOS dev builds where the keychain-backed
/// primary throws `PlatformException(-34018)` on every access — the fallback
/// (e.g. a preferences-backed store) keeps clearance tokens alive across
/// restarts instead of degrading to memory-only.
class FallbackSecureValueStore implements SecureValueStore {
  FallbackSecureValueStore({required this.primary, required this.fallback});

  final SecureValueStore primary;
  final SecureValueStore fallback;

  @override
  Future<String?> read(String key) async {
    try {
      return await primary.read(key);
    } catch (_) {
      return fallback.read(key);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await primary.write(key, value);
    } catch (_) {
      await fallback.write(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await primary.delete(key);
    } catch (_) {
      await fallback.delete(key);
    }
  }
}

/// Non-persistent [SecureValueStore] for tests and opt-in fallbacks.
/// Never use for real credentials — contents die with the process.
class InMemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}
