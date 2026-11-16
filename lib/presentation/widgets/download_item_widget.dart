import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';

import '../../core/constants/text_style_const.dart';
import '../../core/config/remote_config_service.dart';
import '../../domain/entities/entities.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/pdf_conversion_service.dart';
import '../../core/utils/download_storage_utils.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';

// Widget for displaying individual download item with progress and actions
class DownloadItemWidget extends StatelessWidget {
  const DownloadItemWidget({
    super.key,
    required this.download,
    this.onTap,
    this.onAction,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  final DownloadStatus download;
  final VoidCallback? onTap;
  final Function(String action)? onAction;
  final bool isSelectionMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and status
              Row(
                children: [
                  if (isSelectionMode) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        onTap?.call();
                      },
                      activeColor: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Source badge + Title
                        Row(
                          children: [
                            // Source badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getSourceColor(
                                    download.sourceId ?? SourceType.nhentai.id,
                                    colorScheme),
                                borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusSm),
                              ),
                              child: Text(
                                (download.sourceId ?? SourceType.nhentai.id)
                                    .toUpperCase(),
                                style: TextStyleConst.caption.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Title with fallback to metadata.json
                            Expanded(
                              child: _buildTitleWidget(context, colorScheme),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spaceXs),
                        // ID + Status
                        Row(
                          children: [
                            Text(
                              _getDisplayId(download),
                              style: TextStyleConst.caption.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyleConst.caption.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              download.statusText,
                              style: TextStyleConst.bodySmall.copyWith(
                                color: _getStatusColor(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isSelectionMode) _buildActionButton(context),
                ],
              ),

              const SizedBox(height: DesignTokens.spaceMd),

              // Progress bar
              if (download.totalPages > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: download.progress,
                        backgroundColor:
                            colorScheme.onSurface.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _getProgressColor(context)),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(download.progressPercentage > 100) ? '100' : download.progressPercentage}%',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceSm),
              ],

              // Details row
              Row(
                children: [
                  if (download.totalPages > 0) ...[
                    Icon(
                      Icons.photo_library_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _buildPagesText(context, download),
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  if (download.fileSize > 0) ...[
                    Icon(
                      Icons.storage_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      download.formattedFileSize,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  if (download.speed > 0) ...[
                    Icon(
                      Icons.speed_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      download.formattedSpeed,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // More actions button
                  IconButton(
                    onPressed: () => _showMoreActions(context),
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),

              // Error message if failed
              if (download.error != null) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          download.error!,
                          style: TextStyleConst.bodySmall.copyWith(
                            color: colorScheme.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ETA if downloading
              if (download.isInProgress &&
                  download.estimatedTimeRemaining != null) ...[
                const SizedBox(height: DesignTokens.spaceSm),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context)?.downloadEtaLabel(
                              _formatDuration(
                                  download.estimatedTimeRemaining!)) ??
                          'ETA: ${_formatDuration(download.estimatedTimeRemaining!)}',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    String action;

    switch (download.state) {
      case DownloadState.queued:
        icon = Icons.schedule;
        color = colorScheme.onSurface.withValues(alpha: 0.6);
        action = 'start';
        break;
      case DownloadState.downloading:
        // If progress is 100%, show as completed even if state hasn't updated yet
        if (download.progressPercentage >= 100) {
          icon = Icons.check_circle;
          color = colorScheme.tertiary;
          action = 'details';
        } else {
          icon = Icons.pause;
          color = colorScheme.primary;
          action = 'pause';
        }
        break;
      case DownloadState.paused:
        icon = Icons.play_arrow;
        color = colorScheme.primary;
        action = 'start';
        break;
      case DownloadState.completed:
        icon = Icons.check_circle;
        color = colorScheme.tertiary;
        action = 'details';
        break;
      case DownloadState.failed:
        icon = Icons.refresh;
        color = colorScheme.error;
        action = 'retry';
        break;
      case DownloadState.cancelled:
        icon = Icons.refresh;
        color = colorScheme.onSurface.withValues(alpha: 0.6);
        action = 'retry';
        break;
    }

    return IconButton(
      onPressed: () => onAction?.call(action),
      icon: Icon(icon, color: color),
      iconSize: 24,
    );
  }

  void _showMoreActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceLg),

            // Title
            Text(
              AppLocalizations.of(context)!.downloadActions,
              style: TextStyleConst.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceLg),

            // Actions
            if (download.canPause)
              _buildActionTile(
                context,
                icon: Icons.pause,
                title: AppLocalizations.of(context)?.downloadActionPause ??
                    AppLocalizations.of(context)!.pause,
                action: 'pause',
              ),

            if (download.canResume)
              _buildActionTile(
                context,
                icon: Icons.play_arrow,
                title: AppLocalizations.of(context)?.downloadActionResume ??
                    AppLocalizations.of(context)!.resume,
                action: 'start',
              ),

            if (download.canCancel)
              _buildActionTile(
                context,
                icon: Icons.cancel,
                title: AppLocalizations.of(context)?.downloadActionCancel ??
                    AppLocalizations.of(context)!.cancel,
                action: 'cancel',
                isDestructive: true,
              ),

            if (download.canRetry)
              _buildActionTile(
                context,
                icon: Icons.refresh,
                title: AppLocalizations.of(context)?.downloadActionRetry ??
                    AppLocalizations.of(context)!.retry,
                action: 'retry',
              ),

            // Add PDF conversion option for completed downloads
            // This allows users to convert downloaded images to PDF
            if (download.state == DownloadState.completed)
              _buildPdfActionTileIfEnabled(context),

            _buildActionTile(
              context,
              icon: Icons.info_outline,
              title: AppLocalizations.of(context)?.downloadActionDetails ??
                  AppLocalizations.of(context)!.details,
              action: 'details',
            ),

            _buildActionTile(
              context,
              icon: Icons.delete_outline,
              title: AppLocalizations.of(context)?.downloadActionRemove ??
                  AppLocalizations.of(context)!.remove,
              action: 'remove',
              isDestructive: true,
            ),

            const SizedBox(height: DesignTokens.spaceLg),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String action,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? colorScheme.error : colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: TextStyleConst.bodyMedium.copyWith(
          color: isDestructive ? colorScheme.error : colorScheme.onSurface,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop();
        onAction?.call(action);
      },
    );
  }

  Widget _buildPdfActionTileIfEnabled(BuildContext context) {
    try {
      final remoteConfig = GetIt.I<RemoteConfigService>();
      // Use sourceId from download, fallback to 'nhentai' if null
      final source = download.sourceId ?? SourceType.nhentai.id;

      final isEnabled =
          remoteConfig.isFeatureEnabled(source, (f) => f.generatePdf);

      if (!isEnabled) {
        return const SizedBox.shrink();
      }

      // Check if PDF already exists using FutureBuilder
      return FutureBuilder<bool>(
        future: GetIt.I<PdfConversionService>().isPdfExistForContent(
          download.contentId,
          sourceId: source,
        ),
        builder: (context, snapshot) {
          final pdfExists = snapshot.data ?? false;

          if (pdfExists) {
            return _buildActionTile(
              context,
              icon: Icons.picture_as_pdf,
              title: AppLocalizations.of(context)!.openPdf,
              action: 'open_pdf', // New action for opening PDF
            );
          }

          return _buildActionTile(
            context,
            icon: Icons.picture_as_pdf,
            title: AppLocalizations.of(context)?.downloadActionConvertToPdf ??
                AppLocalizations.of(context)!.convertToPdf,
            action: 'convert_pdf',
          );
        },
      );
    } catch (e) {
      // If config service not found or error, default to hidden for safety
      return const SizedBox.shrink();
    }
  }

  Color _getStatusColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (download.state) {
      case DownloadState.queued:
        return colorScheme.onSurface.withValues(alpha: 0.6);
      case DownloadState.downloading:
        // If progress is 100%, show success color even if state hasn't updated yet
        if (download.progressPercentage >= 100) {
          return colorScheme.tertiary;
        }
        return colorScheme.primary;
      case DownloadState.paused:
        return colorScheme.secondary;
      case DownloadState.completed:
        return colorScheme.tertiary;
      case DownloadState.failed:
        return colorScheme.error;
      case DownloadState.cancelled:
        return colorScheme.onSurface.withValues(alpha: 0.6);
    }
  }

  Color _getSourceColor(String sourceId, ColorScheme colorScheme) {
    try {
      final remoteConfig = GetIt.I<RemoteConfigService>();
      final config = remoteConfig.getConfig(sourceId.toLowerCase());

      if (config?.ui != null) {
        final hexColor = config!.ui!.activeColor.replaceFirst('#', '0xFF');
        return Color(int.parse(hexColor));
      }
    } catch (e) {
      // Fallback to default
    }

    return colorScheme.secondary;
  }

  // Build title widget - title is stored in database during download
  Widget _buildTitleWidget(BuildContext context, ColorScheme colorScheme) {
    return Text(
      download.title ?? download.contentId,
      style: TextStyleConst.titleMedium.copyWith(
        color: colorScheme.onSurface,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Color _getProgressColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (download.state) {
      case DownloadState.downloading:
        // If progress is 100%, show success color even if state hasn't updated yet
        if (download.progressPercentage >= 100) {
          return colorScheme.tertiary;
        }
        return colorScheme.primary;
      case DownloadState.paused:
        return colorScheme.secondary;
      case DownloadState.completed:
        return colorScheme.tertiary;
      case DownloadState.failed:
        return colorScheme.error;
      default:
        return colorScheme.onSurface.withValues(alpha: 0.3);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _buildPagesText(BuildContext context, DownloadStatus download) {
    if (download.isRangeDownload) {
      // For range downloads, show: "X/Y (Pages A-B of C)"
      return AppLocalizations.of(context)?.downloadPagesRangeFormat(
              download.downloadedPages,
              download.pagesToDownload,
              download.startPage ?? 1,
              download.endPage ?? download.totalPages,
              download.totalPages) ??
          '${download.downloadedPages}/${download.pagesToDownload} (Pages ${download.startPage ?? 1}-${download.endPage ?? download.totalPages} of ${download.totalPages})';
    } else {
      // For full downloads, show: "X/Y"
      return AppLocalizations.of(context)?.downloadPagesFormat(
              download.downloadedPages, download.totalPages) ??
          '${download.downloadedPages}/${download.totalPages}';
    }
  }

  // Get display ID string
  // Returns condensed ID for long slug-based IDs (like Crotpedia)
  String _getDisplayId(DownloadStatus download) {
    // For ALL sources, try to get a shorter "Elegant" ID if the original is too long
    // If it's already short (e.g. nhentai), getElegantId will return it as is.
    final elegantId = DownloadStorageUtils.getElegantId(download.contentId);
    return '#$elegantId';
  }
}
