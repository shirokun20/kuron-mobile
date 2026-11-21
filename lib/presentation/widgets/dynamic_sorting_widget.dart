import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// A dynamic sorting widget that adapts based on [SortingConfig].
///
// Supports:
// - [SortWidgetType.dropdown]: Interactive dropdown for immediate re-sorting (nhentai style)
// - [SortWidgetType.readonly]: Read-only display of current sort (crotpedia style)
// - [SortWidgetType.chips]: Interactive chips (alternative style)
class DynamicSortingWidget extends StatelessWidget {
  final String currentSortValue;
  final SortingConfig config;
  final Function(String)? onSortChanged;
  final VoidCallback? onNavigateToSearch;

  // Optional info text to display
  final String? infoText;

  // Number of results (optional)
  final int? resultCount;

  // Whether to use full width layout
  final bool fullWidth;

  const DynamicSortingWidget({
    super.key,
    required this.currentSortValue,
    required this.config,
    this.onSortChanged,
    this.onNavigateToSearch,
    this.infoText,
    this.resultCount,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    if (config.options.isEmpty || !config.allowDynamicReSort) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: fullWidth ? double.infinity : null,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with info and sort button
          Row(
            children: [
              // Info section (left side)
              Expanded(child: _buildInfoSection(context, colorScheme)),

              // Sort button (right side)
              _buildSortButton(context, colorScheme, isDark),
            ],
          ),

          // Additional info text if provided
          if (infoText != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      infoText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Chips mode: show all options below
          if (config.widgetType == SortWidgetType.chips) ...[
            const SizedBox(height: 12),
            _buildChips(context, colorScheme, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title with icon
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.sort_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.messages.dropdownLabel ??
                      AppLocalizations.of(context)!.sortBy,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (resultCount != null)
                  Text(
                    '$resultCount results',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSortButton(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final currentOption = _getCurrentOption();

    if (config.widgetType == SortWidgetType.readonly) {
      return _buildReadonlyButton(context, colorScheme, currentOption);
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value != currentSortValue) {
          onSortChanged?.call(value);
        }
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      elevation: 8,
      itemBuilder: (context) => config.options.map((option) {
        final isSelected = option.value == currentSortValue;
        return PopupMenuItem<String>(
          value: option.value,
          height: 52,
          child: Row(
            children: [
              // Icon with background
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getIconData(option.icon ?? 'sort'),
                  size: 18,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              // Label
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
              // Check mark
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIconData(currentOption.icon ?? 'sort'),
              size: 18,
              color: colorScheme.onPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              currentOption.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: colorScheme.onPrimary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadonlyButton(
    BuildContext context,
    ColorScheme colorScheme,
    SortOptionConfig option,
  ) {
    return InkWell(
      onTap: onNavigateToSearch,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIconData(option.icon ?? 'sort'),
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (onNavigateToSearch != null) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChips(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: config.options.map((option) {
          final isSelected = option.value == currentSortValue;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSortChanged?.call(option.value),
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                child: AnimatedContainer(
                  duration: DesignTokens.durationPageTurn,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.2),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (option.icon != null) ...[
                        Icon(
                          _getIconData(option.icon!),
                          size: 16,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  SortOptionConfig _getCurrentOption() {
    return config.options.firstWhere(
      (opt) => opt.value == currentSortValue,
      orElse: () => config.options.firstWhere(
        (o) => o.isDefault,
        orElse: () => config.options.first,
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'update':
        return Icons.update_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'date_range':
        return Icons.date_range_rounded;
      case 'today':
        return Icons.today_rounded;
      case 'new_releases':
        return Icons.new_releases_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'sort_by_alpha':
        return Icons.sort_by_alpha_rounded;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'whatshot':
        return Icons.whatshot_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'access_time':
        return Icons.access_time_rounded;
      case 'local_fire_department':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.sort_rounded;
    }
  }
}
