import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as path;

import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';
import 'package:logger/logger.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/image_cache_service.dart';
import '../../core/services/local_image_preloader.dart';
import '../../core/utils/performance_monitor.dart';
import '../../core/di/service_locator.dart';

enum _LocalThumbnailPreviewMode {
  original,
  animatedPlaceholder,
  heavyPlaceholder,
}

// Progressive Image Widget with enhanced local file priority
///
// Loading priority:
// 1. Downloaded content (nhasix/[id]/images/)
// 2. Local cache
// 3. Network with placeholder/error handling
///
// Features:
// - Fast local file detection
// - Shimmer placeholder
// - Error state handling
// - Memory optimization
// - Support for both page images and thumbnails
class ProgressiveImageWidget extends StatefulWidget {
  const ProgressiveImageWidget({
    super.key,
    required this.networkUrl,
    this.contentId,
    this.pageNumber,
    this.isThumbnail = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.memCacheHeight,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = DesignTokens.durationNormal,
    this.fadeOutDuration = const Duration(milliseconds: 100),
    this.httpHeaders,
    this.preferStaticPreview = false,
    this.onImageLoaded,
  });

  final String networkUrl;
  final String? contentId;
  final int? pageNumber;
  final bool isThumbnail;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final Map<String, String>? httpHeaders;
  final bool preferStaticPreview;
  final VoidCallback? onImageLoaded;

  @visibleForTesting
  static int get heavyAnimatedThumbnailThresholdBytesForTesting =>
      _ProgressiveImageWidgetState._heavyAnimatedThumbnailThresholdBytes;

  @visibleForTesting
  static bool shouldSuppressOfflineThumbnailForTesting({
    required String localPath,
    required int fileBytes,
    required bool isAnimated,
  }) {
    return _computeLocalThumbnailPreviewMode(
          localPath: localPath,
          fileBytes: fileBytes,
          isAnimated: isAnimated,
        ) !=
        _LocalThumbnailPreviewMode.original;
  }

  @visibleForTesting
  static bool shouldUseStaticNetworkDecodeFallbackForTesting(
    String networkUrl, {
    int? pageNumber,
    bool isThumbnail = false,
  }) {
    return _ProgressiveImageWidgetState.shouldUseStaticNetworkDecodeFallback(
      networkUrl,
      pageNumber: pageNumber,
      isThumbnail: isThumbnail,
    );
  }

  static _LocalThumbnailPreviewMode _computeLocalThumbnailPreviewMode({
    required String localPath,
    required int fileBytes,
    required bool isAnimated,
  }) {
    if (isAnimated) {
      return _LocalThumbnailPreviewMode.animatedPlaceholder;
    }

    final lowered = localPath.toLowerCase();
    final fileName = path.basename(lowered);
    final hasDedicatedCoverName =
        fileName.startsWith('cover.') ||
        fileName.startsWith('thumbnail.') ||
        fileName.startsWith('thumb.');
    if (fileBytes >=
            _ProgressiveImageWidgetState
                ._heavyAnimatedThumbnailThresholdBytes &&
        !hasDedicatedCoverName) {
      return _LocalThumbnailPreviewMode.heavyPlaceholder;
    }

    return _LocalThumbnailPreviewMode.original;
  }

  @override
  State<ProgressiveImageWidget> createState() => _ProgressiveImageWidgetState();
}

class _ProgressiveImageWidgetState extends State<ProgressiveImageWidget> {
  static final Logger _logger = getIt<Logger>();
  static const int _maxPathCacheSize = 500;
  static const int _maxThumbnailModeCacheSize = 200;
  static final Map<String, String?> _pathCache = {};
  static const int _heavyAnimatedThumbnailThresholdBytes =
      10 * 1024 * 1024; // 10 MB
  static final Map<String, _LocalThumbnailPreviewMode>
  _localThumbnailPreviewModeCache = <String, _LocalThumbnailPreviewMode>{};

  static void _addToPathCache(String key, String? value) {
    if (_pathCache.length >= _maxPathCacheSize) {
      final keysToRemove = _pathCache.keys.take(100).toList();
      for (final k in keysToRemove) {
        _pathCache.remove(k);
      }
    }
    _pathCache[key] = value;
  }

  static void _addToThumbnailModeCache(
    String key,
    _LocalThumbnailPreviewMode mode,
  ) {
    if (_localThumbnailPreviewModeCache.length >= _maxThumbnailModeCacheSize) {
      final keysToRemove = _localThumbnailPreviewModeCache.keys
          .take(50)
          .toList();
      for (final k in keysToRemove) {
        _localThumbnailPreviewModeCache.remove(k);
      }
    }
    _localThumbnailPreviewModeCache[key] = mode;
  }

  String? _cachedLocalPath;
  bool _isLocalPathResolved = false;
  bool _imageLoadedNotified = false;
  // Memoized static-process futures keyed by url+headers: rebuilding must
  // reuse in-flight GIF decode work, not spawn a duplicate isolate per build.
  Future<File?>? _gifProcessFuture;
  String? _gifProcessKey;
  Future<File?>? _staticProcessFuture;
  String? _staticProcessKey;

  Future<File?> _memoizedGifProcess(String url) {
    final key = '$url|${widget.httpHeaders}';
    if (_gifProcessKey != key) {
      _gifProcessKey = key;
      _gifProcessFuture = getIt<ImageCacheService>().getOrProcessStaticGif(
        url,
        widget.httpHeaders,
      );
    }
    return _gifProcessFuture!;
  }

  Future<File?> _memoizedStaticProcess(String url) {
    final key = '$url|${widget.httpHeaders}';
    if (_staticProcessKey != key) {
      _staticProcessKey = key;
      _staticProcessFuture = getIt<ImageCacheService>().getOrProcessStaticImage(
        url,
        headers: widget.httpHeaders,
      );
    }
    return _staticProcessFuture!;
  }

  void _notifyImageLoaded() {
    if (_imageLoadedNotified) return;
    _imageLoadedNotified = true;
    widget.onImageLoaded?.call();
  }

  String _networkCacheKey({String? urlToHash}) {
    final targetUrl = urlToHash ?? widget.networkUrl.split('|').first;
    final headers = widget.httpHeaders;
    if (headers == null || headers.isEmpty) {
      return targetUrl;
    }

    final keys = headers.keys.toList()..sort();
    final normalized = keys
        .map((key) => '$key=${headers[key] ?? ''}')
        .join('&');
    return '$targetUrl::h=$normalized';
  }

  @override
  void initState() {
    super.initState();
    _resolveLocalPath();
  }

  @override
  void didUpdateWidget(ProgressiveImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-resolve if content or page changed
    if (oldWidget.contentId != widget.contentId ||
        oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.isThumbnail != widget.isThumbnail) {
      _cachedLocalPath = null;
      _isLocalPathResolved = false;
      _resolveLocalPath();
    }
  }

  Future<void> _resolveLocalPath() async {
    if (widget.contentId == null) {
      if (mounted) {
        setState(() {
          _isLocalPathResolved = true;
        });
      }
      return;
    }

    // ✅ Check cache first to avoid repeated calls
    final cacheKey =
        '${widget.contentId}_${widget.pageNumber}_${widget.isThumbnail}';
    if (_pathCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _cachedLocalPath = _pathCache[cacheKey];
          _isLocalPathResolved = true;
        });
      }
      return;
    }

    // ✅ CHECK FOR DIRECT FILE PATH
    // If the "networkUrl" is actually a local path, use it directly
    if (!widget.networkUrl.startsWith('http') &&
        (widget.networkUrl.startsWith('/') ||
            widget.networkUrl.startsWith('file://'))) {
      final file = File(widget.networkUrl);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _cachedLocalPath = widget.networkUrl;
            _isLocalPathResolved = true;
          });
        }
        return;
      }
    }

    if (kDebugMode) {
      _logger.d(
        '🔍 Resolving local path for contentId: ${widget.contentId}, pageNumber: ${widget.pageNumber}, isThumbnail: ${widget.isThumbnail}',
      );
    }

    // ✅ Track performance of local path resolution
    final result = await PerformanceMonitor.timeOperation(
      'image_local_path_resolution',
      () async {
        final localPath = await _getLocalImagePath();
        return localPath;
      },
      metadata: {
        'content_id': widget.contentId,
        'page_number': widget.pageNumber,
        'is_thumbnail': widget.isThumbnail,
      },
    );

    // ✅ Cache the result
    _addToPathCache(cacheKey, result);

    if (kDebugMode && result != null) {
      _logger.d('✅ Local path resolved: $result');
    }

    if (mounted) {
      setState(() {
        _cachedLocalPath = result;
        _isLocalPathResolved = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If no contentId provided, fallback to network only
    if (widget.contentId == null) {
      return _buildNetworkImage();
    }

    // Show placeholder while resolving local path
    if (!_isLocalPathResolved) {
      return _buildPlaceholder();
    }

    // Use cached local path if available
    if (_cachedLocalPath != null) {
      return _buildLocalImage(_cachedLocalPath!);
    }

    // Fallback to network
    return _buildNetworkImage();
  }

  Future<_LocalThumbnailPreviewMode> _resolveLocalThumbnailPreviewMode(
    String localPath,
  ) async {
    final cachedMode = _localThumbnailPreviewModeCache[localPath];
    if (cachedMode != null) {
      return cachedMode;
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        _addToThumbnailModeCache(
          localPath,
          _LocalThumbnailPreviewMode.original,
        );
        return _LocalThumbnailPreviewMode.original;
      }

      final fileBytes = await file.length();
      final isAnimated = await _isAnimatedLocalThumbnail(
        localPath: localPath,
        file: file,
      );
      final mode = ProgressiveImageWidget._computeLocalThumbnailPreviewMode(
        localPath: localPath,
        fileBytes: fileBytes,
        isAnimated: isAnimated,
      );

      _addToThumbnailModeCache(localPath, mode);
      return mode;
    } catch (e) {
      _logger.w('Error resolving local thumbnail preview mode: $e');
      _addToThumbnailModeCache(localPath, _LocalThumbnailPreviewMode.original);
      return _LocalThumbnailPreviewMode.original;
    }
  }

  // Get local image path based on type (thumbnail or page)
  Future<String?> _getLocalImagePath() async {
    if (widget.contentId == null) return null;

    String? localPath;

    if (widget.isThumbnail) {
      localPath = await LocalImagePreloader.getLocalThumbnailPath(
        widget.contentId!,
      );
      if (kDebugMode && localPath != null) {
        _logger.d('🖼️ Thumbnail found for ${widget.contentId}: $localPath');
      }
    } else if (widget.pageNumber != null) {
      localPath = await LocalImagePreloader.getLocalImagePath(
        widget.contentId!,
        widget.pageNumber!,
      );
      if (kDebugMode && localPath != null) {
        _logger.d(
          '📄 Page image found for ${widget.contentId} page ${widget.pageNumber}: $localPath',
        );
      }
    }

    return localPath;
  }

  // Build local file image
  Widget _buildLocalImage(String localPath) {
    if (kDebugMode) {
      _logger.d('📸 Using local image: $localPath');
    }

    if (widget.preferStaticPreview &&
        widget.isThumbnail &&
        _shouldUseStaticPreview(localPath)) {
      return _buildManagedLocalThumbnail(localPath);
    }

    Widget imageWidget = Image.file(
      File(localPath),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          _logger.e('❌ Error loading local image from $localPath: $error');
        }
        // If local file fails, fallback to network
        return _buildNetworkImage();
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _notifyImageLoaded();
          return child;
        }
        return _buildPlaceholder();
      },
    );

    // Apply border radius if specified
    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  bool _shouldUseStaticPreview(String localPath) {
    final lowered = localPath.toLowerCase();
    return lowered.endsWith('.gif') ||
        lowered.endsWith('.webp') ||
        lowered.endsWith('.avif');
  }

  static bool shouldUseStaticNetworkDecodeFallback(
    String networkUrl, {
    int? pageNumber,
    required bool isThumbnail,
  }) {
    if (!isThumbnail && pageNumber != null) {
      return false;
    }

    final uri = Uri.tryParse(networkUrl);
    if (uri == null) {
      return false;
    }

    final lowered = uri.path.toLowerCase();
    return lowered.endsWith('.webp') || lowered.endsWith('.avif');
  }

  Widget _buildManagedLocalThumbnail(String localPath) {
    return FutureBuilder<_LocalThumbnailPreviewMode>(
      future: _resolveLocalThumbnailPreviewMode(localPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ?? _buildPlaceholder();
        }

        switch (snapshot.data ?? _LocalThumbnailPreviewMode.original) {
          case _LocalThumbnailPreviewMode.animatedPlaceholder:
            return _buildThumbnailPlaceholder(
              icon: Icons.animation_rounded,
              label: 'ANIMATED',
            );
          case _LocalThumbnailPreviewMode.heavyPlaceholder:
            return _buildThumbnailPlaceholder(
              icon: Icons.photo_size_select_large_rounded,
              label: 'HEAVY',
            );
          case _LocalThumbnailPreviewMode.original:
            return _buildImageFile(localPath);
        }
      },
    );
  }

  Widget _buildThumbnailPlaceholder({
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: widget.borderRadius,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              icon,
              size: widget.isThumbnail ? 28 : 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 12,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyleConst.labelSmall.copyWith(
                      color: colorScheme.onSurface,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _isAnimatedLocalThumbnail({
    required String localPath,
    required File file,
  }) async {
    final lowered = localPath.toLowerCase();
    if (lowered.endsWith('.gif')) {
      return true;
    }

    if (!lowered.endsWith('.webp')) {
      return false;
    }

    try {
      final raf = await file.open();
      try {
        final length = await raf.length();
        final sampleLength = length < 64 ? length : 64;
        final bytes = await raf.read(sampleLength);
        return _looksLikeAnimatedWebP(bytes);
      } finally {
        await raf.close();
      }
    } catch (e) {
      _logger.w('Error probing local thumbnail animation state: $e');
      return false;
    }
  }

  bool _looksLikeAnimatedWebP(List<int> bytes) {
    if (bytes.length < 21) {
      return false;
    }

    if (!_matchesBytes(bytes, 0, const <int>[0x52, 0x49, 0x46, 0x46]) ||
        !_matchesBytes(bytes, 8, const <int>[0x57, 0x45, 0x42, 0x50])) {
      return false;
    }

    if (!_matchesBytes(bytes, 12, const <int>[0x56, 0x50, 0x38, 0x58])) {
      return false;
    }

    return (bytes[20] & 0x02) != 0;
  }

  bool _matchesBytes(List<int> bytes, int offset, List<int> expected) {
    if (bytes.length < offset + expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index++) {
      if (bytes[offset + index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  Widget _buildImageFile(String filePath) {
    Widget imageWidget = Image.file(
      File(filePath),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.memCacheWidth, //  downsample for grid thumbs
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget ?? _buildErrorWidget(),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _notifyImageLoaded();
          return child;
        }
        return widget.placeholder ?? _buildPlaceholder();
      },
    );

    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  // Build network image with caching
  Widget _buildNetworkImage({String? forceUrl}) {
    // Check for fallback URLs separated by pipe
    final targetUrl = forceUrl ?? widget.networkUrl;
    final urlParts = targetUrl.split('|');
    final primaryUrl = urlParts[0];
    // Blank URL can never load: skip CachedNetworkImage entirely so we don't
    // park a perpetual shimmer ticker (battery + pumpAndSettle hangs).
    if (primaryUrl.trim().isEmpty) {
      return widget.errorWidget ?? _buildErrorWidget();
    }
    final fallbackUrl = urlParts.length > 1 ? urlParts[1] : null;

    // Improved GIF detection to handle query parameters
    final uri = Uri.parse(primaryUrl);
    final isGif = uri.path.toLowerCase().endsWith('.gif');

    if (isGif) {
      // Use efficient cached/processed GIF handling
      return FutureBuilder<File?>(
        future: _memoizedGifProcess(primaryUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return widget.placeholder ?? _buildPlaceholder();
          }
          if (snapshot.hasError || snapshot.data == null) {
            if (kDebugMode) {
              _logger.e(
                '❌ Error loading GIF as static image: ${snapshot.error}',
              );
            }
            if (fallbackUrl != null) {
              return _buildNetworkImage(forceUrl: fallbackUrl);
            }
            return widget.errorWidget ?? _buildErrorWidget();
          }

          _notifyImageLoaded();
          final imageWidget = Image.file(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (context, error, stackTrace) {
              if (fallbackUrl != null) {
                return _buildNetworkImage(forceUrl: fallbackUrl);
              }
              return widget.errorWidget ?? _buildErrorWidget();
            },
          );

          if (widget.borderRadius != null) {
            return ClipRRect(
              borderRadius: widget.borderRadius!,
              child: imageWidget,
            );
          }
          return imageWidget;
        },
      );
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: primaryUrl,
      cacheKey: _networkCacheKey(urlToHash: primaryUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: widget.memCacheWidth ?? (widget.isThumbnail ? 400 : 800),
      memCacheHeight:
          widget.memCacheHeight ?? (widget.isThumbnail ? 600 : 1200),
      placeholder: (context, url) => widget.placeholder ?? _buildPlaceholder(),
      imageBuilder: (context, imageProvider) => Image(
        image: imageProvider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            _notifyImageLoaded();
            return child;
          }
          return widget.placeholder ?? _buildPlaceholder();
        },
      ),
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          _logger.w('Network image load failed for $url: $error');
        }

        // If primary fails and we have a fallback URL, retry with fallback
        if (fallbackUrl != null) {
          if (kDebugMode) {
            _logger.w('🔄 Falling back to secondary network URL: $fallbackUrl');
          }
          return _buildNetworkImage(forceUrl: fallbackUrl);
        }

        if (shouldUseStaticNetworkDecodeFallback(
          url,
          pageNumber: widget.pageNumber,
          isThumbnail: widget.isThumbnail,
        )) {
          return _buildStaticNetworkDecodeFallback(primaryUrl);
        }

        return widget.errorWidget ?? _buildErrorWidget();
      },
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
      httpHeaders: widget.httpHeaders,
    );

    // Apply border radius if specified
    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildStaticNetworkDecodeFallback(String url) {
    return FutureBuilder<File?>(
      future: _memoizedStaticProcess(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ?? _buildPlaceholder();
        }

        final file = snapshot.data;
        if (snapshot.hasError || file == null) {
          if (kDebugMode) {
            _logger.e(
              'Static network decode fallback failed for $url: ${snapshot.error}',
            );
          }
          return widget.errorWidget ?? _buildErrorWidget();
        }

        if (kDebugMode) {
          _logger.d(
            'Using static network decode fallback for $url: ${file.path}',
          );
        }
        return _buildImageFile(file.path);
      },
    );
  }

  // Static waiting-Kuro over a shimmer wash (no tickers: grid cells each
  // cost an AnimationController pair, jank on scroll). Custom `placeholder`
  // callers override this per-card; prefer KuroThumbPlaceholder there too.
  Widget _buildPlaceholder() {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: KuroThumbPlaceholder(borderRadius: widget.borderRadius),
    );
  }

  // Build error widget
  Widget _buildErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: widget.borderRadius,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: widget.isThumbnail ? 24 : 32,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          if (!widget.isThumbnail) ...[
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.imageNotAvailable ??
                  AppLocalizations.of(context)!.imageNotAvailable,
              style: TextStyleConst.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// Specialized Progressive Image Widget for Reader Screen
// Optimized for full-screen reading with enhanced local file support
class ProgressiveReaderImageWidget extends StatefulWidget {
  const ProgressiveReaderImageWidget({
    super.key,
    required this.networkUrl,
    required this.contentId,
    required this.pageNumber,
    this.fit = BoxFit.contain,
    this.height,
    this.onLoadingStateChange,
  });

  final String networkUrl;
  final String contentId;
  final int pageNumber;
  final BoxFit fit;
  final double? height;
  final void Function(bool isLoading)? onLoadingStateChange;

  @override
  State<ProgressiveReaderImageWidget> createState() =>
      _ProgressiveReaderImageWidgetState();
}

class _ProgressiveReaderImageWidgetState
    extends State<ProgressiveReaderImageWidget> {
  static final Logger _logger = getIt<Logger>();
  late final ImageCacheService _imageCacheService;
  String? _cachedLocalPath;
  bool _isLocalPathResolved = false;
  Size? _imageSize; // Store original image dimensions

  @override
  void initState() {
    super.initState();
    // Get ImageCacheService from service locator
    _imageCacheService = getIt<ImageCacheService>();
    _resolveLocalPath();
  }

  @override
  void didUpdateWidget(ProgressiveReaderImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-resolve if content or page changed
    if (oldWidget.contentId != widget.contentId ||
        oldWidget.pageNumber != widget.pageNumber) {
      _cachedLocalPath = null;
      _isLocalPathResolved = false;
      _resolveLocalPath();
    }
  }

  Future<void> _resolveLocalPath() async {
    widget.onLoadingStateChange?.call(true);

    if (kDebugMode) {
      _logger.i(
        '🖼️ READER IMAGE DEBUG: Resolving contentId: ${widget.contentId}, pageNumber: ${widget.pageNumber}',
      );
      _logger.d('🌐 Network URL: ${widget.networkUrl}');
    }

    // Check for fallback URLs separated by pipe
    final urlParts = widget.networkUrl.split('|');
    final primaryUrl = urlParts[0];

    // Priority 1: Check ImageCacheService (memory + disk cache with TTL)
    final cachedImage = await _imageCacheService.getCachedImage(primaryUrl);
    if (cachedImage != null) {
      if (kDebugMode) {
        _logger.d(
          'Reader: ✅ Found cached image in ImageCacheService: ${cachedImage.path}',
        );
      }

      if (mounted) {
        setState(() {
          _cachedLocalPath = cachedImage.path;
          _isLocalPathResolved = true;
        });
        widget.onLoadingStateChange?.call(false);
      }
      return;
    }

    // ✅ CHECK FOR DIRECT FILE PATH
    // If the "networkUrl" is actually a local path, use it directly
    if (!widget.networkUrl.startsWith('http') &&
        (widget.networkUrl.startsWith('/') ||
            widget.networkUrl.startsWith('file://'))) {
      final path = widget.networkUrl.replaceFirst('file://', '');
      final file = File(path);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _cachedLocalPath = path;
            _isLocalPathResolved = true;
          });
          widget.onLoadingStateChange?.call(false);
        }
        return;
      }
    }

    // Priority 2: Check LocalImagePreloader (downloaded content)
    final localPath = await LocalImagePreloader.getLocalImagePath(
      widget.contentId,
      widget.pageNumber,
    );

    if (localPath != null) {
      // Found local image
      if (kDebugMode) {
        _logger.d('Reader: ✅ Found local image at: $localPath');
      }

      if (mounted) {
        setState(() {
          _cachedLocalPath = localPath;
          _isLocalPathResolved = true;
        });
        widget.onLoadingStateChange?.call(false);
      }
      return;
    }

    // Priority 3: Download and cache using LocalImagePreloader
    if (kDebugMode) {
      _logger.d(
        'Reader: 📥 No local image found, downloading and caching: $primaryUrl',
      );
    }

    final cachedPath = await LocalImagePreloader.downloadAndCacheImage(
      widget.networkUrl,
      widget.contentId,
      widget.pageNumber,
    );

    if (cachedPath != null) {
      if (kDebugMode) {
        _logger.d('Reader: ✅ Successfully cached image at: $cachedPath');
      }

      // Also cache in ImageCacheService for future fast access
      try {
        final imageBytes = await File(cachedPath).readAsBytes();
        await _imageCacheService.cacheImage(widget.networkUrl, imageBytes);
        if (kDebugMode) {
          _logger.d('Reader: ✅ Also cached in ImageCacheService');
        }
      } catch (e) {
        if (kDebugMode) {
          _logger.w('Reader: ⚠️ Failed to cache in ImageCacheService: $e');
        }
      }

      if (mounted) {
        setState(() {
          _cachedLocalPath = cachedPath;
          _isLocalPathResolved = true;
        });
        widget.onLoadingStateChange?.call(false);
      }
    } else {
      // Cache failed, will fallback to network
      if (kDebugMode) {
        _logger.d(
          'Reader: ❌ Failed to cache image, will use network: ${widget.networkUrl}',
        );
      }

      if (mounted) {
        setState(() {
          _cachedLocalPath = null;
          _isLocalPathResolved = true;
        });
        widget.onLoadingStateChange?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show placeholder while resolving local path
    if (!_isLocalPathResolved) {
      return _buildReaderPlaceholder(context);
    }

    // Use cached local path if available
    if (_cachedLocalPath != null) {
      return _buildLocalImageWithDynamicSize(_cachedLocalPath!);
    }

    // Fallback to network
    if (kDebugMode) {
      _logger.d(
        'Reader: 📡 Falling back to network image: ${widget.networkUrl}',
      );
    }
    return _buildNetworkImageWithDynamicSize(context);
  }

  // Build network image with dynamic sizing
  Widget _buildNetworkImageWithDynamicSize(
    BuildContext context, {
    String? forceUrl,
  }) {
    final targetUrl = forceUrl ?? widget.networkUrl;
    final urlParts = targetUrl.split('|');
    final primaryUrl = urlParts[0];
    final fallbackUrl = urlParts.length > 1 ? urlParts[1] : null;

    if (kDebugMode) {
      _logger.d(
        '📡 Loading reader image with dynamic sizing for page ${widget.pageNumber}: $primaryUrl',
      );
    }

    // Use unique cache key combining contentId and pageNumber to prevent cache collision
    final uniqueCacheKey =
        '${widget.contentId}_page_${widget.pageNumber}_${primaryUrl.hashCode}';

    return CachedNetworkImage(
      key: ValueKey(uniqueCacheKey),
      imageUrl: primaryUrl,
      cacheKey: uniqueCacheKey, // Force unique cache per page
      fit: BoxFit.none, // Use BoxFit.none for custom sizing
      width: _getDisplaySize().width,
      height: _getDisplaySize().height,
      memCacheWidth: 800,
      memCacheHeight: 1200,
      placeholder: (context, url) => _buildReaderPlaceholder(context),
      errorWidget: (context, url, error) {
        if (fallbackUrl != null) {
          if (kDebugMode) {
            _logger.w(
              '🔄 Reader falling back to secondary network URL: $fallbackUrl',
            );
          }
          return _buildNetworkImageWithDynamicSize(
            context,
            forceUrl: fallbackUrl,
          );
        }
        return _buildReaderErrorWidget(context);
      },
      fadeInDuration: DesignTokens.durationPageTurn,
      // Cache image in ImageCacheService when loaded
      imageBuilder: (context, imageProvider) {
        // Listen to image stream to get dimensions
        final imageStream = imageProvider.resolve(ImageConfiguration.empty);
        imageStream.addListener(ImageStreamListener(_calculateImageSize));

        // Cache the image data in ImageCacheService for future use
        _cacheNetworkImage(primaryUrl);
        return Image(
          image: imageProvider,
          fit: BoxFit.fitWidth,
          width: _getDisplaySize().width,
          height: _getDisplaySize().height,
        );
      },
    );
  }

  // Build local image with dynamic sizing
  Widget _buildLocalImageWithDynamicSize(String localPath) {
    final imageProvider = FileImage(File(localPath));

    // Listen to image stream to get dimensions
    final imageStream = imageProvider.resolve(ImageConfiguration.empty);
    imageStream.addListener(ImageStreamListener(_calculateImageSize));

    return Image(
      image: imageProvider,
      fit: BoxFit.fitWidth, // Use BoxFit.none for custom sizing
      width: _getDisplaySize().width,
      height: _getDisplaySize().height,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          _logger.e(
            'Reader: ❌ Error loading local image from $localPath: $error',
          );
        }
        // Fallback to network if local file fails
        return _buildNetworkImageWithDynamicSize(context);
      },
    );
  }

  // Cache network image in ImageCacheService for future fast access
  Future<void> _cacheNetworkImage(String url) async {
    try {
      // Only cache if not already cached
      final isCached = await _imageCacheService.isImageCached(url);
      if (!isCached) {
        // Download and cache the image
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', 'AppleWebKit/537.36');
        request.headers.set('Referer', 'https://nhentai.net/');

        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = <int>[];
          await for (var chunk in response) {
            bytes.addAll(chunk);
          }

          await _imageCacheService.cacheImage(url, bytes);
          if (kDebugMode) {
            _logger.d(
              'Reader: ✅ Cached network image in ImageCacheService: $url',
            );
          }
        }
        httpClient.close();
      }
    } catch (e) {
      if (kDebugMode) {
        _logger.w('Reader: ⚠️ Failed to cache network image: $e');
      }
    }
  }

  // Calculate dynamic size for the image based on its dimensions
  void _calculateImageSize(ImageInfo imageInfo, bool synchronousCall) {
    final imageSize = Size(
      imageInfo.image.width.toDouble(),
      imageInfo.image.height.toDouble(),
    );

    if (_imageSize != imageSize) {
      setState(() {
        _imageSize = imageSize;
      });

      if (kDebugMode) {
        _logger.d(
          'Reader: 📏 Image size: ${imageInfo.image.width}x${imageInfo.image.height}, '
          'No scaling applied',
        );
      }
    }
  }

  // Get the display size for the image
  Size _getDisplaySize() {
    if (_imageSize == null) {
      // Fallback to screen size if dimensions not available
      final screenSize = MediaQuery.of(context).size;
      return Size(screenSize.width, screenSize.height * 0.8);
    }

    return Size(
      _imageSize!.width,
      _imageSize!.height,
    ); // Original size, no scaling
  }

  Widget _buildReaderPlaceholder(BuildContext context) {
    return SizedBox(
      height: widget.height ?? MediaQuery.of(context).size.height * 0.8,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.loadingPage(widget.pageNumber) ??
                AppLocalizations.of(context)!
                    .loadingPageNumber(widget.pageNumber),
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderErrorWidget(BuildContext context) {
    return SizedBox(
      height: widget.height ?? MediaQuery.of(context).size.height * 0.5,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.failedToLoadPage(widget.pageNumber),
            style: TextStyleConst.bodyLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.checkInternetConnection ??
                AppLocalizations.of(context)!.checkInternetConnection,
            style: TextStyleConst.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Specialized Progressive Image Widget for Thumbnails/Cards
// Optimized for grid view with enhanced caching
class ProgressiveThumbnailWidget extends StatelessWidget {
  const ProgressiveThumbnailWidget({
    super.key,
    required this.networkUrl,
    this.contentId,
    this.aspectRatio = 0.7,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.showOfflineIndicator = false,
    this.httpHeaders,
    this.preferStaticPreview = false,
  });

  final String networkUrl;
  final String? contentId;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final bool showOfflineIndicator;
  final Map<String, String>? httpHeaders;
  final bool preferStaticPreview;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        children: [
          ProgressiveImageWidget(
            networkUrl: networkUrl,
            contentId: contentId,
            isThumbnail: true,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            borderRadius: borderRadius,
            memCacheWidth: 400,
            memCacheHeight: 600,
            httpHeaders: httpHeaders,
            preferStaticPreview: preferStaticPreview,
          ),

          // Offline indicator overlay
          if (showOfflineIndicator && contentId != null)
            FutureBuilder<bool>(
              future: LocalImagePreloader.isContentDownloaded(contentId!),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.scrim
                                .withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.download_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onTertiary,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }
}
