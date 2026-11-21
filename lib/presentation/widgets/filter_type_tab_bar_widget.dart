import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

import '../../core/constants/text_style_const.dart';
import '../../domain/entities/entities.dart';

// Tab bar for switching between different filter types
class FilterTypeTabBar extends StatelessWidget {
  const FilterTypeTabBar({
    super.key,
    required this.controller,
    required this.filterTypes,
    required this.onTabChanged,
  });

  final TabController controller;
  final List<String> filterTypes;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: colorScheme.primary,
        indicatorWeight: 3,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.7),
        labelStyle: TextStyleConst.labelMedium.copyWith(
          color: colorScheme.primary,
        ),
        unselectedLabelStyle: TextStyleConst.label.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tabs: filterTypes
            .map((type) => Tab(text: TagType.getDisplayName(type)))
            .toList(),
      ),
    );
  }
}

// Modern tab bar with custom styling
class FilterTypeTabBarModern extends StatelessWidget {
  const FilterTypeTabBarModern({
    super.key,
    required this.controller,
    required this.filterTypes,
    required this.onTabChanged,
  });

  final TabController controller;
  final List<String> filterTypes;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filterTypes.length,
        itemBuilder: (context, index) {
          final type = filterTypes[index];
          final isSelected = controller.index == index;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterTypeTab(
              text: TagType.getDisplayName(type),
              isSelected: isSelected,
              onTap: () {
                controller.animateTo(index);
                onTabChanged(index);
              },
            ),
          );
        },
      ),
    );
  }
}

// Individual tab for filter type
class FilterTypeTab extends StatelessWidget {
  const FilterTypeTab({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.durationPageTurn,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: isSelected
                ? TextStyleConst.labelMedium.copyWith(
                    color: colorScheme.onPrimary,
                  )
                : TextStyleConst.label.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
          ),
        ),
      ),
    );
  }
}

// Segmented control style tab bar
class FilterTypeSegmentedControl extends StatelessWidget {
  const FilterTypeSegmentedControl({
    super.key,
    required this.selectedIndex,
    required this.filterTypes,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<String> filterTypes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Row(
        children: filterTypes.asMap().entries.map((entry) {
          final index = entry.key;
          final type = entry.value;
          final isSelected = selectedIndex == index;
          final isFirst = index == 0;
          final isLast = index == filterTypes.length - 1;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: DesignTokens.durationPageTurn,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: isFirst ? const Radius.circular(12) : Radius.zero,
                    right: isLast ? const Radius.circular(12) : Radius.zero,
                  ),
                ),
                child: Center(
                  child: Text(
                    TagType.getDisplayName(type),
                    style: isSelected
                        ? TextStyleConst.labelMedium.copyWith(
                            color: colorScheme.onPrimary,
                          )
                        : TextStyleConst.label.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Chip-style tab bar
class FilterTypeChipBar extends StatelessWidget {
  const FilterTypeChipBar({
    super.key,
    required this.selectedIndex,
    required this.filterTypes,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<String> filterTypes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filterTypes.length,
        itemBuilder: (context, index) {
          final type = filterTypes[index];
          final isSelected = selectedIndex == index;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(TagType.getDisplayName(type)),
              selected: isSelected,
              onSelected: (selected) => onChanged(index),
              selectedColor: colorScheme.primary.withValues(alpha: 0.2),
              checkmarkColor: colorScheme.primary,
              labelStyle: isSelected
                  ? TextStyleConst.labelMedium.copyWith(
                      color: colorScheme.primary,
                    )
                  : TextStyleConst.label.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              side: BorderSide(
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
            ),
          );
        },
      ),
    );
  }
}
