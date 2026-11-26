import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/text_style_const.dart';
import '../../core/config/remote_config_service.dart';
import '../../core/di/service_locator.dart';
import '../../l10n/app_localizations.dart';
import '../../core/routing/app_router.dart';
import '../../core/constants/design_tokens.dart';
import '../../domain/entities/entities.dart';
import '../blocs/download/download_bloc.dart';
import 'content_list_widget.dart';
import 'kuron_fx.dart';
import 'kuron_squash.dart';
import 'kuron_snack_bar_content.dart';
import '../../domain/services/ehentai_download_strategy.dart';
import 'download_range_selector.dart';
import 'download_settings_widget.dart';

// Widget untuk tombol download dengan status dan progress
class DownloadButtonWidget extends StatelessWidget {
  const DownloadButtonWidget({
    super.key,
    required this.content,
    this.showProgress = true,
    this.showText = true,
    this.size = DownloadButtonSize.medium,
  });

  final Content content;
  final bool showProgress;
  final bool showText;
  final DownloadButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final button = BlocConsumer<DownloadBloc, DownloadBlocState>(
      listenWhen: (previous, current) {
        if (previous is! DownloadLoaded || current is! DownloadLoaded) {
          return false;
        }
        bool isDone(DownloadBlocState s) => s is DownloadLoaded
            ? s.downloads
                  .where(
                    (d) => ContentDownloadCache.matchesDownload(
                      d,
                      content.id,
                      sourceId: content.sourceId,
                    ),
                  )
                  .any((d) => d.state == DownloadState.completed)
            : false;
        return !isDone(previous) && isDone(current);
      },
      listener: (context, state) {
        // Leading edge of the progress/download bar reaching 100%. This
        // supersedes the old `downloadComplete` beat at this hook: both map to
        // JEDER!, but `progressComplete` carries the finish staging (control
        // x 1.2 / 1.05 s) and is anchored on this button's rect. Coalesced
        // inside KuronFx: batch completions never stack overlays.
        KuronFx.trigger(context, kind: KuronFxKind.progressComplete);
      },
      builder: (context, state) {
        if (state is! DownloadLoaded) {
          return _buildButton(
            context: context,
            icon: Icons.download,
            text: AppLocalizations.of(context)!.download,
            onPressed: null,
            color: colorScheme.tertiary,
          );
        }

        // Find download status for this content
        final download = state.downloads
            .where(
              (d) => ContentDownloadCache.matchesDownload(
                d,
                content.id,
                sourceId: content.sourceId,
              ),
            )
            .firstOrNull;

        if (download == null) {
          return FutureBuilder<bool>(
            future: ContentDownloadCache.isDownloaded(
              content.id,
              sourceId: content.sourceId,
              context: context,
            ),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return _buildButton(
                  context: context,
                  icon: Icons.check_circle,
                  text: AppLocalizations.of(context)!.downloaded('').trim(),
                  onPressed: () => context.read<DownloadBloc>().add(
                    const DownloadRefreshEvent(),
                  ),
                  color: colorScheme.tertiary,
                );
              }

              // Check if download feature is enabled for this source
              final remoteConfig = getIt<RemoteConfigService>();
              if (!remoteConfig.isFeatureEnabled(
                content.sourceId,
                (f) => f.download,
              )) {
                // Feature disabled and not downloaded -> Hide button
                return const SizedBox.shrink();
              }

              // Not downloaded, show download options with dropdown
              return _buildDownloadOptionsButton(context);
            },
          );
        }

        // Show status based on download state
        switch (download.state) {
          case DownloadState.queued:
            return _buildButton(
              context: context,
              icon: Icons.schedule,
              text: AppLocalizations.of(context)!.queued,
              onPressed: () => _cancelDownload(context),
              color: colorScheme.secondary,
            );

          case DownloadState.downloading:
            // If progress is 100%, show as completed even if state hasn't updated yet
            if (download.progressPercentage >= 100) {
              return _buildButton(
                context: context,
                icon: Icons.check_circle,
                text: AppLocalizations.of(context)!
                    .downloaded(download.formattedFileSize),
                onPressed: () => _openDownload(context),
                color: colorScheme.tertiary,
              );
            }
            return _buildProgressButton(
              context: context,
              download: download,
              onPressed: () => _pauseDownload(context),
            );

          case DownloadState.paused:
            return _buildButton(
              context: context,
              icon: Icons.play_arrow,
              text: AppLocalizations.of(context)!.resume,
              onPressed: () => _resumeDownload(context),
              color: colorScheme.primary,
              progress: download.progressPercentage / 100,
            );

          case DownloadState.completed:
            return _buildButton(
              context: context,
              icon: Icons.check_circle,
              text: AppLocalizations.of(context)!
                  .downloaded(download.formattedFileSize),
              onPressed: () => _openDownload(context),
              color: colorScheme.tertiary,
            );

          case DownloadState.failed:
            return _buildButton(
              context: context,
              icon: Icons.error,
              text: AppLocalizations.of(context)!.failed,
              onPressed: () => _retryDownload(context),
              color: colorScheme.error,
            );

          case DownloadState.cancelled:
            return _buildButton(
              context: context,
              icon: Icons.download,
              text: AppLocalizations.of(context)!.download,
              onPressed: () => _startDownload(context),
              color: colorScheme.tertiary,
            );
        }
      },
    );
    return KuronSquash(child: button);
  }

  Widget _buildButton({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    Color? color,
    double? progress,
  }) {
    final buttonColor = color ?? Theme.of(context).colorScheme.primary;

    switch (size) {
      case DownloadButtonSize.small:
        return _buildSmallButton(
          context: context,
          icon: icon,
          text: text,
          onPressed: onPressed,
          color: buttonColor,
          progress: progress,
        );

      case DownloadButtonSize.medium:
        return _buildMediumButton(
          context: context,
          icon: icon,
          text: text,
          onPressed: onPressed,
          color: buttonColor,
          progress: progress,
        );

      case DownloadButtonSize.large:
        return _buildLargeButton(
          context: context,
          icon: icon,
          text: text,
          onPressed: onPressed,
          color: buttonColor,
          progress: progress,
        );
    }
  }

  Widget _buildSmallButton({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    required Color color,
    double? progress,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          if (progress != null)
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              backgroundColor: color.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            color: color,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }

  Widget _buildMediumButton({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    required Color color,
    double? progress,
  }) {
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          if (progress != null)
            Positioned.fill(
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  color.withValues(alpha: 0.3),
                ),
              ),
            ),
          ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: showText ? Text(text) : const SizedBox.shrink(),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: EdgeInsets.symmetric(
                horizontal: showText ? 16 : 12,
                vertical: 8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeButton({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    required Color color,
    double? progress,
  }) {
    // For download state, use outlined style to match DetailScreen design
    final isDownloadButton = icon == Icons.download;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (progress != null)
            Positioned.fill(
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  color.withValues(alpha: 0.3),
                ),
              ),
            ),
          if (isDownloadButton)
            // Use outlined style for download button to match DetailScreen
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(
                text,
                maxLines: 1,
                style: TextStyleConst.buttonMedium.copyWith(color: color),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            )
          else
            // Use elevated style for other states
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(text, maxLines: 1, style: TextStyleConst.labelLarge),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressButton({
    required BuildContext context,
    required DownloadStatus download,
    required VoidCallback onPressed,
  }) {
    final progress = download.progressPercentage / 100;
    final isLarge = size == DownloadButtonSize.large;
    final buttonHeight = isLarge ? 48.0 : 40.0;

    // Use more vibrant colors for better visibility
    final progressColor = Theme.of(context).colorScheme.primary;
    final backgroundColor = progressColor.withValues(alpha: 0.15);
    final progressValueColor = progressColor.withValues(alpha: 0.8);

    return SizedBox(
      width: double.infinity,
      height: buttonHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Enhanced progress background with rounded corners
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isLarge ? 12 : 8),
                color: backgroundColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isLarge ? 12 : 8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(progressValueColor),
                  minHeight: buttonHeight,
                ),
              ),
            ),
          ),
          // Enhanced button with better styling
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isLarge ? 12 : 8),
              border: Border.all(
                color: progressColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(
                Icons.pause,
                size: isLarge ? 20 : 18,
                color: Colors.white,
              ),
              label: showText
                  ? Text(
                      '${download.progressPercentage.toInt()}%',
                      style: TextStyleConst.labelLarge.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: isLarge ? 16 : 14,
                      ),
                    )
                  : const SizedBox.shrink(),
              style: ElevatedButton.styleFrom(
                backgroundColor: progressColor,
                foregroundColor: Colors.white,
                elevation: DesignTokens.elevationMd,
                shadowColor: progressColor.withValues(alpha: 0.3),
                padding: EdgeInsets.symmetric(
                  horizontal: showText
                      ? (isLarge ? 24 : 16)
                      : (isLarge ? 16 : 12),
                  vertical: isLarge ? 12 : 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isLarge ? 12 : 8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startDownload(BuildContext context) {
    if (!_checkStorageAndProceed(context)) return;

    // External chapters (e.g. MangaDex externalUrl) cannot be downloaded.
    final chapters = content.chapters;
    if (chapters != null &&
        chapters.isNotEmpty &&
        chapters.every((c) => c.isExternal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.externalChapterDownloadBlocked,
          ),
        ),
      );
      return;
    }

    // Check if download feature is enabled
    final remoteConfig = getIt<RemoteConfigService>();
    if (!remoteConfig.isFeatureEnabled(content.sourceId, (f) => f.download)) {
      _showFeatureDisabledDialog(context);
      return;
    }

    context.read<DownloadBloc>().add(DownloadQueueEvent(content: content));
    context.read<DownloadBloc>().add(DownloadStartEvent(content.id));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: KuronSnackBarContent(
          child: Text(
            AppLocalizations.of(context)!.downloadStarted(content.title),
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _checkStorageAndProceed(BuildContext context) {
    final downloadBloc = context.read<DownloadBloc>();
    final state = downloadBloc.state;

    if (state is DownloadLoaded) {
      if (state.settings.customStorageRoot == null ||
          state.settings.customStorageRoot!.isEmpty) {
        _showStorageMissingPopup(context);
        return false;
      }
    }
    return true;
  }

  void _showStorageMissingPopup(BuildContext context) {
    final downloadBloc = context.read<DownloadBloc>();
    final state = downloadBloc.state;

    if (state is! DownloadLoaded) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.downloadError),
        content: Text(AppLocalizations.of(context)!.pleaseSetStorageLocation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSettingsDialog(context, state.settings);
            },
            child: Text(AppLocalizations.of(context)!.settings),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, DownloadSettings settings) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: DownloadSettingsWidget(
          settings: settings,
          onSettingsChanged: (newSettings) {
            context.read<DownloadBloc>().add(
              DownloadSettingsUpdateEvent(
                maxConcurrentDownloads: newSettings.maxConcurrentDownloads,
                imageQuality: newSettings.imageQuality,
                autoRetry: newSettings.autoRetry,
                retryAttempts: newSettings.retryAttempts,
                retryDelay: newSettings.retryDelay,
                timeoutDuration: newSettings.timeoutDuration,
                enableNotifications: newSettings.enableNotifications,
                wifiOnly: newSettings.wifiOnly,
                customStorageRoot: newSettings.customStorageRoot,
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFeatureDisabledDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.featureDisabledTitle),
        content: Text(l10n.downloadFeatureDisabled),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadOptionsButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remoteConfig = getIt<RemoteConfigService>();
    final rawConfig = remoteConfig.getRawConfig(content.sourceId);
    final ehentaiStrategies = EhentaiDownloadStrategyResolver.resolve(
      content,
      rawConfig: rawConfig,
    );

    if (ehentaiStrategies.isEmpty) {
      return _buildButton(
        context: context,
        icon: Icons.download,
        text: AppLocalizations.of(context)!.download,
        onPressed: () => _startDownload(context),
        color: colorScheme.tertiary,
      );
    }

    return _buildButton(
      context: context,
      icon: Icons.download,
      text: AppLocalizations.of(context)!.download,
      onPressed: () => _showDownloadOptionsSheet(
        context,
        ehentaiStrategies: ehentaiStrategies,
        colorScheme: colorScheme,
      ),
      color: colorScheme.tertiary,
    );
  }

  Future<void> _showDownloadOptionsSheet(
    BuildContext context, {
    required List<EhentaiDownloadStrategy> ehentaiStrategies,
    required ColorScheme colorScheme,
  }) async {
    if (ehentaiStrategies.length == 1 &&
        ehentaiStrategies.first.kind == EhentaiDownloadStrategyKind.partOnly) {
      _startDownload(context);
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  l10n.download,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              if (ehentaiStrategies.isNotEmpty)
                ...ehentaiStrategies.map(
                  (strategy) => ListTile(
                    leading: Icon(
                      strategy.isRange ? Icons.folder_open : Icons.download,
                      color: colorScheme.tertiary,
                    ),
                    title: Text(strategy.title),
                    subtitle: Text(strategy.description),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _handleEhentaiStrategy(context, strategy);
                    },
                  ),
                )
              else ...[
                ListTile(
                  leading: Icon(Icons.download, color: colorScheme.tertiary),
                  title: Text(l10n.downloadAll),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startDownload(context);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.folder_open, color: colorScheme.primary),
                  title: Text(l10n.downloadRange),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showRangeSelector(context, content);
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleEhentaiStrategy(
    BuildContext context,
    EhentaiDownloadStrategy strategy,
  ) async {
    switch (strategy.kind) {
      case EhentaiDownloadStrategyKind.wholeGallery:
      case EhentaiDownloadStrategyKind.partOnly:
        _startDownload(context);
        return;
      case EhentaiDownloadStrategyKind.galleryRange:
        final gL10n = AppLocalizations.of(context)!;
        _showRangeSelector(
          context,
          content,
          scopeTitle: gL10n.downloadGalleryWide,
          scopeDescription: gL10n.downloadGalleryWideDesc,
        );
        return;
      case EhentaiDownloadStrategyKind.partRange:
        return;
    }
  }

  void _showRangeSelector(
    BuildContext context,
    Content targetContent, {
    String? scopeTitle,
    String? scopeDescription,
  }) {
    showDialog(
      context: context,
      builder: (context) => DownloadRangeSelector(
        totalPages: targetContent.pageCount,
        contentTitle: targetContent.title,
        scopeTitle: scopeTitle,
        scopeDescription: scopeDescription,
        onRangeSelected: (startPage, endPage) {
          _startRangeDownload(context, targetContent, startPage, endPage);
        },
      ),
    );
  }

  void _startRangeDownload(
    BuildContext context,
    Content targetContent,
    int startPage,
    int endPage,
  ) {
    if (!_checkStorageAndProceed(context)) return;

    context.read<DownloadBloc>().add(
      DownloadRangeEvent(
        content: targetContent,
        startPage: startPage,
        endPage: endPage,
      ),
    );
    context.read<DownloadBloc>().add(DownloadStartEvent(targetContent.id));

    final pageText = startPage == endPage
        ? AppLocalizations.of(context)!.pageText(startPage)
        : AppLocalizations.of(context)!.pagesText(startPage, endPage);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: KuronSnackBarContent(
          child: Text(
            AppLocalizations.of(context)!
                .rangeDownloadStarted(targetContent.title, pageText),
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _pauseDownload(BuildContext context) {
    context.read<DownloadBloc>().add(DownloadPauseEvent(content.id));
  }

  void _resumeDownload(BuildContext context) {
    context.read<DownloadBloc>().add(DownloadStartEvent(content.id));
  }

  void _cancelDownload(BuildContext context) {
    context.read<DownloadBloc>().add(DownloadCancelEvent(content.id));
  }

  void _retryDownload(BuildContext context) {
    context.read<DownloadBloc>().add(DownloadRetryEvent(content.id));
  }

  void _openDownload(BuildContext context) {
    // Navigate to reader screen with the downloaded content
    AppRouter.goToReader(context, content.id);

    // Show confirmation that content is being opened
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.opening(content.title)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Size options for download button
enum DownloadButtonSize { small, medium, large }
