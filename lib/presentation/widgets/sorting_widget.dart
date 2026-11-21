import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/domain/entities/entities.dart';

// Modern sorting widget for MainScreen
class SortingWidget extends StatelessWidget {
  const SortingWidget({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
    this.isCompact = false,
  });

  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompactSorting(context);
    } else {
      return _buildFullSorting(context);
    }
  }

  // Build compact sorting for smaller spaces
  Widget _buildCompactSorting(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            currentSort.displayName,
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  // Build full sorting with all options visible
  Widget _buildFullSorting(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.sort,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)!.sortBy,
                style: TextStyleConst.headingMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SortOption.values.map((sort) {
                final isSelected = currentSort == sort;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(sort.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        onSortChanged(sort);
                      }
                    },
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh,
                    selectedColor: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.2),
                    labelStyle: isSelected
                        ? TextStyleConst.headingSmall.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : TextStyleConst.bodySmall.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    side: BorderSide(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline
                                .withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    elevation: isSelected ? 2 : 0,
                    pressElevation: 4,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Dropdown version of sorting widget for compact spaces
class SortingDropdown extends StatelessWidget {
  const SortingDropdown({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortOption>(
      initialValue: currentSort,
      onSelected: onSortChanged,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              currentSort.displayName,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => SortOption.values.map((sort) {
        final isSelected = currentSort == sort;
        return PopupMenuItem<SortOption>(
          value: sort,
          child: Row(
            children: [
              if (isSelected)
                Icon(
                  Icons.check,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sort.displayName,
                  style: isSelected
                      ? TextStyleConst.headingSmall.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : TextStyleConst.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
