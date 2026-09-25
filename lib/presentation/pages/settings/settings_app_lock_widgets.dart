import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_cubit.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_state.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_setup_screen.dart';
import 'settings_theme_widgets.dart';

// ── PIN setup sheet (first time) ───────────────────────────────────────

void showPinSetupSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      height: MediaQuery.of(sheetContext).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(sheetContext).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: BlocProvider.value(
        value: context.read<AppLockCubit>(),
        child: PinSetupScreen(
          mode: PinSetupMode.setup,
          onSetupComplete: (_) {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
        ),
      ),
    ),
  );
}

// ── PIN change sheet (old → new → confirm) ────────────────────────────

void showPinChangeDialog(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PinChangeSheet(),
  );
}

class _PinChangeSheet extends StatefulWidget {
  @override
  State<_PinChangeSheet> createState() => _PinChangeSheetState();
}

class _PinChangeSheetState extends State<_PinChangeSheet> {
  int _step = 0; // 0=old pin, 1=new pin, 2=confirm new
  String _oldPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String? _error;
  bool _isLoading = false;
  static const _maxDigits = 6;

  String get _activePin {
    switch (_step) {
      case 0:
        return _oldPin;
      case 1:
        return _newPin;
      case 2:
        return _confirmPin;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final height = MediaQuery.of(context).size.height * 0.65;
    final entries = <_LabelPair>[
      _LabelPair(l10n.enterCurrentPin, l10n.enterCurrentPinSubtitle),
      _LabelPair(l10n.enterNewPin, l10n.enterNewPinSubtitle(_maxDigits)),
      _LabelPair(l10n.confirmNewPin, l10n.confirmNewPinSubtitle),
    ];

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: _PinKeypadBody(
          title: entries[_step].title,
          subtitle: entries[_step].subtitle,
          pin: _activePin,
          maxDigits: _maxDigits,
          error: _error,
          onDigit: _onDigit,
          onDelete: _onDelete,
        ),
      ),
    );
  }

  void _onDigit(String digit) {
    if (_isLoading || _activePin.length >= _maxDigits) return;
    setState(() => _error = null);

    switch (_step) {
      case 0:
        _oldPin += digit;
        if (_oldPin.length == _maxDigits) _verifyOldPin();
        break;
      case 1:
        _newPin += digit;
        if (_newPin.length == _maxDigits) {
          setState(() => _step = 2);
        }
        break;
      case 2:
        _confirmPin += digit;
        if (_confirmPin.length == _maxDigits) _doChange();
        break;
    }
  }

  void _onDelete() {
    if (_isLoading) return;
    setState(() {
      if (_activePin.isNotEmpty) {
        switch (_step) {
          case 0:
            _oldPin = _oldPin.substring(0, _oldPin.length - 1);
          case 1:
            _newPin = _newPin.substring(0, _newPin.length - 1);
          case 2:
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      } else if (_step == 2) {
        _step = 1;
      }
      _error = null;
    });
  }

  Future<void> _verifyOldPin() async {
    setState(() => _isLoading = true);
    final cubit = context.read<AppLockCubit>();
    final correct = await cubit.verifyPin(_oldPin);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (correct) {
        _oldPin = '';
        _step = 1;
      } else {
        _error = AppLocalizations.of(context)!.wrongPin;
        _oldPin = '';
      }
    });
  }

  Future<void> _doChange() async {
    final l10n = AppLocalizations.of(context)!;
    if (_newPin != _confirmPin) {
      setState(() {
        _error = l10n.pinsDoNotMatch;
        _step = 1;
        _newPin = '';
        _confirmPin = '';
      });
      return;
    }
    setState(() => _isLoading = true);
    final cubit = context.read<AppLockCubit>();
    final success = await cubit.setupPin(_newPin);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pinChangedSuccess)),
      );
    } else {
      setState(() => _error = l10n.failedToChangePin);
    }
  }
}

class _LabelPair {
  final String title;
  final String subtitle;
  const _LabelPair(this.title, this.subtitle);
}

// ── PIN dots row ───────────────────────────────────────────────────────

Widget _pinDots(int pinLength, int maxDigits, ThemeData theme) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(maxDigits, (i) {
      final filled = i < pinLength;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: filled
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      );
    }),
  );
}

Widget _keypadRow(
    ThemeData theme, List<String> digits, void Function(String) onDigit) {
  return Row(
    children: digits
        .map((d) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                    onTap: () => onDigit(d),
                    child: Container(
                      height: 64,
                      alignment: Alignment.center,
                      child: Text(d,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ))
        .toList(),
  );
}

Widget _keypadBackspace(ThemeData theme, VoidCallback onDelete) {
  return Expanded(
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          onTap: onDelete,
          child: Container(
            height: 64,
            alignment: Alignment.center,
            child: Icon(Icons.backspace_outlined,
                color: theme.colorScheme.onSurfaceVariant, size: 24),
          ),
        ),
      ),
    ),
  );
}

// ── PIN keypad body ────────────────────────────────────────────────────

class _PinKeypadBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final String pin;
  final int maxDigits;
  final String? error;
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _PinKeypadBody({
    required this.title,
    required this.subtitle,
    required this.pin,
    required this.maxDigits,
    this.error,
    required this.onDigit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const Spacer(flex: 2),
        Text(title,
            style: TextStyleConst.headingMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyleConst.bodyMedium
                .copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 48),
        _pinDots(pin.length, maxDigits, theme),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!,
              style: TextStyleConst.bodyMedium.copyWith(
                  color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
        ],
        const Spacer(flex: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              _keypadRow(theme, ['1', '2', '3'], onDigit),
              _keypadRow(theme, ['4', '5', '6'], onDigit),
              _keypadRow(theme, ['7', '8', '9'], onDigit),
              Row(
                children: [
                  const Expanded(child: SizedBox()),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Material(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusXl),
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusXl),
                          onTap: () => onDigit('0'),
                          child: Container(
                            height: 64,
                            alignment: Alignment.center,
                            child: const Text('0',
                                style: TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _keypadBackspace(theme, onDelete),
                ],
              ),
            ],
          ),
        ),
        const Spacer(flex: 1),
      ],
    );
  }
}

// ── App Lock settings section ──────────────────────────────────────────

Widget buildAppLockSection(BuildContext context, ThemeData theme) {
  final l10n = AppLocalizations.of(context)!;

  return BlocBuilder<AppLockCubit, AppLockState>(
    builder: (context, state) {
      if (state is! AppLockReady) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingsSectionHeader(
              Icons.lock_outline, l10n.appLockSectionTitle, theme),
          const SizedBox(height: 12),
          buildSettingsCard([
            buildSettingsSwitchTile(
              title: l10n.pinLock,
              subtitle: state.hasPin ? l10n.pinLockActive : l10n.pinLockSet,
              value: state.isPinEnabled,
              onChanged: (v) async {
                if (v) {
                  showPinSetupSheet(context);
                } else {
                  _showDisablePinDialog(context);
                }
              },
              theme: theme,
            ),
            buildSettingsDivider(theme),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(l10n.changePin,
                  style: TextStyleConst.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: state.hasPin
                          ? theme.colorScheme.onSurface
                          : theme.disabledColor)),
              subtitle: Text(l10n.changePinDescription,
                  style: TextStyleConst.bodySmall
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)),
              trailing: Icon(Icons.chevron_right,
                  color: state.hasPin
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.disabledColor),
              onTap: state.hasPin ? () => showPinChangeDialog(context) : null,
            ),
            buildSettingsDivider(theme),
            buildSettingsSwitchTile(
              title: l10n.biometricUnlock,
              subtitle: state.isBiometricAvailable
                  ? l10n.biometricAvailable
                  : l10n.biometricUnavailable,
              value: state.isBiometricEnabled,
              enabled: state.isBiometricAvailable && state.hasPin,
              onChanged: (v) async {
                final cubit = context.read<AppLockCubit>();
                if (v) {
                  await cubit.enableBiometric();
                } else {
                  await cubit.disableBiometric();
                }
              },
              theme: theme,
            ),
          ], theme),
        ],
      );
    },
  );
}

void _showDisablePinDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(l10n.disablePinLock),
      content: Text(l10n.disablePinLockDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _PinRemoveSheet(),
            );
          },
          child: Text(l10n.continue_),
        ),
      ],
    ),
  );
}

// ── PIN remove sheet ───────────────────────────────────────────────────

class _PinRemoveSheet extends StatefulWidget {
  @override
  State<_PinRemoveSheet> createState() => _PinRemoveSheetState();
}

class _PinRemoveSheetState extends State<_PinRemoveSheet> {
  String _pin = '';
  String? _error;
  bool _isLoading = false;
  static const _maxDigits = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: _PinKeypadBody(
          title: l10n.enterPinToDisable,
          subtitle: l10n.enterPinToDisableSubtitle,
          pin: _pin,
          maxDigits: _maxDigits,
          error: _error,
          onDigit: _onDigit,
          onDelete: _onDelete,
        ),
      ),
    );
  }

  void _onDigit(String digit) {
    if (_isLoading || _pin.length >= _maxDigits) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == _maxDigits) _submit();
  }

  void _onDelete() {
    if (_isLoading || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    final cubit = context.read<AppLockCubit>();
    final removed = await cubit.removePin(_pin);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (removed) {
        Navigator.of(context).pop();
      } else {
        _error = AppLocalizations.of(context)!.wrongPin;
        _pin = '';
      }
    });
  }
}
