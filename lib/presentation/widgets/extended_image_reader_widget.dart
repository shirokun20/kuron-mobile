import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:logger/logger.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/utils/native_theme_helper.dart';
import '../../data/datasources/reader_image_pipeline.dart';
import '../../core/utils/reader_image_repair_utils.dart';
import '../../core/utils/header_inspector.dart';
import '../../../domain/entities/page_image_result.dart';
import '../../../domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';
class ExtendedImageReaderWidget extends StatefulWidget {
  const ExtendedImageReaderWidget({
    super.key,
    required this.imageUrl,
    required this.contentId,
    required this.pageNumber,
    required this.readingMode,
    this.sourceId,
    this.sourceRawConfig,
    this.httpHeaders,
    this.enableZoom = true,
    this.onLoadError,
    this.onImageLoaded,
    this.visiblePageNotifier,
    this.onHeavyImageDetected,
    this.onRepairBrokenImage,
    this.onOpenSourcePageForRepair,
    this.onDoubleTapGesture,
    this.grayscale = false,
    this.pipeline,
    this.isDistant = false,
  });
  final bool isDistant;

  final String imageUrl;
  final String contentId;
  final int pageNumber;
  final ReadingMode readingMode;
  final String? sourceId;
  final Map<String, dynamic>? sourceRawConfig;
  final Map<String, String>? httpHeaders;
  final bool enableZoom;
  final VoidCallback? onLoadError;
  final Future<bool> Function()? onRepairBrokenImage;
  final Future<bool> Function()? onOpenSourcePageForRepair;

  final Function(int pageNumber, Size imageSize)? onImageLoaded;

  // If set, double-tap calls this instead of the built-in zoom animation.
  final VoidCallback? onDoubleTapGesture;

  // Called once (per content ID) when this page is identified as a heavy
  // animated WebP (≥ 2 MB) while in continuous-scroll mode.
  final VoidCallback? onHeavyImageDetected;

  // Notifier that emits the currently visible page number.
  // Forwarded to [AnimatedWebPView] to auto-pause off-screen animations.
  final ValueNotifier<int>? visiblePageNotifier;

  // Whether the image should be forced to grayscale (Note theme).
  final bool grayscale;
  // Optional pipeline service. Falls back to ReaderImagePipeline.instance.
  final ReaderImagePipeline? pipeline;


  @override
  State<ExtendedImageReaderWidget> createState() =>
      _ExtendedImageReaderWidgetState();

  @visibleForTesting
  static void addHeavyUrlForTesting(String url) =>
      _ExtendedImageReaderWidgetState._boundedSetAdd(
          _ExtendedImageReaderWidgetState._heavyImageUrls,
          url,
          _ExtendedImageReaderWidgetState._maxHeavyImageUrls);

  @visibleForTesting
  static bool isHeavyUrlForTesting(String url) =>
      _ExtendedImageReaderWidgetState._heavyImageUrls.contains(url);

  @visibleForTesting
  static int get maxHeavyImageUrls =>
      _ExtendedImageReaderWidgetState._maxHeavyImageUrls;

  static Future<void> clearNativeAnimatedCache() async {
    _ExtendedImageReaderWidgetState._heavyImageUrls.clear();
    _ExtendedImageReaderWidgetState._confirmedAnimatedWebPUrls.clear();
    _ExtendedImageReaderWidgetState._nonNativeAnimatedUrls.clear();
    _ExtendedImageReaderWidgetState._cachedFilePathByUrl.clear();
    _ExtendedImageReaderWidgetState._knownBrokenLocalAvifPaths.clear();
    await clearDiskCachedImages();
    try {
      await KuronNative.instance.clearAnimatedWebPCache();
    } catch (_) {}
  }

  @visibleForTesting
  static void clearHeavyUrlsForTesting() =>
      _ExtendedImageReaderWidgetState._heavyImageUrls.clear();

  @visibleForTesting
  static int get heavyImageThresholdBytesForTesting =>
      _ExtendedImageReaderWidgetState._heavyImageThresholdBytes;

  @visibleForTesting
  static int get ultraHeavyAnimatedImageThresholdBytesForTesting =>
      _ExtendedImageReaderWidgetState._ultraHeavyAnimatedImageThresholdBytes;

  @visibleForTesting
  static bool isLikelyAnimatedWebPForTesting({
    required String url,
    required bool isHeavy,
  }) {
    if (!isHeavy) return false;
    return _looksLikeNativeAnimatedCapableUrl(url);
  }

  @visibleForTesting
  static bool shouldUseNativeAnimatedViewForTesting({
    required String url,
    required bool isHeavy,
    required bool nativeViewAvailable,
    bool confirmedAnimatedWebP = false,
  }) {
    if (!nativeViewAvailable || !isHeavy) return false;
    return confirmedAnimatedWebP || _looksLikeNativeAnimatedCapableUrl(url);
  }

  @visibleForTesting
  static bool shouldNotifyHeavyImageDetectedForTesting({
    required ReadingMode readingMode,
    required bool confirmedAnimatedWebP,
    required bool hasCallback,
    required bool alreadyNotified,
  }) {
    if (!hasCallback) return false;
    if (readingMode != ReadingMode.continuousScroll) return false;
    if (!confirmedAnimatedWebP) return false;
    if (alreadyNotified) return false;
    return true;
  }

  @visibleForTesting
  static bool shouldAutoPlayAnimatedViewForTesting({
    required int pageNumber,
    int? visiblePageNumber,
  }) {
    return visiblePageNumber == null || visiblePageNumber == pageNumber;
  }

  @visibleForTesting
  static bool shouldKeepAliveForTesting({
    required ReadingMode readingMode,
    required bool isHeavy,
  }) {
    return readingMode != ReadingMode.continuousScroll || isHeavy;
  }

  @visibleForTesting
  static bool shouldClearMemoryCacheOnDisposeForTesting({
    required ReadingMode readingMode,
    required bool isHeavy,
    required bool isHeavyReaderSource,
  }) {
    return readingMode == ReadingMode.continuousScroll &&
        !(isHeavy || isHeavyReaderSource);
  }

  @visibleForTesting
  static int resolveNativeAnimatedDecodeWidthForTesting({
    required double logicalWidth,
    required double devicePixelRatio,
    int? imageBytes,
  }) {
    final viewportPx = logicalWidth * devicePixelRatio;
    final isUltraHeavy = imageBytes != null &&
        imageBytes >=
            _ExtendedImageReaderWidgetState
                ._ultraHeavyAnimatedImageThresholdBytes;
    final factor = isUltraHeavy ? 0.58 : 0.78;
    // Throttle caps: default animated 720px, ultra-heavy (>=10MB) 540px.
    // Never exceeds the display viewport (see maxPx below).
    final capPx = isUltraHeavy ? 540.0 : 720.0;
    final minPx = viewportPx < 360.0 ? viewportPx : 360.0;
    final maxPx = viewportPx < capPx ? viewportPx : capPx;
    return (viewportPx * factor).clamp(minPx, maxPx).round();
  }

  static bool _looksLikeNativeAnimatedCapableUrl(String url) {
    final path = url.toLowerCase().split('?').first;
    return path.endsWith('.webp') || path.contains('-wbp');
  }

  /// AVIF tall enough that the native view must render it. Height — not brand —
  /// decides: a static 720×14870 AVIF served as `.jpg` is common, and Flutter
  /// cannot decode it either, so it needs the same AVIF→WebP conversion.
  @visibleForTesting
  static bool shouldConvertTallAvifFileForTesting(
    File file, {
    required bool nativeViewAvailable,
  }) =>
      ReaderImagePipeline.shouldConvertTallAvifFile(
        file,
        nativeViewAvailable: nativeViewAvailable,
      );

  /// Whether a just-converted AVIF page counts as heavy (native view +
  /// heavy-image notify). Height only decides *conversion*: a tall static
  /// AVIF (720×14870 served as `.jpg`) must be converted because Flutter
  /// cannot decode it, but the produced WebP renders fine as a plain file —
  /// marking it heavy would flip the reader out of webtoon mode.
  @visibleForTesting
  static bool shouldMarkConvertedAvifHeavyForTesting({
    required bool isAvif,
    required bool isAvisBrand,
    required int? height,
  }) {
    if (!isAvif) {
      return false;
    }
    return isAvisBrand;
  }

  /// Path the builders must render: the converted WebP when conversion
  /// happened, otherwise the resolved/original page path.
  @visibleForTesting
  static String resolvedConvertedImagePathForTesting({
    required String? convertedPath,
    required String resolvedPath,
  }) =>
      convertedPath ?? resolvedPath;

  /// Whether the cached file for [url] must be inspected on disk before
  /// Flutter decodes it. Brand (avis vs avif/mif1) and height (> 4096) live in
  /// the bytes, so `.jpg`/`.jpeg`/`.png` URLs are inspected too — mislabeled
  /// AVIF payloads must be caught before the first decode attempt.
  @visibleForTesting
  static bool shouldInspectForNativeAnimatedForTesting({
    required String url,
    required String sourceId,
  }) {
    final path = url.toLowerCase().split('?').first;
    return sourceId.toLowerCase() == 'ehentai' ||
        _looksLikeNativeAnimatedCapableUrl(url) ||
        path.endsWith('.avif') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png');
  }

  @visibleForTesting
  static bool isAnimatedWebPHeaderForTesting(Uint8List bytes) =>
      looksLikeAnimatedWebPHeader(bytes);

  @visibleForTesting
  static bool isSupportedImageHeaderForTesting(Uint8List bytes) =>
      inferImageExtension(bytes: bytes) != null;
}

class _ExtendedImageReaderWidgetState extends State<ExtendedImageReaderWidget>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  ReaderImagePipeline get _pipeline => widget.pipeline ?? ReaderImagePipeline.instance;
  static final Set<String> _knownBrokenLocalAvifPaths = <String>{};
  static final Set<String> _heavyImageUrls = <String>{};
  static final Set<String> _notifiedHeavyContentIds = <String>{};
  static final Map<String, String> _cachedFilePathByUrl = <String, String>{};
  static final Set<String> _confirmedAnimatedWebPUrls = <String>{};
  static final Set<String> _nonNativeAnimatedUrls = <String>{};
  static const int _heavyImageThresholdBytes = 2 * 1024 * 1024; // 2 MB

  static const int _maxHeavyImageUrls = 500;
  static const int _maxCachedFilePathByUrl = 200;
  static const int _maxConfirmedAnimatedWebPUrls = 300;
  static const int _maxNotifiedHeavyContentIds = 100;

  static void _boundedSetAdd(Set<String> set, String item, int maxSize) {
    set.add(item);
    if (set.length > maxSize) {
      set.remove(set.first);
    }
  }

  static void _boundedMapPut(
      Map<String, String> map, String key, String value, int maxSize) {
    map[key] = value;
    if (map.length > maxSize) {
      map.remove(map.keys.first);
    }
  }


  // Files ≥ 10 MB get a more aggressive native target width because the
  // offline reader otherwise pays twice: thumbnail prep + animated playback.
  static const int _ultraHeavyAnimatedImageThresholdBytes =
      10 * 1024 * 1024; // 10 MB

  CancellationToken? _cancelToken;
  ReaderImageCancellation? _resolveCancellation;
  int? _nativeImageByteSize;

  late AnimationController _zoomController;
  late Animation<double> _zoomAnimation;
  late AnimationController _pinchHintController;
  final GlobalKey<ExtendedImageGestureState> _gestureKey = GlobalKey();
  Future<String?>? _ehentaiResolvedImageFuture;
  Future<Uint8List?>? _mangaFireResolvedImageFuture;
  Future<PageImageResult?>? _pageResolveFuture;

  // Path already scheduled through _schedulePostProcessResolvedFile.
  // Prevents queueing a post-frame callback on every rebuild for one file.
  String? _postProcessScheduledPath;

  bool _isHeavyImage = false;

  // Whether this image was positively identified as animated WebP bytes.
  bool _isConfirmedAnimatedWebP = false;

  String? _cachedFilePath;
  // Converted WebP for a tall *static* AVIF page. Such a page is not heavy
  // (Flutter decodes the WebP fine), but the original `.jpg`/`.avif` bytes are
  // deleted after conversion, so the builders must render this path instead.
  String? _staticConvertedFilePath;

  // Image dimensions parsed from the file header (e.g., `ispe` box for AVIF).
  Size? _nativeImageSize;

  int _ehentaiResolveRetries = 0;
  static const int _maxEhentaiResolveRetries = 2;
  bool _isRepairingBrokenImage = false;
  bool _isOpeningSourcePage = false;
  bool _shouldBypassLocalDecode = false;

  // Whether the one-shot AVIF-decode-failure async re-check has already run.
  // Prevents an infinite loop: on the second decode failure for the same
  // widget instance we give up and show the error widget instead of retrying.
  bool _avifDecodeRetried = false;

  // Prevents ExtendedImage from attempting to decode an avis sequence before
  // native view routing, avoiding "getPixels failed with error invalid input".
  bool _awaitingNativeCheck = false;

  // Size? _loadedImageSize;

  // Keep widget state alive for heavy/native images, but only for visible ±1
  // in continuous scroll so long chapter scrolling stays lightweight and GPU
  // texture count is bounded.
  @override
  bool get wantKeepAlive {
    if (widget.readingMode != ReadingMode.continuousScroll) {
      return !widget.isDistant;
    }
    if (!_isHeavyImage) return false;
    final visible = widget.visiblePageNotifier?.value;
    if (visible == null) return true; // before first layout, keep
    return (visible - widget.pageNumber).abs() <= 1;
  }

  bool _isLocalFilePath(String value) {
    return value.startsWith('/') ||
        value.startsWith('\\') ||
        value.startsWith('file://') ||
        (!value.startsWith('http://') && !value.startsWith('https://'));
  }

  String _normalizeLocalPath(String value) {
    if (value.startsWith('file://')) {
      return value.replaceFirst('file://', '');
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _cancelToken = CancellationToken();
    _resolveCancellation = _pipeline.createCancellation();
    _zoomController = AnimationController(
      duration: DesignTokens.durationPageTurn,
      vsync: this,
    );
    _zoomAnimation = _zoomController.drive(Tween<double>(begin: 1.0, end: 1.0));

    _pinchHintController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    if (widget.onDoubleTapGesture != null && widget.enableZoom) {
      // Delay so the image has time to load first
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _pinchHintController.forward();
      });
    }

    _isHeavyImage = _heavyImageUrls.contains(widget.imageUrl);
    _isConfirmedAnimatedWebP =
        _confirmedAnimatedWebPUrls.contains(widget.imageUrl);
    _cachedFilePath = _cachedFilePathByUrl[widget.imageUrl];

    if (_isLocalFilePath(widget.imageUrl)) {
      final localPath = _normalizeLocalPath(widget.imageUrl);
      _seedConvertedPathFromCache(localPath);
      _cachedFilePath = _staticConvertedFilePath ?? localPath;
      _boundedMapPut(_cachedFilePathByUrl, widget.imageUrl, _cachedFilePath!,
          _maxCachedFilePathByUrl);
      final isKnownBrokenAvif = localPath.toLowerCase().endsWith('.avif') &&
          _knownBrokenLocalAvifPaths.contains(localPath);
      _shouldBypassLocalDecode = isKnownBrokenAvif;
      if (!_shouldBypassLocalDecode) {
        _awaitingNativeCheck = _shouldConvertTallAvifLocalFile(localPath);
        _preCheckLocalFileForHeavy(localPath);
      }
    }

    // Pre-check: for .webp URLs not yet identified as heavy, query the disk
    // cache BEFORE ExtendedImage decodes — skip Flutter's expensive
    // raster-thread decode and go straight to native view.
    if (!_isHeavyImage &&
        AnimatedWebPView.isAvailable &&
        !_isLocalFilePath(widget.imageUrl) &&
        _shouldInspectCachedFileForAnimatedWebP(widget.imageUrl)) {
      // For AVIF URLs: block ExtendedImage from rendering until we know
      // whether the cached file is animated (→ native) or static (→ Flutter).
      // This prevents Android's ImageDecoder from attempting avis sequences.
      if (widget.imageUrl.toLowerCase().split('?').first.endsWith('.avif')) {
        _awaitingNativeCheck = true;
      }
      _preCheckDiskCacheForHeavy();
    }

    _prepareEhentaiResolveFuture();
    _prepareMangaFireImageFuture();
  }

  // Async disk-cache check: if a cached .webp file ≥ threshold exists,
  // seed the static maps and rebuild to route straight to native.
  void _preCheckDiskCacheForHeavy() {
    _pipeline
        .preCheckDiskCache(
      imageUrl: widget.imageUrl,
      contentId: widget.contentId,
      pageNumber: widget.pageNumber,
    )
        .then((result) {
      if (!mounted) return;
      if (result != null) {
        _applyProcessedResult(result);
      }
    }).catchError((Object e) {
      _logger.w('[NativeWebP] Pre-check error: $e');
    }).whenComplete(() {
      if (mounted && _awaitingNativeCheck) {
        setState(() => _awaitingNativeCheck = false);
      }
    });
  }

  bool _shouldConvertTallAvifLocalFile(String localPath) {
    return ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
      File(localPath),
      nativeViewAvailable: AnimatedWebPView.isAvailable,
    );
  }

  void _seedConvertedPathFromCache(String localPath) {
    if (_staticConvertedFilePath != null) return;
    final cached = _cachedFilePathByUrl[widget.imageUrl];
    if (cached != null && cached != localPath) {
      _staticConvertedFilePath = cached;
      _cachedFilePath = cached;
    }
  }

  void _applyProcessedResult(ProcessedImageResult result) {
    if (result.wasConverted && result.convertedPath != null) {
      if (result.isHeavy) {
        _markHeavyNativeAnimatedImage(
          cacheKey: widget.imageUrl,
          cachedFilePath: result.convertedPath!,
          confirmedAnimatedWebP: true,
        );
        _isHeavyImage = true;
        _isConfirmedAnimatedWebP = true;
        _cachedFilePath = result.convertedPath;
      } else {
        _staticConvertedFilePath = result.convertedPath;
        _boundedMapPut(_cachedFilePathByUrl, widget.imageUrl,
            result.convertedPath!, _maxCachedFilePathByUrl);
      }
    } else if (result.isHeavy) {
      _markHeavyNativeAnimatedImage(
        cacheKey: widget.imageUrl,
        cachedFilePath: result.renderPath,
        confirmedAnimatedWebP: true,
      );
      _isHeavyImage = true;
      _isConfirmedAnimatedWebP = true;
      _cachedFilePath = result.renderPath;
    }
    if (result.nativeImageSize != null) {
      _nativeImageSize = result.nativeImageSize;
    }
    if (result.imageBytes != null) {
      _nativeImageByteSize = result.imageBytes;
    }
    if (result.shouldBypassLocalDecode) {
      _shouldBypassLocalDecode = true;
    }
    _awaitingNativeCheck = false;

    if (!mounted) return;
    setState(() {});
    if (result.isHeavy) {
      updateKeepAlive();
      _maybeNotifyHeavyImageDetected();
    }
    if (result.nativeImageSize != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onImageLoaded
              ?.call(widget.pageNumber, result.nativeImageSize!);
        }
      });
    }
  }

  Future<void> _preCheckLocalFileForHeavy(String localPath) async {
    if (!AnimatedWebPView.isAvailable) {
      return;
    }

    try {
      final result = await _pipeline.processImageFile(
        filePath: localPath,
        contentId: widget.contentId,
        pageNumber: widget.pageNumber,
        checkInvalidPayload: true,
      );
      _applyProcessedResult(result);
    } catch (e) {
      _logger.w('[NativeWebP] Local pre-check error: $e');
    } finally {
      if (mounted && _awaitingNativeCheck) {
        setState(() => _awaitingNativeCheck = false);
      } else if (_awaitingNativeCheck) {
        _awaitingNativeCheck = false;
      }
    }
  }

  // Fire [widget.onHeavyImageDetected] at most once per content ID.
  void _maybeNotifyHeavyImageDetected() {
    if (!ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
      readingMode: widget.readingMode,
      confirmedAnimatedWebP: _isConfirmedAnimatedWebP,
      hasCallback: widget.onHeavyImageDetected != null,
      alreadyNotified: _notifiedHeavyContentIds.contains(widget.contentId),
    )) {
      return;
    }
    _boundedSetAdd(_notifiedHeavyContentIds, widget.contentId,
        _maxNotifiedHeavyContentIds);
    // postFrameCallback so we never call this during a build/layout phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeavyImageDetected?.call();
    });
  }

  // Pre-seed the static set WITHOUT setState so an in-flight ExtendedImage
  // download is never interrupted mid-way.
  void _preSeedHeavyImageUrl() {
    _boundedSetAdd(_heavyImageUrls, widget.imageUrl, _maxHeavyImageUrls);
  }

  bool _isAvifSource(String source) {
    return source.toLowerCase().split('?').first.endsWith('.avif');
  }

  Future<void> _openFailedAvifExternally(String source) async {
    try {
      if (_isLocalFilePath(source)) {
        await KuronNative.instance.openAvif(
          filePath: _normalizeLocalPath(source),
        );
        return;
      }

      await KuronNative.instance.openWebView(
        url: source,
        backgroundColor: NativeThemeHelper.backgroundColorHex,
        textColor: NativeThemeHelper.textColorHex,
      );
    } catch (e) {
      _logger.w('[AVIF] Failed to open external fallback: $e');
    }
  }

  bool _isLikelyAnimatedUrl(String url) {
    if (_isConfirmedAnimatedWebP) {
      return true;
    }
    return ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
      url: url,
      isHeavy: _isHeavyImage,
    );
  }

  bool _tryNativeAnimatedFallback(String failedUrl) {
    if (!AnimatedWebPView.isAvailable) {
      return false;
    }

    if (!_isLocalFilePath(failedUrl) &&
        failedUrl.toLowerCase().split('?').first.endsWith('.avif')) {
      if (_avifDecodeRetried) {
        return false;
      }
      _avifDecodeRetried = true;
      _logger.w(
        '[NativeWebP] AVIF decode failed, re-inspecting cache: '
        'page=${widget.pageNumber}',
      );
      clearMemoryImageCache(failedUrl);
      _awaitingNativeCheck = true;
      _preCheckDiskCacheForHeavy();
      return true;
    }

    if (!ExtendedImageReaderWidget._looksLikeNativeAnimatedCapableUrl(
      failedUrl,
    )) {
      return false;
    }

    _logger.w(
      '[NativeWebP] Fallback to native animated view after decode failure: '
      'page=${widget.pageNumber}, url=$failedUrl',
    );

    if (!_isLocalFilePath(failedUrl)) {
      clearMemoryImageCache(failedUrl);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _preSeedHeavyImageUrl();
        _isHeavyImage = true;
        _cachedFilePath =
            _cachedFilePathByUrl[widget.imageUrl] ?? _cachedFilePath;
      });
      updateKeepAlive();
      _maybeNotifyHeavyImageDetected();
    });
    return true;
  }

  bool _shouldUseNativeAnimatedView(String url) {
    return ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
      url: url,
      isHeavy: _isHeavyImage,
      nativeViewAvailable: AnimatedWebPView.isAvailable,
      confirmedAnimatedWebP: _isConfirmedAnimatedWebP,
    );
  }

  bool get _shouldAutoPlayAnimatedView {
    return ExtendedImageReaderWidget.shouldAutoPlayAnimatedViewForTesting(
      pageNumber: widget.pageNumber,
      visiblePageNumber: widget.visiblePageNotifier?.value,
    );
  }

  @override
  void didUpdateWidget(covariant ExtendedImageReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sourceChanged = oldWidget.sourceId != widget.sourceId;
    final imageChanged = oldWidget.imageUrl != widget.imageUrl;
    final contentChanged = oldWidget.contentId != widget.contentId;

    if (sourceChanged || imageChanged || contentChanged) {
      _ehentaiResolveRetries = 0;
      _pageResolveFuture = null;
      _postProcessScheduledPath = null;
      _staticConvertedFilePath = null;
      if (_resolveCancellation != null && !_resolveCancellation!.isCancelled) {
        _resolveCancellation!.cancel('Widget updated');
      }
      _resolveCancellation = _pipeline.createCancellation();
      _prepareEhentaiResolveFuture();
      _prepareMangaFireImageFuture();

      if (_isLocalFilePath(widget.imageUrl)) {
        final localPath = _normalizeLocalPath(widget.imageUrl);
        _seedConvertedPathFromCache(localPath);
        _cachedFilePath = _staticConvertedFilePath ?? localPath;
        _boundedMapPut(_cachedFilePathByUrl, widget.imageUrl, _cachedFilePath!,
            _maxCachedFilePathByUrl);
        final isKnownBrokenAvif = localPath.toLowerCase().endsWith('.avif') &&
            _knownBrokenLocalAvifPaths.contains(localPath);
        _shouldBypassLocalDecode = isKnownBrokenAvif;
        if (!_shouldBypassLocalDecode) {
          _awaitingNativeCheck = _shouldConvertTallAvifLocalFile(localPath);
          _preCheckLocalFileForHeavy(localPath);
        }
      } else {
        _shouldBypassLocalDecode = false;
        _awaitingNativeCheck = false;
      }
    }
  }

  void _markLocalDecodeAsBroken() {
    if (_shouldBypassLocalDecode) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shouldBypassLocalDecode) {
        return;
      }

      setState(() {
        _shouldBypassLocalDecode = true;
      });
    });
  }

  void _retryBrokenLocalImage() {
    final localPath = _normalizeLocalPath(widget.imageUrl);
    if (localPath.toLowerCase().endsWith('.avif')) {
      _knownBrokenLocalAvifPaths.remove(localPath);
    }
    _pipeline.hasInvalidImagePayload(localPath).then((shouldBypass) {
      if (!mounted) {
        _shouldBypassLocalDecode = shouldBypass;
        return;
      }
      setState(() {
        _shouldBypassLocalDecode = shouldBypass;
      });
      if (!shouldBypass) {
        _awaitingNativeCheck = _shouldConvertTallAvifLocalFile(localPath);
        _preCheckLocalFileForHeavy(localPath);
      }
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    if (_resolveCancellation != null && !_resolveCancellation!.isCancelled) {
      _resolveCancellation!.cancel('Widget dispose');
    }
    _pinchHintController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  // Adaptive BoxFit — uses fitWidth for all modes so the image always fills width.
  BoxFit _getAdaptiveBoxFit() {
    // Use fitWidth for all modes so the image always fills the screen width.
    // This ensures:
    // - Paginated (single/vertical): image fills full width; zooming expands
    //   BEYOND screen in all directions → free pan (no boxed feel)
    // - continuousScroll: standard fill-width behaviour
    // minScale < 1.0 in GestureConfig lets users pinch-out to see wide/landscape
    // images in full if needed.
    return BoxFit.fitWidth;
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    if (!widget.enableZoom) return;

    final pointerDownPosition = state.pointerDownPosition;
    final double begin = state.gestureDetails!.totalScale!;
    final double end = begin > 1.5 ? 1.0 : 2.0;

    _zoomAnimation.removeListener(() {});
    _zoomController.stop();
    _zoomController.reset();
    _zoomAnimation = _zoomController.drive(
      Tween<double>(begin: begin, end: end),
    );

    void animationListener() {
      state.handleDoubleTap(
        scale: _zoomAnimation.value,
        doubleTapPosition: pointerDownPosition,
      );
    }

    _zoomAnimation.addListener(animationListener);
    _zoomController.forward().then((_) {
      _zoomAnimation.removeListener(animationListener);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 🐛 FIX: page skipped during download — show repair/redownload card.
    if (widget.imageUrl.startsWith('__failed__:')) {
      return _buildFailedPagePlaceholderWidget(context);
    }

    final normalizedLocalPath = _normalizeLocalPath(widget.imageUrl);
    final effectiveLocalPath =
        ExtendedImageReaderWidget.resolvedConvertedImagePathForTesting(
      convertedPath: _staticConvertedFilePath,
      resolvedPath: normalizedLocalPath,
    );

    final isLocalFile = _isLocalFilePath(widget.imageUrl);

    if (isLocalFile) {
      if (_shouldBypassLocalDecode) {
        return _buildErrorWidget(
          context,
          failedSource: effectiveLocalPath,
          onRetry: _retryBrokenLocalImage,
        );
      }

      if (_awaitingNativeCheck) {
        return _buildLoadingIndicator(context);
      }

      // Tall static AVIF on disk (often a `.jpg` holding AVIF): Flutter cannot
      // decode it. Convert in place — same path as initState's pre-check, which
      // also deletes format conflicts and syncs offline metadata.
      if (!_isHeavyImage &&
          AnimatedWebPView.isAvailable &&
          _postProcessScheduledPath != effectiveLocalPath &&
          _shouldConvertTallAvifLocalFile(effectiveLocalPath)) {
        _postProcessScheduledPath = effectiveLocalPath;
        _awaitingNativeCheck = true;
        _preCheckLocalFileForHeavy(effectiveLocalPath);
        return _buildLoadingIndicator(context);
      }

      if (_shouldUseNativeAnimatedView(effectiveLocalPath)) {
        return _buildNativeAnimatedWebP(
          effectiveLocalPath,
          const {},
          filePathOverride: _cachedFilePath ?? effectiveLocalPath,
        );
      }

      //  ExtendedImage.file with cacheWidth — pre-decode via
      // precacheImage already populated ImageCache at display resolution.
      // ExtendedImage.file reads from disk + decodes at cacheWidth → fast.

      return ExtendedImage.file(
        File(effectiveLocalPath),
        key:
            ValueKey('extended_image_${widget.contentId}_${widget.pageNumber}'),
        fit: _getAdaptiveBoxFit(),
        cacheWidth: _targetDecodeWidth(context),
        mode: widget.enableZoom &&
                widget.readingMode != ReadingMode.continuousScroll
            ? ExtendedImageMode.gesture
            : ExtendedImageMode.none,
        // Keep heavy/animated local files in memory on dispose so scroll-back
        // does not trigger re-decode.
        clearMemoryCacheWhenDispose:
            ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
          readingMode: widget.readingMode,
          isHeavy: _isHeavyImage,
          isHeavyReaderSource: false,
        ),
        enableLoadState: true,
        extendedImageGestureKey: _gestureKey,
        initGestureConfigHandler: (state) {
          return GestureConfig(
            // Allow pinch-out to see wide/landscape images, and plenty of
            // pinch-in headroom for reading small text.
            minScale: 0.5,
            maxScale: 5.0,
            animationMinScale: 0.4,
            animationMaxScale: 5.5,
            speed: 1.0,
            inertialSpeed: 100.0,
            initialScale: 1.0,
            inPageView: widget.readingMode != ReadingMode.continuousScroll,
            cacheGesture: false,
            initialAlignment: InitialAlignment.center,
          );
        },
        onDoubleTap: widget.enableZoom
            ? (ExtendedImageGestureState gestureState) {
                if (widget.onDoubleTapGesture != null) {
                  widget.onDoubleTapGesture!();
                } else {
                  _handleDoubleTap(gestureState);
                }
              }
            : null,
        loadStateChanged: (ExtendedImageState state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              if (!_isLocalFilePath(normalizedLocalPath)) {
                return _buildLoadingIndicator(context, state: state);
              }
              return null; // no loading indicator for local files
            case LoadState.failed:
              if (_tryNativeAnimatedFallback(normalizedLocalPath)) {
                return _buildLoadingIndicator(context);
              }
              _markLocalDecodeAsBroken();
              return _buildErrorWidget(
                context,
                failedSource: effectiveLocalPath,
                onRetry: _retryBrokenLocalImage,
              );
            case LoadState.completed:
              if (widget.onImageLoaded != null &&
                  state.extendedImageInfo?.image != null) {
                final image = state.extendedImageInfo!.image;
                final imageSize = Size(
                  image.width.toDouble(),
                  image.height.toDouble(),
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    widget.onImageLoaded?.call(widget.pageNumber, imageSize);
                  }
                });
              }

              if (!_isHeavyImage && AnimatedWebPView.isAvailable) {
                _schedulePostProcessResolvedFile(effectiveLocalPath);
              }

              return _buildCompletedImage(context, state);
          }
        },
      );
    } else {
      final effectiveImageUrl = widget.imageUrl;
      final isEhentaiReaderUrl =
          _shouldResolveEhentaiImageUrl(effectiveImageUrl);
      if (!isEhentaiReaderUrl) {
        final headers = widget.sourceId == 'hentainexus'
            ? _buildHentainexusImageHeaders(effectiveImageUrl)
            : widget.httpHeaders;

        //  ExtendedImage.network handles caching + cacheWidth.
        // Pre-decode via precacheImage already populated ImageCache → instant.
        return _buildNetworkImage(
          context,
          effectiveImageUrl,
          headers: headers,
        );
      }

      return FutureBuilder<String?>(
        future: _ehentaiResolvedImageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingIndicator(context);
          }

          final resolved = snapshot.data;
          if (resolved == null || resolved.isEmpty) {
            return _buildStandaloneErrorWidget(context);
          }

          return _buildNetworkImage(
            context,
            resolved,
            headers: _buildEhentaiImageHeaders(widget.imageUrl),
          );
        },
      );
    }
  }

  void _prepareEhentaiResolveFuture() {
    if (_shouldResolveEhentaiImageUrl(widget.imageUrl)) {
      _ehentaiResolvedImageFuture = _resolveEhentaiImageUrl(widget.imageUrl);
      return;
    }

    _ehentaiResolvedImageFuture = null;
  }

  void _prepareMangaFireImageFuture() {
    if (_shouldResolveMangaFireImageBytes(widget.imageUrl)) {
      _mangaFireResolvedImageFuture =
          _resolveMangaFireImageBytes(widget.imageUrl);
      return;
    }

    _mangaFireResolvedImageFuture = null;
  }

  Widget _buildNetworkImage(
    BuildContext context,
    String rawUrl, {
    Map<String, String>? headers,
    String? forceUrl,
  }) {
    final targetUrl = forceUrl ?? rawUrl;
    final urlParts = targetUrl.split('|');
    final url = urlParts[0];
    final fallbackUrl = urlParts.length > 1 ? urlParts[1] : null;

    if (_shouldResolveMangaFireImageBytes(url)) {
      return FutureBuilder<Uint8List?>(
        future: _mangaFireResolvedImageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingIndicator(context);
          }

          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return _buildResolvedOrNetworkImage(
                context, rawUrl, url, fallbackUrl,
                headers: headers);
          }

          return _buildMemoryImage(context, bytes);
        },
      );
    }

    return _buildResolvedOrNetworkImage(context, rawUrl, url, fallbackUrl,
        headers: headers);
  }

  /// Resolves the page image through the unified download-first repository
  /// (same transport as downloads: remote source + bypass + rate-limit) and
  /// returns a local file path on success. Returns null when the repository is
  /// unavailable or resolution failed, so the caller can fall back.
  Future<PageImageResult?> _resolvePageToFile(String url) {
    _resolveCancellation ??= _pipeline.createCancellation();
    if (_resolveCancellation!.isCancelled) {
      _resolveCancellation = _pipeline.createCancellation();
    }
    return _pipeline.resolvePageToFile(
      url: url,
      contentId: widget.contentId,
      pageNumber: widget.pageNumber,
      sourceId: widget.sourceId,
      headers: widget.httpHeaders,
      cancellation: _resolveCancellation,
    );
  }

  /// Builds the reader page by resolving to a local file first (download-first).
  /// Falls back to the legacy network path only when the repository is absent.
  Widget _buildResolvedOrNetworkImage(
    BuildContext context,
    String rawUrl,
    String url,
    String? fallbackUrl, {
    Map<String, String>? headers,
  }) {
    _pageResolveFuture ??= _resolvePageToFile(url);

    return FutureBuilder<PageImageResult?>(
      future: _pageResolveFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoadingIndicator(context);
        }

        final result = snapshot.data;
        final String? path = result is ReadyFromDisk
            ? result.path
            : result is ReadyFresh
                ? result.path
                : null;
        if (path != null) {
          // If an AVIF→WebP conversion is in-flight, show loading instead
          // of letting Flutter try to decode the AVIF (which fails).
          if (_awaitingNativeCheck) {
            return _buildLoadingIndicator(context);
          }
          // Tall static AVIF served as `.jpg`/`.png` fails Flutter's decode
          // too. Flag it before the first decode attempt, then convert.
          if (!_isHeavyImage &&
              AnimatedWebPView.isAvailable &&
              _postProcessScheduledPath != path &&
              _shouldConvertTallAvifLocalFile(path)) {
            _awaitingNativeCheck = true;
            _schedulePostProcessResolvedFile(path);
            return _buildLoadingIndicator(context);
          }
          // Fire-and-forget post-processing: animated detection + conversion.
          // Only runs when _preCheckDiskCacheForHeavy did not already find
          // the file (i.e. _awaitingNativeCheck is false and file is not yet
          // marked as heavy). This prevents double conversion.
          // Deferred post-frame: _postProcessResolvedFile calls setState
          // before its first await, so calling it here would run setState
          // synchronously inside the build phase.
          if (!_isHeavyImage && AnimatedWebPView.isAvailable) {
            _schedulePostProcessResolvedFile(path);
          }
          // Heavy/animated routing still runs from the local file (unchanged).
          if (_shouldUseNativeAnimatedView(path)) {
            return _buildNativeAnimatedWebP(path, headers);
          }
          // Tall static AVIF was converted in place: the resolved path is
          // gone, so render the WebP as a plain webtoon page.
          final renderPath =
              ExtendedImageReaderWidget.resolvedConvertedImagePathForTesting(
            convertedPath: _staticConvertedFilePath,
            resolvedPath: path,
          );
          return ExtendedImage.file(
            File(renderPath),
            key: ValueKey(
                'extended_image_${widget.contentId}_${widget.pageNumber}'),
            fit: _getAdaptiveBoxFit(),
            cacheWidth: _targetDecodeWidth(context, imageUrl: renderPath),
            mode: widget.enableZoom &&
                    widget.readingMode != ReadingMode.continuousScroll
                ? ExtendedImageMode.gesture
                : ExtendedImageMode.none,
            enableLoadState: true,
            extendedImageGestureKey: _gestureKey,
            initGestureConfigHandler: (state) {
              return GestureConfig(
                minScale: 0.5,
                maxScale: 5.0,
                animationMinScale: 0.4,
                animationMaxScale: 5.5,
                speed: 1.0,
                inertialSpeed: 100.0,
                initialScale: 1.0,
                inPageView: widget.readingMode != ReadingMode.continuousScroll,
                cacheGesture: false,
                initialAlignment: InitialAlignment.center,
              );
            },
            onDoubleTap: widget.enableZoom
                ? (ExtendedImageGestureState g) {
                    if (widget.onDoubleTapGesture != null) {
                      widget.onDoubleTapGesture!();
                    } else {
                      _handleDoubleTap(g);
                    }
                  }
                : null,
            loadStateChanged: (state) {
              switch (state.extendedImageLoadState) {
                case LoadState.completed:
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final image = state.extendedImageInfo?.image;
                    if (mounted && image != null) {
                      widget.onImageLoaded?.call(
                        widget.pageNumber,
                        Size(image.width.toDouble(), image.height.toDouble()),
                      );
                    }
                  });
                  return _buildCompletedImage(context, state, imageUrl: path);
                case LoadState.failed:
                  return _buildErrorWidget(context, failedSource: path,
                      onRetry: () {
                    setState(() {
                      _pageResolveFuture = null;
                      _postProcessScheduledPath = null;
                    });
                  });
                case LoadState.loading:
                  return _buildLoadingIndicator(context, state: state);
              }
            },
          );
        }

        // Resolve failed or repo absent → keep the existing network path.
        return _buildStandardNetworkImage(context, rawUrl, url, fallbackUrl,
            headers: headers);
      },
    );
  }

  void _schedulePostProcessResolvedFile(String path) {
    if (_postProcessScheduledPath == path) return;
    _postProcessScheduledPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHeavyImage) return;
      _pipeline
          .processImageFile(
        filePath: path,
        contentId: widget.contentId,
        pageNumber: widget.pageNumber,
      )
          .then((result) {
        _applyProcessedResult(result);
      });
    });
  }

  Widget _buildStandardNetworkImage(
    BuildContext context,
    String rawUrl,
    String url,
    String? fallbackUrl, {
    Map<String, String>? headers,
  }) {
    // Only route small/normal .webp through ExtendedImage.network.
    final isLikelyAnimatedUrl = _isLikelyAnimatedUrl(url);
    if (_shouldUseNativeAnimatedView(url)) {
      return _buildNativeAnimatedWebP(url, headers);
    }

    // Block ExtendedImage from decoding while the async native-format check
    // is in flight. Prevents "getPixels failed: invalid input" when Android's
    // ImageDecoder encounters an avis animated-AVIF sequence.
    if (_awaitingNativeCheck) {
      return _buildLoadingIndicator(context);
    }

    final decodeWidth = _targetDecodeWidth(
      context,
      imageUrl: url,
      isLikelyAnimatedUrl: isLikelyAnimatedUrl,
    );

    return ExtendedImage.network(
      url,
      key: ValueKey('extended_image_${widget.contentId}_${widget.pageNumber}'),
      headers: headers,
      fit: _getAdaptiveBoxFit(),
      //  ALL static images use FilterQuality.low (bilinear) —
      // cacheWidth at display size makes nearest-neighbor (none) acceptable.
      // Animated WebP uses FilterQuality.none (fastest per-frame).
      filterQuality:
          isLikelyAnimatedUrl ? FilterQuality.none : FilterQuality.low,
      mode: widget.enableZoom &&
              widget.readingMode != ReadingMode.continuousScroll
          ? ExtendedImageMode.gesture
          : ExtendedImageMode.none,
      // Let ordinary pages in long continuous-scroll sessions recycle their
      // decoded frame buffers, while heavy/native pages stay warm.
      clearMemoryCacheWhenDispose:
          ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
        readingMode: widget.readingMode,
        isHeavy: _isHeavyImage,
        isHeavyReaderSource: _isHeavyReaderSource(),
      ),
      cache: true,
      cacheMaxAge: const Duration(days: 14),
      cacheWidth: decodeWidth,
      cancelToken: _cancelToken,
      handleLoadingProgress: true,
      enableLoadState: true,
      extendedImageGestureKey: _gestureKey,
      initGestureConfigHandler: (state) {
        return GestureConfig(
          minScale: 0.5,
          maxScale: 5.0,
          animationMinScale: 0.4,
          animationMaxScale: 5.5,
          speed: 1.0,
          inertialSpeed: 100.0,
          initialScale: 1.0,
          inPageView: widget.readingMode != ReadingMode.continuousScroll,
          cacheGesture: false,
          initialAlignment: InitialAlignment.center,
        );
      },
      onDoubleTap: widget.enableZoom
          ? (ExtendedImageGestureState gestureState) {
              if (widget.onDoubleTapGesture != null) {
                widget.onDoubleTapGesture!();
              } else {
                _handleDoubleTap(gestureState);
              }
            }
          : null,
      loadStateChanged: (ExtendedImageState state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            // Optional pre-seed via Content-Length (only if server sends it):
            // servers that skip Content-Length are handled at LoadState.completed.
            if (!_isHeavyImage) {
              try {
                final dynamic prog = (state as dynamic).loadingProgress;
                final total = prog?.expectedTotalBytes;
                if (total is num && total >= _heavyImageThresholdBytes) {
                  _preSeedHeavyImageUrl();
                  // Online large payload detected: lock continuous mode early.
                  _maybeNotifyHeavyImageDetected();
                }
              } catch (e) {
                _logger.w('Heavy image detection failed', error: e);
              }
            }

            return _buildLoadingIndicator(context, state: state);
          case LoadState.failed:
            if (_tryRefreshEhentaiResolvedImageUrl(url)) {
              return _buildLoadingIndicator(context);
            }
            if (_tryNativeAnimatedFallback(url)) {
              return _buildLoadingIndicator(context);
            }
            if (fallbackUrl != null) {
              _logger.w(
                  '🔄 Reader falling back to secondary network URL: $fallbackUrl');
              return _buildNetworkImage(context, rawUrl,
                  headers: headers, forceUrl: fallbackUrl);
            }
            return _buildErrorWidget(
              context,
              state: state,
              failedSource: url,
            );
          case LoadState.completed:
            _ehentaiResolveRetries = 0;
            if (widget.onImageLoaded != null &&
                state.extendedImageInfo?.image != null) {
              final image = state.extendedImageInfo!.image;
              final imageSize = Size(
                image.width.toDouble(),
                image.height.toDouble(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onImageLoaded?.call(widget.pageNumber, imageSize);
              });
            }

            // Many servers skip Content-Length; check actual file on disk at complete.
            if (!_isConfirmedAnimatedWebP &&
                AnimatedWebPView.isAvailable &&
                _shouldInspectCachedFileForAnimatedWebP(url)) {
              getCachedImageFile(url).then((cacheFile) {
                if (cacheFile == null) return;
                _pipeline
                    .processImageFile(
                  filePath: cacheFile.path,
                  contentId: widget.contentId,
                  pageNumber: widget.pageNumber,
                )
                    .then((result) {
                  if (result.isHeavy || result.isConfirmedAnimatedWebP) {
                    _markHeavyNativeAnimatedImage(
                      cacheKey: widget.imageUrl,
                      cachedFilePath: cacheFile.path,
                      confirmedAnimatedWebP: true,
                    );
                    clearMemoryImageCache(url);
                    _cancelToken?.cancel();
                    if (!mounted) return;
                    _cancelToken = CancellationToken();
                    setState(() {
                      _isHeavyImage = true;
                      _isConfirmedAnimatedWebP = true;
                      _cachedFilePath = cacheFile.path;
                      if (result.nativeImageSize != null) {
                        _nativeImageSize = result.nativeImageSize;
                      }
                      if (result.imageBytes != null) {
                        _nativeImageByteSize = result.imageBytes;
                      }
                    });
                    updateKeepAlive();
                    _maybeNotifyHeavyImageDetected();
                    if (result.nativeImageSize != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          widget.onImageLoaded
                              ?.call(widget.pageNumber, result.nativeImageSize!);
                        }
                      });
                    }
                  } else {
                    _boundedSetAdd(
                        _nonNativeAnimatedUrls, url, _maxHeavyImageUrls);
                  }
                });
              }).catchError((Object e) {
                _logger.w('[NativeWebP] getCachedImageFile error: $e');
              });
            }

            return _buildCompletedImage(
              context,
              state,
              imageUrl: url,
            );
        }
      },
    );
  }

  // Wraps [AnimatedWebPView] in [RepaintBoundary] so native animation
  // layers do not invalidate the surrounding Flutter tree.
  Widget _buildNativeAnimatedWebP(
    String url,
    Map<String, String>? headers, {
    String? filePathOverride,
  }) {
    final resolvedFilePath = filePathOverride ?? _cachedFilePath;
    final playInlineInContinuousScroll =
        widget.readingMode == ReadingMode.continuousScroll;

    final l10n = AppLocalizations.of(context);
    Widget nativeView = RepaintBoundary(
      child: AnimatedWebPView(
        key: ValueKey('native_webp_${widget.contentId}_${widget.pageNumber}'),
        url: url,
        filePath: resolvedFilePath,
        headers: headers ?? const {},
        targetWidth: _nativeDecodeWidth(context),
        pauseTooltip: l10n?.pause ?? 'Pause',
        playTooltip: l10n?.resume ?? 'Resume',
        autoPlay: playInlineInContinuousScroll || _shouldAutoPlayAnimatedView,
        pageNumber: widget.pageNumber,
        visiblePageNotifier: widget.visiblePageNotifier,
        grayscale: widget.grayscale,
        loadingBuilder: (context, receivedBytes, totalBytes) =>
            _buildLoadingIndicator(
          context,
          loadedBytesOverride: receivedBytes,
          totalBytesOverride: totalBytes,
        ),
        fallback: _buildLoadingIndicator(context),
      ),
    );

    // In webtoon/continuous-scroll mode, ListView items have no intrinsic
    // height so SizedBox.expand inside AnimatedWebPView collapses to zero.
    // Apply AspectRatio when image dimensions are known.
    if (widget.readingMode == ReadingMode.continuousScroll) {
      if (_nativeImageSize != null &&
          _nativeImageSize!.width > 0 &&
          _nativeImageSize!.height > 0) {
        nativeView = AspectRatio(
          aspectRatio: _nativeImageSize!.width / _nativeImageSize!.height,
          child: nativeView,
        );
      } else {
        nativeView = ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.width * 0.5,
            maxHeight: MediaQuery.of(context).size.width * 1.6,
          ),
          child: nativeView,
        );
      }
    }

    return nativeView;
  }

  bool _shouldResolveEhentaiImageUrl(String url) {
    return _pipeline.shouldResolveEhentai(url, sourceId: widget.sourceId);
  }

  bool _isHeavyReaderSource() {
    switch (widget.sourceId?.toLowerCase()) {
      case 'hentainexus':
      case 'ehentai':
        return true;
      default:
        return false;
    }
  }

  bool _shouldInspectCachedFileForAnimatedWebP(String url) {
    if (_nonNativeAnimatedUrls.contains(url)) {
      return false;
    }

    // Always inspect after download — brand (avis vs avif/mif1) and image
    // height (≤ 4096 vs > 4096) live in the bytes, not the URL, and `.jpg` /
    // `.jpeg` / `.png` URLs can carry AVIF payloads.
    // ReaderImagePipeline handles the precise check.
    return ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
      url: url,
      sourceId: widget.sourceId ?? '',
    );
  }

  void _markHeavyNativeAnimatedImage({
    required String cacheKey,
    required String cachedFilePath,
    required bool confirmedAnimatedWebP,
  }) {
    _boundedSetAdd(_heavyImageUrls, cacheKey, _maxHeavyImageUrls);
    _boundedMapPut(_cachedFilePathByUrl, cacheKey, cachedFilePath,
        _maxCachedFilePathByUrl);
    if (confirmedAnimatedWebP) {
      _boundedSetAdd(
          _confirmedAnimatedWebPUrls, cacheKey, _maxConfirmedAnimatedWebPUrls);
    }
  }


  int? _targetDecodeWidth(
    BuildContext context, {
    String? imageUrl,
    bool? isLikelyAnimatedUrl,
  }) {
    //  decode at display resolution — 25× less GPU texture upload
    // for non-CS pages. Pinch-zoom: ExtendedImage reloads from cache.
    if (!(_isHeavyReaderSource() || _isHeavyImage)) {
      final mediaQuery = MediaQuery.of(context);
      return (mediaQuery.size.width * mediaQuery.devicePixelRatio).round();
    }

    final mediaQuery = MediaQuery.of(context);
    // Animated WebP: 40% — each frame of a 45-frame 1416×1608 animation at
    // 75% would still be ~2.5 MB raw; at 40% it drops to ~700 KB per frame,
    // bringing the total decoded footprint from ~112 MB to ~31 MB.
    // Static heavy: 75% — keeps text/detail readable.
    // Normal images: 100% width × DPR — exact display size, 0 waste.
    final bool animatedImage = isLikelyAnimatedUrl ??
        _isLikelyAnimatedUrl(imageUrl ?? widget.imageUrl);
    final bool heavyImage = _isHeavyReaderSource() || _isHeavyImage;
    final double factor = animatedImage ? 0.40 : (heavyImage ? 0.75 : 1.0);
    return ((mediaQuery.size.width * factor) * mediaQuery.devicePixelRatio)
        .round();
  }

  // Viewport-relative decode width with caps for very large offline animated WebP.
  int _nativeDecodeWidth(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ExtendedImageReaderWidget.resolveNativeAnimatedDecodeWidthForTesting(
      logicalWidth: mq.size.width,
      devicePixelRatio: mq.devicePixelRatio,
      imageBytes: _resolveNativeAnimatedImageBytes(),
    );
  }

  int? _resolveNativeAnimatedImageBytes() {
    return _nativeImageByteSize;
  }

  Map<String, String> _buildEhentaiImageHeaders(String readerPageUrl) {
    final headers = <String, String>{...?widget.httpHeaders};
    headers['Referer'] = readerPageUrl;
    return headers;
  }

  Map<String, String> _buildHentainexusImageHeaders(String imageUrl) {
    final headers = <String, String>{...?widget.httpHeaders};
    headers['Accept'] =
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';
    headers['Accept-Language'] = 'en-US,en;q=0.6';
    headers['Origin'] = 'https://hentainexus.com';
    headers['Referer'] = 'https://hentainexus.com/';
    return headers;
  }

  Future<String?> _resolveEhentaiImageUrl(String readerPageUrl) {
    return _pipeline.resolveEhentaiImageUrl(
      readerPageUrl,
      headers: widget.httpHeaders,
      rawConfig: widget.sourceRawConfig,
    );
  }

  void _invalidateEhentaiResolvedImageUrl(String readerPageUrl) {
    _pipeline.invalidateEhentaiResolvedImageUrl(readerPageUrl);
  }

  bool _tryRefreshEhentaiResolvedImageUrl(String failedUrl) {
    if ((widget.sourceId ?? '').toLowerCase() != 'ehentai') {
      return false;
    }

    final readerPageUrl = widget.imageUrl;
    if (!_shouldResolveEhentaiImageUrl(readerPageUrl)) {
      return false;
    }

    if (_ehentaiResolveRetries >= _maxEhentaiResolveRetries) {
      return false;
    }

    _ehentaiResolveRetries++;
    _invalidateEhentaiResolvedImageUrl(readerPageUrl);
    _logger.w(
      'E-Hentai reader image failed, refreshing tokenized URL '
      '(attempt $_ehentaiResolveRetries/$_maxEhentaiResolveRetries). '
      'page=${widget.pageNumber}, failed=$failedUrl',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _ehentaiResolvedImageFuture = _resolveEhentaiImageUrl(readerPageUrl);
      });
    });

    return true;
  }

  String _formatByteSize(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Widget _buildStandaloneErrorWidget(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        AppLocalizations.of(context)!.failedToLoadImage,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMemoryImage(BuildContext context, Uint8List bytes) {
    final decodeWidth = _targetDecodeWidth(
      context,
      imageUrl: widget.imageUrl,
      isLikelyAnimatedUrl: false,
    );

    return ExtendedImage.memory(
      bytes,
      key: ValueKey('extended_memory_${widget.contentId}_${widget.pageNumber}'),
      fit: _getAdaptiveBoxFit(),
      filterQuality: FilterQuality.low,
      mode: widget.enableZoom &&
              widget.readingMode != ReadingMode.continuousScroll
          ? ExtendedImageMode.gesture
          : ExtendedImageMode.none,
      clearMemoryCacheWhenDispose:
          ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
        readingMode: widget.readingMode,
        isHeavy: _isHeavyImage,
        isHeavyReaderSource: _isHeavyReaderSource(),
      ),
      cacheWidth: decodeWidth,
      extendedImageGestureKey: _gestureKey,
      initGestureConfigHandler: (state) {
        return GestureConfig(
          minScale: 0.5,
          maxScale: 5.0,
          animationMinScale: 0.4,
          animationMaxScale: 5.5,
          speed: 1.0,
          inertialSpeed: 100.0,
          initialScale: 1.0,
          inPageView: widget.readingMode != ReadingMode.continuousScroll,
          initialAlignment: InitialAlignment.center,
        );
      },
      onDoubleTap: widget.onDoubleTapGesture != null
          ? null
          : (state) => _handleDoubleTap(state),
    );
  }

  bool _shouldResolveMangaFireImageBytes(String url) {
    return _pipeline.shouldResolveMangaFireImageBytes(url,
        sourceId: widget.sourceId);
  }

  Future<Uint8List?> _resolveMangaFireImageBytes(String url) {
    return _pipeline.resolveMangaFireImageBytes(
      url,
      headers: widget.httpHeaders,
    );
  }

  // Card for a page skipped during download, with repair/redownload buttons.
  Widget _buildFailedPagePlaceholderWidget(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasRepair = widget.onRepairBrokenImage != null;
    final bool hasSourcePageFallback = widget.onOpenSourcePageForRepair != null;
    final isRepairing = _isRepairingBrokenImage;
    final isOpeningSourcePage = _isOpeningSourcePage;
    final isActionBusy = isRepairing || isOpeningSourcePage;

    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.readerPageNotDownloaded(widget.pageNumber),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.readerPageSkippedDuringDownload,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                textAlign: TextAlign.center,
              ),
              if (hasSourcePageFallback) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isActionBusy
                        ? null
                        : () async {
                            setState(() {
                              _isOpeningSourcePage = true;
                            });

                            try {
                              await widget.onOpenSourcePageForRepair!.call();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isOpeningSourcePage = false;
                                });
                              }
                            }
                          },
                    icon: isOpeningSourcePage
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.language, size: 16),
                    label: Text(
                      isOpeningSourcePage
                          ? l10n.readerOpeningSourcePage
                          : l10n.readerOpenSourcePage,
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                  ),
                ),
              ],
              if (hasRepair) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isActionBusy
                        ? null
                        : () async {
                            setState(() {
                              _isRepairingBrokenImage = true;
                            });

                            try {
                              await widget.onRepairBrokenImage!.call();
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isRepairingBrokenImage = false;
                                });
                              }
                            }
                          },
                    icon: isRepairing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: Text(
                      isRepairing
                          ? l10n.readerRepairingImage
                          : l10n.readerRedownloadImage,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Loading indicator with download progress.
  Widget _buildLoadingIndicator(BuildContext context,
      {ExtendedImageState? state,
      int? loadedBytesOverride,
      int? totalBytesOverride}) {
    final l10n = AppLocalizations.of(context)!;
    final bool isContinuousScroll =
        widget.readingMode == ReadingMode.continuousScroll;

    double? progressValue;
    int? progressPercent;
    int loadedBytes = loadedBytesOverride ?? 0;
    int? totalBytes = totalBytesOverride;
    try {
      if (state != null) {
        final dynamic progressEvent = (state as dynamic).loadingProgress;
        final loadedRaw = progressEvent?.cumulativeBytesLoaded;
        final totalRaw = progressEvent?.expectedTotalBytes;

        if (loadedRaw is num) {
          loadedBytes = loadedRaw.toInt();
        }
        if (totalRaw is num) {
          totalBytes = totalRaw.toInt();
        }
      }

      if (totalBytes != null && totalBytes > 0) {
        progressValue = (loadedBytes / totalBytes).clamp(0.0, 1.0);
        progressPercent = (progressValue * 100).floor();
      }
    } catch (_) {}

    final bool hasKnownTotal = totalBytes != null && totalBytes > 0;
    final bool hasRealByteCount = loadedBytes > 0;
    final int resolvedTotalBytes = totalBytes ?? 0;
    final bool isConvertingBadAvif = _awaitingNativeCheck;
    // Satu caption (headline % + detail byte digabung): 1 fokal teks.
    final String captionText = isConvertingBadAvif
        ? l10n.processingBadAvifToWebp
        : hasKnownTotal
            ? '${_formatByteSize(loadedBytes)} / ${_formatByteSize(resolvedTotalBytes)} • $progressPercent%'
            : hasRealByteCount
                ? l10n.downloaded(_formatByteSize(loadedBytes))
                : l10n.downloadingImageData;
    final double? indicatorValue = progressValue;
    final bool showIndeterminateFromRealBytes =
        hasRealByteCount && !hasKnownTotal;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      margin: isContinuousScroll
          ? EdgeInsets.symmetric(vertical: DesignTokens.spaceLg)
          : EdgeInsets.zero,
      child: Center(
        // Flat + bordered (house rule): elevation 0 + outline 1px,
        // maxWidth ganti fixed 240/280. Eye path: maskot → bar → caption.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: DesignTokens.spaceLg),
            padding: EdgeInsets.all(DesignTokens.spaceMd),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1 ticker pair per kartu loading; cuma window visible±4
                // yang hidup — masih di bawah budget thermal.
                const KuroMascot(mood: KuroMood.waiting, size: 64),
                SizedBox(height: DesignTokens.spaceSm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  child: LinearProgressIndicator(
                    value:
                        showIndeterminateFromRealBytes ? null : indicatorValue,
                    minHeight: 6,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                SizedBox(height: DesignTokens.spaceSm),
                Text(
                  captionText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Error widget with logo and retry option
  Widget _buildErrorWidget(
    BuildContext context, {
    ExtendedImageState? state,
    String? failedSource,
    VoidCallback? onRetry,
  }) {
    final bool isContinuousScroll =
        widget.readingMode == ReadingMode.continuousScroll;
    final double cardSize = isContinuousScroll ? 250 : 200;
    final double logoSize = isContinuousScroll ? 100 : 100;
    final double iconSize = isContinuousScroll ? 24 : 32;
    final l10n = AppLocalizations.of(context)!;
    final isRepairing = _isRepairingBrokenImage;
    final isOpeningSourcePage = _isOpeningSourcePage;
    final isActionBusy = isRepairing || isOpeningSourcePage;
    final resolvedFailedSource = failedSource ?? widget.imageUrl;
    final canOpenLocalAvif = _isLocalFilePath(resolvedFailedSource) &&
        _isAvifSource(resolvedFailedSource);
    final canOpenRemoteAvif = !_isLocalFilePath(resolvedFailedSource) &&
        _isAvifSource(resolvedFailedSource);
    final retryAction = onRetry ?? state?.reLoadImage;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Card(
          elevation: 8,
          shadowColor:
              Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            width: cardSize,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: const DecorationImage(
                          image: AssetImage('assets/icons/frame.webp'),
                          fit: BoxFit.cover,
                        ),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                    // Error icon overlay
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.8),
                      ),
                      child: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onError,
                        size: iconSize,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Text(
                  isRepairing
                      ? l10n.readerRepairingImage
                      : isOpeningSourcePage
                          ? l10n.readerOpeningSourcePage
                          : l10n.failedToLoad,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isActionBusy
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                  textAlign: TextAlign.center,
                ),

                Text(
                  l10n.pageNumber(widget.pageNumber),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                if (widget.onOpenSourcePageForRepair != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isActionBusy
                          ? null
                          : () async {
                              setState(() {
                                _isOpeningSourcePage = true;
                              });

                              bool repaired = false;
                              try {
                                repaired = await widget
                                    .onOpenSourcePageForRepair!
                                    .call();
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isOpeningSourcePage = false;
                                  });
                                }
                              }

                              if (repaired && mounted) {
                                if (state != null) {
                                  state.reLoadImage();
                                } else {
                                  _retryBrokenLocalImage();
                                }
                              }
                            },
                      icon: isOpeningSourcePage
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.language, size: 16),
                      label: Text(
                        isOpeningSourcePage
                            ? l10n.readerOpeningSourcePage
                            : l10n.readerOpenSourcePage,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusLg),
                        ),
                      ),
                    ),
                  ),

                if (widget.onOpenSourcePageForRepair != null)
                  const SizedBox(height: 8),

                if (widget.onRepairBrokenImage != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isActionBusy
                          ? null
                          : () async {
                              setState(() {
                                _isRepairingBrokenImage = true;
                              });

                              bool repaired = false;
                              try {
                                repaired =
                                    await widget.onRepairBrokenImage!.call();
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isRepairingBrokenImage = false;
                                  });
                                }
                              }

                              if (repaired && mounted) {
                                if (state != null) {
                                  state.reLoadImage();
                                } else {
                                  _retryBrokenLocalImage();
                                }
                              }
                            },
                      icon: isRepairing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.download_for_offline_outlined,
                              size: 16),
                      label: Text(
                        isRepairing
                            ? l10n.readerRepairingImage
                            : l10n.readerRedownloadImage,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusLg),
                        ),
                      ),
                    ),
                  ),

                if (widget.onRepairBrokenImage != null)
                  const SizedBox(height: 8),

                if (canOpenLocalAvif) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isActionBusy
                          ? null
                          : () =>
                              _openFailedAvifExternally(resolvedFailedSource),
                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                      label: Text(l10n.readerOpenInGallery),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusLg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Retry button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isActionBusy ? null : retryAction,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(l10n.retry),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      elevation: DesignTokens.elevationMd,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                  ),
                ),

                if (canOpenRemoteAvif) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isActionBusy
                          ? null
                          : () =>
                              _openFailedAvifExternally(resolvedFailedSource),
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: Text(l10n.openInBrowser),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusLg),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Completed image with zoom indicator.
  // Animated images wrapped in [RepaintBoundary] so each animation tick
  // re-rasterizes only its own composited layer, not siblings.
  Widget _buildCompletedImage(
    BuildContext context,
    ExtendedImageState state, {
    String? imageUrl,
  }) {
    final isLikelyAnimatedImage =
        _isLikelyAnimatedUrl(imageUrl ?? widget.imageUrl);
    final Widget imageWidget = widget.enableZoom
        ? state.completedWidget
        : ExtendedRawImage(
            image: state.extendedImageInfo?.image,
            fit: _getAdaptiveBoxFit(),
            alignment: Alignment.center,
          );

    if (!widget.enableZoom) {
      return isLikelyAnimatedImage
          ? RepaintBoundary(child: imageWidget)
          : imageWidget;
    }

    // RepaintBoundary isolates AnimatedBuilder rebuilds from the ListView.
    final Widget gestureWidget = AnimatedBuilder(
      animation: Listenable.merge([_zoomController, _pinchHintController]),
      builder: (context, child) {
        final gestureState = _gestureKey.currentState;
        final currentScale = gestureState?.gestureDetails?.totalScale ?? 1.0;
        final isZoomed = currentScale > 1.2;
        // Pinch hint: fade in then out during _pinchHintController lifetime
        final hintOpacity = _pinchHintController.value < 0.2
            ? _pinchHintController.value / 0.2
            : _pinchHintController.value > 0.7
                ? (1.0 - _pinchHintController.value) / 0.3
                : 1.0;
        final showHint = widget.onDoubleTapGesture != null &&
            _pinchHintController.isAnimating &&
            !isZoomed;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Continuous only: force viewport width so narrow sources fill
            // edge-to-edge inside their fixed-height box. Paged modes keep
            // Center — forcing width there crops tall pages vertically
            // with no scroll to recover the cut part.
            if (widget.readingMode == ReadingMode.continuousScroll)
              SizedBox(width: double.infinity, child: imageWidget)
            else
              Center(child: imageWidget),
            // Zoom level indicator (shown when zoomed in)
            if (isZoomed && widget.readingMode != ReadingMode.continuousScroll)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${(currentScale * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (showHint)
              Positioned(
                bottom: 72,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: hintOpacity.clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radius2xl),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.pinch,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(context)!.readerPinchToZoom,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    return isLikelyAnimatedImage
        ? RepaintBoundary(child: gestureWidget)
        : gestureWidget;
  }
}
