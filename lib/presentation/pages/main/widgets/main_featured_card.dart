import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/constants/colors_const.dart'
    show AppColors, KuronColors;

import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/widgets/animated_status_border_frame.dart';
import 'package:nhasixapp/presentation/widgets/content_list_widget.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/core/utils/app_animations.dart';
import 'package:nhasixapp/core/utils/relative_time_utils.dart';
import 'package:kuron_core/kuron_core.dart';

// Horizontal featured card widget: Image left (40%), Content info right (60%)
class MainFeaturedCard extends StatefulWidget {
  const MainFeaturedCard({
    super.key,
    required this.content,
    required this.onTap,
    this.blurThumbnails = false,
    this.isBlacklisted = false,
  });

  final Content content;
  final VoidCallback onTap;
  final bool blurThumbnails;
  final bool isBlacklisted;

  @override
  State<MainFeaturedCard> createState() => _MainFeaturedCardState();
}

class _MainFeaturedCardState extends State<MainFeaturedCard> {
  // Once a content's cover has loaded, keep the Hero eligible across widget
  // rebuilds (home grid rebuilds often) so the flight works consistently.
  bool _imageReady = false;

  @override
  void initState() {
    super.initState();
    _imageReady = AppHeroHelper.readyCoverContentIds.contains(content.id);
  }

  Content get content => widget.content;
  VoidCallback get onTap => widget.onTap;
  bool get blurThumbnails => widget.blurThumbnails;
  bool get isBlacklisted => widget.isBlacklisted;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DownloadBloc, DownloadBlocState>(
      buildWhen: (previous, current) =>
          previous.runtimeType != current.runtimeType ||
          previous.lastUpdated != current.lastUpdated,
      builder: (context, _) {
        return FutureBuilder<bool>(
          future: ContentDownloadCache.isDownloaded(
            content.id,
            sourceId: content.sourceId,
            allowFilesystemFallback: false,
            context: context,
          ),
          builder: (context, snapshot) {
            final isDownloaded = snapshot.data ?? false;
            return FutureBuilder<bool>(
              future: ContentReadCache.readProgress(content)
                  .then((progress) => progress != null && progress > 0),
              builder: (context, readSnapshot) {
                final isRead = readSnapshot.data ?? false;
                final theme = Theme.of(context);
                final kuronColors = theme.extension<KuronColors>();
                final gradientStart = kuronColors?.cardGradientStart ??
                    AppColors.darkGradientStart;
                final gradientEnd =
                    kuronColors?.cardGradientEnd ?? AppColors.darkGradientEnd;
                final cardBorder =
                    kuronColors?.cardBorder ?? AppColors.darkBorder;
                const downloadBorderColor = AppColors.brandCoral;
                final runningBorderColor =
                    theme.colorScheme.onSurface.withValues(alpha: 0.1);
                final readGoldColor =
                    kuronColors?.readGold ?? AppColors.readGold;
                final hasAnimatedBorder = isRead || isDownloaded;
                final borderColors = isRead && isDownloaded
                    ? <Color>[
                        downloadBorderColor,
                        readGoldColor,
                        downloadBorderColor,
                        runningBorderColor,
                      ]
                    : isRead
                        ? <Color>[readGoldColor]
                        : <Color>[downloadBorderColor];
                final borderStyle = switch ((isDownloaded, isRead)) {
                  (true, true) => (
                      innerColor: readGoldColor,
                      innerWidth: 2.2,
                      shadowColor: readGoldColor.withValues(alpha: 0.18),
                    ),
                  (true, false) => (
                      innerColor: downloadBorderColor,
                      innerWidth: 2.0,
                      shadowColor: downloadBorderColor.withValues(alpha: 0.25),
                    ),
                  (false, true) => (
                      innerColor: readGoldColor,
                      innerWidth: 2.0,
                      shadowColor: readGoldColor.withValues(alpha: 0.25),
                    ),
                  _ => (
                      innerColor: cardBorder,
                      innerWidth: 1.5,
                      shadowColor: cardBorder.withValues(alpha: 0.08),
                    ),
                };

                final innerCard = Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [gradientStart, gradientEnd],
                    ),
                    border: hasAnimatedBorder
                        ? Border.all(color: Colors.transparent, width: 0)
                        : Border.all(
                            color: borderStyle.innerColor,
                            width: borderStyle.innerWidth,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: borderStyle.shadowColor,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                    child: Stack(
                      children: [
                        // Main content Row
                        Row(
                          children: [
                            // Cover Image (Left side - 40% width)
                            Expanded(
                              flex: 4,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildImageWithBlur(
                                    context: context,
                                    coverUrl: content.coverUrl,
                                    fallbackUrl: content.imageUrls.isNotEmpty
                                        ? content.imageUrls.first
                                        : null,
                                  ),
                                  if (isBlacklisted)
                                    _buildBlacklistedOverlay(context),
                                  if (isRead)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: readGoldColor.withValues(
                                            alpha: 0.88,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            DesignTokens.radiusMd,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.menu_book_rounded,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'READ',
                                              style: TextStyleConst.overline
                                                  .copyWith(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // Page count badge
                                  if (content.pageCount > 0)
                                    Positioned(
                                      bottom: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.7),
                                          borderRadius: BorderRadius.circular(
                                              DesignTokens.radiusMd),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.photo_library_outlined,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${content.pageCount}',
                                              style: TextStyleConst.labelSmall
                                                  .copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // OFFLINE badge
                                  if (isDownloaded)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.tertiary
                                              .withValues(alpha: 0.9),
                                          borderRadius: BorderRadius.circular(
                                              DesignTokens.radiusMd),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.offline_bolt,
                                              size: 12,
                                              color:
                                                  theme.colorScheme.onTertiary,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'OFFLINE',
                                              style: TextStyleConst.overline
                                                  .copyWith(
                                                color: theme
                                                    .colorScheme.onTertiary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Content Info (Right side - 60% width)
                            Expanded(
                              flex: 6,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      gradientStart,
                                      gradientEnd,
                                    ],
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title
                                    Text(
                                      content.getDisplayTitle(),
                                      style:
                                          TextStyleConst.headingSmall.copyWith(
                                        color: theme.colorScheme.onSurface,
                                        fontSize: 15,
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    // Subtitle (Chapter info)
                                    if (content.subTitle != null &&
                                        content.subTitle!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        content.subTitle!,
                                        style:
                                            TextStyleConst.labelSmall.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                          fontSize: 10,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    // Artists
                                    if (content.artists.isNotEmpty)
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.brush_rounded,
                                            size: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              content.artists
                                                  .take(2)
                                                  .join(', '),
                                              style: TextStyleConst.bodySmall
                                                  .copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    const Spacer(),
                                    // Genre/Tags preview
                                    if (content.tags.isNotEmpty) ...[
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children:
                                            content.tags.take(3).map((tag) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme.primaryContainer
                                                  .withValues(alpha: 0.5),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              tag.name,
                                              style: TextStyleConst.labelSmall
                                                  .copyWith(
                                                color: theme.colorScheme
                                                    .onPrimaryContainer,
                                                fontSize: 10,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    // Last update / release time (hidden when epoch/future)
                                    Builder(
                                      builder: (context) {
                                        final label = RelativeTimeUtils.format(
                                          content.uploadDate,
                                          context,
                                        );
                                        if (label == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.schedule,
                                                size: 10,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.7),
                                              ),
                                              const SizedBox(width: 3),
                                              Flexible(
                                                child: Text(
                                                  label,
                                                  style: TextStyleConst
                                                      .labelSmall
                                                      .copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant
                                                        .withValues(alpha: 0.7),
                                                    fontSize: 10,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    // Language flag
                                    Row(
                                      children: [
                                        Builder(builder: (context) {
                                          final langSvc =
                                              getIt<LanguageService>();
                                          final normLang = content.language
                                              .toLowerCase()
                                              .trim();
                                          final hasLang = normLang.isNotEmpty &&
                                              normLang != 'unknown';
                                          final emoji = hasLang
                                              ? langSvc.flagEmoji(normLang)
                                              : null;
                                          final languageBadge = hasLang
                                              ? (normLang.length >= 2
                                                  ? normLang
                                                      .substring(0, 2)
                                                      .toUpperCase()
                                                  : normLang.toUpperCase())
                                              : '--';
                                          final label = hasLang
                                              ? langSvc.displayName(normLang)
                                              : content.language;

                                          return Text(
                                            '${emoji ?? languageBadge} $label',
                                            style: TextStyleConst.labelSmall
                                                .copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Ripple effect overlay (on top of everything)
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onTap,
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusXl),
                              splashColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.3),
                              highlightColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (!hasAnimatedBorder) {
                  return innerCard;
                }

                return AnimatedStatusBorderFrame(
                  colors: borderColors,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                  strokeWidth: 1.2,
                  shadowColor: borderStyle.shadowColor,
                  child: innerCard,
                );
              },
            );
          },
        );
      },
    );
  }

  // Build image with optional blur effect
  Widget _buildImageWithBlur({
    required BuildContext context,
    required String coverUrl,
    String? fallbackUrl,
  }) {
    final image = _buildCachedImage(
      context: context,
      coverUrl: coverUrl,
      fallbackUrl: fallbackUrl,
    );

    // Hero flight only when the primary image has loaded — otherwise the
    // transition falls back to the normal page transition.
    final heroImage = _imageReady
        ? AppHeroHelper.createImageHero(
            tag: 'content-cover-${content.id}',
            image: image,
          )
        : image;

    if (blurThumbnails) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: heroImage,
        ),
      );
    }

    return heroImage;
  }

  // Build cached image with fallback to first page if cover fails
  Widget _buildCachedImage({
    required BuildContext context,
    required String coverUrl,
    String? fallbackUrl,
  }) {
    return ProgressiveImageWidget(
      networkUrl: coverUrl,
      onImageLoaded: () {
        // frameBuilder fires during the Image build phase — defer the
        // setState so we never call markNeedsBuild mid-build.
        AppHeroHelper.readyCoverContentIds.add(content.id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _imageReady = true);
          }
        });
      },
      httpHeaders: getIt<ContentSourceRegistry>()
          .getSource(content.sourceId)
          ?.getImageDownloadHeaders(imageUrl: coverUrl),
      fit: BoxFit.cover,
      memCacheWidth: 400,
      memCacheHeight: 600,
      placeholder: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 40,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.5),
          ),
        ),
      ),
      errorWidget:
          // Try fallback URL if available
          (fallbackUrl != null && fallbackUrl != coverUrl)
              ? ProgressiveImageWidget(
                  networkUrl: fallbackUrl,
                  httpHeaders: getIt<ContentSourceRegistry>()
                      .getSource(content.sourceId)
                      ?.getImageDownloadHeaders(imageUrl: fallbackUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  memCacheHeight: 600,
                  placeholder: Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  errorWidget: _buildErrorPlaceholder(context),
                )
              : _buildErrorPlaceholder(context),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildBlacklistedOverlay(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.64),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.92),
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
}
