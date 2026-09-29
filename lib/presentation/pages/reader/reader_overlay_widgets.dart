part of 'reader_screen.dart';

// ───── Helper functions ─────

ReadingMode _getNextReadingMode(
  ReadingMode currentMode, {
  required bool disableContinuousScroll,
}) {
  if (!disableContinuousScroll) {
    switch (currentMode) {
      case ReadingMode.singlePage:
        return ReadingMode.verticalPage;
      case ReadingMode.verticalPage:
        return ReadingMode.continuousScroll;
      case ReadingMode.continuousScroll:
        return ReadingMode.singlePage;
    }
  }
  switch (currentMode) {
    case ReadingMode.singlePage:
      return ReadingMode.verticalPage;
    case ReadingMode.verticalPage:
      return ReadingMode.singlePage;
    case ReadingMode.continuousScroll:
      return ReadingMode.singlePage;
  }
}

IconData _getReadingModeIcon(ReadingMode mode) {
  switch (mode) {
    case ReadingMode.singlePage:
      return Icons.view_carousel;
    case ReadingMode.verticalPage:
      return Icons.view_agenda;
    case ReadingMode.continuousScroll:
      return Icons.view_stream;
  }
}

// ───── Failed page card ─────

class _FailedPageCard extends StatelessWidget {
  const _FailedPageCard({
    required this.pageNumber,
    this.canRetry = false,
    this.onRetry,
  });

  final int pageNumber;
  final bool canRetry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context)!.pageFailedDownload(pageNumber),
                style: TextStyleConst.titleSmall),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)!.tapToRetry,
                style: TextStyleConst.bodySmall),
            if (canRetry)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(AppLocalizations.of(context)!.retry),
                  onPressed: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───── Top bar ─────

enum _TopBarAction { keepScreenOn, settings, skipSfx, switchModel }

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.state,
    required this.onBack,
    required this.onToggleKeepScreenOn,
    required this.onOpenSettings,
    this.onTranslate,
    this.onToggleSkipSfx,
  });

  final ReaderState state;
  final VoidCallback onBack;
  final VoidCallback onToggleKeepScreenOn;
  final VoidCallback onOpenSettings;
  final VoidCallback? onTranslate;
  final VoidCallback? onToggleSkipSfx;

  @override
  Widget build(BuildContext context) {
    final kuron = Theme.of(context).extension<KuronColors>();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final glassBg =
        kuron?.readerBg.withValues(alpha: 1) ?? const Color(0xFF000000);
    final iconColor = isDark ? Colors.white : const Color(0xFF2E2722);
    final textColor = isDark ? Colors.white : const Color(0xFF2E2722);
    final subColor = isDark ? Colors.white60 : const Color(0xFF7A6E66);
    final colorScheme = Theme.of(context).colorScheme;
    final skipSfx = context.read<ReaderTranslationCubit>().skipSfx;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, color: iconColor),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.content?.getDisplayTitle() ??
                                AppLocalizations.of(context)?.loading ??
                                '',
                            style: TextStyleConst.headingMedium.copyWith(
                              color: textColor,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (state.isOfflineMode ?? false) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(DesignTokens.radiusSm),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.offline_bolt,
                                    size: 11, color: subColor),
                                const SizedBox(width: 2),
                                Text('offline',
                                    style: TextStyle(
                                        color: subColor, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (state.readingMode != ReadingMode.continuousScroll)
                      Text(
                        (state.currentPage ?? 1) >
                                (state.content?.pageCount ?? 1)
                            ? (AppLocalizations.of(context)?.chapterComplete ??
                                '')
                            : (AppLocalizations.of(context)?.pageOfPages(
                                    state.currentPage ?? 1,
                                    state.content?.pageCount ?? 1) ??
                                AppLocalizations.of(context)!.pageOfContent(
                                    state.currentPage ?? 1,
                                    state.content?.pageCount ?? 1)),
                        style: TextStyle(color: subColor, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (onTranslate != null)
                ReaderTranslationToolbar(
                  readingMode: state.readingMode ?? ReadingMode.singlePage,
                  onTranslate: onTranslate!,
                ),
              PopupMenuButton<_TopBarAction>(
                onSelected: (action) {
                  switch (action) {
                    case _TopBarAction.keepScreenOn:
                      onToggleKeepScreenOn();
                    case _TopBarAction.settings:
                      onOpenSettings();
                    case _TopBarAction.skipSfx:
                      onToggleSkipSfx?.call();
                    case _TopBarAction.switchModel:
                      showReaderModelSwitcherSheet(context);
                  }
                },
                icon: Icon(Icons.more_vert, color: subColor),
                iconSize: 20,
                tooltip: AppLocalizations.of(context)?.moreActions,
                color: kuron?.readerBg ?? const Color(0xFF000000),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _TopBarAction.keepScreenOn,
                    child: Row(
                      children: [
                        Icon(
                          (state.keepScreenOn ?? false)
                              ? Icons.screen_lock_portrait
                              : Icons.screen_lock_portrait_outlined,
                          size: 18,
                          color: (state.keepScreenOn ?? false)
                              ? colorScheme.primary
                              : subColor,
                        ),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.keepScreenOnLabel),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _TopBarAction.settings,
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 18, color: subColor),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.readerSettings),
                      ],
                    ),
                  ),
                  if (onTranslate != null)
                    PopupMenuItem(
                      value: _TopBarAction.skipSfx,
                      child: Row(
                        children: [
                          Icon(
                            skipSfx ? Icons.volume_off : Icons.volume_up,
                            size: 18,
                            color: skipSfx ? colorScheme.primary : subColor,
                          ),
                          const SizedBox(width: 12),
                          Text(skipSfx
                              ? AppLocalizations.of(context)!.aiSkipSfxOn
                              : AppLocalizations.of(context)!.aiSkipSfxOff),
                        ],
                      ),
                    ),
                  if (onTranslate != null)
                    PopupMenuItem(
                      value: _TopBarAction.switchModel,
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz, size: 18, color: subColor),
                          const SizedBox(width: 12),
                          Text(AppLocalizations.of(context)!.aiSwitchModel),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───── Bottom bar ─────

class _ReaderBottomBar extends StatefulWidget {
  const _ReaderBottomBar({
    required this.state,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onJumpToPage,
    required this.onChangeReadingMode,
    required this.disableContinuousScroll,
  });

  final ReaderState state;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onChangeReadingMode;
  final bool disableContinuousScroll;

  @override
  State<_ReaderBottomBar> createState() => _ReaderBottomBarState();
}

class _ReaderBottomBarState extends State<_ReaderBottomBar> {
  double? _sliderPreviewValue;

  @override
  Widget build(BuildContext context) {
    final isOnNavigationPage = (widget.state.currentPage ?? 1) >
        (widget.state.content?.pageCount ?? 1);
    // A page-less video chapter reports 0 pages; `clamp(1, 0)` throws
    // ArgumentError, so the slider works against a floor of 1.
    final totalPages = (widget.state.content?.pageCount ?? 1) < 1
        ? 1
        : widget.state.content!.pageCount;
    final currentPage = isOnNavigationPage
        ? totalPages
        : (widget.state.currentPage ?? 1).clamp(1, totalPages);
    final sliderValue = (_sliderPreviewValue ?? currentPage.toDouble())
        .clamp(1.0, totalPages.toDouble())
        .toDouble();
    final displayPage = sliderValue.round().clamp(1, totalPages);
    final kuron = Theme.of(context).extension<KuronColors>();
    final glassBg =
        kuron?.readerBg.withValues(alpha: 1) ?? const Color(0xFF000000);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.state.isFirstPage ? null : widget.onPrevPage,
                icon: Icon(
                  Icons.navigate_before,
                  color: widget.state.isFirstPage
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white,
                ),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: isOnNavigationPage
                    ? Center(
                        child: Text(
                          '$totalPages / $totalPages',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      )
                    : Row(
                        children: [
                          Text(
                            '$displayPage',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                trackHeight: 2.5,
                                activeTrackColor: Colors.white,
                                inactiveTrackColor:
                                    Colors.white.withValues(alpha: 0.25),
                                thumbColor: Colors.white,
                                overlayColor:
                                    Colors.white.withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: sliderValue,
                                min: 1,
                                max: totalPages
                                    .toDouble()
                                    .clamp(1, double.infinity),
                                onChanged: (v) {
                                  if (_sliderPreviewValue == v) return;
                                  setState(() {
                                    _sliderPreviewValue = v;
                                  });
                                },
                                onChangeEnd: (v) {
                                  final targetPage =
                                      v.round().clamp(1, totalPages);
                                  setState(() {
                                    _sliderPreviewValue = null;
                                  });
                                  if (targetPage != currentPage) {
                                    widget.onJumpToPage(targetPage);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$totalPages',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
              ),
              IconButton(
                onPressed: widget.onNextPage,
                icon: const Icon(Icons.navigate_next, color: Colors.white),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: widget.onChangeReadingMode,
                icon: Icon(
                  _getReadingModeIcon(
                      widget.state.readingMode ?? ReadingMode.singlePage),
                  color: Colors.white,
                ),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───── Animated UI overlay ─────

class _ReaderUIOverlay extends StatelessWidget {
  const _ReaderUIOverlay({
    required this.isVisible,
    required this.topBar,
    this.bottomBar,
  });

  final bool isVisible;
  final Widget topBar;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isVisible,
      child: SafeArea(
        child: Column(
          children: [
            AnimatedSlide(
              offset: isVisible ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: isVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: topBar,
              ),
            ),
            const Spacer(),
            if (bottomBar != null)
              AnimatedSlide(
                offset: isVisible ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: isVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: bottomBar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───── Floating page indicator ─────

class _ReaderFloatingPageIndicator extends StatelessWidget {
  const _ReaderFloatingPageIndicator({
    required this.scrollingNotifier,
    required this.visiblePageNotifier,
    required this.totalPages,
  });

  final ValueNotifier<bool> scrollingNotifier;
  final ValueNotifier<int> visiblePageNotifier;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    if (totalPages == 0) return const SizedBox.shrink();

    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: scrollingNotifier,
          builder: (context, isScrolling, _) {
            return AnimatedOpacity(
              opacity: isScrolling ? 1.0 : 0.0,
              duration: Duration(milliseconds: isScrolling ? 200 : 600),
              curve: Curves.easeOut,
              child: ValueListenableBuilder<int>(
                valueListenable: visiblePageNotifier,
                builder: (context, page, _) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .inverseSurface
                          .withValues(alpha: 0.85),
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radius2xl),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$page / $totalPages',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// ───── Mini chrome toggle ─────

class _ReaderMiniChromeToggle extends StatefulWidget {
  const _ReaderMiniChromeToggle({
    required this.isVisible,
    required this.onToggle,
  });

  final bool isVisible;
  final VoidCallback onToggle;

  @override
  State<_ReaderMiniChromeToggle> createState() =>
      _ReaderMiniChromeToggleState();
}

class _ReaderMiniChromeToggleState extends State<_ReaderMiniChromeToggle> {
  static const double _toggleSize = 40;
  Offset? _miniChromeToggleOffset;

  Offset _clampOffset(Offset offset, MediaQueryData mediaQuery) {
    const margin = 8.0;
    const minX = margin;
    final maxX = mediaQuery.size.width - _toggleSize - margin;
    final minY = mediaQuery.padding.top + margin;
    final maxY = mediaQuery.size.height -
        mediaQuery.padding.bottom -
        _toggleSize -
        margin;

    return Offset(
      offset.dx.clamp(minX, maxX),
      offset.dy.clamp(minY, maxY),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final defaultOffset = Offset(
      mediaQuery.size.width - _toggleSize - 12,
      mediaQuery.padding.top + 82,
    );
    final offset = _clampOffset(
      _miniChromeToggleOffset ?? defaultOffset,
      mediaQuery,
    );

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            final currentOffset = _miniChromeToggleOffset ?? offset;
            _miniChromeToggleOffset = _clampOffset(
              currentOffset + details.delta,
              MediaQuery.of(context),
            );
          });
        },
        child: AnimatedOpacity(
          opacity: widget.isVisible ? 0.55 : 0.9,
          duration: const Duration(milliseconds: 180),
          child: Material(
            color: Colors.transparent,
            child: Tooltip(
              message: widget.isVisible ? 'Hide controls' : 'Show controls',
              child: InkWell(
                borderRadius: BorderRadius.circular(_toggleSize / 2),
                onTap: widget.onToggle,
                child: Container(
                  width: _toggleSize,
                  height: _toggleSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          colorScheme.onInverseSurface.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isVisible
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.more_horiz_rounded,
                    size: 22,
                    color: colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
