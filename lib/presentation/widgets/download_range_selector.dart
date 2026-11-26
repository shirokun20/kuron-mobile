import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';

import '../../l10n/app_localizations.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

import 'kuron_slider_fling.dart';

// Widget for selecting download range (page X to page Y)
// Allows users to download partial content instead of all pages
class DownloadRangeSelector extends StatefulWidget {
  final int totalPages;
  final Function(int startPage, int endPage) onRangeSelected;
  final String contentTitle;
  final String? scopeTitle;
  final String? scopeDescription;

  const DownloadRangeSelector({
    super.key,
    required this.totalPages,
    required this.onRangeSelected,
    required this.contentTitle,
    this.scopeTitle,
    this.scopeDescription,
  });

  @override
  State<DownloadRangeSelector> createState() => _DownloadRangeSelectorState();
}

class _DownloadRangeSelectorState extends State<DownloadRangeSelector> {
  late int startPage;
  late int endPage;
  late RangeValues _currentRangeValues;

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  /// Coarse scrub granularity for the slider. Precision comes from the
  /// manual fields, so there is no need for one division per page.
  static const int _maxSliderDivisions = 200;

  /// Idle delay before keystrokes in the manual fields sync to the slider.
  /// Keystrokes keep echoing via the controllers without rebuilding the
  /// slider on every character.
  static const Duration _textSyncDebounce = Duration(milliseconds: 400);

  Timer? _textSyncTimer;

  @override
  void initState() {
    super.initState();
    startPage = 1;
    endPage = widget.totalPages;
    _currentRangeValues = RangeValues(1, widget.totalPages.toDouble());
    _updateControllers();
  }

  @override
  void dispose() {
    _textSyncTimer?.cancel();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _updateControllers() {
    _startController.text = startPage.toString();
    _endController.text = endPage.toString();
  }

  void _updateFromSlider() {
    setState(() {
      startPage = _currentRangeValues.start.round();
      endPage = _currentRangeValues.end.round();
      _updateControllers();
    });
  }

  void _updateFromTextFields() {
    final start = int.tryParse(_startController.text);
    final end = int.tryParse(_endController.text);

    if (start != null &&
        end != null &&
        start >= 1 &&
        end <= widget.totalPages &&
        start <= end) {
      setState(() {
        startPage = start;
        endPage = end;
        _currentRangeValues = RangeValues(start.toDouble(), end.toDouble());
      });
    }
  }

  /// Slider tick marks cost O(divisions) paint per frame. Galleries with
  /// hundreds–thousands of pages (e.g. ehentai) jank on every rebuild
  /// during the keyboard-show resize animation, so cap the divisions.
  int? get _sliderDivisions {
    if (widget.totalPages <= 1) return null;
    return widget.totalPages > _maxSliderDivisions
        ? _maxSliderDivisions
        : widget.totalPages - 1;
  }

  void _scheduleTextSync() {
    _textSyncTimer?.cancel();
    _textSyncTimer = Timer(_textSyncDebounce, _updateFromTextFields);
  }

  void _applyTextSyncNow() {
    _textSyncTimer?.cancel();
    _updateFromTextFields();
  }

  int get selectedPageCount => endPage - startPage + 1;
  double get selectionPercentage =>
      (selectedPageCount / widget.totalPages) * 100;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      title: Text(
        AppLocalizations.of(context)!.selectDownloadRange,
        style: TextStyleConst.headingLarge.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppLocalizations.of(context)!.content}: ${widget.contentTitle}',
                    style: TextStyleConst.bodyLarge.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${AppLocalizations.of(context)!.totalPages}: ${widget.totalPages}',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  if ((widget.scopeTitle ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.scopeTitle!,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if ((widget.scopeDescription ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
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
            const SizedBox(height: 20),

            // Selection summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    AppLocalizations.of(context)!
                        .selectedPagesTo(startPage, endPage),
                    style: TextStyleConst.headingSmall.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)!.pagesPercentage(
                      selectedPageCount,
                      selectionPercentage.toStringAsFixed(1),
                    ),
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Range slider
            Text(
              AppLocalizations.of(context)!.useSliderToSelectRange,
              style: TextStyleConst.bodyLarge.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.onSurface.withValues(
                  alpha: 0.4,
                ),
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                valueIndicatorColor: colorScheme.primary,
                valueIndicatorTextStyle: TextStyleConst.bodySmall.copyWith(
                  color: colorScheme.onPrimary,
                ),
              ),
              child: RangeSlider(
                values: _currentRangeValues,
                min: 1,
                max: widget.totalPages.toDouble(),
                divisions: _sliderDivisions,
                labels: RangeLabels(startPage.toString(), endPage.toString()),
                onChanged: (values) {
                  setState(() {
                    _currentRangeValues = values;
                  });
                  _updateFromSlider();
                },
              ).withKuronSliderFx(),
            ),
            const SizedBox(height: 20),

            // Manual input fields
            Text(
              AppLocalizations.of(context)!.orEnterManually,
              style: TextStyleConst.bodyLarge.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.startPage,
                      labelStyle: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (_) => _scheduleTextSync(),
                    onSubmitted: (_) => _applyTextSyncNow(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.endPage,
                      labelStyle: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (_) => _scheduleTextSync(),
                    onSubmitted: (_) => _applyTextSyncNow(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick selection buttons
            Text(
              AppLocalizations.of(context)!.quickSelections,
              style: TextStyleConst.bodyLarge.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickSelectChip(
                  AppLocalizations.of(context)!.allPages,
                  1,
                  widget.totalPages,
                  context,
                ),
                _buildQuickSelectChip(
                  AppLocalizations.of(context)!.firstHalf,
                  1,
                  (widget.totalPages / 2).round(),
                  context,
                ),
                _buildQuickSelectChip(
                  AppLocalizations.of(context)!.secondHalf,
                  (widget.totalPages / 2).round() + 1,
                  widget.totalPages,
                  context,
                ),
                _buildQuickSelectChip(
                  AppLocalizations.of(context)!.first10,
                  1,
                  (widget.totalPages >= 10) ? 10 : widget.totalPages,
                  context,
                ),
                _buildQuickSelectChip(
                  AppLocalizations.of(context)!.last10,
                  (widget.totalPages >= 10) ? widget.totalPages - 9 : 1,
                  widget.totalPages,
                  context,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            AppLocalizations.of(context)!.cancel,
            style: TextStyleConst.bodyMedium.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            widget.onRangeSelected(startPage, endPage);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.download),
          label: Text(AppLocalizations.of(context)!.downloadRange),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickSelectChip(
    String label,
    int start,
    int end,
    BuildContext context,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = startPage == start && endPage == end;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          startPage = start;
          endPage = end;
          _currentRangeValues = RangeValues(start.toDouble(), end.toDouble());
          _updateControllers();
        });
      },
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primary.withValues(alpha: 0.2),
      labelStyle: isSelected
          ? TextStyleConst.headingSmall.copyWith(color: colorScheme.primary)
          : TextStyleConst.bodySmall.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
    );
  }
}
