import 'package:flutter/material.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/utils/app_animations.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';

/// Two-pane detail layout for wide screens (>900dp: tablet landscape,
/// desktop/macOS). Same section widgets as the narrow single-column view,
/// only arranged differently:
///
/// - Left rail (draggable width, own scroll): cover card with the same Hero
///   tag as the narrow header + [infoWidgets] (title, metadata, synopsis,
///   tags, and the read/download buttons for gallery-type sources).
/// - Right pane (flex, constrained to 760dp): [contentWidgets] (chapter
///   section or action buttons, related, comments) on [rightScrollController]
///   so chapter auto-scroll keeps working.
///
/// Show-state only: no cubits, services, or navigation decisions in here.
/// The rail width is session-only state (not persisted).
class DetailWideView extends StatefulWidget {
  const DetailWideView({
    super.key,
    required this.rightScrollController,
    required this.isOfflineMode,
    required this.headerImageUrl,
    required this.contentId,
    required this.onBack,
    required this.onGoOnline,
    required this.appBarActions,
    required this.infoWidgets,
    required this.contentWidgets,
    this.pageNumber,
    this.imageHeaders,
    this.blurOverlay,
  });

  /// Breakpoint shared with the persistent sidebar rule (>900dp).
  static const double minWidth = 900;

  /// Max line length for the right pane (chapters/comments stay readable
  /// on very wide windows).
  static const double maxContentWidth = 760;

  static const double railWidth = 360;
  static const double minRailWidth = 280;
  static const double maxRailWidth = 560;

  final ScrollController rightScrollController;
  final bool isOfflineMode;
  final String headerImageUrl;
  final String contentId;
  final int? pageNumber;
  final Map<String, String>? imageHeaders;
  final Widget? blurOverlay;
  final VoidCallback onBack;
  final VoidCallback onGoOnline;
  final List<Widget> appBarActions;
  final List<Widget> infoWidgets;
  final List<Widget> contentWidgets;

  @override
  State<DetailWideView> createState() => _DetailWideViewState();
}

class _DetailWideViewState extends State<DetailWideView> {
  double _railWidth = DetailWideView.railWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Top safe area: keeps the bar clear of the Android status bar on
    // tablets (edge-to-edge). No-op on macOS windowed (padding is zero).
    return SafeArea(
      top: true,
      bottom: false,
      left: false,
      right: false,
      child: Column(
        children: [
          if (widget.isOfflineMode)
            Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.secondaryContainer,
            child: Row(
              children: [
                Icon(
                  Icons.wifi_off,
                  color: colorScheme.onSecondaryContainer,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.youAreOffline,
                    style: TextStyleConst.bodySmall.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onGoOnline,
                  child: Text(
                    l10n.goOnline,
                    style: TextStyleConst.labelMedium.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
                onPressed: widget.onBack,
              ),
              const Spacer(),
              ...widget.appBarActions,
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _railWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverCard(
                        headerImageUrl: widget.headerImageUrl,
                        contentId: widget.contentId,
                        pageNumber: widget.pageNumber,
                        imageHeaders: widget.imageHeaders,
                        blurOverlay: widget.blurOverlay,
                      ),
                      const SizedBox(height: DesignTokens.spaceLg),
                      ...widget.infoWidgets,
                    ],
                  ),
                ),
              ),
              _DragDivider(
                onDelta: (dx) => setState(() {
                  _railWidth = (_railWidth + dx).clamp(
                    DetailWideView.minRailWidth,
                    DetailWideView.maxRailWidth,
                  );
                }),
                onReset: () => setState(() {
                  _railWidth = DetailWideView.railWidth;
                }),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: widget.rightScrollController,
                  padding: const EdgeInsets.all(24),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DetailWideView.maxContentWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.contentWidgets,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    )
    );
  }
}

/// Draggable boundary between the info rail and the content pane.
/// Horizontal drag resizes the rail (clamped by the caller); double-tap
/// resets it. 9dp hit area, 1dp visible line, resize cursor on desktop.
class _DragDivider extends StatelessWidget {
  const _DragDivider({
    required this.onDelta,
    required this.onReset,
  });

  final ValueChanged<double> onDelta;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
        onDoubleTap: onReset,
        child: Container(
          width: 9,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            color: colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.headerImageUrl,
    required this.contentId,
    required this.pageNumber,
    required this.imageHeaders,
    required this.blurOverlay,
  });

  final String headerImageUrl;
  final String contentId;
  final int? pageNumber;
  final Map<String, String>? imageHeaders;
  final Widget? blurOverlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Same Hero tag as the narrow SliverAppBar header so the
              // flight from content cards always has a destination.
              AppHeroHelper.createImageHero(
                tag: 'content-cover-$contentId',
                image: ProgressiveImageWidget(
                  networkUrl: headerImageUrl,
                  contentId: contentId,
                  pageNumber: pageNumber,
                  isThumbnail: false,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  memCacheHeight: 800,
                  httpHeaders: imageHeaders,
                  placeholder: const KuroThumbPlaceholder(),
                  errorWidget: Container(
                    color: colorScheme.surfaceContainer,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              if (blurOverlay != null) blurOverlay!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading placeholder matching [DetailWideView]: cover shimmer left,
/// body shimmer right.
class DetailWideLoadingView extends StatelessWidget {
  const DetailWideLoadingView({
    super.key,
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget box(double h, double w) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return SafeArea(
      top: true,
      bottom: false,
      left: false,
      right: false,
      child: Column(
        children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
            onPressed: onBack,
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: DetailWideView.railWidth,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusXl,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      box(24, double.infinity),
                      const SizedBox(height: 12),
                      box(16, 180),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: colorScheme.outlineVariant),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(24, 220),
                      const SizedBox(height: 16),
                      ...List.generate(
                        5,
                        (_) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              box(16, 120),
                              const SizedBox(width: 16),
                              Expanded(child: box(16, double.infinity)),
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
        ),
      ],
    )
    );
  }
}
