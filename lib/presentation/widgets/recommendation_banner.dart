import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';
import 'package:nhasixapp/presentation/widgets/recommendation_card.dart';

// Full-width hero banner carousel for home recommendations.
// Auto-advances every 5s, pauses while the user drags, manual swipe anytime.
// Title + reason sit ON the banner over a legibility scrim (plain black
// gradient — functional, not decorative).
class RecommendationBannerCarousel extends StatefulWidget {
  const RecommendationBannerCarousel({
    super.key,
    required this.items,
    required this.onTap,
    this.onDismiss,
    this.height = 200,
  }) : assert(items.length > 0, 'Use RecommendationRow for empty states');

  final List<Recommendation> items;
  final ValueChanged<Recommendation> onTap;
  final ValueChanged<Recommendation>? onDismiss;
  final double height;

  @override
  State<RecommendationBannerCarousel> createState() =>
      _RecommendationBannerCarouselState();
}

class _RecommendationBannerCarouselState
    extends State<RecommendationBannerCarousel>
    with SingleTickerProviderStateMixin {
  static const _autoPlayInterval = Duration(seconds: 5);
  static const _resumeDelay = Duration(seconds: 4);

  late final PageController _controller;
  late final AnimationController _progress;
  Timer? _autoPlay;
  Timer? _resume;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _progress = AnimationController(
      vsync: this,
      duration: _autoPlayInterval,
    );
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(RecommendationBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length && mounted) {
      if (_page >= widget.items.length) {
        _page = 0;
        _controller.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _autoPlay?.cancel();
    _resume?.cancel();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlay?.cancel();
    if (widget.items.length < 2) return;
    _progress.forward(from: 0);
    _autoPlay = Timer.periodic(_autoPlayInterval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pauseForInteraction() {
    _autoPlay?.cancel();
    _resume?.cancel();
    _resume = Timer(_resumeDelay, () {
      if (mounted) _startAutoPlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) {
          _autoPlay?.cancel();
          _resume?.cancel();
          _progress.stop();
        } else if (n is ScrollEndNotification) {
          _pauseForInteraction();
        }
        return false;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.height,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                _progress.forward(from: 0);
              },
              itemBuilder: (context, i) => _SlideFocus(
                controller: _controller,
                index: i,
                activePage: _page,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 16 : 4,
                    right: i == widget.items.length - 1 ? 16 : 4,
                  ),
                  child: _BannerSlide(
                    item: widget.items[i],
                    rank: i + 1,
                    onTap: () => widget.onTap(widget.items[i]),
                    onDismiss: widget.onDismiss == null
                        ? null
                        : () => widget.onDismiss!(widget.items[i]),
                  ),
                ),
              ),
            ),
          ),
          if (widget.items.length > 1) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AutoPlayProgress(
                key: const ValueKey('autoplay-progress'),
                progress: _progress,
              ),
            ),
          ],
          const SizedBox(height: 8),
          BannerDots(count: widget.items.length, active: _page),
        ],
      ),
    );
  }
}

/// Inactive slides shrink slightly and dim so the eye lands on the active
/// slide. Pure transform — no layout change, no extra raster cost.
class _SlideFocus extends StatelessWidget {
  const _SlideFocus({
    required this.controller,
    required this.index,
    required this.activePage,
    required this.child,
  });

  final PageController controller;
  final int index;
  final int activePage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        var delta = (index - activePage).abs().toDouble();
        if (controller.hasClients && controller.page != null) {
          delta = (controller.page! - index).abs().clamp(0.0, 1.0);
        }
        return Transform.scale(
          scale: 1.0 - 0.045 * delta,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (delta > 0.01)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22 * delta),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: child,
    );
  }
}

/// Thin autoplay countdown under the banner. Pauses while the user drags
/// (mirrors the autoplay timer), resets on every page change.
class _AutoPlayProgress extends StatelessWidget {
  const _AutoPlayProgress({super.key, required this.progress});

  final AnimationController progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(1),
        ),
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({
    required this.item,
    required this.rank,
    required this.onTap,
    this.onDismiss,
  });

  final Recommendation item;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final content = item.content;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        onTap: onTap,
        onLongPress: onDismiss == null ? null : () => _confirm(context, l10n),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (content != null)
                ProgressiveImageWidget(
                  networkUrl: content.coverUrl,
                  httpHeaders: getIt<ContentSourceRegistry>()
                      .getSource(content.sourceId)
                      ?.getImageDownloadHeaders(
                          imageUrl: content.coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 800,
                  memCacheHeight: 450,
                  placeholder: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_outlined,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                )
              else
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              // Legibility scrim (functional black gradient).
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color.fromRGBO(0, 0, 0, 0.55),
                      Color.fromRGBO(0, 0, 0, 0.88),
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              ),
              // Ghost rank number (Top-10 style): position info, doubles as
              // the slide's visual anchor. Outline only — never covers art.
              Positioned(
                top: 6,
                right: 12,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.5
                      ..color = Colors.white.withValues(alpha: 0.9),
                    shadows: const [
                      Shadow(
                        blurRadius: 8,
                        color: Color.fromRGBO(0, 0, 0, 0.45),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ReasonChip(item: item),
                    const SizedBox(height: 4),
                    Text(
                      content?.title ?? item.contentId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, AppLocalizations l10n) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text(l10n.notInterested),
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    if (confirmed == true) onDismiss?.call();
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.item});

  final Recommendation item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = RecommendationCard.shortTitle(
      item.contributorTitle.isNotEmpty
          ? item.contributorTitle
          : item.contentId,
    );
    final text = switch (item.contributorRelation) {
      RecommendationRelation.favorite =>
        l10n.recommendedReasonFavorite(title),
      RecommendationRelation.download =>
        l10n.recommendedReasonDownload(title),
      // Explore items show the origin source as the chip — the title
      // already appears below, so no "Jelajahi:" prefix is needed.
      RecommendationRelation.similar => item.sourceId,
      _ => l10n.recommendedReasonRead(title),
    };
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Dots indicator below the carousel (never over the art).
class BannerDots extends StatelessWidget {
  const BannerDots({
    super.key,
    required this.count,
    required this.active,
  });

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (count < 2) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}
