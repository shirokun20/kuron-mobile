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
