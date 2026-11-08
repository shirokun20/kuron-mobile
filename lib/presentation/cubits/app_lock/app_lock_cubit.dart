import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nhasixapp/data/repositories/app_lock_repository_impl.dart';
import 'package:nhasixapp/domain/repositories/app_lock_repository.dart';
import 'dart:async';

import '../base/base_cubit.dart';
import 'app_lock_state.dart';

class AppLockCubit extends BaseCubit<AppLockState> {
  AppLockCubit({
    required AppLockRepository appLockRepository,
    required super.logger,
    this._biometricAuth,
  })  : _repository = appLockRepository,
        super(initialState: const AppLockLoading());

  final AppLockRepository _repository;
  final Future<bool> Function()? _biometricAuth;
  LocalAuthentication? _localAuth;
  bool _inited = false;
  Timer? _sessionTimer;

  static const _sessionDuration = Duration(minutes: 10);
  static const _sessionCheckInterval = Duration(seconds: 30);

  // Call after splash completes. Checks session first — if session active,
  // gate is unlocked. Otherwise shows PIN/biometric unlock.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      logInfo('Loading app lock');
      emit(const AppLockLoading());

      final isPinEnabled = await _repository.getPinEnabled();
      final pinHash = await _repository.getPinHash();
      final hasPin = pinHash != null && pinHash.isNotEmpty;
      final isBiometricEnabled = await _repository.getBiometricEnabled();
      bool biometricAvailable = await _repository.isBiometricAvailable();

      if (!biometricAvailable) {
        biometricAvailable = await _checkBiometricSupport();
        if (biometricAvailable) {
          final impl = _repository as AppLockRepositoryImpl?;
          if (impl != null) await impl.setBiometricAvailable(true);
        }
      }

      // Session check — skip lock if session still active
      final sessionActive = await _repository.isSessionActive();
      final isLocked = !sessionActive && hasPin && isPinEnabled;

      emit(AppLockReady(
        isLocked: isLocked,
        isPinEnabled: isPinEnabled,
        isBiometricEnabled: isBiometricEnabled,
        hasPin: hasPin,
        isBiometricAvailable: biometricAvailable,
      ));

      logInfo('App lock: pin=$isPinEnabled bio=$isBiometricEnabled '
          'hasPin=$hasPin locked=$isLocked session=$sessionActive');
    } catch (e, st) {
      logger.e('App lock init failed: $e', error: e, stackTrace: st);
      emit(AppLockError(message: 'Failed to load lock settings'));
    }
  }

  Future<bool> _checkBiometricSupport() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> setupPin(String pin) async {
    try {
      final hash = _hashPin(pin);
      await _repository.savePinHash(hash);
      await _repository.setPinEnabled(true);
      await _startSession();
      _emitWith(isLocked: false, isPinEnabled: true, hasPin: true);
      return true;
    } catch (e, st) {
      logger.e('Setup PIN failed: $e', error: e, stackTrace: st);
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final storedHash = await _repository.getPinHash();
      if (storedHash == null || storedHash.isEmpty) return false;
      final correct = _hashPin(pin) == storedHash;
      if (correct) {
        await _startSession();
        _emitWith(isLocked: false);
      }
      return correct;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    if (!await verifyPin(oldPin)) return false;
    return setupPin(newPin);
  }

  Future<bool> removePin(String pin) async {
    if (!await verifyPin(pin)) return false;
    await _repository.clear();
    _sessionTimer?.cancel();
    _emitWith(
      isLocked: false,
      isPinEnabled: false,
      isBiometricEnabled: false,
      hasPin: false,
    );
    return true;
  }

  Future<void> enableBiometric() async {
    await _repository.setBiometricEnabled(true);
    _emitWith(isBiometricEnabled: true);
  }

  Future<void> disableBiometric() async {
    await _repository.setBiometricEnabled(false);
    _emitWith(isBiometricEnabled: false);
  }

  Future<bool> authenticateBiometric() async {
    try {
      if (_biometricAuth != null) return await _biometricAuth();
      _localAuth ??= LocalAuthentication();
      final authed = await _localAuth!
          .authenticate(
            localizedReason: 'Unlock Kuron',
            biometricOnly: true,
            sensitiveTransaction: false,
          )
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (authed) {
        await _startSession();
        _emitWith(isLocked: false);
      }
      return authed;
    } catch (e) {
      logWarning('Biometric auth failed: $e');
      return false;
    }
  }

  // Start a new session — after this, [isSessionActive] returns true
  // for [_sessionDuration]. Gate skips lock during active session.
  Future<void> _startSession() async {
    final expiry = DateTime.now().add(_sessionDuration);
    await _repository.saveSessionExpiry(expiry);
    _sessionTimer?.cancel();
    _sessionTimer =
        Timer.periodic(_sessionCheckInterval, (_) => _checkSession());
    logInfo('Session started until $expiry');
  }

  void _checkSession() {
    final s = state;
    if (s is! AppLockReady || s.isLocked) {
      _sessionTimer?.cancel();
      return;
    }
    _repository.isSessionActive().then((active) {
      if (!active &&
          state is AppLockReady &&
          !(state as AppLockReady).isLocked) {
        _sessionTimer?.cancel();
        _emitWith(isLocked: true);
        logInfo('Session expired — locked');
      }
    });
  }

  void _emitWith({
    bool? isLocked,
    bool? isPinEnabled,
    bool? isBiometricEnabled,
    bool? hasPin,
    bool? isBiometricAvailable,
  }) {
    final s = state;
    if (s is! AppLockReady) return;
    emit(s.copyWith(
      isLocked: isLocked,
      isPinEnabled: isPinEnabled,
      isBiometricEnabled: isBiometricEnabled,
      hasPin: hasPin,
      isBiometricAvailable: isBiometricAvailable,
    ));
  }

  @override
  Future<void> close() {
    _sessionTimer?.cancel();
    return super.close();
  }

  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();
}
