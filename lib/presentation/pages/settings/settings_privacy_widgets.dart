import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/core/services/tag_blacklist_service.dart';
import 'package:nhasixapp/core/utils/tag_blacklist_utils.dart';
import 'package:nhasixapp/domain/entities/search_filter.dart' as search_filter;
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';

import 'settings_theme_widgets.dart';

Widget buildTagBlacklistSection(
  BuildContext context,
  UserPreferences prefs,
  ThemeData theme, {
  required TagBlacklistService tagBlacklistService,
}) {
  return AnimatedBuilder(
    animation: tagBlacklistService,
    builder: (context, _) {
      final mergedEntries = tagBlacklistService.getMergedEntries(
        sourceId: 'nhentai',
        localEntries: prefs.blacklistedTags,
      );
      final onlineRules = tagBlacklistService.getCachedOnlineRules('nhentai');
      final hasSession = tagBlacklistService.hasActiveSession('nhentai');
      final isSyncingRules = tagBlacklistService.isSyncingRules('nhentai');

      return buildSettingsCard([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.visibility_off_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.tagBlacklist,
                          style: TextStyleConst.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppLocalizations.of(context)!.blacklistDescription,
                          style: TextStyleConst.bodySmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => showTagBlacklistSheet(
                      context,
                      prefs,
                      theme,
                      tagBlacklistService: tagBlacklistService,
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(AppLocalizations.of(context)!.manage),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  buildBlacklistStatChip(
                    theme: theme,
                    label: AppLocalizations.of(context)!.local,
                    value: '${prefs.blacklistedTags.length}',
                    icon: Icons.sd_storage_rounded,
                  ),
                  buildBlacklistStatChip(
                    theme: theme,
                    label: AppLocalizations.of(context)!.rules,
                    value: hasSession
                        ? '${onlineRules.length}'
                        : AppLocalizations.of(context)!.login,
                    icon: Icons.rule_rounded,
                    isLoading: isSyncingRules,
                  ),
                  buildBlacklistStatChip(
                    theme: theme,
                    label: AppLocalizations.of(context)!.active,
                    value: '${mergedEntries.length}',
                    icon: Icons.layers_rounded,
                  ),
                ],
              ),
              if (hasSession) ...[
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!
                      .onlineRuleDetailsCount(onlineRules.length),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (onlineRules.isEmpty)
                  buildSettingsSheetHint(
                    theme,
                    AppLocalizations.of(context)!.noOnlineRulesYet,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: onlineRules
                        .take(12)
                        .map(
                          (rule) =>
                              buildBlacklistEntryChip(theme, rule.displayLabel),
                        )
                        .toList(),
                  ),
              ],
              const SizedBox(height: 16),
              if (mergedEntries.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.noBlacklistRulesYet,
                    style: TextStyleConst.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!
                        .activeCoverageDescription(mergedEntries.length),
                    style: TextStyleConst.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ], theme);
    },
  );
}

Widget buildBlacklistStatChip({
  required ThemeData theme,
  required String label,
  required String value,
  required IconData icon,
  bool isLoading = false,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.2),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          )
        else
          Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label • $value',
          style: TextStyleConst.labelMedium.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget buildBlacklistEntryChip(ThemeData theme, String entry) {
  final chipLabel = int.tryParse(entry) != null ? '#$entry' : entry;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
    ),
    child: Text(
      chipLabel,
      style: TextStyleConst.labelMedium.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String buildLocalBlacklistLabel(
  String entry,
  List<OnlineBlacklistRule> onlineRules,
  Map<String, BlacklistedTagMetadata> localMetadata,
) {
  final normalized = TagBlacklistUtils.normalizeEntry(entry);

  String? idCandidate;
  if (int.tryParse(normalized) != null) {
    idCandidate = normalized;
  } else {
    final idMatch = RegExp(r'^(?:id|tag_id|tagid|tag):\s*(\d+)$')
        .firstMatch(normalized);
    idCandidate = idMatch?.group(1);
  }

  if (idCandidate == null) {
    return entry;
  }

  final localMeta = localMetadata[idCandidate];
  if (localMeta != null && localMeta.name.isNotEmpty) {
    return '${localMeta.type}:${localMeta.name} (#$idCandidate)';
  }

  for (final rule in onlineRules) {
    if (rule.id == idCandidate) {
      return '${rule.displayLabel} (#$idCandidate)';
    }
  }

  return '#$idCandidate';
}

Future<void> showTagBlacklistSheet(
  BuildContext context,
  UserPreferences prefs,
  ThemeData theme, {
  required TagBlacklistService tagBlacklistService,
}) async {
  final controller = TextEditingController();
  var localEntries = List<String>.from(prefs.blacklistedTags);
  var localMetadata = Map<String, BlacklistedTagMetadata>.from(
    prefs.blacklistedTagMetadata,
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // Initialize: sync from Cubit to ensure fresh data on first open
          final settingsState = sheetContext.read<SettingsCubit>().state;
          if (settingsState is SettingsLoaded &&
              (!listEquals(
                    localEntries,
                    settingsState.preferences.blacklistedTags,
                  ) ||
                  localMetadata.length !=
                      settingsState
                          .preferences
                          .blacklistedTagMetadata
                          .length)) {
            // If Cubit has different data, use that (source of truth)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              localEntries = List<String>.from(
                settingsState.preferences.blacklistedTags,
              );
              localMetadata = Map<String, BlacklistedTagMetadata>.from(
                settingsState.preferences.blacklistedTagMetadata,
              );
              if (sheetContext.mounted) {
                setSheetState(() {});
              }
            });
          }

          final mediaQuery = MediaQuery.of(sheetContext);
          final mergedEntries = tagBlacklistService.getMergedEntries(
            sourceId: 'nhentai',
            localEntries: localEntries,
          );
          final onlineRules = tagBlacklistService.getCachedOnlineRules(
            'nhentai',
          );
          final hasSession = tagBlacklistService.hasActiveSession('nhentai');
          final isSyncing = tagBlacklistService.isSyncing('nhentai');
          final isSyncingRules = tagBlacklistService.isSyncingRules('nhentai');

          // Sync localEntries from Cubit state to ensure data consistency
          void syncFromCubit() {
            final settingsState = context.read<SettingsCubit>().state;
            if (settingsState is SettingsLoaded) {
              localEntries = List<String>.from(
                settingsState.preferences.blacklistedTags,
              );
              localMetadata = Map<String, BlacklistedTagMetadata>.from(
                settingsState.preferences.blacklistedTagMetadata,
              );
            }
          }

          Future<void> saveState() async {
            await context
                .read<SettingsCubit>()
                .updateBlacklistedTagsWithMetadata(localEntries, localMetadata);
          }

          Future<void> pickFromTags() async {
            final selectedFiltersForPicker = localEntries
                .map((entry) {
                  final normalizedEntry = TagBlacklistUtils.normalizeEntry(
                    entry,
                  );
                  final numericId = int.tryParse(normalizedEntry);
                  if (numericId == null) {
                    return search_filter.FilterItem.include(
                      entry,
                      tagName: entry,
                    );
                  }

                  final localMeta = localMetadata[normalizedEntry];
                  if (localMeta != null) {
                    return search_filter.FilterItem.include(
                      normalizedEntry,
                      tagId: numericId,
                      tagType: localMeta.type,
                      tagName: localMeta.name,
                      tagSlug: localMeta.slug,
                    );
                  }

                  final onlineMeta = onlineRules.firstWhere(
                    (rule) => rule.id == normalizedEntry,
                    orElse: () => OnlineBlacklistRule(token: normalizedEntry),
                  );
                  return search_filter.FilterItem.include(
                    normalizedEntry,
                    tagId: numericId,
                    tagType: onlineMeta.type,
                    tagName: onlineMeta.name,
                  );
                })
                .toList(growable: false);

            final selected = await AppRouter.goToFilterData(
              context,
              filterType: 'tag',
              sourceId: 'nhentai',
              hideOtherTabs: false,
              supportsExclude: false,
              selectedFilters: selectedFiltersForPicker,
            );

            if (!context.mounted || selected == null) {
              return;
            }

            final backupEntries = List<String>.from(localEntries);
            final backupMetadata = Map<String, BlacklistedTagMetadata>.from(
              localMetadata,
            );

            // FilterData works as a full selector. Apply should replace
            // current local selections, including the empty state.
            localEntries = <String>[];
            localMetadata = <String, BlacklistedTagMetadata>{};

            for (final filter in selected.where((item) => !item.isExcluded)) {
              final id = filter.tagId;
              if (id != null && id > 0) {
                final idString = id.toString();
                localEntries.add(idString);
                localMetadata[idString] = BlacklistedTagMetadata(
                  id: idString,
                  type: filter.tagType ?? 'tag',
                  name: filter.tagName ?? filter.value,
                  slug: filter.tagSlug,
                );
              } else {
                localEntries.add(filter.value);
              }
            }

            localEntries = TagBlacklistUtils.sanitizeEntries(localEntries);

            try {
              await saveState();
              syncFromCubit();
            } catch (e) {
              localEntries = backupEntries;
              localMetadata = backupMetadata;
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.failedToSave(e.toString()),
                    ),
                  ),
                );
              }
              return;
            }

            if (sheetContext.mounted) {
              setSheetState(() {});
            }
          }

          Future<void> addEntries() async {
            final parsedEntries = TagBlacklistUtils.parseManualEntries(
              controller.text,
            );
            if (parsedEntries.isEmpty) {
              return;
            }

            // Diagnostic: check Cubit state BEFORE add
            final cubitBefore = context.read<SettingsCubit>().state;
            if (cubitBefore is SettingsLoaded) {
              getIt<Logger>().d(
                'SHEET_ADD_BEFORE: blur=${cubitBefore.preferences.blurThumbnails}, tags=${cubitBefore.preferences.blacklistedTags.length}',
              );
            }

            final backup = List<String>.from(localEntries);
            localEntries = TagBlacklistUtils.sanitizeEntries([
              ...localEntries,
              ...parsedEntries,
            ]);

            try {
              await saveState();

              // Diagnostic: check Cubit state AFTER add
              if (!context.mounted) return;
              final cubitAfter = context.read<SettingsCubit>().state;
              if (cubitAfter is SettingsLoaded) {
                getIt<Logger>().d(
                  'SHEET_ADD_AFTER: blur=${cubitAfter.preferences.blurThumbnails}, tags=${cubitAfter.preferences.blacklistedTags.length}',
                );
              }

              // Sync back from Cubit to ensure data consistency
              syncFromCubit();

              controller.clear();
            } catch (e) {
              // Restore backup if save failed
              localEntries = backup;
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.failedToSave(e.toString()),
                    ),
                  ),
                );
              }
              return;
            }

            if (sheetContext.mounted) {
              setSheetState(() {});
            }
          }

          Future<void> removeEntry(String entry) async {
            final backup = List<String>.from(localEntries);
            final backupMetadata = Map<String, BlacklistedTagMetadata>.from(
              localMetadata,
            );
            localEntries = localEntries
                .where((current) => current != entry)
                .toList(growable: false);
            final normalized = TagBlacklistUtils.normalizeEntry(entry);
            localMetadata.remove(normalized);

            try {
              await saveState();

              // Sync back from Cubit to ensure data consistency
              syncFromCubit();
            } catch (e) {
              // Restore backup if save failed
              localEntries = backup;
              localMetadata = backupMetadata;
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!
                          .failedToDelete(e.toString()),
                    ),
                  ),
                );
              }
              return;
            }

            if (sheetContext.mounted) {
              setSheetState(() {});
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusFull,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusXl,
                                  ),
                                ),
                                child: Icon(
                                  Icons.visibility_off_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!
                                          .manageTagBlacklist,
                                      style: TextStyleConst.headingSmall
                                          .copyWith(
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocalizations.of(context)!
                                          .addTagRulesDescription,
                                      style: TextStyleConst.bodySmall.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: controller,
                            minLines: 1,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)!
                                  .searchExampleHint,
                              prefixIcon: const Icon(Icons.tag_rounded),
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => addEntries(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isSyncing
                                      ? null
                                      : () async {
                                          await Future.wait([
                                            tagBlacklistService
                                                .syncOnlineEntries(
                                                  'nhentai',
                                                  forceRefresh: true,
                                                ),
                                            tagBlacklistService.syncOnlineRules(
                                              'nhentai',
                                              forceRefresh: true,
                                            ),
                                          ]);
                                          if (sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                  icon: isSyncing
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.sync_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    AppLocalizations.of(context)!.refreshOnline,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: addEntries,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text(
                                    AppLocalizations.of(context)!.addRules,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: pickFromTags,
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: Text(
                                AppLocalizations.of(context)!.pickFromTags,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!
                                  .localRulesCount(localEntries.length),
                              style: TextStyleConst.bodyLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (localEntries.isEmpty)
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .nothingSavedLocally,
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: localEntries
                                    .map(
                                      (entry) => InputChip(
                                        label: Text(
                                          buildLocalBlacklistLabel(
                                            entry,
                                            onlineRules,
                                            localMetadata,
                                          ),
                                        ),
                                        onDeleted: () => removeEntry(entry),
                                        deleteIconColor:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                    .toList(),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              hasSession
                                  ? AppLocalizations.of(context)!
                                        .onlineRulesMetadataCount(
                                          onlineRules.length,
                                        )
                                  : AppLocalizations.of(context)!
                                        .onlineRulesMetadata,
                              style: TextStyleConst.bodyLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (!hasSession)
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .loginRequiredForRules,
                              )
                            else if (isSyncingRules && onlineRules.isEmpty)
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .syncingOnlineRules,
                              )
                            else if (onlineRules.isEmpty)
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .noOnlineRuleDetails,
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: onlineRules
                                    .map(
                                      (rule) => buildBlacklistEntryChip(
                                        theme,
                                        rule.displayLabel,
                                      ),
                                    )
                                    .toList(),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              AppLocalizations.of(context)!
                                  .activeCoverageCount(mergedEntries.length),
                              style: TextStyleConst.bodyLarge.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (mergedEntries.isEmpty)
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .blacklistGalleriesInfo,
                              )
                            else
                              buildSettingsSheetHint(
                                theme,
                                AppLocalizations.of(context)!
                                    .coverageActiveDescription(
                                      mergedEntries.length,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            // Ensure all pending updates are flushed before closing
                            // This gives time for any lingering async updates to complete
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                            if (sheetContext.mounted) {
                              sheetContext.pop();
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.done),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
