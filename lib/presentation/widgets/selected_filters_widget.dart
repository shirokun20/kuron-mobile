import 'package:material_ui/material_ui.dart';

import '../../core/constants/text_style_const.dart';
import '../../domain/entities/entities.dart';

import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Horizontal scrollable widget for displaying selected filters
class SelectedFiltersWidget extends StatelessWidget {
  const SelectedFiltersWidget({
    super.key,
    required this.selectedFilters,
    required this.onRemove,
    this.height = 60,
  });

  final List<FilterItem> selectedFilters;
  final ValueChanged<String> onRemove;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (selectedFilters.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: selectedFilters.length,
        itemBuilder: (context, index) {
          final filter = selectedFilters[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SelectedFilterChip(
              filterItem: filter,
              onRemove: () => onRemove(filter.value),
            ),
          );
        },
      ),
    );
  }
}

// Individual chip for selected filter item
class SelectedFilterChip extends StatelessWidget {
  const SelectedFilterChip({
    super.key,
    required this.filterItem,
    required this.onRemove,
  });

  final FilterItem filterItem;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isExclude = filterItem.isExcluded;
    final colors = _selectedFilterColors(
      isExclude: isExclude,
      context: context,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
        border: Border.all(color: colors.accent),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Icon(
              isExclude ? Icons.remove_rounded : Icons.add_rounded,
              size: 14,
              color: colors.accent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Text(
              filterItem.tagName ?? filterItem.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.foreground,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, left: 2),
              child: Icon(Icons.close_rounded, size: 14, color: colors.accent),
            ),
          ),
        ],
      ),
    );
  }

  _SelectedFilterColors _selectedFilterColors({
    required bool isExclude,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isExclude
        ? (isDark ? AppColors.error : AppColors.error)
        : (isDark ? AppColors.success : AppColors.success);
    final foreground = isExclude
        ? (isDark ? AppColors.error.withValues(alpha: 0.8) : AppColors.error)
        : (isDark
              ? AppColors.success.withValues(alpha: 0.8)
              : AppColors.success);

    return _SelectedFilterColors(
      accent: accent,
      foreground: foreground,
      background: accent.withValues(alpha: isDark ? 0.20 : 0.14),
    );
  }
}

// Compact version for smaller spaces
class SelectedFiltersWidgetCompact extends StatelessWidget {
  const SelectedFiltersWidgetCompact({
    super.key,
    required this.selectedFilters,
    required this.onRemove,
    this.maxVisible = 3,
  });

  final List<FilterItem> selectedFilters;
  final ValueChanged<String> onRemove;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (selectedFilters.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleFilters = selectedFilters.take(maxVisible).toList();
    final remainingCount = selectedFilters.length - maxVisible;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...visibleFilters.map(
          (filter) => SelectedFilterChipCompact(
            filterItem: filter,
            onRemove: () => onRemove(filter.value),
          ),
        ),
        if (remainingCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            ),
            child: Text(
              AppLocalizations.of(context)!.nMoreFilters(remainingCount),
              style: TextStyleConst.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

// Compact chip for selected filter item
class SelectedFilterChipCompact extends StatelessWidget {
  const SelectedFilterChipCompact({
    super.key,
    required this.filterItem,
    required this.onRemove,
  });

  final FilterItem filterItem;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _getChipColor(context),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: _getBorderColor(context), width: 1),
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Prefix icon
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                filterItem.isExcluded ? Icons.remove : Icons.add,
                size: 12,
                color: _getIconColor(context),
              ),
            ),

            // Filter text
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  filterItem.tagName ?? filterItem.value,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: _getTextColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Remove button
            GestureDetector(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: _getIconColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getChipColor(BuildContext context) {
    return _selectedFilterColors(
      isExclude: filterItem.isExcluded,
      context: context,
    ).background;
  }

  Color _getBorderColor(BuildContext context) {
    return _selectedFilterColors(
      isExclude: filterItem.isExcluded,
      context: context,
    ).accent.withValues(alpha: 0.62);
  }

  Color _getIconColor(BuildContext context) {
    return _selectedFilterColors(
      isExclude: filterItem.isExcluded,
      context: context,
    ).accent;
  }

  Color _getTextColor(BuildContext context) {
    return _selectedFilterColors(
      isExclude: filterItem.isExcluded,
      context: context,
    ).foreground;
  }
}

_SelectedFilterColors _selectedFilterColors({
  required bool isExclude,
  required BuildContext context,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = isExclude
      ? (isDark ? AppColors.error : AppColors.error)
      : (isDark ? AppColors.success : AppColors.success);
  final foreground = isExclude
      ? (isDark ? AppColors.error.withValues(alpha: 0.8) : AppColors.error)
      : (isDark ? AppColors.success.withValues(alpha: 0.8) : AppColors.success);

  return _SelectedFilterColors(
    accent: accent,
    foreground: foreground,
    background: accent.withValues(alpha: isDark ? 0.20 : 0.14),
  );
}

class _SelectedFilterColors {
  const _SelectedFilterColors({
    required this.accent,
    required this.foreground,
    required this.background,
  });

  final Color accent;
  final Color foreground;
  final Color background;
}
