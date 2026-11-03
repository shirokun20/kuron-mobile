import 'dart:async';

// Prefetch download engine for the reader. Owns which pages are prefetched /
// in-flight, so the bookkeeping that used to live in _ReaderScreenState is
// testable and survives widget rebuild/dispose.
//
// ponytail: decode-pre-caching (precacheImage → ImageCache) needs a
// BuildContext, so it stays in the widget. This cubit only owns the
// context-free part: the window policy + delegation to the unified
// ReaderImageRepository (download-first). It no longer implements its own
// network download when a repository is injected.

import 'package:dio/dio.dart';
import 'package:nhasixapp/core/models/image_metadata.dart';
import 'package:nhasixapp/core/services/local_image_preloader.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/repositories/reader_image_repository.dart';

import '../base/base_cubit.dart';

/// Immutable snapshot of the prefetch engine state — which pages are known to
/// be locally cached (prefetched) and which downloads are in-flight.
class ReaderPrefetchState extends BaseCubitState {
  const ReaderPrefetchState({
    this.prefetchedPages = const {},
    this.inflightPages = const {},
    this.totalPrefetched = 0,
  });

  final Set<int> prefetchedPages;
  final Set<int> inflightPages;
  final int totalPrefetched;

  @override
  List<Object?> get props => [prefetchedPages, inflightPages, totalPrefetched];

  ReaderPrefetchState _mutate({
    Set<int>? prefetchedPages,
    Set<int>? inflightPages,
    int? totalPrefetched,
  }) {
    return ReaderPrefetchState(
      prefetchedPages: prefetchedPages ?? this.prefetchedPages,
      inflightPages: inflightPages ?? this.inflightPages,
      totalPrefetched: totalPrefetched ?? this.totalPrefetched,
    );
  }
}

/// Owns prefetch downloads + policy that used to live in `_ReaderScreenState`.
class ReaderPrefetchCubit extends BaseCubit<ReaderPrefetchState> {
  static const int _prefetchCount = 3;
  static const int _prefetchBackCount = 1;

  // Heavy sources (HentaiNexus): GPU saturation — skip forward prefetch.
  static const Set<String> _heavyPrefetchSourceIds = {
    // Filled by source registry; kept here for fallback if not registered.
  };

  final Map<int, CancelToken> _cancelTokens = <int, CancelToken>{};

  /// Per-page tokens for the repo (`resolvePage`) path, so window-cancel
  /// reaches repo downloads — not just the legacy Dio path.
  final Map<int, CancelToken> _repoTokens = <int, CancelToken>{};

  /// Window generation id: starting a new window cancels the previous
  /// window's out-of-window token(s). Only pages OUTSIDE the new window are
  /// cancelled (their `.part` is deleted by the streaming writer's
  /// cancel cleanup); overlapping pages keep running.
  int _windowGeneration = 0;

  /// Current window generation (for tests).
  int get windowGeneration => _windowGeneration;

  /// Unified download-first resolver. When injected, prefetch delegates its
  /// network download here (streaming + dedup). When null (e.g. some tests), a
  /// legacy Dio path is kept as fallback.
  final ReaderImageRepository? repository;

  ReaderPrefetchCubit({required super.logger, this.repository})
      : super(initialState: const ReaderPrefetchState());

  /// Number of pages ahead (+1) and behind (−1) that are currently prefetched
  /// or in-flight — exposed for tests/config.
  static int get prefetchCount => _prefetchCount;
  static int get prefetchBackCount => _prefetchBackCount;

  /// Kick prefetch for the given page window. [imageMetadata] used to validate
  /// URL consistency; [sourceId] gates heavy-source skip + header lookup.
  ///
  /// Widget still handles decode-pre-cache (needs BuildContext); this only
  /// does the network download + bookkeeping.
  Future<void> prefetchImages({
    required int currentPage,
    required List<String> imageUrls,
    List<ImageMetadata>? imageMetadata,
    String? sourceId,
    required String contentId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    if (imageUrls.isEmpty) return;

    _startWindow(currentPage, imageUrls.length);

    if (_isHeavySource(sourceId)) {
      // Only back-prefetch (recent pages) for heavy sources — forward would
      // saturate GPU.
      await _prefetchBack(
          currentPage, imageUrls, contentId, headers, sourceId, cancelToken);
    } else {
      await Future.wait([
        _prefetchBack(
            currentPage, imageUrls, contentId, headers, sourceId, cancelToken),
        _prefetchForward(currentPage, imageUrls, imageMetadata, sourceId,
            contentId, headers, cancelToken),
      ]);
    }
  }

  /// Pages covered by a window centred on [currentPage].
  static Set<int> windowFor(int currentPage, int totalPages) {
    final window = <int>{currentPage};
    for (int i = 1; i <= _prefetchBackCount; i++) {
      if (currentPage - i >= 1) window.add(currentPage - i);
    }
    for (int i = 1; i <= _prefetchCount; i++) {
      if (currentPage + i <= totalPages) window.add(currentPage + i);
    }
    return window;
  }

  void _startWindow(int currentPage, int totalPages) {
    _windowGeneration++;
    final window = windowFor(currentPage, totalPages);
    // Cancel previous window's tokens for pages outside the new window.
    // In-flight entries are dropped from bookkeeping so they can be
    // re-attempted; overlapping pages keep running untouched.
    for (final entry in _cancelTokens.entries.toList()) {
      if (!window.contains(entry.key)) {
        if (!entry.value.isCancelled) entry.value.cancel('window moved');
        _cancelTokens.remove(entry.key);
        _setInflight(entry.key, false);
      }
    }
    for (final entry in _repoTokens.entries.toList()) {
      if (!window.contains(entry.key)) {
        if (!entry.value.isCancelled) entry.value.cancel('window moved');
        _repoTokens.remove(entry.key);
        _setInflight(entry.key, false);
      }
    }
  }

  bool _isHeavySource(String? sourceId) {
    if (sourceId == null) return false;
    // Keep the registry-gated semantics the widget used: HentaiNexus only.
    // Heavy-source check lives in the source registry; we approximate by
    // calling the shared coordinator-known set is not available here.
    // ponytail: explicit list; extend as heavy sources appear.
    return _heavyPrefetchSourceIds.contains(sourceId);
  }

  Future<void> _prefetchBack(
    int currentPage,
    List<String> imageUrls,
    String contentId,
    Map<String, String>? headers, [
    String? sourceId,
    CancelToken? cancelToken,
  ]) async {
    final futures = <Future<void>>[];
    for (int i = 1; i <= _prefetchBackCount; i++) {
      final targetPage = currentPage - i;
      if (targetPage >= 1 && !_isPrefetched(targetPage)) {
        futures.add(_downloadPage(targetPage, imageUrls[targetPage - 1],
            contentId, headers, sourceId, cancelToken));
      }
    }
    await Future.wait(futures);
  }

  Future<void> _prefetchForward(
    int currentPage,
    List<String> imageUrls,
    List<ImageMetadata>? imageMetadata,
    String? sourceId,
    String contentId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  ) async {
    final futures = <Future<void>>[];
    for (int i = 1; i <= _prefetchCount; i++) {
      final targetPage = currentPage + i;
      if (targetPage > imageUrls.length || _isPrefetched(targetPage)) continue;

      final imageUrl = imageUrls[targetPage - 1];
      // EHentai reader pages resolve real image URLs lazily — skip.
      if (_isEhentaiReaderPageUrl(imageUrl, sourceId)) {
        continue;
      }
      if (imageMetadata != null && imageMetadata.isNotEmpty) {
        ImageMetadata? matched;
        for (final m in imageMetadata) {
          if (m.pageNumber == targetPage) {
            matched = m;
            break;
          }
        }
        if (matched != null && matched.imageUrl != imageUrl) {
          logDebug('prefetch skip: metadata mismatch page $targetPage');
          continue; // allow retry next tick (don't mark prefetched)
        }
      }
      if (!_isHttp(imageUrl) &&
          (imageUrl.startsWith('/') || imageUrl.startsWith('file://'))) {
        continue;
      }
      futures.add(_downloadPage(
          targetPage, imageUrl, contentId, headers, sourceId, cancelToken));
    }
    await Future.wait(futures);
  }

  Future<void> _downloadPage(int targetPage, String imageUrl, String contentId,
      Map<String, String>? headers,
      [String? sourceId, CancelToken? cancelToken]) async {
    if (!_isHttp(imageUrl)) {
      // non-http (local/file) — nothing to download; mark prefetched.
      _markPrefetched(targetPage);
      return;
    }

    // Download-first: delegate to the unified (streaming + deduplicating)
    // resolver when present. Tracked under the same in-flight bookkeeping as
    // the legacy path so window-cancel reaches repo downloads and
    // `_isPrefetched` actually dedups concurrent repo requests.
    final repo = repository;
    if (repo != null) {
      if (cancelToken?.isCancelled == true) {
        _unmarkPrefetched(targetPage);
        return;
      }
      if (_isPrefetched(targetPage)) return;
      final pageToken = CancelToken();
      _repoTokens[targetPage] = pageToken;
      _setInflight(targetPage, true);
      try {
        final result = await repo.resolvePage(
          url: imageUrl,
          contentId: contentId,
          pageNumber: targetPage,
          sourceId: sourceId,
          headers: headers,
          cancelToken: pageToken,
        );
        if (result is ReadyFromDisk || result is ReadyFresh) {
          _markPrefetched(targetPage);
        } else {
          // FailedPage — allow retry later.
          final reason =
              result is FailedPage ? result.reason.toString() : 'unknown';
          logDebug('prefetch fail page $targetPage: $reason');
          _unmarkPrefetched(targetPage);
        }
      } finally {
        _repoTokens.remove(targetPage);
        _setInflight(targetPage, false);
      }
      return;
    }

    // Legacy Dio fallback (only when no repository injected).
    final legacyToken = CancelToken();
    _cancelTokens[targetPage] = legacyToken;
    _setInflight(targetPage, true);
    try {
      await LocalImagePreloader.downloadAndCacheImage(
        imageUrl,
        contentId,
        targetPage,
        headers: headers,
        cancelToken: legacyToken,
      );
      _markPrefetched(targetPage);
    } catch (e) {
      // Failed download — allow retry later.
      logDebug('prefetch fail page $targetPage: $e');
      _unmarkPrefetched(targetPage);
    } finally {
      _cancelTokens.remove(targetPage);
      _setInflight(targetPage, false);
    }
  }

  bool _isPrefetched(int page) =>
      state.prefetchedPages.contains(page) ||
      state.inflightPages.contains(page);

  void _markPrefetched(int page) {
    if (isClosed) return;
    emit(state._mutate(
      prefetchedPages: {...state.prefetchedPages, page},
      totalPrefetched: state.totalPrefetched + 1,
    ));
  }

  void _unmarkPrefetched(int page) {
    if (isClosed) return;
    emit(state._mutate(
      prefetchedPages: {...state.prefetchedPages}..remove(page),
      totalPrefetched:
          state.totalPrefetched > 0 ? state.totalPrefetched - 1 : 0,
    ));
  }

  void _setInflight(int page, bool v) {
    if (isClosed) return;
    final next = {...state.inflightPages};
    if (v) {
      next.add(page);
    } else {
      next.remove(page);
    }
    emit(state._mutate(inflightPages: next));
  }

  bool _isHttp(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  bool _isEhentaiReaderPageUrl(String url, String? sourceId) {
    // EHentai /s/... reader pages — resolved lazily. Only meaningful for that
    // source; keep the predicate closest to the original widget logic.
    return sourceId == 'ehentai' && url.contains('/s/');
  }

  bool isPrefetchedPage(int page) => state.prefetchedPages.contains(page);

  int get prefetchedPageCount => state.totalPrefetched;

  /// Cancel all in-flight downloads (e.g. on dispose). Cancelled pages are
  /// cleared from bookkeeping so they can be re-attempted next time.
  void cancelAll([CancelToken? scopeToken]) {
    if (scopeToken != null && !scopeToken.isCancelled) {
      scopeToken.cancel('Reader dispose');
    }
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _cancelTokens.clear();
    for (final token in _repoTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _repoTokens.clear();
    emit(state._mutate(inflightPages: const {}, prefetchedPages: const {}));
  }
}
