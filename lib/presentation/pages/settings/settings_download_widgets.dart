import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'settings_theme_widgets.dart';

Widget buildDownloadSection(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n,
) {
  return BlocBuilder<DownloadBloc, DownloadBlocState>(
    builder: (context, state) {
      if (state is DownloadError) {
        return buildSettingsCard([
          ListTile(
            title: Text(
              l10n.failedToLoad,
              style: TextStyleConst.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.message,
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            trailing: state.canRetry
                ? IconButton(
                    onPressed: () => context
                        .read<DownloadBloc>()
                        .add(const DownloadInitializeEvent()),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: l10n.retry,
                  )
                : null,
          ),
        ], theme);
      }

      if (state is DownloadInitial || state is DownloadInitializing) {
        return buildSettingsCard([
          ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              l10n.loadingDownloads,
              style: TextStyleConst.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ], theme);
      }

      if (state is! DownloadLoaded) {
        return const SizedBox.shrink();
      }

      final settings = state.settings;

      return buildSettingsCard([
        // Max Concurrent Downloads
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: Text(
            l10n.maxConcurrentDownloads,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: DesignTokens.spaceSm),
              Slider(
                value: settings.maxConcurrentDownloads.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '${settings.maxConcurrentDownloads}',
                onChanged: (value) {
                  context.read<DownloadBloc>().add(
                        DownloadSettingsUpdateEvent(
                          maxConcurrentDownloads: value.toInt(),
                          imageQuality: settings.imageQuality,
                          autoRetry: settings.autoRetry,
                          retryAttempts: settings.retryAttempts,
                          retryDelay: settings.retryDelay,
                          timeoutDuration: settings.timeoutDuration,
                          enableNotifications: settings.enableNotifications,
                          wifiOnly: settings.wifiOnly,
                          customStorageRoot: settings.customStorageRoot,
                        ),
                      );
                },
              ),
              Text(
                l10n.concurrentDownloadsWarning,
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        buildSettingsDivider(theme),

        // Image Quality
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: Text(
            l10n.imageQualityLabel,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: DropdownButton<String>(
            value: settings.imageQuality,
            isExpanded: true,
            items: [
              DropdownMenuItem(
                value: 'low',
                child: Text(l10n.lowQuality),
              ),
              DropdownMenuItem(
                value: 'medium',
                child: Text(l10n.mediumQuality),
              ),
              DropdownMenuItem(
                value: 'high',
                child: Text(l10n.highQuality),
              ),
              DropdownMenuItem(
                value: 'original',
                child: Text(l10n.originalQuality),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                context.read<DownloadBloc>().add(
                      DownloadSettingsUpdateEvent(
                        maxConcurrentDownloads: settings.maxConcurrentDownloads,
                        imageQuality: value,
                        autoRetry: settings.autoRetry,
                        retryAttempts: settings.retryAttempts,
                        retryDelay: settings.retryDelay,
                        timeoutDuration: settings.timeoutDuration,
                        enableNotifications: settings.enableNotifications,
                        wifiOnly: settings.wifiOnly,
                        customStorageRoot: settings.customStorageRoot,
                      ),
                    );
              }
            },
          ),
        ),
        buildSettingsDivider(theme),

        // Auto Retry
        buildSettingsSwitchTile(
          title: l10n.autoRetryFailedDownloads,
          subtitle: l10n.autoRetryDescription,
          value: settings.autoRetry,
          onChanged: (value) {
            context.read<DownloadBloc>().add(
                  DownloadSettingsUpdateEvent(
                    maxConcurrentDownloads: settings.maxConcurrentDownloads,
                    imageQuality: settings.imageQuality,
                    autoRetry: value,
                    retryAttempts: settings.retryAttempts,
                    retryDelay: settings.retryDelay,
                    timeoutDuration: settings.timeoutDuration,
                    enableNotifications: settings.enableNotifications,
                    wifiOnly: settings.wifiOnly,
                    customStorageRoot: settings.customStorageRoot,
                  ),
                );
          },
          theme: theme,
        ),

        if (settings.autoRetry) ...[
          buildSettingsDivider(theme),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              l10n.maxRetryAttempts,
              style: TextStyleConst.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: Slider(
              value: settings.retryAttempts.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${settings.retryAttempts}',
              onChanged: (value) {
                context.read<DownloadBloc>().add(
                      DownloadSettingsUpdateEvent(
                        maxConcurrentDownloads: settings.maxConcurrentDownloads,
                        imageQuality: settings.imageQuality,
                        autoRetry: settings.autoRetry,
                        retryAttempts: value.toInt(),
                        retryDelay: settings.retryDelay,
                        timeoutDuration: settings.timeoutDuration,
                        enableNotifications: settings.enableNotifications,
                        wifiOnly: settings.wifiOnly,
                        customStorageRoot: settings.customStorageRoot,
                      ),
                    );
              },
            ),
          ),
        ],
        buildSettingsDivider(theme),

        // WiFi Only
        buildSettingsSwitchTile(
          title: l10n.wifiOnlyLabel,
          subtitle: l10n.wifiOnlyDescription,
          value: settings.wifiOnly,
          onChanged: (value) {
            context.read<DownloadBloc>().add(
                  DownloadSettingsUpdateEvent(
                    maxConcurrentDownloads: settings.maxConcurrentDownloads,
                    imageQuality: settings.imageQuality,
                    autoRetry: settings.autoRetry,
                    retryAttempts: settings.retryAttempts,
                    retryDelay: settings.retryDelay,
                    timeoutDuration: settings.timeoutDuration,
                    enableNotifications: settings.enableNotifications,
                    wifiOnly: value,
                    customStorageRoot: settings.customStorageRoot,
                  ),
                );
          },
          theme: theme,
        ),
        buildSettingsDivider(theme),

        // Download Timeout
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          title: Text(
            l10n.downloadTimeoutLabel,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: DesignTokens.spaceSm),
              Text(
                '${settings.timeoutDuration.inMinutes} ${l10n.minutesUnit}',
                style: TextStyleConst.bodyMedium.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Slider(
                value: settings.timeoutDuration.inMinutes.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: AppLocalizations.of(context)!
                    .timeoutMinutes(settings.timeoutDuration.inMinutes),
                onChanged: (value) {
                  context.read<DownloadBloc>().add(
                        DownloadSettingsUpdateEvent(
                          maxConcurrentDownloads:
                              settings.maxConcurrentDownloads,
                          imageQuality: settings.imageQuality,
                          autoRetry: settings.autoRetry,
                          retryAttempts: settings.retryAttempts,
                          retryDelay: settings.retryDelay,
                          timeoutDuration: Duration(minutes: value.toInt()),
                          enableNotifications: settings.enableNotifications,
                          wifiOnly: settings.wifiOnly,
                          customStorageRoot: settings.customStorageRoot,
                        ),
                      );
                },
              ),
            ],
          ),
        ),
        buildSettingsDivider(theme),

        // Enable Notifications
        buildSettingsSwitchTile(
          title: l10n.enableNotificationsLabel,
          subtitle: l10n.enableNotificationsDescription,
          value: settings.enableNotifications,
          onChanged: (value) {
            context.read<DownloadBloc>().add(
                  DownloadSettingsUpdateEvent(
                    maxConcurrentDownloads: settings.maxConcurrentDownloads,
                    imageQuality: settings.imageQuality,
                    autoRetry: settings.autoRetry,
                    retryAttempts: settings.retryAttempts,
                    retryDelay: settings.retryDelay,
                    timeoutDuration: settings.timeoutDuration,
                    enableNotifications: value,
                    wifiOnly: settings.wifiOnly,
                    customStorageRoot: settings.customStorageRoot,
                  ),
                );
          },
          theme: theme,
        ),
      ], theme);
    },
  );
}
