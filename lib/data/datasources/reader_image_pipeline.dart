import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;

import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/header_inspector_service.dart';
import 'package:nhasixapp/core/services/local_image_preloader.dart';
import 'package:nhasixapp/core/utils/header_inspector.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/utils/reader_image_repair_utils.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/repositories/reader_image_repository.dart';
import 'remote/ehentai_reader_datasource.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';

/// Cancellation handle for reader page resolution without exposing Dio types to widgets.
class ReaderImageCancellation {
  ReaderImageCancellation() : _token = CancelToken();

  final CancelToken _token;

  CancelToken get dioToken => _token;

  bool get isCancelled => _token.isCancelled;

  void cancel([String? reason]) {
    if (!_token.isCancelled) {
      _token.cancel(reason);
    }
  }
}

/// Single, authoritative outcome of routing a reader page image.
enum ImageRouteOutcome {
  /// Render directly using Flutter (ExtendedImage.network / ExtendedImage.file / memory).
  flutterDirect,

  /// Convert tall static AVIF to WebP, then render directly using Flutter (not heavy).
  convertAvifThenDirect,

  /// Animated image (avis AVIF or confirmed animated WebP) rendered via native AnimatedWebPView.
  nativeAnimated,

  /// Empty or unknown/corrupted payload requiring repair/error UI without attempting decode.
  bypassError,
}

/// Pure, side-effect-free routing decider for reader page images.
/// Payload (header bytes) ALWAYS beats URL extension or hints.
class ImageRouteDecider {
  ImageRouteDecider._();

  static ImageRouteOutcome decide({
    Object? header,
    List<int>? headerBytes,
    int? fileSize,
    int? width,
    int? height,
    String? avifBrand,
    bool? isAvif,
    bool? isAvisBrand,
    bool? isConfirmedAnimatedWebP,
    bool? isHeavy,
    String? sourceId,
    ReadingMode? readingMode,
    String? url,
    bool nativeViewAvailable = true,
  }) {
    // Unpack polymorphic header object if provided
    if (header != null) {
      if (header is List<int>) {
        headerBytes ??= header;
      } else if (header is ({String? format, int? width, int? height})) {
        width ??= header.width;
        height ??= header.height;
        if (header.format == 'avif') isAvif ??= true;
        if (header.format == 'webp') isConfirmedAnimatedWebP ??= true;
      } else if (header is ({
        bool isAvif,
        bool isAvisBrand,
        int? width,
        int? height
      })) {
        isAvif ??= header.isAvif;
        isAvisBrand ??= header.isAvisBrand;
        width ??= header.width;
        height ??= header.height;
      }
    }

    // 1. Zero-byte or empty file check
    if (fileSize != null && fileSize <= 0) {
      return ImageRouteOutcome.bypassError;
    }
    if (headerBytes != null &&
        headerBytes.isEmpty &&
        (fileSize == null || fileSize == 0)) {
      return ImageRouteOutcome.bypassError;
    }

    // 2. Payload bytes inspection (payload ALWAYS beats URL)
    if (headerBytes != null && headerBytes.isNotEmpty) {
      final ext = inferImageExtension(bytes: headerBytes);
      if (ext == null) {
        // Unknown format or non-image payload (e.g. HTML error, corrupt bytes)
        return ImageRouteOutcome.bypassError;
      }

      if (ext == 'jpg' || ext == 'png' || ext == 'gif' || ext == 'bmp') {
        // Standard formats decode directly in Flutter regardless of URL extension.
        return ImageRouteOutcome.flutterDirect;
      }

      if (ext == 'webp') {
        final uint8 = headerBytes is Uint8List
            ? headerBytes
            : Uint8List.fromList(headerBytes);
        final isAnimated = (isConfirmedAnimatedWebP == true) ||
            looksLikeAnimatedWebPHeader(uint8);
        if (isAnimated) {
          return nativeViewAvailable
              ? ImageRouteOutcome.nativeAnimated
              : ImageRouteOutcome.flutterDirect;
        }
        return ImageRouteOutcome.flutterDirect;
      }

      if (ext == 'avif') {
        final uint8 = headerBytes is Uint8List
            ? headerBytes
            : Uint8List.fromList(headerBytes);
        final avifInfo = inspectAvifBytesForRouting(uint8);
        final effectiveIsAvis = avifInfo.isAvisBrand ||
            isAvisBrand == true ||
            avifBrand?.toLowerCase() == 'avis';
        final effectiveHeight = height ?? avifInfo.height;

        if (effectiveIsAvis) {
          return nativeViewAvailable
              ? ImageRouteOutcome.nativeAnimated
              : ImageRouteOutcome.flutterDirect;
        }

        if ((effectiveHeight ?? 0) > maxNativeAvifHeight) {
          return ImageRouteOutcome.convertAvifThenDirect;
        }

        return ImageRouteOutcome.flutterDirect;
      }
    }

    // 3. Fallback to structured metadata if headerBytes was not supplied
    if (isAvif == true || avifBrand != null) {
      final effectiveIsAvis =
          isAvisBrand == true || avifBrand?.toLowerCase() == 'avis';
      if (effectiveIsAvis) {
        return nativeViewAvailable
            ? ImageRouteOutcome.nativeAnimated
            : ImageRouteOutcome.flutterDirect;
      }
      if ((height ?? 0) > maxNativeAvifHeight) {
        return ImageRouteOutcome.convertAvifThenDirect;
      }
      return ImageRouteOutcome.flutterDirect;
    }

    if (isConfirmedAnimatedWebP == true) {
      return nativeViewAvailable
          ? ImageRouteOutcome.nativeAnimated
          : ImageRouteOutcome.flutterDirect;
    }

    // 4. Fallback to URL hints (e.g. before bytes are available)
    if (url != null) {
      final normalized = url.toLowerCase().split('?').first;
      if (normalized.endsWith('.avif')) {
        // AVIF routing is deferred to post-download brand check
        return ImageRouteOutcome.flutterDirect;
      }
      if (isHeavy == true &&
          (normalized.endsWith('.webp') || normalized.contains('-wbp'))) {
        return nativeViewAvailable
            ? ImageRouteOutcome.nativeAnimated
            : ImageRouteOutcome.flutterDirect;
      }
    }

    return ImageRouteOutcome.flutterDirect;
  }
}

/// Result of processing a local/cached image file through the pipeline.
class ProcessedImageResult {
  const ProcessedImageResult({
    required this.renderPath,
    this.convertedPath,
    this.wasConverted = false,
    this.isHeavy = false,
    this.isConfirmedAnimatedWebP = false,
    this.nativeImageSize,
    this.imageBytes,
    this.shouldBypassLocalDecode = false,
  });

  final String renderPath;
  final String? convertedPath;
  final bool wasConverted;
  final bool isHeavy;
  final bool isConfirmedAnimatedWebP;
  final Size? nativeImageSize;
  final int? imageBytes;
  final bool shouldBypassLocalDecode;
}

/// Pipeline service coordinating reader image resolution, network scraping,
/// in-memory caching, AVIF→WebP conversion, format conflict deletion, and header inspection.
class ReaderImagePipeline {
  ReaderImagePipeline({
    ReaderImageRepository? repository,
    EhentaiReaderDataSource? ehentaiDataSource,
    HeaderInspectorService? headerInspector,
    OfflineContentManager? offlineContentManager,
    Logger? logger,
  })  : _repository = repository,
        _ehentaiDataSource = ehentaiDataSource ?? EhentaiReaderDataSource(),
        _headerInspector = headerInspector,
        _offlineContentManager = offlineContentManager,
        _logger = logger ??
            (getIt.isRegistered<Logger>() ? getIt<Logger>() : Logger());

  static ReaderImagePipeline? _instance;
  static ReaderImagePipeline get instance =>
      _instance ??= ReaderImagePipeline();
  @visibleForTesting
  static set instance(ReaderImagePipeline? val) => _instance = val;

  final ReaderImageRepository? _repository;
  final EhentaiReaderDataSource _ehentaiDataSource;
  final HeaderInspectorService? _headerInspector;
  final OfflineContentManager? _offlineContentManager;
  final Logger _logger;

  ReaderImageRepository? get _effectiveRepository {
    if (_repository != null) return _repository;
    if (getIt.isRegistered<ReaderImageRepository>()) {
      return getIt<ReaderImageRepository>();
    }
    return null;
  }

  HeaderInspectorService? get _effectiveHeaderInspector {
    if (_headerInspector != null) return _headerInspector;
    if (getIt.isRegistered<HeaderInspectorService>()) {
      return getIt<HeaderInspectorService>();
    }
    return null;
  }

  OfflineContentManager? get _effectiveOfflineContentManager {
    if (_offlineContentManager != null) return _offlineContentManager;
    if (getIt.isRegistered<OfflineContentManager>()) {
      return getIt<OfflineContentManager>();
    }
    return null;
  }

  ReaderImageCancellation createCancellation() => ReaderImageCancellation();

  // ─────────────────────────────────────────────────────────────────────────
  // E-Hentai Scraping & Token Resolution
  // ─────────────────────────────────────────────────────────────────────────

  bool shouldResolveEhentai(String url, {String? sourceId}) =>
      _ehentaiDataSource.shouldResolve(url, sourceId: sourceId);

  Future<String?> resolveEhentaiImageUrl(
    String readerPageUrl, {
    Map<String, String>? headers,
    Map<String, dynamic>? rawConfig,
  }) =>
      _ehentaiDataSource.resolveImageUrl(
        readerPageUrl,
        headers: headers,
        rawConfig: rawConfig,
      );

  void invalidateEhentaiResolvedImageUrl(String readerPageUrl) =>
      _ehentaiDataSource.invalidate(readerPageUrl);

  // ─────────────────────────────────────────────────────────────────────────
  // MangaFire De-scrambling Binary Resolution
  // ─────────────────────────────────────────────────────────────────────────

  bool shouldResolveMangaFireImageBytes(String url, {String? sourceId}) {
    return sourceId == 'mangafire' && url.contains('#scrambled_');
  }

  Future<Uint8List?> resolveMangaFireImageBytes(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      return await KuronNative.instance.downloadBinary(
        url: url,
        headers: headers,
      );
    } catch (e) {
      _logger.w('[ReaderPipeline] Failed to resolve MangaFire bytes: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Download-first Page Image Resolution
  // ─────────────────────────────────────────────────────────────────────────

  Future<PageImageResult?> resolvePageToFile({
    required String url,
    required String contentId,
    required int pageNumber,
    String? sourceId,
    Map<String, String>? headers,
    ReaderImageCancellation? cancellation,
  }) async {
    final repo = _effectiveRepository;
    if (repo == null) return null;

    return repo.resolvePage(
      url: url,
      contentId: contentId,
      pageNumber: pageNumber,
      sourceId: sourceId,
      headers: headers,
      cancelToken: cancellation?.dioToken,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AVIF & Animated WebP Inspection & Conversion
  // ─────────────────────────────────────────────────────────────────────────

  static ImageRouteOutcome decide({
    Object? header,
    List<int>? headerBytes,
    int? fileSize,
    int? width,
    int? height,
    String? avifBrand,
    bool? isAvif,
    bool? isAvisBrand,
    bool? isConfirmedAnimatedWebP,
    bool? isHeavy,
    String? sourceId,
    ReadingMode? readingMode,
    String? url,
    bool nativeViewAvailable = true,
  }) =>
      ImageRouteDecider.decide(
        header: header,
        headerBytes: headerBytes,
        fileSize: fileSize,
        width: width,
        height: height,
        avifBrand: avifBrand,
        isAvif: isAvif,
        isAvisBrand: isAvisBrand,
        isConfirmedAnimatedWebP: isConfirmedAnimatedWebP,
        isHeavy: isHeavy,
        sourceId: sourceId,
        readingMode: readingMode,
        url: url,
        nativeViewAvailable: nativeViewAvailable,
      );

  static bool shouldConvertAvifToWebP(
    ({bool isAvif, bool isAvisBrand, int? width, int? height}) avifInfo,
  ) {
    if (!avifInfo.isAvif) {
      return false;
    }
    final outcome = decide(
      isAvif: avifInfo.isAvif,
      isAvisBrand: avifInfo.isAvisBrand,
      width: avifInfo.width,
      height: avifInfo.height,
    );
    return outcome == ImageRouteOutcome.convertAvifThenDirect ||
        outcome == ImageRouteOutcome.nativeAnimated;
  }

  static bool shouldConvertTallAvifFile(
    File file, {
    required bool nativeViewAvailable,
  }) {
    if (!nativeViewAvailable) {
      return false;
    }
    try {
      if (!file.existsSync()) {
        return false;
      }
      final avifInfo = inspectAvifHeaderForRouting(file);
      return avifInfo.isAvif && (avifInfo.height ?? 0) > maxNativeAvifHeight;
    } catch (_) {
      return false;
    }
  }

  static bool shouldMarkConvertedAvifHeavy({
    required bool isAvif,
    required bool isAvisBrand,
    required int? height,
  }) {
    if (!isAvif) {
      return false;
    }
    return decide(
          isAvif: isAvif,
          isAvisBrand: isAvisBrand,
          height: height,
        ) ==
        ImageRouteOutcome.nativeAnimated;
  }

  Future<bool> hasInvalidImagePayload(String localPath) async {
    RandomAccessFile? raf;
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return true;
      }
      final length = await file.length();
      if (length <= 0) {
        return true;
      }
      final sampleLength = length < 64 ? length : 64;
      raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(sampleLength);
      return inferImageExtension(bytes: bytes) == null;
    } catch (e) {
      _logger.w(
          '[ReaderPipeline] Failed to validate local payload $localPath: $e');
      return true;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  Future<void> deleteLocalPageFormatConflicts({
    required String currentImagePath,
    required String convertedPath,
  }) async {
    final directory = Directory(path.dirname(currentImagePath));
    if (!await directory.exists()) {
      return;
    }

    final targetBaseName = path.basenameWithoutExtension(currentImagePath);
    final normalizedConvertedPath = path.normalize(convertedPath);
    final tempPath = '$convertedPath.repairing';
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }

      final normalizedCandidate = path.normalize(entity.path);
      if (normalizedCandidate == normalizedConvertedPath ||
          normalizedCandidate == path.normalize(tempPath)) {
        continue;
      }

      final extension = path.extension(entity.path).toLowerCase();
      if (!kReaderRepairSupportedImageExtensions.contains(extension)) {
        continue;
      }

      if (path.basenameWithoutExtension(entity.path) != targetBaseName) {
        continue;
      }

      try {
        await entity.delete();
      } catch (e) {
        _logger.w(
          '[ReaderPipeline] Failed deleting stale local page ${entity.path}: $e',
        );
      }
    }
  }

  Future<void> syncOfflineMetadataForConvertedLocalPage({
    required String contentId,
    required int pageNumber,
    required String originalLocalPath,
    required String convertedLocalPath,
  }) async {
    try {
      final manager = _effectiveOfflineContentManager;
      if (manager != null) {
        await manager.rewriteMetadataForConvertedLocalPage(
          contentId: contentId,
          pageNumber: pageNumber,
          originalLocalPath: originalLocalPath,
          convertedLocalPath: convertedLocalPath,
        );
      }
    } catch (e) {
      _logger.w(
        '[ReaderPipeline] Failed updating metadata for local conversion '
        'content=$contentId page=$pageNumber: $e',
      );
    }
  }

  Future<FileHeaderResult> inspectHeader(String path) {
    final inspector = _effectiveHeaderInspector;
    if (inspector != null) {
      return inspector.inspect(path);
    }
    return compute(inspectFileHeader, path);
  }

  Future<ProcessedImageResult> processImageFile({
    required String filePath,
    required String contentId,
    required int pageNumber,
    bool checkInvalidPayload = false,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ProcessedImageResult(renderPath: filePath);
      }

      final fileSize = await file.length();
      if (fileSize <= 0) {
        return ProcessedImageResult(
          renderPath: filePath,
          shouldBypassLocalDecode: true,
        );
      }

      if (checkInvalidPayload && await hasInvalidImagePayload(filePath)) {
        return ProcessedImageResult(
          renderPath: filePath,
          shouldBypassLocalDecode: true,
        );
      }

      // Read sample header bytes for single decider
      RandomAccessFile? raf;
      Uint8List? sampleBytes;
      try {
        final sampleLength = fileSize < 4096 ? fileSize : 4096;
        raf = await file.open(mode: FileMode.read);
        sampleBytes = await raf.read(sampleLength);
      } finally {
        try {
          await raf?.close();
        } catch (_) {}
      }

      final decision = decide(
        headerBytes: sampleBytes,
        fileSize: fileSize,
      );

      if (decision == ImageRouteOutcome.bypassError) {
        return ProcessedImageResult(
          renderPath: filePath,
          shouldBypassLocalDecode: true,
        );
      }

      // Background / service header inspection
      inspectHeader(filePath);
      final avifInfo = inspectAvifBytesForRouting(sampleBytes);
      final shouldConvert =
          decision == ImageRouteOutcome.convertAvifThenDirect ||
              (decision == ImageRouteOutcome.nativeAnimated && avifInfo.isAvif);
      if (shouldConvert) {
        _logger.i(
          '[ReaderPipeline] Animated/tall AVIF detected. Converting to WebP '
          'page=$pageNumber height=${avifInfo.height}',
        );
        final outputPath = buildReplacementImagePath(
          currentImagePath: filePath,
          extension: 'webp',
        );
        final convertedPath = await KuronNative.instance.convertAvifToWebP(
          inputPath: filePath,
          outputPath: outputPath,
        );

        if (convertedPath != null) {
          final convertedFile = File(convertedPath);
          if (await convertedFile.exists() &&
              await convertedFile.length() > 0) {
            await deleteLocalPageFormatConflicts(
              currentImagePath: filePath,
              convertedPath: convertedPath,
            );
            await syncOfflineMetadataForConvertedLocalPage(
              contentId: contentId,
              pageNumber: pageNumber,
              originalLocalPath: filePath,
              convertedLocalPath: convertedPath,
            );

            final markHeavy = decision == ImageRouteOutcome.nativeAnimated;

            final webpHeader = inspectFileHeader(convertedPath);
            final nativeSize = (webpHeader.width != null &&
                    webpHeader.height != null)
                ? Size(
                    webpHeader.width!.toDouble(), webpHeader.height!.toDouble())
                : (avifInfo.width != null && avifInfo.height != null)
                    ? Size(
                        avifInfo.width!.toDouble(), avifInfo.height!.toDouble())
                    : null;

            final convertedLength = await convertedFile.length();
            _logger.i(
              '[ReaderPipeline] AVIF converted to WebP page=$pageNumber '
              'src=${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB '
              'out=${(convertedLength / 1024 / 1024).toStringAsFixed(1)} MB',
            );

            return ProcessedImageResult(
              renderPath: convertedPath,
              convertedPath: convertedPath,
              wasConverted: true,
              isHeavy: markHeavy,
              isConfirmedAnimatedWebP: markHeavy,
              nativeImageSize: nativeSize,
              imageBytes: convertedLength,
            );
          }
        }

        _logger.w('[ReaderPipeline] AVIF conversion failed page=$pageNumber');
        return ProcessedImageResult(renderPath: filePath);
      }

      // Check for animated WebP
      if (decision == ImageRouteOutcome.nativeAnimated) {
        final header = inspectFileHeader(filePath);
        final nativeSize = (header.width != null && header.height != null)
            ? Size(header.width!.toDouble(), header.height!.toDouble())
            : null;
        return ProcessedImageResult(
          renderPath: filePath,
          isHeavy: true,
          isConfirmedAnimatedWebP: true,
          nativeImageSize: nativeSize,
          imageBytes: fileSize,
        );
      }

      return ProcessedImageResult(
        renderPath: filePath,
        imageBytes: fileSize,
      );
    } catch (e) {
      _logger.w('[ReaderPipeline] Error processing $filePath: $e');
      return ProcessedImageResult(renderPath: filePath);
    }
  }

  Future<ProcessedImageResult?> preCheckDiskCache({
    required String imageUrl,
    required String contentId,
    required int pageNumber,
  }) async {
    try {
      final legacyFile = await DefaultCacheManager().getFileFromCache(imageUrl);
      if (legacyFile != null && await legacyFile.file.exists()) {
        return await processImageFile(
          filePath: legacyFile.file.path,
          contentId: contentId,
          pageNumber: pageNumber,
        );
      }

      final localPath =
          await LocalImagePreloader.getLocalImagePath(contentId, pageNumber);
      if (localPath != null) {
        final f = File(localPath);
        if (await f.exists() && await f.length() > 0) {
          return await processImageFile(
            filePath: localPath,
            contentId: contentId,
            pageNumber: pageNumber,
          );
        }
      }
    } catch (e) {
      _logger.w('[ReaderPipeline] Pre-check disk cache error: $e');
    }
    return null;
  }
}
