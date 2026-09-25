import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_cubit.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    this.mode = PinSetupMode.setup,
    this.onSetupComplete,
    super.key,
  });

  final PinSetupMode mode;
  final void Function(bool success)? onSetupComplete;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

enum PinSetupMode { setup, change }

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _firstPin = '';
  String _confirmPin = '';
  bool _isConfirmPhase = false;
  String? _error;
  bool _isLoading = false;
  static const _maxDigits = 6;

  String get _activePin => _isConfirmPhase ? _confirmPin : _firstPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(Icons.lock_outline,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              _isConfirmPhase
                  ? l10n.confirmPin
                  : widget.mode == PinSetupMode.change
                      ? l10n.enterNewPin
                      : l10n.setupPin,
              style: TextStyleConst.headingMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirmPhase
                  ? l10n.confirmPinSubtitle
                  : l10n.setupPinSubtitle(_maxDigits),
              style: TextStyleConst.bodyMedium.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxDigits, (i) {
                final filled = i < _activePin.length;
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
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyleConst.bodyMedium.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(flex: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  _buildRow(theme, ['1', '2', '3']),
                  _buildRow(theme, ['4', '5', '6']),
                  _buildRow(theme, ['7', '8', '9']),
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      Expanded(child: _buildKey(theme, '0')),
                      _buildBackspace(theme),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  void _onDigit(String digit) {
    if (_isLoading) return;
    if (_activePin.length >= _maxDigits) return;
    setState(() => _error = null);

    if (_isConfirmPhase) {
      _confirmPin += digit;
      if (_confirmPin.length == _maxDigits) _onConfirmComplete();
    } else {
      _firstPin += digit;
      if (_firstPin.length == _maxDigits) {
        setState(() {
          _isConfirmPhase = true;
        });
      }
    }
  }

  void _onDelete() {
    if (_isLoading) return;
    if (_activePin.isEmpty) {
      if (_isConfirmPhase) {
        setState(() {
          _isConfirmPhase = false;
          _firstPin = '';
        });
      }
      return;
    }
    setState(() {
      if (_isConfirmPhase) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else {
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
      }
      _error = null;
    });
  }

  Future<void> _onConfirmComplete() async {
    final l10n = AppLocalizations.of(context)!;
    if (_firstPin != _confirmPin) {
      setState(() {
        _error = l10n.pinsDoNotMatch;
        _isConfirmPhase = false;
        _confirmPin = '';
      });
      return;
    }

    setState(() => _isLoading = true);
    final cubit = context.read<AppLockCubit>();
    final success = await cubit.setupPin(_firstPin);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      widget.onSetupComplete?.call(true);
    } else {
      setState(() => _error = l10n.failedToSavePin);
    }
  }

  Widget _buildRow(ThemeData theme, List<String> digits) {
    return Row(
      children:
          digits.map((d) => Expanded(child: _buildKey(theme, d))).toList(),
    );
  }

  Widget _buildKey(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          onTap: () => _onDigit(label),
          child: Container(
            height: 64,
            alignment: Alignment.center,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspace(ThemeData theme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            onTap: _onDelete,
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
}
