// Page Resolution Pipeline (Section 5).
///
// Converts adapter-level chapter/image URL data into canonical
// [ResolvedChapterPages] that both the reader and the native download worker
// can consume without further parsing.
///
// The pipeline:
//   1. Accepts raw image URLs + global headers from an adapter.
//   2. Applies source-level header and referer rules from [NetworkRules].
//   3. Returns a [ResolvedChapterPages] with per-page [ResolvedPageRequest]s.
//   4. Performs download-readiness checks and attaches diagnostics.
///
// This is a pure-Dart component — no Flutter, no network access.
library;

import 'package:kuron_core/kuron_core.dart';

import '../config/typed_config/network_rules.dart';

// Input for a single pipeline resolution request.
class PageResolutionInput {
  const PageResolutionInput({
    required this.sourceId,
    required this.contentId,
    required this.imageUrls,
    this.chapterId,
    this.globalHeaders = const <String, String>{},
    this.referer,
    this.pageMimeHint,
    this.filenamePrefix,
    this.isExternalChapter = false,
  });

  final String sourceId;
  final String contentId;
  final String? chapterId;

  // Raw image URL list resolved by the adapter.
  final List<String> imageUrls;

  // Global headers the source declares for all requests.
  final Map<String, String> globalHeaders;

  // Primary referer to use when none is per-page.
  final String? referer;

  // Optional mime hint for all pages (e.g. `image/webp`).
  final String? pageMimeHint;

  // Optional filename prefix for download hints (e.g. `c001_`).
  final String? filenamePrefix;

  // True when the chapter is hosted externally (e.g. MangaDex externalUrl).
  // When true, the pipeline emits an `externalChapter` diagnostic instead of
  // treating empty imageUrls as a download failure.
  final bool isExternalChapter;
}

// Result of running the pipeline.
class PageResolutionResult {
  const PageResolutionResult({
    required this.pages,
    required this.diagnostics,
  });

  final ResolvedChapterPages pages;

  // Pipeline-level diagnostics (download readiness failures, warnings, etc.).
  final List<ValidationDiagnostic> diagnostics;

  bool get isDownloadReady => pages.isDownloadReady;
}

// Shared resolution pipeline.
///
// Keeps adapter entry points (REST / scraper) independent while routing
// their internal results through the same canonical representation used by
// the reader and the native download worker.
class PageResolutionPipeline {
  const PageResolutionPipeline({this._networkRules});

  final NetworkRules? _networkRules;

  // Resolve a list of raw image URLs into [ResolvedChapterPages].
  ///
  // - Merges [NetworkRules.staticHeaders] with per-request [input.globalHeaders]
  //   (per-request wins).
  // - All pages are produced as [PageRequestKind.directImage] since
  //   the URLs are already resolved by the adapter.
  // - Runs download-readiness checks and emits diagnostics for failures.
  PageResolutionResult resolve(PageResolutionInput input) {
    final List<ValidationDiagnostic> diags = <ValidationDiagnostic>[];

    // External chapters have no in-app images; emit a distinct diagnostic
    // so callers can distinguish "external" from "download failure".
    if (input.isExternalChapter) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.info,
        code: 'externalChapter',
        message:
            'Chapter ${input.chapterId ?? input.contentId} is hosted externally and cannot be downloaded in-app.',
        context: <String, Object?>{
          'chapterId': input.chapterId,
          'contentId': input.contentId,
        },
      ));
    }

    // Merge static config headers with adapter-supplied global headers.
    final Map<String, String> merged = <String, String>{
      ...?_networkRules?.staticHeaders,
      ...input.globalHeaders,
    };

    final String? referer =
        input.referer ?? _networkRules?.staticHeaders['Referer'];

    // Build per-page requests.
    final List<ResolvedPageRequest> pages = <ResolvedPageRequest>[];
    int pageNumber = 1;
    for (final String rawUrl in input.imageUrls) {
      // Strip fallback URL if present (e.g. url1|url2) so native OkHttp doesn't fail parsing.
      final String url =
          rawUrl.contains('|') ? rawUrl.split('|').first : rawUrl;
      final bool valid = url.isNotEmpty;
      if (!valid) {
        diags.add(ValidationDiagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'emptyImageUrl',
          message:
              'Page $pageNumber has an empty image URL and will be skipped.',
          context: <String, Object?>{'pageNumber': pageNumber},
        ));
      }
      pages.add(ResolvedPageRequest(
        pageNumber: pageNumber,
        kind: PageRequestKind.directImage,
        finalImageUrl: valid ? url : null,
        referer: referer,
        filenameHint: input.filenamePrefix != null
            ? '${input.filenamePrefix}${pageNumber.toString().padLeft(3, '0')}'
            : null,
        mimeHint: input.pageMimeHint,
      ));
      pageNumber++;
    }

    // Check download readiness.
    final List<ResolvedPageRequest> unresolved = pages
        .where((ResolvedPageRequest p) => !p.isDownloadReady)
        .toList(growable: false);
    if (unresolved.isNotEmpty) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'downloadNotReady',
        message: '${unresolved.length} of ${pages.length} pages are not '
            'download-ready (missing finalImageUrl).',
        context: <String, Object?>{
          'unreadyCount': unresolved.length,
          'totalCount': pages.length,
          'firstUnreadyPage':
              unresolved.isNotEmpty ? unresolved.first.pageNumber : null,
        },
      ));
    }

    // Emit parity diagnostic when reader could work but download cannot (5.5).
    if (pages.isNotEmpty && unresolved.length < pages.length) {
      final int readyCount = pages.length - unresolved.length;
      if (unresolved.isNotEmpty) {
        diags.add(ValidationDiagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'readerDownloadParity',
          message:
              '$readyCount pages are reader-ready but ${unresolved.length} '
              'are not download-ready. Reader will succeed but download will '
              'skip unresolved pages.',
          context: <String, Object?>{
            'readyCount': readyCount,
            'unreadyCount': unresolved.length,
          },
        ));
      }
    }

    final ResolvedChapterPages chapterPages = ResolvedChapterPages(
      sourceId: input.sourceId,
      contentId: input.contentId,
      chapterId: input.chapterId,
      globalHeaders: merged,
      referer: referer,
      pages: pages,
    );

    return PageResolutionResult(
      pages: chapterPages,
      diagnostics: diags,
    );
  }

  // Build a download-ready URL list from [ResolvedChapterPages].
  ///
  // Returns only pages that pass [ResolvedPageRequest.isDownloadReady], in
  // order. Each entry is the [ResolvedPageRequest.finalImageUrl].
  ///
  // This is the bridge to [NativeDownloadService.startDownload] which
  // currently expects `List<String> imageUrls`.
  List<String> toDownloadUrls(ResolvedChapterPages pages) {
    return pages.pages
        .where((ResolvedPageRequest p) => p.isDownloadReady)
        .map((ResolvedPageRequest p) => p.finalImageUrl!)
        .toList(growable: false);
  }

  // Build merged per-page headers for a specific page index.
  ///
  // Uses [ResolvedChapterPages.mergedPage] to combine global + per-page
  // headers. Returns the final header map the download worker should use.
  Map<String, String> headersForPage(ResolvedChapterPages pages, int index) {
    return pages.mergedPage(index).perPageHeaders;
  }
}
