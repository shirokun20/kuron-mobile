import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:kuron_core/kuron_core.dart';

import '../../../../core/constants/text_style_const.dart';
import '../../../../domain/entities/entities.dart';
import '../../../widgets/progressive_image_widget.dart';

// Widget for displaying individual history item
class HistoryItemWidget extends StatelessWidget {
  const HistoryItemWidget({
    super.key,
    required this.history,
    required this.onTap,
    this.onRemove,
    this.showRemoveButton = true,
    this.blurThumbnails = false,
    this.isBlurred = false,
  });

  final History history;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool showRemoveButton;
  final bool blurThumbnails;
  final bool isBlurred;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: DesignTokens.elevationMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Thumbnail
              _buildThumbnail(context),

              const SizedBox(width: 16),

              // Content info
              Expanded(child: _buildContentInfo(context)),

              // Actions
              if (showRemoveButton && onRemove != null) _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final thumbnailContent = history.coverUrl != null
        ? ProgressiveImageWidget(
            networkUrl: history.coverUrl!,
            width: 80,
            height: 120,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            httpHeaders: getIt<ContentSourceRegistry>()
                .getSource(history.sourceId)
                ?.getImageDownloadHeaders(imageUrl: history.coverUrl!),
          )
        : Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.image_not_supported,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 32,
            ),
          );

    Widget image = thumbnailContent;
    if (blurThumbnails) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: image,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: SizedBox(
        width: 80,
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (isBlurred) _buildBlacklistedThumbnailOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBlacklistedThumbnailOverlay(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.62),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                Icons.visibility_off_rounded,
                size: 14,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentInfo(BuildContext context) {
    final progressPercentage = history.totalPages > 0
        ? (history.lastPage / history.totalPages).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          history.title ?? AppLocalizations.of(context)!.unknownTitle,
          style: TextStyleConst.contentTitle.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 8),

        // Progress info
        Row(
          children: [
            Icon(
              Icons.menu_book,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context)!
                  .pageProgress(history.lastPage, history.totalPages),
              style: TextStyleConst.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (history.isCompleted) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.check_circle,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.readingCompleted,
                style: TextStyleConst.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 8),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: LinearProgressIndicator(
            value: progressPercentage,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              history.isCompleted
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.secondary,
            ),
            minHeight: 4,
          ),
        ),

        const SizedBox(height: 8),

        // Last viewed
        Text(
          _formatLastViewed(context, history.lastViewed),
          style: TextStyleConst.caption.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.8),
          ),
        ),

        // Time spent (if available)
        if (history.timeSpent.inMinutes > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
              Text(
                _formatTimeSpent(context, history.timeSpent),
                style: TextStyleConst.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        // Continue reading button
        IconButton(
          onPressed: onTap,
          icon: Icon(
            history.isCompleted ? Icons.replay : Icons.play_arrow,
            color: Theme.of(context).colorScheme.primary,
          ),
          tooltip: history.isCompleted
              ? AppLocalizations.of(context)!.readAgain
              : AppLocalizations.of(context)!.continueReading,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),

        const SizedBox(height: 8),

        // Remove button
        IconButton(
          onPressed: onRemove,
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: AppLocalizations.of(context)!.removeFromHistory,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ],
    );
  }

  String _formatLastViewed(BuildContext context, DateTime lastViewed) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final difference = now.difference(lastViewed);

    if (difference.inDays > 0) {
      return l10n.daysAgo(difference.inDays, difference.inDays == 1 ? '' : 's');
    } else if (difference.inHours > 0) {
      return l10n.hoursAgo(
        difference.inHours,
        difference.inHours == 1 ? '' : 's',
      );
    } else if (difference.inMinutes > 0) {
      return l10n.minutesAgo(
        difference.inMinutes,
        difference.inMinutes == 1 ? '' : 's',
      );
    } else {
      return l10n.justNow;
    }
  }

  String _formatTimeSpent(BuildContext context, Duration timeSpent) {
    final l10n = AppLocalizations.of(context)!;
    if (timeSpent.inHours > 0) {
      return '${timeSpent.inHours}h ${timeSpent.inMinutes % 60}m ${l10n.readingTime}';
    } else if (timeSpent.inMinutes > 0) {
      return '${timeSpent.inMinutes}m ${l10n.readingTime}';
    } else {
      return l10n.lessThanOneMinute;
    }
  }
}
