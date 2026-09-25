import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/constants/colors_const.dart' show AppColors, KuronColors;
import '../../core/constants/design_tokens.dart';
import '../../core/constants/text_style_const.dart';
import '../../core/utils/offline_content_manager.dart';
import '../models/content_group.dart';
import 'animated_status_border_frame.dart';
import 'progressive_image_widget.dart';

class ContentGroupCardWidget extends StatelessWidget {
  const ContentGroupCardWidget({
    super.key,
    required this.contentGroup,
    this.onTap,
    this.onLongPress,
    this.aspectRatio = 0.7,
    this.isListMode = false,
    this.hideOfflineIndicator = false,
  });

  final ContentGroup contentGroup;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double aspectRatio;
  final bool isListMode;
  final bool hideOfflineIndicator;

  @override
  Widget build(BuildContext context) {
    return isListMode ? _buildListMode(context) : _buildGridMode(context);
  }

  Widget _buildGridMode(BuildContext context) {
    final representative = contentGroup.representativeContent;
    final totalSizeStr =
        OfflineContentManager.formatStorageSize(contentGroup.totalSize);
    final theme = Theme.of(context);
    final readColor =
        theme.extension<KuronColors>()?.readGold ?? AppColors.readGold;
    const offlineColor = AppColors.brandCoral;
    final hasReadProgress = contentGroup.readProgress > 0;
    final isCompletedRead =
        contentGroup.isRead || contentGroup.readProgress >= 1;

    final innerCard = AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: hasReadProgress || hideOfflineIndicator
                ? Colors.transparent
                : offlineColor,
            width: hasReadProgress || hideOfflineIndicator ? 0 : 1.4,
          ),
          boxShadow: [
            if (hasReadProgress || !hideOfflineIndicator)
              BoxShadow(
                color: (hasReadProgress ? readColor : offlineColor)
                    .withValues(alpha: hasReadProgress ? 0.2 : 0.14),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ProgressiveThumbnailWidget(
                networkUrl: representative.coverUrl,
                contentId: representative.id,
                aspectRatio: aspectRatio,
                borderRadius: BorderRadius.zero,
                showOfflineIndicator: false,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
              ),
              if (!hideOfflineIndicator)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildStatusPill(
                    icon: Icons.download_done_rounded,
                    text: 'OFFLINE',
                    color: offlineColor.withValues(alpha: 0.9),
                    textColor: Colors.white,
                  ),
                ),
              if (hasReadProgress)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildStatusPill(
                    icon: Icons.menu_book_rounded,
                    text: isCompletedRead
                        ? 'READ'
                        : '${(contentGroup.readProgress * 100).toInt()}%',
                    color: readColor.withValues(alpha: 0.9),
                    textColor: Colors.white,
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contentGroup.baseTitle,
                      style: TextStyleConst.contentTitle.copyWith(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildBadge(
                          icon: Icons.library_books_rounded,
                          text: '${contentGroup.chapterCount} Ch',
                          color: Colors.white.withValues(alpha: 0.18),
                          textColor: Colors.white,
                        ),
                        _buildBadge(
                          text: representative.sourceId.toUpperCase(),
                          color: offlineColor.withValues(alpha: 0.82),
                          textColor: Colors.white,
                        ),
                        if (contentGroup.totalSize > 0)
                          _buildBadge(
                            icon: Icons.storage_rounded,
                            text: totalSizeStr,
                            color: Colors.black.withValues(alpha: 0.36),
                            textColor: Colors.white,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return _wrapGridCard(
      context,
      child: innerCard,
      hasReadProgress: hasReadProgress,
      readColor: readColor,
      offlineColor: offlineColor,
    );
  }

  Widget _buildListMode(BuildContext context) {
    final representative = contentGroup.representativeContent;
    final totalSizeStr =
        OfflineContentManager.formatStorageSize(contentGroup.totalSize);
    final theme = Theme.of(context);
    final readColor =
        theme.extension<KuronColors>()?.readGold ?? AppColors.readGold;
    const offlineColor = AppColors.brandCoral;
    final hasReadProgress = contentGroup.readProgress > 0;
    final isCompletedRead =
        contentGroup.isRead || contentGroup.readProgress >= 1;

    final innerCard = Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        border: Border.all(
          color: hasReadProgress || hideOfflineIndicator
              ? Colors.transparent
              : offlineColor,
          width: hasReadProgress || hideOfflineIndicator ? 0 : 1.2,
        ),
        boxShadow: [
          if (hasReadProgress || !hideOfflineIndicator)
            BoxShadow(
              color: (hasReadProgress ? readColor : offlineColor)
                  .withValues(alpha: hasReadProgress ? 0.16 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProgressiveThumbnailWidget(
                    networkUrl: representative.coverUrl,
                    contentId: representative.id,
                    aspectRatio: aspectRatio,
                    borderRadius: BorderRadius.zero,
                    showOfflineIndicator: false,
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!hideOfflineIndicator)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildStatusPill(
                        icon: Icons.download_done_rounded,
                        text: 'OFFLINE',
                        color: offlineColor.withValues(alpha: 0.9),
                        textColor: Colors.white,
                      ),
                    ),
                  if (hasReadProgress)
                    Positioned(
                      top: 38,
                      left: 8,
                      child: _buildStatusPill(
                        icon: Icons.menu_book_rounded,
                        text: isCompletedRead
                            ? 'READ'
                            : '${(contentGroup.readProgress * 100).toInt()}%',
                        color: readColor.withValues(alpha: 0.9),
                        textColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contentGroup.baseTitle,
                      style: TextStyleConst.contentTitle.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildBadge(
                          icon: Icons.library_books_rounded,
                          text: '${contentGroup.chapterCount} Ch',
                          color: theme.colorScheme.surfaceContainerHighest,
                          textColor: theme.colorScheme.onSurfaceVariant,
                        ),
                        _buildBadge(
                          text: representative.sourceId.toUpperCase(),
                          color: offlineColor.withValues(alpha: 0.14),
                          textColor: offlineColor,
                        ),
                        if (contentGroup.totalSize > 0)
                          _buildBadge(
                            icon: Icons.storage_rounded,
                            text: totalSizeStr,
                            color: theme.colorScheme.surfaceContainerHighest,
                            textColor: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (hasReadProgress) ...[
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusSm),
                        child: LinearProgressIndicator(
                          value: contentGroup.readProgress,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          color: readColor,
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${AppLocalizations.of(context)?.progress ?? 'Progress'}: ${(contentGroup.readProgress * 100).toInt()}%',
                        style: TextStyleConst.labelSmall.copyWith(
                          color: readColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return _wrapListCard(
      context,
      child: innerCard,
      hasReadProgress: hasReadProgress,
      readColor: readColor,
      offlineColor: offlineColor,
    );
  }

  Widget _wrapGridCard(
    BuildContext context, {
    required Widget child,
    required bool hasReadProgress,
    required Color readColor,
    required Color offlineColor,
  }) {
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: child,
      ),
    );

    if (!hasReadProgress) {
      return card;
    }

    final borderColors = hideOfflineIndicator
        ? <Color>[
            readColor,
            readColor.withValues(alpha: 0.4),
            readColor,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          ]
        : <Color>[
            offlineColor,
            readColor,
            offlineColor,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          ];

    return AnimatedStatusBorderFrame(
      colors: borderColors,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      strokeWidth: 1.2,
      shadowColor: readColor.withValues(alpha: 0.18),
      child: card,
    );
  }

  Widget _wrapListCard(
    BuildContext context, {
    required Widget child,
    required bool hasReadProgress,
    required Color readColor,
    required Color offlineColor,
  }) {
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        child: child,
      ),
    );

    if (!hasReadProgress) {
      return card;
    }

    final borderColors = hideOfflineIndicator
        ? <Color>[
            readColor,
            readColor.withValues(alpha: 0.4),
            readColor,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          ]
        : <Color>[
            offlineColor,
            readColor,
            offlineColor,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          ];

    return AnimatedStatusBorderFrame(
      colors: borderColors,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      strokeWidth: 1.2,
      shadowColor: readColor.withValues(alpha: 0.16),
      child: card,
    );
  }

  Widget _buildBadge({
    IconData? icon,
    required String text,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyleConst.labelSmall.copyWith(
              color: textColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    IconData? icon,
    required String text,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyleConst.overline.copyWith(
              color: textColor,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
