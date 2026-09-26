import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/config/remote_config_service.dart';
import '../../../core/utils/source_url_resolver.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/entities/download_task.dart';
import '../../../domain/usecases/downloads/downloads_usecases.dart';
import '../../../domain/usecases/content/content_usecases.dart';
import '../../../domain/usecases/content/get_chapter_images_usecase.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../core/services/native_pdf_reader_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/offline_content_manager.dart';
import '../../../core/services/notification_service.dart';
import '../../cubits/recommendations/recommendation_refresh_bus.dart';
import '../../../core/services/download_manager.dart';
import '../../../core/services/pdf_conversion_service.dart';
import '../../../core/services/pdf_conversion_queue_manager.dart';
import '../../../core/utils/download_storage_utils.dart';
import '../../../core/utils/storage_settings.dart';
import '../../widgets/content_list_widget.dart';

import 'package:nhasixapp/core/services/workers/background_download_utils.dart';
// import 'package:nhasixapp/core/services/workers/download_worker.dart'; // REMOVED
import '../../../core/services/native_download_service.dart';

part 'download_event.dart';
part 'download_state.dart';
part 'download_bloc_helpers.dart';

class DownloadBloc extends Bloc<DownloadEvent, DownloadBlocState> {
  DownloadBloc({
    required DownloadContentUseCase downloadContentUseCase,
    required GetContentDetailUseCase getContentDetailUseCase,
    required GetChapterImagesUseCase getChapterImagesUseCase,
    required UserDataRepository userDataRepository,
    required OfflineContentManager offlineContentManager,
    required Logger logger,
    required Connectivity connectivity,
    required NotificationService notificationService,
    required PdfConversionService pdfConversionService,
    required PdfConversionQueueManager pdfConversionQueueManager,
    required RemoteConfigService remoteConfigService,
    AppLocalizations? appLocalizations,
    DownloadManager? downloadManager, // NEW: Optional for testing
  })  : _downloadContentUseCase = downloadContentUseCase,
        _getContentDetailUseCase = getContentDetailUseCase,
        _getChapterImagesUseCase = getChapterImagesUseCase,
        _userDataRepository = userDataRepository,
        _offlineContentManager = offlineContentManager,
        _logger = logger,
        _connectivity = connectivity,
        _notificationService = notificationService,
        // _pdfConversionService = pdfConversionService,
        _pdfConversionQueueManager = pdfConversionQueueManager,
        _remoteConfigService = remoteConfigService,
        _appLocalizations = appLocalizations,
        _downloadManager = downloadManager ??
            DownloadManager(), // Use injected or default singleton
        super(const DownloadInitial()) {
    on<DownloadInitializeEvent>(_onInitialize);
    on<DownloadQueueEvent>(_onQueue);
    on<DownloadRangeEvent>(_onRange);
    on<DownloadStartEvent>(_onStart);
    on<DownloadPauseEvent>(_onPause);
    on<DownloadCancelEvent>(_onCancel);
    on<DownloadRetryEvent>(_onRetry);
    on<DownloadResumeEvent>(_onResume);
    on<DownloadRemoveEvent>(_onRemove);
    on<DownloadRefreshEvent>(_onRefresh);
    on<DownloadProgressUpdateEvent>(_onProgressUpdate);
    on<DownloadSettingsUpdateEvent>(_onSettingsUpdate);
    on<DownloadBulkActionEvent>(_onBulkAction);
    on<DownloadSelectionActionEvent>(_onSelectionAction);
    on<DownloadConvertToPdfEvent>(_onConvertToPdf);
    on<DownloadOpenContentEvent>(_onOpenContent);
    on<DownloadCleanupStorageEvent>(_onCleanupStorage);
    on<DownloadExportEvent>(_onExport);
    on<DownloadBulkDeleteEvent>(_onBulkDelete);
    on<DownloadCompletedEvent>(_onCompleted);
    on<DownloadNativeFailedEvent>(_onNativeFailed);

    // If permission not granted, service will be initialized later when user grants permission
    _notificationService.initialize();

    _setupNotificationCallbacks();

    _initializeProgressStream();
  }

  final DownloadContentUseCase _downloadContentUseCase;
  final GetContentDetailUseCase _getContentDetailUseCase;
  final GetChapterImagesUseCase _getChapterImagesUseCase;
  final UserDataRepository _userDataRepository;
  final OfflineContentManager _offlineContentManager;
  final Logger _logger;
  final Connectivity _connectivity;
  final NotificationService _notificationService;
  // final PdfConversionService _pdfConversionService;
  final PdfConversionQueueManager _pdfConversionQueueManager;
  final RemoteConfigService _remoteConfigService;
  final AppLocalizations? _appLocalizations;
  final DownloadManager
      _downloadManager; // Use instance variable instead of singleton directly

  // Batch DB save infrastructure
  final Map<String, int> _dbSaveSkipCount = {};
  final Set<String> _pendingDbSave = {};
  Timer? _dbFlushTimer;
  static const int _kDbSaveInterval = 10;
  // Session download completion counter (not total in DB)
  int _sessionCompletedCount = 0;

  // 2.2: foreground-aware maxParallelImages
  // LifecycleWatcher sets this; DownloadBloc reads it before starting downloads
  static bool _isForeground = true;
  static int get defaultMaxParallelImages => _isForeground ? 1 : 3;

  static void updateForeground(bool foreground) {
    _isForeground = foreground;
  }

  void pauseBackgroundWork() {
    _logger.i('DownloadBloc: Pausing background work');
    _flushPendingDbSaves();
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;
  }

  void resumeBackgroundWork() {
    _logger.i('DownloadBloc: Resuming background work');
    _dbFlushTimer?.cancel();
    _dbFlushTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _flushPendingDbSaves(),
    );
  }

  String _generateFallbackUrl(String? sourceId, String contentId) {
    try {
      if (sourceId != null && sourceId.isNotEmpty) {
        final preferChapterPattern = contentId.contains('chapter');
        final normalizedContentId = _normalizeDetailContentId(
          sourceId: sourceId,
          contentId: contentId,
        );
        final targetContentId =
            preferChapterPattern ? contentId : normalizedContentId;
        final configDrivenUrl = SourceUrlResolver.buildContentUrl(
          remoteConfigService: _remoteConfigService,
          sourceId: sourceId,
          contentId: targetContentId,
          preferChapterPattern: preferChapterPattern,
        );
        if (configDrivenUrl.isNotEmpty) {
          return configDrivenUrl;
        }
      }
    } catch (e) {
      _logger.w(
        'DownloadBloc: Failed to build fallback URL for $sourceId/$contentId: $e',
      );
    }

    return '';
  }

  String _normalizeDetailContentId({
    required String sourceId,
    required String contentId,
  }) {
    if (_isEhentaiSource(sourceId)) {
      return contentId;
    }

    final slashIndex = contentId.lastIndexOf('/');
    if (slashIndex <= 0 || slashIndex >= contentId.length - 1) {
      return contentId;
    }

    final parentId = contentId.substring(0, slashIndex);
    final chapterSegment = contentId.substring(slashIndex + 1);
    final looksNumericChapter = int.tryParse(chapterSegment) != null;
    if (!looksNumericChapter || parentId.isEmpty) {
      return contentId;
    }

    final rawConfig = _remoteConfigService.getRawConfig(sourceId);
    final apiEndpoints = ((rawConfig?['api'] as Map?)?['endpoints'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final detailPath = _extractEndpointPath(apiEndpoints['detail']);
    final imagesPath = _extractEndpointPath(apiEndpoints['images']) ??
        _extractEndpointPath(apiEndpoints['pages']) ??
        _extractEndpointPath(apiEndpoints['chapterImages']);

    final detailExpectsSingleId = detailPath?.contains('{id}') ?? false;
    final chapterEndpointPresent = (imagesPath?.contains('{chapter}') ??
            imagesPath?.contains('{chapterId}') ??
            false) ||
        imagesPath?.contains('{chapterIdFull}') == true;

    if (detailExpectsSingleId && chapterEndpointPresent) {
      return parentId;
    }

    return contentId;
  }

  Future<List<String>> _collectEhentaiChapterImages({
    required String initialChapterId,
    required String sourceId,
  }) async {
    const maxChunks = 150;
    final shouldFollowLinkedSegments = !_isEhentaiPartId(initialChapterId);

    final mergedImages = <String>[];
    final seenUrls = <String>{};

    String? nextChapterId = initialChapterId;
    var chunkCount = 0;

    while (nextChapterId != null &&
        nextChapterId.isNotEmpty &&
        chunkCount < maxChunks) {
      final chunkData = await _getChapterImagesUseCase.call(
        GetChapterImagesParams.fromString(
          nextChapterId,
          sourceId: sourceId,
        ),
      );

      chunkCount++;

      for (final imageUrl in chunkData.images) {
        if (seenUrls.add(imageUrl)) {
          mergedImages.add(imageUrl);
        }
      }

      final candidateNextId = chunkData.nextChapterId;
      if (!shouldFollowLinkedSegments ||
          candidateNextId == null ||
          candidateNextId.isEmpty ||
          candidateNextId == nextChapterId ||
          !_isEhentaiVirtualChapterId(candidateNextId)) {
        break;
      }

      nextChapterId = candidateNextId;
    }

    if (chunkCount >= maxChunks) {
      _logger.w(
          'DownloadBloc: EHentai chunk aggregation reached safety limit ($maxChunks) for $initialChapterId');
    }

    _logger.i(
        'DownloadBloc: EHentai chunk aggregation complete for $initialChapterId with ${mergedImages.length} images across $chunkCount chunks');

    return mergedImages;
  }

  String _getLocalizedString(
      String Function(AppLocalizations) getter, String fallback) {
    if (_appLocalizations != null) {
      return getter(_appLocalizations);
    }
    return fallback;
  }

  DownloadSettings _settings = DownloadSettings.defaultSettings();
  final Map<String, DownloadTask> _activeTasks = {};
  StreamSubscription<DownloadProgressUpdate>? _progressSubscription;

  void _initializeProgressStream() {
    _progressSubscription = _downloadManager.progressStream.listen(
      (update) {
        _logger.d('DownloadBloc: Received progress update: $update');

        if (update.downloadedPages == -1) {
          if (update.totalPages == -1) {
            _logger.d(
                'DownloadBloc: Received completion event for ${update.contentId}');
            add(DownloadCompletedEvent(update.contentId));
          } else if (update.totalPages == -2) {
            _logger.w(
                'DownloadBloc: Received native failed event for ${update.contentId}');
            add(DownloadNativeFailedEvent(
              update.contentId,
              error: 'Native download reported failure',
            ));
          } else {
            _logger.w(
                'DownloadBloc: Ignored unknown terminal marker for ${update.contentId}: ${update.totalPages}');
          }
        } else {
          add(DownloadProgressUpdateEvent(
            contentId: update.contentId,
            downloadedPages: update.downloadedPages,
            totalPages: update.totalPages,
            downloadSpeed: update.downloadSpeed,
            estimatedTimeRemaining: update.estimatedTimeRemaining,
          ));
        }
      },
      onError: (error) {
        _logger.e('DownloadBloc: Progress stream error: $error');
      },
    );

    _dbFlushTimer?.cancel();
    _dbFlushTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _flushPendingDbSaves(),
    );

    _logger.i('DownloadBloc: Progress stream subscription initialized');
  }

  Future<void> _flushPendingDbSaves() async {
    if (_pendingDbSave.isEmpty) return;
    final ids = List<String>.from(_pendingDbSave);
    _pendingDbSave.clear();
    for (final id in ids) {
      try {
        final currentState = state;
        if (currentState is DownloadLoaded) {
          final dl = currentState.downloads.firstWhere(
            (d) => d.contentId == id,
            orElse: () => throw Exception('pending save $id not found'),
          );
          await _userDataRepository.saveDownloadStatus(dl);
        }
      } catch (e) {
        _logger.w('DownloadBloc: flush save failed for $id: $e');
      }
    }
  }

  Future<List<DownloadStatus>> _loadAllDownloadsFromDb({
    DownloadState? state,
    String? sourceId,
  }) async {
    const batchSize = 500;
    var offset = 0;
    final allDownloads = <DownloadStatus>[];

    while (true) {
      final page = await _userDataRepository.getAllDownloads(
        state: state,
        sourceId: sourceId,
        limit: batchSize,
        offset: offset,
      );

      if (page.isEmpty) {
        break;
      }

      allDownloads.addAll(page);
      if (page.length < batchSize) {
        break;
      }
      offset += batchSize;
    }

    return allDownloads;
  }

  void _setupNotificationCallbacks() {
    _notificationService.setCallbacks(
      onDownloadPause: (contentId) {
        _logger.i('NotificationAction: Pause requested for $contentId');
        add(DownloadPauseEvent(contentId));
      },
      onDownloadResume: (contentId) {
        _logger.i('NotificationAction: Resume requested for $contentId');
        add(DownloadResumeEvent(contentId));
      },
      onDownloadCancel: (contentId) {
        _logger.i('NotificationAction: Cancel requested for $contentId');
        add(DownloadCancelEvent(contentId));
      },
      onDownloadRetry: (contentId) {
        _logger.i('NotificationAction: Retry requested for $contentId');
        add(DownloadRetryEvent(contentId));
      },
      onPdfRetry: (contentId) {
        _logger.i('NotificationAction: PDF retry requested for $contentId');
        _retryPdfConversion(contentId);
      },
      onOpenDownload: (contentId) {
        _logger.i('NotificationAction: Open download requested for $contentId');
        _openDownloadedContent(contentId);
      },
      onNavigateToDownloads: (contentId) {
        _logger.i(
            'NotificationAction: Navigate to downloads requested for $contentId');
        add(const DownloadRefreshEvent());
      },
    );
    _logger.i('DownloadBloc: Notification callbacks configured');
  }

  Future<void> _onInitialize(
    DownloadInitializeEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    try {
      _logger.i('DownloadBloc: Initializing download manager');
      emit(const DownloadInitializing());

      final downloads = await _loadAllDownloadsFromDb();

      final userPrefs = await _userDataRepository.getUserPreferences();
      final remoteMaxConcurrent =
          _remoteConfigService.appConfig?.limits?.maxConcurrentDownloads ?? 3;

      final customRoot = await StorageSettings.getCustomRootPath();
      _logger.i('DownloadBloc: Custom storage root loaded: $customRoot');
      _logger.d(
          '📁 DOWNLOAD_BLOC: Loading customStorageRoot from StorageSettings');
      _logger.d('📁 DOWNLOAD_BLOC: customRoot value: $customRoot');

      _settings = DownloadSettings(
        maxConcurrentDownloads: userPrefs.maxConcurrentDownloads != 3
            ? userPrefs.maxConcurrentDownloads
            : remoteMaxConcurrent,
        imageQuality: userPrefs.imageQuality,
        autoRetry: userPrefs.autoRetry,
        retryAttempts: userPrefs.retryAttempts,
        retryDelay: userPrefs.retryDelay,
        timeoutDuration: userPrefs.timeoutDuration,
        enableNotifications: userPrefs.enableNotifications,
        wifiOnly: userPrefs.wifiOnly,
        customStorageRoot: customRoot,
      );
      _logger.d(
          '📁 DOWNLOAD_BLOC: DownloadSettings created with customStorageRoot: ${_settings.customStorageRoot}');

      emit(DownloadLoaded(
        downloads: downloads,
        settings: _settings,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('DownloadBloc: Initialized with ${downloads.length} downloads');

      // 1. ZOMBIE STATE FIX: Reset any downloads stuck in "downloading" state
      // This happens if the app was killed while downloading.
      final correctedDownloads = <DownloadStatus>[];
      for (final download in downloads) {
        if (download.state == DownloadState.downloading) {
          _logger.w(
              'DownloadBloc: Found zombie download stuck in downloading state: ${download.contentId}. Resetting to Paused.');
          final fixedDownload = download.copyWith(
            state: DownloadState.paused,
            error: 'Download interrupted (App Restart)',
          );
          await _userDataRepository.saveDownloadStatus(fixedDownload);
          correctedDownloads.add(fixedDownload);
        } else {
          correctedDownloads.add(download);
        }
      }

      emit(DownloadLoaded(
        downloads: correctedDownloads,
        settings: _settings,
        lastUpdated: DateTime.now(),
      ));

      await _processQueue();
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error initializing',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToInitializeDownloadManager(e.toString()),
          'Failed to initialize download manager: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _processQueue() async {
    if (state is! DownloadLoaded) return;
    final currentState = state as DownloadLoaded;

    try {
      final queuedDownloads = currentState.downloads
          .where((d) => d.state == DownloadState.queued)
          .toList();
      final activeDownloads = currentState.downloads
          .where((d) => d.state == DownloadState.downloading)
          .toList();

      if (queuedDownloads.isEmpty) {
        _logger.d('DownloadBloc: No queued downloads to process');
        return;
      }

      final maxConcurrent = currentState.settings.maxConcurrentDownloads;

      if (activeDownloads.length >= maxConcurrent) {
        _logger.d(
            'DownloadBloc: Already at max concurrent downloads: $maxConcurrent');
        return;
      }

      final sortedQueue = List<DownloadStatus>.from(queuedDownloads);

      final availableSlots = maxConcurrent - activeDownloads.length;
      final toStart = sortedQueue.take(availableSlots).toList();

      _logger
          .i('DownloadBloc: Starting ${toStart.length} downloads from queue');

      for (final download in toStart) {
        add(DownloadStartEvent(download.contentId));
      }
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error processing queue',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _onQueue(
    DownloadQueueEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger.w('DownloadBloc: Cannot queue download - not in loaded state');
      return;
    }

    try {
      _logger.i('DownloadBloc: Queuing download for ${event.content.id}');

      // STRICT CHECK: Verify storage root is set before queuing
      if (currentState.settings.customStorageRoot == null ||
          currentState.settings.customStorageRoot!.isEmpty) {
        _logger.e('❌ Download blocked: No custom storage root selected.');
        emit(DownloadError(
          message:
              'Storage location not set. Please select a folder in Settings.',
          errorType: DownloadErrorType.storage,
          previousState: currentState,
        ));
        return;
      }

      // Check if this is chapter-based content (Crotpedia manga)
      // We now ALLOW this, but we need to ensure the UI handles it correctly
      // (e.g. by downloading individual chapters if they are passed as content)
      /*
      if (event.content.imageUrls.isEmpty &&
          event.content.chapters != null &&
          event.content.chapters!.isNotEmpty) {
        _logger.w(
            'DownloadBloc: Cannot download chapter-based content ${event.content.id}');
        
        return;
      }
      */

      // Exception: For chapter-based content (Crotpedia), images may be fetched lazily during download
      // We check for slug-based IDs which indicate chapter content that will have images fetched during _onStart
      final isSlugBasedContent = !RegExp(r'^\d+$').hasMatch(event.content.id);

      if (event.content.imageUrls.isEmpty &&
          event.content.pageCount == 0 &&
          !isSlugBasedContent) {
        _logger.w(
            'DownloadBloc: Content ${event.content.id} has no downloadable images');

        emit(DownloadError(
          message: 'noDownloadableImages',
          errorType: DownloadErrorType.unknown,
          previousState: currentState,
        ));
        return;
      }

      if (isSlugBasedContent && event.content.imageUrls.isEmpty) {
        _logger.i(
            'DownloadBloc: Slug-based content ${event.content.id} - images will be fetched during download');
      }
      final existingDownload = currentState.downloads
          .where((d) => d.contentId == event.content.id)
          .firstOrNull;

      if (existingDownload != null) {
        _logger.w(
            'DownloadBloc: Content ${event.content.id} already in download list');

        if (existingDownload.canRetry) {
          _logger.i(
              'DownloadBloc: Retrying existing download for ${event.content.id}');
          add(DownloadRetryEvent(event.content.id));
        }

        return;
      }

      final downloadStatus = DownloadStatus.initial(
        event.content.id,
        event.content.pageCount,
        startPage: event.startPage,
        endPage: event.endPage,
        title: event.content.title,
        coverUrl: event.content.coverUrl,
        sourceId: event.content.sourceId,
      );

      await _userDataRepository.saveDownloadStatus(downloadStatus);

      final updatedDownloads = [...currentState.downloads, downloadStatus];
      emit(currentState.copyWith(
        downloads: updatedDownloads,
        lastUpdated: DateTime.now(),
      ));

      _updateDownloadGroupNotification();

      _logger.i('DownloadBloc: Queued download for ${event.content.id}');

      await _processQueue();
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error queuing download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToQueueDownload(e.toString()),
          'Failed to queue download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onRange(
    DownloadRangeEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger
          .w('DownloadBloc: Cannot queue range download - not in loaded state');
      return;
    }

    try {
      _logger.i(
          'DownloadBloc: Queuing range download for ${event.content.id} (pages ${event.startPage}-${event.endPage})');

      // STRICT CHECK: Verify storage root is set before queuing
      if (currentState.settings.customStorageRoot == null ||
          currentState.settings.customStorageRoot!.isEmpty) {
        _logger.e('❌ Range download blocked: No custom storage root selected.');
        emit(DownloadError(
          message:
              'Storage location not set. Please select a folder in Settings.',
          errorType: DownloadErrorType.storage,
          previousState: currentState,
        ));
        return;
      }

      if (!event.isValidRange) {
        throw ArgumentError(
            'Invalid page range: ${event.startPage}-${event.endPage} (total: ${event.content.pageCount})');
      }

      final existingDownload = currentState.downloads
          .where((d) => d.contentId == event.content.id)
          .firstOrNull;

      if (existingDownload != null) {
        _logger.w(
            'DownloadBloc: Content ${event.content.id} already in download list');

        if (existingDownload.canRetry) {
          _logger.i(
              'DownloadBloc: Retrying existing download for ${event.content.id}');
          add(DownloadRetryEvent(event.content.id));
        }

        return;
      }

      final downloadStatus = DownloadStatus.initial(
        event.content.id,
        event.content.pageCount,
        startPage: event.startPage,
        endPage: event.endPage,
        title: event.content.title,
        coverUrl: event.content.coverUrl,
        sourceId: event.content.sourceId,
      );

      await _userDataRepository.saveDownloadStatus(downloadStatus);

      final updatedDownloads = [...currentState.downloads, downloadStatus];
      emit(currentState.copyWith(
        downloads: updatedDownloads,
        lastUpdated: DateTime.now(),
      ));

      _updateDownloadGroupNotification();

      _logger.i('DownloadBloc: Queued range download for ${event.content.id}');

      await _processQueue();
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error queuing range download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToQueueRangeDownload(e.toString()),
          'Failed to queue range download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onStart(
    DownloadStartEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger.w('DownloadBloc: Cannot start download - not in loaded state');
      return;
    }

    try {
      _logger.i('DownloadBloc: Starting download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null) {
        _logger.w('DownloadBloc: Download not found: ${event.contentId}');
        return;
      }

      if (download.isInProgress) {
        _logger.i(
            'DownloadBloc: Download already in progress: ${event.contentId}');
        return;
      }

      if (currentState.settings.wifiOnly) {
        final connectivityResults = await _connectivity.checkConnectivity();
        final connectivityResult = connectivityResults.isNotEmpty
            ? connectivityResults.first
            : ConnectivityResult.none;

        if (connectivityResult != ConnectivityResult.wifi) {
          _logger.i(
              'DownloadBloc: WiFi required but not connected, queuing download for ${event.contentId}');

          final waitingDownload = download.copyWith(
            state: DownloadState.queued,
            error: _getLocalizedString(
              (l10n) => l10n.waitingForWifiConnection,
              'Waiting for WiFi connection',
            ),
          );

          await _userDataRepository.saveDownloadStatus(waitingDownload);
          add(const DownloadRefreshEvent());
          return;
        }
      }

      var updatedDownload = DownloadStatus(
        contentId: download.contentId,
        state: DownloadState.downloading,
        downloadedPages: download.downloadedPages,
        totalPages: download.totalPages,
        startTime: DateTime.now(),
        endTime: download.endTime,
        error: null,
        downloadPath: download.downloadPath,
        fileSize: download.fileSize,
        speed: download.speed,
        retryCount: download.retryCount,
        startPage: download.startPage,
        endPage: download.endPage,
        title: download.title,
        sourceId: download.sourceId,
        coverUrl: download.coverUrl,
      );

      await _userDataRepository.saveDownloadStatus(updatedDownload);

      final updatedDownloads = currentState.downloads
          .map((d) => d.contentId == event.contentId ? updatedDownload : d)
          .toList();

      emit(currentState.copyWith(
        downloads: updatedDownloads,
        lastUpdated: DateTime.now(),
      ));

      late Content content;
      final detailContentId = _normalizeDetailContentId(
        sourceId: updatedDownload.sourceId ?? '',
        contentId: event.contentId,
      );
      final isCompositeChapterDownload = detailContentId != event.contentId;
      try {
        content = await _getContentDetailUseCase.call(
          GetContentDetailParams.fromString(
            detailContentId,
            sourceId: updatedDownload.sourceId,
          ),
        );

        // Keep chapter ID stable for chapter downloads (e.g. "slug/17").
        // Detail APIs may require parent slug only, but offline metadata,
        // download status, and reader routing must keep the original chapter ID.
        if (isCompositeChapterDownload) {
          final chapterUrl =
              _generateFallbackUrl(updatedDownload.sourceId, event.contentId);
          content = content.copyWith(
            id: event.contentId,
            url: chapterUrl.isNotEmpty ? chapterUrl : content.url,
          );
        }
      } catch (e) {
        // getContentDetail failed - fallback
        _logger.w(
            'DownloadBloc: getContentDetail failed for ${event.contentId}, will try getChapterImages fallback: $e');
        final fallbackUrl =
            _generateFallbackUrl(updatedDownload.sourceId, event.contentId);

        content = Content(
          id: event.contentId,
          title: event.contentId,
          coverUrl: '',
          pageCount: 0,
          imageUrls: const [],
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: '',
          url: fallbackUrl,
          uploadDate: DateTime.now(),
          favorites: 0,
          sourceId: updatedDownload.sourceId ?? '',
        );
      }

      final effectiveSourceId = updatedDownload.sourceId ?? content.sourceId;
      final shouldFetchChapterImages = content.imageUrls.isEmpty ||
          _isEhentaiSource(effectiveSourceId) ||
          _hasPaginationConfig(effectiveSourceId) ||
          isCompositeChapterDownload;

      // Fallback chapter image logic
      if (shouldFetchChapterImages) {
        _logger.i(
            'DownloadBloc: Fetching chapter images for ${event.contentId} (source: $effectiveSourceId)');
        try {
          List<String> resolvedImages = const [];

          if (_isEhentaiSource(effectiveSourceId)) {
            // EHentai uses virtual part IDs and may still expose legacy chunk
            // IDs. Aggregate all linked segments before native download.
            resolvedImages = await _collectEhentaiChapterImages(
              initialChapterId: event.contentId,
              sourceId: effectiveSourceId,
            );
          } else {
            // FIX: Pass sourceId so the correct source (e.g. komiktap) is used,
            // not the currently active source which may be different.
            final chapterData = await _getChapterImagesUseCase.call(
              GetChapterImagesParams.fromString(
                event.contentId,
                sourceId: updatedDownload.sourceId,
              ),
            );
            resolvedImages = chapterData.images;
          }

          if (resolvedImages.isNotEmpty) {
            // Keep resolved images even if subsequent metadata/state updates fail.
            var fallbackUrl = content.url;
            if (fallbackUrl == null || fallbackUrl.isEmpty) {
              try {
                fallbackUrl = _generateFallbackUrl(
                    updatedDownload.sourceId, event.contentId);
              } catch (e) {
                _logger.w(
                  'DownloadBloc: Failed to generate fallback chapter URL for ${event.contentId}: $e',
                );
              }
            }

            content = content.copyWith(
              imageUrls: resolvedImages,
              pageCount: resolvedImages.length,
              url: fallbackUrl,
            );

            // Persist download metadata/state best-effort, but do not fail the
            // whole start flow after images are already resolved.
            try {
              updatedDownload = updatedDownload.copyWith(
                totalPages: resolvedImages.length,
                sourceId: updatedDownload.sourceId,
              );
              await _userDataRepository.saveDownloadStatus(updatedDownload);

              final latestState = state;
              if (latestState is DownloadLoaded) {
                emit(latestState.copyWith(
                  downloads: latestState.downloads
                      .map((d) =>
                          d.contentId == event.contentId ? updatedDownload : d)
                      .toList(),
                  lastUpdated: DateTime.now(),
                ));
              }
            } catch (e) {
              _logger.w(
                'DownloadBloc: Chapter image metadata update failed for ${event.contentId}: $e',
              );
            }
          }
        } catch (e) {
          _logger.w('Fallback chapter image fetch failed: $e');
        }
      }

      // FIX: Restore the correct title from updatedDownload since getDetail might fail or return junk for chapters
      final hasValidStoredTitle =
          updatedDownload.title != null && updatedDownload.title!.isNotEmpty;
      final isFetchedTitleInvalid = content.title.isEmpty ||
          content.title == event.contentId ||
          content.title != updatedDownload.title;

      if (hasValidStoredTitle && isFetchedTitleInvalid) {
        content = content.copyWith(
          title: updatedDownload.title!,
          // Also restore cover if it was lost during fallback
          coverUrl: updatedDownload.coverUrl != null &&
                  updatedDownload.coverUrl!.isNotEmpty
              ? updatedDownload.coverUrl!
              : content.coverUrl,
        );
        _logger.d(
            'DownloadBloc: Restored correct title from pending download status: ${content.title}');
      }

      if (content.imageUrls.isEmpty) {
        _logger.e(
          'DownloadBloc: No image URLs resolved for ${event.contentId} '
          '(source: ${content.sourceId}). Aborting download start.',
        );
        await _handleDownloadFailure(
          event.contentId,
          'No chapter images resolved for download',
          null,
          emit,
        );
        return;
      }

      final task = DownloadTask(
        contentId: event.contentId,
        title: content.title,
      );
      _activeTasks[event.contentId] = task;

      _downloadManager.registerTask(task);

      _updateDownloadGroupNotification();

      String? savePath;
      try {
        // 🐛 CRITICAL FIX: Ensure we don't reuse an UNSAFE (too long) path from a previous failed attempt
        // If contentId is long (>50 chars) and the existing path ends with it, it's likely unsafe.
        bool isExistingPathUnsafe = false;
        if (updatedDownload.downloadPath != null &&
            event.contentId.length > 50 &&
            updatedDownload.downloadPath!.endsWith(event.contentId)) {
          _logger.w(
              '⚠️ Detected unsafe existing path (too long), forcing regeneration: ${updatedDownload.downloadPath}');
          isExistingPathUnsafe = true;
        }

        if (updatedDownload.downloadPath != null &&
            updatedDownload.downloadPath!.isNotEmpty &&
            !isExistingPathUnsafe) {
          savePath = updatedDownload.downloadPath;
          _logger.d('Using existing download path: $savePath');
        } else if (currentState.settings.customStorageRoot != null &&
            currentState.settings.customStorageRoot!.isNotEmpty) {
          final baseDownloadPath = currentState.settings.customStorageRoot!;

          // Get backup folder name from AppConfig via RemoteConfigService (default: "nhasix")
          final remoteConfigService = getIt<RemoteConfigService>();
          final backupFolderName =
              remoteConfigService.appConfig?.storage?.folders?.backup ??
                  'nhasix';

          final safeContentId =
              DownloadStorageUtils.getSafeContentId(event.contentId);
          savePath = path.join(baseDownloadPath, backupFolderName,
              content.sourceId, safeContentId);
        } else {
          // STRICT REQUIREMENT: If customStorageRoot is empty, DO NOT ALLOW DOWNLOAD.
          _logger.e('❌ Download blocked: No custom storage root selected.');

          _activeTasks.remove(event.contentId);
          _downloadManager.unregisterTask(event.contentId);

          emit(DownloadError(
            message:
                'Storage location not set. Please select a folder in Settings.',
            // or check string in UI to show DownloadStorageErrorWidget
            errorType: DownloadErrorType.storage,
            previousState: currentState,
          ));
          return;
        }

        // 🐛 CRITICAL FIX: If we generated a NEW path (either brand new or regenerated safe path),
        // we MUST save it to the database immediately. Otherwise, if the download fails early (e.g. network),
        // the next retry might pick up the old unsafe path or no path at all.
        if (savePath != null && (updatedDownload.downloadPath != savePath)) {
          _logger.i('💾 Saving new safe download path to DB: $savePath');
          final newPathDownload = updatedDownload.copyWith(
            downloadPath: savePath,
          );
          await _userDataRepository
              .saveDownloadStatus(newPathDownload)
              .catchError((e) {
            _logger.w('Failed to save new download path to DB: $e');
          });
        }

        if (savePath != null) {
          await BackgroundDownloadUtils.saveResumeState(
            event.contentId,
            downloadUrl:
                content.imageUrls.isNotEmpty ? content.imageUrls.first : '',
            savePath: savePath,
            title: content.title,
            totalImages: content.pageCount,
          );
        }
      } catch (e) {
        _logger.w('Failed to save resume state for worker: $e');
      }

      Map<String, String>? cookies;

      Map<String, String>? networkHeaders;
      try {
        final rawConfig = _remoteConfigService.getRawConfig(content.sourceId);
        if (rawConfig != null) {
          final network =
              (rawConfig['network'] as Map?)?.cast<String, dynamic>();
          final configHeaders = network?['headers'];
          if (configHeaders is Map) {
            networkHeaders = configHeaders
                .cast<String, dynamic>()
                .map((k, v) => MapEntry(k, v.toString()));
          }
        }

        // Keep download headers aligned with Reader behavior: always overlay
        // source-provided `getImageDownloadHeaders(...)` on top of config
        // headers. For bypass sources this carries the runtime Cookie header
        // (cf_clearance) and WebView UA that static config can never hold —
        // cf_clearance is UA-bound, so the native worker MUST send both.
        {
          final sampleUrl = content.imageUrls.isNotEmpty
              ? content.imageUrls.first
              : (content.url ?? content.coverUrl);
          final source =
              getIt<ContentSourceRegistry>().getSource(content.sourceId);
          if (source != null && sampleUrl.isNotEmpty) {
            final sourceHeaders =
                source.getImageDownloadHeaders(imageUrl: sampleUrl);
            if (sourceHeaders.isNotEmpty) {
              networkHeaders ??= <String, String>{};
              networkHeaders.addAll(sourceHeaders);
              _logger.i(
                  '🌐 Source headers merged for ${content.sourceId}: ${sourceHeaders.keys.join(", ")}');
            }
          }
        }

        if (networkHeaders != null && networkHeaders.isNotEmpty) {
          _logger.i(
              '🌐 Loaded ${networkHeaders.length} network headers for ${content.sourceId}: ${networkHeaders.keys.join(", ")}');
        }

        // Anti-hotlink hardening: prefer dynamic referer/origin from current
        // content URL only when config/source did not provide explicit values.
        if (content.url != null && content.url!.isNotEmpty) {
          final parsedContentUri = Uri.tryParse(content.url!);
          if (parsedContentUri != null && parsedContentUri.scheme.isNotEmpty) {
            networkHeaders ??= <String, String>{};

            final normalizedReferer =
                content.url!.endsWith('/') ? content.url! : '${content.url!}/';
            final origin =
                '${parsedContentUri.scheme}://${parsedContentUri.host}';
            final hasExplicitReferer = networkHeaders.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'referer' &&
                  entry.value.trim().isNotEmpty,
            );
            final hasExplicitOrigin = networkHeaders.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'origin' &&
                  entry.value.trim().isNotEmpty,
            );

            if (!hasExplicitReferer) {
              networkHeaders['Referer'] = normalizedReferer;
              networkHeaders['referer'] = normalizedReferer;
            }
            if (!hasExplicitOrigin) {
              networkHeaders['Origin'] = origin;
              networkHeaders['origin'] = origin;
            }

            if (!hasExplicitReferer || !hasExplicitOrigin) {
              _logger.i(
                '🌐 Applied dynamic referer/origin for ${content.sourceId}: '
                '$normalizedReferer',
              );
            } else {
              _logger.d(
                '🌐 Keeping configured referer/origin for ${content.sourceId}',
              );
            }
          }
        }
      } catch (e) {
        _logger.w('DownloadBloc: Failed to extract network headers: $e');
      }

      final downloadParams = DownloadContentParams.immediate(
        content,
        imageQuality: currentState.settings.imageQuality,
        timeoutDuration: currentState.settings.timeoutDuration,
        startPage: updatedDownload.startPage,
        endPage: updatedDownload.endPage,
        cookies: cookies,
        headers: networkHeaders,
        savePath: savePath,
        enableNotifications: currentState.settings.enableNotifications,
        maxParallelImages: DownloadBloc.defaultMaxParallelImages,
      );

      final result = await _downloadContentUseCase.call(downloadParams);

      if (result.isFailed) {
        _logger.w('Download failed immediately to start: ${result.error}');
        await _handleDownloadFailure(
            event.contentId, result.error ?? 'Unknown error', null, emit);
        return;
      }

      _activeTasks.remove(event.contentId);
      _downloadManager.unregisterTask(event.contentId);

      await _processQueue();
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error starting download',
          error: e, stackTrace: stackTrace);

      _activeTasks.remove(event.contentId);
      _downloadManager.unregisterTask(event.contentId);

      await _handleDownloadFailure(event.contentId, e, stackTrace, emit);
    }
  }

  Future<void> _handleDownloadFailure(
    String contentId,
    Object error,
    StackTrace? stackTrace,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      if (error is! Exception) {
        emit(DownloadError(
          message: 'failedToStartDownload',
          errorType: _determineErrorType(error),
          previousState: null,
          stackTrace: stackTrace,
        ));
      }
      return;
    }

    final currentDownload = currentState.getDownload(contentId);

    if (currentDownload != null) {
      if (currentState.settings.autoRetry &&
          currentDownload.retryCount < currentState.settings.retryAttempts) {
        _logger.i(
            'DownloadBloc: Auto-retrying download $contentId (attempt ${currentDownload.retryCount + 1}/${currentState.settings.retryAttempts})');

        final retryDownload = currentDownload.copyWith(
          retryCount: currentDownload.retryCount + 1,
          state: DownloadState.queued,
          error: _getLocalizedString(
            (l10n) => l10n.retryingDownload(currentDownload.retryCount + 1,
                currentState.settings.retryAttempts),
            'Retrying download (attempt ${currentDownload.retryCount + 1}/${currentState.settings.retryAttempts})',
          ),
          endTime: null, // Reset end time for retry
        );

        await _userDataRepository.saveDownloadStatus(retryDownload);

        final updatedDownloads = currentState.downloads
            .map((d) => d.contentId == contentId ? retryDownload : d)
            .toList();

        emit(currentState.copyWith(
          downloads: updatedDownloads,
          lastUpdated: DateTime.now(),
        ));

        Timer(
          Duration(
            milliseconds: currentState.settings.retryDelay.inMilliseconds,
          ),
          () {
            if (!isClosed) {
              add(DownloadStartEvent(contentId));
            }
          },
        );
        return;
      }

      final failedDownload = currentDownload.copyWith(
        state: DownloadState.failed,
        error: error.toString(),
        endTime: DateTime.now(),
      );

      await _userDataRepository.saveDownloadStatus(failedDownload);

      /*
      if (currentState.settings.enableNotifications) {
        _notificationService.showDownloadError(
          contentId: contentId,
          title: failedDownload.title ?? contentId,
          error: error.toString(),
        );
      }
      */

      final updatedDownloads = currentState.downloads
          .map((d) => d.contentId == contentId ? failedDownload : d)
          .toList();

      emit(currentState.copyWith(
        downloads: updatedDownloads,
        lastUpdated: DateTime.now(),
      ));

      await _processQueue();
    } else {
      emit(DownloadError(
        message: 'failedToStartDownload',
        errorType: _determineErrorType(error),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onPause(
    DownloadPauseEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Pausing download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null || !download.canPause) {
        _logger.w('DownloadBloc: Cannot pause download: ${event.contentId}');
        return;
      }

      final task = _activeTasks[event.contentId];
      if (task != null) {
        task.pause();
        _logger.i('DownloadBloc: Paused task for ${event.contentId}');
      }

      await NativeDownloadService().pauseDownload(event.contentId);

      final updatedDownload = download.copyWith(
        state: DownloadState.paused,
        endTime: DateTime.now(),
      );

      await _userDataRepository.saveDownloadStatus(updatedDownload);

      if (currentState.settings.enableNotifications) {
        final progressPercentage = updatedDownload.progressPercentage.round();
        await _notificationService
            .updateDownloadProgress(
          contentId: event.contentId,
          progress: progressPercentage,
          title: updatedDownload.title ?? updatedDownload.contentId,
          isPaused: true,
        )
            .catchError((e) {
          _logger.w('DownloadBloc: Failed to update pause notification: $e');
        });
      }

      add(const DownloadRefreshEvent());

      _logger.i('DownloadBloc: Paused download for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error pausing download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToPauseDownload(e.toString()),
          'Failed to pause download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onCancel(
    DownloadCancelEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Cancelling download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null || !download.canCancel) {
        _logger.w('DownloadBloc: Cannot cancel download: ${event.contentId}');
        return;
      }

      _cancelDownloadTask(event.contentId);

      await NativeDownloadService().cancelDownload(event.contentId);

      final updatedDownload = download.copyWith(
        state: DownloadState.cancelled,
        endTime: DateTime.now(),
      );

      await _userDataRepository.saveDownloadStatus(updatedDownload);

      add(const DownloadRefreshEvent());

      _logger.i('DownloadBloc: Cancelled download for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error cancelling download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToCancelDownload(e.toString()),
          'Failed to cancel download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onRetry(
    DownloadRetryEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Retrying download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null) {
        _logger.w('DownloadBloc: Cannot retry download: ${event.contentId}');
        return;
      }

      final updatedDownload = DownloadStatus(
        contentId: download.contentId,
        state: DownloadState.queued,
        downloadedPages: download.downloadedPages,
        totalPages: download.totalPages,
        startTime: download.startTime,
        endTime: download.endTime,
        error: null,
        downloadPath: download.downloadPath,
        fileSize: download.fileSize,
        speed: download.speed,
        retryCount: download.retryCount,
        startPage: download.startPage,
        endPage: download.endPage,
        title: download.title,
        sourceId: download.sourceId,
        coverUrl: download.coverUrl,
      );

      await _userDataRepository.saveDownloadStatus(updatedDownload);

      // ✅ FIXED: Reset notification when retrying
      // This prevents the notification from being stuck at the last progress (e.g., 92%)
      /*
      if (currentState.settings.enableNotifications) {
        _notificationService
            .showDownloadStarted(
          contentId: event.contentId,
          title: download.title ?? download.contentId,
        )
            .catchError((e) {
          _logger.w('DownloadBloc: Failed to reset notification on retry: $e');
        });
        _logger
            .i('DownloadBloc: Reset notification for retry ${event.contentId}');
      }
      */

      add(const DownloadRefreshEvent());

      _logger.i('DownloadBloc: Queued retry for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error retrying download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToRetryDownload(e.toString()),
          'Failed to retry download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onResume(
    DownloadResumeEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Resuming download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null || download.state != DownloadState.paused) {
        _logger.w('DownloadBloc: Cannot resume download: ${event.contentId}');
        return;
      }

      final task = _activeTasks[event.contentId];
      if (task != null) {
        task.resume();
        _logger.i('DownloadBloc: Resumed task for ${event.contentId}');
      }

      final updatedDownload = DownloadStatus(
        contentId: download.contentId,
        state: DownloadState.queued,
        downloadedPages: download.downloadedPages,
        totalPages: download.totalPages,
        startTime: DateTime.now(),
        endTime: null, // Clear end time
        error: null,
        downloadPath: download.downloadPath,
        fileSize: download.fileSize,
        speed: download.speed,
        retryCount: download.retryCount,
        startPage: download.startPage,
        endPage: download.endPage,
        title: download.title,
        sourceId: download.sourceId,
        coverUrl: download.coverUrl,
      );

      await _userDataRepository.saveDownloadStatus(updatedDownload);

      if (currentState.settings.enableNotifications) {
        final progressPercentage = updatedDownload.progressPercentage.round();
        await _notificationService
            .updateDownloadProgress(
          contentId: event.contentId,
          progress: progressPercentage,
          title: updatedDownload.title ?? updatedDownload.contentId,
          isPaused: false, // Resume means no longer paused
        )
            .catchError((e) {
          _logger.w('DownloadBloc: Failed to update resume notification: $e');
        });
      }

      add(const DownloadRefreshEvent());
      await _processQueue();

      _logger.i('DownloadBloc: Resumed download for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error resuming download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToResumeDownload(e.toString()),
          'Failed to resume download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onRemove(
    DownloadRemoveEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Removing download for ${event.contentId}');

      final download = currentState.downloads
          .where((d) => d.contentId == event.contentId)
          .firstOrNull;

      if (download == null) {
        _logger.w('DownloadBloc: Download not found: ${event.contentId}');
        return;
      }

      if (download.isInProgress) {
        _cancelDownloadTask(event.contentId);
      }

      // Optimistic update: Remove from state immediately to prevent race conditions
      // if user tries to re-download while deletion is in progress
      final updatedDownloads = currentState.downloads
          .where((d) => d.contentId != event.contentId)
          .toList();

      emit(currentState.copyWith(
        downloads: updatedDownloads,
        lastUpdated: DateTime.now(),
      ));

      await _userDataRepository.deleteDownloadStatus(event.contentId);

      String? pathToDelete = download.downloadPath;
      if (pathToDelete == null || pathToDelete.isEmpty) {
        if (currentState.settings.customStorageRoot != null) {
          // Best guess reconstruction: root/nhasix/[source]/[id]
          // We might need sourceId, hopefully it's in the download object or we guess
          final sourceId = download.sourceId ??
              'unknown'; // Fallback might fail but worth a try or iterate sources
          pathToDelete = path.join(currentState.settings.customStorageRoot!,
              'nhasix', sourceId, event.contentId);
        }
      }

      await _downloadContentUseCase.deleteCall(event.contentId,
          dirPath: pathToDelete);

      ContentDownloadCache.invalidateCache(event.contentId);

      // 🐛 FIX Bug B: Invalidate OfflineContentManager path/image cache so the
      // reader does not serve stale offline paths after the files are deleted.
      try {
        getIt<OfflineContentManager>().invalidateCacheFor(event.contentId);
      } catch (e) {
        _logger.e('Cache invalidation failed', error: e);
      }

      add(const DownloadRefreshEvent());

      _logger.i('DownloadBloc: Removed download for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error removing download',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToRemoveDownload(e.toString()),
          'Failed to remove download: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onRefresh(
    DownloadRefreshEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;

    try {
      _logger.i('DownloadBloc: Refreshing download list');

      // 🔄 CRITICAL: Reload customStorageRoot from StorageSettings
      // This ensures UI always shows correct storage location even if:
      // 1. DownloadBloc was initialized before storage location was set
      // 2. User changed storage location via settings dialog
      final customRoot = await StorageSettings.getCustomRootPath();
      _logger.d(
          '📁 DOWNLOAD_BLOC: Refreshing customStorageRoot from StorageSettings');
      _logger.d('📁 DOWNLOAD_BLOC: customRoot value on refresh: $customRoot');

      _settings = _settings.copyWith(customStorageRoot: customRoot);
      _logger.d(
          '📁 DOWNLOAD_BLOC: Updated _settings.customStorageRoot: ${_settings.customStorageRoot}');

      final downloads = await _loadAllDownloadsFromDb();

      if (currentState is DownloadLoaded) {
        emit(currentState.copyWith(
          downloads: downloads,
          lastUpdated: DateTime.now(),
        ));
      } else {
        emit(DownloadLoaded(
          downloads: downloads,
          settings: _settings,
          lastUpdated: DateTime.now(),
        ));
      }

      _logger.i('DownloadBloc: Refreshed with ${downloads.length} downloads');

      await _processQueue();
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error refreshing downloads',
          error: e, stackTrace: stackTrace);

      if (currentState is! DownloadLoaded) {
        emit(DownloadError(
          message: _getLocalizedString(
            (l10n) => l10n.failedToRefreshDownloads(e.toString()),
            'Failed to refresh downloads: ${e.toString()}',
          ),
          errorType: _determineErrorType(e),
          previousState: currentState is DownloadLoaded ? currentState : null,
          stackTrace: stackTrace,
        ));
      }
    }
  }

  DateTime _lastNotifUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _notifThrottle = Duration(milliseconds: 300);

  Future<void> _onProgressUpdate(
    DownloadProgressUpdateEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final cs = state;
    if (cs is! DownloadLoaded && cs is! DownloadProcessing) return;

    final dl = cs.downloads;
    final idx = dl.indexWhere((d) => d.contentId == event.contentId);
    if (idx == -1) return;

    final cur = dl[idx];
    if (event.downloadedPages < cur.downloadedPages &&
        event.downloadedPages >= 0) {
      _logger.w(
          'DownloadBloc: Ignoring regressive progress for ${event.contentId}');
      return;
    }

    // Skip emit if downloadedPages unchanged (duplicate event from stream)
    if (event.downloadedPages == cur.downloadedPages) return;

    final targetState = cur.state == DownloadState.queued
        ? DownloadState.downloading
        : cur.state;

    final effectiveTotal =
        event.totalPages > 0 ? event.totalPages : cur.totalPages;

    final updated = cur.copyWith(
      state: targetState,
      downloadedPages: event.downloadedPages,
      totalPages: effectiveTotal,
      speed: event.downloadSpeed,
    );

    final newDownloads = [...dl]..[idx] = updated;
    emit(DownloadLoaded(
      downloads: newDownloads,
      settings: cs is DownloadLoaded
          ? cs.settings
          : (cs as DownloadProcessing).settings,
      lastUpdated: DateTime.now(),
    ));

    // Batch DB save
    final isTerminal = updated.downloadedPages >= updated.totalPages;
    if (isTerminal) {
      await _userDataRepository.saveDownloadStatus(updated).catchError(
          (e) => _logger.w('DownloadBloc: Failed to save progress: $e'));
      _pendingDbSave.remove(event.contentId);
    } else {
      final skip = (_dbSaveSkipCount[event.contentId] ?? 0) + 1;
      _dbSaveSkipCount[event.contentId] = skip;
      if (skip >= _kDbSaveInterval) {
        _dbSaveSkipCount[event.contentId] = 0;
        await _userDataRepository.saveDownloadStatus(updated).catchError(
            (e) => _logger.w('DownloadBloc: Failed to save progress: $e'));
        _pendingDbSave.remove(event.contentId);
      } else {
        _pendingDbSave.add(event.contentId);
      }
    }

    // Throttle notification update to max 1 per 300ms (platform channel is expensive)
    final now = DateTime.now();
    if (now.difference(_lastNotifUpdate) >= _notifThrottle) {
      _lastNotifUpdate = now;
      _updateDownloadGroupNotification();
    }

    _logger.d(
        'DownloadBloc: Progress ${event.contentId}: ${event.downloadedPages}/${event.totalPages}');
  }

  void _updateDownloadGroupNotification() {
    final cs = state;
    if (cs is! DownloadLoaded) return;
    final active = cs.downloads
        .where((d) => d.state == DownloadState.downloading)
        .toList();
    if (active.isEmpty) return;
    final total = active.fold<int>(0, (s, d) => s + d.totalPages);
    final done = active.fold<int>(0, (s, d) => s + d.downloadedPages);
    final pct = total > 0 ? (done / total * 100).round() : 0;
    final speed = active.fold<double>(0, (s, d) => s + d.speed);
    final speedText = _formatSpeedForNotif(speed);
    _notificationService.updateDownloadGroupProgress(
      activeCount: active.length,
      totalProgress: pct,
      speedText: speedText,
    );
  }

  String _formatSpeedForNotif(double speed) {
    if (speed <= 0) return '';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var v = speed;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  void _notifyAllDownloadsComplete() {
    final cs = state;
    if (cs is! DownloadLoaded) return;
    final active = cs.downloads
        .where((d) => d.state == DownloadState.downloading)
        .toList();
    if (active.isEmpty && _sessionCompletedCount > 0) {
      _notificationService.showDownloadGroupCompleted(_sessionCompletedCount);
      _sessionCompletedCount = 0;
    }
  }

  Future<void> _onCompleted(
    DownloadCompletedEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;

    // We need to be in a loaded state to process this, or at least have access to the lists
    // If state is not loaded, we might just want to refresh to get latest state from DB
    // But importantly, we MUST update the DB to say "completed" first.

    try {
      _logger.i('🎯 DownloadBloc: Handling completion for ${event.contentId}');

      // We need to fetch current status to preserve other fields (like title, etc)
      // If we are in Loaded state, use that. Otherwise fetch from DB.

      DownloadStatus? currentDownload;

      if (currentState is DownloadLoaded) {
        currentDownload = currentState.getDownload(event.contentId);
        _logger.d('Found download in state: ${currentDownload != null}');
      }

      // If not found in state or state not loaded, fetch from DB
      if (currentDownload == null) {
        _logger.d('Fetching download from database...');
        currentDownload =
            await _userDataRepository.getDownloadStatus(event.contentId);
      }

      if (currentDownload == null) {
        _logger
            .w('DownloadBloc: Completing unknown download ${event.contentId}');
        add(const DownloadRefreshEvent());
        return;
      }

      currentDownload = currentDownload.copyWith(
        downloadedPages: currentDownload.pagesToDownload,
        totalPages: currentDownload.totalPages > 0
            ? currentDownload.totalPages
            : currentDownload.pagesToDownload,
        state: DownloadState.completed,
      );

      int totalSize = currentDownload.fileSize;
      String? downloadPath = currentDownload.downloadPath;

      // FALLBACK: If downloadPath is missing or invalid, use smart lookup
      if (downloadPath == null ||
          downloadPath.isEmpty ||
          !File(downloadPath).parent.existsSync()) {
        _logger.w('⚠️ Download path missing or invalid, using smart lookup');
        try {
          downloadPath = await DownloadStorageUtils.getContentDirectory(
              event.contentId,
              sourceId: currentDownload.sourceId);
          _logger.i('✅ Resolved path via smart lookup: $downloadPath');
        } catch (e) {
          _logger.e('Failed to resolve path via smart lookup', error: e);
        }
      }

      if (downloadPath != null && downloadPath.isNotEmpty) {
        String currentPath = downloadPath;
        _logger.d('Calculating file size for path: $currentPath');

        // Try multiple times with delays in case filesystem is still syncing
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            final dir = Directory(currentPath);
            if (!dir.existsSync()) {
              _logger.w(
                  'Directory does not exist (attempt $attempt): $currentPath');

              // LAST RESORT: Try to find ANY valid directory for this content
              // This handles cases where downloadPath might point to "images" subdir or parent
              final smartPath = await DownloadStorageUtils.getContentDirectory(
                  event.contentId,
                  sourceId: currentDownload.sourceId);

              if (Directory(smartPath).existsSync()) {
                currentPath = smartPath; // Update checks to use this valid path
                downloadPath = smartPath; // Update main variable too
                _logger.i(
                    'Found valid directory via smart lookup recovery: $smartPath');
                // Don't continue, just let the next lines use this new path
              } else {
                if (attempt < 3) {
                  await Future.delayed(Duration(milliseconds: 500 * attempt));
                  continue;
                }
              }
            }

            // Double check existence after potential recovery
            if (Directory(currentPath).existsSync()) {
              totalSize = await DownloadStorageUtils.getDirectorySize(
                  Directory(currentPath));
              _logger.i(
                  '💾 Calculated final size for ${event.contentId}: ${DownloadStorageUtils.formatBytes(totalSize)} ($totalSize bytes)');
              break; // Success
            }
          } catch (e) {
            _logger.w('Failed to calculate size (attempt $attempt/3): $e');
            if (attempt < 3) {
              await Future.delayed(Duration(milliseconds: 500 * attempt));
            }
          }
        }
      } else {
        _logger
            .e('❌ Cannot calculate file size: downloadPath is null or empty');
      }

      final downloadedImagesCount = await _countDownloadedImages(
        contentId: event.contentId,
        sourceId: currentDownload.sourceId,
        downloadPath: downloadPath,
      );
      final hasPathHint = (downloadPath != null && downloadPath.isNotEmpty) ||
          (currentDownload.downloadPath != null &&
              currentDownload.downloadPath!.isNotEmpty);
      if (hasPathHint && downloadedImagesCount <= 0) {
        _logger.e(
          '❌ DownloadBloc: Native completion arrived but no image files were found '
          'for ${event.contentId}. Marking as failed.',
        );
        await _handleDownloadFailure(
          event.contentId,
          'Native download completed without saved image files',
          null,
          emit,
        );
        add(const DownloadRefreshEvent());
        return;
      }

      try {
        await _offlineContentManager
            .reconcileChapterMetadataForCompletedDownload(
          contentId: event.contentId,
          contentPath: downloadPath,
        );
      } catch (e) {
        _logger.w(
          'DownloadBloc: metadata reconciliation skipped for ${event.contentId}: $e',
        );
      }

      final completedDownload = DownloadStatus(
        contentId: currentDownload.contentId,
        state: DownloadState.completed,
        downloadedPages: downloadedImagesCount,
        totalPages: currentDownload.totalPages > 0
            ? currentDownload.totalPages
            : downloadedImagesCount,
        startTime: currentDownload.startTime,
        endTime: DateTime.now(),
        error: null,
        downloadPath: downloadPath, // Update path if retrieved
        fileSize: totalSize, // Save calculated size
        speed: currentDownload.speed,
        retryCount: currentDownload.retryCount,
        startPage: currentDownload.startPage,
        endPage: currentDownload.endPage,
        title: currentDownload.title,
        sourceId: currentDownload.sourceId,
        coverUrl: currentDownload.coverUrl,
      );

      _logger.d('Saving completed download to database...');
      await _userDataRepository.saveDownloadStatus(completedDownload);
      RecommendationRefreshBus.requestGlobalRefresh();
      _logger.i(
          '✅ Saved "completed" status to DB for ${event.contentId} with size: ${DownloadStorageUtils.formatBytes(totalSize)}');

      _activeTasks.remove(event.contentId);
      _downloadManager.unregisterTask(event.contentId);
      _logger.d('Removed ${event.contentId} from active tasks');

      if (currentState is DownloadLoaded) {
        final updatedDownloads = currentState.downloads
            .map((d) => d.contentId == event.contentId ? completedDownload : d)
            .toList();

        emit(currentState.copyWith(
          downloads: updatedDownloads,
          lastUpdated: DateTime.now(),
        ));
        _logger.d('Updated state with completed download');
      }

      _sessionCompletedCount++;
      _updateDownloadGroupNotification();
      _notifyAllDownloadsComplete();

      _logger.d('Triggering refresh to sync offline content...');
      add(const DownloadRefreshEvent());

      await _processQueue();

      _logger.i('🎉 Completion handling finished for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e('❌ DownloadBloc: Error handling completion',
          error: e, stackTrace: stackTrace);
      add(const DownloadRefreshEvent());
    }
  }

  Future<void> _onNativeFailed(
    DownloadNativeFailedEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    _logger.e(
      'DownloadBloc: Native layer reported failure for ${event.contentId}',
    );
    await _handleDownloadFailure(
      event.contentId,
      event.error ?? 'Native download failed',
      null,
      emit,
    );
  }

  Future<void> _onSettingsUpdate(
    DownloadSettingsUpdateEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Updating download settings');

      _settings = _settings.copyWith(
        maxConcurrentDownloads: event.maxConcurrentDownloads,
        imageQuality: event.imageQuality,
        autoRetry: event.autoRetry,
        retryAttempts: event.retryAttempts,
        retryDelay: event.retryDelay,
        timeoutDuration: event.timeoutDuration,
        enableNotifications: event.enableNotifications,
        wifiOnly: event.wifiOnly,
        customStorageRoot: event.customStorageRoot,
      );

      emit(currentState.copyWith(settings: _settings));

      final currentUserPrefs = await _userDataRepository.getUserPreferences();
      final updatedUserPrefs = currentUserPrefs.copyWith(
        maxConcurrentDownloads: event.maxConcurrentDownloads,
        imageQuality: event.imageQuality,
        customStorageRoot: event.customStorageRoot,
        autoRetry: event.autoRetry,
        retryAttempts: event.retryAttempts,
        retryDelaySeconds: event.retryDelay?.inSeconds,
        timeoutDurationSeconds: event.timeoutDuration?.inSeconds,
        enableNotifications: event.enableNotifications,
        wifiOnly: event.wifiOnly,
      );

      await _userDataRepository.saveUserPreferences(updatedUserPrefs);

      _logger.i(
          'DownloadBloc: Updated download settings - concurrent: ${_settings.maxConcurrentDownloads}, quality: ${_settings.imageQuality}, wifiOnly: ${_settings.wifiOnly}, notifications: ${_settings.enableNotifications}, customRoot: ${_settings.customStorageRoot}');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error updating settings',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToUpdateDownloadSettings(e.toString()),
          'Failed to update download settings: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  void _cancelDownloadTask(String contentId) {
    final task = _activeTasks[contentId];
    if (task != null && !task.isCancelled) {
      task.cancel('Download cancelled by user');
      _activeTasks.remove(contentId);

      _downloadManager.unregisterTask(contentId);
      _logger.d('DownloadBloc: Cancelled task for $contentId');
    }
  }

  Future<void> _onBulkAction(
    DownloadBulkActionEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Bulk action ${event.action}');

      List<DownloadStatus> targets;
      DownloadState newState;
      String operation;

      switch (event.action) {
        case BulkAction.pauseAll:
          targets = currentState.downloads
              .where((d) => d.state == DownloadState.downloading)
              .toList();
          if (targets.isEmpty) {
            _logger.i('DownloadBloc: No active downloads to pause');
            emit(currentState.copyWith(lastUpdated: DateTime.now()));
            return;
          }
          newState = DownloadState.paused;
          operation = 'Pausing all downloads';
        case BulkAction.resumeAll:
          targets = currentState.downloads
              .where((d) => d.state == DownloadState.paused)
              .toList();
          if (targets.isEmpty) {
            _logger.i('DownloadBloc: No paused downloads to resume');
            emit(currentState.copyWith(lastUpdated: DateTime.now()));
            return;
          }
          newState = DownloadState.queued;
          operation = 'Resuming all downloads';
        case BulkAction.cancelAll:
          targets = currentState.downloads
              .where((d) =>
                  d.state == DownloadState.downloading ||
                  d.state == DownloadState.queued)
              .toList();
          if (targets.isEmpty) {
            _logger.i('DownloadBloc: No active or queued downloads to cancel');
            emit(currentState.copyWith(lastUpdated: DateTime.now()));
            return;
          }
          newState = DownloadState.cancelled;
          operation = 'Cancelling all downloads';
        case BulkAction.clearCompleted:
          targets = currentState.downloads
              .where((d) => d.state == DownloadState.completed)
              .toList();
          if (targets.isEmpty) {
            _logger.i('DownloadBloc: No completed downloads to clear');
            emit(currentState.copyWith(lastUpdated: DateTime.now()));
            return;
          }
          emit(DownloadProcessing(
            downloads: currentState.downloads,
            settings: currentState.settings,
            operation: 'Clearing completed downloads',
            lastUpdated: currentState.lastUpdated,
          ));
          for (final d in targets) {
            await _userDataRepository.deleteDownloadStatus(d.contentId);
          }
          add(const DownloadRefreshEvent());
          _logger
              .i('DownloadBloc: Cleared ${targets.length} completed downloads');
          return;
      }

      emit(DownloadProcessing(
        downloads: currentState.downloads,
        settings: currentState.settings,
        operation: operation,
        lastUpdated: currentState.lastUpdated,
      ));

      for (final download in targets) {
        if (newState == DownloadState.paused ||
            newState == DownloadState.cancelled) {
          _cancelDownloadTask(download.contentId);
        }
        final updated = download.copyWith(
            state: newState,
            endTime: newState == DownloadState.queued ? null : DateTime.now());
        await _userDataRepository.saveDownloadStatus(updated);
      }

      add(const DownloadRefreshEvent());
      if (event.action == BulkAction.resumeAll) await _processQueue();

      _logger.i('DownloadBloc: Bulk action ${event.action} completed');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error in bulk action ${event.action}',
          error: e, stackTrace: stackTrace);
      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToPauseAllDownloads(e.toString()),
          'Bulk action failed: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  Future<void> _onSelectionAction(
    DownloadSelectionActionEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i('DownloadBloc: Selection action ${event.action}');

      switch (event.action) {
        case SelectionAction.selectItem:
          if (event.contentId == null || event.isSelected == null) return;
          final updated = Set<String>.from(currentState.selectedItems);
          if (event.isSelected!) {
            updated.add(event.contentId!);
          } else {
            updated.remove(event.contentId!);
          }
          emit(currentState.copyWith(
            selectedItems: updated,
            lastUpdated: DateTime.now(),
          ));

        case SelectionAction.selectAll:
          final allIds = currentState.downloads.map((d) => d.contentId).toSet();
          emit(currentState.copyWith(
            selectedItems: allIds,
            lastUpdated: DateTime.now(),
          ));

        case SelectionAction.clearSelection:
          emit(currentState.copyWith(
            selectedItems: const {},
            lastUpdated: DateTime.now(),
          ));

        case SelectionAction.toggleSelectionMode:
          emit(currentState.copyWith(
            isSelectionMode: !currentState.isSelectionMode,
            selectedItems: const {},
            lastUpdated: DateTime.now(),
          ));
      }

      _logger.i('DownloadBloc: Selection action ${event.action} completed');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error in selection action',
          error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _onConvertToPdf(
    DownloadConvertToPdfEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger.w('DownloadBloc: Cannot convert to PDF - not in loaded state');
      return;
    }

    try {
      _logger.i('DownloadBloc: Starting PDF conversion for ${event.contentId}');

      final download = currentState.downloads.firstWhere(
        (d) => d.contentId == event.contentId,
        orElse: () => throw Exception(
            'Download not found for content: ${event.contentId}'),
      );

      if (!download.isCompleted) {
        _logger.w(
            'DownloadBloc: Cannot convert incomplete download to PDF: ${event.contentId}');
        await _notificationService.showPdfConversionError(
          contentId: event.contentId,
          title: event.contentId,
          error: _getLocalizedString(
            (l10n) => l10n.downloadNotCompletedYet,
            'Download not completed yet',
          ),
        );
        return;
      }

      String? sourceId = event.sourceId;

      if (sourceId == null) {
        _logger.d(
            'DownloadBloc: sourceId not provided, attempting discovery for ${event.contentId}');
        for (final source in AppStorage.knownSources) {
          final metadata = await DownloadStorageUtils.readLocalMetadata(
            event.contentId,
            sourceId: source,
          );
          if (metadata != null) {
            sourceId = source;
            _logger.i(
                'DownloadBloc: Discovered sourceId for ${event.contentId}: $sourceId');
            break;
          }
        }
      }

      String contentTitle = event.contentId;
      final localMetadata = await DownloadStorageUtils.readLocalMetadata(
        event.contentId,
        sourceId: sourceId,
      );

      if (localMetadata != null) {
        // Use local metadata for offline support
        // FIX: Use safe title extraction to handle empty strings
        contentTitle = DownloadStorageUtils.getSafeTitleFromMetadata(
          localMetadata,
          event.contentId,
        );
        // If sourceId was still null (legacy path), try to get it from metadata
        if (sourceId == null && localMetadata['source'] != null) {
          sourceId = localMetadata['source'] as String;
        }
        _logger.i(
            'DownloadBloc: Using local metadata for PDF conversion - Title: $contentTitle, Source: $sourceId');
      } else {
        try {
          final content = await _getContentDetailUseCase.call(
            GetContentDetailParams.fromString(event.contentId),
          );
          contentTitle = content.title;
          sourceId ??= content.sourceId;
          _logger.i(
              'DownloadBloc: Using API content details for PDF conversion - Title: $contentTitle, Source: $sourceId');
        } catch (e) {
          _logger.w(
              'DownloadBloc: Failed to get content details from API, using contentId as title: $e');
        }
      }

      final imagePaths = await DownloadStorageUtils.getDownloadedImagePaths(
        event.contentId,
        sourceId: sourceId,
      );

      if (imagePaths.isEmpty) {
        _logger.w(
            'DownloadBloc: No downloaded images found for PDF conversion: ${event.contentId}');
        await _notificationService.showPdfConversionError(
          contentId: event.contentId,
          title: contentTitle,
          error: _getLocalizedString(
            (l10n) => l10n.noImagesFoundForConversion,
            'No images found for conversion',
          ),
        );
        return;
      }

      await _notificationService.cancelDownloadNotification(event.contentId);

      await _pdfConversionQueueManager.queueConversion(
        contentId: event.contentId,
        title: contentTitle,
        imagePaths: imagePaths,
        sourceId: sourceId,
      );

      _logger.i('DownloadBloc: PDF conversion queued for ${event.contentId}');
    } catch (e, stackTrace) {
      _logger.e(
          'DownloadBloc: Error during PDF conversion for ${event.contentId}',
          error: e,
          stackTrace: stackTrace);

      await _notificationService.showPdfConversionError(
        contentId: event.contentId,
        title: event.contentId, // Use contentId as fallback title in error case
        error: e.toString(),
      );
    }
  }

  Future<void> _onOpenContent(
    DownloadOpenContentEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    await _openDownloadedContent(event.contentId);
  }

  Future<void> _onCleanupStorage(
    DownloadCleanupStorageEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger.w('DownloadBloc: Cannot cleanup storage - not in loaded state');
      return;
    }

    try {
      _logger.i('DownloadBloc: Starting storage cleanup');

      final downloadsPath = await DownloadStorageUtils.getDownloadsDirectory();
      final nhasixDir = Directory(path.join(downloadsPath, 'nhasix'));

      if (!await nhasixDir.exists()) {
        _logger
            .i('DownloadBloc: No nhasix directory found, nothing to cleanup');
        return;
      }

      int cleanedFiles = 0;
      int freedSpaceBytes = 0;

      final contentDirs = <Directory>[];
      await for (final entity in nhasixDir.list()) {
        if (entity is Directory) {
          contentDirs.add(entity);
        }
      }

      for (final contentDir in contentDirs) {
        final contentId = path.basename(contentDir.path);

        // Check if this content is still in downloads list
        final isActiveDownload = currentState.downloads
            .any((download) => download.contentId == contentId);

        if (!isActiveDownload) {
          // This is an orphaned download, safe to delete
          _logger.d('DownloadBloc: Cleaning up orphaned download: $contentId');

          try {
            final dirSize =
                await DownloadStorageUtils.getDirectorySize(contentDir);

            await contentDir.delete(recursive: true);

            cleanedFiles++;
            freedSpaceBytes += dirSize;

            _logger.d(
                'DownloadBloc: Cleaned up ${(dirSize / 1024 / 1024).toStringAsFixed(2)} MB from: $contentId');
          } catch (e) {
            _logger.w(
                'DownloadBloc: Failed to delete directory: ${contentDir.path}, error: $e');
          }
        } else {
          // For active downloads, clean up temporary files
          await DownloadStorageUtils.cleanupTempFiles(contentDir);
        }
      }

      _logger.i(
          'DownloadBloc: Storage cleanup completed. Cleaned $cleanedFiles directories, freed ${(freedSpaceBytes / 1024 / 1024).toStringAsFixed(2)} MB');

      _logger.i(
          'Storage Cleanup Complete: Cleaned $cleanedFiles items, freed ${(freedSpaceBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error during storage cleanup',
          error: e, stackTrace: stackTrace);

      _logger.e('Storage Cleanup Failed: ${e.toString()}');
    }
  }

  Future<void> _onExport(
    DownloadExportEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) {
      _logger.w('DownloadBloc: Cannot export - not in loaded state');
      return;
    }

    try {
      _logger.i('DownloadBloc: Starting export operation');

      final exportData = <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'app_version': '1.0.0', // You can get this from package_info_plus
        'total_downloads': currentState.downloads.length,
        'downloads': currentState.downloads
            .map((download) => {
                  'content_id': download.contentId,
                  'state': download.state.toString(),
                  'progress': download.progress,
                  'downloaded_pages': download.downloadedPages,
                  'total_pages': download.totalPages,
                  'file_size': download.fileSize,
                  'speed': download.speed,
                  'start_time': download.startTime?.toIso8601String(),
                  'end_time': download.endTime?.toIso8601String(),
                  'download_path': download.downloadPath,
                  'error': download.error,
                  'is_completed': download.isCompleted,
                  'is_paused': download.isPaused,
                  'is_cancelled': download.isCancelled,
                  'is_failed': download.isFailed,
                })
            .toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      final downloadsPath = await DownloadStorageUtils.getDownloadsDirectory();
      final exportFileName =
          'nhasix_downloads_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final exportFile = File(path.join(downloadsPath, exportFileName));

      await exportFile.writeAsString(jsonString);

      _logger.i('DownloadBloc: Export completed: ${exportFile.path}');

      _logger.i('Export Complete: Downloads exported to $exportFileName');
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error during export',
          error: e, stackTrace: stackTrace);

      _logger.e('Export Failed: ${e.toString()}');
    }
  }

  Future<void> _retryPdfConversion(String contentId) async {
    try {
      final downloads = await _loadAllDownloadsFromDb();
      final download = downloads.firstWhere(
        (d) => d.contentId == contentId,
        orElse: () =>
            throw Exception('Download not found for content: $contentId'),
      );

      if (download.state == DownloadState.completed) {
        add(DownloadConvertToPdfEvent(contentId));
        _logger.i('DownloadBloc: PDF retry initiated for $contentId');
      } else {
        _logger.w(
            'DownloadBloc: Cannot retry PDF - download not completed for $contentId');
      }
    } catch (e) {
      _logger.e('DownloadBloc: Error retrying PDF conversion: $e');
    }
  }

  Future<void> _openDownloadedContent(String contentId) async {
    try {
      final downloads = await _loadAllDownloadsFromDb();

      final download =
          downloads.where((d) => d.contentId == contentId).firstOrNull;

      if (download == null) {
        _logger.w('DownloadBloc: Download not found for content: $contentId');
        return;
      }

      String? downloadPath = download.downloadPath;
      if (downloadPath == null || downloadPath.isEmpty) {
        if (_settings.customStorageRoot != null &&
            _settings.customStorageRoot!.isNotEmpty) {
          final sourceId =
              (download.sourceId != null && download.sourceId!.isNotEmpty)
                  ? download.sourceId!
                  : 'unknown';
          downloadPath = path.join(
              _settings.customStorageRoot!, 'nhasix', sourceId, contentId);
          _logger.d('DownloadBloc: Reconstructed path for open: $downloadPath');
        }
      }

      if (downloadPath != null) {
        final directory = Directory(downloadPath);
        // Relaxed check: Exist on disk is enough, even if state is not "Completed"
        if (await directory.exists()) {
          _logger.i('DownloadBloc: Opening download directory: $downloadPath');

          // Check if this is a PDF file (has pdf/ subdirectory with .pdf files)
          final pdfDir = Directory(path.join(downloadPath, 'pdf'));
          if (await pdfDir.exists()) {
            try {
              final pdfFiles = await pdfDir
                  .list()
                  .where((entity) => entity.path.endsWith('.pdf'))
                  .toList();

              if (pdfFiles.isNotEmpty) {
                _logger.i(
                    'DownloadBloc: Found PDF file, opening with native reader');
                final pdfReaderService = getIt<NativePdfReaderService>();
                // Sort by name to get the latest/main one if multiple
                final sortedFiles = pdfFiles.toList()
                  ..sort((a, b) => b.path.compareTo(a.path));

                await pdfReaderService.openPdf(sortedFiles.first.path);
                return;
              }
            } catch (e) {
              _logger.w('DownloadBloc: Error checking for PDF: $e');
            }
          }

          bool opened = false;

          try {
            final result = await OpenFile.open(downloadPath);
            if (result.type == ResultType.done) {
              _logger.i('DownloadBloc: Successfully opened download directory');
              opened = true;
            } else {
              _logger.w(
                  'DownloadBloc: Failed to open directory: ${result.message}');
            }
          } catch (e) {
            _logger.w('DownloadBloc: Error opening directory: $e');
          }

          if (!opened) {
            try {
              final imagesDir = Directory(path.join(downloadPath, 'images'));
              if (await imagesDir.exists()) {
                final result = await OpenFile.open(imagesDir.path);
                if (result.type == ResultType.done) {
                  _logger
                      .i('DownloadBloc: Successfully opened images directory');
                  opened = true;
                } else {
                  _logger.w(
                      'DownloadBloc: Failed to open images directory: ${result.message}');
                }
              }
            } catch (e) {
              _logger.w('DownloadBloc: Error opening images directory: $e');
            }
          }

          if (!opened) {
            try {
              final imagePaths =
                  await DownloadStorageUtils.getDownloadedImagePaths(contentId);
              if (imagePaths.isNotEmpty) {
                final firstImage = imagePaths.first;
                final result = await OpenFile.open(firstImage);
                if (result.type == ResultType.done) {
                  _logger.i(
                      'DownloadBloc: Successfully opened first image: $firstImage');
                  opened = true;
                } else {
                  _logger.w(
                      'DownloadBloc: Failed to open first image: ${result.message}');
                }
              }
            } catch (e) {
              _logger.w('DownloadBloc: Error opening first image: $e');
            }
          }

          if (!opened) {
            _logger.e(
                'DownloadBloc: All strategies failed to open downloaded content for $contentId');
          }
        } else {
          _logger
              .w('DownloadBloc: Download directory not found: $downloadPath');
        }
      } else {
        _logger.w(
            'DownloadBloc: Cannot open - path missing and could not be reconstructed for $contentId');
      }
    } catch (e) {
      _logger.e('DownloadBloc: Error opening downloaded content: $e');
    }
  }

  Future<void> _onBulkDelete(
    DownloadBulkDeleteEvent event,
    Emitter<DownloadBlocState> emit,
  ) async {
    final currentState = state;
    if (currentState is! DownloadLoaded) return;

    try {
      _logger.i(
          'DownloadBloc: Starting bulk delete of ${event.contentIds.length} items');

      emit(DownloadProcessing(
        downloads: currentState.downloads,
        settings: currentState.settings,
        operation: 'Deleting ${event.contentIds.length} downloads',
        lastUpdated: currentState.lastUpdated,
      ));

      int successCount = 0;
      int failureCount = 0;
      final errors = <String>[];

      for (final contentId in event.contentIds) {
        try {
          if (currentState.getDownload(contentId)?.isInProgress == true) {
            _cancelDownloadTask(contentId);
          }

          await _userDataRepository.deleteDownloadStatus(contentId);
          await _downloadContentUseCase.deleteCall(contentId);

          ContentDownloadCache.invalidateCache(contentId);

          // 🐛 FIX Bug B: Invalidate OfflineContentManager cache for each deleted item
          try {
            getIt<OfflineContentManager>().invalidateCacheFor(contentId);
          } catch (e) {
            _logger.e('Cache invalidation failed for $contentId', error: e);
          }

          successCount++;
          _logger.d('DownloadBloc: Successfully deleted $contentId');
        } catch (e) {
          failureCount++;
          errors.add('$contentId: $e');
          _logger.w('DownloadBloc: Failed to delete $contentId: $e');
        }
      }

      final updatedDownloads = currentState.downloads
          .where((d) => !event.contentIds.contains(d.contentId))
          .toList();

      emit(DownloadLoaded(
        downloads: updatedDownloads,
        settings: currentState.settings,
        isSelectionMode: false,
        selectedItems: const {},
        lastUpdated: DateTime.now(),
      ));

      _logger.i(
          'DownloadBloc: Bulk delete completed. Success: $successCount, Failures: $failureCount');

      add(const DownloadRefreshEvent());

      if (errors.isNotEmpty) {
        throw BulkDeleteException(
          'Bulk delete completed with $failureCount failures: ${errors.join(', ')}',
        );
      }
    } catch (e, stackTrace) {
      _logger.e('DownloadBloc: Error during bulk delete',
          error: e, stackTrace: stackTrace);

      emit(DownloadError(
        message: _getLocalizedString(
          (l10n) => l10n.failedToRemoveDownload(e.toString()),
          'Bulk delete failed: ${e.toString()}',
        ),
        errorType: _determineErrorType(e),
        previousState: currentState,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    _logger.i('DownloadBloc: Progress stream subscription cancelled');

    _dbFlushTimer?.cancel();
    //  fire-and-forget — may not complete if event loop shutting down
    _flushPendingDbSaves();
    _logger.i('DownloadBloc: DB flush timer cancelled, pending saves flushed');

    for (final task in _activeTasks.values) {
      if (!task.isCancelled) {
        task.cancel('BLoC is closing');
      }
      _downloadManager.unregisterTask(task.contentId);
    }
    _activeTasks.clear();

    return super.close();
  }
}

class BulkDeleteException implements Exception {
  final String message;
  const BulkDeleteException(this.message);

  @override
  String toString() => message;
}
