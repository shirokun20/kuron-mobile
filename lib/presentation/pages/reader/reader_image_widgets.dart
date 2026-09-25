part of 'reader_screen.dart';

// ───── AI translation: image download headers ─────

/// Resolves the download headers (referer/cookie/user-agent) for a page image
/// from its source. Plain requests are rejected by most sources — the
/// translation pipeline MUST reuse the reader's header strategy.
Map<String, String>? _sourceImageHeaders(String? sourceId, String imageUrl) {
  if (sourceId == null || sourceId.trim().isEmpty) return null;
  return getIt<ContentSourceRegistry>()
      .getSource(sourceId)
      ?.getImageDownloadHeaders(imageUrl: imageUrl);
}

// ───── _ReaderImageViewer ─────

class _ReaderImageViewer extends StatelessWidget {
  const _ReaderImageViewer({
    required this.imageUrl,
    required this.pageNumber,
    required this.contentId,
    required this.visiblePageNotifier,
    required this.cubit,
    this.isContinuous = false,
    this.enableZoom,
    this.sourceId,
    this.resolvedHeight,
    this.onHeavyImageDetected,
    this.onRepairBrokenImage,
    this.onOpenSourcePageForRepair,
    this.onContinuousImageLoaded,
  });

  final String imageUrl;
  final int pageNumber;
  final String contentId;
  final bool isContinuous;
  final bool? enableZoom;
  final String? sourceId;
  final ValueNotifier<int> visiblePageNotifier;
  final ReaderCubit cubit;
  final double? resolvedHeight;
  final VoidCallback? onHeavyImageDetected;
  final Future<bool> Function(int pageNumber)? onRepairBrokenImage;
  final Future<bool> Function(int pageNumber)? onOpenSourcePageForRepair;
  final void Function(int page, Size imageSize)? onContinuousImageLoaded;

  bool _canRepair({required String imageUrl, required String? sourceId}) {
    if (!cubit.networkCubit.isConnected) return false;
    if (sourceId == null || sourceId.trim().isEmpty) return false;
    if (getIt<ContentSourceRegistry>().getSource(sourceId) == null) {
      return false;
    }
    if (OfflineContentManager.isFailedPagePlaceholder(imageUrl)) {
      final originalUrl =
          OfflineContentManager.extractOriginalUrlFromPlaceholder(imageUrl);
      return originalUrl != null && originalUrl.trim().isNotEmpty;
    }
    if (!imageUrl.startsWith('/') && !imageUrl.startsWith('file://')) {
      return false;
    }
    return isLocalReaderImagePath(normalizeLocalReaderImagePath(imageUrl));
  }

  bool _canOpenSourcePage(
      {required String imageUrl, required String? sourceId}) {
    if (!_canRepair(imageUrl: imageUrl, sourceId: sourceId)) return false;
    final rawConfig = sourceId == null || sourceId.trim().isEmpty
        ? null
        : getIt<RemoteConfigService>().getRawConfig(sourceId);
    return supportsSourcePageManualRepair(rawConfig);
  }

  Map<String, String>? _headers(String? sourceId, String imageUrl) =>
      _sourceImageHeaders(sourceId, imageUrl);

  Map<String, dynamic>? _rawConfig(String? sourceId) {
    if (sourceId == null || sourceId.trim().isEmpty) return null;
    return getIt<RemoteConfigService>().getRawConfig(sourceId);
  }

  @override
  Widget build(BuildContext context) {
    if (OfflineContentManager.isFailedPagePlaceholder(imageUrl)) {
      final originalUrl =
          OfflineContentManager.extractOriginalUrlFromPlaceholder(imageUrl);
      return _FailedPageCard(
        pageNumber: pageNumber,
        canRetry: originalUrl != null && originalUrl.trim().isNotEmpty,
        onRetry: () => onRepairBrokenImage?.call(pageNumber),
      );
    }

    final grayscale = context.read<ThemeCubit>().currentTheme == 'note' ||
        context.read<ThemeCubit>().currentTheme == 'note_dark';

    if (isContinuous) {
      final zoom = enableZoom ?? true;
      return RepaintBoundary(
        child: SizedBox(
          key: ValueKey('image_viewer_$pageNumber'),
          height: resolvedHeight,
          child: Padding(
            padding: const EdgeInsets.only(
                bottom: ReaderScreen.kReaderContinuousGap),
            child: ExtendedImageReaderWidget(
              imageUrl: imageUrl,
              contentId: contentId,
              pageNumber: pageNumber,
              readingMode: ReadingMode.continuousScroll,
              sourceId: sourceId,
              sourceRawConfig: _rawConfig(sourceId),
              httpHeaders: _headers(sourceId, imageUrl),
              enableZoom: zoom,
              visiblePageNotifier: visiblePageNotifier,
              grayscale: grayscale,
              onHeavyImageDetected: onHeavyImageDetected,
              onRepairBrokenImage:
                  _canRepair(imageUrl: imageUrl, sourceId: sourceId)
                      ? () =>
                          onRepairBrokenImage?.call(pageNumber) ??
                          Future.value(false)
                      : null,
              onOpenSourcePageForRepair:
                  _canOpenSourcePage(imageUrl: imageUrl, sourceId: sourceId)
                      ? () =>
                          onOpenSourcePageForRepair?.call(pageNumber) ??
                          Future.value(false)
                      : null,
              onImageLoaded: onContinuousImageLoaded ?? cubit.onImageLoaded,
            ),
          ),
        ),
      );
    }

    return BlocBuilder<ReaderCubit, ReaderState>(
      builder: (context, state) {
        final zoom = enableZoom ?? state.enableZoom ?? true;
        final resolvedSourceId = sourceId ?? state.content?.sourceId;
        return RepaintBoundary(
          child: ExtendedImageReaderWidget(
            imageUrl: imageUrl,
            contentId: contentId,
            pageNumber: pageNumber,
            readingMode: state.readingMode ?? ReadingMode.singlePage,
            sourceId: resolvedSourceId,
            sourceRawConfig: _rawConfig(resolvedSourceId),
            httpHeaders: _headers(resolvedSourceId, imageUrl),
            enableZoom: zoom,
            visiblePageNotifier: visiblePageNotifier,
            grayscale: grayscale,
            onDoubleTapGesture: () => cubit.toggleUI(),
            onRepairBrokenImage: _canRepair(
                    imageUrl: imageUrl, sourceId: resolvedSourceId)
                ? () =>
                    onRepairBrokenImage?.call(pageNumber) ?? Future.value(false)
                : null,
            onOpenSourcePageForRepair: _canOpenSourcePage(
                    imageUrl: imageUrl, sourceId: resolvedSourceId)
                ? () =>
                    onOpenSourcePageForRepair?.call(pageNumber) ??
                    Future.value(false)
                : null,
            onImageLoaded: cubit.onImageLoaded,
          ),
        );
      },
    );
  }
}
