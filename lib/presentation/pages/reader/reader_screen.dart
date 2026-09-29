import 'dart:async';
import 'dart:isolate';
import 'package:dio/dio.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:image/image.dart' as img;
import 'package:nhasixapp/core/utils/native_theme_helper.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import '../../../core/constants/colors_const.dart' show KuronColors;
import '../../../core/constants/design_tokens.dart';
import '../../../core/constants/text_style_const.dart';
import '../../../core/config/remote_config_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/services/download_service.dart';
import '../../../core/models/image_metadata.dart';
import '../../../core/routing/reader_route_extra.dart';
import '../../../core/utils/offline_content_manager.dart';
import '../../blocs/download/download_bloc.dart';
import 'package:extended_image/extended_image.dart';
import '../../../core/utils/reader_image_repair_utils.dart';
import '../../../domain/entities/reader_settings_entity.dart';

import 'package:kuron_core/kuron_core.dart';

import 'package:logger/logger.dart';
import '../../../core/services/local_image_preloader.dart';
import '../../../core/services/memory_budget_coordinator.dart';
import '../../cubits/reader/reader_cubit.dart';
import '../../cubits/reader/reader_prefetch_cubit.dart';
import '../../cubits/theme/theme_cubit.dart';
import '../../utils/chapter_language_presenter.dart';
// import '../../cubits/reader/reader_state.dart';
import '../../widgets/progress_indicator_widget.dart';
import '../../widgets/error_widget.dart';
import '../../widgets/extended_image_reader_widget.dart';
import 'chapter_open_overlay.dart';
import 'end_of_chapter_overlay.dart';
import 'reader_video_chapter.dart';

import 'reader_translation_widgets.dart';
import 'reader_translation_draw_mode.dart';
import 'reader_ai_tutorial_sheet.dart';
import '../../cubits/reader/reader_translation_cubit.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';

part 'reader_overlay_widgets.dart';
part 'reader_settings_widgets.dart';
part 'reader_image_widgets.dart';
part 'reader_mode_widgets.dart';

class ReaderScreen extends StatefulWidget {
  /// Bottom padding added to each image in continue scroll — must match
  /// `Padding(bottom:)` in reader_image_widgets.dart. Kept as one const so
  /// the continuous-scroll crop math (which excludes the gap) stays in sync.
  static const double kReaderContinuousGap = 8.0;
  const ReaderScreen({
    super.key,
    required this.contentId,
    this.initialPage = 1,
    this.forceStartFromBeginning = false,
    this.preloadedContent,
    this.imageMetadata,
    this.chapterData,
    this.parentContent, // Parent series for chapter mode
    this.allChapters,
    this.currentChapter,
    this.activeChapterLanguage,
  });

  final String contentId;
  final int initialPage;
  final bool forceStartFromBeginning;
  final Content? preloadedContent;
  final List<ImageMetadata>? imageMetadata;
  final ChapterData? chapterData;
  final Content? parentContent; // Parent series
  final List<Chapter>? allChapters;
  final Chapter? currentChapter;
  final String? activeChapterLanguage;

  /// Whether a heavy animated page must NOT auto-switch the reader out of
  /// continuous scroll.
  ///
  /// Config-driven: a source opts out with
  /// `scraper.selectors.reader.heavyImageAutoSwitch: false` (webtoon and
  /// dual-page chapters have to keep continuous scroll even when one page is a
  /// ≥2 MB animated WebP). Declared value wins in both directions.
  ///
  /// ponytail: [_legacyHeavyImageAutoSkipSources] is the pre-config list. It
  /// stays only so already-published sources keep their behaviour before their
  /// config declares the flag; it is deleted once every config says it.
  static const Set<String> _legacyHeavyImageAutoSkipSources = {
    'manga18.club',
    'ehentai',
    'komiktap',
  };

  @visibleForTesting
  static bool shouldSkipHeavyImageAutoSwitch({
    required String? sourceId,
    Map<String, dynamic>? rawConfig,
  }) {
    final declared = _readerFlag(rawConfig, 'heavyImageAutoSwitch');
    if (declared != null) return !declared;
    return _legacyHeavyImageAutoSkipSources
        .contains((sourceId ?? '').toLowerCase());
  }

  /// Reads one key out of `scraper.selectors.reader` in a raw source config.
  static bool? _readerFlag(Map<String, dynamic>? rawConfig, String key) {
    final scraper = rawConfig?['scraper'];
    if (scraper is! Map) return null;
    final selectors = scraper['selectors'];
    if (selectors is! Map) return null;
    final reader = selectors['reader'];
    if (reader is! Map) return null;
    final value = reader[key];
    return value is bool ? value : null;
  }

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Logger get _logger => getIt<Logger>();

  late PageController _pageController;
  late PageController _verticalPageController;
  late ScrollController _scrollController;
  late ReaderCubit _readerCubit;
  late ReaderPrefetchCubit _prefetchCubit;
  final CancelToken _scopeToken = CancelToken();

  // Debouncing for scroll updates
  int _lastReportedPage = 1;
  int _lastSavedPage = 0; // Track last saved page to prevent backward saves
  String? _lastTrackedProgressKey;

  // 🐛 FIX: Cache rendered image heights to prevent scroll jumping on scroll-up
  // When items are rebuilt after disposal, the loading placeholder must match
  // the original image height to keep the scroll offset stable.
  final Map<int, double> _cachedImageHeights = {};

  // Prefetch bookkeeping moved to ReaderPrefetchCubit (download engine).
  // Widget keeps only the BuildContext-bound decode pre-cache (_decodeQueue).

  // Chapter open overlay: shown once per reader session
  bool _chapterOverlayShown = false;

  // 🎬 Heavy-image guard: content IDs where continuous-scroll is disabled.
  // Static so the lock persists across reader navigations in the same session.
  static final Set<String> _autoSwitchedContentIds = <String>{};

  // Throttle expensive continuous-scroll computations.
  // 🔥 THERMAL: Increased from 90ms → 150ms → 200ms → 300ms
  // At 300ms (3-4 fps) the page indicator still feels responsive while
  // prefetch/evict loops run 40% less often.
  static const Duration _scrollHeavyOpsInterval = Duration(milliseconds: 300);
  DateTime _lastHeavyOpsAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 🚀 OPTIMIZATION: Frame-aligned decode throttle
  // Queues prefetch decode requests and processes max 2 per frame tick (1 for heavy sources).
  // Visible page decodes bypass the queue (priority path).
  final List<void Function()> _decodeQueue = [];
  static const int _maxDecodePerFrame = 2;
  static const int _maxDecodePerFrameHeavy = 1;
  int _currentMaxDecodePerFrame = _maxDecodePerFrame;
  bool _isDecodeTickScheduled = false;

  // Debounce mechanism to prevent onPageChanged loops
  bool _isProgrammaticAnimation = false;

  // Track last content ID to detect chapter changes vs timer-only updates
  String? _lastSyncedContentId;

  // 🚀 OPTIMIZATION: Throttle save to DB and UI toggle
  Timer? _saveDebounceTimer;
  Timer? _pageUpdateTimer;
  Timer? _uiToggleDebounceTimer;
  DateTime _lastTapTime = DateTime.now();
  bool _lastUIVisibleState = true;

  // 🎯 Tap-to-toggle detection for continuous scroll
  // 🎯 Floating page indicator (ValueNotifiers avoid full-screen rebuild)
  final ValueNotifier<int> _visiblePageNotifier = ValueNotifier<int>(1);
  final ValueNotifier<bool> _scrollingNotifier = ValueNotifier<bool>(false);
  Timer? _scrollIndicatorTimer;

  //  separate notifier for AnimatedWebPView pause, so _visiblePageNotifier
  // (used by page indicator) never flickers to 0.
  final ValueNotifier<int> _animatedPauseNotifier = ValueNotifier<int>(1);

  // Slider footer previews the destination locally while dragging and only
  // commits navigation once on release, preventing overlapping PageView syncs.
  // 🚀 OPTIMIZATION: Preload content before BlocProvider setup
  Content? _preloadedContent;
  List<ImageMetadata>? _preloadedImageMetadata;
  ChapterData? _preloadedChapterData;
  Content? _preloadedParentContent; // Parent series for chapters
  List<Chapter>? _preloadedAllChapters;
  Chapter? _preloadedCurrentChapter;
  String? _preloadedActiveChapterLanguage;
  bool _isPreloading = false;
  bool _didInitRouteExtra = false;

  //  batch height updates during initial image load stampede.
  // 🏎️ Ticker for 120 FPS page indicator (vsync-aligned, not Timer)
  Ticker? _pageTicker;
  int _pendingEstimatedPage = 0;
  bool _isTicking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive').value = true;
    MemoryBudgetCoordinator().onReaderActiveChanged(true);
    _lastReportedPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage - 1);
    _verticalPageController =
        PageController(initialPage: widget.initialPage - 1);

    // 🐛 CRITICAL FIX: Set flag BEFORE ScrollController to prevent false saves
    // When ScrollController is created with initialScrollOffset, it triggers
    // scroll events immediately which can cause false page saves
    if (widget.initialPage > 1) {
      _isProgrammaticAnimation = true;
      _logger.i(
          '🔒 Locked programmatic animation flag for initial scroll to page ${widget.initialPage}');
    }

    // 🚀 OPTIMIZATION: Calculate initial scroll offset for continuous scroll
    // This allows starting from a specific page while keeping all pages available
    final screenHeight = WidgetsBinding
            .instance.platformDispatcher.views.first.physicalSize.height /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final estimatedItemHeight = screenHeight * 0.9;
    final initialScrollOffset = (widget.initialPage - 1) * estimatedItemHeight;

    _scrollController = ScrollController(
      initialScrollOffset: initialScrollOffset > 0 ? initialScrollOffset : 0,
    );
    _readerCubit = context.read<ReaderCubit>();
    _prefetchCubit = getIt<ReaderPrefetchCubit>();
    _pageTicker = createTicker(_onPageTick);

    // 🚀 OPTIMIZATION: Initialize route extra handled in didChangeDependencies (once)

    // Defer GoRouterState access until after widget is mounted (for any additional processing)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPreloading();

      // 🚀 FIX: Unlock flag after content settles (1.5s for images to load)
      if (widget.initialPage > 1) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _isProgrammaticAnimation = false;
            _logger.i(
                '🔓 Unlocked programmatic animation flag - user can scroll freely');
          }
        });
      }
    });

    // 🚀 REMOVED: _onScrollChanged listener (causes duplicate saves)
    // We now use ONLY NotificationListener for more accurate tracking
    // _scrollController.addListener(_onScrollChanged);

    // 🚀 OPTIMIZATION: Start preloading content immediately - MOVED TO POST FRAME CALLBACK
    // _startPreloading();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitRouteExtra) {
      _didInitRouteExtra = true;
      _initializeFromRouteExtra();
    }
  }

  void _initializeFromRouteExtra() {
    if (_preloadedContent != null) return;

    final rawRouteExtra = GoRouterState.of(context).extra;
    final routeExtra = asReaderRouteExtra(rawRouteExtra);

    // Only log once (not on every build)
    _logger.i(
        '📥 ReaderScreen._initializeFromRouteExtra - Received: ${rawRouteExtra.runtimeType}');

    if (routeExtra != null) {
      _logger.i('  Map keys: ${routeExtra.keys.toList()}');

      final parsedContent = readReaderContent(routeExtra['content']);
      if (parsedContent != null && widget.preloadedContent == null) {
        _preloadedContent = parsedContent;
        _logger.i('  ✓ content: ${_preloadedContent?.title}');
      }

      final parsedImageMetadata = readReaderImageMetadata(
        routeExtra['imageMetadata'],
      );
      if (parsedImageMetadata != null && widget.imageMetadata == null) {
        _preloadedImageMetadata = parsedImageMetadata;
        Logger()
            .i('  ✓ imageMetadata: ${_preloadedImageMetadata?.length} items');
      }

      final parsedChapterData =
          readReaderChapterData(routeExtra['chapterData']);
      if (parsedChapterData != null && widget.chapterData == null) {
        _preloadedChapterData = parsedChapterData;
        _logger.i(
            '  ✓ chapterData: prev=${_preloadedChapterData?.prevChapterId}, next=${_preloadedChapterData?.nextChapterId}');
      }

      final parsedParentContent =
          readReaderContent(routeExtra['parentContent']);
      if (parsedParentContent != null && widget.parentContent == null) {
        _preloadedParentContent = parsedParentContent;
        _logger.i('  ✓ parentContent: ${_preloadedParentContent?.title}');
      }

      final parsedAllChapters = readReaderChapters(routeExtra['allChapters']);
      if (parsedAllChapters != null && widget.allChapters == null) {
        _preloadedAllChapters = parsedAllChapters;
        Logger()
            .i('  ✓ allChapters: ${_preloadedAllChapters?.length} chapters');
        if (_preloadedAllChapters != null &&
            _preloadedAllChapters!.isNotEmpty) {
          _logger.i('    First: ${_preloadedAllChapters!.first.title}');
          _logger.i('    Last: ${_preloadedAllChapters!.last.title}');
        }
      }

      final parsedCurrentChapter =
          readReaderChapter(routeExtra['currentChapter']);
      if (parsedCurrentChapter != null && widget.currentChapter == null) {
        _preloadedCurrentChapter = parsedCurrentChapter;
        _logger.i('  ✓ currentChapter: ${_preloadedCurrentChapter?.title}');
      }

      final parsedActiveChapterLanguage = readReaderActiveChapterLanguage(
        routeExtra['activeChapterLanguage'],
      );
      if (parsedActiveChapterLanguage != null &&
          widget.activeChapterLanguage == null) {
        _preloadedActiveChapterLanguage = parsedActiveChapterLanguage;
      }
    } else if (widget.preloadedContent == null) {
      final parsedDirectContent = readReaderContent(rawRouteExtra);
      if (parsedDirectContent != null) {
        _preloadedContent = parsedDirectContent;
        _logger.i('  ✓ Direct Content: ${_preloadedContent?.title}');
      }
    }
  }

  Future<void> _startPreloading() async {
    if (_preloadedContent != null) {
      return;
    }

    if (_isPreloading) return;

    _isPreloading = true;
    try {
      final offlineManager = getIt<OfflineContentManager>();
      final isOfflineAvailable =
          await offlineManager.isContentAvailableOffline(widget.contentId);

      if (isOfflineAvailable) {
        _preloadedContent =
            await offlineManager.createOfflineContent(widget.contentId);
      }
    } catch (e) {
      // Ignore preload errors, will fallback to normal loading
      _logger.d('Reader preload failed: $e');
    } finally {
      _isPreloading = false;
    }
  }

  void _onScrollNotification(
      ScrollUpdateNotification notification, ReaderState state) {
    if (state.content == null) return;

    final progressKey =
        '${state.content?.id ?? ''}::${state.currentChapter?.id ?? ''}';
    if (_lastTrackedProgressKey != progressKey) {
      _lastTrackedProgressKey = progressKey;
      _lastSavedPage = 0;
      _lastReportedPage = 0;
    }

    // 🐛 CRITICAL: Skip all processing during programmatic scroll
    if (_isProgrammaticAnimation) return;

    final metrics = notification.metrics;
    final totalPages = state.content!.pageCount;
    final screenHeight = MediaQuery.of(context).size.height;
    final estimatedPage = _estimateContinuousVisiblePage(
      metrics: metrics,
      totalPages: totalPages,
      screenHeight: screenHeight,
    );

    // === UNTHROTTLED: Page indicator — runs every vsync frame ===
    if (estimatedPage != _lastReportedPage) {
      _pendingEstimatedPage = estimatedPage;
      if (!_isTicking) {
        _isTicking = true;
        _pageTicker?.start();
      }
    }

    // Pause animated WebP during scroll
    if (!_scrollingNotifier.value) {
      _scrollingNotifier.value = true;
      _animatedPauseNotifier.value = 0;
    }
    _scrollIndicatorTimer?.cancel();
    _scrollIndicatorTimer = Timer(const Duration(milliseconds: 200), () {
      _scrollingNotifier.value = false;
      _animatedPauseNotifier.value = _lastReportedPage;
    });

    // === THROTTLED (300ms): Heavy ops only ===
    final now = DateTime.now();
    if (now.difference(_lastHeavyOpsAt) < _scrollHeavyOpsInterval) return;
    _lastHeavyOpsAt = now;

    if (estimatedPage != _lastReportedPage) {
      _debouncePageUpdate(estimatedPage, state);
      _prefetchImages(
        estimatedPage,
        state.content!.imageUrls,
        state.imageMetadata,
        sourceId: state.content?.sourceId,
        contentId: state.content!.id,
      );
    }

    final isAtBottom = metrics.pixels >= metrics.maxScrollExtent - 50;
    if (isAtBottom) {
      _debounceSaveHistory(state, totalPages);
    }

    if (_isHeavyPrefetchSource(state.content?.sourceId)) {
      _evictDistantPages(estimatedPage, state.content!.imageUrls,
          isOffline: state.isOfflineMode ?? false);
    }

    if (notification.scrollDelta != null && notification.scrollDelta! > 5) {
      _debounceUIToggle(false, state);
    } else if (notification.scrollDelta != null &&
        notification.scrollDelta! < -5) {
      _debounceUIToggle(true, state);
    }
  }

  int _estimateContinuousVisiblePage({
    required ScrollMetrics metrics,
    required int totalPages,
    required double screenHeight,
  }) {
    if (totalPages <= 0) return 1;

    final viewportCenter = metrics.pixels + (metrics.viewportDimension / 2);
    final avgHeight = _resolveAverageItemHeight(
      metrics: metrics,
      totalPages: totalPages,
      screenHeight: screenHeight,
    );

    //  O(n) scan that stops as soon as viewportCenter is reached.
    // Each page uses cached height (if available) or average fallback.
    // Bounded by totalPages but in practice exits after 20-50 pages.
    // ~50μs for 200 pages — negligible even at 120 FPS.
    double cumulativeHeight = 0;
    for (int page = 1; page <= totalPages; page++) {
      cumulativeHeight +=
          (_cachedImageHeights[page] ?? avgHeight).clamp(1.0, double.infinity);
      if (viewportCenter < cumulativeHeight) return page;
    }
    return totalPages;
  }

  void _onPageTick(Duration elapsed) {
    if (_pendingEstimatedPage > 0 &&
        _pendingEstimatedPage != _lastReportedPage) {
      _lastReportedPage = _pendingEstimatedPage;
      //  page indicator (O(1) average) is approximate — good enough
      // for the UI counter. Animated pause notifier needs accurate page
      // detection so the correct AnimatedWebPView plays. Compute a windowed
      // scan from cached heights when available.
      _visiblePageNotifier.value = _pendingEstimatedPage;
      _animatedPauseNotifier.value = _pendingEstimatedPage;
    }
    if (_pendingEstimatedPage == _lastReportedPage ||
        _pendingEstimatedPage == 0) {
      _isTicking = false;
      _pageTicker?.stop();
    }
  }

  // O(1) average height estimation — no linear scan.
  // Improves accuracy as more images load into [_cachedImageHeights].
  double _resolveAverageItemHeight({
    required ScrollMetrics metrics,
    required int totalPages,
    required double screenHeight,
  }) {
    // 1. From cached heights (sample first 20 pages)
    if (_cachedImageHeights.length >= 3) {
      final sample = _cachedImageHeights.values.take(20).toList();
      if (sample.isNotEmpty) {
        return sample.fold(0.0, (a, b) => a + b) / sample.length;
      }
    }
    // 2. From scroll metrics estimate
    if (metrics.maxScrollExtent > 0) {
      return ((metrics.maxScrollExtent + metrics.viewportDimension) /
              totalPages)
          .clamp(1.0, double.infinity);
    }
    // 3. Fallback viewport
    return screenHeight * 0.9;
  }

  double _resolveContinuousItemHeight(int pageNumber, double screenHeight) {
    final cachedHeight = _cachedImageHeights[pageNumber];
    if (cachedHeight != null && cachedHeight > 0) {
      return cachedHeight;
    }

    for (final candidatePage in <int>[
      pageNumber - 1,
      pageNumber + 1,
      pageNumber - 2,
      pageNumber + 2,
    ]) {
      final candidateHeight = _cachedImageHeights[candidatePage];
      if (candidateHeight != null && candidateHeight > 0) {
        return candidateHeight;
      }
    }

    if (_cachedImageHeights.isNotEmpty) {
      return _cachedImageHeights.values.last;
    }

    return (screenHeight * 0.5).clamp(1.0, double.infinity).toDouble();
  }

  void _debounceSaveHistory(ReaderState state, int page) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(DesignTokens.durationSlow, () {
      // Only save if still at bottom after 500ms
      if (state.readingMode == ReadingMode.continuousScroll) {
        _readerCubit.updateCurrentPageSilent(page);
      } else {
        _readerCubit.updateCurrentPageFromSwipe(page);
      }
    });
  }

  void _debouncePageUpdate(int page, ReaderState state) {
    // 🐛 FIX: Only save if progress moves forward (user reads more)
    // Don't save when scrolling back up to re-read
    if (page <= _lastSavedPage) {
      return;
    }

    final isHeavySource = _isHeavyPrefetchSource(state.content?.sourceId);
    final isTinyAdvance = page - _lastSavedPage < 2;
    if (isHeavySource && isTinyAdvance) {
      return;
    }

    _pageUpdateTimer?.cancel();
    _pageUpdateTimer = Timer(
      Duration(milliseconds: isHeavySource ? 1400 : 800),
      () {
        // Save page progress after user stops scrolling for 800ms
        // This prevents DB spam when user scrolls up/down repeatedly
        _lastSavedPage = page;
        if (state.readingMode == ReadingMode.continuousScroll) {
          _readerCubit.updateCurrentPageSilent(page);
        } else {
          _readerCubit.updateCurrentPageFromSwipe(page);
        }
      },
    );
  }

  void _debounceUIToggle(bool shouldShow, ReaderState state) {
    if (_lastUIVisibleState == shouldShow) return;

    _uiToggleDebounceTimer?.cancel();
    _uiToggleDebounceTimer = Timer(DesignTokens.durationFast, () {
      _lastUIVisibleState = shouldShow;
      if (shouldShow && !(state.showUI ?? false)) {
        _readerCubit.showUI();
      } else if (!shouldShow && (state.showUI ?? false)) {
        _readerCubit.hideUI();
      }
    });
  }

  // Called when an [ExtendedImageReaderWidget] at an early page detects a
  // heavy animated WebP (≥ 2 MB) while in continuous-scroll mode.
  ///
  // Automatically disables continuous-scroll and switches to single-page
  // mode so only one animation is rendered at a time, eliminating
  // concurrent-decode frame drops.
  void _onHeavyImageDetected() {
    if (!mounted) return;
    final sourceId = _readerCubit.state.content?.sourceId;
    final rawConfig = sourceId == null
        ? null
        : getIt<RemoteConfigService>().getRawConfig(sourceId);
    if (ReaderScreen.shouldSkipHeavyImageAutoSwitch(
      sourceId: sourceId,
      rawConfig: rawConfig,
    )) {
      return;
    }

    final contentId = widget.contentId;
    if (_autoSwitchedContentIds.contains(contentId)) return;
    _autoSwitchedContentIds.add(contentId);

    _readerCubit.changeReadingMode(
      ReadingMode.singlePage,
      persistPreference: false,
      resetWebtoonDetection: false,
    );

    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.readerContinuousDisabledHeavyImage),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _onContinuousImageLoaded(int page, Size imageSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (imageSize.width > 0) {
      final renderedHeight = imageSize.height * (screenWidth / imageSize.width);
      final totalHeight = renderedHeight + ReaderScreen.kReaderContinuousGap;
      if (_cachedImageHeights[page] != totalHeight) {
        _cachedImageHeights[page] = totalHeight;
        setState(() {});
      }
    }
    _readerCubit.onImageLoaded(page, imageSize);
  }

  Future<bool> _repairBrokenImage(int pageNumber) async {
    final result = await _readerCubit.repairBrokenImage(pageNumber);
    if (!mounted) return result.success;
    _showRepairSnackBar(pageNumber, result);
    return result.success;
  }

  Future<bool> _openSourcePageForRepair(int pageNumber) async {
    final manualContext =
        await _readerCubit.prepareManualRepairContext(pageNumber);
    if (manualContext == null) {
      if (mounted) {
        _showRepairSnackBar(
          pageNumber,
          (success: false, reason: 'remote_unavailable', statusCode: null),
        );
      }
      return false;
    }

    final sourceRules = resolveSourceImageResolutionRules(
      _getSourceRawConfig(manualContext.sourceId),
    );
    final webViewResult = await KuronNative.instance.showLoginWebView(
      url: manualContext.sourcePageUrl,
      successUrlFilters: const <String>[],
      initialCookie: manualContext.initialCookie,
      userAgent: null,
      backgroundColor: NativeThemeHelper.backgroundColorHex,
      textColor: NativeThemeHelper.textColorHex,
      domImageSelectors: sourceRules.imageSelectors,
      domImageAttributes: sourceRules.imageAttributes,
      domLinkSelectors: sourceRules.linkSelectors,
      clearCookies: false,
    );

    if (!mounted) return false;

    final launched = (webViewResult?['success'] as bool?) == true;
    if (!launched) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final l10n = AppLocalizations.of(context)!;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l10n.failedToOpenBrowser),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }

    final rawCookies =
        (webViewResult?['cookies'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
    final userAgent = webViewResult?['userAgent'] as String?;
    final sessionUrl = webViewResult?['currentUrl'] as String?;
    final resolvedImageUrl = webViewResult?['resolvedImageUrl'] as String?;

    final result = await _readerCubit.retryRepairAfterManualSession(
      pageNumber: pageNumber,
      sourcePageUrl: manualContext.sourcePageUrl,
      sessionUrl: sessionUrl,
      resolvedImageUrl: resolvedImageUrl,
      rawCookies: rawCookies,
      userAgent: userAgent,
    );

    if (mounted) {
      _showRepairSnackBar(pageNumber, result);
      _refreshDownloadBloc();
    }

    return result.success;
  }

  Map<String, dynamic>? _getSourceRawConfig(String? sourceId) {
    if (sourceId == null || sourceId.trim().isEmpty) return null;
    return getIt<RemoteConfigService>().getRawConfig(sourceId);
  }

  void _refreshDownloadBloc() {
    try {
      context.read<DownloadBloc>().add(const DownloadRefreshEvent());
    } catch (e) {
      _logger.w('DownloadBloc refresh failed', error: e);
    }
  }

  void _showRepairSnackBar(int pageNumber, ReaderImageRepairResult result) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context)!;
    final message = switch (result.reason) {
      'success' => l10n.readerImageRepairSuccess(pageNumber),
      'no_connection' => l10n.noInternetConnection,
      'http_status' =>
        l10n.readerImageRepairHttpStatus(pageNumber, result.statusCode ?? 0),
      'invalid_image' => l10n.readerImageRepairInvalidImage(pageNumber),
      'provider_unavailable' ||
      'remote_unavailable' ||
      'page_unavailable' ||
      'content_unavailable' =>
        l10n.readerImageRepairUnavailable(pageNumber),
      _ => l10n.readerImageRepairFailed(pageNumber),
    };
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _readerCubit.handleLifecyclePause();
        break;
      case AppLifecycleState.resumed:
        _readerCubit.handleLifecycleResume();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushReaderProgressBeforeDispose();

    // Cancel all in-flight prefetch downloads (repo-path via scope token + legacy)
    if (!_scopeToken.isCancelled) _scopeToken.cancel('Reader dispose');
    _prefetchCubit.cancelAll(_scopeToken);
    _heavyImageBudgetTimer?.cancel();

    // Clear pending decode queue so orphan precacheImage tasks stop
    _decodeQueue.clear();
    _isDecodeTickScheduled = false;

    // Flush static cache maps to prevent unbounded growth across sessions
    ExtendedImageReaderWidget.clearNativeAnimatedCache();

    // 🚀 REMOVED: Old scroll listener (now using NotificationListener)
    // _scrollController.removeListener(_onScrollChanged);
    _pageController.dispose();
    _verticalPageController.dispose();
    _scrollController.dispose();

    _saveDebounceTimer?.cancel();
    _pageUpdateTimer?.cancel();
    _uiToggleDebounceTimer?.cancel();
    _scrollIndicatorTimer?.cancel();
    _animatedPauseNotifier.dispose();
    _visiblePageNotifier.dispose();
    _pageTicker?.dispose();
    _scrollingNotifier.dispose();

    // 🎬 Restore system UI when leaving reader
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive').value =
        false;
    MemoryBudgetCoordinator().onReaderActiveChanged(false);
    super.dispose();
  }

  void _flushReaderProgressBeforeDispose() {
    final state = _readerCubit.state;
    final content = state.content;
    if (content == null || content.pageCount <= 0) return;

    var pageToSave = state.currentPage ?? widget.initialPage;
    final visiblePage = _visiblePageNotifier.value;
    if (visiblePage > pageToSave) {
      pageToSave = visiblePage;
    }

    final validPage = pageToSave.clamp(1, content.pageCount);
    if (state.readingMode == ReadingMode.continuousScroll) {
      _readerCubit.updateCurrentPageSilent(validPage);
    } else {
      _readerCubit.updateCurrentPageFromSwipe(validPage);
    }
  }

  void _toggleImmersiveMode(bool immersive) {
    if (immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  void _scheduleFrameDecode() {
    if (_isDecodeTickScheduled) return;
    if (_decodeQueue.isEmpty) return;
    _isDecodeTickScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _isDecodeTickScheduled = false;
      if (!mounted || _scopeToken.isCancelled || _decodeQueue.isEmpty) return;
      for (int i = 0;
          i < _currentMaxDecodePerFrame && _decodeQueue.isNotEmpty;
          i++) {
        if (_scopeToken.isCancelled || !mounted) break;
        final task = _decodeQueue.removeAt(0);
        task();
      }
      if (_decodeQueue.isNotEmpty && !_scopeToken.isCancelled && mounted) {
        _scheduleFrameDecode();
      }
    });
  }

  void _prefetchImages(int currentPage, List<String> imageUrls,
      List<ImageMetadata>? imageMetadata,
      {String? sourceId, String? contentId}) {
    if (imageUrls.isEmpty) return;

    // detect fast scroll by page jump, not timer. If user moved
    // >3 pages since last tick, they're flying through — skip prefetch.
    final pageJump = (currentPage - _lastReportedPage).abs();
    if (pageJump > 3) return;

    final prefetchHeaders = sourceId == null
        ? null
        : getIt<ContentSourceRegistry>()
            .getSource(sourceId)
            ?.getImageDownloadHeaders(
              imageUrl:
                  imageUrls[(currentPage - 1).clamp(0, imageUrls.length - 1)],
            );

    // Network download + bookkeeping lives in ReaderPrefetchCubit (testable,
    // survives widget rebuild). Widget keeps the BuildContext-bound decode
    // pre-cache below.
    if (_scopeToken.isCancelled) return;
    final effectiveContentId = contentId ?? widget.contentId;
    _prefetchCubit.prefetchImages(
      currentPage: currentPage,
      imageUrls: imageUrls,
      imageMetadata: imageMetadata,
      sourceId: sourceId,
      headers: prefetchHeaders,
      contentId: effectiveContentId,
      cancelToken: _scopeToken,
    );

    //  pre-decode adjacent pages into ImageCache at display width.
    // Online → ExtendedNetworkImageProvider (HTTP → ExtendedImage disk cache).
    // Offline → ExtendedFileImageProvider from LocalImagePreloader's file.
    // Both wrapped in ExtendedResizeImage — same wrapper ExtendedImage
    // (network/file) uses internally via cacheWidth param.
    // Throttle: heavy source (ehentai/hentainexus) → 1/frame, normal → 2/frame for N±1
    final isHeavySource = _isHeavyPrefetchSource(sourceId);
    _currentMaxDecodePerFrame =
        isHeavySource ? _maxDecodePerFrameHeavy : _maxDecodePerFrame;
    final decodeWidth = (MediaQuery.of(context).size.width *
            MediaQuery.of(context).devicePixelRatio)
        .round();

    for (final int targetPage in <int>{currentPage + 1, currentPage - 1}) {
      if (targetPage >= 1 && targetPage <= imageUrls.length) {
        final rawUrl = imageUrls[targetPage - 1];
        final url = rawUrl.split('|').first;
        if (!url.startsWith('http')) continue;
        final effectiveContentIdForDecode = contentId ?? widget.contentId;
        _decodeQueue.add(() {
          if (!mounted || _scopeToken.isCancelled) return;
          LocalImagePreloader.getLocalImagePath(
            effectiveContentIdForDecode,
            targetPage,
          ).then((localPath) {
            if (!mounted || _scopeToken.isCancelled) return;
            final ImageProvider provider;
            if (localPath != null && File(localPath).existsSync()) {
              provider = ExtendedFileImageProvider(File(localPath));
            } else {
              provider =
                  ExtendedNetworkImageProvider(url, headers: prefetchHeaders);
            }
            precacheImage(
              ExtendedResizeImage.resizeIfNeeded(
                cacheWidth: decodeWidth,
                cacheHeight: null,
                provider: provider,
              ),
              context,
            );
          });
        });
      }
    }
    _scheduleFrameDecode();
  }

  // Evict excess pages when decoded image budget is exceeded.
  ///
  // Uses byte budget from [MemoryBudgetCoordinator] — estimates decoded size
  // per page (width × height × 4) and evicts farthest pages until under budget.
  // Eviction is skipped for offline content (pages are on disk).
  //  page-count heuristic replaced by byte-aware budget from coordinator.
  // Budget resets [_heavyImageBudgetResetMs] after last scroll tick.
  static const Duration _heavyImageBudgetResetMs = Duration(seconds: 5);
  int _estimatedDecodedBytes = 0;
  Timer? _heavyImageBudgetTimer;

  void _evictDistantPages(int currentPage, List<String> imageUrls,
      {bool isOffline = false}) {
    if (isOffline || imageUrls.isEmpty) return;

    final coordinator = MemoryBudgetCoordinator();
    final budget = coordinator.readerDecodedBudgetBytes;

    _heavyImageBudgetTimer?.cancel();
    _heavyImageBudgetTimer = Timer(_heavyImageBudgetResetMs, () {
      _estimatedDecodedBytes = 0;
    });

    // Real byte estimator: sum of window visible ± keepRadius (not tick accumulation)
    const keepRadius = 4;
    int windowBytes = 0;
    for (int p = currentPage - keepRadius; p <= currentPage + keepRadius; p++) {
      if (p >= 1 && p <= imageUrls.length) {
        windowBytes += _estimatePageBytes(p);
      }
    }
    _estimatedDecodedBytes = windowBytes;

    if (_estimatedDecodedBytes < budget) return;

    // Budget exceeded: evict farthest pages until ≤ 80% of budget.
    final target = (budget * 0.8).round();
    _evictFarthestBytes(currentPage, imageUrls, target);
    _estimatedDecodedBytes = target;
  }

  int _estimatePageBytes(int page) {
    final h = _cachedImageHeights[page];
    if (h == null || h <= 0) return 0;
    // Real decode width: viewport logical width * dpr capped like ExtendedImage cacheWidth.
    // Fallback 1080 only when MediaQuery not available (tests).
    double viewportWidth;
    try {
      viewportWidth = MediaQuery.of(context).size.width;
    } catch (_) {
      viewportWidth = 1080;
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (viewportWidth * dpr).clamp(360, 900).toDouble();
    // h is rendered height (logical px) at screen width; pixel height = h * dpr
    final pixelW = cacheWidth;
    final pixelH = h * dpr;
    return (pixelW * pixelH * 4).round(); // RGBA
  }

  void _evictFarthestBytes(
      int currentPage, List<String> imageUrls, int targetBytes) {
    const keepRadius = 4;
    final total = imageUrls.length;
    if (total <= keepRadius * 2 + 1) return;

    final sorted = List.generate(total, (i) => i + 1);
    sorted.sort(
        (a, b) => (b - currentPage).abs().compareTo((a - currentPage).abs()));

    int accumulated = 0;
    for (final page in sorted) {
      if ((page - currentPage).abs() <= keepRadius) continue;
      final url = imageUrls[page - 1];
      if (!url.startsWith('http')) continue;

      NetworkImage(url).evict();
      accumulated += _estimatePageBytes(page);
      if (accumulated >= (_estimatedDecodedBytes - targetBytes)) break;
    }
  }

  bool _isHeavyPrefetchSource(String? sourceId) {
    switch (sourceId?.toLowerCase()) {
      case 'hentainexus':
      case 'ehentai':
        return true;
      default:
        return false;
    }
  }

  bool _isContinuousScrollDisabledForCurrentContent() {
    return _autoSwitchedContentIds.contains(widget.contentId);
  }

  // DELETED: _getNextReadingMode (extracted to part file helper function)

  void _syncControllersWithState(ReaderState state) {
    final contentChanged = state.content?.id != _lastSyncedContentId;
    _lastSyncedContentId = state.content?.id;

    // Clear height cache when content changes (chapter navigation)
    // Prevents stale heights from previous chapter in continuous scroll.
    if (contentChanged) {
      _cachedImageHeights.clear();
      // Prefetch bookkeeping is per-chapter (page numbers collide across chapters)
      // Without clearing, _isPrefetched(page) returns true for new chapter's same page numbers
      // and skips download, causing stale images to be shown.
      _prefetchCubit.cancelAll();
      _decodeQueue.clear();
      _isDecodeTickScheduled = false;
      _lastReportedPage = state.currentPage ?? 1;
      _lastSavedPage = 0;
      _visiblePageNotifier.value = state.currentPage ?? 1;
      _animatedPauseNotifier.value = state.currentPage ?? 1;
      _scrollingNotifier.value = false;
    }

    // 🚀 OPTIMIZATION: Skip sync for continuous scroll when same content
    // Prevents scroll position reset when readingTimer updates state every second.
    // Allow sync when content changes (chapter navigation) so scroll resets to top.
    if (state.readingMode == ReadingMode.continuousScroll && !contentChanged) {
      return;
    }

    final currentPage = state.currentPage ?? 1;
    final targetPageIndex = currentPage - 1;

    if (state.readingMode == ReadingMode.singlePage) {
      if (_pageController.hasClients) {
        final currentPageControllerIndex = _pageController.page?.round();

        // Early return if already in sync - prevents infinite loop
        if (currentPageControllerIndex == targetPageIndex) {
          return;
        }

        final distance =
            ((currentPageControllerIndex ?? 0) - targetPageIndex).abs();

        if (distance > 5) {
          // Use immediate jump for large distances to avoid animation interruption
          _logger.d(
              '🔄 SYNC: Jumping PageController from $currentPageControllerIndex to $targetPageIndex (distance: $distance)');
          _isProgrammaticAnimation = true;
          _pageController.jumpToPage(targetPageIndex);
          _isProgrammaticAnimation = false;
        } else {
          // Use smooth animation for small distances
          _logger.d(
              '🔄 SYNC: Animating PageController from $currentPageControllerIndex to $targetPageIndex (distance: $distance)');
          _isProgrammaticAnimation = true;
          //  skip animation for rapid consecutive taps. User tapping
          // faster than animation duration expects instant response — queuing
          // animations makes offline images feel delayed.
          final timeSinceTap = DateTime.now().difference(_lastTapTime);
          final isRapidTap = timeSinceTap < DesignTokens.durationPageTurn;
          _lastTapTime = DateTime.now();
          if (isRapidTap) {
            _pageController.jumpToPage(targetPageIndex);
            _isProgrammaticAnimation = false;
          } else {
            _pageController
                .animateToPage(
              targetPageIndex,
              duration: DesignTokens.durationPageTurn,
              curve: Curves.easeOutCubic,
            )
                .then((_) {
              _isProgrammaticAnimation = false;
            });
          }
        }
      }
    } else if (state.readingMode == ReadingMode.verticalPage) {
      if (_verticalPageController.hasClients) {
        final currentVerticalIndex = _verticalPageController.page?.round();

        // Early return if already in sync - prevents infinite loop
        if (currentVerticalIndex == targetPageIndex) {
          return;
        }

        final distance = ((currentVerticalIndex ?? 0) - targetPageIndex).abs();

        if (distance > 5) {
          // Use immediate jump for large distances to avoid animation interruption
          _logger.d(
              '🔄 SYNC: Jumping VerticalPageController from $currentVerticalIndex to $targetPageIndex (distance: $distance)');
          _isProgrammaticAnimation = true;
          _verticalPageController.jumpToPage(targetPageIndex);
          _isProgrammaticAnimation = false;
        } else {
          // Use smooth animation for small distances
          _logger.d(
              '🔄 SYNC: Animating VerticalPageController from $currentVerticalIndex to $targetPageIndex (distance: $distance)');
          _isProgrammaticAnimation = true;
          _verticalPageController
              .animateToPage(
            targetPageIndex,
            duration: DesignTokens.durationNormal,
            curve: Curves.easeInOut,
          )
              .then((_) {
            _isProgrammaticAnimation = false;
          });
        }
      }
    } else if (state.readingMode == ReadingMode.continuousScroll) {
      if (state.content == null) return;
      final targetPage = state.currentPage ?? 1;
      final targetScrollOffset = (targetPage - 1) * 0.0; // page 1 → top

      // Defer to post-frame so ListView.builder is mounted with new content.
      // Without this, _scrollController may lack clients right after a chapter
      // change emit, or the old client's offset is stale.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final threshold = MediaQuery.of(context).size.height * 0.5;
        if ((_scrollController.offset - targetScrollOffset).abs() > threshold) {
          _scrollController.animateTo(
            targetScrollOffset,
            duration: DesignTokens.durationNormal,
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // _initializeFromRouteExtra now handled once in didChangeDependencies

    return BlocProvider<ReaderCubit>(
      create: (context) {
        // 🚀 OPTIMIZATION: Always pass preloaded content (from widget or route extra)
        final effectivePreloadedContent =
            _preloadedContent ?? widget.preloadedContent;
        final effectiveImageMetadata =
            _preloadedImageMetadata ?? widget.imageMetadata;
        final effectiveChapterData =
            _preloadedChapterData ?? widget.chapterData;
        final effectiveParentContent =
            _preloadedParentContent ?? widget.parentContent;
        final effectiveAllChapters =
            _preloadedAllChapters ?? widget.allChapters;
        final effectiveCurrentChapter =
            _preloadedCurrentChapter ?? widget.currentChapter;
        return _readerCubit
          ..loadContent(
            widget.contentId,
            initialPage: widget.initialPage,
            forceStartFromBeginning: widget.forceStartFromBeginning,
            preloadedContent: effectivePreloadedContent,
            imageMetadata: effectiveImageMetadata,
            chapterData: effectiveChapterData,
            parentContent: effectiveParentContent,
            allChapters: effectiveAllChapters,
            currentChapter: effectiveCurrentChapter,
          );
      },
      child: BlocListener<ReaderCubit, ReaderState>(
        listenWhen: (previous, current) {
          final prevContentId = previous.content?.id;
          final currContentId = current.content?.id;
          final prevImageCount = previous.content?.imageUrls.length ?? 0;
          final currImageCount = current.content?.imageUrls.length ?? 0;

          // Ignore timer-only or unrelated state updates.
          return previous.currentPage != current.currentPage ||
              previous.readingMode != current.readingMode ||
              previous.showUI != current.showUI ||
              prevContentId != currContentId ||
              prevImageCount != currImageCount;
        },
        listener: (context, state) {
          if (_isContinuousScrollDisabledForCurrentContent() &&
              state.readingMode == ReadingMode.continuousScroll) {
            _readerCubit.changeReadingMode(
              ReadingMode.singlePage,
              persistPreference: false,
              resetWebtoonDetection: false,
            );
            return;
          }

          _syncControllersWithState(state);

          _toggleImmersiveMode(!(state.showUI ?? false));

          // Prefetch only for continuous scroll — PageView handles its own
          // image caching via ExtendedImage's item builder. Manual precache
          // in non-CS modes competes for IO thread on rapid taps.
          if (state.readingMode == ReadingMode.continuousScroll &&
              state.content != null &&
              state.content!.imageUrls.isNotEmpty) {
            final currentPage = state.currentPage ?? widget.initialPage;
            _prefetchImages(
              currentPage,
              state.content!.imageUrls,
              state.imageMetadata,
              sourceId: state.content?.sourceId,
              contentId: state.content!.id,
            );
          }
        },
        child: BlocBuilder<ReaderCubit, ReaderState>(
          buildWhen: (previous, current) {
            final prevContentId = previous.content?.id;
            final currContentId = current.content?.id;
            final prevImageCount = previous.content?.imageUrls.length ?? 0;
            final currImageCount = current.content?.imageUrls.length ?? 0;

            final onlyCurrentPageChanged =
                previous.currentPage != current.currentPage &&
                    previous.runtimeType == current.runtimeType &&
                    prevContentId == currContentId &&
                    prevImageCount == currImageCount &&
                    previous.showUI == current.showUI &&
                    previous.readingMode == current.readingMode &&
                    previous.enableZoom == current.enableZoom &&
                    previous.keepScreenOn == current.keepScreenOn &&
                    previous.isOfflineMode == current.isOfflineMode;

            final isContinuousMode =
                current.readingMode == ReadingMode.continuousScroll;

            if (isContinuousMode && onlyCurrentPageChanged) {
              return false;
            }

            // Prevent full-screen rebuild every second from readingTimer.
            return previous.runtimeType != current.runtimeType ||
                prevContentId != currContentId ||
                prevImageCount != currImageCount ||
                previous.content != current.content ||
                previous.currentPage != current.currentPage ||
                previous.showUI != current.showUI ||
                previous.readingMode != current.readingMode ||
                previous.enableZoom != current.enableZoom ||
                previous.keepScreenOn != current.keepScreenOn ||
                previous.isOfflineMode != current.isOfflineMode;
          },
          builder: (context, state) {
            return Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 50 || constraints.maxHeight < 50) {
                    return const SizedBox.shrink();
                  }
                  return _buildBody(state);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(ReaderState state) {
    if (state.status == ReaderStatus.loading) {
      return Center(
        child: AppProgressIndicator(
          message: AppLocalizations.of(context)?.loadingContent ??
              AppLocalizations.of(context)!.loadingContent,
        ),
      );
    }

    if (state.status == ReaderStatus.error) {
      return Center(
        child: AppErrorWidget(
          title: AppLocalizations.of(context)!.loadingError,
          message: state.message ?? '',
          onRetry: () => _readerCubit.loadContent(
            widget.contentId,
            initialPage: widget.initialPage,
            forceStartFromBeginning: widget.forceStartFromBeginning,
            preloadedContent: widget.preloadedContent,
            imageMetadata: widget.imageMetadata,
            chapterData: widget.chapterData,
            parentContent: widget.parentContent,
            allChapters: widget.allChapters,
            currentChapter: widget.currentChapter,
          ),
        ),
      );
    }
    return _ReaderContentWidget(
      state: state,
      cubit: _readerCubit,
      pageController: _pageController,
      verticalPageController: _verticalPageController,
      scrollController: _scrollController,
      visiblePageNotifier: _visiblePageNotifier,
      animatedPauseNotifier: _animatedPauseNotifier,
      scrollingNotifier: _scrollingNotifier,
      contentId: widget.contentId,
      chapterOverlayShown: _chapterOverlayShown,
      isProgrammaticAnimation: _isProgrammaticAnimation,
      logger: _logger,
      onHeavyImageDetected: _onHeavyImageDetected,
      onContinuousImageLoaded: _onContinuousImageLoaded,
      onRepairBrokenImage: _repairBrokenImage,
      onOpenSourcePageForRepair: _openSourcePageForRepair,
      onScrollNotification: _onScrollNotification,
      onShowSettings: _showReaderSettingsEntity,
      onDismissChapterOverlay: () {
        if (mounted) setState(() => _chapterOverlayShown = true);
      },
      prefetchImages: _prefetchImages,
      evictDistantPages: _evictDistantPages,
      resolveContinuousItemHeight: _resolveContinuousItemHeight,
      isHeavyPrefetchSource: _isHeavyPrefetchSource,
      isContinuousScrollDisabled: _isContinuousScrollDisabledForCurrentContent,
      getNextReadingMode: _getNextReadingMode,
    );
  }

  void _showReaderSettingsEntity(ReaderState state) {
    final disableContinuous = _isContinuousScrollDisabledForCurrentContent();
    final readingModeLabel = disableContinuous
        ? '${_getReadingModeLabel(context, state.readingMode ?? ReadingMode.singlePage)} • ${AppLocalizations.of(context)!.readerContinuousOffHeavyImage}'
        : _getReadingModeLabel(
            context, state.readingMode ?? ReadingMode.singlePage);
    final tapDirectionDescription = _getTapDirectionDescription(
        context, state.tapDirection ?? TapDirection.normal);
    final activeLanguage = _normalizeLanguageForFilter(
        state.currentChapter?.language ??
            _preloadedActiveChapterLanguage ??
            widget.activeChapterLanguage);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocBuilder<ReaderCubit, ReaderState>(
        bloc: _readerCubit,
        builder: (context, currentState) => _ReaderSettingsSheet(
          cubit: _readerCubit,
          state: currentState,
          readingModeLabel: readingModeLabel,
          tapDirectionDescription: tapDirectionDescription,
          onShowResetConfirmation: () => _showResetConfirmationDialog(
              context, () => _resetReaderSettings(context, _readerCubit)),
          onShowChapterSelector: () {
            context.pop();
            _showChapterSelector(context, _readerCubit, currentState,
                activeLanguage: activeLanguage);
          },
          onClearImageCache: () => _clearReaderImageCache(context),
        ),
      ),
    );
  }
}
