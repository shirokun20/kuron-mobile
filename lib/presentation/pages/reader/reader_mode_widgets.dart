part of 'reader_screen.dart';

// ───── _PaginatedTapWrapper ─────

class _PaginatedTapWrapper extends StatefulWidget {
  const _PaginatedTapWrapper({
    required this.child,
    required this.state,
    required this.cubit,
  });

  final Widget child;
  final ReaderState state;
  final ReaderCubit cubit;

  @override
  State<_PaginatedTapWrapper> createState() => _PaginatedTapWrapperState();
}

class _PaginatedTapWrapperState extends State<_PaginatedTapWrapper> {
  Offset _tapDownPosition = Offset.zero;
  DateTime _tapDownTime = DateTime.now();

  bool _isNextTap(double tapX, double screenWidth, TapDirection tapDirection) {
    final isRightSide = tapX > screenWidth * 0.7;
    return tapDirection == TapDirection.inverted ? !isRightSide : isRightSide;
  }

  bool _isPrevTap(double tapX, double screenWidth, TapDirection tapDirection) {
    final isLeftSide = tapX < screenWidth * 0.3;
    return tapDirection == TapDirection.inverted ? !isLeftSide : isLeftSide;
  }

  bool _isTapInsideChrome(Offset position) {
    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return position.dy <= topInset + 64 ||
        position.dy >= size.height - bottomInset - 76;
  }

  void _handlePaginatedTap(Offset position) {
    final state = widget.state;
    final cubit = widget.cubit;
    final tapDir = state.tapDirection ?? TapDirection.normal;
    final mode = state.readingMode ?? ReadingMode.singlePage;

    if (mode == ReadingMode.verticalPage) {
      final screenHeight = MediaQuery.of(context).size.height;
      final isTopArea = position.dy < screenHeight * 0.3;
      final isBottomArea = position.dy > screenHeight * 0.7;
      final prevArea =
          tapDir == TapDirection.inverted ? isBottomArea : isTopArea;
      final nextArea =
          tapDir == TapDirection.inverted ? isTopArea : isBottomArea;

      if (prevArea) {
        cubit.previousPage();
      } else if (nextArea) {
        cubit.nextPage();
      } else {
        cubit.toggleUI();
      }
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    if (_isPrevTap(position.dx, screenWidth, tapDir)) {
      cubit.previousPage();
    } else if (_isNextTap(position.dx, screenWidth, tapDir)) {
      cubit.nextPage();
    } else {
      cubit.toggleUI();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.position;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        final distance = (event.position - _tapDownPosition).distance;
        final duration = DateTime.now().difference(_tapDownTime);
        if (distance >= 20 || duration.inMilliseconds >= 300) return;

        if ((widget.state.showUI ?? false) &&
            _isTapInsideChrome(event.position)) {
          return;
        }

        _handlePaginatedTap(event.position);
      },
      child: widget.child,
    );
  }
}

// ───── _ReaderContentWidget ─────

class _ReaderContentWidget extends StatefulWidget {
  const _ReaderContentWidget({
    required this.state,
    required this.cubit,
    required this.pageController,
    required this.verticalPageController,
    required this.scrollController,
    required this.visiblePageNotifier,
    required this.animatedPauseNotifier,
    required this.scrollingNotifier,
    required this.contentId,
    required this.chapterOverlayShown,
    required this.isProgrammaticAnimation,
    required this.logger,
    required this.onHeavyImageDetected,
    required this.onContinuousImageLoaded,
    required this.onRepairBrokenImage,
    required this.onOpenSourcePageForRepair,
    required this.onScrollNotification,
    required this.onShowSettings,
    required this.onDismissChapterOverlay,
    required this.prefetchImages,
    required this.evictDistantPages,
    required this.resolveContinuousItemHeight,
    required this.isHeavyPrefetchSource,
    required this.isContinuousScrollDisabled,
    required this.getNextReadingMode,
  });

  final ReaderState state;
  final ReaderCubit cubit;
  final PageController pageController;
  final PageController verticalPageController;
  final ScrollController scrollController;
  final ValueNotifier<int> visiblePageNotifier;
  final ValueNotifier<int> animatedPauseNotifier;
  final ValueNotifier<bool> scrollingNotifier;
  final String contentId;
  final bool chapterOverlayShown;
  final bool isProgrammaticAnimation;
  final Logger logger;
  final VoidCallback onHeavyImageDetected;
  final void Function(int, Size) onContinuousImageLoaded;
  final Future<bool> Function(int) onRepairBrokenImage;
  final Future<bool> Function(int) onOpenSourcePageForRepair;
  final void Function(ScrollUpdateNotification, ReaderState)
      onScrollNotification;
  final void Function(ReaderState) onShowSettings;
  final VoidCallback onDismissChapterOverlay;
  final void Function(int, List<String>, List<ImageMetadata>?,
      {String? sourceId, String? contentId}) prefetchImages;
  final void Function(int, List<String>, {bool isOffline}) evictDistantPages;
  final double Function(int, double) resolveContinuousItemHeight;
  final bool Function(String?) isHeavyPrefetchSource;
  final bool Function() isContinuousScrollDisabled;
  final ReadingMode Function(ReadingMode,
      {required bool disableContinuousScroll}) getNextReadingMode;

  @override
  State<_ReaderContentWidget> createState() => _ReaderContentWidgetState();
}

class _ReaderContentWidgetState extends State<_ReaderContentWidget> {
  Offset _tapDownPosition = Offset.zero;
  DateTime _tapDownTime = DateTime.now();

  /// Owned here so handlers (which run in contexts above the provider) can
  /// reach it directly.
  late final ReaderTranslationCubit _translationCubit =
      getIt<ReaderTranslationCubit>();

  /// RepaintBoundary key wrapping the whole reader content. In continue-scroll
  /// this snapshots the ACTUAL visible viewport (what the user sees on screen),
  /// so translated/detected boxes are WYSIWYG relative to the viewport — not to
  /// the full page image (which is far taller than the screen).
  final GlobalKey _viewportKey = GlobalKey();

  /// Cached viewport snapshot (+ its signature) so draw-mode "Detect" reuses
  /// the last capture instead of re-snapping + re-encoding the whole screen
  /// when nothing scrolled/resized. Resetting the offset to -inf forces the
  /// first call to capture fresh.
  Uint8List? _cachedViewportBytes;
  int _cachedViewportSign = -1;
  double _cachedViewportOffset = double.negativeInfinity;
  int _cachedViewportPage = -1;

  /// T2 prefetch idle timer: resets on every scroll notification / page
  /// change; fires 600ms after the last one, when the page has settled.
  Timer? _prefetchIdleTimer;

  @override
  void initState() {
    super.initState();
    _translationCubit.initPreferences();
    // Hide the reader chrome (top bar + bottom slider/nav) while in manual
    // bubble draw mode — the drawer is a full-screen task and the chrome
    // only blocks the page it is drawn over.
    _translationCubit.onDrawModeChanged = () {
      if (_translationCubit.drawMode) {
        widget.cubit.hideUI();
      } else {
        widget.cubit.showUI();
      }
    };
    _maybeShowAiTutorial();
  }

  /// One-time tutorial for the AI-translate toolbar buttons (first reader
  /// open). Never blocks — sheet dismisses or auto-shows once.
  Future<void> _maybeShowAiTutorial() async {
    final prefs = getIt<AiPreferencesRepository>();
    if (await prefs.isAiTutorialSeen()) return;
    await prefs.markAiTutorialSeen();
    if (!mounted) return;
    // Defer: reader builds its Scaffold in the same frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Full-screen dark barrier + centered info card (not a bottom sheet).
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) => ReaderAiTutorialOverlay(
            onComplete: _dismissTutorial,
          ),
        ),
      );
    });
  }

  void _dismissTutorial() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _prefetchIdleTimer?.cancel();
    _translationCubit.onDrawModeChanged = null;
    _translationCubit.close();
    super.dispose();
  }

  /// T2 prefetch schedule: reset on activity, fire 600ms after the last
  /// scroll/page-change when the image has settled (spec 2.2). The cubit
  /// itself skips when busy / memory-pressured (spec 2.3).
  void _schedulePrefetchDetection() {
    _prefetchIdleTimer?.cancel();
    _prefetchIdleTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _translationCubit.prefetchDetection();
    });
  }

  Widget _buildChapterNavigationPage({VoidCallback? onGoToFirstPage}) {
    final hasPrevChapter = widget.cubit.hasPreviousChapter;
    final hasNextChapter = widget.cubit.hasNextChapter;
    final isChapterMode = widget.state.chapterData != null ||
        widget.state.currentChapter != null ||
        hasPrevChapter ||
        hasNextChapter;

    return EndOfChapterOverlay(
      state: widget.state,
      isChapterMode: isChapterMode,
      isOfflineMode: widget.state.isOfflineMode ?? false,
      onBackToDetail: () => context.pop(),
      onPreviousChapter:
          hasPrevChapter ? () => widget.cubit.loadPreviousChapter() : null,
      onNextChapter:
          hasNextChapter ? () => widget.cubit.loadNextChapter() : null,
      onGoToFirstPage: onGoToFirstPage,
    );
  }

  Widget _buildSinglePageReader(
      {bool showNavigation = false, bool hasVideoStrip = false}) {
    final state = widget.state;
    final pageCount = state.content?.imageUrls.length ?? 0;
    // The play card goes where the site put the video, which is not always
    // the end: a gallery can carry the embed above or between its photos.
    // `videoIndex` counts the pages before it; null ⇒ after the last page.
    final videoAt = readerVideoSlot(
      pageCount: pageCount,
      hasVideoStrip: hasVideoStrip,
      videoIndex: state.chapterData?.videoIndex,
    );
    final navAt =
        readerNavSlot(pageCount: pageCount, hasVideoStrip: hasVideoStrip);
    final totalItems =
        pageCount + (showNavigation ? 1 : 0) + (hasVideoStrip ? 1 : 0);

    widget.logger.d(
        '📖 SinglePageReader: pageCount=$pageCount, showNavigation=$showNavigation, totalItems=$totalItems');

    return PageView.builder(
      key: ValueKey('horizontal_page_view_${state.content?.id}'),
      controller: widget.pageController,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      onPageChanged: (index) {
        // The card is an item, not a page: indices after it shift by one.
        final imageIndex = readerPageIndexFor(index, videoAt);
        final reportPage =
            (imageIndex + 1).clamp(1, pageCount == 0 ? 1 : pageCount);
        widget.visiblePageNotifier.value = reportPage;
        widget.animatedPauseNotifier.value = reportPage;
        // New page → clear stale translation overlay
        _translationCubit.resetPage();
        _schedulePrefetchDetection();

        widget.logger.d(
            '📖 VerticalPageView changed to index=$index (reporting page $reportPage)');

        final imageUrls = state.content?.imageUrls ?? [];
        if (imageIndex < pageCount) {
          if (state.readingMode != ReadingMode.singlePage &&
              state.readingMode != ReadingMode.verticalPage) {
            widget.prefetchImages(reportPage, imageUrls, state.imageMetadata,
                sourceId: state.content?.sourceId,
                contentId: state.content?.id);
          }
        }

        widget.cubit.updateCurrentPageFromSwipe(reportPage);
      },
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (hasVideoStrip && index == videoAt) {
          return _buildVideoStripPage();
        }
        if (showNavigation && index == navAt) {
          return _buildChapterNavigationPage();
        }
        final imageIndex = readerPageIndexFor(index, videoAt);
        final imageUrl = state.content?.imageUrls[imageIndex] ?? '';
        final pageNumber = imageIndex + 1;

        return _ReaderImageViewer(
          imageUrl: imageUrl,
          pageNumber: pageNumber,
          contentId: state.content?.id ?? widget.contentId,
          visiblePageNotifier: widget.animatedPauseNotifier,
          cubit: widget.cubit,
          onHeavyImageDetected: widget.onHeavyImageDetected,
          onRepairBrokenImage: widget.onRepairBrokenImage,
          onOpenSourcePageForRepair: widget.onOpenSourcePageForRepair,
        );
      },
    );
  }

  Widget _buildVerticalPageReader(
      {bool showNavigation = false, bool hasVideoStrip = false}) {
    final state = widget.state;
    final pageCount = state.content?.imageUrls.length ?? 0;
    // See _buildSinglePageReader: the card is an item at the video's own
    // position, so indices after it shift by one.
    final videoAt = readerVideoSlot(
      pageCount: pageCount,
      hasVideoStrip: hasVideoStrip,
      videoIndex: state.chapterData?.videoIndex,
    );
    final navAt =
        readerNavSlot(pageCount: pageCount, hasVideoStrip: hasVideoStrip);
    final totalItems =
        pageCount + (showNavigation ? 1 : 0) + (hasVideoStrip ? 1 : 0);

    widget.logger.d(
        '📖 VerticalPageReader: pageCount=$pageCount, showNavigation=$showNavigation, totalItems=$totalItems');

    return PageView.builder(
      key: ValueKey('vertical_page_view_${state.content?.id}'),
      controller: widget.verticalPageController,
      scrollDirection: Axis.vertical,
      clipBehavior: Clip.none,
      onPageChanged: (index) {
        final imageIndex = readerPageIndexFor(index, videoAt);
        final reportPage =
            (imageIndex + 1).clamp(1, pageCount == 0 ? 1 : pageCount);
        widget.visiblePageNotifier.value = reportPage;
        widget.animatedPauseNotifier.value = reportPage;
        // New page → clear stale translation overlay
        _translationCubit.resetPage();
        _schedulePrefetchDetection();

        widget.logger.d(
            '📖 Vertical PageView changed to index=$index (reporting page $reportPage)');

        final imageUrls = state.content?.imageUrls ?? [];
        if (imageIndex < pageCount) {
          widget.prefetchImages(reportPage, imageUrls, state.imageMetadata,
              sourceId: state.content?.sourceId, contentId: state.content?.id);
          widget.evictDistantPages(reportPage, imageUrls,
              isOffline: state.isOfflineMode ?? false);
        }

        if (!widget.isProgrammaticAnimation) {
          widget.cubit.updateCurrentPageFromSwipe(reportPage);
        }
      },
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (hasVideoStrip && index == videoAt) {
          return _buildVideoStripPage();
        }
        if (showNavigation && index == navAt) {
          return _buildChapterNavigationPage();
        }
        final imageIndex = readerPageIndexFor(index, videoAt);
        final imageUrl = state.content?.imageUrls[imageIndex] ?? '';
        final pageNumber = imageIndex + 1;
        return _ReaderImageViewer(
          imageUrl: imageUrl,
          pageNumber: pageNumber,
          contentId: state.content?.id ?? widget.contentId,
          visiblePageNotifier: widget.animatedPauseNotifier,
          cubit: widget.cubit,
          sourceId: state.content?.sourceId,
          onHeavyImageDetected: widget.onHeavyImageDetected,
          onRepairBrokenImage: widget.onRepairBrokenImage,
          onOpenSourcePageForRepair: widget.onOpenSourcePageForRepair,
        );
      },
    );
  }

  Widget _buildContinuousReader(
      {bool showNavigation = false, bool hasVideoStrip = false}) {
    final state = widget.state;
    final pageCount = state.content?.imageUrls.length ?? 0;
    // See _buildSinglePageReader: the card is an item at the video's own
    // position in the chapter, not always after the last photo.
    final videoAt = readerVideoSlot(
      pageCount: pageCount,
      hasVideoStrip: hasVideoStrip,
      videoIndex: state.chapterData?.videoIndex,
    );
    final navAt =
        readerNavSlot(pageCount: pageCount, hasVideoStrip: hasVideoStrip);
    final totalItems =
        pageCount + (showNavigation ? 1 : 0) + (hasVideoStrip ? 1 : 0);

    final enableZoom = state.enableZoom ?? true;
    final isHeavySource = widget.isHeavyPrefetchSource(state.content?.sourceId);
    final viewportHeight = MediaQuery.of(context).size.height;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.position;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        final distance = (event.position - _tapDownPosition).distance;
        final duration = DateTime.now().difference(_tapDownTime);
        if (distance < 20 && duration.inMilliseconds < 300) {
          final screenHeight = MediaQuery.of(context).size.height;
          final tapY = event.position.dy;
          if (tapY > screenHeight * 0.2 && tapY < screenHeight * 0.8) {
            // Draw mode owns all taps (drawing / bubble remove) — never
            // toggle the chrome. Without this, tapping the draw pill
            // (bottom-center) also fires the middle-tap UI toggle, flashing
            // the chrome + rebuilding the overlay on every pill tap.
            if (_translationCubit.drawMode) return;
            widget.cubit.toggleUI();
          }
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification is ScrollUpdateNotification) {
            widget.onScrollNotification(notification, state);
            _schedulePrefetchDetection();
          }
          return false;
        },
        child: ListView.builder(
          key: ValueKey('continuous_list_${state.content?.id}'),
          scrollCacheExtent: ScrollCacheExtent.pixels(
              isHeavySource ? viewportHeight * 0.25 : viewportHeight * 1.0),
          controller: widget.scrollController,
          physics: isHeavySource
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(),
          addAutomaticKeepAlives: true,
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (hasVideoStrip && index == videoAt) {
              final chapterData = state.chapterData;
              if (chapterData == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(
                    bottom: ReaderScreen.kReaderContinuousGap),
                child: ReaderVideoStrip(
                  chapterData: chapterData,
                  title: state.content?.title,
                ),
              );
            }
            if (showNavigation && index == navAt) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: _buildChapterNavigationPage(
                  onGoToFirstPage: () => widget.scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  ),
                ),
              );
            }

            final imageIndex = readerPageIndexFor(index, videoAt);
            final pageNumber = imageIndex + 1;
            final imageUrl = state.content?.imageUrls[imageIndex] ?? '';
            final resolvedHeight = widget.resolveContinuousItemHeight(
              pageNumber,
              viewportHeight,
            );
            return _ReaderImageViewer(
              imageUrl: imageUrl,
              pageNumber: pageNumber,
              contentId: state.content?.id ?? widget.contentId,
              visiblePageNotifier: widget.animatedPauseNotifier,
              cubit: widget.cubit,
              isContinuous: true,
              enableZoom: enableZoom,
              sourceId: state.content?.sourceId,
              resolvedHeight: resolvedHeight,
              onHeavyImageDetected: widget.onHeavyImageDetected,
              onContinuousImageLoaded: widget.onContinuousImageLoaded,
              onRepairBrokenImage: widget.onRepairBrokenImage,
              onOpenSourcePageForRepair: widget.onOpenSourcePageForRepair,
            );
          },
        ),
      ),
    );
  }

  Widget _buildReaderContent() {
    final state = widget.state;

    // Video/HLS chapter (issue #68): no images to page, so play the stream.
    // The image pager, end-of-chapter overlay and per-page translation all
    // assume a non-empty imageUrls list.
    if (isVideoChapter(state.chapterData)) {
      return ReaderVideoChapter(
        chapterData: state.chapterData!,
        cubit: widget.cubit,
      );
    }

    final showNav =
        state.content != null && state.content!.imageUrls.isNotEmpty;

    // Mixed chapter: pages AND a stream. isVideoChapter already returned
    // above, so images are non-empty here. The strip rides the content flow
    // as an item right after the last image — the site's own order — never a
    // replacement for the pager, and with no edge-pinning.
    final chapterData = state.chapterData;
    final hasVideoStrip = chapterData != null &&
        chapterData.images.isNotEmpty &&
        chapterData.videoUrls.isNotEmpty;

    final content = switch (state.readingMode ?? ReadingMode.singlePage) {
      ReadingMode.singlePage => _buildSinglePageReader(
          showNavigation: showNav, hasVideoStrip: hasVideoStrip),
      ReadingMode.verticalPage => _buildVerticalPageReader(
          showNavigation: showNav, hasVideoStrip: hasVideoStrip),
      ReadingMode.continuousScroll => _buildContinuousReader(
          showNavigation: showNav, hasVideoStrip: hasVideoStrip),
    };

    final Widget body = (state.readingMode ?? ReadingMode.singlePage) ==
            ReadingMode.continuousScroll
        ? content
        : _PaginatedTapWrapper(
            state: state,
            cubit: widget.cubit,
            child: content,
          );

    return body;
  }

  /// The video card as a content-flow item for the paged readers: full width,
  /// own height. A PageView forces tight viewport constraints on its pages,
  /// so top-align instead of stretching to fill.
  Widget _buildVideoStripPage() {
    final chapterData = widget.state.chapterData;
    if (chapterData == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: ReaderVideoStrip(
          chapterData: chapterData,
          title: widget.state.content?.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showOverlay = !widget.chapterOverlayShown && (state.content != null);

    return BlocProvider<ReaderTranslationCubit>.value(
      value: _translationCubit,
      child: BlocListener<ReaderTranslationCubit, ReaderTranslationState>(
        // Surface pipeline failures exactly once per emit (not per rebuild).
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context);
          final l10n = AppLocalizations.of(context)!;
          if (state is ReaderTranslationError) {
            messenger.showSnackBar(
                SnackBar(content: Text(l10n.aiTranslateFailed(state.message))));
          } else if (state is ReaderTranslationNoProvider) {
            messenger.showSnackBar(SnackBar(
              content: Text(state.modelName != null
                  ? l10n.aiModelNotVision(state.modelName!)
                  : (state.message ?? l10n.aiNeedVisionProvider)),
            ));
          } else if (state is ReaderTranslationRateLimited) {
            messenger.showSnackBar(SnackBar(
              content: Text(state.fallbackName != null
                  ? l10n
                      .aiRateLimited(l10n.aiUsingFallback(state.fallbackName!))
                  : l10n.aiRateLimited(
                      l10n.aiWaitCooldown(state.cooldownSeconds))),
            ));
          }
        },
        child: BlocBuilder<ReaderTranslationCubit, ReaderTranslationState>(
          builder: (context, cubitState) {
            final drawMode = context.read<ReaderTranslationCubit>().drawMode;
            return Stack(
              children: [
                // Lock page navigation while in draw mode.
                AbsorbPointer(
                  absorbing: drawMode,
                  child: RepaintBoundary(
                    key: _viewportKey,
                    child: _buildReaderContent(),
                  ),
                ),
                // Draw references stay visible, but below loading and chrome.
                Positioned.fill(
                  child: ReaderTranslationDrawMode(
                    onCaptureNeeded: _captureForDraw,
                  ),
                ),
                // Translation loading/results sit above draw references but
                // below reader chrome, so header controls stay clickable.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: drawMode,
                    child: const ReaderTranslationOverlay(),
                  ),
                ),
                _ReaderUIOverlay(
                  isVisible: state.showUI ?? false,
                  topBar: _ReaderTopBar(
                    state: state,
                    onBack: () => context.pop(),
                    onToggleKeepScreenOn: widget.cubit.toggleKeepScreenOn,
                    onOpenSettings: () => widget.onShowSettings(state),
                    onTranslate: () => _onTranslatePressed(),
                    onToggleSkipSfx: () => _translationCubit
                        .setSkipSfx(!_translationCubit.skipSfx),
                  ),
                  // Video chapter (issue #68): pageCount is 0, so the pager
                  // slider has no range — chapter nav lives on the player.
                  bottomBar:
                      state.readingMode != ReadingMode.continuousScroll &&
                              !isVideoChapter(state.chapterData)
                          ? _ReaderBottomBar(
                              state: state,
                              onPrevPage: widget.cubit.previousPage,
                              onNextPage: widget.cubit.nextPage,
                              onJumpToPage: widget.cubit.jumpToPage,
                              onChangeReadingMode: () {
                                final newMode = widget.getNextReadingMode(
                                  state.readingMode ?? ReadingMode.singlePage,
                                  disableContinuousScroll:
                                      widget.isContinuousScrollDisabled(),
                                );
                                widget.cubit.changeReadingMode(newMode);
                              },
                              disableContinuousScroll:
                                  widget.isContinuousScrollDisabled(),
                            )
                          : null,
                ),
                if (!drawMode)
                  _ReaderMiniChromeToggle(
                    isVisible: state.showUI ?? false,
                    onToggle: widget.cubit.toggleUI,
                  ),
                // In draw mode the pill owns the bottom-center spot — the
                // indicator (opacity 0, but still hit-testable while fading)
                // would sit on top of it and swallow pill taps. Page number
                // is useless while drawing; hide it entirely.
                if (state.readingMode == ReadingMode.continuousScroll &&
                    !drawMode)
                  _ReaderFloatingPageIndicator(
                    scrollingNotifier: widget.scrollingNotifier,
                    visiblePageNotifier: widget.visiblePageNotifier,
                    totalPages: state.content?.pageCount ?? 0,
                  ),
                if (showOverlay && !isVideoChapter(state.chapterData))
                  ChapterOpenOverlay(
                    title: state.content!.getDisplayTitle(),
                    totalPages: state.content!.pageCount,
                    onDismiss: widget.onDismissChapterOverlay,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Lets the user know the on-screen viewport is being captured (continue
  /// scroll snapshots the visible region before translate/detect).
  void _showCapturingSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.aiCapturingViewport),
        duration: const Duration(seconds: 1),
      ));
  }

  /// Fetches the active page image bytes and triggers the AI pipeline.
  Future<void> _onTranslatePressed() async {
    final state = widget.state;
    final urls = state.content?.imageUrls ?? [];
    // Continuous scroll → the page under the scroll offset, so the crop
    // follows the real reading position (may straddle a page boundary).
    final target = _actionTarget();
    final pageIndex = target.page;
    if (pageIndex < 0 || pageIndex >= urls.length) return;

    final cubit = _translationCubit;

    // 4.3 Privacy disclosure — shown once before first translate
    final prefsRepo = getIt<AiPreferencesRepository>();
    if (!await prefsRepo.isPrivacyAcknowledged()) {
      if (!mounted) return;
      final ok = await _showPrivacyDialog(context);
      if (ok != true || !mounted) return;
      await prefsRepo.setPrivacyAcknowledged();
    }

    final isCs = state.readingMode == ReadingMode.continuousScroll;
    if (isCs) _showCapturingSnackbar();

    final page = await _fetchAndCapturePage(
      url: urls[pageIndex],
      pageIndex: pageIndex,
      // Same offset used for page resolution + crop, so the fetched/cropped
      // region matches the page we resolve — no drift between the two calls.
      offsetInItem: target.offsetInItem,
    );
    if (page == null || !mounted) return;

    cubit.translatePage(
      imageBytes: page.bytes,
      imageWidth: page.size.width.round(),
      imageHeight: page.size.height.round(),
      contentId: widget.contentId,
      pageIndex: pageIndex,
      imageUrl: urls[pageIndex],
      readingMode: state.readingMode ?? ReadingMode.singlePage,
      imageUrlCount: urls.length,
      cropYTop: page.cropYTop,
    );
  }

  Future<bool?> _showPrivacyDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.aiPrivacyDisclosure),
        content: Text(AppLocalizations.of(dialogContext)!.aiPrivacyDialogDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppLocalizations.of(dialogContext)!.aiCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppLocalizations.of(dialogContext)!.aiPrivacyAgree),
          ),
        ],
      ),
    );
  }

  /// Captures the current viewport for draw-mode detection. Called LAZILY by the
  /// draw-mode 🛰 button (ReaderTranslationDrawMode.onCaptureNeeded) — not on
  /// draw-mode entry, so toggling draw mode repeatedly doesn't re-capture (the
  /// cause of the perceived lag).
  Future<void> _captureForDraw() async {
    final state = widget.state;
    final urls = state.content?.imageUrls ?? [];
    final target = _actionTarget();
    final pageIndex = target.page;
    if (pageIndex < 0 || pageIndex >= urls.length) return;
    if (state.readingMode == ReadingMode.continuousScroll) {
      _showCapturingSnackbar();
    }
    await _fetchAndCapturePage(
      url: urls[pageIndex],
      pageIndex: pageIndex,
      offsetInItem: target.offsetInItem,
    );
  }

  /// Resolves the active page + its in-item scroll offset for the translate /
  /// draw action. Non-continuous mode → the visible page, offset 0.
  /// Continuous scroll → picks the page whose item covers the CENTER of the
  /// viewport (`offset + viewportH/2`), so at a page boundary the page filling
  /// most of the screen wins. The crop offset is the top of the viewport
  /// within that page.
  ({int page, double offsetInItem}) _actionTarget() {
    final state = widget.state;
    final urls = state.content?.imageUrls ?? const [];
    if (urls.isEmpty) return (page: 0, offsetInItem: 0);
    final visible = widget.visiblePageNotifier.value;
    final visiblePage = (visible > 0 ? visible : 1) - 1;
    if ((state.readingMode ?? ReadingMode.singlePage) !=
            ReadingMode.continuousScroll ||
        !widget.scrollController.hasClients) {
      return (page: visiblePage.clamp(0, urls.length - 1), offsetInItem: 0);
    }
    final screenH = MediaQuery.of(context).size.height;
    final heights = [
      for (var i = 0; i < urls.length; i++)
        widget.resolveContinuousItemHeight(i + 1, screenH),
    ];
    final offset = widget.scrollController.offset;
    // Page who owns the viewport center — the page the user is actually
    // reading, not just the one at the top edge.
    final page = computeScrollPage(
      offset: offset + screenH / 2,
      itemHeights: heights,
    ).page;
    // Top of the viewport, expressed within that page (screen px). Clamp to
    // the rendered IMAGE height, not the item height — each item is
    // image + 8px bottom gap (Padding in _ReaderImageViewer), and the gap is
    // not part of the image, so cropping into it would shift yTop.
    var topInPage = offset;
    for (var i = 0; i < page; i++) {
      topInPage -= heights[i];
    }
    final imageHeightInItem =
        (heights[page] - ReaderScreen.kReaderContinuousGap)
            .clamp(1.0, heights[page]);
    topInPage = topInPage.clamp(0.0, imageHeightInItem);
    return (page: page, offsetInItem: topInPage);
  }

  /// Fetches the page image, caches it in the translation cubit (for
  /// draw-mode detect) and returns bytes + pixel size. Null on failure.
  ///
  /// In continue scroll the visible viewport region is cropped from the
  /// fetched image so translate + draw map to what the user actually sees —
  /// for a single strip AND for the page the scroll currently sits on.
  Future<({Uint8List bytes, Size size, int cropYTop})?> _fetchAndCapturePage({
    required String url,
    required int pageIndex,
    // When provided, used as the crop offset (matches the page resolved by
    // the caller). When null, re-resolved here from the live scroll position.
    double? offsetInItem,
  }) async {
    final isContinuous = (widget.state.readingMode ?? ReadingMode.singlePage) ==
        ReadingMode.continuousScroll;

    // Continuous scroll → WYSIWYG: snapshot the ACTUAL visible viewport (the
    // RepaintBoundary wrapping all reader content). The snapshot is exactly
    // what the user sees on screen, so no crop/offset math is needed — boxes
    // are interpreted relative to this viewport bitmap. cropYTop = scroll
    // offset keeps the cache key unique per scroll position.
    if (isContinuous) {
      final resolvedOffset = offsetInItem ?? _actionTarget().offsetInItem;
      // Reuse last snapshot when viewport size + scroll offset unchanged —
      // the screen looks identical, so re-snapping/re-encoding (toImage →
      // PNG → JPG, all CPU/GPU-heavy) just wastes time on every draw Detect.
      final viewport = _currentViewportSize();
      final cachedSig = viewport == null
          ? -1
          : (viewport.width.round() ^
              (viewport.height.round() << 16) ^
              resolvedOffset.round());
      if (cachedSig == _cachedViewportSign &&
          _cachedViewportBytes != null &&
          resolvedOffset == _cachedViewportOffset &&
          pageIndex == _cachedViewportPage) {
        widget.logger.d(
            'AI translate: reuse cached viewport snapshot (${viewport!.width.round()}x${viewport.height.round()} @$resolvedOffset p$pageIndex)');
        _translationCubit.capturePage(
          imageBytes: _cachedViewportBytes!,
          imageWidth: viewport.width.round(),
          imageHeight: viewport.height.round(),
        );
        _schedulePrefetchDetection();
        return (
          bytes: _cachedViewportBytes!,
          size: Size(viewport.width, viewport.height),
          cropYTop: resolvedOffset.round(),
        );
      }
      final captured = await _captureVisibleViewport();
      if (captured == null) {
        widget.logger.w('AI translate: viewport capture gagal');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.aiGagalCapture)));
        }
        return null;
      }
      if (!mounted) return null;
      // Re-encode the PNG snapshot as JPG on a background isolate — decode +
      // encode are CPU-bound and would otherwise jank the UI (draw-mode entry
      // and translate both go through here).
      final bytesOut =
          await Isolate.run(() => _encodeViewportJpg(captured.bytes));
      if (bytesOut == null) {
        widget.logger.w('AI translate: snapshot decode gagal');
        return null;
      }
      final sizeOut = Size(
        captured.width.toDouble(),
        captured.height.toDouble(),
      );
      widget.logger.d('AI translate: viewport capture ${sizeOut.width.round()}x'
          '${sizeOut.height.round()} bytes=${bytesOut.length}');
      _cachedViewportBytes = bytesOut;
      _cachedViewportSign = viewport == null
          ? -1
          : (viewport.width.round() ^
              (viewport.height.round() << 16) ^
              resolvedOffset.round());
      _cachedViewportOffset = resolvedOffset;
      _cachedViewportPage = pageIndex;
      _translationCubit.capturePage(
        imageBytes: bytesOut,
        imageWidth: sizeOut.width.round(),
        imageHeight: sizeOut.height.round(),
      );
      _schedulePrefetchDetection();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.aiCapturedViewport),
            duration: const Duration(seconds: 1),
          ));
      }
      return (bytes: bytesOut, size: sizeOut, cropYTop: resolvedOffset.round());
    }

    // Non-continuous: fetch full page, no crop.
    final bytes = await _fetchPageBytes(url);
    if (bytes == null) {
      widget.logger.w('AI translate: fetch gagal untuk $url');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.aiGagalFetch)));
      }
      return null;
    }
    if (!mounted) return null;
    final size = await _imageSize(bytes);
    if (size == null) {
      widget.logger
          .w('AI translate: decode ukuran gagal, bytes=${bytes.length}');
      return null;
    }
    _translationCubit.capturePage(
      imageBytes: bytes,
      imageWidth: size.width.round(),
      imageHeight: size.height.round(),
    );
    _schedulePrefetchDetection();
    widget.logger.d('AI translate: page ${size.width.round()}x'
        '${size.height.round()} bytes=${bytes.length}');
    return (bytes: bytes, size: size, cropYTop: 0);
  }

  /// Snapshot of the RepaintBoundary wrapping all reader content — i.e. the
  /// ACTUAL visible viewport (WYSIWYG). Returns raw PNG bytes of exactly what
  /// is on screen. Null when the boundary isn't mounted or capture fails.
  Future<({Uint8List bytes, int width, int height})?>
      _captureVisibleViewport() async {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    try {
      // pixelRatio 1 → snapshot at logical device scale (== screen), so the
      // returned boxes map 1:1 to the on-screen viewport.
      final image = await renderObject.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;
      return (
        bytes: byteData.buffer.asUint8List(),
        width: renderObject.size.width.round(),
        height: renderObject.size.height.round(),
      );
    } catch (e) {
      widget.logger.w('AI translate: viewport capture gagal: $e');
      return null;
    }
  }

  /// Current rendered viewport size (logical px) WITHOUT rasterizing. Used to
  /// key the snapshot cache — size + scroll offset fully identify the view.
  Size? _currentViewportSize() {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    return renderObject is RenderRepaintBoundary ? renderObject.size : null;
  }

  Future<Uint8List?> _fetchPageBytes(String url) async {
    // Local/offline images: read directly from disk.
    if (url.startsWith('/') || url.startsWith('file://')) {
      final path = url.replaceFirst('file://', '');
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
      return null;
    }
    // Remote: use the source's download headers (referer/cookie/user-agent) —
    // most sources reject plain requests, silently killing the pipeline.
    final sourceId = widget.state.content?.sourceId;
    if (sourceId == null || sourceId.trim().isEmpty) return null;
    return getIt<DownloadService>().fetchRemoteImageBytes(sourceId, url);
  }

  Future<Size?> _imageSize(Uint8List bytes) async {
    try {
      final decoded = await decodeImageFromList(bytes);
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) {
      return null;
    }
  }
}

/// Computes the visible viewport crop of a single-image webtoon strip
/// rendered `fitWidth` in a scroll view.
///
/// `offset` is the scroll position in screen px; `full` is the strip's pixel
/// size; `viewport` is the screen size. The strip is drawn at
/// `screenW / imgW` scale, so scroll px → image px is `offset * (imgW / screenW)`.
/// Returns null when the mapping is degenerate (no viewport). yTop/cropH are
/// clamped to image bounds.
({int yTop, int cropH})? computeViewportCrop({
  required double offset,
  required Size full,
  required Size viewport,
}) {
  if (full.height <= 0 ||
      full.width <= 0 ||
      viewport.height <= 0 ||
      viewport.width <= 0) {
    return null;
  }
  final scale = full.width / viewport.width;
  // Intended viewport height in image px, but never exceed the image.
  final cropH = (viewport.height * scale).round().clamp(1, full.height.toInt());
  // Center the viewport on the scroll position; clamp to the top edge.
  final yTop = (offset * scale).round().clamp(0, full.height.toInt() - cropH);
  return (yTop: yTop, cropH: cropH);
}

/// Maps a continue-scroll [offset] (screen px) to the page whose vertical
/// span contains it, plus the offset within that page (screen px). Uses each
/// item's rendered height. Past the last item → last page's offset.
({int page, double offsetInItem}) computeScrollPage({
  required double offset,
  required List<double> itemHeights,
}) {
  var acc = 0.0;
  for (var i = 0; i < itemHeights.length; i++) {
    final h = itemHeights[i];
    if (offset < acc + h) {
      return (page: i, offsetInItem: (offset - acc).clamp(0.0, h));
    }
    acc += h;
  }
  return (page: itemHeights.length - 1, offsetInItem: itemHeights.last);
}

/// Background-isolate re-encode of a PNG viewport snapshot → JPG. Keeps the
/// CPU-bound decode/encode off the UI isolate (draw-mode entry + translate
/// both capture a viewport).
Uint8List? _encodeViewportJpg(Uint8List pngBytes) {
  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) return null;
  return img.encodeJpg(decoded, quality: 90);
}
