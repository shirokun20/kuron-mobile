import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

// E-Hentai adapter that delegates generic scraping and adds per-page image
// extraction from reader links (`/s/{hash}/{gid}-{page}`).
class EHentaiScraperAdapter implements GenericAdapter {
  @override
  Duration get detailTimeout => _delegate.detailTimeout;

  static const String _partPrefix = '__ehpart__';
  static const String _chunkPrefix = '__ehchunk__';

  final Dio _dio;
  final GenericUrlBuilder _urlBuilder;
  final GenericHtmlParser _parser;
  final Logger _logger;
  final String _sourceId;
  final GenericScraperAdapter _delegate;
  final Map<String, String> _pageUrlCache = <String, String>{};
  RateLimiter? _rateLimiter;

  EHentaiScraperAdapter({
    required Dio dio,
    required GenericUrlBuilder urlBuilder,
    required GenericHtmlParser parser,
    required Logger logger,
    required String sourceId,
  })  : _dio = dio,
        _urlBuilder = urlBuilder,
        _parser = parser,
        _logger = logger,
        _sourceId = sourceId,
        _delegate = GenericScraperAdapter(
          dio: dio,
          urlBuilder: urlBuilder,
          parser: parser,
          logger: logger,
          sourceId: sourceId,
        );

  @override
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async =>
      const <Chapter>[];

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final resolvedQuery = _resolveSearchQuery(filter, rawConfig);
    final normalizedFilter = filter.copyWith(query: resolvedQuery);
    final searchContext = await _buildSearchContext(filter, rawConfig);

    var delegated = await _delegate.search(
      searchContext.filter,
      searchContext.config,
    );

    var enrichmentFilter = searchContext.filter;
    var enrichmentConfig = searchContext.config;

    // `next=` token pagination in query mode can intermittently return a 200
    // response with an empty list. Retry with the standard search URL format
    // as a safety fallback so UI does not get stuck on ContentEmpty.
    final isQueryPage = resolvedQuery.isNotEmpty && filter.page > 1;
    if (delegated.items.isEmpty && isQueryPage) {
      final fallback = await _delegate.search(normalizedFilter, rawConfig);
      if (fallback.items.isNotEmpty) {
        delegated = fallback;
        enrichmentFilter = normalizedFilter;
        enrichmentConfig = rawConfig;
      }
    }

    if (delegated.items.isEmpty) {
      return delegated;
    }

    // Extract covers and languages in single pass to avoid duplicate HTTP requests
    final combinedData = await _extractListCoversAndLanguages(
      filter: enrichmentFilter,
      rawConfig: enrichmentConfig,
      resolvedQuery: resolvedQuery,
    );
    if (combinedData.isEmpty) {
      return delegated;
    }

    final enriched = <Content>[];
    for (final current in delegated.items) {
      final data = combinedData[current.id] ?? {};
      final cover = (data['cover'] as String?) ?? '';
      final currentCover = current.coverUrl.trim();
      final needsFix = currentCover.isEmpty || currentCover.startsWith('data:');

      var updated = current;
      if (needsFix && cover.isNotEmpty) {
        updated = updated.copyWith(coverUrl: cover);
      }

      // Set language from home page tag if found
      final language = (data['language'] as String?);
      if (language != null && language.isNotEmpty) {
        updated = updated.copyWith(language: language);
      }

      // Set uploadDate from list posted date if available
      final postedDate = data['postedDate'] as DateTime?;
      if (postedDate != null) {
        updated = updated.copyWith(uploadDate: postedDate);
      }

      enriched.add(updated);
    }

    return AdapterSearchResult(
      items: enriched,
      hasNextPage: delegated.hasNextPage,
      totalPages: delegated.totalPages,
    );
  }

  Future<_SearchContext> _buildSearchContext(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final resolvedQuery = _resolveSearchQuery(filter, rawConfig);
    final isHomeMode = resolvedQuery.isEmpty && filter.includeTags.isEmpty;
    final isQueryMode = resolvedQuery.isNotEmpty;

    if ((!isHomeMode && !isQueryMode) || filter.page <= 1) {
      return _SearchContext(
        filter: filter.copyWith(query: resolvedQuery),
        config: rawConfig,
      );
    }

    final pageUrl = await _resolveListPageUrl(
      targetPage: filter.page,
      query: resolvedQuery,
      rawConfig: rawConfig,
    );
    if (pageUrl == null || pageUrl.isEmpty) {
      return _SearchContext(filter: filter, config: rawConfig);
    }

    final patchedConfig = _cloneMap(rawConfig);
    final scraper = ((patchedConfig['scraper'] as Map?) ?? <String, dynamic>{})
        .cast<String, dynamic>();
    patchedConfig['scraper'] = scraper;
    final urlPatterns =
        ((scraper['urlPatterns'] as Map?) ?? <String, dynamic>{})
            .cast<String, dynamic>();
    scraper['urlPatterns'] = urlPatterns;

    final patternKey = isHomeMode ? 'home' : 'search';
    final inheritedListConfig = _resolveInheritedListConfig(
      urlPatterns: urlPatterns,
      patternKey: patternKey,
    );

    // Force delegate to use resolved URL by running with page=1.
    urlPatterns[patternKey] = <String, dynamic>{
      'url': pageUrl,
      'list': inheritedListConfig,
    };

    return _SearchContext(
      filter: filter.copyWith(page: 1, query: resolvedQuery),
      config: patchedConfig,
    );
  }

  Future<String?> _resolveListPageUrl({
    required int targetPage,
    required String query,
    required Map<String, dynamic> rawConfig,
  }) async {
    final normalizedQuery = query.trim();
    // `next=` tokens in search URLs can be short-lived. Reusing cached token
    // URLs may return 200 with empty list content, so only cache stable
    // home-page pagination URLs.
    final allowCache = normalizedQuery.isEmpty;
    final queryKey = normalizedQuery.isEmpty
        ? 'home:$targetPage'
        : 'search:${normalizedQuery.toLowerCase()}:$targetPage';
    if (allowCache) {
      final cached = _pageUrlCache[queryKey];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final seedPaths = _buildSearchSeedPaths(normalizedQuery);
    final firstPage = await _fetchFirstSeedPage(
      seedPaths: seedPaths,
      rawConfig: rawConfig,
    );
    if (firstPage == null) {
      return null;
    }

    var currentUrl = firstPage.url;
    var currentHtml = firstPage.html;
    if (targetPage <= 1) {
      if (allowCache) {
        _pageUrlCache[queryKey] = currentUrl;
      }
      return currentUrl;
    }

    for (var page = 2; page <= targetPage; page++) {
      final nextUrl = _extractNextPageUrl(currentHtml);
      if (nextUrl == null || nextUrl.isEmpty) {
        // Parse prev nav too so search-page pagination handling stays
        // symmetric with next/prev token formats.
        _extractPreviousPageUrl(currentHtml);
        return null;
      }

      currentUrl = nextUrl;
      if (page == targetPage) {
        break;
      }

      try {
        await _throttle(rawConfig);
        final response = await _dio.get<String>(
          currentUrl,
          options: Options(responseType: ResponseType.plain),
        );
        currentHtml = response.data ?? '';
        if (currentHtml.isEmpty) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }

    if (allowCache) {
      _pageUrlCache[queryKey] = currentUrl;
    }
    return currentUrl;
  }

  List<String> _buildSearchSeedPaths(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return const ['/', '/?page=1'];
    }

    final encodedVariants = <String>{
      _encodeSearchQueryValue(normalizedQuery),
      Uri.encodeQueryComponent(normalizedQuery),
    }.where((value) => value.isNotEmpty).toList();

    final seedPaths = <String>[];
    for (final encoded in encodedVariants) {
      seedPaths.add('/?f_search=$encoded');
      seedPaths.add('/?f_search=$encoded&page=1');
    }
    return seedPaths;
  }

  Future<_ListSeedPage?> _fetchFirstSeedPage({
    required List<String> seedPaths,
    required Map<String, dynamic> rawConfig,
  }) async {
    for (final seedPath in seedPaths) {
      final seedUrl = _urlBuilder.resolve(seedPath, const {});
      try {
        await _throttle(rawConfig);
        final response = await _dio.get<String>(
          seedUrl,
          options: Options(responseType: ResponseType.plain),
        );
        final html = response.data ?? '';
        if (html.isEmpty) {
          continue;
        }
        return _ListSeedPage(url: seedUrl, html: html);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _encodeSearchQueryValue(String value) {
    if (value.isEmpty) {
      return value;
    }

    final buffer = StringBuffer();
    var index = 0;
    while (index < value.length) {
      if (value.codeUnitAt(index) == 0x25 && index + 2 < value.length) {
        final hex = value.substring(index + 1, index + 3);
        if (int.tryParse(hex, radix: 16) != null) {
          buffer.write('%${hex.toUpperCase()}');
          index += 3;
          continue;
        }
      }

      final char = value[index];
      if (char == ':') {
        buffer.write(':');
      } else {
        buffer.write(Uri.encodeQueryComponent(char));
      }
      index += 1;
    }
    return buffer.toString();
  }

  String? _extractNextPageUrl(String html) {
    return _extractSearchNavUrl(html, isNext: true);
  }

  String? _extractPreviousPageUrl(String html) {
    return _extractSearchNavUrl(html, isNext: false);
  }

  String? _extractSearchNavUrl(String html, {required bool isNext}) {
    final doc = _parser.parse(html);
    final directId = isNext ? '#unext' : '#uprev';
    final legacyId = isNext ? '#dnext' : '#dprev';
    final hrefPattern = isNext ? 'next=' : 'prev=';

    final navEl = doc.querySelector(directId) ??
        doc.querySelector(legacyId) ??
        doc.querySelector('.searchnav a$directId') ??
        doc.querySelector('.searchnav a$legacyId') ??
        doc.querySelector('.searchnav a[href*="$hrefPattern"]');
    final href = navEl?.attributes['href']?.trim();
    if (href != null && href.isNotEmpty) {
      if (href.startsWith('http')) return href;
      return _urlBuilder.resolve(href, const {});
    }

    final scriptVar = isNext ? 'nexturl' : 'prevurl';
    // Fallback: search pages expose navigation URL in script vars.
    final scriptMatch = RegExp('var\\s+$scriptVar\\s*=\\s*"([^"]+)"')
        .firstMatch(html)
        ?.group(1)
        ?.trim();
    if (scriptMatch == null || scriptMatch.isEmpty) {
      return null;
    }
    if (scriptMatch.startsWith('http')) return scriptMatch;
    return _urlBuilder.resolve(scriptMatch, const {});
  }

  Map<String, dynamic> _extractListConfig(dynamic patternValue) {
    if (patternValue is Map) {
      final map = patternValue.cast<String, dynamic>();
      final list = map['list'];
      if (list is Map) {
        return list.cast<String, dynamic>();
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _resolveInheritedListConfig({
    required Map<String, dynamic> urlPatterns,
    required String patternKey,
  }) {
    final direct = _extractListConfig(urlPatterns[patternKey]);
    if (direct.isNotEmpty) {
      return direct;
    }

    final patternMap = urlPatterns[patternKey];
    if (patternMap is Map) {
      final inherits = patternMap['inherits'] as String?;
      if (inherits != null && inherits.isNotEmpty) {
        final inherited = _extractListConfig(urlPatterns[inherits]);
        if (inherited.isNotEmpty) {
          return inherited;
        }
      }
    }

    return <String, dynamic>{};
  }

  Map<String, dynamic> _cloneMap(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is Map) {
        result[key] = _cloneMap(value.cast<String, dynamic>());
      } else if (value is List) {
        result[key] = value
            .map((item) =>
                item is Map ? _cloneMap(item.cast<String, dynamic>()) : item)
            .toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    var normalizedContent = _emptyContent(contentId, rawConfig);
    const fallbackImages = <String>[];

    try {
      final scraperMap =
          (rawConfig['scraper'] as Map?)?.cast<String, dynamic>();
      final urlPatterns =
          (scraperMap?['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};
      final detailPattern = _patternUrl(urlPatterns, 'detail').isNotEmpty
          ? _patternUrl(urlPatterns, 'detail')
          : '/g/{id}/';

      final baseUrl = (rawConfig['baseUrl'] as String?) ?? '';
      if (baseUrl.isEmpty) {
        return AdapterDetailResult(
          content: normalizedContent,
          imageUrls: fallbackImages,
        );
      }

      final detailUrl = GenericUrlBuilder(baseUrl: baseUrl)
          .buildDetailUrl(detailPattern, contentId);
      final detailHtmlRaw = await _fetchDetailHtml(
        detailUrl: detailUrl,
        baseUrl: baseUrl,
        detailPattern: detailPattern,
        contentId: contentId,
        rawConfig: rawConfig,
      );
      final detailHtml = _normalizeHtml(detailHtmlRaw);
      if (detailHtml.isEmpty) {
        return AdapterDetailResult(
          content: normalizedContent,
          imageUrls: fallbackImages,
        );
      }

      normalizedContent = _hydrateDetailMetadata(normalizedContent, detailHtml);

      final expectedPageCount = _extractExpectedPageCount(detailHtml);
      final maxGalleryPage = _estimateMaxGalleryPage(
        html: detailHtml,
        expectedPageCount: expectedPageCount,
      );
      final identity = _extractGalleryIdentity(contentId) ??
          _extractGalleryIdentity(normalizedContent.id);

      // Keep detail screen fast: do not crawl gallery pagination here.
      // Full reader link collection is handled in fetchChapterImages().
      final firstPageLinks = _extractReaderLinks(detailHtml).length;

      // ✅ LAZY LOADING: Don't fetch reader pages during detail screen
      // Reader screen will call fetchChapterImages() to load images
      // This prevents blocking detail screen for large galleries.

      // Set pageCount from expected count (parsed from detail HTML)
      final updated = normalizedContent.copyWith(
        pageCount: expectedPageCount > 0 ? expectedPageCount : firstPageLinks,
        chapters: _buildPartChapters(
          identity: identity,
          maxGalleryPage: maxGalleryPage,
        ),
      );

      return AdapterDetailResult(
        content: updated,
        imageUrls: fallbackImages, // Empty - will be loaded by reader screen
      );
    } catch (e, stackTrace) {
      _logger.e(
        '$_sourceId fetchDetail failed for $contentId',
        error: e,
        stackTrace: stackTrace,
      );
      return AdapterDetailResult(
        content: normalizedContent,
        imageUrls: fallbackImages,
      );
    }
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) {
    return _delegate.fetchRelated(contentId, rawConfig);
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) {
    return _delegate.fetchComments(contentId, rawConfig);
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraperMap = (rawConfig['scraper'] as Map?)?.cast<String, dynamic>();
    final urlPatterns =
        (scraperMap?['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};
    final detailPattern = _patternUrl(urlPatterns, 'detail').isNotEmpty
        ? _patternUrl(urlPatterns, 'detail')
        : '/g/{id}/';

    final partId = _parsePartId(chapterId);
    final chunkId = _parseChunkId(chapterId);

    String galleryIdentity = chapterId;
    int targetGalleryPage = 0;
    if (partId != null) {
      galleryIdentity = '${partId.gid}/${partId.token}';
      targetGalleryPage = partId.page;
    } else if (chunkId != null) {
      galleryIdentity = '${chunkId.gid}/${chunkId.token}';
      targetGalleryPage = chunkId.page;
    }

    final baseUrl = (rawConfig['baseUrl'] as String?) ?? '';
    if (baseUrl.isEmpty) {
      return null;
    }

    final detailUrl = GenericUrlBuilder(baseUrl: baseUrl)
        .buildDetailUrl(detailPattern, galleryIdentity);

    var detailHtml = '';
    if (targetGalleryPage == 0) {
      try {
        await _throttle(rawConfig);
        final directResponse = await _dio.get<dynamic>(
          detailUrl,
          options: Options(responseType: ResponseType.plain),
        );
        detailHtml = directResponse.data?.toString() ?? '';
      } catch (_) {
        // Fall through to resilient URL probing below.
      }

      if (detailHtml.isEmpty) {
        detailHtml = await _fetchDetailHtml(
          detailUrl: detailUrl,
          baseUrl: baseUrl,
          detailPattern: detailPattern,
          contentId: galleryIdentity,
          rawConfig: rawConfig,
        );
      }
    } else {
      final pageUri = Uri.parse(detailUrl).replace(
        queryParameters: <String, String>{
          ...Uri.parse(detailUrl).queryParameters,
          'p': targetGalleryPage.toString(),
        },
      );
      try {
        await _throttle(rawConfig);
        final response = await _dio.get<dynamic>(
          pageUri.toString(),
          options: Options(responseType: ResponseType.plain),
        );
        detailHtml = response.data?.toString() ?? '';
      } catch (_) {
        detailHtml = '';
      }
    }

    if (detailHtml.isEmpty) {
      return null;
    }

    final readerLinks = _extractReaderLinks(detailHtml);
    final expectedPageCount = _extractExpectedPageCount(detailHtml);

    if (readerLinks.isEmpty) {
      return null;
    }

    final pages = <String>[];
    final seen = <String>{};
    for (final link in readerLinks) {
      final readerUrl = _toAbsoluteUrl(link, baseUrl);
      if (seen.add(readerUrl)) {
        pages.add(readerUrl);
      }
    }

    if (pages.isEmpty) {
      return null;
    }

    final identity = _extractGalleryIdentity(galleryIdentity);
    final maxGalleryPage = _estimateMaxGalleryPage(
      html: detailHtml,
      expectedPageCount: expectedPageCount,
    );

    String? previousPartId;
    String? previousPartTitle;
    String? nextPartId;
    String? nextPartTitle;
    if (identity != null && targetGalleryPage < maxGalleryPage) {
      nextPartId = _buildPartId(
        gid: identity.gid,
        token: identity.token,
        page: targetGalleryPage + 1,
      );
      nextPartTitle = _buildPartLabel(targetGalleryPage + 2);
    }
    if (identity != null && targetGalleryPage > 0) {
      previousPartId = _buildPartId(
        gid: identity.gid,
        token: identity.token,
        page: targetGalleryPage - 1,
      );
      previousPartTitle = _buildPartLabel(targetGalleryPage);
    }

    // Return reader page URLs quickly.
    // Reader widget resolves each /s/... page lazily using the installed
    // E-Hentai config's image selector rules.
    return ChapterData(
      images: pages,
      prevChapterId: previousPartId,
      nextChapterId: nextPartId,
      prevChapterTitle: previousPartTitle,
      nextChapterTitle: nextPartTitle,
    );
  }

  int _estimateMaxGalleryPage({
    required String html,
    required int expectedPageCount,
  }) {
    final firstPageLinks = _extractReaderLinks(html).length;
    final window = _extractGalleryWindow(html);

    final expectedTotal = (() {
      final fromWindow = window?.totalImages ?? 0;
      return fromWindow > expectedPageCount ? fromWindow : expectedPageCount;
    })();

    final perPage = (() {
      final fromWindow = window?.itemsPerPage ?? 0;
      if (fromWindow > 0) return fromWindow;
      if (firstPageLinks > 0) return firstPageLinks;
      return 0;
    })();

    final expectedMaxPage = (expectedTotal > 0 && perPage > 0)
        ? ((expectedTotal - 1) / perPage).floor()
        : 0;
    final navMaxPage = _extractMaxGalleryThumbPage(html);
    return navMaxPage > 0 ? navMaxPage : expectedMaxPage;
  }

  String _buildPartId({
    required String gid,
    required String token,
    required int page,
  }) {
    return '$_partPrefix:$gid:$token:$page';
  }

  List<Chapter>? _buildPartChapters({
    required _GalleryIdentity? identity,
    required int maxGalleryPage,
  }) {
    if (identity == null) {
      return null;
    }

    final normalizedMaxPage = maxGalleryPage < 0 ? 0 : maxGalleryPage;
    final chapters = <Chapter>[];
    for (var page = 0; page <= normalizedMaxPage; page++) {
      final displayIndex = page + 1;
      chapters.add(
        Chapter(
          id: _buildPartId(
            gid: identity.gid,
            token: identity.token,
            page: page,
          ),
          title: _buildPartLabel(displayIndex),
          url: '/g/${identity.gid}/${identity.token}/?p=$page',
        ),
      );
    }
    return chapters;
  }

  String _buildPartLabel(int partNumber) {
    return 'Part $partNumber';
  }

  _EhentaiPartId? _parsePartId(String value) {
    final match = RegExp(
      '^${RegExp.escape(_partPrefix)}:(\\d+):([A-Za-z0-9_-]+):(\\d+)\$',
    ).firstMatch(value);
    if (match == null) return null;

    final gid = match.group(1);
    final token = match.group(2);
    final page = int.tryParse(match.group(3) ?? '');
    if (gid == null || token == null || page == null) {
      return null;
    }
    return _EhentaiPartId(gid: gid, token: token, page: page);
  }

  _EhentaiChunkId? _parseChunkId(String value) {
    final match = RegExp(
      '^${RegExp.escape(_chunkPrefix)}:(\\d+):([A-Za-z0-9_-]+):(\\d+)\$',
    ).firstMatch(value);
    if (match == null) return null;

    final gid = match.group(1);
    final token = match.group(2);
    final page = int.tryParse(match.group(3) ?? '');
    if (gid == null || token == null || page == null) {
      return null;
    }
    return _EhentaiChunkId(gid: gid, token: token, page: page);
  }

  _GalleryIdentity? _extractGalleryIdentity(String value) {
    final match = RegExp(r'([0-9]+)/([A-Za-z0-9_-]+)').firstMatch(value);
    if (match == null) return null;
    final gid = match.group(1);
    final token = match.group(2);
    if (gid == null || token == null) return null;
    return _GalleryIdentity(gid: gid, token: token);
  }

  String _toAbsoluteUrl(String link, String baseUrl) {
    if (link.startsWith('http://') || link.startsWith('https://')) {
      return link;
    }
    if (link.startsWith('//')) {
      return 'https:$link';
    }
    return _urlBuilder.resolve(link, const {});
  }

  List<String> _extractReaderLinks(String html) {
    final bridge = RustBridge.instance;
    if (bridge != null) {
      try {
        final rustUrls = bridge.ehentaiExtractUrls(html);
        if (rustUrls != null) {
          return rustUrls.map((u) => _normalizeReaderLink(u)).toList();
        }
      } catch (_) {
        return const <String>[];
      }
      return const <String>[];
    }

    // Dart fallback — only when Rust unavailable
    final normalizedHtml = html.replaceAll(r'\/', '/');
    final urlPattern = RegExp(
      r'((?:https?:)?//(?:e-hentai|exhentai)\.org)?/s/[A-Za-z0-9_-]+/[0-9]+-[0-9]+',
      caseSensitive: false,
    );
    final seen = <String>{};
    final links = <String>[];
    for (final match in urlPattern.allMatches(normalizedHtml)) {
      final link = match.group(0)!;
      if (seen.add(link)) {
        links.add(_normalizeReaderLink(link));
      }
    }
    return links;
  }

  int _extractExpectedPageCount(String html) {
    final direct = RegExp(
      r'<td[^>]*class="gdt2"[^>]*>\s*([0-9]+)\s+pages?\s*</td>',
      caseSensitive: false,
    ).firstMatch(html);
    if (direct != null) {
      return int.tryParse(direct.group(1) ?? '') ?? 0;
    }

    final fallback = RegExp(r'([0-9]+)\s+pages?', caseSensitive: false)
        .firstMatch(html)
        ?.group(1);
    return int.tryParse(fallback ?? '') ?? 0;
  }

  _GalleryWindow? _extractGalleryWindow(String html) {
    final match = RegExp(
      r'Showing\s+(\d+)\s*-\s*(\d+)\s+of\s+(\d+)\s+images',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) {
      return null;
    }

    final start = int.tryParse(match.group(1) ?? '');
    final end = int.tryParse(match.group(2) ?? '');
    final total = int.tryParse(match.group(3) ?? '');

    if (start == null || end == null || total == null) {
      return null;
    }
    if (end < start || total <= 0) {
      return null;
    }

    return _GalleryWindow(
      itemsPerPage: end - start + 1,
      totalImages: total,
    );
  }

  int _extractMaxGalleryThumbPage(String html) {
    final doc = _parser.parse(html);
    final anchors = doc.querySelectorAll('a[href*="?p="]');

    var maxPage = 0;
    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      try {
        final uri =
            Uri.parse(href.startsWith('http') ? href : 'https://x$href');
        final value = uri.queryParameters['p'];
        final page = int.tryParse(value ?? '');
        if (page != null && page > maxPage) {
          maxPage = page;
        }
      } catch (_) {
        continue;
      }
    }

    return maxPage;
  }

  String _normalizeReaderLink(String link) {
    final decoded = link.replaceAll('&amp;', '&').trim();
    if (decoded.startsWith('//')) {
      final uri = Uri.parse('https:$decoded');
      final query = uri.query.isEmpty ? '' : '?${uri.query}';
      return '${uri.path}$query';
    }

    if (decoded.startsWith('http')) {
      final uri = Uri.parse(decoded);
      final query = uri.query.isEmpty ? '' : '?${uri.query}';
      return '${uri.path}$query';
    }

    return decoded;
  }

  String _patternUrl(Map<String, dynamic> patterns, String key) {
    final entry = patterns[key];
    if (entry is String) return entry;
    if (entry is Map<String, dynamic>) {
      return (entry['url'] as String?) ?? '';
    }
    return '';
  }

  Future<String> _fetchDetailHtml({
    required String detailUrl,
    required String baseUrl,
    required String detailPattern,
    required String contentId,
    required Map<String, dynamic> rawConfig,
  }) async {
    final candidates = <String>{detailUrl};

    final withSlash = contentId.endsWith('/') ? contentId : '$contentId/';
    final withoutSlash = contentId.endsWith('/')
        ? contentId.substring(0, contentId.length - 1)
        : contentId;

    final encoded = Uri.encodeComponent(contentId);
    final encodedWithSlash = Uri.encodeComponent(
        withSlash.endsWith('/') ? withSlash : '$withSlash/');
    final encodedNoSlash = Uri.encodeComponent(withoutSlash);

    final doubleEncoded = Uri.encodeComponent(encoded);

    for (final id in <String>[
      contentId,
      withSlash,
      withoutSlash,
      encoded,
      encodedWithSlash,
      encodedNoSlash,
      doubleEncoded,
    ]) {
      if (id.isEmpty) continue;
      final candidate =
          GenericUrlBuilder(baseUrl: baseUrl).buildDetailUrl(detailPattern, id);
      candidates.add(candidate);
    }

    for (final url in candidates) {
      try {
        await _throttle(rawConfig);
        final response = await _dio.get<dynamic>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final html = response.data?.toString() ?? '';
        if (html.isNotEmpty) {
          return html;
        }
      } catch (_) {
        // Try next candidate URL variant.
      }
    }

    return '';
  }

  Content _emptyContent(String id, Map<String, dynamic> rawConfig) {
    return Content(
      id: id,
      sourceId: (rawConfig['source'] as String?) ?? 'ehentai',
      title: 'Unknown',
      coverUrl: '',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'unknown',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String _normalizeHtml(String html) {
    if (!html.contains(r'\"') && !html.contains(r'\n')) {
      return html;
    }

    return html
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\/', '/')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t');
  }

  Content _hydrateDetailMetadata(Content content, String html) {
    final currentTitle = content.title.trim();
    final currentCover = content.coverUrl.trim();

    final title = currentTitle.isEmpty || currentTitle == 'Unknown'
        ? _extractTitle(html)
        : currentTitle;
    final coverUrl =
        currentCover.isEmpty ? _extractCoverUrl(html) : currentCover;

    var tags = content.tags;
    if (tags.isEmpty) {
      final parsedTags = _extractTags(html);
      if (parsedTags.isNotEmpty) {
        tags = parsedTags;
      }
    }
    final uploaderTag = _extractUploaderTag(html);
    if (uploaderTag != null &&
        !tags.any((tag) =>
            tag.type == uploaderTag.type &&
            tag.name.toLowerCase() == uploaderTag.name.toLowerCase())) {
      tags = <Tag>[...tags, uploaderTag];
    }

    // Extract upload date
    final uploadDate = _extractUploadDate(html);

    final hydrated = content.copyWith(
      title: title.isEmpty ? content.title : title,
      coverUrl: coverUrl.isEmpty ? content.coverUrl : coverUrl,
      tags: tags,
      uploadDate: uploadDate ?? content.uploadDate,
    );

    return _normalizeEhentaiTags(hydrated);
  }

  DateTime? _extractUploadDate(String html) {
    // E-Hentai detail page date format:
    // <td class="gdt2">2026-03-24 03:00</td>
    final dateMatch = RegExp(
      r'<td[^>]*class="gdt2"[^>]*>(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})',
    ).firstMatch(html);

    if (dateMatch == null) return null;

    try {
      final year = int.parse(dateMatch.group(1) ?? '0');
      final month = int.parse(dateMatch.group(2) ?? '1');
      final day = int.parse(dateMatch.group(3) ?? '1');
      final hour = int.parse(dateMatch.group(4) ?? '0');
      final minute = int.parse(dateMatch.group(5) ?? '0');

      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  String _extractTitle(String html) {
    final match =
        RegExp(r'<h1[^>]*id="gn"[^>]*>([\s\S]*?)</h1>').firstMatch(html);
    return _cleanHtmlText(match?.group(1) ?? '');
  }

  String _extractCoverUrl(String html) {
    final block = RegExp(
      r'<div[^>]*id="gd1"[^>]*>[\s\S]*?</div>',
      caseSensitive: false,
    ).firstMatch(html)?.group(0);

    final src = RegExp(
      r'<img[^>]*(?:data-src|src)="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(block ?? '')?.group(1);
    if (src != null && src.isNotEmpty) {
      return src.trim();
    }

    final styleUrlRaw = RegExp(r'url\(([^\)]+)\)', caseSensitive: false)
        .firstMatch(html)
        ?.group(1);

    if (styleUrlRaw == null || styleUrlRaw.trim().isEmpty) {
      return '';
    }

    return styleUrlRaw.trim().replaceAll(RegExp(r'^["]|["]$'), '');
  }

  Tag? _extractUploaderTag(String html) {
    final match = RegExp(
      r'<div[^>]*id="gdn"[^>]*>\s*<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;

    final name = _cleanHtmlText(match.group(2) ?? '');
    if (name.isEmpty) return null;

    final href = (match.group(1) ?? '').trim();
    return Tag(
      id: 0,
      name: name,
      type: 'uploader',
      count: 0,
      url: href,
      slug: name,
    );
  }

  List<Tag> _extractTags(String html) {
    final bridge = RustBridge.instance;
    if (bridge != null) {
      try {
        final rustTags = bridge.ehentaiExtractTags(html);
        if (rustTags != null) {
          return rustTags.map((t) {
            return Tag(
              id: 0,
              name: t,
              type: TagType.tag,
              count: 0,
              url: '',
              slug: t,
            );
          }).toList();
        }
      } catch (_) {
        return const <Tag>[];
      }
      return const <Tag>[];
    }

    // Dart fallback — only when Rust unavailable
    // E-Hentai detail page tag structure:
    // <div id="td_language:korean" class="gt" ...>
    //   <a id="ta_language:korean" href="..." class="">korean</a>
    // </div>
    // Parse tags from div ID attribute: "td_TYPE:VALUE"
    final tags = <Tag>[];
    final tagMatches = RegExp(
      r'<div[^>]*id="td_([^"]+)"[^>]*>[\s\S]*?<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    ).allMatches(html);

    for (final match in tagMatches) {
      final tagSpec = (match.group(1) ?? '').trim();
      if (tagSpec.isEmpty || !tagSpec.contains(':')) continue;

      final separatorIndex = tagSpec.indexOf(':');
      final rawType = tagSpec.substring(0, separatorIndex).trim();
      if (rawType.isEmpty) continue;

      final href = (match.group(2) ?? '').trim();
      final tagText = _cleanHtmlText(match.group(3) ?? '');
      if (tagText.isEmpty) continue;

      final fullTagName = '$rawType:$tagText';
      tags.add(Tag(
        id: 0,
        name: fullTagName,
        type: TagType.tag,
        count: 0,
        url: href,
        slug: fullTagName,
      ));
    }

    // Fallback for legacy pages using title="type:value" directly.
    if (tags.isEmpty) {
      final matches = RegExp(
        r'<div[^>]*class="[^"]*\bgt\b[^"]*"[^>]*title="([^"]+)"',
      ).allMatches(html);
      for (final match in matches) {
        final name = _cleanHtmlText(match.group(1) ?? '');
        if (name.isEmpty) continue;
        tags.add(Tag(id: 0, name: name, type: TagType.tag, count: 0));
      }
    }

    return tags;
  }

  String _cleanHtmlText(String text) {
    if (text.isEmpty) return '';
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .trim();
  }

  Content _normalizeEhentaiTags(Content content) {
    if (content.tags.isEmpty) return content;

    final normalizedTags = <Tag>[];
    final artists = <String>[];
    final characters = <String>[];
    final parodies = <String>[];
    final groups = <String>[];
    var language = content.language;

    for (final tag in content.tags) {
      final raw = tag.name.trim();
      if (!raw.contains(':')) {
        normalizedTags.add(tag);
        continue;
      }

      final parts = raw.split(':');
      if (parts.length < 2) {
        normalizedTags.add(tag);
        continue;
      }

      final type = parts.first.trim().toLowerCase();
      final name = parts.sublist(1).join(':').trim();
      if (name.isEmpty) {
        normalizedTags.add(tag);
        continue;
      }

      final mappedType = _mapTagType(type);
      normalizedTags.add(tag.copyWith(type: mappedType, name: name));

      switch (mappedType) {
        case TagType.artist:
          artists.add(name);
          break;
        case TagType.character:
          characters.add(name);
          break;
        case TagType.parody:
          parodies.add(name);
          break;
        case TagType.group:
          groups.add(name);
          break;
        case TagType.language:
          final normalized = name.toLowerCase();
          if (normalized != 'translated') {
            language = name;
          } else if (language == 'unknown' || language.isEmpty) {
            language = name;
          }
          break;
        default:
          break;
      }
    }

    return content.copyWith(
      tags: normalizedTags,
      artists: artists.isNotEmpty ? artists : content.artists,
      characters: characters.isNotEmpty ? characters : content.characters,
      parodies: parodies.isNotEmpty ? parodies : content.parodies,
      groups: groups.isNotEmpty ? groups : content.groups,
      language: language,
    );
  }

  String _mapTagType(String rawType) {
    switch (rawType) {
      case 'artist':
        return TagType.artist;
      case 'character':
        return TagType.character;
      case 'parody':
        return TagType.parody;
      case 'group':
        return TagType.group;
      case 'language':
        return TagType.language;
      case 'category':
        return TagType.category;
      default:
        return rawType.isEmpty ? TagType.tag : rawType;
    }
  }

  Future<void> _throttle(Map<String, dynamic> rawConfig) async {
    _rateLimiter ??= RateLimiter.fromNetwork(
      (rawConfig['network'] as Map?)?.cast<String, dynamic>(),
    );
    await _rateLimiter?.throttle();
  }

  // Extract both covers and languages in a single HTTP request
  // Returns `Map<String, String>` where key is ID and value contains 'cover' and 'language'
  Future<Map<String, Map<String, dynamic>>> _extractListCoversAndLanguages({
    required SearchFilter filter,
    required Map<String, dynamic> rawConfig,
    required String resolvedQuery,
  }) async {
    final scraper = (rawConfig['scraper'] as Map?)?.cast<String, dynamic>();
    final urlPatterns =
        (scraper?['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};
    if (urlPatterns.isEmpty) return const <String, Map<String, dynamic>>{};

    final patternKey = _resolveSearchPatternKey(filter, urlPatterns);
    final resolved =
        _resolveListPattern(urlPatterns: urlPatterns, patternKey: patternKey);
    if (resolved == null) return const <String, Map<String, dynamic>>{};

    final urlTemplate = _applyPageOverride(
      patternMap: resolved.patternMap,
      fallbackTemplate: resolved.urlTemplate,
      page: filter.page,
    );

    final url = _urlBuilder.resolve(urlTemplate, {
      'page': filter.page.toString(),
      'query': Uri.encodeQueryComponent(resolvedQuery),
      'tag': filter.includeTags.isNotEmpty
          ? filter.includeTags.first.name.toLowerCase().replaceAll(' ', '-')
          : '',
    });

    try {
      await _throttle(rawConfig);
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data ?? '';
      if (html.isEmpty) return const <String, Map<String, dynamic>>{};

      final doc = _parser.parse(html);
      final container = resolved.listConfig['container'] as String?;
      if (container == null || container.isEmpty) {
        return const <String, Map<String, dynamic>>{};
      }

      final fields =
          (resolved.listConfig['fields'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      final coverDef = (fields['coverUrl'] as Map?)?.cast<String, dynamic>();
      final idDef = (fields['id'] as Map?)?.cast<String, dynamic>();
      final idSelector = idDef?['selector'] as String?;
      final idAttribute = (idDef?['attribute'] as String?) ?? 'href';

      final result = <String, Map<String, dynamic>>{};
      for (final row in _parser.selectAll(doc, container)) {
        // Extract ID first
        if (idSelector == null || idSelector.isEmpty) {
          continue;
        }
        final idElement = row.querySelector(idSelector);
        if (idElement == null) continue;

        String? idValue = idElement.attributes[idAttribute];
        if (idValue == null || idValue.isEmpty) continue;

        // Extract regex if defined
        final idRegex = idDef?['regex'] as String?;
        if (idRegex != null && idRegex.isNotEmpty) {
          final match = RegExp(idRegex).firstMatch(idValue);
          if (match != null && match.groupCount > 0) {
            idValue = match.group(1);
          }
        }

        if (idValue == null || idValue.isEmpty) continue;

        // Extract cover for this ID
        final cover = _extractCoverFromRow(row, coverDef);

        // Extract language for this ID
        final language = _extractLanguageFromRow(row);

        // Extract posted date for this ID (e.g. "2026-09-02 12:29")
        final postedRaw = _extractPostedDateFromRow(row);
        final postedDate = _parsePostedDate(postedRaw);

        // Store combined data
        result[idValue] = {
          'cover': cover,
          'language': language,
          'postedRaw': postedRaw,
          'postedDate': postedDate,
        };
      }

      return result;
    } catch (_) {
      return const <String, Map<String, dynamic>>{};
    }
  }

  // Extract language tags from home page HTML
  // Returns `Map<String, String>` where key is content ID and value is language
  // Example: "english", "chinese", "japanese", etc.
  // Extract language tag from a single row element
  // Looks for <div class="gt" title="language:xxx"> tags
  String _extractLanguageFromRow(dom.Element row) {
    final tags = row.querySelectorAll('.gt[title]');
    for (final tag in tags) {
      final title = tag.attributes['title'] ?? '';
      if (title.contains('language:')) {
        // Parse "language:english" -> "english"
        final parts = title.split(':');
        if (parts.length >= 2) {
          final language = parts.sublist(1).join(':').trim();
          if (language.isNotEmpty) {
            return language;
          }
        }
      }
    }
    return '';
  }

  String _resolveSearchPatternKey(
    SearchFilter filter,
    Map<String, dynamic> urlPatterns,
  ) {
    if (filter.includeTags.isNotEmpty &&
        urlPatterns.containsKey('genreSearch')) {
      return filter.page > 1 && urlPatterns.containsKey('genreSearchPage')
          ? 'genreSearchPage'
          : 'genreSearch';
    }

    if (filter.query.trim().isNotEmpty) {
      return filter.page > 1 && urlPatterns.containsKey('searchPage')
          ? 'searchPage'
          : 'search';
    }

    return filter.page > 1 && urlPatterns.containsKey('homePage')
        ? 'homePage'
        : 'home';
  }

  String _resolveSearchQuery(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) {
    final query = filter.query.trim();
    if (!query.startsWith('raw:')) {
      return query;
    }

    final payload = query.substring(4);
    if (payload.isEmpty) {
      return '';
    }

    final queryParamName = _resolveRawQueryParamName(rawConfig);
    for (final pair in payload.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) continue;

      final key = _safeDecodeComponent(pair.substring(0, idx));
      if (key != queryParamName) continue;

      return _safeDecodeComponent(pair.substring(idx + 1)).trim();
    }

    return '';
  }

  String _resolveRawQueryParamName(Map<String, dynamic> rawConfig) {
    final searchForm =
        (rawConfig['searchForm'] as Map?)?.cast<String, dynamic>();
    final params = (searchForm?['params'] as Map?)?.cast<String, dynamic>();
    final queryDef = (params?['query'] as Map?)?.cast<String, dynamic>();
    final configured = (queryDef?['queryParam'] as String?)?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return 'f_search';
  }

  String _safeDecodeComponent(String value) {
    if (value.isEmpty || !value.contains('%')) {
      return value;
    }

    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return _decodePercentEncodedSegments(value) ?? value;
    }
  }

  String? _decodePercentEncodedSegments(String value) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < value.length) {
      if (value.codeUnitAt(index) != 0x25) {
        buffer.writeCharCode(value.codeUnitAt(index));
        index += 1;
        continue;
      }

      final bytes = <int>[];
      var cursor = index;

      while (cursor + 2 < value.length && value.codeUnitAt(cursor) == 0x25) {
        final hex = value.substring(cursor + 1, cursor + 3);
        final byte = int.tryParse(hex, radix: 16);
        if (byte == null) {
          break;
        }
        bytes.add(byte);
        cursor += 3;
      }

      if (bytes.isEmpty) {
        return null;
      }

      try {
        buffer.write(utf8.decode(bytes));
      } on FormatException {
        return null;
      }

      index = cursor;
    }

    return buffer.toString();
  }

  _ResolvedListPattern? _resolveListPattern({
    required Map<String, dynamic> urlPatterns,
    required String patternKey,
  }) {
    final value = urlPatterns[patternKey];
    if (value is String) {
      return null;
    }
    if (value is! Map) {
      return null;
    }

    final patternMap = value.cast<String, dynamic>();
    final urlTemplate = (patternMap['url'] as String?) ?? '';
    if (urlTemplate.isEmpty) return null;

    final localList =
        (patternMap['list'] as Map?)?.cast<String, dynamic>() ?? {};

    Map<String, dynamic> mergedList = {...localList};
    final parentKey = patternMap['inherits'] as String?;
    if (parentKey != null) {
      final parent = urlPatterns[parentKey];
      if (parent is Map) {
        final parentMap = parent.cast<String, dynamic>();
        final parentList =
            (parentMap['list'] as Map?)?.cast<String, dynamic>() ?? {};
        mergedList = {...parentList, ...localList};

        final parentFields =
            (parentList['fields'] as Map?)?.cast<String, dynamic>() ?? {};
        final localFields =
            (localList['fields'] as Map?)?.cast<String, dynamic>() ?? {};
        if (parentFields.isNotEmpty || localFields.isNotEmpty) {
          mergedList['fields'] = {...parentFields, ...localFields};
        }

        final parentPagination =
            (parentList['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
        final localPagination =
            (localList['pagination'] as Map?)?.cast<String, dynamic>() ?? {};
        if (parentPagination.isNotEmpty || localPagination.isNotEmpty) {
          mergedList['pagination'] = {
            ...parentPagination,
            ...localPagination,
          };
        }
      }
    }

    return _ResolvedListPattern(
      urlTemplate: urlTemplate,
      listConfig: mergedList,
      patternMap: patternMap,
    );
  }

  String _applyPageOverride({
    required Map<String, dynamic> patternMap,
    required String fallbackTemplate,
    required int page,
  }) {
    final pageOverrides =
        (patternMap['pageOverrides'] as Map?)?.cast<String, dynamic>();
    final overrideTemplate = pageOverrides?[page.toString()] as String?;
    if (overrideTemplate != null && overrideTemplate.isNotEmpty) {
      return overrideTemplate;
    }
    return fallbackTemplate;
  }

  String _extractCoverFromRow(
    dom.Element row,
    Map<String, dynamic>? coverDef,
  ) {
    if (coverDef != null) {
      final selector = coverDef['selector'] as String?;
      final attribute = coverDef['attribute'] as String?;
      final regexPattern = coverDef['regex'] as String?;

      if (selector != null && selector.isNotEmpty) {
        final node = row.querySelector(selector);
        if (node != null) {
          var value = '';
          if (attribute != null && attribute.isNotEmpty) {
            value = (node.attributes[attribute] ?? '').trim();

            // If src is a data: URI (placeholder) or empty, try fallbacks
            if ((value.isEmpty || value.startsWith('data:')) &&
                attribute == 'src') {
              value = (node.attributes['data-src'] ??
                      node.attributes['data-lazy-src'] ??
                      node.attributes['srcset']
                          ?.split(',')
                          .first
                          .split(' ')
                          .first ??
                      '')
                  .trim();
            }
          } else {
            value = node.text.trim();
          }

          if (regexPattern != null &&
              regexPattern.isNotEmpty &&
              value.isNotEmpty) {
            final match =
                RegExp(regexPattern, caseSensitive: false).firstMatch(value);
            if (match != null) {
              value =
                  (match.groupCount > 0 ? match.group(1) : match.group(0)) ??
                      '';
            }
          }

          if (value.isNotEmpty) {
            return _cleanCoverUrl(value);
          }
        }
      }
    }

    final styleValue = row.querySelector('.glthumb div')?.attributes['style'] ??
        row.querySelector('.gl1t div')?.attributes['style'] ??
        '';
    if (styleValue.isNotEmpty) {
      final styleMatch = RegExp(
        "url\\(([\\\"']?)([^\\\"')]+)\\1\\)",
        caseSensitive: false,
      ).firstMatch(styleValue);
      final styleUrl = styleMatch?.group(2) ?? '';
      if (styleUrl.isNotEmpty) {
        return _cleanCoverUrl(styleUrl);
      }
    }

    final img = row.querySelector('.gl2c img, .glthumb img, .gl1t img');
    if (img != null) {
      var imgUrl = (img.attributes['src'] ?? '').trim();

      // If src is placeholder (data: URI), use data-src instead
      if (imgUrl.startsWith('data:')) {
        imgUrl = (img.attributes['data-src'] ??
                img.attributes['data-lazy-src'] ??
                '')
            .trim();
      }

      // If still empty, try srcset
      if (imgUrl.isEmpty) {
        imgUrl =
            (img.attributes['srcset']?.split(',').first.split(' ').first ?? '')
                .trim();
      }

      if (imgUrl.isNotEmpty) {
        return _cleanCoverUrl(imgUrl);
      }
    }

    return '';
  }

  String _cleanCoverUrl(String value) {
    var cleaned = value.trim().replaceAll('&amp;', '&');
    if (cleaned.length >= 2) {
      if (cleaned.startsWith('"') || cleaned.startsWith("'")) {
        cleaned = cleaned.substring(1);
      }
      if (cleaned.endsWith('"') || cleaned.endsWith("'")) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
    }
    return cleaned;
  }

  String _extractPostedDateFromRow(dom.Element row) {
    // E-Hentai list row date: <div id="posted_123">2026-09-02 12:29</div>
    // or <div id="postedpop_123">2026-09-02 12:29</div>
    final posted = row.querySelector('[id^="posted_"]') ??
        row.querySelector('[id^="postedpop_"]');
    if (posted != null) {
      final text = posted.text.trim();
      if (text.isNotEmpty) return text;
    }
    // Fallback: search for date pattern in row text
    final match =
        RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})').firstMatch(row.text);
    return match?.group(1) ?? '';
  }

  DateTime? _parsePostedDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // Format: "2026-09-02 12:29" or "2026-09-02 12:29:00"
    final normalized = trimmed.replaceFirst(' ', 'T');
    // Try with seconds, then without
    var parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
    // Try adding seconds
    parsed = DateTime.tryParse('$normalized:00');
    return parsed;
  }
}

class _ResolvedListPattern {
  final String urlTemplate;
  final Map<String, dynamic> listConfig;
  final Map<String, dynamic> patternMap;

  _ResolvedListPattern({
    required this.urlTemplate,
    required this.listConfig,
    required this.patternMap,
  });
}

class _SearchContext {
  final SearchFilter filter;
  final Map<String, dynamic> config;

  _SearchContext({
    required this.filter,
    required this.config,
  });
}

class _ListSeedPage {
  final String url;
  final String html;

  _ListSeedPage({
    required this.url,
    required this.html,
  });
}

class _GalleryWindow {
  final int itemsPerPage;
  final int totalImages;

  _GalleryWindow({
    required this.itemsPerPage,
    required this.totalImages,
  });
}

class _GalleryIdentity {
  final String gid;
  final String token;

  _GalleryIdentity({
    required this.gid,
    required this.token,
  });
}

class _EhentaiPartId {
  final String gid;
  final String token;
  final int page;

  _EhentaiPartId({
    required this.gid,
    required this.token,
    required this.page,
  });
}

class _EhentaiChunkId {
  final String gid;
  final String token;
  final int page;

  _EhentaiChunkId({
    required this.gid,
    required this.token,
    required this.page,
  });
}
