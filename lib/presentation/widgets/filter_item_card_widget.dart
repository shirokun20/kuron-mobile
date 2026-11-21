import 'package:material_ui/material_ui.dart';

import '../../core/constants/text_style_const.dart';
import '../../domain/entities/entities.dart';
import '../../l10n/app_localizations.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

// Modern card widget for filter items with include/exclude toggle
class FilterItemCard extends StatelessWidget {
  const FilterItemCard({
    super.key,
    required this.tag,
    required this.isIncluded,
    required this.isExcluded,
    required this.onTap,
    required this.onInclude,
    required this.onExclude,
    this.supportsExclude = true,
  });

  final Tag tag;
  final bool isIncluded;
  final bool isExcluded;
  final VoidCallback onTap;
  final VoidCallback onInclude;
  final VoidCallback onExclude;
  final bool supportsExclude;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: DesignTokens.elevationNone,
      color: _getCardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(
          color: _getBorderColor(context),
          width: _getBorderWidth(),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Tag info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Tag type indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getTagTypeColor(context)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            TagType.getDisplayName(tag.type),
                            style: TextStyleConst.label.copyWith(
                              color: _getTagTypeColor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Popularity indicator
                        if (tag.isPopular) ...[
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Tag name
                    Text(
                      tag.name,
                      style: TextStyleConst.contentTitle.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Tag count
                    Text(
                      AppLocalizations.of(context)!.nItems(tag.count),
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              // Action buttons
              const SizedBox(width: 16),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Builder(
      builder: (context) {
        if (isIncluded || isExcluded) {
          // Show selected state with remove option
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isIncluded
                      ? Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.error
                            .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIncluded ? Icons.add : Icons.remove,
                      size: 16,
                      color: isIncluded
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isIncluded
                          ? AppLocalizations.of(context)!.includeFilter
                          : AppLocalizations.of(context)!.excludeFilter,
                      style: TextStyleConst.label.copyWith(
                        color: isIncluded
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Remove button
              IconButton(
                onPressed: onTap, // Tap to remove/toggle
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.7),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          );
        } else {
          // Show include/exclude options
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Include button
              IconButton(
                onPressed: onInclude,
                icon: Icon(
                  Icons.add,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              if (supportsExclude) ...[
                const SizedBox(width: 8),
                // Exclude button
                IconButton(
                  onPressed: onExclude,
                  icon: Icon(
                    Icons.remove,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error
                        .withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Color _getCardColor(BuildContext context) {
    if (isIncluded) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.05);
    } else if (isExcluded) {
      return Theme.of(context).colorScheme.error.withValues(alpha: 0.05);
    }
    return Theme.of(context).colorScheme.surface;
  }

  Color _getBorderColor(BuildContext context) {
    if (isIncluded) {
      return Theme.of(context).colorScheme.primary;
    } else if (isExcluded) {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.outline;
  }

  double _getBorderWidth() {
    return (isIncluded || isExcluded) ? 2 : 1;
  }

  Color _getTagTypeColor(BuildContext context) {
    // Use theme-adaptive colors that work in both light and dark modes
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (tag.type.toLowerCase()) {
      case 'artist':
        return isDark
            ? const Color(0xFFFF6B6B)
            : const Color(0xFFE53E3E); // Red
      case 'character':
        return isDark
            ? const Color(0xFF4ECDC4)
            : const Color(0xFF319795); // Teal
      case 'parody':
        return isDark
            ? const Color(0xFF45B7D1)
            : const Color(0xFF3182CE); // Blue
      case 'group':
        return isDark
            ? const Color(0xFF96CEB4)
            : const Color(0xFF38A169); // Green
      case 'language':
        return isDark
            ? const Color(0xFFFFA726)
            : const Color(0xFFD69E2E); // Orange
      case 'category':
        return isDark
            ? const Color(0xFFBA68C8)
            : const Color(0xFF9F7AEA); // Purple
      default:
        return Theme.of(context).colorScheme.primary; // Default theme primary
    }
  }
}

// Compact version of filter item card for smaller spaces
class FilterItemCardCompact extends StatelessWidget {
  const FilterItemCardCompact({
    super.key,
    required this.tag,
    required this.isIncluded,
    required this.isExcluded,
    required this.onTap,
    required this.onInclude,
    required this.onExclude,
  });

  final Tag tag;
  final bool isIncluded;
  final bool isExcluded;
  final VoidCallback onTap;
  final VoidCallback onInclude;
  final VoidCallback onExclude;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: DesignTokens.elevationNone,
      color: _getCardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        side: BorderSide(
          color: _getBorderColor(context),
          width: _getBorderWidth(),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Tag info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tag.count}',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Action button
              const SizedBox(width: 8),
              _buildActionButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (isIncluded || isExcluded) {
      return Icon(
        isIncluded ? Icons.add_circle : Icons.remove_circle,
        color: isIncluded
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        size: 24,
      );
    } else {
      return Icon(
        Icons.add_circle_outline,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 24,
      );
    }
  }

  Color _getCardColor(BuildContext context) {
    if (isIncluded) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.05);
    } else if (isExcluded) {
      return Theme.of(context).colorScheme.error.withValues(alpha: 0.05);
    }
    return Theme.of(context).colorScheme.surface;
  }

  Color _getBorderColor(BuildContext context) {
    if (isIncluded) {
      return Theme.of(context).colorScheme.primary;
    } else if (isExcluded) {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.outline;
  }

  double _getBorderWidth() {
    return (isIncluded || isExcluded) ? 2 : 1;
  }
}
