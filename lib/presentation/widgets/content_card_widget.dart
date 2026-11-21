import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../core/constants/colors_const.dart' show AppColors, KuronColors;
import '../../core/constants/text_style_const.dart';

import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/core/utils/tag_color_palette.dart';
import 'package:kuron_core/kuron_core.dart';

import '../../l10n/app_localizations.dart';

import 'progressive_image_widget.dart';

import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

import 'highlighted_text_widget.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

// Enhanced content card widget with image caching and improved UI
///
// Usage:
// - Main screen: showUploadDate = false (default) - matches nhentai main page
// - Search/Browse: showUploadDate = true - shows when content was uploaded
// - Detail views: Can show tags, upload date, and other metadata
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.onLongPress,
    this.showFavoriteButton = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.showDownloadStatus = false,
    this.downloadProgress,
    this.aspectRatio = 0.7,
    this.showPageCount = true,
    this.showLanguageFlag = true,
    this.showTags = false,
    this.showUploadDate = false, // Hidden by default for main screen
    this.maxTagsToShow = 3,
    this.showOfflineIndicator = false,
    this.showDownloadBadge = false,
    this.isHighlighted = false, // NEW: for highlight matching content
    this.highlightReason, // NEW: reason for highlight
    this.blurThumbnails = false, // NEW: global blur setting
    this.isBlurred = false, // NEW: for blur excluded content
    this.offlineDownloadDate, // NEW: for offline screen - when content was downloaded
    this.offlineSize, // NEW: for offline screen - total file size
    this.highlightQuery, // NEW: for search highlighting
    this.preferStaticCover = false,
    this.readProgress, // NEW: 0.0 to 1.0 for history reading progress
    this.isNew = false, // NEW: red dot status for new updates
  });

  final Content content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showFavoriteButton;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final bool showDownloadStatus;
  final double? downloadProgress; // 0.0 to 1.0
  final double aspectRatio;
  final bool showPageCount;
  final bool showLanguageFlag;
  final bool showTags;
  final bool showUploadDate;
  final int maxTagsToShow;
  final bool showOfflineIndicator;
  final bool showDownloadBadge;
  final bool isHighlighted; // NEW: for highlight matching content
  final String? highlightReason; // NEW: reason for highlight
  final bool blurThumbnails; // NEW: global blur setting
  final bool isBlurred; // NEW: for blur excluded content
  final String?
  offlineDownloadDate; // NEW: formatted download date (e.g., "Nov 27, 2025")
  final String? offlineSize; // NEW: formatted file size (e.g., "45.2 MB")
  final String? highlightQuery; // NEW: text to highlight in title
  final bool preferStaticCover;
  final double? readProgress; // NEW: 0.0 to 1.0 for history reading progress
  final bool isNew; // NEW: red dot status for new updates

  @override
  Widget build(BuildContext context) {
    final kuronColors = Theme.of(context).extension<KuronColors>();
    final cardBorderColor = kuronColors?.cardBorder ?? AppColors.darkBorder;
    final gradientStart =
        kuronColors?.cardGradientStart ?? AppColors.darkGradientStart;
    final gradientEnd =
        kuronColors?.cardGradientEnd ?? AppColors.darkGradientEnd;
    final readGoldColor = kuronColors?.readGold ?? AppColors.readGold;
    final offlineColor = Theme.of(context).colorScheme.tertiary;
    final isRead = readProgress != null && readProgress! > 0;
    final isOffline = showDownloadBadge || showOfflineIndicator;
    final showHighlightBorder = isHighlighted && !isRead && !isOffline;
    BoxBorder? borderDecoration;
    if (isRead && isOffline) {
      borderDecoration = Border.all(color: Colors.transparent, width: 0);
    } else if (isRead) {
      borderDecoration = Border.all(color: readGoldColor, width: 1.5);
    } else if (isOffline) {
      borderDecoration = Border(
        left: BorderSide(color: offlineColor, width: 1.5),
      );
    } else if (showHighlightBorder) {
      borderDecoration = Border.all(color: AppColors.brandCoral, width: 1.5);
    } else {
      borderDecoration = Border.all(
        color: cardBorderColor,
        width: showHighlightBorder ? 1.5 : 1.0,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: borderDecoration,
      ),
      child: Stack(
        children: [
          if (isRead && isOffline)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildMixedStatusBorderOverlay(
                  readColor: readGoldColor,
                  offlineColor: offlineColor,
                ),
              ),
            ),
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            splashColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.1),
            highlightColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover image with overlay elements
                  Expanded(
                    flex: 3,
                    child: Stack(
                      children: [
                        // Main cover image
                        _buildCoverImage(),

                        ..._buildCoverStatusBadges(
                          context: context,
                          isRead: isRead,
                          isOffline: isOffline,
                        ),

                        // Download progress overlay
                        if (showDownloadStatus && downloadProgress != null)
                          _buildDownloadProgressOverlay(),

                        // Top overlay with favorite button, page count, and new indicator
                        if (content.pageCount > 0 || isNew) _buildTopOverlay(),

                        // Bottom gradient overlay for better text readability
                        _buildBottomGradientOverlay(),
                      ],
                    ),
                  ),

                  // Content info section
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          _buildTitle(),

                          const SizedBox(height: 4),

                          // Subtitle (chapter info for manga/webtoon)
                          if (content.subTitle != null &&
                              content.subTitle!.isNotEmpty)
                            _buildSubtitle(),

                          // Offline size (if available) - below title
                          if (offlineSize != null) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.storage,
                                  size: 11,
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  offlineSize!,
                                  style: TextStyleConst.labelSmall.copyWith(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                          ],

                          // Artist
                          if (content.artists.isNotEmpty) _buildArtist(),

                          // Tags (if enabled)
                          if (showTags && content.tags.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildTags(),
                          ],

                          const Spacer(),

                          // Bottom row with language flag and metadata
                          _buildBottomRow(),

                          if (readProgress != null && readProgress! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: readProgress,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                                minHeight: 3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMixedStatusBorderOverlay({
    required Color readColor,
    required Color offlineColor,
  }) {
    return _buildSegmentedStatusBorderOverlay(
      radius: DesignTokens.radiusXl,
      strokeWidth: 1.2,
      topColor: readColor,
      leftColor: offlineColor,
    );
  }

  Widget _buildSegmentedStatusBorderOverlay({
    required double radius,
    required double strokeWidth,
    Color? topColor,
    Color? rightColor,
    Color? bottomColor,
    Color? leftColor,
  }) {
    return CustomPaint(
      painter: _SegmentedStatusBorderPainter(
        radius: radius,
        strokeWidth: strokeWidth,
        topColor: topColor,
        rightColor: rightColor,
        bottomColor: bottomColor,
        leftColor: leftColor,
      ),
      child: const SizedBox.expand(),
    );
  }

  List<Widget> _buildCoverStatusBadges({
    required BuildContext context,
    required bool isRead,
    required bool isOffline,
  }) {
    if (!isRead && !isOffline) {
      return const [];
    }

    final readColor =
        Theme.of(context).extension<KuronColors>()?.readGold ??
        AppColors.readGold;
    final offlineColor = Theme.of(context).colorScheme.tertiary;
    final badges = <Widget>[];

    if (isOffline) {
      badges.add(
        Positioned(
          top: 8,
          left: 8,
          child: _buildBadgePill(
            context,
            icon: Icons.offline_bolt_rounded,
            label: (AppLocalizations.of(context)?.offline ?? 'OFFLINE')
                .toUpperCase(),
            color: offlineColor,
          ),
        ),
      );
    }

    if (isRead) {
      badges.add(
        Positioned(
          top: 8,
          right: 8,
          child: _buildBadgePill(
            context,
            icon: Icons.menu_book_rounded,
            label: 'READ',
            color: readColor,
          ),
        ),
      );
    }

    return badges;
  }

  Widget _buildCoverImage() {
    // Get headers for image request (needed for Crotpedia and other sources that require Referer)
    final source = getIt<ContentSourceRegistry>().getSource(content.sourceId);
    final headers = source?.getImageDownloadHeaders(imageUrl: content.coverUrl);

    return Builder(
      builder: (context) {
        Widget image = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: content.coverUrl.isNotEmpty
              ? ProgressiveThumbnailWidget(
                  networkUrl: content.coverUrl,
                  contentId: content.id,
                  aspectRatio: aspectRatio,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DesignTokens.radiusXl),
                  ),
                  showOfflineIndicator: false, // Disable to prevent duplicate with ContentCard's own indicator
                  httpHeaders: headers,
                  preferStaticPreview: preferStaticCover,
                )
              : _buildImageError(),
        );

        if (blurThumbnails) {
          image = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: image,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (isBlurred) _buildBlacklistedCoverOverlay(context),
          ],
        );
      },
    );
  }

  Widget _buildBlacklistedCoverOverlay(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.62),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_off_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'BLACKLISTED',
                    style: TextStyleConst.labelSmall.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageError() {
    return Builder(
      builder: (context) => Container(
        width: double.infinity,
        height: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.imageNotAvailable ??
                  AppLocalizations.of(context)!.imageNotAvailable,
              style: TextStyleConst.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgressOverlay() {
    return Positioned.fill(
      child: Builder(
        builder: (context) => Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                value: downloadProgress,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).colorScheme.outline,
                strokeWidth: 3,
              ),
              const SizedBox(height: 8),
              Text(
                '${(downloadProgress! * 100).toInt()}%',
                style: TextStyleConst.labelMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Builder(
        builder: (context) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left side badges
            Row(
              children: [
                // New update dot
                if (isNew)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                // Page count badge
                if (showPageCount && content.pageCount > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusLg,
                          ),
                        ),
                        child: Text(
                          '${content.pageCount}${AppLocalizations.of(context)?.pages ?? 'p'}',
                          style: TextStyleConst.labelSmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Favorite button
            if (showFavoriteButton)
              GestureDetector(
                onTap: onFavoriteToggle,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: isFavorite
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgePill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 10,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyleConst.labelSmall.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGradientOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 40,
      child: Builder(
        builder: (context) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Builder(
      builder: (context) {
        if (highlightQuery != null && highlightQuery!.isNotEmpty) {
          return HighlightedText(
            text: content.getDisplayTitle(),
            highlight: highlightQuery!,
            style: TextStyleConst.contentTitle.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Text(
          content.getDisplayTitle(),
          style: TextStyleConst.contentTitle.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Widget _buildSubtitle() {
    return Builder(
      builder: (context) => Text(
        content.subTitle!,
        style: TextStyleConst.contentSubtitle.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildArtist() {
    return Builder(
      builder: (context) => Text(
        content.artists.take(2).join(', '),
        style: TextStyleConst.contentSubtitle.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTags() {
    final visibleTags = content.tags.take(maxTagsToShow).toList();

    return Builder(
      builder: (context) => Wrap(
        spacing: 4,
        runSpacing: 2,
        children: visibleTags
            .map(
              (tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _getTagColor(context, tag.type).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(
                    color: _getTagColor(
                      context,
                      tag.type,
                    ).withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  tag.name,
                  style: TextStyleConst.contentTag.copyWith(
                    color: _getTagColor(context, tag.type),
                    fontSize: 9,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // Helper method to get theme-aware tag color based on tag type.
  Color _getTagColor(BuildContext context, String tagType) {
    return TagColorPalette.resolve(
      tagType,
      brightness: Theme.of(context).brightness,
    );
  }

  Widget _buildBottomRow() {
    return Builder(
      builder: (context) {
        return Row(
          children: [
            // Upload date (only show if enabled)
            if (showUploadDate)
              Builder(
                builder: (context) => Text(
                  _formatUploadDate(content.uploadDate, context),
                  style: TextStyleConst.caption.copyWith(fontSize: 10),
                ),
              ),

            // Download date for offline content (only show if provided)
            if (offlineDownloadDate != null)
              Builder(
                builder: (context) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_done,
                      size: 10,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      offlineDownloadDate!,
                      style: TextStyleConst.caption.copyWith(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // Downloaded indicator icon
            if (isHighlighted) ...[
              const Icon(
                Icons.offline_pin,
                size: 14,
                color: AppColors.brandCoral,
              ),
              const SizedBox(width: 4),
            ],

            // Language flag
            if (showLanguageFlag && content.language.isNotEmpty)
              _buildLanguageFlag(),
          ],
        );
      },
    );
  }

  Widget _buildLanguageFlag() {
    return Builder(
      builder: (context) {
        final languageService = getIt<LanguageService>();
        final normalizedLanguage = content.language.toLowerCase().trim();
        final hasLanguage =
            normalizedLanguage.isNotEmpty && normalizedLanguage != 'unknown';
        final flagEmoji = hasLanguage
            ? languageService.flagEmoji(normalizedLanguage)
            : null;
        final languageBadge = hasLanguage
            ? (normalizedLanguage.length >= 2
                  ? normalizedLanguage.substring(0, 2).toUpperCase()
                  : normalizedLanguage.toUpperCase())
            : '--';
        final languageLabel = hasLanguage
            ? languageService.displayName(normalizedLanguage)
            : content.language;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${flagEmoji ?? languageBadge} $languageLabel',
              style: TextStyleConst.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.8),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatUploadDate(DateTime date, BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(date);
    final loc = AppLocalizations.of(context)!;

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return loc.yearAgo(years, years > 1 ? 's' : '');
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return loc.monthAgo(months, months > 1 ? 's' : '');
    } else if (difference.inDays > 0) {
      return loc.daysAgo(difference.inDays, difference.inDays == 1 ? '' : 's');
    } else if (difference.inHours > 0) {
      return loc.hoursAgo(
        difference.inHours,
        difference.inHours == 1 ? '' : 's',
      );
    } else {
      return loc.justNow;
    }
  }

  // Static method to build image widget for reuse in other components
  static Widget buildImage({
    required String imageUrl,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    int? memCacheWidth,
    int? memCacheHeight,
    Map<String, String>? httpHeaders,
    required BuildContext context,
  }) {
    if (imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.noImage ?? 'No image',
              style: TextStyleConst.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ProgressiveImageWidget(
      networkUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth ?? 400,
      memCacheHeight: memCacheHeight ?? 600,
      httpHeaders: httpHeaders,
      placeholder: const KuroThumbPlaceholder(),
      errorWidget: Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.failedToLoad,
              style: TextStyleConst.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedStatusBorderPainter extends CustomPainter {
  const _SegmentedStatusBorderPainter({
    required this.radius,
    required this.strokeWidth,
    this.topColor,
    this.rightColor,
    this.bottomColor,
    this.leftColor,
  });

  final double radius;
  final double strokeWidth;
  final Color? topColor;
  final Color? rightColor;
  final Color? bottomColor;
  final Color? leftColor;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;
    final cornerRadius = math.max(0.0, radius - inset);

    Paint paintFor(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    Rect cornerRect(double x, double y) =>
        Rect.fromLTWH(x, y, cornerRadius * 2, cornerRadius * 2);

    void drawLine(Color? color, Offset start, Offset end) {
      if (color == null) return;
      canvas.drawLine(start, end, paintFor(color));
    }

    void drawArc(
      Color? color,
      Rect rect,
      double startAngle,
      double sweepAngle,
    ) {
      if (color == null || cornerRadius <= 0) return;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paintFor(color));
    }

    final topLeftRect = cornerRect(left, top);
    final topRightRect = cornerRect(right - cornerRadius * 2, top);
    final bottomRightRect = cornerRect(
      right - cornerRadius * 2,
      bottom - cornerRadius * 2,
    );
    final bottomLeftRect = cornerRect(left, bottom - cornerRadius * 2);

    drawArc(topColor, topLeftRect, math.pi, -math.pi / 2);
    drawLine(
      topColor,
      Offset(left + cornerRadius, top),
      Offset(right - cornerRadius, top),
    );
    drawArc(topColor, topRightRect, -math.pi / 2, math.pi / 2);

    drawArc(rightColor, topRightRect, -math.pi / 2, math.pi / 2);
    drawLine(
      rightColor,
      Offset(right, top + cornerRadius),
      Offset(right, bottom - cornerRadius),
    );
    drawArc(rightColor, bottomRightRect, 0, math.pi / 2);

    drawArc(bottomColor, bottomRightRect, 0, math.pi / 2);
    drawLine(
      bottomColor,
      Offset(right - cornerRadius, bottom),
      Offset(left + cornerRadius, bottom),
    );
    drawArc(bottomColor, bottomLeftRect, math.pi / 2, math.pi / 2);

    drawArc(leftColor, topLeftRect, -math.pi / 2, -math.pi / 2);
    drawLine(
      leftColor,
      Offset(left, top + cornerRadius),
      Offset(left, bottom - cornerRadius),
    );
    drawArc(leftColor, bottomLeftRect, math.pi, -math.pi / 2);
  }

  @override
  bool shouldRepaint(covariant _SegmentedStatusBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.topColor != topColor ||
        oldDelegate.rightColor != rightColor ||
        oldDelegate.bottomColor != bottomColor ||
        oldDelegate.leftColor != leftColor;
  }
}

// Compact content card for list views
class CompactContentCard extends StatelessWidget {
  const CompactContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.showFavoriteButton = false,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  final Content content;
  final VoidCallback? onTap;
  final bool showFavoriteButton;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final kuronColors = Theme.of(context).extension<KuronColors>();
    final gradientStart =
        kuronColors?.cardGradientStart ?? AppColors.darkGradientStart;
    final gradientEnd =
        kuronColors?.cardGradientEnd ?? AppColors.darkGradientEnd;
    final cardBorder = kuronColors?.cardBorder ?? AppColors.darkBorder;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                child: SizedBox(
                  width: 60,
                  height: 80,
                  child: ProgressiveImageWidget(
                    networkUrl: content.coverUrl,
                    httpHeaders: getIt<ContentSourceRegistry>()
                        .getSource(content.sourceId)
                        ?.getImageDownloadHeaders(imageUrl: content.coverUrl),
                    fit: BoxFit.cover,
                    width: 60,
                    height: 80,
                    placeholder: const KuroThumbPlaceholder(),
                    errorWidget: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
                    memCacheWidth: 120,
                    memCacheHeight: 160,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Content info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.getDisplayTitle(),
                      style: TextStyleConst.headingSmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (content.artists.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        content.artists.join(', '),
                        style: TextStyleConst.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${content.pageCount} ${AppLocalizations.of(context)?.pages ?? 'pages'}',
                          style: TextStyleConst.caption.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (content.language.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusSm,
                              ),
                            ),
                            child: Text(
                              content.language.toUpperCase(),
                              style: TextStyleConst.labelSmall.copyWith(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite button
              if (showFavoriteButton)
                IconButton(
                  onPressed: onFavoriteToggle,
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
