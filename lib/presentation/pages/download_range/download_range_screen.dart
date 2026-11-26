import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/kuron_slider_fling.dart';

enum _RangeField { start, end }

/// Dedicated full-screen page for selecting a download page range without
/// opening an `AlertDialog` or invoking the Android soft keyboard.
///
/// Pops with `(int start, int end)` when confirmed, or `null` when cancelled.
class DownloadRangeScreen extends StatefulWidget {
  const DownloadRangeScreen({
    super.key,
    required this.totalPages,
    required this.contentTitle,
    this.scopeTitle,
    this.scopeDescription,
  });

  final int totalPages;
  final String contentTitle;
  final String? scopeTitle;
  final String? scopeDescription;

  @override
  State<DownloadRangeScreen> createState() => _DownloadRangeScreenState();
}

class _DownloadRangeScreenState extends State<DownloadRangeScreen> {
  static const int _maxSliderDivisions = 200;

  late int _startPage;
  late int _endPage;
  _RangeField _activeField = _RangeField.end;
  bool _replaceOnNextDigit = true;
  String _buffer = '';

  int get _maxPages => math.max(1, widget.totalPages);

  int? get _sliderDivisions {
    if (_maxPages <= 1) return null;
    return _maxPages > _maxSliderDivisions
        ? _maxSliderDivisions
        : _maxPages - 1;
  }

  @override
  void initState() {
    super.initState();
    _startPage = 1;
    _endPage = _maxPages;
    _buffer = _endPage.toString();
  }

  void _selectField(_RangeField field) {
    if (_activeField == field && !_replaceOnNextDigit) return;
    setState(() {
      _commitBuffer();
      _activeField = field;
      _replaceOnNextDigit = true;
      _buffer = (field == _RangeField.start ? _startPage : _endPage).toString();
    });
  }

  void _commitBuffer() {
    final parsed = int.tryParse(_buffer);
    if (parsed == null) return;
    if (_activeField == _RangeField.start) {
      _startPage = parsed.clamp(1, _endPage);
    } else {
      _endPage = parsed.clamp(_startPage, _maxPages);
    }
  }

  void _onDigit(int digit) {
    setState(() {
      if (_replaceOnNextDigit) {
        _buffer = digit == 0 ? '1' : digit.toString();
        _replaceOnNextDigit = false;
      } else {
        if (_buffer.length >= 6) return;
        _buffer = _buffer == '0' ? digit.toString() : '$_buffer$digit';
      }
      final parsed = int.tryParse(_buffer);
      if (parsed == null || parsed <= 0) return;
      if (_activeField == _RangeField.start) {
        if (parsed <= _endPage) {
          _startPage = parsed.clamp(1, _maxPages);
        } else if (parsed <= _maxPages) {
          _startPage = parsed;
          _endPage = parsed;
        }
      } else {
        if (parsed >= _startPage && parsed <= _maxPages) {
          _endPage = parsed;
        } else if (parsed > _maxPages) {
          _endPage = _maxPages;
          _buffer = _maxPages.toString();
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (_replaceOnNextDigit) {
        _buffer = '';
        _replaceOnNextDigit = false;
        return;
      }
      if (_buffer.isNotEmpty) {
        _buffer = _buffer.substring(0, _buffer.length - 1);
      }
      final parsed = int.tryParse(_buffer);
      if (parsed != null && parsed >= 1) {
        if (_activeField == _RangeField.start && parsed <= _endPage) {
          _startPage = parsed;
        } else if (_activeField == _RangeField.end &&
            parsed >= _startPage &&
            parsed <= _maxPages) {
          _endPage = parsed;
        }
      }
    });
  }

  void _onClear() {
    setState(() {
      _buffer = '';
      _replaceOnNextDigit = false;
    });
  }

  void _applyRange(int start, int end) {
    final s = start.clamp(1, _maxPages);
    final e = end.clamp(s, _maxPages);
    setState(() {
      _startPage = s;
      _endPage = e;
      _replaceOnNextDigit = true;
      _buffer = (_activeField == _RangeField.start ? s : e).toString();
    });
  }

  void _confirm() {
    _commitBuffer();
    final s = _startPage.clamp(1, _maxPages);
    final e = _endPage.clamp(s, _maxPages);
    Navigator.of(context).pop((s, e));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selectedCount = (_endPage - _startPage + 1).clamp(1, _maxPages);
    final pct = ((selectedCount / _maxPages) * 100).toStringAsFixed(1);

    final startDisplay =
        _activeField == _RangeField.start && !_replaceOnNextDigit
        ? (_buffer.isEmpty ? '—' : _buffer)
        : _startPage.toString();
    final endDisplay = _activeField == _RangeField.end && !_replaceOnNextDigit
        ? (_buffer.isEmpty ? '—' : _buffer)
        : _endPage.toString();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.selectDownloadRange,
          style: TextStyleConst.headingMedium.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Content info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        border: Border.all(color: colorScheme.outline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.content}: ${widget.contentTitle}',
                            style: TextStyleConst.bodyMedium.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.totalPages}: $_maxPages',
                            style: TextStyleConst.bodySmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if ((widget.scopeTitle ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.scopeTitle!,
                              style: TextStyleConst.bodySmall.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if ((widget.scopeDescription ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.scopeDescription!,
                              style: TextStyleConst.bodySmall.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Selection summary
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              l10n.selectedPagesTo(_startPage, _endPage),
                              style: TextStyleConst.headingSmall.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          Text(
                            l10n.pagesPercentage(selectedCount, pct),
                            style: TextStyleConst.bodySmall.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Range slider
                    RepaintBoundary(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor: colorScheme.onSurface.withValues(
                            alpha: 0.35,
                          ),
                          thumbColor: colorScheme.primary,
                          overlayColor: colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                          valueIndicatorColor: colorScheme.primary,
                          valueIndicatorTextStyle: TextStyleConst.bodySmall
                              .copyWith(color: colorScheme.onPrimary),
                        ),
                        child: RangeSlider(
                          values: RangeValues(
                            _startPage.toDouble(),
                            _endPage.toDouble(),
                          ),
                          min: 1,
                          max: _maxPages.toDouble(),
                          divisions: _sliderDivisions,
                          labels: RangeLabels(
                            _startPage.toString(),
                            _endPage.toString(),
                          ),
                          onChanged: (values) => _applyRange(
                            values.start.round(),
                            values.end.round(),
                          ),
                        ).withKuronSliderFx(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Tap-to-focus Start & End boxes (no system keyboard)
                    Row(
                      children: [
                        Expanded(
                          child: _RangeFieldBox(
                            label: l10n.startPage,
                            value: startDisplay,
                            active: _activeField == _RangeField.start,
                            onTap: () => _selectField(_RangeField.start),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RangeFieldBox(
                            label: l10n.endPage,
                            value: endDisplay,
                            active: _activeField == _RangeField.end,
                            onTap: () => _selectField(_RangeField.end),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick selection chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildQuickChip(l10n.allPages, 1, _maxPages),
                        _buildQuickChip(
                          l10n.firstHalf,
                          1,
                          (_maxPages / 2).round(),
                        ),
                        _buildQuickChip(
                          l10n.secondHalf,
                          (_maxPages / 2).round() + 1,
                          _maxPages,
                        ),
                        _buildQuickChip(
                          l10n.first10,
                          1,
                          _maxPages >= 10 ? 10 : _maxPages,
                        ),
                        _buildQuickChip(
                          l10n.last10,
                          _maxPages >= 10 ? _maxPages - 9 : 1,
                          _maxPages,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // In-app numpad + action buttons (zero Android IME overhead)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NumpadGrid(
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    onClear: _onClear,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          key: const ValueKey('download-range-confirm'),
                          onPressed: _confirm,
                          icon: const Icon(Icons.download),
                          label: Text(l10n.downloadRange),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, int start, int end) {
    final s = start.clamp(1, _maxPages);
    final e = end.clamp(s, _maxPages);
    final selected = _startPage == s && _endPage == e;
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _applyRange(s, e),
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primary.withValues(alpha: 0.2),
      side: BorderSide(
        color: selected ? colorScheme.primary : colorScheme.outline,
      ),
    );
  }
}

class _RangeFieldBox extends StatelessWidget {
  const _RangeFieldBox({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outline,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyleConst.bodySmall.copyWith(
                color: active
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyleConst.headingMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumpadGrid extends StatelessWidget {
  const _NumpadGrid({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final rows = <List<_PadKey>>[
      [_PadKey.digit(1), _PadKey.digit(2), _PadKey.digit(3)],
      [_PadKey.digit(4), _PadKey.digit(5), _PadKey.digit(6)],
      [_PadKey.digit(7), _PadKey.digit(8), _PadKey.digit(9)],
      [
        _PadKey.action('C', onClear),
        _PadKey.digit(0),
        _PadKey.icon(Icons.backspace_outlined, onBackspace),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var c = 0; c < rows[r].length; c++) ...[
                if (c > 0) const SizedBox(width: 6),
                Expanded(child: _buildButton(context, rows[r][c])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildButton(BuildContext context, _PadKey key) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Material(
        color: key.isAction
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: InkWell(
          key: key.digit != null ? ValueKey('numpad-${key.digit}') : null,
          onTap: key.digit != null ? () => onDigit(key.digit!) : key.onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          child: Center(
            child: key.iconData != null
                ? Icon(key.iconData, size: 20, color: colorScheme.onSurface)
                : Text(
                    key.label!,
                    style: TextStyleConst.headingSmall.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PadKey {
  const _PadKey._({
    this.digit,
    this.label,
    this.iconData,
    this.onTap,
    this.isAction = false,
  });

  factory _PadKey.digit(int d) => _PadKey._(digit: d, label: d.toString());
  factory _PadKey.action(String label, VoidCallback onTap) =>
      _PadKey._(label: label, onTap: onTap, isAction: true);
  factory _PadKey.icon(IconData icon, VoidCallback onTap) =>
      _PadKey._(iconData: icon, onTap: onTap, isAction: true);

  final int? digit;
  final String? label;
  final IconData? iconData;
  final VoidCallback? onTap;
  final bool isAction;
}
