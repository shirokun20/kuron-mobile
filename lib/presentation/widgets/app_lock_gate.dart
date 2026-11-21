import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_cubit.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_state.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_entry_screen.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_setup_screen.dart';

// Renders PIN/biometric gate when locked. Passes through when unlocked
// or session active. Session lasts 10 min after unlock (persisted),
// so background/foreground within session does not re-lock.
class AppLockGate extends StatefulWidget {
  const AppLockGate({required this.child, super.key});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inited) {
      _inited = true;
      // Init runs once. If session active, gate stays unlocked.
      context.read<AppLockCubit>().init();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<AppLockCubit, AppLockState>(
      builder: (context, lockState) {
        if (lockState is AppLockLoading) {
          return const SizedBox.shrink();
        }

        if (lockState is AppLockReady) {
          // Show setup only when PIN is enabled but no PIN stored yet.
          // If PIN is disabled, just pass through — dont ask to set up again.
          if (!lockState.hasPin && lockState.isPinEnabled) {
            return PinSetupScreen(onSetupComplete: (_) {});
          }
          if (lockState.showLockGate) {
            return PinEntryScreen(
              title: l10n.enterPin,
              subtitle: l10n.unlockKuron,
              showBiometric:
                  lockState.isBiometricEnabled &&
                  lockState.isBiometricAvailable,
              onPinEntered: (pin) =>
                  context.read<AppLockCubit>().verifyPin(pin),
              onBiometricTap: () async =>
                  context.read<AppLockCubit>().authenticateBiometric(),
            );
          }
        }

        return widget.child;
      },
    );
  }
}
