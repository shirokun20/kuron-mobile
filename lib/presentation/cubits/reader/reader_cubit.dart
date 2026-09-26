import 'dart:async';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_generic/kuron_generic.dart'
    show PageResolutionPipeline, PageResolutionInput;
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:kuron_core/kuron_core.dart';
import '../../../domain/entities/reader_position.dart';
import '../../../domain/usecases/reader/get_reader_settings_usecase.dart';
import '../../../domain/usecases/reader/save_reader_settings_usecase.dart';
import '../../../domain/usecases/reader/save_reader_position_usecase.dart';
import '../../../domain/usecases/reader/clear_all_reader_positions_usecase.dart';
import '../../../domain/usecases/reader/get_reader_position_usecase.dart';
import '../../../domain/usecases/content/get_content_detail_usecase.dart';
import '../../../domain/usecases/content/get_chapter_images_usecase.dart';
import '../../../domain/usecases/history/add_to_history_usecase.dart';
import '../../../domain/repositories/reader_settings_repository.dart';
import '../../../domain/repositories/reader_repository.dart';
import '../../../domain/entities/reader_settings_entity.dart';
import '../../../core/utils/offline_content_manager.dart';
import '../../../core/di/service_locator.dart';
import '../recommendations/recommendation_refresh_bus.dart';
import '../../../core/utils/chapter_id_classifier.dart';
import '../../../core/utils/reader_image_repair_utils.dart';
import '../../../core/models/image_metadata.dart';
import '../../../core/config/remote_config_service.dart';
import '../../../core/services/image_metadata_service.dart';
import '../../../core/services/local_image_preloader.dart';
import '../../widgets/content_list_widget.dart';
import '../../utils/chapter_language_presenter.dart';
import '../network/network_cubit.dart';
import '../../../core/utils/webtoon_detector.dart';

part 'reader_state.dart';

typedef ReaderImageRepairResult = ({
  bool success,
  String reason,
  int? statusCode,
});

typedef ReaderManualRepairContext = ({
  String sourceId,
  String sourcePageUrl,
  String? initialCookie,
});

class ReaderCubit extends Cubit<ReaderState> {
  static const String _ehentaiPartPrefix = '__ehpart__';
  static const String _ehentaiChunkPrefix = '__ehchunk__';
  static const int _maxEhentaiRepairChunks = 150;

  ReaderCubit({
    required this.getContentDetailUseCase,
    required this.getChapterImagesUseCase,
    required this.addToHistoryUseCase,
    required this.getReaderSettingsUseCase,
    required this.saveReaderSettingsUseCase,
    required this.saveReaderPositionUseCase,
    required this.clearAllReaderPositionsUseCase,
    required this.getReaderPositionUseCase,
    required this.readerSettingsEntityRepository,
    required this.readerRepository,
    required this.offlineContentManager,
    required this.networkCubit,
    required this.imageMetadataService,
    required this.httpClient,
    required this.contentSourceRegistry,
    required this.ehentaiCookieJar,
    required this.remoteConfigService,
    required Logger logger,
  })  : _logger = logger,
        super(const ReaderState());

  final GetContentDetailUseCase getContentDetailUseCase;
  final GetChapterImagesUseCase getChapterImagesUseCase;
  final AddToHistoryUseCase addToHistoryUseCase;
  final GetReaderSettingsUseCase getReaderSettingsUseCase;
  final SaveReaderSettingsUseCase saveReaderSettingsUseCase;
  final SaveReaderPositionUseCase saveReaderPositionUseCase;
  final ClearAllReaderPositionsUseCase clearAllReaderPositionsUseCase;
  final GetReaderPositionUseCase getReaderPositionUseCase;
  final ReaderSettingsEntityRepository readerSettingsEntityRepository;
  final ReaderRepository readerRepository;
  final OfflineContentManager offlineContentManager;
  final NetworkCubit networkCubit;
  final ImageMetadataService imageMetadataService;
  final Dio httpClient;
  final ContentSourceRegistry contentSourceRegistry;
  final PersistCookieJar ehentaiCookieJar;
  final RemoteConfigService remoteConfigService;
  final Logger _logger;

  Timer? _readingTimer;
  Timer? _autoHideTimer;

  // Webtoon/manhwa auto-detection
  bool _hasDetectedWebtoon = false;

  // Lifecycle state for background/foreground tracking
  bool _isBackgrounded = false;
  bool _wasKeepScreenOnBeforePause = false;

  // Chapter navigation context
  Content? _parentContent; // Parent series for chapter navigation
  List<Chapter>? _allChapters; // All chapters available for navigation
  int _lastTrackedPage =
      1; // Tracks current page for persistence even when state is silent

  // Recommendation refresh dedupe: fire once per content at ≥90% completion.
  String? _lastRecRefreshKey;

  Content? get parentContent => _parentContent;

  ReaderState _withStatus(ReaderStatus newStatus) {
    final s = state;
    return ReaderState(
      status: newStatus,
      content: s.content,
      currentPage: s.currentPage,
      readingMode: s.readingMode,
      showUI: s.showUI,
      keepScreenOn: s.keepScreenOn,
      enableZoom: s.enableZoom,
      readingTimer: s.readingTimer ?? Duration.zero,
      message: s.message,
      isOfflineMode: s.isOfflineMode ?? false,
      imageMetadata: s.imageMetadata,
      chapterData: s.chapterData,
      currentChapter: s.currentChapter,
      tapDirection: s.tapDirection ?? TapDirection.normal,
    );
  }

  List<Chapter>? get allChapters => _allChapters;

  Future<void> loadContent(
    String contentId, {
    int initialPage = 1,
    bool forceStartFromBeginning = false,
    Content? preloadedContent,
    List<ImageMetadata>? imageMetadata,
    ChapterData? chapterData,
    Content? parentContent,
    List<Chapter>? allChapters,
    Chapter? currentChapter,
  }) async {
    try {
      _stopAutoHideTimer();
      emit(_withStatus(ReaderStatus.loading));

      _parentContent = parentContent;
      _allChapters = allChapters;

      // Fast-path: preloaded already has imageUrls → defer heavy sync work.
      // Spec reader-coldstart-fastpath: emit loaded without awaiting offline scan + bypass seeding.
      final fastPathEligible =
          preloadedContent != null && preloadedContent.imageUrls.isNotEmpty;
      if (fastPathEligible) {
        unawaited(_backgroundSeedBypassCaches());
      } else {
        // Cold-start bridge: seed static bypass header caches from persisted
        // cookie jars so image requests carry a still-valid cf_clearance even
        // when the reader is the first screen after an app restart.
        // Only for non-fast-path (fast-path does it in background).
        try {
          final configService = getIt<RemoteConfigService>();
          for (final cfg in configService.getAllSourceConfigs()) {
            final sourceId = cfg.source;
            final raw = configService.getRawConfig(sourceId);
            if (raw == null) continue;
            final network = raw['network'] as Map<String, dynamic>?;
            if (network == null) continue;
            final cf = network['cloudflare'] as Map<String, dynamic>?;
            final requiresBypass = network['requiresBypass'] == true;
            final cloudflareBypass = cf?['bypassEnabled'] == true;
            if (!requiresBypass && !cloudflareBypass) continue;
            if (getIt.isRegistered<WebViewSessionAdapter>(
                instanceName: 'cf_$sourceId')) {
              await getIt<WebViewSessionAdapter>(instanceName: 'cf_$sourceId')
                  .seedBypassHeaderCacheFromJar();
            }
          }
        } catch (_) {
          // Best-effort — bypass flow repopulates caches on first challenge.
        }
      }

      // 🔍 DEBUG LOGGING
      _logger.i('📥 ReaderCubit.loadContent - Received:');
      _logger.i('  contentId: $contentId');
      _logger.i('  preloadedContent: ${preloadedContent?.title ?? "NULL"}');
      _logger.i('  parentContent: ${parentContent?.title ?? "NULL"}');
      _logger.i('  parentContent.id: ${parentContent?.id ?? "NULL"}');
      _logger.i('  allChapters: ${allChapters?.length ?? 0} chapters');
      if (allChapters != null && allChapters.isNotEmpty) {
        _logger.i(
            '    First: ${allChapters.first.title} (${allChapters.first.id})');
        _logger
            .i('    Last: ${allChapters.last.title} (${allChapters.last.id})');
      }
      _logger.i('  currentChapter: ${currentChapter?.title ?? "NULL"}');
      _logger.i(
          '  chapterData: prev=${chapterData?.prevChapterId}, next=${chapterData?.nextChapterId}');
      _logger.i('');
      _logger.i('  Stored in ReaderCubit:');
      _logger.i('  _parentContent: ${_parentContent?.title ?? "NULL"}');
      _logger.i('  _allChapters: ${_allChapters?.length ?? 0} chapters');

      final isConnected = networkCubit.isConnected;
      final sourceHint = _resolveSourceHint(
        preloadedContent: preloadedContent,
        parentContent: parentContent,
      );
      final isCrotpediaChapter =
          _isCrotpediaChapterId(contentId, sourceId: sourceHint);

      // Fast-path: skip offline scan, assume remote for now, background check updates badge later
      bool? isOfflineAvailable;
      if (!fastPathEligible) {
        isOfflineAvailable =
            await offlineContentManager.isContentAvailableOffline(contentId);
      }

      final localResults = await Future.wait([
        _loadReaderSettingsEntityOptimized(),
        if (forceStartFromBeginning)
          Future<int>.value(1)
        else
          _restoreReaderPosition(contentId),
      ]);

      final savedSettings = localResults[0] as ReaderSettingsEntity;
      final restoredPage = localResults[1] as int;

      final startPage = initialPage > 1
          ? initialPage
          : (restoredPage > 1 ? restoredPage : initialPage);

      _lastTrackedPage = startPage;

      Content? content;
      bool isOfflineMode = false;

      // Strategy A: Preloaded Content
      final hasPreloadedContent = preloadedContent != null;
      final shouldUseImagePreloaded =
          hasPreloadedContent && preloadedContent.imageUrls.isNotEmpty;
      final shouldUseNoChapterPreloaded = hasPreloadedContent &&
          preloadedContent.imageUrls.isEmpty &&
          chapterData == null &&
          (allChapters == null || allChapters.isEmpty);
      if (shouldUseImagePreloaded) {
        final hasLocalPaths =
            preloadedContent.imageUrls.any((url) => url.startsWith('/'));
        if (hasLocalPaths) {
          _logger
              .i('✅ Strategy A: Using preloaded OFFLINE content: $contentId');
          content = preloadedContent;
          isOfflineMode = true;
        } else {
          final hasRemoteUrls =
              preloadedContent.imageUrls.any((url) => url.startsWith('http'));

          if (isOfflineAvailable == true && hasRemoteUrls) {
            _logger.i(
                '💾 Strategy A2: Found offline available, loading from local storage');
            content =
                await offlineContentManager.createOfflineContent(contentId);
            isOfflineMode = true;
          } else if (hasRemoteUrls) {
            _logger.i(
                '✅ Strategy A3: Using preloaded content with remote URLs: $contentId');
            content = preloadedContent;
            isOfflineMode = !isConnected;
            // Fast-path: schedule background offline check to update badge without blocking
            if (fastPathEligible && isOfflineAvailable == null) {
              unawaited(_backgroundOfflineCheck(contentId));
            }
          }
        }
      }
      // Strategy A4: Fast metadata-only shell (no images yet).
      // Upgrade to offline content with imageUrls if available.
      //  single fallback path, add multi-source retry if needed.
      if (content == null && shouldUseNoChapterPreloaded) {
        _logger.i(
            '✅ Strategy A4: Using preloaded no-chapters content shell: $contentId');
        content = preloadedContent;
        isOfflineMode = !isConnected;
        if (isOfflineAvailable == true) {
          final offlineContent =
              await offlineContentManager.createOfflineContent(contentId);
          if (offlineContent != null) {
            content = offlineContent;
            isOfflineMode = true;
          }
        }
      }

      // Strategy B: Offline Content
      if (content == null && isOfflineAvailable == true) {
        _logger.i(
            '💾 Strategy B: Loading content from offline storage: $contentId');
        content = await offlineContentManager.createOfflineContent(contentId);
        isOfflineMode = true;

        if (isConnected && !isCrotpediaChapter) {
          await _fetchOnlineDetailsInBackground(contentId);
        }
      }
      // Strategy C: Online Content
      else if (content == null && isConnected && !isCrotpediaChapter) {
        _logger.i('🌐 Strategy C: Fetching online content: $contentId');
        try {
          content = await getContentDetailUseCase(
              GetContentDetailParams.fromString(contentId,
                  sourceId: sourceHint));
          isOfflineMode = false;
        } catch (e) {
          _logger.w('Online fetch failed: $e');
        }
      }
      // Strategy D: Last Resort Fallback
      if (content == null) {
        _logger.i('🔍 READER_CUBIT all strategies failed, entering Strategy D');
        if (preloadedContent != null && preloadedContent.imageUrls.isNotEmpty) {
          _logger.i(
              '🔍 READER_CUBIT Strategy D using preloaded fallback imageUrls=${preloadedContent.imageUrls.length}');
          _logger.w(
              '⚠️ Strategy D: Using preloaded content as fallback: $contentId');
          content = preloadedContent;
          isOfflineMode = !isConnected;
        } else {
          try {
            content =
                await offlineContentManager.createOfflineContent(contentId);
            if (content != null) isOfflineMode = true;
          } catch (_) {
            _logger.w('Offline content creation fallback failed');
          }
        }
      }

      if (content == null) {
        if (isCrotpediaChapter) {
          throw Exception(
              'Chapter not available offline. Please access this chapter from the series detail page to read online.');
        }
        throw Exception('Content not available online or offline');
      }

      // Fetch ChapterData if missing (for navigation)
      if (chapterData == null && isConnected && isCrotpediaChapter) {
        try {
          _logger
              .i('🔍 Fetching missing chapter data for navigation: $contentId');
          final fetchedChapterData =
              await getChapterImagesUseCase(GetChapterImagesParams.fromString(
            contentId,
            sourceId: content.sourceId,
          ));
          chapterData = fetchedChapterData;
        } catch (e) {
          _logger.w('Failed to fetch chapter navigation data: $e');
          // Start without navigation rather than failing completely
        }
      }

      // Fallback: detail payload has no image URLs, fetch from chapter endpoint
      if (content.imageUrls.isEmpty &&
          (isConnected || shouldUseNoChapterPreloaded)) {
        try {
          _logger.i(
              '🖼️ Content has no imageUrls, fetching chapter images fallback: $contentId');
          final fallbackChapterData =
              await getChapterImagesUseCase(GetChapterImagesParams.fromString(
            contentId,
            sourceId: content.sourceId,
          ));

          if (fallbackChapterData.images.isNotEmpty) {
            content = content.copyWith(
              imageUrls: fallbackChapterData.images,
              pageCount: fallbackChapterData.images.length,
            );

            // Preserve any previously fetched chapterData, but if absent,
            // keep fallback navigation so next/prev can still work.
            chapterData ??= fallbackChapterData;

            // §8.2 — Run pipeline to emit download-readiness diagnostics.
            // Non-blocking; only logs. Full pipeline-based resolution is a
            // future enhancement once adapter outputs are wired through
            // ResolvedChapterPages end-to-end.
            final pipelineResult = const PageResolutionPipeline().resolve(
              PageResolutionInput(
                sourceId: content.sourceId,
                contentId: contentId,
                chapterId: null,
                imageUrls: fallbackChapterData.images,
              ),
            );
            if (!pipelineResult.pages.isDownloadReady) {
              _logger.w(
                'Reader pipeline: download not ready for $contentId — '
                '${pipelineResult.diagnostics.map((d) => d.code).join(', ')}',
              );
            }

            _logger.i(
                '✅ Fallback loaded ${fallbackChapterData.images.length} images for: $contentId');
          } else {
            _logger.w(
                '⚠️ Fallback chapter image fetch returned empty for: $contentId');
          }
        } catch (e) {
          _logger.w('Fallback chapter image fetch failed for $contentId: $e');
        }
      }

      // Emit Loaded State
      emit(ReaderState(
        status: ReaderStatus.loaded,
        content: content!,
        currentPage: startPage,
        readingMode: savedSettings.readingMode,
        showUI: savedSettings.showUI,
        keepScreenOn: savedSettings.keepScreenOn,
        readingTimer: Duration.zero,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: savedSettings.tapDirection,
      ));

      _logImageUrlMapping(content);
      emit(_withStatus(ReaderStatus.loaded));

      await _handlePostLoadSetup(savedSettings);
    } catch (e, stackTrace) {
      _logger.e('Reader Cubit Error: $e', error: e, stackTrace: stackTrace);
      _stopAutoHideTimer();
      if (!isClosed) {
        emit(_withStatus(ReaderStatus.error)
            .copyWithMessage('failedLoadContentError'));
      }
    }
  }

  Future<void> _backgroundSeedBypassCaches() async {
    try {
      final configService = getIt<RemoteConfigService>();
      for (final cfg in configService.getAllSourceConfigs()) {
        final sourceId = cfg.source;
        final raw = configService.getRawConfig(sourceId);
        if (raw == null) continue;
        final network = raw['network'] as Map<String, dynamic>?;
        if (network == null) continue;
        final cf = network['cloudflare'] as Map<String, dynamic>?;
        final requiresBypass = network['requiresBypass'] == true;
        final cloudflareBypass = cf?['bypassEnabled'] == true;
        if (!requiresBypass && !cloudflareBypass) continue;
        if (getIt.isRegistered<WebViewSessionAdapter>(
            instanceName: 'cf_$sourceId')) {
          await getIt<WebViewSessionAdapter>(instanceName: 'cf_$sourceId')
              .seedBypassHeaderCacheFromJar();
        }
      }
    } catch (_) {}
  }

  Future<void> _backgroundOfflineCheck(String contentId) async {
    try {
      final available =
          await offlineContentManager.isContentAvailableOffline(contentId);
      if (available && !isClosed && state.content?.id == contentId) {
        // Update badge only, don't reload content while reading
        _logger
            .i('🔄 Background offline check: $contentId is offline available');
      }
    } catch (_) {}
  }

  Future<void> _fetchOnlineDetailsInBackground(String contentId) async {
    try {
      // For composite chapter IDs (e.g. "doctors-rebirth/234"), extract only
      // the parent slug for the series detail request. Using the full composite
      // ID would build an invalid URL like /series/doctors-rebirth/234 → 404.
      final parentId = _extractParentContentId(contentId);
      await getContentDetailUseCase(
          GetContentDetailParams.fromString(parentId));
      // Results are cached by repository, so next load handles it.
      // We don't update current UI to avoid jarring changes while reading.
    } catch (e) {
      // Ignore background errors
    }
  }

  Future<ReaderSettingsEntity> _loadReaderSettingsEntityOptimized() async {
    try {
      return await getReaderSettingsUseCase();
    } catch (e) {
      _logger.w('Failed to load reader settings, using defaults: $e');
      return const ReaderSettingsEntity();
    }
  }

  Future<void> _handlePostLoadSetup(ReaderSettingsEntity savedSettings) async {
    try {
      if (savedSettings.keepScreenOn) {
        await WakelockPlus.enable();
      }

      _startReadingTimer();

      await _saveToHistory();
    } catch (e) {
      _logger.w('Post-load setup failed: $e');
    }
  }

  void nextPage() {
    if (!isClosed && state.content != null) {
      final currentPage = state.currentPage ?? 1;
      final pageCount = state.content!.pageCount;

      // Allow +1 for navigation page if exists
      final hasNavigationPage = !(state.isOfflineMode ?? false) &&
          state.content!.imageUrls.isNotEmpty;

      final maxPage = hasNavigationPage ? pageCount + 1 : pageCount;

      if (currentPage < maxPage) {
        final newPage = (currentPage + 1).clamp(1, maxPage);

        _logger.d(
            'Next page: $currentPage -> $newPage (total: $pageCount, max with nav: $maxPage)');

        _lastTrackedPage = newPage;
        emit(state.copyWithPage(newPage));
        _saveReaderPosition();
        _saveToHistory();
      } else {
        _logger.d('Already at last page ($currentPage), cannot go further');
      }
    }
  }

  void previousPage() {
    if (!state.isFirstPage && !isClosed && state.content != null) {
      final currentPage = state.currentPage ?? 1;
      final newPage = (currentPage - 1).clamp(1, state.content!.pageCount);

      _logger.d(
          'Previous page: $currentPage -> $newPage (total: ${state.content!.pageCount})');

      _lastTrackedPage = newPage;
      emit(state.copyWithPage(newPage));
      _saveReaderPosition();
      _saveToHistory();
    }
  }

  Future<void> loadNextChapter() async {
    await _saveToHistory();

    var nextChapterId = _resolveNextChapterId();
    // If boundary hit, try fetching the next page.
    if (nextChapterId == null) {
      final poolSize = _allChapters?.length ?? 0;
      if (poolSize > 0) {
        // Pool expanded by bottom sheet — no more pages to fetch.
        if (poolSize > _configuredPageLimit) {
          _logger.d('No next chapter (pool already expanded)');
          return;
        }
        final nextPage = poolSize ~/ _configuredPageLimit + 1;
        await _fetchAndMergePage(nextPage);
        nextChapterId = _resolveNextChapterId();
      }
    }

    if (nextChapterId == null) {
      _logger.d('No next chapter available');
      return;
    }

    if (_isEhentaiPartId(nextChapterId)) {
      await loadChapter(nextChapterId);
      return;
    }

    if (_isEhentaiChunkId(nextChapterId)) {
      await _appendEhentaiChunk(nextChapterId);
      return;
    }

    await loadChapter(nextChapterId);
  }

  Future<void> loadPreviousChapter() async {
    await _saveToHistory();

    var previousChapterId = _resolvePreviousChapterId();
    // If boundary hit, try fetching the previous page.
    if (previousChapterId == null) {
      final poolSize = _allChapters?.length ?? 0;
      if (poolSize > 0) {
        // Pool expanded by bottom sheet — no more pages to fetch.
        if (poolSize > _configuredPageLimit) {
          _logger.d('No previous chapter (pool already expanded)');
          return;
        }
        await _fetchAndMergePage(1);
        previousChapterId = _resolvePreviousChapterId();
      }
    }

    if (previousChapterId == null) {
      _logger.d('No previous chapter available');
      return;
    }

    if (_isEhentaiPartId(previousChapterId)) {
      await loadChapter(previousChapterId);
      return;
    }

    if (_isEhentaiChunkId(previousChapterId)) {
      _logger.d('Previous EHentai chunk navigation is not enabled');
      return;
    }

    await loadChapter(previousChapterId);
  }

  bool _isEhentaiPartId(String id) => id.startsWith(_ehentaiPartPrefix);

  bool _isEhentaiChunkId(String id) => id.startsWith(_ehentaiChunkPrefix);

  bool _isEhentaiVirtualChapterId(String id) {
    return _isEhentaiPartId(id) || _isEhentaiChunkId(id);
  }

  Future<void> _appendEhentaiChunk(String chunkId) async {
    if (state.content == null) {
      return;
    }

    final sourceId = _parentContent?.sourceId ?? state.content!.sourceId;
    final beforeCount = state.content!.imageUrls.length;

    try {
      final chunkData =
          await getChapterImagesUseCase(GetChapterImagesParams.fromString(
        chunkId,
        sourceId: sourceId,
      ));

      if (chunkData.images.isEmpty) {
        _logger.w('EHentai chunk returned no images: $chunkId');
        return;
      }

      final merged = <String>[];
      final seen = <String>{};
      for (final url in state.content!.imageUrls) {
        if (seen.add(url)) merged.add(url);
      }
      for (final url in chunkData.images) {
        if (seen.add(url)) merged.add(url);
      }

      final newContent = state.content!.copyWith(
        imageUrls: merged,
        pageCount: merged.length,
      );

      var targetPage = state.currentPage ?? 1;
      if (targetPage >= beforeCount) {
        targetPage = (beforeCount + 1).clamp(1, merged.length);
      }

      _lastTrackedPage = targetPage;

      emit(_withStatus(ReaderStatus.loaded)
          .copyWithContent(content: newContent, chapterData: chunkData)
          .copyWithPage(targetPage));

      _logger.i(
          'Appended EHentai chunk: +${chunkData.images.length} images (total ${merged.length})');

      await _saveReaderPosition();
      await _saveToHistory();
    } catch (e) {
      _logger.e('Failed to append EHentai chunk $chunkId: $e');
    }
  }

  bool get hasNextChapter => _resolveNextChapterId() != null;

  bool get hasPreviousChapter => _resolvePreviousChapterId() != null;

  Future<void> loadMoreChapters() async {
    if (_allChapters == null || _allChapters!.isEmpty) return;
    final nextPage = _allChapters!.length ~/ _configuredPageLimit + 1;
    await _fetchAndMergePage(nextPage);
  }

  int get _configuredPageLimit {
    final sourceId = _parentContent?.sourceId ?? state.content?.sourceId;
    if (sourceId == null) return 100;
    final rawCfg = remoteConfigService.getRawConfig(sourceId);
    final chapterCfg = rawCfg?['api']?['detail']?['chapters'] as Map? ??
        rawCfg?['api']?['chapters'] as Map?;
    final endpoint = chapterCfg?['endpoint']?.toString() ?? '';
    final match = RegExp(r'limit=(\d+)').firstMatch(endpoint);
    return match != null ? int.parse(match.group(1)!) : 100;
  }

  Future<int> _fetchAndMergePage(int page) async {
    final sourceId = _parentContent?.sourceId ?? state.content?.sourceId;
    final currentChapter = state.currentChapter;
    if (sourceId == null || currentChapter == null) return 0;

    final source = contentSourceRegistry.getSource(sourceId);
    if (source == null) return 0;

    final limit = _configuredPageLimit;

    try {
      final incoming = await source.getChapters(
        _parentContent?.id ?? state.content?.id ?? '',
        language: currentChapter.language,
        scanGroup: currentChapter.scanGroup,
        page: page,
        limit: limit,
      );
      if (incoming.isEmpty) return 0;

      final existing = _allChapters ?? [];
      final seenIds = existing.map((c) => c.id).toSet();
      final merged = <Chapter>[...existing];
      for (final chapter in incoming) {
        if (seenIds.add(chapter.id)) merged.add(chapter);
      }

      // Sort ascending by chapter number
      merged.sort((a, b) {
        final aNum = _extractChapterValue(a.title) ?? double.infinity;
        final bNum = _extractChapterValue(b.title) ?? double.infinity;
        final cmp = aNum.compareTo(bNum);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });

      _allChapters = merged;
      return incoming.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _ensureChapterInPool(String chapterId) async {
    if (_allChapters == null) return;
    final exists = _allChapters!.any((c) => c.id == chapterId);
    if (exists || _allChapters!.isEmpty) return;

    // Pool already expanded by bottom-sheet load more — chapter genuinely missing.
    if (_allChapters!.length > _configuredPageLimit) return;

    // Try a reasonable range of pages forward
    for (int page = 1; page <= 5; page++) {
      final added = await _fetchAndMergePage(page);
      if (_allChapters!.any((c) => c.id == chapterId)) return;
      if (added == 0) break; // no more pages
    }
  }

  String? _resolveNextChapterId() {
    final preferredLanguage = _currentChapterLanguageKey();
    if (preferredLanguage != null) {
      return _resolveAdjacentChapterId(
        step: 1,
        preferredLanguage: preferredLanguage,
      );
    }

    // Prefer pool lookup so IDs match _allChapters format.
    // Fallback to chapterData only when pool gives nothing.
    final poolId = _resolveAdjacentChapterId(step: 1);
    if (poolId != null) return poolId;

    final directNextId = state.chapterData?.nextChapterId;
    if (directNextId != null && directNextId.isNotEmpty) {
      return directNextId;
    }

    return null;
  }

  String? _resolvePreviousChapterId() {
    final preferredLanguage = _currentChapterLanguageKey();
    if (preferredLanguage != null) {
      return _resolveAdjacentChapterId(
        step: -1,
        preferredLanguage: preferredLanguage,
      );
    }

    // Prefer pool lookup so IDs match _allChapters format.
    // Fallback to chapterData only when pool gives nothing.
    final poolId = _resolveAdjacentChapterId(step: -1);
    if (poolId != null) return poolId;

    final directPrevId = state.chapterData?.prevChapterId;
    if (directPrevId != null && directPrevId.isNotEmpty) {
      return directPrevId;
    }

    return null;
  }

  String? _resolveAdjacentChapterId({
    required int step,
    String? preferredLanguage,
  }) {
    if (_allChapters == null || _allChapters!.isEmpty) {
      return null;
    }

    // Filter by current scanGroup (chapters vs volumes) so prev/next navigation
    // stays within the same type.
    final currentScanGroup = state.currentChapter?.scanGroup;
    var chapterPool = currentScanGroup == null
        ? _allChapters!
        : _allChapters!
            .where((chapter) => chapter.scanGroup == currentScanGroup)
            .toList();

    if (chapterPool.isEmpty) {
      return null;
    }

    if (preferredLanguage != null) {
      chapterPool = chapterPool
          .where((chapter) =>
              _normalizeLanguageKey(chapter.language) == preferredLanguage)
          .toList();
    }

    if (chapterPool.isEmpty) {
      return null;
    }

    final currentChapterId = state.currentChapter?.id ?? state.content?.id;
    if (currentChapterId == null || currentChapterId.isEmpty) {
      return null;
    }

    final currentIndex =
        chapterPool.indexWhere((chapter) => chapter.id == currentChapterId);
    if (currentIndex == -1) {
      return null;
    }

    final isAscending = _isAscendingByChapterNumber(chapterPool);
    final effectiveStep =
        isAscending == null ? step : (isAscending ? step : -step);

    final targetIndex = currentIndex + effectiveStep;
    if (targetIndex < 0 || targetIndex >= chapterPool.length) {
      return null;
    }

    final targetChapterId = chapterPool[targetIndex].id;
    if (targetChapterId.isEmpty || targetChapterId == currentChapterId) {
      return null;
    }

    return targetChapterId;
  }

  String? _currentChapterLanguageKey() {
    return _normalizeLanguageKey(state.currentChapter?.language);
  }

  String? _normalizeLanguageKey(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return ChapterLanguagePresenter.normalize(value);
  }

  bool? _isAscendingByChapterNumber(List<Chapter> chapters) {
    if (chapters.length < 2) {
      return null;
    }

    for (int i = 0; i < chapters.length - 1; i++) {
      final comparison = _compareChapterOrder(chapters[i], chapters[i + 1]);
      if (comparison == null || comparison == 0) {
        continue;
      }
      return comparison > 0;
    }

    return null;
  }

  int? _compareChapterOrder(Chapter current, Chapter next) {
    final currentOrder = _extractChapterOrder(current);
    final nextOrder = _extractChapterOrder(next);

    if (currentOrder == null || nextOrder == null) {
      return null;
    }

    if (currentOrder.volume != null || nextOrder.volume != null) {
      final volumeCompare = (nextOrder.volume ?? 0).compareTo(
        currentOrder.volume ?? 0,
      );
      if (volumeCompare != 0) {
        return volumeCompare;
      }
    }

    return nextOrder.chapter.compareTo(currentOrder.chapter);
  }

  _ChapterOrder? _extractChapterOrder(Chapter chapter) {
    final title = chapter.title;
    final id = chapter.id;

    final chapterValue =
        _extractChapterValue(title) ?? _extractChapterValue(id);
    if (chapterValue == null) {
      return null;
    }

    final volumeValue = _extractVolumeValue(title) ?? _extractVolumeValue(id);
    return _ChapterOrder(chapter: chapterValue, volume: volumeValue);
  }

  double? _extractChapterValue(String input) {
    final chapterPattern = RegExp(
      r'(?:\bch(?:apter)?\b\s*[:\.-]?)\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    );
    final chapterMatch = chapterPattern.firstMatch(input);
    if (chapterMatch != null) {
      return double.tryParse(chapterMatch.group(1) ?? '');
    }

    final numericMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(input);
    if (numericMatch != null) {
      return double.tryParse(numericMatch.group(1) ?? '');
    }

    return null;
  }

  double? _extractVolumeValue(String input) {
    final volumePattern = RegExp(
      r'(?:\bvol(?:ume)?\b\s*[:\.-]?)\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    );
    final volumeMatch = volumePattern.firstMatch(input);
    if (volumeMatch == null) {
      return null;
    }

    return double.tryParse(volumeMatch.group(1) ?? '');
  }

  Future<void> loadChapter(String chapterId) async {
    try {
      if (_allChapters == null || _allChapters!.isEmpty) {
        _logger.e('⛔ Cannot navigate: No chapter list available');
        emit(_withStatus(ReaderStatus.error)
            .copyWithMessage('chapterNavNotAvailable'));
        return;
      }

      // Clear Flutter image cache before loading new chapter
      // Prevents stale decoded frames from previous chapter (fix image mixup)
      PaintingBinding.instance.imageCache.clear();
      emit(_withStatus(ReaderStatus.loading));

      // Expand pool if chapter not in current _allChapters
      await _ensureChapterInPool(chapterId);

      final chapter = _allChapters!.firstWhere(
        (ch) => ch.id == chapterId,
        orElse: () =>
            Chapter(id: chapterId, title: 'unknownChapter', url: chapterId),
      );

      _logger.i('Loading chapter: ${chapter.title} (${chapter.id})');

      // Check offline availability first
      final isOfflineAvailable =
          await offlineContentManager.isContentAvailableOffline(chapterId);

      List<String> chapterImages = [];
      bool loadedFromOffline = false;

      if (isOfflineAvailable) {
        _logger.i(
            '✅ Chapter $chapterId found offline, loading from local storage');
        chapterImages =
            await offlineContentManager.getOfflineImageUrls(chapterId);

        if (chapterImages.isNotEmpty) {
          loadedFromOffline = true;
          _logger.i(
              '✅ Loaded ${chapterImages.length} images from offline storage');
        } else {
          _logger.w('⚠️ Offline chapter directory exists but no images found');
        }
      }

      // Fallback to online API
      ChapterData? chapterData;
      if (!loadedFromOffline) {
        _logger.i('📡 Fetching chapter from online API');

        // Check connectivity before online request
        final hasConnection = networkCubit.isConnected;

        if (!hasConnection) {
          _logger
              .e('❌ No internet connection and chapter not available offline');
          emit(_withStatus(ReaderStatus.error).copyWithMessage(
              'Cannot load chapter: No internet connection and chapter not downloaded'));
          return;
        }

        try {
          chapterData =
              await getChapterImagesUseCase(GetChapterImagesParams.fromString(
            chapterId,
            sourceId: _parentContent?.sourceId ?? state.content?.sourceId,
          ));

          if (chapterData.images.isEmpty) {
            emit(_withStatus(ReaderStatus.error)
                .copyWithMessage('failedLoadChapterImages'));
            return;
          }

          chapterImages = chapterData.images;
        } catch (e) {
          _logger.e('Failed to load chapter from online API: $e');
          emit(_withStatus(ReaderStatus.error)
              .copyWithMessage('failedLoadChapter'));
          return;
        }
      }

      // Build combined title from parent series + chapter
      final parentTitle =
          _parentContent?.title ?? state.content?.title.split(' - ')[0] ?? '';
      final fullTitle = '$parentTitle - ${chapter.title}';

      final newContent = (_parentContent ?? state.content!).copyWith(
        id: chapterId,
        title: fullTitle,
        imageUrls: chapterImages,
        pageCount: chapterImages.length,
        chapters: _allChapters ?? [],
      );

      _lastTrackedPage = 1;

      emit(_withStatus(ReaderStatus.loaded)
          .copyWithContent(
              content: newContent,
              chapterData: chapterData,
              currentChapter: chapter)
          .copyWithPage(1)
          .copyWithTimer(Duration.zero)
          .copyWithOffline(loadedFromOffline));

      // Save to history
      await _saveToHistory();
    } catch (e) {
      _logger.e('Failed to load chapter: $e');
      emit(
          _withStatus(ReaderStatus.error).copyWithMessage('failedLoadChapter'));
    }
  }

  void jumpToPage(int page) {
    goToPage(page);
  }

  void goToPage(int page) {
    if (!isClosed && state.content != null) {
      final totalPages = state.content!.pageCount;
      final validPage = page.clamp(1, totalPages);

      if (page != validPage) {
        _logger.w(
            'Invalid page requested: $page, clamped to: $validPage (total: $totalPages)');
      }

      _logger.d(
          'Navigating to page: $validPage (requested: $page, total: $totalPages)');

      _lastTrackedPage = validPage;
      emit(state.copyWithPage(validPage));
      _saveReaderPosition();
      _saveToHistory();
    } else {
      _logger.e(
          'Cannot navigate to page $page - cubit closed or content not loaded');
    }
  }

  void updateCurrentPageFromSwipe(int page) {
    if (!isClosed && state.content != null) {
      final totalPages = state.content!.pageCount;

      // Allow +1 for navigation page (if exists)
      final hasNavigationPage = !(state.isOfflineMode ?? false) &&
          state.content!.imageUrls.isNotEmpty;
      final maxPage = hasNavigationPage ? totalPages + 1 : totalPages;

      final validPage = page.clamp(1, maxPage);

      _logger.d(
          'Updating page from swipe: $validPage (total: $totalPages, max with nav: $maxPage)');

      _lastTrackedPage = validPage;

      emit(state.copyWithPage(validPage));
      _saveReaderPosition();
      _saveToHistory();
    }
  }

  int _lastSilentSavedPage = -1;
  DateTime _lastSilentSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _silentSaveThrottle = Duration(seconds: 2);

  void updateCurrentPageSilent(int page) async {
    if (!isClosed && state.content == null) return;

    final totalPages = state.content!.pageCount;
    final validPage = page.clamp(1, totalPages);

    _lastTrackedPage = validPage;

    // Skip if same page or too soon
    final now = DateTime.now();
    if (validPage == _lastSilentSavedPage &&
        now.difference(_lastSilentSaveAt) < _silentSaveThrottle) {
      _logger.d(
          '📍 Skipping silent DB save for $validPage (throttled, last saved $_lastSilentSavedPage)');
      return;
    }
    _lastSilentSavedPage = validPage;
    _lastSilentSaveAt = now;

    _logger.d(
        '📍 Silent page update for continuous scroll: $validPage (total: $totalPages)');

    // Don't emit state — prevents BlocBuilder rebuilds, still save position + history
    try {
      final position = ReaderPosition.create(
        contentId: state.content!.id,
        currentPage: validPage,
        totalPages: totalPages,
        title: state.content!.title,
        coverUrl: state.content!.coverUrl,
        readingTimeMinutes: (state.readingTimer?.inMinutes ?? 0),
      );

      await saveReaderPositionUseCase(position);

      if (state.isOfflineMode == true) return;

      int? chapterIndex;
      if (state.currentChapter != null && state.content?.chapters != null) {
        chapterIndex = state.content!.chapters!
            .indexWhere((c) => c.id == state.currentChapter!.id);
      }

      String? chapterId = state.currentChapter?.id;
      String? chapterTitle = state.currentChapter?.title;

      if (chapterId == null || chapterId.isEmpty) {
        final contentId = state.content!.id;
        if (_isCrotpediaChapterId(
          contentId,
          sourceId: state.content?.sourceId ?? _parentContent?.sourceId,
        )) {
          chapterId = contentId;
          final title = state.content!.title;
          if (title.contains(' - ')) {
            chapterTitle = title.split(' - ').last;
          } else {
            chapterTitle = title;
          }
        }
      }

      if ((chapterId == null || chapterId.isEmpty) &&
          chapterTitle != null &&
          chapterTitle.isNotEmpty &&
          chapterTitle.contains('-chapter-')) {
        chapterId = chapterTitle;
      }

      final bool isChapterMode = chapterId != null && chapterId.isNotEmpty;
      final String historyContentId;
      final String? historyParentId;

      if (isChapterMode) {
        historyContentId = chapterId;
        historyParentId = _parentContent?.id;
      } else {
        historyContentId = state.content!.id;
        historyParentId = null;
      }

      final params = AddToHistoryParams.fromString(
        historyContentId,
        validPage,
        totalPages,
        timeSpent: state.readingTimer ?? Duration.zero,
        title: state.content!.title,
        coverUrl: state.content!.coverUrl,
        sourceId: state.content!.sourceId,
        parentId: historyParentId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        content: state.content,
      );
      await addToHistoryUseCase(params);
      _maybeRequestRecommendationRefresh(historyContentId, validPage,
          totalPages, state.content!.sourceId);
      ContentReadCache.invalidateCache(
        historyContentId,
        sourceId: state.content!.sourceId,
      );
      if (historyParentId != null && historyParentId.isNotEmpty) {
        ContentReadCache.invalidateCache(
          historyParentId,
          sourceId: state.content!.sourceId,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to save silent page update to history',
          error: e, stackTrace: stackTrace);
      // Don't emit error state
    }
  }

  void toggleUI() {
    if (!isClosed) {
      final newShowUI = !(state.showUI ?? true);
      emit(state.copyWithUI(showUI: newShowUI));

      readerSettingsEntityRepository
          .saveShowUI(newShowUI)
          .catchError((e, stackTrace) {
        _logger.e('Failed to save show UI setting: $e',
            error: e, stackTrace: stackTrace);
        // Settings will still apply for current session
      });

      // Start auto-hide timer
      if (newShowUI) {
        _startAutoHideTimer();
      } else {
        _stopAutoHideTimer();
      }
    }
  }

  void showUI() {
    if (!isClosed) {
      emit(state.copyWithUI(showUI: true));
    }
    _startAutoHideTimer();
  }

  void hideUI() {
    if (!isClosed) {
      emit(state.copyWithUI(showUI: false));
    }
    _stopAutoHideTimer();
  }

  // Auto-switch to continuous scroll on tall-image detection
  void onImageLoaded(int pageNumber, Size imageSize) {
    // Only check first few images to avoid performance overhead
    if (pageNumber > 3 || _hasDetectedWebtoon) return;

    final isWebtoon = WebtoonDetector.isWebtoon(imageSize);
    final aspectRatio = WebtoonDetector.getAspectRatio(imageSize);

    if (isWebtoon) {
      _hasDetectedWebtoon = true;
      final currentMode = state.readingMode ?? ReadingMode.singlePage;

      if (currentMode != ReadingMode.continuousScroll) {
        _logger.i('🎨 Webtoon/Manhwa detected on page $pageNumber! '
            'AR=${aspectRatio?.toStringAsFixed(2)} (${imageSize.width.toInt()}x${imageSize.height.toInt()}px) '
            '→ Auto-switching from ${currentMode.name} to continuousScroll');

        if (!isClosed) {
          emit(state.copyWithMode(readingMode: ReadingMode.continuousScroll));
        }

        // Don't persist — session-only auto-switch preserves user preference
      }
    } else {
      // _logger.d('📖 Normal image detected on page $pageNumber: '
      //     'AR=${aspectRatio?.toStringAsFixed(2)} (${imageSize.width.toInt()}x${imageSize.height.toInt()}px)');
    }
  }

  Future<void> changeReadingMode(
    ReadingMode mode, {
    bool persistPreference = true,
    bool resetWebtoonDetection = true,
  }) async {
    if (!isClosed) {
      emit(state.copyWithMode(readingMode: mode));
    }

    if (resetWebtoonDetection) {
      _hasDetectedWebtoon = false;
    }

    if (!persistPreference) {
      return;
    }

    try {
      await readerSettingsEntityRepository.saveReadingMode(mode);
      _logger.i('Successfully saved reading mode: ${mode.name}');
    } catch (e, stackTrace) {
      _logger.e('Failed to save reading mode: $e',
          error: e, stackTrace: stackTrace);
      // Settings will still apply for current session
    }
  }

  Future<void> toggleEnableZoom() async {
    final newEnableZoom = !(state.enableZoom ?? true);
    if (!isClosed) {
      emit(state.copyWithUI(enableZoom: newEnableZoom));
    }
    try {
      final current = await getReaderSettingsUseCase();
      await saveReaderSettingsUseCase(
          current.copyWith(enableZoom: newEnableZoom));
      _logger.i('Successfully saved enable zoom: $newEnableZoom');
    } catch (e, stackTrace) {
      _logger.e('Failed to save enable zoom: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> setTapDirection(TapDirection direction) async {
    if (!isClosed) {
      emit(state.copyWithMode(tapDirection: direction));
    }
    try {
      await readerSettingsEntityRepository.saveTapDirection(direction);
      _logger.i('Successfully saved tap direction: ${direction.name}');
    } catch (e, stackTrace) {
      _logger.e('Failed to save tap direction: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> toggleKeepScreenOn() async {
    final newKeepScreenOn = !(state.keepScreenOn ?? false);

    try {
      if (newKeepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }

      if (!isClosed) {
        emit(state.copyWithUI(keepScreenOn: newKeepScreenOn));
      }

      try {
        await readerSettingsEntityRepository.saveKeepScreenOn(newKeepScreenOn);
        _logger.i('Successfully saved keep screen on: $newKeepScreenOn');
      } catch (e, stackTrace) {
        _logger.e('Failed to save keep screen on setting: $e',
            error: e, stackTrace: stackTrace);
        // Settings will still apply for current session
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to toggle wakelock: $e',
          error: e, stackTrace: stackTrace);
      // Don't update state if wakelock operation failed
    }
  }

  Future<void> clearReaderPosition(String contentId) async {
    try {
      await readerRepository.deleteReaderPosition(contentId);
      _logger.i('🗑️ Cleared reader position for content: $contentId');
    } catch (e) {
      _logger.e('Failed to clear reader position: $e');
    }
  }

  Future<void> clearAllReaderPositions() async {
    try {
      await clearAllReaderPositionsUseCase();
      _logger.i('🗑️ Cleared all reader positions');
    } catch (e) {
      _logger.e('Failed to clear all reader positions: $e');
    }
  }

  Future<void> clearImageCache(String contentId) async {
    try {
      await LocalImagePreloader.clearContentCache(contentId);
      _logger.i('🖼️ Cleared image cache for content: $contentId');

      // Note: CachedNetworkImage cache clearing requires DefaultCacheManager
      // Users can manually clear app data if needed
      _logger
          .i('ℹ️ To clear network image cache, clear app data or restart app');
    } catch (e) {
      _logger.e('Failed to clear image cache: $e');
    }
  }

  Future<ReaderImageRepairResult> repairBrokenImage(int pageNumber) async {
    final currentContent = state.content;
    if (currentContent == null) {
      return (success: false, reason: 'content_unavailable', statusCode: null);
    }

    final sourceId = currentContent.sourceId.trim();
    if (sourceId.isEmpty) {
      return (success: false, reason: 'provider_unavailable', statusCode: null);
    }

    if (!networkCubit.isConnected) {
      return (success: false, reason: 'no_connection', statusCode: null);
    }

    final source = contentSourceRegistry.getSource(sourceId);
    if (source == null) {
      return (success: false, reason: 'provider_unavailable', statusCode: null);
    }

    if (pageNumber <= 0 || pageNumber > currentContent.imageUrls.length) {
      return (success: false, reason: 'page_unavailable', statusCode: null);
    }

    final currentImagePath = await _resolveCurrentImagePathForRepair(
      content: currentContent,
      pageNumber: pageNumber,
    );
    if (currentImagePath == null) {
      return (success: false, reason: 'page_unavailable', statusCode: null);
    }

    return _repairBrokenImageInternal(
      currentContent: currentContent,
      sourceId: sourceId,
      pageNumber: pageNumber,
      currentImagePath: currentImagePath,
    );
  }

  Future<ReaderImageRepairResult> _repairBrokenImageInternal({
    required Content currentContent,
    required String sourceId,
    required int pageNumber,
    required String currentImagePath,
    _ReaderRepairTarget? overrideTarget,
  }) async {
    try {
      final repairTarget = overrideTarget ??
          await _resolveRepairTarget(
            content: currentContent,
            sourceId: sourceId,
            pageNumber: pageNumber,
          );
      if (repairTarget == null) {
        return (
          success: false,
          reason: 'remote_unavailable',
          statusCode: null,
        );
      }

      final headers = _buildRepairHeaders(
        sourceId: sourceId,
        imageUrl: repairTarget.requestUrl,
        readerPageUrl: repairTarget.readerPageUrl,
      );

      final response = await httpClient.get<List<int>>(
        repairTarget.requestUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );

      final statusCode = response.statusCode;
      if (statusCode != 200) {
        _logger.w(
          'Reader repair rejected for page $pageNumber: '
          'status=$statusCode url=${repairTarget.requestUrl}',
        );
        return (
          success: false,
          reason: 'http_status',
          statusCode: statusCode,
        );
      }

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return (
          success: false,
          reason: 'invalid_image',
          statusCode: statusCode,
        );
      }

      final extension = inferImageExtension(
        bytes: bytes,
        contentType: response.headers.value(Headers.contentTypeHeader),
        sourceUrl: repairTarget.requestUrl,
      );
      if (extension == null || extension.isEmpty) {
        _logger.w(
          'Reader repair rejected non-image payload for page $pageNumber '
          'from ${repairTarget.requestUrl}',
        );
        return (
          success: false,
          reason: 'invalid_image',
          statusCode: statusCode,
        );
      }

      final repairedImagePath = buildReplacementImagePath(
        currentImagePath: currentImagePath,
        extension: extension,
      );

      await _persistRepairedImage(
        currentImagePath: currentImagePath,
        repairedImagePath: repairedImagePath,
        bytes: bytes,
      );

      final updatedImageUrls = List<String>.from(currentContent.imageUrls);
      updatedImageUrls[pageNumber - 1] = repairedImagePath;

      final updatedContent = currentContent.copyWith(
        coverUrl:
            pageNumber == 1 && isLocalReaderImagePath(currentContent.coverUrl)
                ? repairedImagePath
                : currentContent.coverUrl,
        imageUrls: updatedImageUrls,
      );

      // Remove failed_pages from metadata so placeholder isn't re-injected
      await offlineContentManager.removeFailedPageFromMetadata(
        currentContent.id,
        pageNumber,
      );

      emit(_withStatus(ReaderStatus.loaded)
          .copyWithContent(content: updatedContent));

      _logger.i(
        'Reader repair succeeded for ${currentContent.id} '
        'page=$pageNumber -> $repairedImagePath',
      );
      return (success: true, reason: 'success', statusCode: statusCode);
    } catch (e, stackTrace) {
      _logger.e(
        'Reader repair failed for ${currentContent.id} page $pageNumber',
        error: e,
        stackTrace: stackTrace,
      );
      return (success: false, reason: 'failed', statusCode: null);
    }
  }

  Future<ReaderManualRepairContext?> prepareManualRepairContext(
    int pageNumber,
  ) async {
    final currentContent = state.content;
    if (currentContent == null) {
      return null;
    }

    final sourceId = currentContent.sourceId.trim();
    if (sourceId.isEmpty ||
        !supportsSourcePageManualRepair(
          remoteConfigService.getRawConfig(sourceId),
        )) {
      return null;
    }

    if (pageNumber <= 0 || pageNumber > currentContent.imageUrls.length) {
      return null;
    }

    try {
      final repairTarget = await _resolveRepairTarget(
        content: currentContent,
        sourceId: sourceId,
        pageNumber: pageNumber,
      );
      if (repairTarget == null) {
        return null;
      }

      final sourcePageUrl = repairTarget.readerPageUrl;
      if (sourcePageUrl == null || sourcePageUrl.trim().isEmpty) {
        return null;
      }

      return (
        sourceId: sourceId,
        sourcePageUrl: sourcePageUrl,
        initialCookie: await _buildCookieHeaderForUrl(sourceId, sourcePageUrl),
      );
    } catch (e) {
      _logger.w(
        'Failed to prepare manual repair context for '
        '${currentContent.id} page $pageNumber: $e',
      );
      return null;
    }
  }

  Future<ReaderImageRepairResult> retryRepairAfterManualSession({
    required int pageNumber,
    required String sourcePageUrl,
    String? sessionUrl,
    String? resolvedImageUrl,
    List<String> rawCookies = const <String>[],
    String? userAgent,
  }) async {
    final effectiveSessionUrl = sessionUrl?.trim().isNotEmpty == true
        ? sessionUrl!.trim()
        : sourcePageUrl;

    try {
      final currentSourceId = state.content?.sourceId.trim();
      if (rawCookies.isNotEmpty &&
          currentSourceId != null &&
          currentSourceId.isNotEmpty) {
        await _saveRawSourceCookies(
          currentSourceId,
          rawCookies,
          effectiveSessionUrl,
        );
      }

      final normalizedUserAgent = userAgent?.trim();
      if (normalizedUserAgent != null && normalizedUserAgent.isNotEmpty) {
        httpClient.options.headers['User-Agent'] = normalizedUserAgent;
      }
    } catch (e) {
      _logger.w(
        'Failed to refresh manual repair session for page $pageNumber: $e',
      );
    }

    final directImageUrl = resolvedImageUrl?.trim();
    if (directImageUrl != null && directImageUrl.isNotEmpty) {
      final currentContent = state.content;
      if (currentContent == null) {
        return (
          success: false,
          reason: 'content_unavailable',
          statusCode: null,
        );
      }

      final sourceId = currentContent.sourceId.trim();
      if (sourceId.isEmpty) {
        return (
          success: false,
          reason: 'provider_unavailable',
          statusCode: null,
        );
      }

      if (!networkCubit.isConnected) {
        return (success: false, reason: 'no_connection', statusCode: null);
      }

      if (contentSourceRegistry.getSource(sourceId) == null) {
        return (
          success: false,
          reason: 'provider_unavailable',
          statusCode: null,
        );
      }

      if (pageNumber <= 0 || pageNumber > currentContent.imageUrls.length) {
        return (
          success: false,
          reason: 'page_unavailable',
          statusCode: null,
        );
      }

      final currentImagePath = await _resolveCurrentImagePathForRepair(
        content: currentContent,
        pageNumber: pageNumber,
      );
      if (currentImagePath == null) {
        return (success: false, reason: 'page_unavailable', statusCode: null);
      }

      return _repairBrokenImageInternal(
        currentContent: currentContent,
        sourceId: sourceId,
        pageNumber: pageNumber,
        currentImagePath: currentImagePath,
        overrideTarget: _ReaderRepairTarget(
          requestUrl: directImageUrl,
          readerPageUrl: _resolveManualRepairReferer(
            sourcePageUrl: sourcePageUrl,
            sessionUrl: effectiveSessionUrl,
          ),
        ),
      );
    }

    return repairBrokenImage(pageNumber);
  }

  Future<_ReaderRepairTarget?> _resolveRepairTarget({
    required Content content,
    required String sourceId,
    required int pageNumber,
  }) async {
    final metadata = _metadataForPage(pageNumber);
    if (metadata != null) {
      final resolved = await _normalizeRepairTarget(
        sourceId: sourceId,
        candidateUrl: metadata.imageUrl,
      );
      if (resolved != null) {
        return resolved;
      }
    }

    final currentPageUrl = _extractRepairCandidateUrl(
      content.imageUrls[pageNumber - 1],
    );
    if (currentPageUrl != null && !isLocalReaderImagePath(currentPageUrl)) {
      final resolved = await _normalizeRepairTarget(
        sourceId: sourceId,
        candidateUrl: currentPageUrl,
      );
      if (resolved != null) {
        return resolved;
      }
    }

    final fetchTargetId = state.currentChapter?.id ?? content.id;
    final chapterTarget = await _resolveRepairTargetFromChapterImages(
      chapterId: fetchTargetId,
      sourceId: sourceId,
      pageNumber: pageNumber,
    );
    if (chapterTarget != null) {
      return chapterTarget;
    }

    try {
      final detail = await getContentDetailUseCase(
        GetContentDetailParams.fromString(content.id, sourceId: sourceId),
      );
      if (pageNumber <= detail.imageUrls.length) {
        return await _normalizeRepairTarget(
          sourceId: sourceId,
          candidateUrl: detail.imageUrls[pageNumber - 1],
        );
      }
    } catch (e) {
      _logger.w(
        'Reader repair detail fallback failed for ${content.id} '
        'page $pageNumber: $e',
      );
    }

    return null;
  }

  String? _extractRepairCandidateUrl(String rawUrl) {
    if (!OfflineContentManager.isFailedPagePlaceholder(rawUrl)) {
      return rawUrl;
    }

    final originalUrl =
        OfflineContentManager.extractOriginalUrlFromPlaceholder(rawUrl);
    if (originalUrl == null || originalUrl.trim().isEmpty) {
      return null;
    }

    return originalUrl.trim();
  }

  Future<String?> _resolveCurrentImagePathForRepair({
    required Content content,
    required int pageNumber,
  }) async {
    final rawUrl = content.imageUrls[pageNumber - 1];
    if (!OfflineContentManager.isFailedPagePlaceholder(rawUrl)) {
      final currentImagePath = normalizeLocalReaderImagePath(rawUrl);
      if (!isLocalReaderImagePath(currentImagePath)) {
        return null;
      }
      return currentImagePath;
    }

    for (final candidateUrl in content.imageUrls) {
      final normalizedCandidate = normalizeLocalReaderImagePath(candidateUrl);
      if (isLocalReaderImagePath(normalizedCandidate)) {
        final siblingDirectory = path.dirname(normalizedCandidate);
        return path.join(
          siblingDirectory,
          'page_${pageNumber.toString().padLeft(3, '0')}.jpg',
        );
      }
    }

    final contentPath = await offlineContentManager.getOfflineContentPath(
      content.id,
    );
    if (contentPath == null || contentPath.trim().isEmpty) {
      return null;
    }

    final imagesDir = path.join(contentPath, 'images');
    final targetDirectory =
        await Directory(imagesDir).exists() ? imagesDir : contentPath;

    return path.join(
      targetDirectory,
      'page_${pageNumber.toString().padLeft(3, '0')}.jpg',
    );
  }

  Future<_ReaderRepairTarget?> _resolveRepairTargetFromChapterImages({
    required String chapterId,
    required String sourceId,
    required int pageNumber,
  }) async {
    try {
      if (sourceId.toLowerCase() == 'ehentai') {
        return await _resolveEhentaiRepairTarget(
          chapterId: chapterId,
          sourceId: sourceId,
          pageNumber: pageNumber,
        );
      }

      final chapterData = await getChapterImagesUseCase(
        GetChapterImagesParams.fromString(
          chapterId,
          sourceId: sourceId,
        ),
      );
      if (pageNumber <= 0 || pageNumber > chapterData.images.length) {
        return null;
      }

      return await _normalizeRepairTarget(
        sourceId: sourceId,
        candidateUrl: chapterData.images[pageNumber - 1],
      );
    } catch (e) {
      _logger.w(
        'Reader repair chapter-image lookup failed for $chapterId '
        'page $pageNumber: $e',
      );
      return null;
    }
  }

  Future<_ReaderRepairTarget?> _resolveEhentaiRepairTarget({
    required String chapterId,
    required String sourceId,
    required int pageNumber,
  }) async {
    String? nextChapterId = chapterId;
    final seenUrls = <String>{};
    var mergedIndex = 0;
    var chunkCount = 0;

    while (nextChapterId != null &&
        nextChapterId.isNotEmpty &&
        chunkCount < _maxEhentaiRepairChunks) {
      final chunkData = await getChapterImagesUseCase(
        GetChapterImagesParams.fromString(
          nextChapterId,
          sourceId: sourceId,
        ),
      );
      chunkCount++;

      for (final candidateUrl in chunkData.images) {
        if (!seenUrls.add(candidateUrl)) {
          continue;
        }

        mergedIndex++;
        if (mergedIndex == pageNumber) {
          return _normalizeRepairTarget(
            sourceId: sourceId,
            candidateUrl: candidateUrl,
          );
        }
      }

      final candidateNextId = chunkData.nextChapterId;
      if (candidateNextId == null ||
          candidateNextId.isEmpty ||
          candidateNextId == nextChapterId ||
          !_isEhentaiVirtualChapterId(candidateNextId)) {
        break;
      }
      nextChapterId = candidateNextId;
    }

    if (chunkCount >= _maxEhentaiRepairChunks) {
      _logger.w(
        'Reader repair EHentai chunk lookup hit safety limit '
        'for $chapterId page $pageNumber',
      );
    }

    return null;
  }

  Future<_ReaderRepairTarget?> _normalizeRepairTarget({
    required String sourceId,
    required String candidateUrl,
  }) async {
    final trimmed = candidateUrl.trim();
    if (trimmed.isEmpty || isLocalReaderImagePath(trimmed)) {
      return null;
    }

    final rawConfig = remoteConfigService.getRawConfig(sourceId);
    if (!supportsSourcePageManualRepair(rawConfig)) {
      return _ReaderRepairTarget(requestUrl: trimmed);
    }

    if (!_shouldResolveSourceReaderPage(
      sourceId: sourceId,
      url: trimmed,
      rawConfig: rawConfig,
    )) {
      return _ReaderRepairTarget(requestUrl: trimmed);
    }

    final resolvedImageUrl = await _resolveSourceReaderImageUrl(
      sourceId: sourceId,
      readerPageUrl: trimmed,
      rawConfig: rawConfig,
    );
    if (resolvedImageUrl == null || resolvedImageUrl.isEmpty) {
      return null;
    }

    return _ReaderRepairTarget(
      requestUrl: resolvedImageUrl,
      readerPageUrl: trimmed,
    );
  }

  Map<String, String> _buildRepairHeaders({
    required String sourceId,
    required String imageUrl,
    String? readerPageUrl,
  }) {
    final headers = <String, String>{};
    final source = contentSourceRegistry.getSource(sourceId);
    if (source != null) {
      headers.addAll(source.getImageDownloadHeaders(imageUrl: imageUrl));
    }
    if (readerPageUrl != null && readerPageUrl.isNotEmpty) {
      headers['Referer'] = readerPageUrl;
    }
    return headers;
  }

  bool _shouldResolveSourceReaderPage({
    required String sourceId,
    required String url,
    Map<String, dynamic>? rawConfig,
  }) {
    if (!supportsSourcePageManualRepair(rawConfig)) {
      return false;
    }

    final lowered = url.toLowerCase();
    if (lowered.startsWith('/')) {
      return !looksLikeDirectImagePath(lowered);
    }

    if (lowered.startsWith('/s/') || lowered.startsWith('/fullimg/')) {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (!_isSourceRepairHost(
      sourceId: sourceId,
      host: host,
      rawConfig: rawConfig,
    )) {
      return false;
    }

    final loweredPath = uri.path.toLowerCase();
    if (loweredPath.contains('/s/') || loweredPath.contains('/fullimg/')) {
      return true;
    }

    return !looksLikeDirectImagePath(loweredPath);
  }

  Future<String?> _resolveSourceReaderImageUrl({
    required String sourceId,
    required String readerPageUrl,
    Map<String, dynamic>? rawConfig,
  }) async {
    try {
      final headers = _buildRepairHeaders(
        sourceId: sourceId,
        imageUrl: readerPageUrl,
        readerPageUrl: readerPageUrl,
      );

      final response = await httpClient.get<dynamic>(
        readerPageUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: true,
          validateStatus: (status) => (status ?? 0) < 400,
        ),
      );

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) {
        return null;
      }

      return extractSourceImageUrlFromHtml(
        html,
        readerPageUrl,
        rawConfig: rawConfig ?? remoteConfigService.getRawConfig(sourceId),
      );
    } catch (e) {
      _logger.w(
        'Reader repair source-page resolve failed for '
        '$sourceId $readerPageUrl: $e',
      );
      return null;
    }
  }

  Future<void> _persistRepairedImage({
    required String currentImagePath,
    required String repairedImagePath,
    required List<int> bytes,
  }) async {
    final repairedFile = File(repairedImagePath);
    final repairDirectory = repairedFile.parent;
    if (!await repairDirectory.exists()) {
      await repairDirectory.create(recursive: true);
    }

    final tempFile = File('$repairedImagePath.repairing');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await tempFile.writeAsBytes(bytes, flush: true);
    await _deleteRepairConflicts(
      currentImagePath: currentImagePath,
      repairedImagePath: repairedImagePath,
    );

    if (await repairedFile.exists()) {
      await repairedFile.delete();
    }

    await tempFile.rename(repairedImagePath);
  }

  Future<String?> _buildCookieHeaderForUrl(String sourceId, String url) async {
    if (sourceId.toLowerCase() != 'ehentai') {
      return null;
    }

    try {
      final cookies = await ehentaiCookieJar.loadForRequest(Uri.parse(url));
      if (cookies.isEmpty) {
        return null;
      }

      return cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (e) {
      _logger.w('Failed to build cookie header for $url: $e');
      return null;
    }
  }

  Future<void> _saveRawSourceCookies(
    String sourceId,
    List<String> rawCookies,
    String url,
  ) async {
    if (sourceId.toLowerCase() != 'ehentai') {
      return;
    }

    if (rawCookies.isEmpty) {
      return;
    }

    final uri = Uri.parse(url);
    final cookiesToSave = <Cookie>[];

    for (final rawCookie in rawCookies) {
      final separatorIndex = rawCookie.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      final name = rawCookie.substring(0, separatorIndex).trim();
      final value = rawCookie.substring(separatorIndex + 1).trim();
      if (name.isEmpty) {
        continue;
      }

      cookiesToSave.add(
        Cookie(name, value)
          ..domain = uri.host
          ..path = '/',
      );
    }

    if (cookiesToSave.isEmpty) {
      return;
    }

    await ehentaiCookieJar.saveFromResponse(uri, cookiesToSave);
    _logger.d(
      'Saved ${cookiesToSave.length} manual repair cookies for ${uri.host}',
    );
  }

  String _resolveManualRepairReferer({
    required String sourcePageUrl,
    required String sessionUrl,
  }) {
    final normalizedSessionUrl = sessionUrl.trim();
    if (normalizedSessionUrl.isEmpty) {
      return sourcePageUrl;
    }

    final currentSourceId = state.content?.sourceId.trim();
    if ((currentSourceId != null &&
            currentSourceId.isNotEmpty &&
            _shouldResolveSourceReaderPage(
              sourceId: currentSourceId,
              url: normalizedSessionUrl,
              rawConfig: remoteConfigService.getRawConfig(currentSourceId),
            )) ||
        !looksLikeDirectImagePath(normalizedSessionUrl)) {
      return normalizedSessionUrl;
    }

    return sourcePageUrl;
  }

  bool _isSourceRepairHost({
    required String sourceId,
    required String host,
    Map<String, dynamic>? rawConfig,
  }) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) {
      return false;
    }

    final config = rawConfig ?? remoteConfigService.getRawConfig(sourceId);
    final networkConfig = _asDynamicMap(config?['network']);
    final uiConfig = _asDynamicMap(config?['ui']);
    final allowedHosts = <String>{
      ..._extractRepairHostsFromValue(config?['baseUrl']),
      ..._extractRepairHostsFromValue(networkConfig['exBaseUrl']),
      ..._extractRepairHostsFromValue(uiConfig['openInBrowserUrl']),
    };

    if (allowedHosts.isEmpty) {
      return true;
    }

    for (final allowedHost in allowedHosts) {
      if (normalizedHost == allowedHost ||
          normalizedHost.endsWith('.$allowedHost')) {
        return true;
      }
    }

    return false;
  }

  Set<String> _extractRepairHostsFromValue(dynamic value) {
    if (value == null) {
      return const <String>{};
    }

    final candidates = <String>{};
    if (value is String && value.trim().isNotEmpty) {
      candidates.add(value.trim());
    } else if (value is Iterable) {
      for (final entry in value) {
        final stringValue = entry?.toString().trim();
        if (stringValue != null && stringValue.isNotEmpty) {
          candidates.add(stringValue);
        }
      }
    }

    final hosts = <String>{};
    for (final candidate in candidates) {
      final normalizedCandidate =
          candidate.contains('://') ? candidate : 'https://$candidate';
      final uri = Uri.tryParse(normalizedCandidate);
      if (uri != null && uri.host.isNotEmpty) {
        hosts.add(uri.host.toLowerCase());
      }
    }
    return hosts;
  }

  Map<String, dynamic> _asDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), entry),
      );
    }
    return <String, dynamic>{};
  }

  Future<void> _deleteRepairConflicts({
    required String currentImagePath,
    required String repairedImagePath,
  }) async {
    final directory = Directory(path.dirname(currentImagePath));
    if (!await directory.exists()) {
      return;
    }

    final targetBasename = path.basenameWithoutExtension(currentImagePath);
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }

      if (entity.path == '$repairedImagePath.repairing') {
        continue;
      }

      final extension = path.extension(entity.path).toLowerCase();
      if (!kReaderRepairSupportedImageExtensions.contains(extension)) {
        continue;
      }

      if (path.basenameWithoutExtension(entity.path) != targetBasename) {
        continue;
      }

      try {
        await entity.delete();
      } catch (e) {
        _logger.w('Failed to delete stale repaired image ${entity.path}: $e');
      }
    }
  }

  ImageMetadata? _metadataForPage(int pageNumber) {
    final metadataList = state.imageMetadata;
    if (metadataList == null) {
      return null;
    }

    for (final metadata in metadataList) {
      if (metadata.pageNumber == pageNumber) {
        return metadata;
      }
    }

    return null;
  }

  void _logImageUrlMapping(Content content) {
    if (content.imageUrls.isEmpty) {
      _logger.w('⚠️ No image URLs found for content: ${content.id}');
      return;
    }

    _logger.i(
        '🖼️ Image URL Mapping for ${content.id} (${content.imageUrls.length} pages):');

    for (int i = 0; i < content.imageUrls.length && i < 10; i++) {
      final pageNumber = i + 1;
      final url = content.imageUrls[i];

      // Extract page number from URL if possible
      final urlPageNumber = _extractPageNumberFromUrl(url);

      final isMatch = urlPageNumber == pageNumber;
      final status = isMatch ? '✅' : '❌';

      _logger.i('  Page $pageNumber: $status URL contains page $urlPageNumber');
      _logger.d('    URL: $url');

      // Additional validation for first few pages
      if (i < 3) {
        _validateImageUrl(url, pageNumber, content.id);
      }
    }

    if (content.imageUrls.length > 10) {
      _logger.i('  ... and ${content.imageUrls.length - 10} more pages');
    }

    // Check for duplicate URLs in first few pages
    _checkForDuplicateUrls(content);
  }

  void _validateImageUrl(String url, int expectedPage, String contentId) {
    try {
      // Check if URL is accessible (basic validation)
      // Allow local file paths (start with /)
      if (url.startsWith('/')) {
        _logger.d(
            '✅ Local file path validation passed for page $expectedPage: $url');
        return;
      }

      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        _logger.w('⚠️ Invalid URL format for page $expectedPage: $url');
        return;
      }

      // Extract gallery ID from URL
      final galleryMatch = RegExp(r'/galleries/(\d+)/').firstMatch(url);
      if (galleryMatch != null) {
        final galleryId = galleryMatch.group(1);
        if (galleryId != contentId) {
          _logger.w(
              '⚠️ URL gallery ID mismatch! Expected $contentId, got $galleryId in URL: $url');
        }
      }

      _logger.d('✅ URL validation passed for page $expectedPage: $url');
    } catch (e) {
      _logger.w('⚠️ URL validation failed for page $expectedPage: $e');
    }
  }

  void _checkForDuplicateUrls(Content content) {
    final urlSet = <String>{};
    final duplicates = <String>[];

    for (final url in content.imageUrls) {
      if (!urlSet.add(url)) {
        duplicates.add(url);
      }
    }

    if (duplicates.isNotEmpty) {
      _logger.e('🚨 DUPLICATE URLs FOUND in content ${content.id}:');
      for (final duplicate in duplicates) {
        final indices = <int>[];
        for (int i = 0; i < content.imageUrls.length; i++) {
          if (content.imageUrls[i] == duplicate) {
            indices.add(i + 1); // Convert to 1-based page numbers
          }
        }
        _logger.e('  URL: $duplicate appears on pages: ${indices.join(", ")}');
      }
    } else {
      _logger.i('✅ No duplicate URLs found in content ${content.id}');
    }
  }

  int? _extractPageNumberFromUrl(String url) {
    // Try to extract page number from patterns like:
    // https://i.nhentai.net/galleries/123456/1.jpg -> 1
    // https://i.nhentai.net/galleries/123456/86.jpg -> 86
    final match = RegExp(r'/galleries/\d+/(\d+)\.[^/]+$').firstMatch(url);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    // Try other patterns if needed
    final match2 = RegExp(r'/(\d+)\.[^/]*$').firstMatch(url);
    if (match2 != null) {
      return int.tryParse(match2.group(1)!);
    }

    return null;
  }

  Future<void> resetReaderSettings() async {
    try {
      await readerSettingsEntityRepository.resetToDefaults();
      _logger.i('Successfully reset reader settings to defaults');

      if (!isClosed) {
        emit(state
            .copyWithUI(showUI: true, keepScreenOn: false)
            .copyWithMode(readingMode: ReadingMode.singlePage));
      }

      // Disable wakelock
      try {
        await WakelockPlus.disable();
      } catch (e, stackTrace) {
        _logger.e('Failed to disable wakelock during reset: $e',
            error: e, stackTrace: stackTrace);
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to reset reader settings: $e',
          error: e, stackTrace: stackTrace);

      // Still apply default settings to current state even if persistence failed
      if (!isClosed) {
        emit(state
            .copyWithUI(showUI: true, keepScreenOn: false)
            .copyWithMode(readingMode: ReadingMode.singlePage));
      }

      // Try to disable wakelock anyway
      try {
        await WakelockPlus.disable();
      } catch (wakelockError) {
        _logger
            .e('Failed to disable wakelock after reset error: $wakelockError');
      }

      // Re-throw to let UI handle the error
      rethrow;
    }
  }

  // Fires the recommendation refresh bus once per content when reading
  // passes 90% completion (spec 7.1). Page-by-page saves below the
  // threshold stay silent so the engine is not recomputed per page turn.
  void _maybeRequestRecommendationRefresh(
    String historyContentId,
    int page,
    int totalPages,
    String sourceId,
  ) {
    if (totalPages <= 0) return;
    if (page / totalPages < 0.9) return;
    final key = '$sourceId|$historyContentId';
    if (_lastRecRefreshKey == key) return;
    _lastRecRefreshKey = key;
    RecommendationRefreshBus.requestGlobalRefresh();
  }

  Future<void> _saveToHistory() async {
    if (state.isOfflineMode == true) return;

    try {
      _logger.d('📝 _saveToHistory called');
      _logger.d(
          '   state.currentChapter: ${state.currentChapter?.title ?? "NULL"}');
      _logger.d(
          '   state.currentChapter.id: ${state.currentChapter?.id ?? "NULL"}');
      _logger.d('   state.content.id: ${state.content!.id}');

      int? chapterIndex;
      if (state.currentChapter != null && state.content?.chapters != null) {
        chapterIndex = state.content!.chapters!
            .indexWhere((c) => c.id == state.currentChapter!.id);
      }

      String? chapterId = state.currentChapter?.id;
      String? chapterTitle = state.currentChapter?.title;

      _logger.d('   Initial chapterId: $chapterId');
      _logger.d('   Initial chapterTitle: $chapterTitle');

      // If currentChapter is null but content.id looks like a chapter ID, use it
      if (chapterId == null || chapterId.isEmpty) {
        final contentId = state.content!.id;
        if (_isCrotpediaChapterId(
          contentId,
          sourceId: state.content?.sourceId ?? _parentContent?.sourceId,
        )) {
          chapterId = contentId;
          final title = state.content!.title;
          if (title.contains(' - ')) {
            chapterTitle = title.split(' - ').last;
          } else {
            chapterTitle = title;
          }
          _logger.d('📝 Using content.id as chapterId: $chapterId');
        }
      }

      // chapterTitle may contain "-chapter-", use as fallback ID
      if ((chapterId == null || chapterId.isEmpty) &&
          chapterTitle != null &&
          chapterTitle.isNotEmpty &&
          chapterTitle.contains('-chapter-')) {
        chapterId = chapterTitle;
        _logger.d('📝 Using chapterTitle as chapterId: $chapterId');
      }

      _logger.d('   Final chapterId: $chapterId');
      _logger.d('   _parentContent.id: ${_parentContent?.id ?? "NULL"}');

      final bool isChapterMode = chapterId != null && chapterId.isNotEmpty;
      final String historyContentId;
      final String? historyParentId;

      if (isChapterMode) {
        historyContentId = chapterId;
        historyParentId = _parentContent?.id;
      } else {
        historyContentId = state.content!.id;
        historyParentId = null;
        _logger.d('📖 NON-CHAPTER MODE: contentId=$historyContentId');
      }

      final safePage = _lastTrackedPage.clamp(1, state.content!.pageCount);

      final params = AddToHistoryParams.fromString(
        historyContentId,
        safePage,
        state.content!.pageCount,
        timeSpent: state.readingTimer ?? Duration.zero,
        title: state.content!.title,
        coverUrl: state.content!.coverUrl,
        sourceId: state.content!.sourceId,
        parentId: historyParentId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        content: state.content,
      );

      _logger.d(
          '📤 Saving history with contentId: ${params.contentId.value}, parentId: ${params.parentId}, chapterId: ${params.chapterId}');
      await addToHistoryUseCase(params);
      _maybeRequestRecommendationRefresh(historyContentId, safePage,
          state.content!.pageCount, state.content!.sourceId);
      ContentReadCache.invalidateCache(
        historyContentId,
        sourceId: state.content!.sourceId,
      );
      if (historyParentId != null && historyParentId.isNotEmpty) {
        ContentReadCache.invalidateCache(
          historyParentId,
          sourceId: state.content!.sourceId,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to save reading progress to history',
          error: e, stackTrace: stackTrace);
      // Log error but don't emit error state for history saving
    }
  }

  Future<void> _saveReaderPosition() async {
    if (state.content == null) return;

    try {
      final position = ReaderPosition.create(
        contentId: state.content!.id,
        currentPage: _lastTrackedPage,
        totalPages: state.content!.pageCount,
        title: state.content!.title,
        coverUrl: state.content!.coverUrl,
        readingTimeMinutes: (state.readingTimer?.inMinutes ?? 0),
      );
      // if (position.currentPage <= position.totalPages) {
      await saveReaderPositionUseCase(position);
      // }
      // _logger.i(
      //     '✅ Saved reader position: ${state.content!.id} at page ${state.currentPage}/${state.content!.pageCount}');
    } catch (e) {
      _logger.e('Failed to save reader position: $e');
      // Don't emit error state for position saving
    }
  }

  Future<int> _restoreReaderPosition(String contentId) async {
    try {
      final position = await getReaderPositionUseCase(contentId);
      if (position != null) {
        _logger.i(
            '📖 Restored reader position: $contentId at page ${position.currentPage}/${position.totalPages}');
        return position.currentPage;
      }
    } catch (e) {
      _logger.e('Failed to restore reader position: $e');
    }

    return 1;
  }

  void _startReadingTimer() {
    _logger.i('start reading timer');
    _readingTimer?.cancel();
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isClosed) {
        final currentTimer = state.readingTimer ?? Duration.zero;
        emit(state.copyWithTimer(currentTimer + const Duration(seconds: 1)));
      } else {
        // Cancel timer if cubit is closed
        timer.cancel();
      }
    });
    _logger.i('end reading timer');
  }

  void _stopReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = null;
  }

  void _startAutoHideTimer() {
    _stopAutoHideTimer();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      // Check if cubit is still active before calling hideUI
      if (!isClosed && (state.showUI ?? false)) {
        hideUI();
      }
    });
  }

  // Extracts the parent content ID from a composite chapter ID.
  ///
  // Komikcast and similar sources store chapter IDs as composite slugs:
  //   - "doctors-rebirth/234"  → parent = "doctors-rebirth"
  //   - "doctor-rebirth/chapter/234" → parent = "doctors-rebirth"
  ///
  // Returns the original [contentId] if it is not a composite ID (i.e. no `/`).
  String _extractParentContentId(String contentId) {
    final trimmed = contentId.trim();
    final slashIndex = trimmed.indexOf('/');
    if (slashIndex <= 0) return trimmed; // not composite, return as-is
    return trimmed.substring(0, slashIndex);
  }

  // Check if contentId is a Crotpedia chapter ID
  // Crotpedia chapter IDs typically contain "chapter" in the slug
  // e.g., "manga-name-chapter-1-bahasa-indonesia"
  bool _isCrotpediaChapterId(
    String contentId, {
    String? sourceId,
  }) {
    return ChapterIdClassifier.isCrotpediaChapterId(
      contentId,
      sourceId: sourceId,
    );
  }

  String? _resolveSourceHint({
    Content? preloadedContent,
    Content? parentContent,
  }) {
    final preloadedSource = preloadedContent?.sourceId.trim();
    if (preloadedSource != null && preloadedSource.isNotEmpty) {
      return preloadedSource;
    }

    final parentSource = parentContent?.sourceId.trim();
    if (parentSource != null && parentSource.isNotEmpty) {
      return parentSource;
    }

    final stateSource = state.content?.sourceId.trim();
    if (stateSource != null && stateSource.isNotEmpty) {
      return stateSource;
    }

    return null;
  }

  void handleLifecyclePause() {
    if (_isBackgrounded) return;
    _isBackgrounded = true;

    _wasKeepScreenOnBeforePause = state.keepScreenOn ?? false;

    _stopReadingTimer();

    // Fire-and-forget: disable wakelock in background
    WakelockPlus.disable().catchError((_) {});
  }

  void handleLifecycleResume() {
    if (!_isBackgrounded) return;
    _isBackgrounded = false;

    if (_wasKeepScreenOnBeforePause) {
      WakelockPlus.enable().catchError((_) {});
    }

    _startReadingTimer();
  }

  void _stopAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  @override
  Future<void> close() async {
    // Reset lifecycle state in case we're closed while backgrounded
    _isBackgrounded = false;
    _wasKeepScreenOnBeforePause = false;

    // Stop timers
    _stopReadingTimer();
    _stopAutoHideTimer();

    // Save final reading progress
    await _saveToHistory();

    // Disable wakelock
    await WakelockPlus.disable();

    return super.close();
  }
}

class _ReaderRepairTarget {
  const _ReaderRepairTarget({
    required this.requestUrl,
    this.readerPageUrl,
  });

  final String requestUrl;
  final String? readerPageUrl;
}

class _ChapterOrder {
  const _ChapterOrder({
    required this.chapter,
    required this.volume,
  });

  final double chapter;
  final double? volume;
}
