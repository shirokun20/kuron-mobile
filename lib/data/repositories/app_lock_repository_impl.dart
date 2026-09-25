import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nhasixapp/domain/repositories/app_lock_repository.dart';

class AppLockRepositoryImpl implements AppLockRepository {
  AppLockRepositoryImpl({required FlutterSecureStorage storage})
      : _storage = storage;

  final FlutterSecureStorage _storage;

  static const _keyPinHash = 'app_lock_pin_hash';
  static const _keyPinEnabled = 'app_lock_pin_enabled';
  static const _keyBiometricEnabled = 'app_lock_biometric_enabled';
  static const _keyBiometricAvailable = 'app_lock_biometric_available';
  static const _keySessionExpiry = 'app_lock_session_expiry';

  @override
  Future<void> savePinHash(String hash) =>
      _storage.write(key: _keyPinHash, value: hash);

  @override
  Future<String?> getPinHash() => _storage.read(key: _keyPinHash);

  @override
  Future<void> setPinEnabled(bool enabled) =>
      _storage.write(key: _keyPinEnabled, value: enabled.toString());

  @override
  Future<bool> getPinEnabled() async {
    final val = await _storage.read(key: _keyPinEnabled);
    return val == 'true';
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _keyBiometricEnabled, value: enabled.toString());

  @override
  Future<bool> getBiometricEnabled() async {
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  @override
  Future<bool> isBiometricAvailable() async {
    final val = await _storage.read(key: _keyBiometricAvailable);
    return val == 'true';
  }

  Future<void> setBiometricAvailable(bool available) =>
      _storage.write(key: _keyBiometricAvailable, value: available.toString());

  @override
  Future<void> saveSessionExpiry(DateTime expiry) => _storage.write(
      key: _keySessionExpiry, value: expiry.millisecondsSinceEpoch.toString());

  @override
  Future<DateTime?> getSessionExpiry() async {
    final val = await _storage.read(key: _keySessionExpiry);
    if (val == null) return null;
    final ms = int.tryParse(val);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  @override
  Future<void> clearSession() => _storage.delete(key: _keySessionExpiry);

  @override
  Future<bool> isSessionActive() async {
    final expiry = await getSessionExpiry();
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyPinHash),
      _storage.delete(key: _keyPinEnabled),
      _storage.delete(key: _keyBiometricEnabled),
      _storage.delete(key: _keyBiometricAvailable),
      _storage.delete(key: _keySessionExpiry),
    ]);
  }
}
