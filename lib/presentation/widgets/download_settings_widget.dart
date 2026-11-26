import 'package:material_ui/material_ui.dart';

import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../../core/constants/design_tokens.dart';
import '../blocs/download/download_bloc.dart';
import 'kuron_slider_fling.dart';

// Widget for configuring download settings
class DownloadSettingsWidget extends StatefulWidget {
  const DownloadSettingsWidget({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final DownloadSettings settings;
  final Function(DownloadSettings) onSettingsChanged;

  @override
  State<DownloadSettingsWidget> createState() => _DownloadSettingsWidgetState();
}

class _DownloadSettingsWidgetState extends State<DownloadSettingsWidget> {
  late DownloadSettings _settings;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.maxFinite,
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)?.downloadSettingsTitle ??
                      AppLocalizations.of(context)!.downloadSettings,
                  style: TextStyleConst.headlineSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Settings form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Concurrent downloads
                    _buildSectionTitle(
                      AppLocalizations.of(context)?.performanceSection ??
                          AppLocalizations.of(context)!.performance,
                    ),
                    _buildConcurrentDownloadsSlider(),
                    const SizedBox(height: 16),

                    // Image quality
                    _buildImageQualityDropdown(),
                    const SizedBox(height: 24),

                    // Auto retry settings
                    _buildSectionTitle(
                      AppLocalizations.of(context)?.autoRetrySection ??
                          AppLocalizations.of(context)!.autoRetry,
                    ),
                    _buildAutoRetrySwitch(),
                    if (_settings.autoRetry) ...[
                      const SizedBox(height: 8),
                      _buildRetryAttemptsSlider(),
                    ],
                    const SizedBox(height: 24),

                    // Network settings
                    _buildSectionTitle(
                      AppLocalizations.of(context)?.networkSection ??
                          AppLocalizations.of(context)!.network,
                    ),
                    _buildWifiOnlySwitch(),
                    const SizedBox(height: 16),
                    _buildTimeoutSlider(),
                    const SizedBox(height: 24),

                    // Notifications
                    _buildSectionTitle(
                      AppLocalizations.of(context)?.notificationsSection ??
                          AppLocalizations.of(context)!.notifications,
                    ),
                    _buildNotificationsSwitch(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      style: TextStyleConst.labelLarge,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.save ?? 'Save',
                      style: TextStyleConst.labelLarge.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyleConst.titleMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildConcurrentDownloadsSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)?.maxConcurrentDownloads ??
                  AppLocalizations.of(context)!.maxConcurrentDownloads,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${_settings.maxConcurrentDownloads}',
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _settings.maxConcurrentDownloads.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: Theme.of(context).colorScheme.primary,
          inactiveColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.2),
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(
                maxConcurrentDownloads: value.toInt(),
              );
            });
          },
        ).withKuronSliderFx(),
        Text(
          AppLocalizations.of(context)?.concurrentDownloadsWarning ??
              AppLocalizations.of(context)!.higherValuesBandwidth,
          style: TextStyleConst.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildImageQualityDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.imageQualityLabel ?? 'Image Quality',
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _settings.imageQuality,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          dropdownColor: Theme.of(context).colorScheme.surface,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: 'low',
              child: Text(AppLocalizations.of(context)!.lowQuality),
            ),
            DropdownMenuItem(
              value: 'medium',
              child: Text(AppLocalizations.of(context)!.mediumQuality),
            ),
            DropdownMenuItem(
              value: 'high',
              child: Text(AppLocalizations.of(context)!.highQuality),
            ),
            DropdownMenuItem(
              value: 'original',
              child: Text(AppLocalizations.of(context)!.originalQuality),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _settings = _settings.copyWith(imageQuality: value);
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildAutoRetrySwitch() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)?.autoRetryFailedDownloads ??
                    AppLocalizations.of(context)!.autoRetryFailed,
                style: TextStyleConst.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                AppLocalizations.of(context)?.autoRetryDescription ??
                    AppLocalizations.of(context)!.autoRetryDescription,
                style: TextStyleConst.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: _settings.autoRetry,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(autoRetry: value);
            });
          },
        ),
      ],
    );
  }

  Widget _buildRetryAttemptsSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)?.maxRetryAttempts ??
                  AppLocalizations.of(context)!.maxRetryAttempts,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${_settings.retryAttempts}',
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _settings.retryAttempts.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: Theme.of(context).colorScheme.primary,
          inactiveColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.2),
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(retryAttempts: value.toInt());
            });
          },
        ).withKuronSliderFx(),
      ],
    );
  }

  Widget _buildWifiOnlySwitch() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)?.wifiOnlyLabel ?? 'WiFi Only',
                style: TextStyleConst.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                AppLocalizations.of(context)?.wifiOnlyDescription ??
                    AppLocalizations.of(context)!.wifiOnlyDownload,
                style: TextStyleConst.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: _settings.wifiOnly,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(wifiOnly: value);
            });
          },
        ),
      ],
    );
  }

  Widget _buildTimeoutSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)?.downloadTimeoutLabel ??
                  AppLocalizations.of(context)!.downloadTimeout,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${_settings.timeoutDuration.inMinutes} ${AppLocalizations.of(context)?.minutesUnit ?? 'min'}',
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _settings.timeoutDuration.inMinutes.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          activeColor: Theme.of(context).colorScheme.primary,
          inactiveColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.2),
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(
                timeoutDuration: Duration(minutes: value.toInt()),
              );
            });
          },
        ).withKuronSliderFx(),
      ],
    );
  }

  Widget _buildNotificationsSwitch() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)?.enableNotificationsLabel ??
                    AppLocalizations.of(context)!.enableNotifications,
                style: TextStyleConst.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                AppLocalizations.of(context)?.enableNotificationsDescription ??
                    AppLocalizations.of(context)!.showNotificationsProgress,
                style: TextStyleConst.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: _settings.enableNotifications,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (value) {
            setState(() {
              _settings = _settings.copyWith(enableNotifications: value);
            });
          },
        ),
      ],
    );
  }

  void _saveSettings() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSettingsChanged(_settings);
      Navigator.of(context).pop();
    }
  }
}
