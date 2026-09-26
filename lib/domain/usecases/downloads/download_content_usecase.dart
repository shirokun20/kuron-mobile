import 'dart:async';
import 'package:kuron_generic/kuron_generic.dart'
    show PageResolutionPipeline, PageResolutionInput;
import 'package:logger/logger.dart';

import '../base_usecase.dart';
import '../../entities/entities.dart';
import '../../repositories/repositories.dart';
import '../../../core/services/memory_budget_coordinator.dart';
import '../../repositories/user_data_repository.dart';
import '../../../core/services/native_download_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/download_storage_utils.dart';

// Use case for downloading content for offline reading
class DownloadContentUseCase
    extends UseCase<DownloadStatus, DownloadContentParams> {
  DownloadContentUseCase(
    this._userDataRepository,
    this._nativeDownloadService, {
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final UserDataRepository _userDataRepository;
  final NativeDownloadService _nativeDownloadService;
  final Logger _logger;

  @override
  Future<DownloadStatus> call(DownloadContentParams params) async {
    try {
      // Validate parameters
      if (params.content.id.isEmpty) {
        throw const ValidationException('Content ID cannot be empty');
      }

      if (params.content.imageUrls.isEmpty) {
        throw const ValidationException('Content has no images to download');
      }

      if (params.priority < 0 || params.priority > 10) {
        throw const ValidationException('Priority must be between 0 and 10');
      }

      // STORAGE VALIDATION: Custom Storage Root is MANDATORY
      // Use provided savePath or fallback to global setting
      // We must resolve this BEFORE starting download
      String effectiveSavePath = params.savePath ?? '';
      if (effectiveSavePath.isEmpty) {
        // Import StorageSettings if not already imported, or fetch from repository if available.
        // Since we don't have StorageSettings imported here, we'll try to rely on UserDataRepository or assume params MUST have it.
        // However, the user asked to check "flutter.custom_storage_root".
        // Let's check UserPreferences via repository.
        final prefs = await _userDataRepository.getUserPreferences();
        if (prefs.customStorageRoot.isNotEmpty) {
          effectiveSavePath = prefs.customStorageRoot;
        }
      }

      if (effectiveSavePath.isEmpty) {
        throw const ValidationException(
            'Custom storage root is required. Please set a download location in settings.');
      }

      // Check if already downloaded (optional)
      if (params.checkExisting) {
        final existingStatus = await _userDataRepository.getDownloadStatus(
          params.content.id,
        );

        if (existingStatus != null && existingStatus.isCompleted) {
          if (params.throwIfExists) {
            throw const ValidationException('Content is already downloaded');
          } else {
            // Return existing download status
            return existingStatus;
          }
        }
      }

      // Create initial download status and save it
      var downloadStatus = DownloadStatus.initial(
        params.content.id,
        params.content.pageCount,
        startPage: params.startPage,
        endPage: params.endPage,
        title: params.content.title,
        sourceId: params.content.sourceId,
        coverUrl: params.content.coverUrl,
      );

      await _userDataRepository.saveDownloadStatus(downloadStatus);

      // Start actual download if not just queuing
      if (params.startImmediately) {
        // Query coordinator for dynamic maxParallel
        final coordinator = MemoryBudgetCoordinator();
        final dynamicParallel = coordinator.isReaderActive
            ? coordinator.maxDownloadParallel
            : params.maxParallelImages;

        downloadStatus = await _performActualDownload(
          params.content,
          downloadStatus,
          params.imageQuality,
          params.timeoutDuration,
          params.startPage,
          params.endPage,
          params.cookies,
          params.headers,
          effectiveSavePath,
          false,
          dynamicParallel,
        );
      }

      return downloadStatus;
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to queue download: ${e.toString()}');
    }
  }

  // make features for delete folder by content id
  Future<void> deleteCall(String contentId, {String? dirPath}) async {
    try {
      // Remove download status from repository
      await _userDataRepository.deleteDownloadStatus(contentId);

      // Remove downloaded files from storage
      await _nativeDownloadService.deleteDownloadedContent(contentId,
          dirPath: dirPath);
    } catch (e) {
      _logger.e('Failed to delete downloaded content: $contentId', error: e);
    }
  }

  // Perform the actual download process using NativeDownloadService
  ///
  // REVAMP: This method is now "Fire-and-Forget".
  // It starts the native download and returns immediately.
  // Progress and completion are handled globally by DownloadManager listening to NativeDownloadService.
  Future<DownloadStatus> _performActualDownload(
    Content content,
    DownloadStatus initialStatus,
    String imageQuality,
    Duration? timeoutDuration,
    int? startPage,
    int? endPage,
    Map<String, String>? cookies,
    Map<String, String>? headers,
    String? savePath,
    bool enableNotifications,
    int maxParallelImages, // 2.2: foreground-aware
  ) async {
    var currentStatus = initialStatus;

    try {
      // Update status to downloading
      currentStatus = currentStatus.copyWith(
        state: DownloadState.downloading,
        startTime: DateTime.now(),
      );
      await _userDataRepository.saveDownloadStatus(currentStatus);

      // Convert thumbnail URLs to full image URLs
      final allImageUrls = content.imageUrls.map((url) => url).toList();

      // 🐛 CRITICAL FIX: Apply range filtering BEFORE sending to native layer
      // Without this, the native downloader receives ALL URLs and downloads everything,
      // ignoring the user's selected range (e.g., pages 1-22 would download all 100+ pages).
      final effectiveStartPage = startPage ?? 1;
      final effectiveEndPage = endPage ?? allImageUrls.length;
      final isRangeDownload = startPage != null || endPage != null;
      final totalAvailablePages = allImageUrls.length;

      // Validate range bounds
      final clampedStart = effectiveStartPage.clamp(1, totalAvailablePages);
      final clampedEnd =
          effectiveEndPage.clamp(clampedStart, totalAvailablePages);

      // Slice URLs: convert 1-based page numbers to 0-based indices
      final rangeImageUrls = allImageUrls.sublist(clampedStart - 1, clampedEnd);

      _logger.i(
        'Download range: pages $clampedStart-$clampedEnd '
        '(${rangeImageUrls.length}/${allImageUrls.length} images)'
        '${isRangeDownload ? ' [RANGE]' : ' [FULL]'}',
      );

      // §8.3 — Validate download readiness via PageResolutionPipeline.
      // This emits diagnostics for empty URLs, parity mismatches, and
      // missing headers *before* the native worker starts.
      final pipelineResult = const PageResolutionPipeline().resolve(
        PageResolutionInput(
          sourceId: content.sourceId,
          contentId: content.id,
          chapterId: null,
          imageUrls: rangeImageUrls,
          globalHeaders: headers ?? const <String, String>{},
        ),
      );
      if (!pipelineResult.pages.isDownloadReady) {
        final blockers = pipelineResult.diagnostics
            .map((d) => '${d.code}: ${d.message}')
            .join('; ');
        _logger.w(
          'Download readiness check failed for ${content.id}: $blockers',
        );
        // Non-fatal: log and proceed. Native layer may still succeed with
        // partial data. Change to early return if strictness is required.
      }

      final String destination = savePath ?? '';

      // 💾 Save metadata JSON as the "Decoder Key" for Safe IDs (CRITICAL)
      // This ensures that even with hashed folder names, we can identify the content.
      // Tags are included for the local recommendation engine (MetadataTagScanner
      // reads them back as scoring seeds; old files without these keys are skipped).
      await DownloadStorageUtils.saveLocalMetadata(
        contentId: content.id,
        sourceId: content.sourceId,
        title: content.title,
        savePath: destination,
        coverUrl: content.coverUrl,
        url: content.url,
        language: content.language,
        totalImages: totalAvailablePages,
        extraData: {
          'tags': [
            for (final tag in content.tags)
              {'name': tag.name, 'type': tag.type},
          ],
          'artists': content.artists,
          'contentLanguage': content.language,
        },
      );

      // Use the cleaned/resolved URLs from the pipeline (strips fallback '|' tokens).
      // Fallback to rangeImageUrls if pipeline returns empty (should not happen for valid sources).
      final resolvedDownloadUrls =
          const PageResolutionPipeline().toDownloadUrls(pipelineResult.pages);
      final finalImageUrls = resolvedDownloadUrls.isNotEmpty
          ? resolvedDownloadUrls
          : rangeImageUrls;

      // Start Native Download (Fire and Forget)
      // Pass only the range-filtered URLs so native layer downloads the correct subset
      await _nativeDownloadService.startDownload(
        contentId: content.id,
        sourceId: content.sourceId,
        imageUrls: finalImageUrls,
        destinationPath: destination,
        cookies: cookies,
        headers: headers, // Source-specific headers (Referer for Hitomi, etc.)
        title: content.title,
        url: content.url,
        coverUrl: content.coverUrl,
        language: content.language,
        startPage: clampedStart,
        endPage: clampedEnd,
        totalPages: totalAvailablePages,
        enableNotifications: enableNotifications,
        backupFolderName: AppStorage.backupFolderName, // ✅ Pass from config
        maxParallelImages: maxParallelImages,
      );

      // We do NOT wait for completion here anymore.
      // The NativeService emits events to the EventChannel, which DownloadManager picks up.
      // DownloadBloc listens to DownloadManager and updates state accordingly.

      _logger.i('Native download started for ${content.id}');

      // Note: If PDF conversion is requested, we need a way to trigger it AFTER download completes.
      // Since we are not waiting here, the PDF conversion logic must be moved
      // to where the 'COMPLETED' event is handled (likely in DownloadBloc._onProgressUpdate).
      // For now, we'll note this limitation or handle it in Bloc.

      return currentStatus;
    } catch (e) {
      _logger.e('Failed to start download for content: ${content.id}',
          error: e);

      // Update status to failed
      currentStatus = currentStatus.copyWith(
        state: DownloadState.failed,
        endTime: DateTime.now(),
        error: e.toString(),
      );
      await _userDataRepository.saveDownloadStatus(currentStatus);

      return currentStatus;
    }
  }
}

// Parameters for DownloadContentUseCase
class DownloadContentParams extends UseCaseParams {
  // 2.2: foreground-aware maxParallelImages
  final int maxParallelImages;

  const DownloadContentParams({
    required this.content,
    this.priority = 0,
    this.checkExisting = true,
    this.throwIfExists = false,
    this.startImmediately = false,
    this.imageQuality = 'high',
    this.timeoutDuration,
    this.startPage,
    this.endPage,
    this.cookies,
    this.headers,
    this.savePath,
    this.enableNotifications = true,
    this.maxParallelImages = 3,
  });

  final Content content;
  final int priority;
  final bool checkExisting;
  final bool throwIfExists;
  final bool startImmediately;
  final String imageQuality;
  final Duration? timeoutDuration;
  final int? startPage; // NEW: Start page for range download (1-based)
  final int? endPage; // NEW: End page for range download (1-based)
  final Map<String, String>? cookies; // NEW: Cookies for authentication
  final Map<String, String>? headers; // NEW: Source-specific HTTP headers
  final String? savePath; // NEW: Custom save path
  final bool enableNotifications; // NEW

  // Check if this is a range download
  bool get isRangeDownload => startPage != null || endPage != null;

  // Get effective start page (1 if not specified)
  int get effectiveStartPage => startPage ?? 1;

  // Get effective end page (total pages if not specified)
  int get effectiveEndPage => endPage ?? content.pageCount;

  @override
  List<Object?> get props => [
        content,
        priority,
        checkExisting,
        throwIfExists,
        startImmediately,
        imageQuality,
        timeoutDuration,
        startPage,
        endPage,
        cookies,
        headers,
        savePath,
        enableNotifications,
        maxParallelImages,
      ];

  DownloadContentParams copyWith({
    Content? content,
    int? priority,
    bool? checkExisting,
    bool? throwIfExists,
    bool? startImmediately,
    String? imageQuality,
    Duration? timeoutDuration,
    int? startPage,
    int? endPage,
    Map<String, String>? cookies,
    Map<String, String>? headers,
    String? savePath,
    bool? enableNotifications,
    int? maxParallelImages,
  }) {
    return DownloadContentParams(
      content: content ?? this.content,
      priority: priority ?? this.priority,
      checkExisting: checkExisting ?? this.checkExisting,
      throwIfExists: throwIfExists ?? this.throwIfExists,
      startImmediately: startImmediately ?? this.startImmediately,
      imageQuality: imageQuality ?? this.imageQuality,
      timeoutDuration: timeoutDuration ?? this.timeoutDuration,
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      cookies: cookies ?? this.cookies,
      headers: headers ?? this.headers,
      savePath: savePath ?? this.savePath,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      maxParallelImages: maxParallelImages ?? this.maxParallelImages,
    );
  }

  // Create params with normal priority
  factory DownloadContentParams.normal(Content content) {
    return DownloadContentParams(content: content, priority: 0);
  }

  // Create params with high priority
  factory DownloadContentParams.highPriority(Content content) {
    return DownloadContentParams(content: content, priority: 5);
  }

  // Create params with maximum priority
  factory DownloadContentParams.urgent(Content content) {
    return DownloadContentParams(content: content, priority: 10);
  }

  // Create params with existing check disabled
  factory DownloadContentParams.force(Content content, {int priority = 0}) {
    return DownloadContentParams(
      content: content,
      priority: priority,
      checkExisting: false,
    );
  }

  // Create params for batch download
  factory DownloadContentParams.batch(Content content, int batchPriority) {
    return DownloadContentParams(
      content: content,
      priority: batchPriority,
      checkExisting: true,
      throwIfExists: false, // Don't throw for batch operations
    );
  }

  // Create params for immediate download with images
  factory DownloadContentParams.immediate(
    Content content, {
    String imageQuality = 'high',
    Duration? timeoutDuration,
    int? startPage,
    int? endPage,
    Map<String, String>? cookies,
    Map<String, String>? headers,
    String? savePath,
    bool enableNotifications = true,
    int maxParallelImages = 3,
  }) {
    return DownloadContentParams(
      content: content,
      priority: 5,
      startImmediately: true,
      imageQuality: imageQuality,
      timeoutDuration: timeoutDuration,
      startPage: startPage,
      endPage: endPage,
      cookies: cookies,
      headers: headers,
      savePath: savePath,
      enableNotifications: enableNotifications,
      maxParallelImages: maxParallelImages,
    );
  }
}
