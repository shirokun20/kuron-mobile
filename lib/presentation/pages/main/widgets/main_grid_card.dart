import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/presentation/widgets/animated_status_border_frame.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/presentation/widgets/content_list_widget.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/core/utils/app_animations.dart';
import 'package:nhasixapp/core/utils/relative_time_utils.dart';

// Grid card widget for 2-column layout with ripple effect
class MainGridCard extends StatefulWidget {
  const MainGridCard({
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
  State<MainGridCard> createState() => _MainGridCardState();
}

class _MainGridCardState extends State<MainGridCard> {
  // Once a content's cover has loaded, keep the Hero eligible across widget
  // rebuilds (home grid rebuilds often) so the flight works consistently.
  bool _imageReady = false;
  late Future<List<bool>> _statusFutures;

  Future<List<bool>> _resolveStatusFutures() {
    return Future.wait([
      ContentDownloadCache.isDownloaded(
        content.id,
        sourceId: content.sourceId,
        allowFilesystemFallback: false,
        context: context,
      ),
      ContentReadCache.readProgress(content)
          .then((progress) => progress != null && progress > 0),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _statusFutures = _resolveStatusFutures();
    _imageReady = AppHeroHelper.readyCoverContentIds.contains(content.id);
  }

  @override
  void didUpdateWidget(MainGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.id != widget.content.id) {
      _statusFutures = _resolveStatusFutures();
    }
  }

  Content get content => widget.content;
  VoidCallback get onTap => widget.onTap;
  bool get blurThumbnails => widget.blurThumbnails;
  bool get isBlacklisted => widget.isBlacklisted;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DownloadBloc, DownloadBlocState>(
      buildWhen: (previous, current) {
        if (previous.runtimeType != current.runtimeType) return true;
        DownloadStatus? entryOf(DownloadBlocState s) {
          if (s is! DownloadLoaded) return null;
          for (final d in s.downloads) {
            if (d.contentId == content.id) return d;
          }
          return null;
        }
        return entryOf(previous) != entryOf(current);
      },
      builder: (context, _) {
        return FutureBuilder<List<bool>>(
          future: _statusFutures,
          builder: (context, snapshot) {
            final results = snapshot.data;
            final isDownloaded =
                results != null && results.length > 1 && results[0];
            final isRead = results != null && results.length > 1 && results[1];
            final theme = Theme.of(context);
            const readGoldColor = AppColors.readGold;
            const downloadBorderColor = AppColors.success;
            final runningBorderColor =
                theme.colorScheme.onSurface.withValues(alpha: 0.1);
            final hasAnimatedBorder = isRead || isDownloaded;
            final borderColors = isRead && isDownloaded
                ? <Color>[
                    downloadBorderColor,
                    readGoldColor,
                    downloadBorderColor,
                    runningBorderColor
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
                  innerWidth: 2.5,
                  shadowColor: downloadBorderColor.withValues(alpha: 0.4),
                ),
              (false, true) => (
                  innerColor: readGoldColor,
                  innerWidth: 2.5,
                  shadowColor: readGoldColor.withValues(alpha: 0.4),
                ),
              _ => (
                  innerColor:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  innerWidth: 1.0,
                  shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
                ),
            };

            final innerCard = AspectRatio(
              aspectRatio: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: hasAnimatedBorder
                      ? Border.all(color: Colors.transparent, width: 0)
                      : Border.all(
                          color: borderStyle.innerColor,
                          width: borderStyle.innerWidth,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: borderStyle.shadowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover image with fallback to page 1 and optional blur
                      _buildImageWithBlur(
                        context: context,
                        coverUrl: content.coverUrl,
                        fallbackUrl: content.imageUrls.isNotEmpty
                            ? content.imageUrls.first
                            : null,
                      ),
                      if (isBlacklisted) _buildBlacklistedOverlay(context),
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
                              color: readGoldColor.withValues(alpha: 0.88),
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusMd),
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
                                  style: TextStyleConst.overline.copyWith(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Gradient overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.75),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Content info at bottom
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              content.getDisplayTitle(),
                              style: TextStyleConst.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Subtitle (Chapter info)
                            if (content.subTitle != null &&
                                content.subTitle!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                content.subTitle!,
                                style: TextStyleConst.overline.copyWith(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 9,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (content.pageCount > 1) ...[
                                  Icon(
                                    Icons.menu_book,
                                    size: 12,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${content.pageCount}',
                                    style: TextStyleConst.overline.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (content.language.isNotEmpty) ...[
                                  _LanguageFlag(
                                      language: content.language, theme: theme),
                                ],
                              ],
                            ),
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
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: 10,
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          label,
                                          style:
                                              TextStyleConst.overline.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontSize: 9,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // OFFLINE badge for downloaded items
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
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusMd),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.offline_bolt,
                                  size: 12,
                                  color: theme.colorScheme.onTertiary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'OFFLINE',
                                  style: TextStyleConst.overline.copyWith(
                                    color: theme.colorScheme.onTertiary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Ripple effect overlay (on top of everything)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onTap,
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusLg),
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
              ),
            );

            final card = !hasAnimatedBorder
                ? innerCard
                : AnimatedStatusBorderFrame(
                    colors: borderColors,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    strokeWidth: 1.2,
                    shadowColor: borderStyle.shadowColor,
                    child: innerCard,
                  );
            return RepaintBoundary(child: card);
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
    // transition falls back to the normal page transition (no placeholder
    // flying to the detail header).
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
      placeholder: const KuroThumbPlaceholder(),
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
                  placeholder: const KuroThumbPlaceholder(),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                    size: 14,
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

// Language flag widget — emoji + display name
class _LanguageFlag extends StatelessWidget {
  const _LanguageFlag({required this.language, required this.theme});
  final String language;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final lang = language.toLowerCase().trim();
    final svc = getIt<LanguageService>();
    final emoji = svc.flagEmoji(lang);
    final label = svc.displayName(lang);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Text(
        emoji != null ? '$emoji $label' : label,
        style: TextStyleConst.overline.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
