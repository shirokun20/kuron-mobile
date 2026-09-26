import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kuron_core/kuron_core.dart';

// Keystore-backed [SecureValueStore] for production.
class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read(String key) => _secureStorage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _secureStorage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _secureStorage.delete(key: key);
}
