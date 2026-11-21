import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/domain/entities/search/dynamic_option.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/search/dynamic_form_search/dynamic_form_filter_parser.dart';

class TagChipColors {
  const TagChipColors({
    required this.accent,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color accent;
  final Color foreground;
  final Color background;
  final Color border;
}

enum TagPickState { include, exclude }

class CombinedPickerResult {
  const CombinedPickerResult({required this.included, required this.excluded});

  final List<DynamicOption> included;
  final List<DynamicOption> excluded;
}

IconData pickerLeadingIcon(String name, SearchFormFieldConfig field) {
  if (isIncludedTagField(name, field)) {
    return Icons.add_circle_outline;
  }
  if (isExcludedTagField(name, field)) {
    return Icons.remove_circle_outline;
  }
  return Icons.local_offer_outlined;
}

Color pickerAccentColor(
  String name,
  SearchFormFieldConfig field,
  BuildContext context,
) {
  final colorScheme = Theme.of(context).colorScheme;
  if (isIncludedTagField(name, field)) {
    return tagChipColors(TagPickState.include, context).accent;
  }
  if (isExcludedTagField(name, field)) {
    return tagChipColors(TagPickState.exclude, context).accent;
  }
  return colorScheme.primary;
}

Color onAccentColor(Color accentColor) {
  final brightness = ThemeData.estimateBrightnessForColor(accentColor);
  return brightness == Brightness.dark ? Colors.white : Colors.black;
}

TagChipColors tagChipColors(TagPickState state, BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final Color accent;
  final Color foreground;
  switch (state) {
    case TagPickState.include:
      accent = isDark ? AppColors.success : AppColors.success;
      foreground = isDark ? const Color(0xFFB9F6CA) : const Color(0xFF006C45);
    case TagPickState.exclude:
      accent = isDark ? AppColors.error : AppColors.error;
      foreground = isDark ? const Color(0xFFFFD6D6) : const Color(0xFF9F1D1D);
  }

  return TagChipColors(
    accent: accent,
    foreground: foreground,
    background: accent.withValues(alpha: isDark ? 0.18 : 0.14),
    border: accent.withValues(alpha: isDark ? 0.78 : 0.62),
  );
}

TagChipColors pickerSelectedColors(
  String name,
  SearchFormFieldConfig field,
  BuildContext context,
) {
  if (isIncludedTagField(name, field)) {
    return tagChipColors(TagPickState.include, context);
  }
  if (isExcludedTagField(name, field)) {
    return tagChipColors(TagPickState.exclude, context);
  }

  final accent = pickerAccentColor(name, field, context);
  return TagChipColors(
    accent: accent,
    foreground: accent,
    background: accent.withValues(alpha: 0.16),
    border: accent.withValues(alpha: 0.62),
  );
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

Future<CombinedPickerResult?> showDynamicFormCombinedPicker({
  required BuildContext context,
  required List<DynamicOption> options,
  required List<DynamicOption> initialIncluded,
  required List<DynamicOption> initialExcluded,
}) {
  final includeColors = tagChipColors(TagPickState.include, context);
  final excludeColors = tagChipColors(TagPickState.exclude, context);

  final selectedState = <String, TagPickState>{
    for (final o in initialIncluded) o.value: TagPickState.include,
    for (final o in initialExcluded) o.value: TagPickState.exclude,
  };

  var query = '';

  return showModalBottomSheet<CombinedPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = options.where((o) {
            if (query.isEmpty) return true;
            return o.label.toLowerCase().contains(query.toLowerCase());
          }).toList();

          final grouped = <String, List<DynamicOption>>{};
          for (final option in filtered) {
            final groupRaw = option.group?.trim();
            final key = (groupRaw == null || groupRaw.isEmpty)
                ? 'other'
                : groupRaw.toLowerCase();
            (grouped[key] ??= <DynamicOption>[]).add(option);
          }

          const groupOrder = <String>[
            'format',
            'genre',
            'theme',
            'content',
            'other',
          ];

          final groupKeys = grouped.keys.toList()
            ..sort((a, b) {
              final ia = groupOrder.indexOf(a);
              final ib = groupOrder.indexOf(b);
              final ra = ia == -1 ? groupOrder.length : ia;
              final rb = ib == -1 ? groupOrder.length : ib;
              if (ra != rb) return ra.compareTo(rb);
              return a.compareTo(b);
            });

          int includeCount = 0;
          int excludeCount = 0;
          for (final state in selectedState.values) {
            if (state == TagPickState.include) includeCount++;
            if (state == TagPickState.exclude) excludeCount++;
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusFull,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.filterTags,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: selectedState.isEmpty
                              ? null
                              : () => setSheetState(selectedState.clear),
                          child: Text(AppLocalizations.of(context)!.reset),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spaceXs),
                    Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: includeColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!
                              .includeCountLabel(includeCount),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.remove_circle_outline,
                          size: 16,
                          color: excludeColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!
                              .excludeCountLabel(excludeCount),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: AppLocalizations.of(context)!.searchTagsHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusLg,
                          ),
                        ),
                        filled: true,
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.noTagsFound,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              children: [
                                for (final groupKey in groupKeys) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      _capitalize(groupKey),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: grouped[groupKey]!.map((option) {
                                      final pickState =
                                          selectedState[option.value];
                                      final isInclude =
                                          pickState == TagPickState.include;
                                      final isExclude =
                                          pickState == TagPickState.exclude;
                                      final selectedColors = isInclude
                                          ? includeColors
                                          : isExclude
                                          ? excludeColors
                                          : null;
                                      final fallbackBorder = Theme.of(context)
                                          .colorScheme
                                          .outlineVariant;

                                      return FilterChip(
                                        showCheckmark: false,
                                        label: Text(option.label),
                                        selected: isInclude || isExclude,
                                        avatar: isInclude
                                            ? Icon(
                                                Icons.add,
                                                size: 14,
                                                color: includeColors.accent,
                                              )
                                            : isExclude
                                            ? Icon(
                                                Icons.remove,
                                                size: 14,
                                                color: excludeColors.accent,
                                              )
                                            : null,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        selectedColor:
                                            selectedColors?.background,
                                        side: BorderSide(
                                          color: (isInclude || isExclude)
                                              ? selectedColors!.border
                                              : fallbackBorder,
                                        ),
                                        checkmarkColor:
                                            selectedColors?.foreground,
                                        labelStyle: TextStyle(
                                          color: (isInclude || isExclude)
                                              ? selectedColors!.foreground
                                              : null,
                                          fontWeight: (isInclude || isExclude)
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                        onSelected: (_) {
                                          setSheetState(() {
                                            final current =
                                                selectedState[option.value];
                                            if (current == null) {
                                              selectedState[option.value] =
                                                  TagPickState.include;
                                            } else if (current ==
                                                TagPickState.include) {
                                              selectedState[option.value] =
                                                  TagPickState.exclude;
                                            } else {
                                              selectedState.remove(
                                                option.value,
                                              );
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: DesignTokens.spaceMd),
                                ],
                                const SizedBox(height: DesignTokens.spaceSm),
                              ],
                            ),
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          final include = options
                              .where(
                                (o) =>
                                    selectedState[o.value] ==
                                    TagPickState.include,
                              )
                              .toList();
                          final exclude = options
                              .where(
                                (o) =>
                                    selectedState[o.value] ==
                                    TagPickState.exclude,
                              )
                              .toList();
                          context.pop(
                            CombinedPickerResult(
                              included: include,
                              excluded: exclude,
                            ),
                          );
                        },
                        child: Text(
                          AppLocalizations.of(context)!
                              .applyWithCounts(includeCount, excludeCount),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

Future<List<DynamicOption>?> showDynamicFormMultiSelectPicker({
  required BuildContext context,
  required String title,
  required IconData leadingIcon,
  required TagChipColors colors,
  required List<DynamicOption> options,
  required List<DynamicOption> initialSelected,
}) {
  final accentColor = colors.accent;
  final selected = List<DynamicOption>.from(initialSelected);
  final selectedValues = selected.map((e) => e.value).toSet();
  var query = '';

  return showModalBottomSheet<List<DynamicOption>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = options.where((o) {
            if (query.isEmpty) return true;
            return o.label.toLowerCase().contains(query.toLowerCase());
          }).toList();

          final grouped = <String, List<DynamicOption>>{};
          for (final option in filtered) {
            final groupRaw = option.group?.trim();
            final key = (groupRaw == null || groupRaw.isEmpty)
                ? 'other'
                : groupRaw.toLowerCase();
            (grouped[key] ??= <DynamicOption>[]).add(option);
          }

          const groupOrder = <String>[
            'format',
            'genre',
            'theme',
            'content',
            'other',
          ];

          final groupKeys = grouped.keys.toList()
            ..sort((a, b) {
              final ia = groupOrder.indexOf(a);
              final ib = groupOrder.indexOf(b);
              final ra = ia == -1 ? groupOrder.length : ia;
              final rb = ib == -1 ? groupOrder.length : ib;
              if (ra != rb) return ra.compareTo(rb);
              return a.compareTo(b);
            });

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusFull,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(leadingIcon, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                          ),
                          onPressed: selectedValues.isEmpty
                              ? null
                              : () =>
                                    setSheetState(() => selectedValues.clear()),
                          child: Text(AppLocalizations.of(context)!.reset),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: AppLocalizations.of(context)!.searchTagsHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusLg,
                          ),
                        ),
                        filled: true,
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.noTagsFound,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          : ListView(
                              controller: scrollController,
                              children: [
                                for (final groupKey in groupKeys) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      _capitalize(groupKey),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: grouped[groupKey]!.map((option) {
                                      final isSelected = selectedValues
                                          .contains(option.value);
                                      return FilterChip(
                                        label: Text(option.label),
                                        selected: isSelected,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLow,
                                        selectedColor: colors.background,
                                        side: BorderSide(
                                          color: isSelected
                                              ? colors.border
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .outlineVariant,
                                        ),
                                        checkmarkColor: colors.foreground,
                                        labelStyle: TextStyle(
                                          color: isSelected
                                              ? colors.foreground
                                              : null,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                        onSelected: (isSelected) {
                                          setSheetState(() {
                                            if (isSelected) {
                                              selectedValues.add(option.value);
                                            } else {
                                              selectedValues.remove(
                                                option.value,
                                              );
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: DesignTokens.spaceMd),
                                ],
                                const SizedBox(height: DesignTokens.spaceSm),
                              ],
                            ),
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: onAccentColor(accentColor),
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          final applied = options
                              .where((o) => selectedValues.contains(o.value))
                              .toList();
                          context.pop(applied);
                        },
                        child: Text(
                          AppLocalizations.of(context)!
                              .applyWithCount(selectedValues.length),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}
