import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/network/source_health_monitor.dart';
import 'package:nhasixapp/core/utils/storage_settings.dart';
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';

// ======================================================================
// Shared Builder Helpers
// ======================================================================

Widget buildSettingsSectionHeader(
  IconData icon,
  String title,
  ThemeData theme,
) {
  return Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    ),
  );
}

Widget buildSettingsCard(List<Widget> children, ThemeData theme) {
  return Card(
    elevation: DesignTokens.elevationNone,
    color: theme.colorScheme.surfaceContainer,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
    ),
    child: Material(
      // Restore ink-splash rendering for ListTiles inside the card.
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: children),
      ),
    ),
  );
}

Widget buildSettingsDivider(ThemeData theme) {
  return Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: theme.dividerColor.withValues(alpha: 0.2),
  );
}

Widget buildSettingsDropdownTile<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required Function(T?) onChanged,
  required ThemeData theme,
  bool enabled = true,
}) {
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(
      title,
      style: TextStyleConst.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
        color: enabled ? theme.colorScheme.onSurface : theme.disabledColor,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyleConst.bodySmall.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        icon: Icon(
          Icons.arrow_drop_down,
          color: theme.colorScheme.primary,
          size: 20,
        ),
        style: TextStyleConst.bodyMedium.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        dropdownColor: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    ),
  );
}

Widget buildSettingsSwitchTile({
  required String title,
  required String subtitle,
  required bool value,
  required Function(bool) onChanged,
  required ThemeData theme,
  bool enabled = true,
}) {
  return SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(
      title,
      style: TextStyleConst.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
        color: enabled ? theme.colorScheme.onSurface : theme.disabledColor,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyleConst.bodySmall.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    value: value,
    onChanged: enabled ? onChanged : null,
    activeThumbColor: theme.colorScheme.primary,
  );
}

Widget buildSettingsActionTile({
  required String title,
  required String subtitle,
  required String actionLabel,
  required VoidCallback onTap,
  required ThemeData theme,
  bool isDestructive = false,
}) {
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(
      title,
      style: TextStyleConst.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyleConst.bodySmall.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    trailing: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: isDestructive
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
        foregroundColor: isDestructive
            ? theme.colorScheme.onError
            : theme.colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(
        actionLabel,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

Widget buildSettingsInfoBanner(String text, IconData icon, ThemeData theme) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget buildSettingsSheetHint(ThemeData theme, String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      border: Border.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.2),
      ),
    ),
    child: Text(
      text,
      style: TextStyleConst.bodySmall.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

// Build colored dot for source reachability status.
Widget buildHealthDot(
  ContentSource source,
  SourceHealthStatus health,
  ThemeData theme,
) {
  Color color;
  switch (health) {
    case SourceHealthStatus.reachable:
      color = const Color(0xFF4CAF50); // green
    case SourceHealthStatus.unreachable:
      color = const Color(0xFFF44336); // red
    case SourceHealthStatus.unknown:
      color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
  }
  return SizedBox(
    width: 24,
    height: 24,
    child: Icon(Icons.circle, size: 12, color: color),
  );
}

// ======================================================================
// Theme / Display Section Widgets
// ======================================================================

Widget buildDisguiseModeTile(
  UserPreferences prefs,
  ThemeData theme,
  AppLocalizations l10n,
) {
  return BlocBuilder<SettingsCubit, SettingsState>(
    builder: (context, state) {
      final isLoading = state is SettingsLoaded && state.isUpdatingDisguiseMode;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          l10n.disguiseMode,
          style: TextStyleConst.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          isLoading ? l10n.applyingDisguiseMode : l10n.disguiseModeDescription,
          style: TextStyleConst.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButton<String>(
            value: prefs.disguiseMode,
            underline: const SizedBox(),
            icon: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Icon(
                    Icons.arrow_drop_down,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
            style: TextStyleConst.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            dropdownColor: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            items: [
              DropdownMenuItem(
                value: 'default',
                child: Text(l10n.disguiseDefault),
              ),
              DropdownMenuItem(
                value: 'calculator',
                child: Text(l10n.disguiseCalculator),
              ),
              DropdownMenuItem(value: 'notes', child: Text(l10n.disguiseNotes)),
              DropdownMenuItem(
                value: 'weather',
                child: Text(l10n.disguiseWeather),
              ),
            ],
            onChanged: isLoading
                ? null
                : (mode) {
                    if (mode != null) {
                      context.read<SettingsCubit>().updateDisguiseMode(mode);
                    }
                  },
          ),
        ),
      );
    },
  );
}

Widget buildDnsStatusCard(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n, {
  required Map<String, dynamic>? deviceDnsState,
}) {
  final deviceActive = deviceDnsState?['isActive'] == true;
  final deviceServerName = deviceDnsState?['serverName'] as String?;
  final deviceReason = deviceDnsState?['reason'] as String?;

  return buildSettingsCard([
    //  App DNS status hidden — no user changer yet
    // Device Private DNS status
    ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(Icons.security_outlined, color: theme.colorScheme.primary),
      title: Text(
        l10n.devicePrivateDns,
        style: TextStyleConst.bodyLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        deviceActive
            ? (deviceServerName != null
                  ? l10n.dnsPrivateDnsStrict(deviceServerName)
                  : l10n.dnsPrivateDnsOpportunistic)
            : (deviceReason == 'API_29_REQUIRED'
                  ? l10n.dnsPrivateDnsRequirements
                  : l10n.dnsPrivateDnsOff),
        style: TextStyleConst.bodySmall.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              (deviceActive
                      ? AppColors.success
                      : theme.colorScheme.surfaceContainerHighest)
                  .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        ),
        child: Text(
          deviceActive ? l10n.dnsModeOn : l10n.dnsModeOff,
          style: TextStyleConst.labelMedium.copyWith(
            color: deviceActive
                ? AppColors.success
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),

    // Open DNS settings + guidance
    buildSettingsDivider(theme),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            deviceReason == 'API_29_REQUIRED'
                ? l10n.dnsPrivateDnsRequiresAndroid10
                : l10n.dnsPrivateDnsGuidance,
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dnsPrivateDnsCannotAutoSet,
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!deviceActive && deviceReason != 'API_29_REQUIRED') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => KuronNative.instance.openDnsSettings(),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.openDnsSettings),
              ),
            ),
          ],
        ],
      ),
    ),
  ], theme);
}

Widget buildStorageSection(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n, {
  required VoidCallback onRefresh,
}) {
  return FutureBuilder<String?>(
    future: StorageSettings.getCustomRootPath(),
    builder: (context, snapshot) {
      final customPath = snapshot.data;
      final hasCustomPath = customPath != null && customPath.isNotEmpty;

      return buildSettingsCard([
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(Icons.folder_open, color: theme.colorScheme.primary),
          title: Text(
            l10n.downloadDirectory,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            hasCustomPath ? customPath : l10n.defaultStorage,
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
            tooltip: l10n.changeDirectory,
            onPressed: () async {
              final newPath = await StorageSettings.pickAndSaveCustomRoot(
                context,
              );
              if (newPath != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.downloadDirectoryUpdated),
                    backgroundColor: AppColors.success,
                  ),
                );
                onRefresh(); // Refresh UI
              }
            },
          ),
        ),
        if (hasCustomPath) ...[
          buildSettingsDivider(theme),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Icon(Icons.refresh, color: theme.colorScheme.error),
            title: Text(
              l10n.resetToDefault,
              style: TextStyleConst.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.error,
              ),
            ),
            subtitle: Text(
              l10n.useDefaultInternalStorage,
              style: TextStyleConst.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: theme.colorScheme.surface,
                  title: Text(
                    l10n.resetToDefault,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  content: Text(
                    l10n.confirmResetStorageDirectory,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(l10n.reset),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await StorageSettings.clearCustomRoot();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.downloadDirectoryReset)),
                  );
                  onRefresh(); // Refresh UI
                }
              }
            },
          ),
        ],
      ], theme);
    },
  );
}

Widget buildResetButton(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n,
) {
  return FilledButton.icon(
    onPressed: () async {
      final settingsCubit = context.read<SettingsCubit>();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          ),
          title: Text(l10n.resetSettings, style: TextStyleConst.headingSmall),
          content: Text(
            l10n.confirmResetSettings,
            style: TextStyleConst.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => ctx.pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => ctx.pop(true),
              child: Text(l10n.reset),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await settingsCubit.resetToDefaults();
      }
    },
    icon: const Icon(Icons.refresh),
    label: Text(l10n.resetToDefault),
    style: FilledButton.styleFrom(
      backgroundColor: theme.colorScheme.error,
      foregroundColor: theme.colorScheme.onError,
      minimumSize: const Size(double.infinity, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
    ),
  );
}
