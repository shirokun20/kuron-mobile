import 'package:flutter/material.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({
    required this.title,
    this.subtitle,
    this.showBiometric = false,
    required this.onPinEntered,
    this.onBiometricTap,
    this.maxDigits = 6,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool showBiometric;
  final Future<bool> Function(String pin) onPinEntered;
  final Future<void> Function()? onBiometricTap;
  final int maxDigits;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _pin = StringBuffer();
  String? _error;
  bool _isLoading = false;

  void _onDigit(String digit) {
    if (_isLoading) return;
    if (_pin.length >= widget.maxDigits) return;
    setState(() {
      _pin.write(digit);
      _error = null;
    });
    if (_pin.length == widget.maxDigits) {
      _submit();
    }
  }

  void _onDelete() {
    if (_isLoading) return;
    if (_pin.isEmpty) return;
    setState(() {
      final current = _pin.toString();
      _pin.clear();
      _pin.write(current.substring(0, current.length - 1));
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    final correct = await widget.onPinEntered(_pin.toString());
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (correct) {
        _pin.clear();
      } else {
        _error = AppLocalizations.of(context)!.wrongPin;
        _pin.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Text(
              widget.title,
              style: TextStyleConst.headingMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                style: TextStyleConst.bodyMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.maxDigits, (i) {
                final filled = i < _pin.length;
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
                      if (widget.showBiometric)
                        Expanded(child: _buildBiometricButton(theme))
                      else
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
              child: Icon(
                Icons.backspace_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          onTap: () async {
            if (widget.onBiometricTap != null) {
              await widget.onBiometricTap!();
            }
          },
          child: Container(
            height: 64,
            alignment: Alignment.center,
            child: Icon(
              Icons.fingerprint,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
