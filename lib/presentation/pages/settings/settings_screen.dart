import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/routing/app_router.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/network/source_health_monitor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../domain/entities/user_preferences.dart';
import '../../../core/utils/source_config_display_utils.dart';
import '../../../core/services/tag_blacklist_service.dart';

import '../../cubits/settings/settings_cubit.dart';
import '../../cubits/source/source_cubit.dart';
import '../../cubits/source/source_state.dart';
import '../../blocs/download/download_bloc.dart';
import '../../../core/utils/app_update_test.dart';
import '../../widgets/app_main_drawer_widget.dart';
import 'settings_theme_widgets.dart';
import 'settings_download_widgets.dart';
import 'settings_privacy_widgets.dart';
import 'settings_app_lock_widgets.dart';
import 'settings_kuron_backup.dart';
import 'settings_nclient_import.dart';
import 'ai_settings_screen.dart';

part 'settings_source_install.dart';
part 'settings_source_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final TagBlacklistService _tagBlacklistService;
  Map<String, dynamic>? _deviceDnsState;

  void _ensureDownloadBlocInitialized() {
    final downloadBloc = context.read<DownloadBloc>();
    if (downloadBloc.state is DownloadInitial) {
      downloadBloc.add(const DownloadInitializeEvent());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tagBlacklistService = getIt<TagBlacklistService>();
    _ensureDownloadBlocInitialized();

    unawaited(
      Future.wait([
        _tagBlacklistService.syncOnlineEntries('nhentai'),
        _tagBlacklistService.syncOnlineRules('nhentai'),
      ]),
    );
    _loadDnsDiagnostics();
  }

  Future<void> _loadDnsDiagnostics() async {
    try {
      final deviceState = await KuronNative.instance.getPrivateDnsDiagnostics();
      if (mounted) {
        setState(() {
          _deviceDnsState = deviceState;
        });
      }
    } catch (e) {
      getIt<Logger>().w('DNS diagnostics failed', error: e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDnsDiagnostics();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        centerTitle: true,
        elevation: DesignTokens.elevationNone,
        backgroundColor: Colors.transparent,
      ),
      drawer: AppMainDrawerWidget(context: context),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            if (state is SettingsLoaded) {
              return _buildSettingsContent(
                context,
                state.preferences,
                theme,
                l10n,
              );
            } else if (state is SettingsError) {
              return Center(child: Text(state.getUserFriendlyMessage(l10n)));
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
    );
  }

  Widget _buildSettingsContent(
    BuildContext context,
    UserPreferences prefs,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(height: DesignTokens.spaceLg),

          // Display Settings Card
          buildSettingsSectionHeader(Icons.palette_outlined, 'DISPLAY', theme),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsCard([
            buildSettingsDropdownTile(
              context: context,
              title: l10n.theme,
              subtitle: l10n.themeDescription,
              value: prefs.theme,
              items: ThemeOption.all
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(ThemeOption.getDisplayName(t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => context.read<SettingsCubit>().updateTheme(v!),
              theme: theme,
            ),
            buildSettingsDivider(theme),
            buildSettingsDropdownTile(
              context: context,
              title: l10n.appLanguage,
              subtitle: 'Select your preferred language',
              value: prefs.defaultLanguage,
              items: [
                DropdownMenuItem(value: 'english', child: Text(l10n.english)),
                DropdownMenuItem(
                  value: 'indonesian',
                  child: Text(l10n.indonesian),
                ),
                DropdownMenuItem(value: 'chinese', child: Text(l10n.chinese)),
              ],
              onChanged: (v) =>
                  context.read<SettingsCubit>().updateDefaultLanguage(v!),
              theme: theme,
            ),
            buildSettingsDivider(theme),
            buildSettingsDropdownTile(
              context: context,
              title: l10n.imageQuality,
              subtitle: l10n.imageQualityDescription,
              value: prefs.imageQuality,
              items: ImageQuality.all
                  .map(
                    (q) => DropdownMenuItem(
                      value: q,
                      child: Text(ImageQuality.getDisplayName(q)),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  context.read<SettingsCubit>().updateImageQuality(v!),
              theme: theme,
            ),
            buildSettingsDivider(theme),
            buildSettingsSwitchTile(
              title: l10n.blurThumbnails,
              subtitle: l10n.blurThumbnailsDescription,
              value: prefs.blurThumbnails,
              onChanged: (v) =>
                  context.read<SettingsCubit>().updateBlurThumbnails(v),
              theme: theme,
            ),
          ], theme),

          SizedBox(height: DesignTokens.spaceXl),

          buildSettingsSectionHeader(
            Icons.visibility_off_outlined,
            AppLocalizations.of(context)!.contentFilters,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsInfoBanner(
            AppLocalizations.of(context)!.blurCoversDescription,
            Icons.shield_moon_outlined,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildTagBlacklistSection(context, prefs, theme,
              tagBlacklistService: _tagBlacklistService),

          SizedBox(height: DesignTokens.spaceXl),

          // Storage Settings Card
          buildSettingsSectionHeader(Icons.folder_outlined, 'STORAGE', theme),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsInfoBanner(
            l10n.storageDescription,
            Icons.info_outline,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildStorageSection(context, theme, l10n,
              onRefresh: () => setState(() {})),

          SizedBox(height: DesignTokens.spaceXl),

          // Download Settings Card
          buildSettingsSectionHeader(
              Icons.download_outlined, 'DOWNLOAD', theme),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsInfoBanner(
            l10n.imageQualityDescription,
            Icons.info_outline,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildDownloadSection(context, theme, l10n),

          SizedBox(height: DesignTokens.spaceXl),

          // Reader Settings Card
          buildSettingsSectionHeader(
              Icons.auto_stories_outlined, 'READER', theme),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsInfoBanner(
            l10n.autoCleanupDescription,
            Icons.info_outline,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsCard([
            buildSettingsSwitchTile(
              title: l10n.autoCleanupHistory,
              subtitle: l10n.automaticallyCleanOldReadingHistory,
              value: prefs.autoCleanupHistory,
              onChanged: (v) =>
                  context.read<SettingsCubit>().updateAutoCleanupHistory(v),
              theme: theme,
            ),
            if (prefs.autoCleanupHistory) ...[
              buildSettingsDivider(theme),
              buildSettingsDropdownTile(
                context: context,
                title: l10n.cleanupInterval,
                subtitle: l10n.howOftenToCleanupHistory,
                value: prefs.historyCleanupIntervalHours,
                items: [6, 12, 24, 48, 168].map((h) {
                  final String label = h < 24
                      ? '${h}h'
                      : h == 24
                          ? l10n.oneDay
                          : h == 48
                              ? l10n.twoDays
                              : l10n.oneWeek;
                  return DropdownMenuItem(value: h, child: Text(label));
                }).toList(),
                onChanged: (v) => context
                    .read<SettingsCubit>()
                    .updateHistoryCleanupInterval(v!),
                theme: theme,
              ),
              buildSettingsDivider(theme),
              buildSettingsDropdownTile(
                context: context,
                title: l10n.maxHistoryDays,
                subtitle: l10n.maximumDaysToKeepHistory,
                value: prefs.maxHistoryDays,
                items: [0, 7, 14, 30, 60, 90]
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          d == 0 ? l10n.unlimited : l10n.daysValue(d),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    context.read<SettingsCubit>().updateMaxHistoryDays(v!),
                theme: theme,
              ),
              buildSettingsDivider(theme),
              buildSettingsSwitchTile(
                title: l10n.cleanupOnInactivity,
                subtitle: l10n.cleanHistoryWhenAppUnused,
                value: prefs.cleanupOnInactivity,
                onChanged: (v) =>
                    context.read<SettingsCubit>().updateCleanupOnInactivity(v),
                theme: theme,
              ),
              if (prefs.cleanupOnInactivity) ...[
                buildSettingsDivider(theme),
                buildSettingsDropdownTile(
                  context: context,
                  title: l10n.inactivityThreshold,
                  subtitle: l10n.daysOfInactivityBeforeCleanup,
                  value: prefs.inactivityCleanupDays,
                  items: [3, 5, 7, 14, 30]
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(l10n.daysValue(d)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => context
                      .read<SettingsCubit>()
                      .updateInactivityCleanupDays(v!),
                  theme: theme,
                ),
              ],
            ],
          ], theme),

          SizedBox(height: DesignTokens.spaceXl),

          // App Lock Section
          buildAppLockSection(context, theme),

          SizedBox(height: DesignTokens.spaceXl),

          // App Disguise Card
          buildSettingsSectionHeader(
            Icons.visibility_off_outlined,
            AppLocalizations.of(context)!.appDisguise,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsCard([
            buildDisguiseModeTile(prefs, theme, l10n),
          ], theme),

          SizedBox(height: DesignTokens.spaceXl),

          // DNS Status Section
          buildSettingsSectionHeader(
            Icons.dns_outlined,
            'DNS',
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildDnsStatusCard(context, theme, l10n,
              deviceDnsState: _deviceDnsState),

          SizedBox(height: DesignTokens.spaceXl),

          // Available Sources Section
          _buildSourcesShortcut(this, theme, l10n),

          SizedBox(height: DesignTokens.spaceXl),

          // Developer Tools Card
          buildSettingsSectionHeader(
            Icons.bug_report_outlined,
            AppLocalizations.of(context)!.developerTools,
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsCard([
            if (kDebugMode) ...[
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.dns_outlined),
                title: const Text('DoH Test'),
                subtitle:
                    const Text('Test DNS-over-HTTPS resolver and responses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => AppRouter.goToDohTest(context),
              ),
              buildSettingsDivider(theme),
            ],
            buildSettingsActionTile(
              title: l10n.testCacheClearing,
              subtitle: l10n.testCacheClearingDescription,
              actionLabel: l10n.runTest,
              onTap: () => AppUpdateTest.runTests(context),
              theme: theme,
            ),
            buildSettingsDivider(theme),
            buildSettingsActionTile(
              title: l10n.forceClearCache,
              subtitle: l10n.forceClearCacheDescription,
              actionLabel: l10n.clearCacheButton,
              onTap: () => AppUpdateTest.forceClearCache(context),
              isDestructive: true,
              theme: theme,
            ),
          ], theme),

          SizedBox(height: DesignTokens.spaceXl),

          // AI Translation Card
          buildSettingsSectionHeader(
            Icons.auto_awesome_outlined,
            'AI TRANSLATION',
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsActionTile(
            title: AppLocalizations.of(context)!.aiSettings,
            subtitle: AppLocalizations.of(context)!.aiProvidersSubtitle,
            actionLabel: AppLocalizations.of(context)!.aiOpen,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AiSettingsScreen(),
              ),
            ),
            theme: theme,
          ),

          SizedBox(height: DesignTokens.spaceXl),

          // Backup & Restore Section
          buildSettingsSectionHeader(
            Icons.backup_outlined,
            'BACKUP & RESTORE',
            theme,
          ),
          SizedBox(height: DesignTokens.spaceMd),
          buildSettingsCard([
            buildKuronBackupTile(context, theme, l10n),
            buildKuronRestoreTile(context, theme, l10n),
            buildNclientImportTile(context, theme, l10n),
          ], theme),

          SizedBox(height: DesignTokens.spaceXl),

          // Reset Button
          buildResetButton(context, theme, l10n),

          SizedBox(height: DesignTokens.space2xl),
        ],
      ),
    );
  }
}
