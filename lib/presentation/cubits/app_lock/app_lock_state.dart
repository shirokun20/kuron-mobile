import 'package:nhasixapp/presentation/cubits/base/base_cubit.dart';

abstract class AppLockState extends BaseCubitState {
  const AppLockState();
}

class AppLockLoading extends AppLockState {
  const AppLockLoading();

  @override
  List<Object?> get props => [];
}

class AppLockReady extends AppLockState {
  const AppLockReady({
    this.isLocked = false,
    this.isPinEnabled = false,
    this.isBiometricEnabled = false,
    this.hasPin = false,
    this.isBiometricAvailable = false,
  });

  final bool isLocked;
  final bool isPinEnabled;
  final bool isBiometricEnabled;
  final bool hasPin;
  final bool isBiometricAvailable;

  bool get showLockGate => isLocked && (isPinEnabled || hasPin);

  @override
  List<Object?> get props => [
        isLocked,
        isPinEnabled,
        isBiometricEnabled,
        hasPin,
        isBiometricAvailable,
      ];

  AppLockReady copyWith({
    bool? isLocked,
    bool? isPinEnabled,
    bool? isBiometricEnabled,
    bool? hasPin,
    bool? isBiometricAvailable,
  }) {
    return AppLockReady(
      isLocked: isLocked ?? this.isLocked,
      isPinEnabled: isPinEnabled ?? this.isPinEnabled,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      hasPin: hasPin ?? this.hasPin,
      isBiometricAvailable: isBiometricAvailable ?? this.isBiometricAvailable,
    );
  }
}

class AppLockError extends AppLockState {
  const AppLockError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
