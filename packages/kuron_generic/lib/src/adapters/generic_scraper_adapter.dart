// Generic scraper adapter — handles HTML scraping sources.
///
// All extraction behaviour is driven purely by the source config JSON; the
// adapter has no knowledge of any specific source's CSS selectors or field
// naming conventions.
///
// ### Config schema expected by this adapter
///
// Each **list URL pattern** (home, search, genreSearch, …) is either a plain
// String (URL only) or a Map with at minimum a `"url"` key and a `"list"`
// sub-block:
///
// ```json
// "home": {
//   "url": "/",
//   "list": {
//     "container": ".utao",
//     "fields": {
//       "id":       { "selector": "a.series", "attribute": "href", "transform": "slug" },
//       "title":    { "selector": ".luf > a > h4" },
//       "coverUrl": { "selector": "img.ts-post-image", "attribute": "src" }
//     },
//     "pagination": { "next": ".hpage a.r", "alt": ".pagination .next.page-numbers" }
//   }
// }
// ```
///
// Patterns may declare `"inherits": "home"` to copy the parent pattern's
// `"list"` block (then optionally override individual keys locally).
///
// The **detail** selectors live in `scraper.selectors.detail`:
///
// ```json
// "detail": {
//   "fields": {
//     "title":    { "selector": ".entry-title" },
//     "coverUrl": { "selector": ".thumb img", "attribute": "src" },
//     "tags":     { "selector": ".seriestugenre a", "multi": true }
//   },
//   "chapters": {
//     "container": "#chapterlist li",
//     "fields": {
//       "id":    { "selector": ".chbox a", "attribute": "href", "transform": "slug" },
//       "title": { "selector": ".chapternum" },
//       "date":  { "selector": ".chapterdate" }
//     }
//   }
// }
// ```
///
// The **reader** config (for chapter image extraction) lives in
// `scraper.selectors.reader`:
///
// ```json
// "reader": {
//   "tsReaderRegex": "ts_reader\\.run\\((.*?)\\);",
//   "container": "#readerarea",
//   "images":    { "selector": "img", "attribute": "src" },
//   "nav": { "next": "a.next-chapter", "prev": "a.prev-chapter" }
// }
// ```
///
// ### URL template placeholders
// `{page}`, `{query}` (URI-encoded), `{tag}` (first included tag, kebab-case).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import '../mappers/generic_content_mapper.dart';
import '../models/source_config_runtime.dart';
import '../parsers/generic_html_parser.dart';
import '../readers/reader_image_resolver.dart';
import '../routing/search_query_routing.dart';
import '../url_builder/generic_url_builder.dart';
import 'generic_adapter.dart';

// ### Module map
// - `readers/reader_image_resolver.dart` — chapter-image mode handlers
//   (chapterData / base64 / slides / preview-CDN / hentaiFox / ajax field
//   extraction / sanitize + normalize).
// - `routing/search_query_routing.dart` — URL pattern lookup, page params,
//   query encoding, category routes, percent decoding.
// This adapter keeps orchestration (fetch, detail, pagination) and delegates;
// behavior is unchanged from the pre-extraction single file.

class GenericScraperAdapter implements GenericAdapter {
  final Dio _dio;
  final GenericUrlBuilder _urlBuilder;
  final GenericHtmlParser _parser;
  final Logger _logger;
  final String _sourceId;
  late final ReaderImageResolver _readerImages;


  late final SearchQueryRouting _searchRouting;
  final Future<void> Function()? _delayApplier;
  final RateLimiter? _rateLimiter;
  final Map<String, String> _paginationCursorCache = <String, String>{};

  GenericScraperAdapter({
    required Dio dio,
    required GenericUrlBuilder urlBuilder,
    required GenericHtmlParser parser,
    required Logger logger,
    required String sourceId,
    Future<void> Function()? delayApplier,
    RateLimiter? rateLimiter,
  })  : _dio = dio,
        _urlBuilder = urlBuilder,
        _parser = parser,
        _logger = logger,
        _sourceId = sourceId,
        _delayApplier = delayApplier,
        _rateLimiter = rateLimiter {
    _readerImages = ReaderImageResolver(
      urlBuilder: urlBuilder,
      parser: parser,
      logger: logger,
      sourceId: sourceId,
    );
    _searchRouting = SearchQueryRouting(
      logger: logger,
      sourceId: sourceId,
    );
  }

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

  Future<void> _prepareRequestDelay() async {
    if (_delayApplier != null) {
      await _delayApplier();
    }
  }

  Future<T> _executeRequest<T>(Future<T> Function() request) async {
    await _prepareRequestDelay();
    if (_rateLimiter == null) {
      return request();
    }
    return _rateLimiter.execute(request);
  }

  // ── search ─────────────────────────────────────────────────────────────────

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    if (scraper == null) {
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }
    final urlPatternsCfg =
        (scraper['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};

    // ── Raw-param mode (from DynamicFormSearchUI) ──────────────────────────
    // Must run BEFORE prefix routing: a raw query value can itself look like
    // a prefix (e.g. "raw:f_search=parody:azur lane"), and the prefix branch
    // would strip it and route to a pattern like "parodySearch" that the
    // source may not have configured. raw: always means the form supplied the
    // query params directly.
    if (filter.query.startsWith('raw:')) {
      return _searchRaw(
        rawParams: filter.query.substring(4),
        page: filter.page,
        rawConfig: rawConfig,
        scraper: scraper,
        urlPatternsCfg: urlPatternsCfg,
      );
    }

    // ── Prefix-based routing (genre:/tag:/author:/artist:/publisher:) ────
    // Map each prefix → {searchPattern, searchPagePattern}
    const prefixMapping = {
      'genre:': ('genreSearch', 'genreSearchPage'),
      'tag:': ('tagSearch', 'tagSearchPage'),
      'author:': ('authorSearch', 'authorSearchPage'),
      'artist:': ('artistSearch', 'artistSearchPage'),
      'publisher:': ('publisherSearch', 'publisherSearchPage'),
      'parody:': ('parodySearch', 'parodySearchPage'),
      'language:': ('languageSearch', 'languageSearchPage'),
      'scanlator:': ('scanlatorSearch', 'scanlatorSearchPage'),
      'release:': ('releaseSearch', 'releaseSearchPage'),
    };

    // Sources with a searchForm send their query as a raw form value, so a
    // value that looks like a prefix (e.g. "parody:azur lane" inside
    // "f_search=...") is search TEXT, not a routing prefix. Only apply
    // prefix routing when the source has no searchForm.
    final usesSearchForm = rawConfig['searchForm'] is Map<String, dynamic>;

    var prefixPatternKey = <String>{};
    if (!usesSearchForm) {
      for (final entry in prefixMapping.entries) {
        if (filter.query.startsWith(entry.key)) {
          final tagValue = filter.query.substring(entry.key.length);
          if (tagValue.isNotEmpty) {
            filter = filter.copyWith(query: tagValue);
            prefixPatternKey = <String>{entry.value.$1, entry.value.$2};
          }
          break;
        }
      }
    }

    // 1) Prefix pattern (genreSearch / tagSearch / authorSearch / …)
    // 2) Type-aware tag filter: type='tag' → tagSearch when the source has a
    //    separate tag taxonomy (e.g. WP /tag/ vs /category/); else genreSearch.
    // 3) Non-empty text   → search / searchPage
    // 4) Empty query      → category-routed browse (if configured)
    // 5) Empty query      → home/homePage fallback
    final String patternKey;
    if (prefixPatternKey.isNotEmpty) {
      patternKey =
          filter.page > 1 && urlPatternsCfg.containsKey(prefixPatternKey.last)
              ? prefixPatternKey.last
              : prefixPatternKey.first;
    } else if (filter.includeTags.isNotEmpty &&
        urlPatternsCfg.containsKey('genreSearch')) {
      const wantsPlainTag = 'tag';
      final firstType = filter.includeTags.first.type.toLowerCase().trim();
      final useTagPattern =
          firstType == wantsPlainTag && urlPatternsCfg.containsKey('tagSearch');
      final baseKey = useTagPattern ? 'tagSearch' : 'genreSearch';
      final pageKey = '${baseKey}Page';
      patternKey = filter.page > 1 && urlPatternsCfg.containsKey(pageKey)
          ? pageKey
          : baseKey;
    } else if (filter.query.trim().isNotEmpty) {
      patternKey = filter.page > 1 && urlPatternsCfg.containsKey('searchPage')
          ? 'searchPage'
          : 'search';
    } else {
      patternKey = _searchRouting.resolveBrowsePatternKey(
        filter: filter,
        scraper: scraper,
        urlPatternsCfg: urlPatternsCfg,
      );
    }

    if (!urlPatternsCfg.containsKey(patternKey)) {
      _logger.w('$_sourceId: URL pattern "$patternKey" not configured');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    final paginationCacheKey = _buildPaginationCacheKey(
      scope: _paginationScopeForPatternKey(patternKey),
      filter: filter,
    );

    final (url, listConfig) = _resolvePattern(
      scraper,
      patternKey,
      filter: filter,
    );
    if (url.isEmpty) {
      _logger.w('$_sourceId: empty URL for pattern "$patternKey"');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }
    if (listConfig == null) {
      _logger
          .w('$_sourceId: no "list" block configured in pattern "$patternKey"');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    var pagedUrl = _resolveListRequestUrlFromCursorCache(
      page: filter.page,
      cacheKey: paginationCacheKey,
    );

    pagedUrl = await _tryPrimeCursorPagination(
          requestUrl: pagedUrl,
          page: filter.page,
          patternKey: patternKey,
          listConfig: listConfig,
          rawConfig: rawConfig,
          paginationCacheKey: paginationCacheKey,
          initialUrl: url,
        ) ??
        pagedUrl;

    pagedUrl ??= _searchRouting.ensurePageQueryForStandardSearch(
      resolvedUrl: url,
      patternKey: patternKey,
      filter: filter,
      rawConfig: rawConfig,
      urlPatternsCfg: urlPatternsCfg,
    );

    _logger.d('$_sourceId scraper [$patternKey]: $pagedUrl');
    return _fetchListPage(
      pagedUrl,
      rawConfig,
      listConfig,
      currentPage: filter.page,
      paginationCacheKey: paginationCacheKey,
      defaultLanguage: rawConfig['defaultLanguage'] as String?,
    );
  }

  // Handle `raw:` query format produced by [DynamicFormSearchUI].
  ///
  // Parses the raw query-param string and builds the final URL by taking the
  // base path of the appropriate URL pattern (strip any `?…` template vars)
  // and appending all raw params + the page param.
  Future<AdapterSearchResult> _searchRaw({
    required String rawParams,
    required int page,
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> scraper,
    required Map<String, dynamic> urlPatternsCfg,
  }) async {
    // Parse raw params (e.g. "s=manga&status=ongoing")
    final rawMap = <String, List<String>>{};
    for (final pair in rawParams.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) continue;
      final key = _searchRouting.safeDecodeComponent(pair.substring(0, idx));
      final value = _searchRouting.safeDecodeComponent(pair.substring(idx + 1));
      rawMap.putIfAbsent(key, () => <String>[]).add(value);
    }

    String? firstRawValue(String key) {
      final values = rawMap[key];
      if (values == null || values.isEmpty) return null;
      final value = values.first.trim();
      return value.isEmpty ? null : value;
    }

    // Determine which URL pattern to use from searchForm config.
    final searchFormCfg = rawConfig['searchForm'] as Map<String, dynamic>?;

    // Check if raw params override the pattern key explicitly
    final overridePatternKey = firstRawValue('patternKey');
    if (overridePatternKey != null) {
      rawMap.remove('patternKey');
    }

    final formParamsCfg =
        (searchFormCfg?['params'] as Map?)?.cast<String, dynamic>() ?? {};

    final basePatternKey = overridePatternKey ??
        _resolveFieldDrivenPatternKey(
          rawMap: rawMap,
          formParamsCfg: formParamsCfg,
        ) ??
        (searchFormCfg?['urlPattern'] as String?) ??
        'search';

    final queryParamName = ((formParamsCfg['query']
            as Map<String, dynamic>?)?['queryParam'] as String?) ??
        'query';
    final tagParamName = ((formParamsCfg['tag']
            as Map<String, dynamic>?)?['queryParam'] as String?) ??
        'tag';
    final categoryParamName = ((formParamsCfg['category']
            as Map<String, dynamic>?)?['queryParam'] as String?) ??
        'category';

    final rawQueryValue =
        firstRawValue(queryParamName) ?? firstRawValue('query');
    final rawTagValue = firstRawValue(tagParamName) ?? firstRawValue('tag');
    final rawCategoryValue =
        firstRawValue(categoryParamName) ?? firstRawValue('category');

    // Prefer category browse routing when form sends only category in raw mode,
    // e.g. "raw:type=Doujinshi" with empty text query.
    String patternKey;
    if (rawQueryValue == null &&
        rawTagValue == null &&
        rawCategoryValue != null) {
      patternKey = _searchRouting.resolveBrowsePatternKey(
        filter: SearchFilter(
          query: '',
          page: page,
          category: rawCategoryValue,
        ),
        scraper: scraper,
        urlPatternsCfg: urlPatternsCfg,
      );
      rawMap.remove(categoryParamName);
      rawMap.remove('category');
    } else {
      // Prefer `{pattern}Page` variant for page > 1 when provided by config.
      final pagedPatternKey = '${basePatternKey}Page';
      patternKey = page > 1 && urlPatternsCfg.containsKey(pagedPatternKey)
          ? pagedPatternKey
          : basePatternKey;
    }

    if (!urlPatternsCfg.containsKey(patternKey)) {
      _logger.w('$_sourceId: raw search — URL pattern "$patternKey" not found');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    final pagedPatternKey = '${basePatternKey}Page';

    // Resolve list config from the URL pattern (for pagination/selector info).
    // We use a dummy SearchFilter to call _resolvePattern just for the listConfig.
    final (_, listConfig) = _resolvePattern(
      scraper,
      patternKey,
      filter: SearchFilter(query: '', page: page),
    );
    if (listConfig == null) {
      _logger.w(
          '$_sourceId: raw search — no list config in pattern "$patternKey"');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    // Derive page query key from config/template (generic, no source hardcode).
    final pageParam = _searchRouting.resolvePageParamName(
      rawConfig: rawConfig,
      urlPatternsCfg: urlPatternsCfg,
      patternKeys: [patternKey, pagedPatternKey, basePatternKey],
    );
    final paginationCacheKey = _buildRawPaginationCacheKey(
      scope: _paginationScopeForPatternKey(patternKey),
      rawMap: rawMap,
    );

    // Build the base URL path and keep template query defaults.
    final patternValue = urlPatternsCfg[patternKey];
    String basePath = '';
    String templateQuery = '';
    if (patternValue is String) {
      basePath = patternValue;
    } else if (patternValue is Map<String, dynamic>) {
      basePath = (patternValue['url'] as String?) ?? '';
    }

    // Extract template query (if any) so we can preserve required keys
    // like `title=` when caller raw params omit them.
    final qIdx = basePath.indexOf('?');
    if (qIdx >= 0) {
      templateQuery = basePath.substring(qIdx + 1);
      basePath = basePath.substring(0, qIdx);
    }

    // Resolve path placeholders from raw params for templates like
    // /search/keyword/{query}/ and /search/tag/{tag}/.

    final queryInPathTemplate = basePath.contains('{query}');
    final tagInPathTemplate = basePath.contains('{tag}');

    if (rawQueryValue != null) {
      basePath = basePath.replaceAll(
          '{query}', Uri.encodeQueryComponent(rawQueryValue));
    }
    // Tag value for the path: the field whose urlPattern routed us here (e.g.
    // `genre=action` → genreSearch), else the generic `tag` param. Compare
    // against the base key so `{pattern}Page` variants still match.
    final pathTagValue = _pathTagValueForPatternKey(
          rawMap: rawMap,
          formParamsCfg: formParamsCfg,
          patternKey: patternKey.endsWith('Page')
              ? patternKey.substring(0, patternKey.length - 4)
              : patternKey,
        ) ??
        rawTagValue;
    if (pathTagValue != null) {
      final normalizedTag = pathTagValue.toLowerCase().replaceAll(' ', '-');
      basePath =
          basePath.replaceAll('{tag}', Uri.encodeQueryComponent(normalizedTag));
    }

    if (queryInPathTemplate) {
      rawMap.remove(queryParamName);
      rawMap.remove('query');
    }
    if (tagInPathTemplate) {
      rawMap.remove(tagParamName);
      rawMap.remove('tag');
    }
    // The routing field's value now lives in the path — drop it from the
    // query string so `/genres/{tag}/` is not fetched with a stray
    // `?genre={tag}` appended. Match on the base key for `{pattern}Page`.
    final routingBaseKey = patternKey.endsWith('Page')
        ? patternKey.substring(0, patternKey.length - 4)
        : patternKey;
    for (final entry in rawMap.keys.toList()) {
      final fieldCfg = formParamsCfg[entry];
      if (fieldCfg is! Map<String, dynamic>) continue;
      if (fieldCfg['urlPattern']?.toString() == routingBaseKey &&
          (fieldCfg['type']?.toString() == 'tag')) {
        rawMap.remove(entry);
      }
    }

    final hasPageInPathTemplate = basePath.contains('{page}');
    final hasPageInQueryTemplate = _searchRouting.queryContainsPagePlaceholder(templateQuery);
    // Substitute {page} if present in path (some sources embed page in path).
    basePath = basePath.replaceAll('{page}', page.toString());

    // Clean unreplaced placeholders in path to avoid `%7Bquery%7D` leak.
    basePath = basePath.replaceAll('{query}', '');
    basePath = basePath.replaceAll('{tag}', '');

    final isAbsolutePath = Uri.tryParse(basePath)?.hasScheme ?? false;
    if (!isAbsolutePath) {
      basePath = basePath.replaceAll('//', '/');
      if (!basePath.startsWith('/')) {
        basePath = '/$basePath';
      } else {
        while (basePath.contains('//')) {
          basePath = basePath.replaceAll('//', '/');
        }
      }
    }

    // Merge template query defaults with raw params (raw params take priority).
    // This keeps mandatory params from template, e.g. `title=value`.
    // Only merge raw params that have non-empty values to avoid overwriting
    // template defaults like `post_type=manga` with `post_type=`.
    final mergedParams = <String, List<String>>{};
    if (templateQuery.isNotEmpty) {
      for (final pair in templateQuery.split('&')) {
        if (pair.isEmpty) continue;
        final idx = pair.indexOf('=');
        final key = idx < 0 ? pair : pair.substring(0, idx);
        if (key.isEmpty) continue;
        var value = idx < 0 ? '' : pair.substring(idx + 1);
        final decodedValue = _searchRouting.safeDecodeComponent(value);
        if (decodedValue == '{query}' || decodedValue == '{tag}') {
          // Template key (e.g. `q={query}`) may differ from the raw form key
          // (`query=...`). Re-key the matching raw param onto the template
          // slot so it flows through the normal merge + encoding path below
          // (leaving `?q=&query=maid` makes sites ignore the search text).
          final isQuery = decodedValue == '{query}';
          final sourceKeys = isQuery
              ? <String>{queryParamName, 'query'}
              : <String>{tagParamName, 'tag'};
          final rawValues = <String>[];
          for (final k in sourceKeys) {
            final v = rawMap[k];
            if (v != null && v.isNotEmpty && v.first.isNotEmpty) {
              rawValues.add(v.first);
            }
          }
          var resolved = rawValues.isEmpty
              ? (isQuery ? rawQueryValue : rawTagValue)
              : rawValues.first;
          if (!isQuery && resolved != null) {
            resolved = resolved.toLowerCase().replaceAll(' ', '-');
          }
          value = resolved ?? '';
          for (final k in sourceKeys) {
            rawMap.remove(k);
          }
          mergedParams[key] = <String>[value];
          continue;
        } else if (decodedValue == '{page}') {
          value = page.toString();
        }
        mergedParams[key] = <String>[value];
      }
    }
    // Pagination is controlled by adapter/page argument. Remove stale page
    // values supplied from raw query params before merging; template/default
    // page (e.g. p={page}) should remain intact.
    final pageKeys = <String>{pageParam, 'page', 'paged', 'p'};
    for (final key in pageKeys) {
      rawMap.remove(key);
    }

    // Only add raw params with non-empty values
    rawMap.forEach((key, values) {
      if (values.isNotEmpty && values.first.isNotEmpty) {
        mergedParams[key] = values;
      }
    });

    // Assemble final query string.
    final queryParts = <String>[];
    mergedParams.forEach((k, values) {
      for (var i = 0; i < values.length; i++) {
        var key = k;
        // WordPress-style paged routes sometimes expect indexed array keys
        // (e.g. genre[0]=anal) instead of repeated genre[]=anal pairs.
        if (page > 1 && key.endsWith('[]')) {
          key = '${key.substring(0, key.length - 2)}[$i]';
        }
        queryParts.add('$key=${_searchRouting.encodeRawQueryValue(key, values[i])}');
      }
    });

    // Only append page query param when actually paginating and path does not
    // already encode page (many WordPress routes reject `page=1`).
    if (page > 1 && !hasPageInPathTemplate && !hasPageInQueryTemplate) {
      queryParts.add('$pageParam=${Uri.encodeComponent(page.toString())}');
    }

    final baseUrl = _urlBuilder.resolve(basePath, {});
    final finalUrl =
        queryParts.isEmpty ? baseUrl : '$baseUrl?${queryParts.join('&')}';

    var requestUrl = _resolveListRequestUrlFromCursorCache(
      page: page,
      cacheKey: paginationCacheKey,
    );

    requestUrl = await _tryPrimeCursorPagination(
          requestUrl: requestUrl,
          page: page,
          patternKey: patternKey,
          listConfig: listConfig,
          rawConfig: rawConfig,
          paginationCacheKey: paginationCacheKey,
          initialUrl: finalUrl,
        ) ??
        requestUrl;

    requestUrl ??= finalUrl;

    _logger.d('$_sourceId scraper [raw/$patternKey]: $requestUrl');
    return _fetchListPage(
      requestUrl,
      rawConfig,
      listConfig,
      currentPage: page,
      paginationCacheKey: paginationCacheKey,
      defaultLanguage: rawConfig['defaultLanguage'] as String?,
    );
  }













  Future<Response<String>> _getWithRedirectFallback(
    String url, {
    required Map<String, dynamic> rawConfig,
  }) async {
    final headers = _resolveRequestHeaders(rawConfig, fallbackReferer: url);

    final initialResponse = await _executeRequest<Response<String>>(
      () => _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      ),
    );

    final initialStatus = initialResponse.statusCode ?? 0;
    if (_isSuccessStatus(initialStatus)) {
      return initialResponse;
    }

    // 🚀 CRITICAL: Detect Cloudflare 403 and throw so WebViewSessionAdapter can handle it
    // GenericScraperAdapter uses validateStatus < 500 to be permissive, but this prevents
    // Cloudflare 403 from being caught by WebViewSessionAdapter.
    // Solution: manually check for CF 403 and throw DioException so WebView can trigger.
    if (initialStatus == 403) {
      final cfMitigated = initialResponse.headers.value('cf-mitigated');
      if (cfMitigated != null) {
        _logger.w(
            '$_sourceId detected Cloudflare 403 (cf-mitigated: $cfMitigated), throwing for WebViewSessionAdapter');
        throw DioException.badResponse(
          statusCode: 403,
          requestOptions: initialResponse.requestOptions,
          response: initialResponse,
        );
      }
    }

    if (_isRedirectStatus(initialStatus)) {
      final location = initialResponse.headers.value('location')?.trim();
      if (location != null && location.isNotEmpty) {
        final resolvedUrl = Uri.parse(url).resolve(location).toString();
        if (!_isAllowedRedirect(Uri.parse(url), Uri.parse(resolvedUrl))) {
          _logger.w(
              '$_sourceId redirect rejected: $url -> $resolvedUrl (host not allowed or protocol downgrade)');
          throw DioException.badResponse(
            statusCode: initialStatus,
            requestOptions: initialResponse.requestOptions,
            response: initialResponse,
          );
        }
        final resolvedResponse = await _executeRequest<Response<String>>(
          () => _dio.get<String>(
            resolvedUrl,
            options: Options(
              responseType: ResponseType.plain,
              headers: headers,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
        );

        if (_isSuccessStatus(resolvedResponse.statusCode)) {
          return resolvedResponse;
        }

        // 🚀 Also detect CF 403 in resolved redirect response
        final resolvedStatus = resolvedResponse.statusCode ?? 0;
        if (resolvedStatus == 403) {
          final cfMitigated = resolvedResponse.headers.value('cf-mitigated');
          if (cfMitigated != null) {
            _logger.w(
                '$_sourceId detected Cloudflare 403 in redirect target (cf-mitigated: $cfMitigated), throwing for WebViewSessionAdapter');
            throw DioException.badResponse(
              statusCode: 403,
              requestOptions: resolvedResponse.requestOptions,
              response: resolvedResponse,
            );
          }
        }
      }

      // Some WAFs (for example Sucuri) may respond with redirect status but no
      // Location header when client fingerLogger().i looks suspicious. In that case,
      // retry once with an isolated clean Dio instance so inherited global
      // headers from other sources do not leak into this request.
      if (location == null || location.isEmpty) {
        _logger.w(
          '$_sourceId redirect loop without Location, retrying with isolated client: $url',
        );

        final isolatedHeaders = _resolveIsolatedHeaders(headers);
        final fallbackUrls = _buildRedirectLoopFallbackUrls(
          url,
          rawConfig: rawConfig,
        );

        for (final candidateUrl in fallbackUrls) {
          try {
            final isolatedResponse = await _fetchWithIsolatedClient(
              candidateUrl,
              headers: isolatedHeaders,
            );

            if (_isSuccessStatus(isolatedResponse.statusCode)) {
              _logger.i(
                '$_sourceId isolated fallback succeeded: $candidateUrl (${isolatedResponse.statusCode})',
              );
              return isolatedResponse;
            }

            // 🚀 Also check for CF 403 in isolated response
            final isolatedStatus = isolatedResponse.statusCode ?? 0;
            if (isolatedStatus == 403) {
              final cfMitigated =
                  isolatedResponse.headers.value('cf-mitigated');
              if (cfMitigated != null) {
                _logger.w(
                    '$_sourceId detected Cloudflare 403 in isolated fallback (cf-mitigated: $cfMitigated), throwing for WebViewSessionAdapter');
                throw DioException.badResponse(
                  statusCode: 403,
                  requestOptions: isolatedResponse.requestOptions,
                  response: isolatedResponse,
                );
              }
            }
          } on DioException catch (isolatedError) {
            _logger.w(
              '$_sourceId isolated fallback failed for $candidateUrl',
              error: isolatedError,
            );
          }
        }
      }
    }

    throw DioException.badResponse(
      statusCode: initialStatus,
      requestOptions: initialResponse.requestOptions,
      response: initialResponse,
    );
  }

  Future<Response<String>> _fetchWithIsolatedClient(
    String url, {
    required Map<String, dynamic> headers,
  }) async {
    final isolatedDio = Dio(
      BaseOptions(
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
        responseType: ResponseType.plain,
        followRedirects: false,
        maxRedirects: 5,
        headers: headers,
      ),
    );

    try {
      return await isolatedDio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } finally {
      isolatedDio.close(force: true);
    }
  }

  Map<String, dynamic> _resolveIsolatedHeaders(Map<String, dynamic> headers) {
    final isolated = <String, dynamic>{};

    final userAgent = headers['User-Agent']?.toString();
    final referer = headers['Referer']?.toString();

    isolated['User-Agent'] = (userAgent == null || userAgent.isEmpty)
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        : userAgent;
    isolated['Accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
    isolated['Accept-Language'] = 'en-US,en;q=0.9';
    if (referer != null && referer.isNotEmpty) {
      isolated['Referer'] = referer;
    }

    return isolated;
  }

  Map<String, dynamic> _resolveRequestHeaders(
    Map<String, dynamic> rawConfig, {
    required String fallbackReferer,
  }) {
    final headers = <String, dynamic>{};
    final network = rawConfig['network'];
    if (network is Map<String, dynamic>) {
      final rawHeaders = network['headers'];
      if (rawHeaders is Map<String, dynamic>) {
        headers.addAll(rawHeaders);
      }
    }

    headers.putIfAbsent('Referer', () => fallbackReferer);
    return headers;
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  bool _isAllowedRedirect(Uri origin, Uri target) {
    if (target.scheme != 'https' && origin.scheme == 'https') {
      return false; // protocol downgrade
    }
    final originDomain = registrableDomain(origin);
    final targetDomain = registrableDomain(target);
    if (originDomain == null || targetDomain == null) return false;
    return originDomain == targetDomain;
  }

  bool _isSuccessStatus(int? statusCode) {
    if (statusCode == null) return false;
    return statusCode >= 200 && statusCode < 300;
  }

  List<String> _buildRedirectLoopFallbackUrls(
    String originalUrl, {
    required Map<String, dynamic> rawConfig,
  }) {
    final urls = <String>[originalUrl];

    final baseUrl = rawConfig['baseUrl'] as String?;
    if (baseUrl != null && baseUrl.isNotEmpty) {
      final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      urls.add(normalizedBase);
      urls.add('${normalizedBase}page/1/');
    }

    final originalUri = Uri.tryParse(originalUrl);
    if (originalUri != null && originalUri.path == '/') {
      urls.add(originalUri.replace(path: '/page/1/').toString());
    }

    return urls.toSet().toList();
  }

  // ── fetchDetail ────────────────────────────────────────────────────────────

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    final urlPatternsCfg =
        (scraper?['urlPatterns'] as Map<String, dynamic>?) ?? {};
    final detailTemplate = _searchRouting.patternUrl(urlPatternsCfg, 'detail');
    Logger().i(
        '[$_sourceId] getDetail: contentId=$contentId, detailTemplate=$detailTemplate');
    if (detailTemplate.isEmpty) {
      Logger().i('[$_sourceId] ERROR: no detail URL pattern configured');
      _logger.w('$_sourceId: no scraper detail URL pattern configured');
      return AdapterDetailResult(
          content: _emptyContent(contentId), imageUrls: []);
    }

    final url = _urlBuilder.buildDetailUrl(detailTemplate, contentId);
    Logger().i('[$_sourceId] getDetail: fetching URL=$url');
    _logger.d('$_sourceId scraper detail: $url');
    final requestHeaders =
        _resolveRequestHeaders(rawConfig, fallbackReferer: url);

    try {
      Logger().i('[$_sourceId] getDetail: about to fetch...');
      final response = await _executeRequest<Response<String>>(
        () => _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: requestHeaders,
            // ponytail: permissive like other fetch paths — 5xx (e.g. b36's
            // intermittent 502) should surface as empty parse result so
            // callers can retry, not as a hard DioException.
            validateStatus: (status) => status != null && status < 500,
          ),
        ),
      );
      Logger().i(
          '[$_sourceId] getDetail: response received, status=${response.statusCode}');
      Logger().i(
          '[$_sourceId] getDetail: response.data type=${response.data.runtimeType}, length=${response.data?.length}');

      final selectors = (scraper?['selectors'] as Map<String, dynamic>?) ?? {};
      final detailCfg = (selectors['detail'] as Map<String, dynamic>?) ?? {};
      final fieldsConfig =
          (detailCfg['fields'] as Map?)?.cast<String, dynamic>() ?? {};

      // Next.js obfuscated JSON detail (nicomanga redesign): the static DOM
      // carries only skeletons; content lives in `chaotic_payload`. When a
      // decode succeeds it replaces DOM extraction entirely.
      final chaoticDecoded = _readerImages.decodeChaoticPayload(
        response.data ?? '',
        key: detailCfg['chaoticKey'] as String?,
      );
      if (chaoticDecoded != null) {
        try {
          final payload = json.decode(chaoticDecoded) as Map<String, dynamic>;
          final chaotic = _extractChaoticDetailFields(payload, detailCfg);
          return AdapterDetailResult(
            content: GenericContentMapper.toDetail(
              contentId,
              chaotic,
              sourceId: _sourceId,
              chapters: _chaoticChapters(payload),
            ),
            imageUrls: const [],
          );
        } catch (e) {
          _logger.w('$_sourceId chaotic detail parse failed: $e');
        }
      }

      final doc = _parser.parse(response.data ?? '');

      Logger().i(
          '[$_sourceId] getDetail: fieldsConfig keys=${fieldsConfig.keys.toList()}');

      final fields = _extractDocumentFields(doc, fieldsConfig);
      Logger().i(
          '[$_sourceId] getDetail: extracted fields=${fields.keys.toList()}');

      // ── Chapters ──────────────────────────────────────────────────────────
      List<Chapter>? chapters;
      final chaptersCfg = detailCfg['chapters'] as Map<String, dynamic>?;
      if (chaptersCfg != null &&
          (chaptersCfg['mode'] as String?) == 'ajaxHtml' &&
          chaptersCfg['container'] is String) {
        // Madara-style: chapter list renders only via POST
        // `{detailUrl}ajax/chapters/` returning an HTML fragment with the
        // same container/fields markup as the static page.
        try {
          final ajaxUrl = '$url' 'ajax/chapters/';
          final ajaxResponse = await _executeRequest<Response<String>>(
            () => _dio.post<String>(
              ajaxUrl,
              data: '',
              options: Options(
                responseType: ResponseType.plain,
                headers: requestHeaders,
              ),
            ),
          );
          final ajaxDoc = _parser.parse(ajaxResponse.data ?? '');
          final chFieldsCfg =
              (chaptersCfg['fields'] as Map?)?.cast<String, dynamic>() ?? {};
          chapters = _parser
              .selectAll(ajaxDoc, chaptersCfg['container'] as String)
              .map((el) => GenericContentMapper.toChapter(
                  _extractElementFields(el, chFieldsCfg)))
              .where((ch) => ch.id.isNotEmpty)
              .toList();
          // Some madara theme builds answer `{detailUrl}ajax/chapters/` with
          // the FULL page (holder spinner still unresolved) instead of a
          // fragment — manhwaclub.net, mangaforfree.com. Those load the list
          // via admin-ajax `manga_get_chapters` keyed by the holder's
          // data-id. Fall back when the fragment yielded nothing.
          if (chapters.isEmpty &&
              doc.querySelector('#manga-chapters-holder') != null) {
            final dataId = doc
                    .querySelector('#manga-chapters-holder')!
                    .attributes['data-id'] ??
                '';
            if (dataId.isNotEmpty) {
              final baseUri = Uri.parse(url);
              final adminAjaxUrl = baseUri
                  .replace(
                      path: '/wp-admin/admin-ajax.php', query: '', fragment: '')
                  .toString();
              final adminResponse = await _executeRequest<Response<String>>(
                () => _dio.post<String>(
                  adminAjaxUrl,
                  data: 'action=manga_get_chapters&manga=$dataId',
                  options: Options(
                    responseType: ResponseType.plain,
                    headers: {
                      ...requestHeaders,
                      'Content-Type': 'application/x-www-form-urlencoded',
                    },
                  ),
                ),
              );
              final adminDoc = _parser.parse(adminResponse.data ?? '');
              chapters = _parser
                  .selectAll(adminDoc, chaptersCfg['container'] as String)
                  .map((el) => GenericContentMapper.toChapter(
                      _extractElementFields(el, chFieldsCfg)))
                  .where((ch) => ch.id.isNotEmpty)
                  .toList();
              _logger.d(
                  '$_sourceId: madaraAdminAjax chapters=${chapters.length} for $contentId');
            }
          }
          _logger.d(
              '$_sourceId: ajaxHtml chapters=${chapters.length} for $contentId');
        } catch (e) {
          _logger.w('$_sourceId ajaxHtml chapters failed, falling back to DOM',
              error: e);
        }
      }
      if (chapters == null && chaptersCfg != null) {
        final containerSel = chaptersCfg['container'] as String?;
        final chFieldsCfg =
            (chaptersCfg['fields'] as Map?)?.cast<String, dynamic>() ?? {};
        if (containerSel != null) {
          final chEls = _parser.selectAll(doc, containerSel);
          chapters = chEls
              .map((el) {
                final chFields = _extractElementFields(el, chFieldsCfg);
                return GenericContentMapper.toChapter(chFields);
              })
              .where((ch) =>
                  ch.id.isNotEmpty &&
                  !ch.title.startsWith('Read First') &&
                  !ch.title.startsWith('Read Last'))
              .toList();
           _logger.d(
               '$_sourceId: extracted ${chapters.length} chapters for $contentId');
         }
         // Deduplicate chapters by url/id (handles duplicate pagination blocks
         // like xiutaku top+bottom nav, or misskon repeated page-link).
         if (chapters != null && chapters.isNotEmpty) {
           final seen = <String>{};
           final deduped = <Chapter>[];
           for (final ch in chapters) {
             final key = ch.url.isNotEmpty ? ch.url : ch.id;
             if (seen.add(key)) deduped.add(ch);
           }
           chapters = deduped;
           _logger.d(
               '$_sourceId: deduped to ${chapters.length} chapters for $contentId');
         }
         // If chapters were extracted but current page is not among them,
         // add it as chapter 1 so the detail page itself is readable.
         // Requires explicit opt-in via chapters.addCurrentPageAsChapter=true.
         final addCurrentPageAsChapter =
             (chaptersCfg['addCurrentPageAsChapter'] as bool?) ?? false;
        if (addCurrentPageAsChapter &&
            chapters != null &&
            chapters.isNotEmpty) {
          final currentPath = Uri.parse(url).path;
          final hasCurrent = chapters.any((ch) {
            final chPath =
                ch.url.startsWith('http') ? Uri.parse(ch.url).path : ch.url;
            return chPath == currentPath || ch.id == currentPath;
          });
          if (!hasCurrent) {
            chapters.insert(0, Chapter(id: currentPath, title: '1', url: url));
            _logger.d(
                '$_sourceId: added current page as chapter 1 for $contentId');
          }
        }
      }

      var content = GenericContentMapper.toDetail(
        contentId,
        fields,
        sourceId: _sourceId,
        chapters: chapters,
      );

      final defaultLang = rawConfig['defaultLanguage'] as String?;
      if (defaultLang != null &&
          (content.language.isEmpty || content.language == 'unknown')) {
        content = content.copyWith(language: defaultLang);
      }

      final readerConfig = selectors['reader'] as Map<String, dynamic>?;
      List<String> detailImageUrls = const [];
      final hasChapters = chapters?.isNotEmpty == true;
      final shouldHydrateDetailImages = readerConfig != null &&
          !hasChapters &&
          (readerConfig['mode'] as String?) != 'chapterDataScript';
      if (shouldHydrateDetailImages) {
        final imagesDef = readerConfig['images'];
        final defMap = _toDefMap(imagesDef);
        if (defMap != null) {
          final sel = _readerImages.fieldDefToSelector(defMap);
          if (sel != null) {
            final seen = <String>{};
            detailImageUrls = _parser
                .extractList(doc, sel)
                .map((u) => u.trim())
                .where((u) => u.isNotEmpty)
                .map((u) => _readerImages.sanitizeImageUrl(u))
                .map((u) => _urlBuilder.resolve(u, const {}))
                .where((u) => seen.add(u))
                .toList();
          }
        }
      }

      if (detailImageUrls.isNotEmpty) {
        content = content.copyWith(
          imageUrls: detailImageUrls,
          pageCount: detailImageUrls.length,
        );
      }

      return AdapterDetailResult(content: content, imageUrls: detailImageUrls);
    } on DioException catch (e, stack) {
      Logger().i(
          '[$_sourceId] getDetail ERROR (DioException): ${e.message}, statusCode=${e.response?.statusCode}');
      Logger().i('[$_sourceId] stack: $stack');
      // 🚀 Re-throw Cloudflare 403 so WebViewSessionAdapter can handle it
      if (e.response?.statusCode == 403) {
        final cfMitigated = e.response?.headers.value('cf-mitigated');
        if (cfMitigated != null) {
          _logger.w(
              '$_sourceId detected Cloudflare 403 in detail page for $contentId, re-throwing for WebViewSessionAdapter');
          rethrow;
        }
      }
      _logger.e('$_sourceId scraper detail failed for $contentId', error: e);
      return AdapterDetailResult(
          content: _emptyContent(contentId), imageUrls: []);
    } catch (e, stack) {
      Logger().e('[$_sourceId] getDetail ERROR (Exception): $e');
      Logger().e('[$_sourceId] stack: $stack');
      _logger.e('$_sourceId scraper detail failed for $contentId', error: e);
      return AdapterDetailResult(
          content: _emptyContent(contentId), imageUrls: []);
    }
  }

  // ── fetchRelated / fetchComments ───────────────────────────────────────────

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    final urlPatternsCfg =
        (scraper?['urlPatterns'] as Map<String, dynamic>?) ?? {};
    final detailTemplate = _searchRouting.patternUrl(urlPatternsCfg, 'detail');
    if (detailTemplate.isEmpty) return const [];

    final selectors = (scraper?['selectors'] as Map<String, dynamic>?) ?? {};
    final relatedCfg = selectors['related'] as Map<String, dynamic>?;
    if (relatedCfg == null) return const [];

    final containerSel = relatedCfg['container'] as String?;
    final fieldsConfig =
        (relatedCfg['fields'] as Map<String, dynamic>?) ?? const {};
    if (containerSel == null || containerSel.isEmpty || fieldsConfig.isEmpty) {
      return const [];
    }

    final url = _urlBuilder.buildDetailUrl(detailTemplate, contentId);
    final requestHeaders =
        _resolveRequestHeaders(rawConfig, fallbackReferer: url);

    try {
      final response = await _executeRequest<Response<String>>(
        () => _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: requestHeaders,
          ),
        ),
      );
      final doc = _parser.parse(response.data ?? '');
      final relatedEls = _parser.selectAll(doc, containerSel);
      if (relatedEls.isEmpty) return const [];

      final defaultLang = rawConfig['defaultLanguage'] as String?;
      final seenIds = <String>{};
      final related = <Content>[];

      for (final el in relatedEls) {
        final fields = _extractElementFields(el, fieldsConfig);
        var item = GenericContentMapper.toListItem(fields, sourceId: _sourceId);

        if (defaultLang != null &&
            (item.language.isEmpty || item.language == 'unknown')) {
          item = item.copyWith(language: defaultLang);
        }

        if (item.id.isEmpty ||
            item.id == contentId ||
            seenIds.contains(item.id)) {
          continue;
        }

        seenIds.add(item.id);
        related.add(item);
      }

      return related;
    } on DioException catch (e) {
      // 🚀 Re-throw Cloudflare 403 so WebViewSessionAdapter can handle it
      if (e.response?.statusCode == 403) {
        final cfMitigated = e.response?.headers.value('cf-mitigated');
        if (cfMitigated != null) {
          _logger.w(
              '$_sourceId detected Cloudflare 403 in related content for $contentId, re-throwing for WebViewSessionAdapter');
          rethrow;
        }
      }
      _logger.e('$_sourceId scraper related fetch failed for $contentId',
          error: e);
      return const [];
    } catch (e) {
      _logger.e('$_sourceId scraper related fetch failed for $contentId',
          error: e);
      return const [];
    }
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    final urlPatternsCfg =
        (scraper?['urlPatterns'] as Map<String, dynamic>?) ?? {};
    final detailTemplate = _searchRouting.patternUrl(urlPatternsCfg, 'detail');
    if (detailTemplate.isEmpty) return const [];

    final selectors = (scraper?['selectors'] as Map<String, dynamic>?) ?? {};
    final detailCfg = selectors['detail'] as Map<String, dynamic>?;
    final commentsCfg = (detailCfg?['comments'] as Map<String, dynamic>?) ??
        (selectors['comments'] as Map<String, dynamic>?);
    if (commentsCfg == null) return const [];

    final url = _urlBuilder.buildDetailUrl(detailTemplate, contentId);
    String? cachedDetailHtml;
    final detailRequestHeaders =
        _resolveRequestHeaders(rawConfig, fallbackReferer: url);

    // 1) API-first comments path (e.g. HentaiFox includes/comments.php)
    final commentsEndpoint = commentsCfg['endpoint'] as String?;
    if (commentsEndpoint != null && commentsEndpoint.isNotEmpty) {
      try {
        final galleryIdParam =
            (commentsCfg['galleryIdParam'] as String?) ?? 'gallery_id';
        final commentsUrl = _urlBuilder.resolve(commentsEndpoint, const {});

        // comments.php is protected by CSRF/session checks.
        final detailResponse = await _executeRequest<Response<String>>(
          () => _dio.get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              headers: detailRequestHeaders,
            ),
          ),
        );
        cachedDetailHtml = detailResponse.data;

        final csrfToken = _extractCsrfToken(cachedDetailHtml ?? '');
        final cookieHeader = _buildCookieHeader(detailResponse.headers);
        final requestHeaders = <String, dynamic>{
          ...detailRequestHeaders,
          'Referer': url,
          'Origin': Uri.parse(url).origin,
          'X-Requested-With': 'XMLHttpRequest',
          if (csrfToken != null && csrfToken.isNotEmpty)
            'X-CSRF-TOKEN': csrfToken,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        };

        final response = await _executeRequest<Response<dynamic>>(
          () => _dio.post<dynamic>(
            commentsUrl,
            data: {galleryIdParam: contentId},
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              responseType: ResponseType.plain,
              headers: requestHeaders,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
        );

        if (response.statusCode != 200) {
          _logger.w(
            '$_sourceId comments API returned ${response.statusCode} for $contentId',
          );
        }

        final apiComments = _parseApiComments(response.data);
        if (apiComments.isNotEmpty) {
          return apiComments;
        }
      } catch (e) {
        // 🚀 Re-throw Cloudflare 403 so WebViewSessionAdapter can handle it
        if (e is DioException && e.response?.statusCode == 403) {
          final cfMitigated = e.response?.headers.value('cf-mitigated');
          if (cfMitigated != null) {
            _logger.w(
                '$_sourceId detected Cloudflare 403 in comments API for $contentId, re-throwing for WebViewSessionAdapter');
            rethrow;
          }
        }
        _logger.w('$_sourceId comments API failed for $contentId', error: e);
      }
    }

    // 2) HTML fallback comments path

    final containerSel = commentsCfg['container'] as String?;
    final fieldsConfig =
        (commentsCfg['fields'] as Map<String, dynamic>?) ?? const {};
    if (containerSel == null || containerSel.isEmpty || fieldsConfig.isEmpty) {
      return const [];
    }

    try {
      final html = cachedDetailHtml ??
          (await _executeRequest<Response<String>>(
            () => _dio.get<String>(
              url,
              options: Options(
                responseType: ResponseType.plain,
                headers: detailRequestHeaders,
              ),
            ),
          ))
              .data ??
          '';
      final doc = _parser.parse(html);
      final commentEls = _parser.selectAll(doc, containerSel);
      if (commentEls.isEmpty) return const [];

      final seenIds = <String>{};
      final comments = <Comment>[];

      for (final el in commentEls) {
        final fields = _extractElementFields(el, fieldsConfig);

        final id = (fields['id']?.toString() ?? '').trim();
        final username = (fields['username']?.toString() ?? '').trim();
        final body = (fields['body']?.toString() ?? '').trim();
        if (id.isEmpty || username.isEmpty || body.isEmpty) continue;
        if (seenIds.contains(id)) continue;

        final avatarRaw = (fields['avatarUrl']?.toString() ?? '').trim();
        final avatar =
            avatarRaw.isEmpty ? null : _urlBuilder.resolve(avatarRaw, const {});
        final postDateRaw = (fields['postDate']?.toString() ?? '').trim();

        comments.add(
          Comment(
            id: id,
            username: username,
            body: body,
            avatarUrl: avatar,
            postDate: _parseRelativeOrAbsoluteDate(postDateRaw),
          ),
        );
        seenIds.add(id);
      }

      return comments;
    } on DioException catch (e) {
      // 🚀 Re-throw Cloudflare 403 so WebViewSessionAdapter can handle it
      if (e.response?.statusCode == 403) {
        final cfMitigated = e.response?.headers.value('cf-mitigated');
        if (cfMitigated != null) {
          _logger.w(
              '$_sourceId detected Cloudflare 403 in HTML comments for $contentId, re-throwing for WebViewSessionAdapter');
          rethrow;
        }
      }
      _logger.e('$_sourceId scraper comments fetch failed for $contentId',
          error: e);
      return const [];
    } catch (e) {
      _logger.e('$_sourceId scraper comments fetch failed for $contentId',
          error: e);
      return const [];
    }
  }

  String? _extractCsrfToken(String html) {
    if (html.isEmpty) return null;

    final doc = _parser.parse(html);
    final metaEls = _parser.selectAll(doc, 'meta[name="csrf-token"]');
    final token =
        metaEls.isNotEmpty ? metaEls.first.attributes['content']?.trim() : null;
    if (token != null && token.isNotEmpty) {
      return token;
    }

    return RegExp(
      '<meta\\s+name=["\\\']csrf-token["\\\']\\s+content=["\\\']([^"\\\']+)["\\\']',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
  }

  String _buildCookieHeader(Headers headers) {
    final setCookies = headers.map['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return '';

    final cookiePairs = setCookies
        .map((raw) => raw.split(';').first.trim())
        .where((pair) => pair.isNotEmpty)
        .toSet();

    return cookiePairs.join('; ');
  }

  // ── fetchChapterImages ─────────────────────────────────────────────────────

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    final urlPatternsCfg =
        (scraper?['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};
    final chapterTemplate = _searchRouting.patternUrl(urlPatternsCfg, 'chapter');
    if (chapterTemplate.isEmpty) return null;

    // Normalize: strip the chapter template's static prefix from chapterId.
    // Some configs have a broad regex that produces IDs already containing the
    // prefix (e.g. "/manhwa/queen-bee/side-story-3"), causing double prefix when
    // buildDetailUrl prepends it again. Strip leading /baseUrl/path segments
    // that match the template's static part.
    final normalizedId =
        _normalizeChapterIdForTemplate(chapterId, chapterTemplate);
    final url = _urlBuilder.buildDetailUrl(chapterTemplate, normalizedId);
    _logger.d('$_sourceId scraper chapter: $url');
    final chapterRequestHeaders =
        _resolveRequestHeaders(rawConfig, fallbackReferer: url);

    try {
      final response = await _executeRequest<Response<String>>(
        () => _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: chapterRequestHeaders,
          ),
        ),
      );
      final htmlContent = response.data ?? '';

      // Check for captured image URLs from WebView bypass (JSON format)
      if (htmlContent.isNotEmpty && htmlContent.trimLeft().startsWith('{')) {
        try {
          final jsonData = json.decode(htmlContent);
          if (jsonData is Map && jsonData['images'] is List) {
            final imgList = (jsonData['images'] as List).cast<String>();
            if (imgList.isNotEmpty) {
              _logger.d(
                  '$_sourceId using WebView-captured image URLs: ${imgList.length}');
              return ChapterData(images: imgList);
            }
          }
        } catch (_) {}
      }

      final selectors = (scraper?['selectors'] as Map<String, dynamic>?) ?? {};
      final readerConfig = selectors['reader'] as Map<String, dynamic>?;
      if (readerConfig == null) return null;

      // Next.js obfuscated JSON reader (nicomanga redesign): images live in
      // the page's `chaotic_payload` (decoded with the configured key).
      if (readerConfig['mode'] == 'chaoticPayload') {
        final decoded = _readerImages.decodeChaoticPayload(
          htmlContent,
          key: readerConfig['chaoticKey'] as String?,
        );
        if (decoded != null) {
          try {
            final payload = json.decode(decoded) as Map<String, dynamic>;
            final imagesRaw = (payload['images'] as List?) ?? const [];
            final images = imagesRaw
                .whereType<String>()
                .map((u) => u.trim())
                .where((u) => u.isNotEmpty)
                .toList();
            if (images.isNotEmpty) {
              _logger.d(
                  '$_sourceId chaoticPayload reader: ${images.length} images');
              return ChapterData(
                images: _readerImages.normalizeChapterImageUrls(images),
              );
            }
          } catch (e) {
            _logger.w('$_sourceId chaoticPayload reader parse failed: $e');
          }
        }
      }

      // JSON API mode: reader images are not in static HTML (e.g. Next.js
      // SPA), site exposes a POST endpoint returning the image URL list.
      if (readerConfig['mode'] == 'parseChapterApi') {
        final apiPath = (readerConfig['parseChapterApiUrl'] as String?) ??
            '/api/parse-chapter';
        try {
          final apiResponse = await _executeRequest<Response<String>>(
            () => _dio.post<String>(
              _urlBuilder.resolve(apiPath, const {}),
              data: json.encode({'chapterUrl': url}),
              options: Options(
                responseType: ResponseType.plain,
                headers: {
                  ...chapterRequestHeaders,
                  Headers.contentTypeHeader: 'application/json',
                },
              ),
            ),
          );
          final apiData =
              json.decode(apiResponse.data ?? '') as Map<String, dynamic>;
          final imagesRaw = apiData['images'];
          if (imagesRaw is List && imagesRaw.isNotEmpty) {
            final apiImages = imagesRaw
                .whereType<String>()
                .map((u) => u.trim())
                .where((u) => u.isNotEmpty)
                .toList();
            if (apiImages.isNotEmpty) {
              _logger.d(
                  '$_sourceId parseChapterApi returned ${apiImages.length} images');
              return ChapterData(
                images: _readerImages.normalizeChapterImageUrls(apiImages),
              );
            }
          }
          final apiError = apiData['error'];
          if (apiError != null && apiError.toString().isNotEmpty) {
            _logger.w('$_sourceId parseChapterApi error: $apiError');
          }
        } catch (e) {
          _logger.w('$_sourceId parseChapterApi failed, falling back to DOM',
              error: e);
        }
      }

      var workingUrl = url;
      var workingHtmlContent = htmlContent;
      var workingDoc = _parser.parse(workingHtmlContent);

      final readerPageLinkDef = _toDefMap(readerConfig['readerPageLink']);
      if (readerPageLinkDef != null) {
        final readerPageSelector = _readerImages.fieldDefToSelector(readerPageLinkDef);
        final extractedReaderPageUrl = readerPageSelector == null
            ? null
            : _parser.extractString(workingDoc, readerPageSelector)?.trim();
        final resolvedReaderPageUrl =
            extractedReaderPageUrl == null || extractedReaderPageUrl.isEmpty
                ? null
                : _urlBuilder.resolve(extractedReaderPageUrl, const {});

        if (resolvedReaderPageUrl != null &&
            resolvedReaderPageUrl.isNotEmpty &&
            resolvedReaderPageUrl != workingUrl) {
          final readerPageResponse = await _executeRequest<Response<String>>(
            () => _dio.get<String>(
              resolvedReaderPageUrl,
              options: Options(
                responseType: ResponseType.plain,
                headers: _resolveRequestHeaders(
                  rawConfig,
                  fallbackReferer: resolvedReaderPageUrl,
                ),
              ),
            ),
          );
          workingUrl = resolvedReaderPageUrl;
          workingHtmlContent = readerPageResponse.data ?? '';
          workingDoc = _parser.parse(workingHtmlContent);
        }
      }

      List<String> imageUrls = [];
      String? nextId;
      String? prevId;

      // 1. Try ts_reader regex extraction first.
      final regexStr = readerConfig['tsReaderRegex'] as String?;
      if (regexStr != null && regexStr.isNotEmpty) {
        final regex = RegExp(regexStr, dotAll: true);
        final match = regex.firstMatch(workingHtmlContent);
        if (match != null) {
          final jsonStr =
              match.groupCount > 0 ? match.group(1) : match.group(0);
          if (jsonStr != null) {
            final cleanJson =
                jsonStr.replaceAll(r'\/', '/').replaceAll(r'\"', '"');
            try {
              final data = json.decode(cleanJson) as Map<String, dynamic>;
              final sources = data['sources'] as List<dynamic>?;
              if (sources != null && sources.isNotEmpty) {
                final first = sources[0] as Map<String, dynamic>;
                final images = first['images'] as List<dynamic>?;
                if (images != null) {
                  imageUrls = images
                      .map((img) => img.toString())
                      .where((u) => u.isNotEmpty)
                      .toList();
                }
              }
              final prevUrlRaw = data['prevUrl'] as String?;
              final nextUrlRaw = data['nextUrl'] as String?;
              if (prevUrlRaw != null && prevUrlRaw.isNotEmpty) {
                prevId = _extractSlugFromUrl(prevUrlRaw.replaceAll(r'\/', '/'));
              }
              if (nextUrlRaw != null && nextUrlRaw.isNotEmpty) {
                nextId = _extractSlugFromUrl(nextUrlRaw.replaceAll(r'\/', '/'));
              }
            } catch (e) {
              _logger.w('$_sourceId tsReaderRegex JSON parse failed', error: e);
            }
          }
        }
      }

      if (imageUrls.isEmpty &&
          (readerConfig['mode'] as String?) == 'ajaxHtmlImages') {
        imageUrls = await _fetchAjaxHtmlImages(
          rawConfig: rawConfig,
          readerConfig: readerConfig,
          readerDocument: workingDoc,
          readerPageUrl: workingUrl,
        );
      }

      // 2. DOM fallback for images.
      if (imageUrls.isEmpty && readerConfig['mode'] == 'hentaifoxCdn') {
        // Prefer true full-res URL from /g/{id}/1/ page so extension follows
        // the actual gallery format (webp/jpg/jpeg/png).
        final readerPagePattern =
            (readerConfig['readerPageUrlPattern'] as String?) ?? '/g/{id}/1/';
        String? readerSampleUrl;
        var readerPageCount = 0;
        Map<int, String> readerExtByPage = const {};
        try {
          final readerPageUrl = _urlBuilder.resolve(
            readerPagePattern.replaceAll('{id}', chapterId),
            const {},
          );
          final readerResp = await _executeRequest<Response<String>>(
            () => _dio.get<String>(
              readerPageUrl,
              options: Options(
                responseType: ResponseType.plain,
                headers: _resolveRequestHeaders(
                  rawConfig,
                  fallbackReferer: readerPageUrl,
                ),
              ),
            ),
          );
          final readerHtml = readerResp.data ?? '';
          final readerDoc = _parser.parse(readerHtml);
          readerExtByPage = _readerImages.extractHentaiFoxExtensionsByPage(readerHtml);

          final readerImageSelector =
              (readerConfig['readerImageSelector'] as String?) ?? '#gimg';
          final readerImageAttr =
              (readerConfig['readerImageAttr'] as String?) ?? 'data-src';
          readerSampleUrl = _parser.extractString(
            readerDoc,
            FieldSelector(
              selector: readerImageSelector,
              attribute: readerImageAttr,
            ),
          );
          if (readerSampleUrl == null || readerSampleUrl.isEmpty) {
            readerSampleUrl = _parser.extractString(
              readerDoc,
              FieldSelector(selector: readerImageSelector, attribute: 'src'),
            );
          }

          final readerPageCountSelector =
              (readerConfig['readerPageCountSelector'] as String?) ?? '#pages';
          final readerPageCountAttr =
              (readerConfig['readerPageCountAttr'] as String?) ?? 'value';
          final readerPageCountStr = _parser.extractString(
                readerDoc,
                FieldSelector(
                  selector: readerPageCountSelector,
                  attribute: readerPageCountAttr,
                ),
              ) ??
              _parser.extractString(
                readerDoc,
                const FieldSelector(selector: '.total_pages'),
              );

          final readerPagesMatch =
              RegExp(r'(\d+)').firstMatch(readerPageCountStr ?? '');
          readerPageCount =
              int.tryParse(readerPagesMatch?.group(1) ?? '0') ?? 0;

          if ((readerSampleUrl?.isNotEmpty ?? false) && readerPageCount > 0) {
            imageUrls = _readerImages.buildHentaiFoxImageUrlsFromSample(
              readerSampleUrl!,
              readerPageCount,
              readerExtByPage,
            );
          }
        } catch (e) {
          _logger.w(
            '$_sourceId: failed to extract HentaiFox reader-page sample URL',
            error: e,
          );
        }

        final thumbSel = readerConfig['thumbSelector'] as String?;
        final thumbAttr = readerConfig['thumbSrcAttr'] as String? ?? 'src';
        final regexStr = readerConfig['cdnPathRegex'] as String?;
        final pageSelStr = readerConfig['pageCountSelector'] as String?;

        if (imageUrls.isEmpty &&
            thumbSel != null &&
            regexStr != null &&
            pageSelStr != null) {
          // Collect explicit thumb URLs as final fallback only.
          final thumbElements = _parser.selectAll(workingDoc, thumbSel);
          final explicitThumbs = <String>[];
          for (final el in thumbElements) {
            final raw =
                (el.attributes[thumbAttr] ?? el.attributes['src'] ?? '').trim();
            if (raw.isEmpty || raw.startsWith('data:image/')) continue;
            if (raw.startsWith('http://') || raw.startsWith('https://')) {
              explicitThumbs.add(raw);
            }
          }

          final countStr = _parser.extractString(
            workingDoc,
            FieldSelector(selector: pageSelStr),
          );
          final pagesMatch = RegExp(r'(\d+)').firstMatch(countStr ?? '');
          final pageCount = int.tryParse(pagesMatch?.group(1) ?? '0') ?? 0;

          final thumbSrc = _parser.extractString(
            workingDoc,
            FieldSelector(selector: thumbSel, attribute: thumbAttr),
          );

          if (thumbSrc != null && pageCount > 0) {
            final regex = RegExp(regexStr);
            final match = regex.firstMatch(thumbSrc);
            if (match != null && match.groupCount >= 2) {
              final cdnHost = match.group(1);
              final internalPath = match.group(2);

              final preferredExt = _readerImages.inferImageExtension(
                readerSampleUrl?.isNotEmpty == true
                    ? readerSampleUrl
                    : thumbSrc,
              );

              // Prefer metadata-based URL building when hidden fields exist.
              final loadDir = _parser.extractString(
                    workingDoc,
                    const FieldSelector(
                        selector: '#load_dir', attribute: 'value'),
                  ) ??
                  _parser.extractString(
                    workingDoc,
                    const FieldSelector(
                        selector: '#image_dir', attribute: 'value'),
                  );
              final loadId = _parser.extractString(
                    workingDoc,
                    const FieldSelector(
                        selector: '#load_id', attribute: 'value'),
                  ) ??
                  _parser.extractString(
                    workingDoc,
                    const FieldSelector(
                        selector: '#gallery_id', attribute: 'value'),
                  );

              if ((loadDir?.isNotEmpty ?? false) &&
                  (loadId?.isNotEmpty ?? false)) {
                for (int i = 1; i <= pageCount; i++) {
                  imageUrls.add(
                      'https://$cdnHost/$loadDir/$loadId/$i.$preferredExt');
                }
              } else {
                for (int i = 1; i <= pageCount; i++) {
                  imageUrls
                      .add('https://$cdnHost/$internalPath/$i.$preferredExt');
                }
              }
            }
          }

          // Absolute last fallback: keep using explicit thumb URLs.
          if (imageUrls.isEmpty && explicitThumbs.isNotEmpty) {
            imageUrls = explicitThumbs;
          }
        }
      }

      if (imageUrls.isEmpty && readerConfig['mode'] == 'chapterDataScript') {
        imageUrls = _readerImages.extractChapterDataScriptImageUrls(
          workingHtmlContent,
          readerConfig: readerConfig,
        );

        // Fallback: when chapterDataScript fails (e.g. Next.js SPA reader),
        // extract preview images from the detail page and rewrite CDN host.
        if (imageUrls.isEmpty) {
          imageUrls = await _extractDetailPreviewImages(
            rawConfig: rawConfig,
            readerConfig: readerConfig,
            chapterHtmlContent: workingHtmlContent,
          );
        }
      }

      if (imageUrls.isEmpty) {
        imageUrls = _readerImages.extractScriptSlidesImageUrls(workingHtmlContent);
      }

      if (imageUrls.isEmpty) {
        final imagesDef = readerConfig['images'];
        if (imagesDef != null) {
          final defMap = _toDefMap(imagesDef);
          if (defMap != null) {
            var sel = _readerImages.fieldDefToSelector(defMap);
            // Scope the fallback selector to reader.container when the
            // selector isn't already self-scoped: without this, a series-slug
            // fetch (detail page, no ts_reader) scrapes every page img —
            // logos, sidebar thumbs — as fake chapter pages. Regex selectors
            // scrape <script> content, not DOM elements — never scope those.
            final containerSel = (readerConfig['container'] as String?)?.trim();
            if (sel != null &&
                defMap['regex'] == null &&
                containerSel != null &&
                containerSel.isNotEmpty &&
                !sel.selector.startsWith(containerSel)) {
              sel = FieldSelector(
                selector: '$containerSel ${sel.selector}',
                attribute: sel.attribute,
                type: sel.type,
                regex: sel.regex,
                fallback: sel.fallback,
              );
            }
            if (sel != null) {
              imageUrls = _parser.extractList(workingDoc, sel);
            }
          }
        }
      }

      // ── Paginated detail galleries (WP <!--nextpage--> / ?page=) ──
      // e.g. misskon /{id}/2/, xiutaku ?page=2, beauty3600000 /2/
      // Config: reader.pagination.next = CSS selector for pagination links, maxPages guard.
      // Aggregates images from all sub-pages when selector present and first page had images.
      // Fallback auto-detects WP pagination even if config not yet updated (for cached installs).
      final paginationCfg = readerConfig['pagination'] as Map<String, dynamic>?;
      String? pagNextSel = (paginationCfg?['next'] as String?)?.trim();
      int maxPages = 8;
      if (paginationCfg != null) {
        final maxPagesRaw = paginationCfg['maxPages'];
        maxPages = maxPagesRaw is int
            ? maxPagesRaw
            : int.tryParse(maxPagesRaw?.toString() ?? '') ?? 8;
      }
      // Fallback auto-detect for already-installed cached configs without pagination field
      if ((pagNextSel == null || pagNextSel.isEmpty) && imageUrls.isNotEmpty) {
        const fallbackSelectors = [
          'div.page-link a.post-page-numbers',
          '.page-link a.post-page-numbers',
          'nav.pagination a.pagination-link:not(.is-current)',
          'nav.pagination a',
        ];
        for (final sel in fallbackSelectors) {
          final els = _parser.selectAll(workingDoc, sel);
          if (els.isNotEmpty) {
            pagNextSel = sel;
            maxPages = 8;
            _logger.d(
              '$_sourceId reader pagination fallback auto-detected selector "$sel" with ${els.length} links',
            );
            break;
          }
        }
      }
      if (pagNextSel != null && pagNextSel.isNotEmpty && imageUrls.isNotEmpty) {
        try {
          // Build selector for image extraction on sub-pages (same as above with container prefix)
          FieldSelector? pagImageSel;
          final pagImagesDef = readerConfig['images'];
          if (pagImagesDef != null) {
            final pagDefMap = _toDefMap(pagImagesDef);
            if (pagDefMap != null) {
              var s = _readerImages.fieldDefToSelector(pagDefMap);
              final cSel = (readerConfig['container'] as String?)?.trim();
              if (s != null &&
                  pagDefMap['regex'] == null &&
                  cSel != null &&
                  cSel.isNotEmpty &&
                  !s.selector.startsWith(cSel)) {
                s = FieldSelector(
                  selector: '$cSel ${s.selector}',
                  attribute: s.attribute,
                  type: s.type,
                  regex: s.regex,
                  fallback: s.fallback,
                );
              }
              pagImageSel = s;
            }
          }
          if (pagImageSel != null) {
            final visited = <String>{workingUrl};
            final pagEls = _parser.selectAll(workingDoc, pagNextSel);
            final pendingUrls = <String>[];
            for (final el in pagEls) {
              if (el.classes.contains('is-current') ||
                  el.classes.contains('current')) {
                continue;
              }
              final href = (el.attributes['href'] ?? '').trim();
              if (href.isEmpty || href == '#') continue;
              final resolved = Uri.parse(workingUrl).resolve(href).toString();
              if (!visited.contains(resolved) &&
                  !pendingUrls.contains(resolved)) {
                pendingUrls.add(resolved);
              }
            }
            // respect maxPages (first page counts as 1)
            final toFetch = pendingUrls.take(maxPages - 1).toList();
            // fetch each sub-page sequentially (respects rate limit via _executeRequest)
            for (final extraUrl in toFetch) {
              if (visited.length >= maxPages) break;
              try {
                final extraResp = await _executeRequest<Response<String>>(
                  () => _dio.get<String>(
                    extraUrl,
                    options: Options(
                      responseType: ResponseType.plain,
                      headers: _resolveRequestHeaders(
                        rawConfig,
                        fallbackReferer: extraUrl,
                      ),
                    ),
                  ),
                );
                final extraHtml = extraResp.data ?? '';
                if (extraHtml.isEmpty) continue;
                final extraDoc = _parser.parse(extraHtml);
                final extraImages = _parser.extractList(extraDoc, pagImageSel);
                if (extraImages.isNotEmpty) {
                  imageUrls.addAll(extraImages);
                }
                visited.add(extraUrl);
                // discover further pagination from this page if truncated (e.g. 1..3 but actual 5)
                if (toFetch.length < maxPages - 1) {
                  final furtherEls = _parser.selectAll(extraDoc, pagNextSel);
                  for (final el in furtherEls) {
                    final href = (el.attributes['href'] ?? '').trim();
                    if (href.isEmpty) continue;
                    final resolved =
                        Uri.parse(extraUrl).resolve(href).toString();
                    if (!visited.contains(resolved) &&
                        !pendingUrls.contains(resolved) &&
                        !toFetch.contains(resolved) &&
                        visited.length + toFetch.length < maxPages) {
                      toFetch.add(resolved);
                    }
                  }
                }
              } catch (e) {
                _logger.w(
                  '$_sourceId reader pagination fetch failed $extraUrl',
                  error: e,
                );
              }
            }
            if (toFetch.isNotEmpty) {
              // dedup preserve order
              final seen = <String>{};
              imageUrls = imageUrls.where((u) => seen.add(u)).toList();
              _logger.i(
                '$_sourceId reader pagination: aggregated ${imageUrls.length} images from ${visited.length} pages (first + ${toFetch.length} sub-pages)',
              );
            }
          }
        } catch (e) {
          _logger.w('$_sourceId reader pagination failed', error: e);
        }
      }

      if (imageUrls.isEmpty &&
          (readerConfig['cdnHost'] as String?)?.isNotEmpty == true) {
        imageUrls = _readerImages.extractPreviewCdnImageUrls(workingHtmlContent);
      }

      imageUrls = _readerImages.normalizeChapterImageUrls(imageUrls);

      // 3b. Re-write preview CDN → reader CDN if configured.
      final cdnHost = readerConfig['cdnHost'] as String?;
      if (cdnHost != null && cdnHost.isNotEmpty) {
        final previewHost =
            (readerConfig['previewHost'] as String?)?.trim().isNotEmpty == true
                ? (readerConfig['previewHost'] as String).trim()
                : 'hencover.xyz'; // legacy default
        final realMangaId = _parser.extractString(
                workingDoc,
                const FieldSelector(
                    selector: '#wp-manga-manga-id', attribute: 'value')) ??
            _parser.extractString(
                workingDoc,
                const FieldSelector(
                    selector: '[data-bookmark]', attribute: 'data-bookmark')) ??
            _parser.extractString(
                workingDoc,
                const FieldSelector(
                    selector: '[data-post]', attribute: 'data-post'));
        final realChapterId = _parser.extractString(
                workingDoc,
                const FieldSelector(
                    selector: '#wp-manga-chapter-id', attribute: 'value')) ??
            _parser.extractString(
                workingDoc,
                const FieldSelector(
                    selector: '[data-chapter]', attribute: 'data-chapter'));

        imageUrls = imageUrls.map((url) {
          String replaced = url.replaceAll('$previewHost/preview', cdnHost);

          if (realMangaId != null &&
              realMangaId.isNotEmpty &&
              realChapterId != null &&
              realChapterId.isNotEmpty) {
            try {
              final uri = Uri.tryParse(replaced);
              if (uri != null && uri.pathSegments.length >= 3) {
                final segments = List<String>.from(uri.pathSegments);
                final len = segments.length;
                segments[len - 3] = realMangaId;
                segments[len - 2] = realChapterId;
                replaced = uri.replace(pathSegments: segments).toString();
              }
            } catch (_) {}
          }
          return replaced;
        }).toList();

        // Extrapolate missing image URLs if lazy-loading only provided a few
        if (imageUrls.isNotEmpty) {
          int maxPage = imageUrls.length;

          final pageOptions = _parser.selectAll(workingDoc,
              'select#single-pager option, select.selectpicker.page-selection option, .wp-manga-nav select.selectpicker option');
          if (pageOptions.isNotEmpty) {
            maxPage = pageOptions.length;
          } else {
            final scriptMatch = RegExp(r'\"pages\"?\s*:\s*(\d+)')
                    .firstMatch(workingHtmlContent) ??
                RegExp('total_pages[\\s"\\\'=]+(\\d+)')
                    .firstMatch(workingHtmlContent);
            if (scriptMatch != null) {
              maxPage = int.tryParse(scriptMatch.group(1) ?? '') ?? maxPage;
            }
          }

          // Fallback: scan entire HTML for reader CDN page images
          // (prefix from config, e.g. `hr_` for HentaiRead, `mr_` for
          // ManhwaRead).
          final imagePrefix = (readerConfig['imagePrefix'] as String?) ??
              'hr_'; // legacy default
          final prefixMatches = RegExp(
            '${RegExp.escape(imagePrefix)}(\\d{4})\\.(jpg|jpeg|png|webp)',
            caseSensitive: false,
          ).allMatches(workingHtmlContent);
          for (final m in prefixMatches) {
            final num = int.tryParse(m.group(1) ?? '0') ?? 0;
            if (num > maxPage) maxPage = num;
          }

          if (maxPage > imageUrls.length) {
            final firstUrl = imageUrls.first;
            final match = RegExp(r'(.+/)([^/]+?)(\d+)\.([a-zA-Z0-9]+)$')
                .firstMatch(firstUrl);
            if (match != null) {
              final basePath = match.group(1);
              final prefix = match.group(2);
              final width = match.group(3)?.length ?? 1;
              final ext = match.group(4);
              for (int i = imageUrls.length + 1; i <= maxPage; i++) {
                final padded = i.toString().padLeft(width, '0');
                imageUrls.add('$basePath$prefix$padded.$ext');
              }
            } else if (realMangaId != null && realChapterId != null) {
              final imagePrefix = (readerConfig['imagePrefix'] as String?) ??
                  'hr_'; // legacy default
              for (int i = imageUrls.length + 1; i <= maxPage; i++) {
                final padded = i.toString().padLeft(4, '0');
                imageUrls.add('https://$cdnHost/$realMangaId/$realChapterId/'
                    '$imagePrefix$padded.jpg');
              }
            }
          }
        }
      }

      // 4. DOM fallback for navigation via reader.nav.{next,prev}.
      final navCfg = readerConfig['nav'] as Map<String, dynamic>?;
      nextId ??= _extractNavChapterId(workingDoc, navCfg?['next']);
      prevId ??= _extractNavChapterId(workingDoc, navCfg?['prev']);

      return ChapterData(
        images: imageUrls,
        nextChapterId: nextId,
        prevChapterId: prevId,
      );
    } on DioException catch (e) {
      // 🚀 Re-throw Cloudflare 403 so WebViewSessionAdapter can handle it
      if (e.response?.statusCode == 403) {
        final cfMitigated = e.response?.headers.value('cf-mitigated');
        if (cfMitigated != null) {
          _logger.w(
              '$_sourceId detected Cloudflare 403 in chapter fetch for $chapterId, re-throwing for WebViewSessionAdapter');
          rethrow;
        }
      }
      _logger.e('$_sourceId scraper chapter fetch failed for $chapterId',
          error: e);
      return null;
    } catch (e) {
      _logger.e('$_sourceId scraper chapter fetch failed for $chapterId',
          error: e);
      return null;
    }
  }

  // ── Private: pattern resolution ────────────────────────────────────────────

  // Resolve a named URL pattern into `(resolvedUrl, listConfig)`.
  ///
  // - Plain String → URL only; `listConfig` is `null`.
  // - Object with `"list"` key → URL + list config.
  // - `"inherits"` borrows parent's `"list"` block; local overrides are merged.
  (String, Map<String, dynamic>?) _resolvePattern(
    Map<String, dynamic> scraper,
    String patternKey, {
    required SearchFilter filter,
  }) {
    final urlPatternsCfg =
        (scraper['urlPatterns'] as Map?)?.cast<String, dynamic>() ?? {};
    final patternValue = urlPatternsCfg[patternKey];

    String urlTemplate;
    Map<String, dynamic>? listConfig;

    Map<String, dynamic>? patternMap;

    if (patternValue is String) {
      urlTemplate = patternValue;
      listConfig = null;
    } else if (patternValue is Map<String, dynamic>) {
      patternMap = patternValue;
      urlTemplate = patternValue['url'] as String? ?? '';

      Map<String, dynamic>? parentList;
      final parentKey = patternValue['inherits'] as String?;
      if (parentKey != null) {
        final parentVal = urlPatternsCfg[parentKey];
        if (parentVal is Map<String, dynamic>) {
          parentList = parentVal['list'] as Map<String, dynamic>?;
        }
      }

      final localList = patternValue['list'] as Map<String, dynamic>?;

      if (parentList != null && localList != null) {
        // Shallow merge then deep-merge fields + pagination sub-blocks.
        listConfig = <String, dynamic>{...parentList, ...localList};
        final pf = parentList['fields'] as Map<String, dynamic>?;
        final lf = localList['fields'] as Map<String, dynamic>?;
        if (pf != null && lf != null) {
          listConfig['fields'] = <String, dynamic>{...pf, ...lf};
        }
        final pp = parentList['pagination'] as Map<String, dynamic>?;
        final lp = localList['pagination'] as Map<String, dynamic>?;
        if (pp != null && lp != null) {
          listConfig['pagination'] = <String, dynamic>{...pp, ...lp};
        }
      } else {
        listConfig = localList ?? parentList;
      }
    } else {
      return ('', null);
    }

    final rawQuery = filter.query == '{query}' ? '' : filter.query;
    final rawTagValue = filter.includeTags.isNotEmpty
        ? filter.includeTags.first.name
        : rawQuery;
    final tagTransform = (patternMap?['tagTransform'] as String? ?? '').trim();
    final tagValue = switch (tagTransform) {
      'urlEncode' => Uri.encodeComponent(rawTagValue),
      'base64' => base64Encode(utf8.encode(rawTagValue)),
      _ => rawTagValue
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'^-|-$'), ''),
    };
    final params = <String, String>{
      'page': filter.page.toString(),
      'query': Uri.encodeQueryComponent(rawQuery),
      'tag': tagValue,
    };

    // Merge custom params from pattern config (e.g., "params": { "n": "{query}" })
    if (patternMap != null) {
      final customParams =
          (patternMap['params'] as Map?)?.cast<String, String>() ?? {};
      for (final entry in customParams.entries) {
        var value = entry.value;
        if (value == '{query}') {
          value = Uri.encodeQueryComponent(rawQuery);
        } else if (value == '{page}') {
          value = filter.page.toString();
        } else if (value == '{tag}' && filter.includeTags.isNotEmpty) {
          value = tagValue;
        }
        params[entry.key] = value;
      }
    }

    // Some sources use non-uniform URL path for specific pages, e.g. page 2.
    if (patternMap != null) {
      final pageOverrides =
          (patternMap['pageOverrides'] as Map?)?.cast<String, dynamic>();
      final overrideTemplate =
          pageOverrides?[filter.page.toString()] as String?;
      if (overrideTemplate != null && overrideTemplate.isNotEmpty) {
        urlTemplate = overrideTemplate;
      }
    }

    return (_urlBuilder.resolve(urlTemplate, params), listConfig);
  }

  // ── Private: list page fetching ────────────────────────────────────────────

  Future<AdapterSearchResult> _fetchListPage(
    String url,
    Map<String, dynamic> rawConfig,
    Map<String, dynamic> listConfig, {
    required int currentPage,
    String? paginationCacheKey,
    String? defaultLanguage,
  }) async {
    try {
      final response = await _getWithRedirectFallback(
        url,
        rawConfig: rawConfig,
      );
      final doc = _parser.parse(response.data ?? '');

      final container = listConfig['container'] as String?;
      final fieldsConfig =
          (listConfig['fields'] as Map?)?.cast<String, dynamic>() ?? {};
      final paginationConfig =
          (listConfig['pagination'] as Map<String, dynamic>?) ?? {};
      final sectionFilterConfig =
          (listConfig['sectionFilter'] as Map<String, dynamic>?) ?? {};
      final sectionFilterEnabled = sectionFilterConfig['enabled'] == true;
      final allowedSectionTitles =
          (sectionFilterConfig['allowedTitleContains'] as List?)
                  ?.map((e) => e.toString().toLowerCase().trim())
                  .where((e) => e.isNotEmpty)
                  .toList() ??
              const <String>[];
      final idFallbackSelectors = (listConfig['idFallbackSelectors'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];

      final items = <Content>[];
      if (container != null) {
        final elements = _parser.selectAll(doc, container);
        _logger.i(
            '$_sourceId list parse: container="$container" matched ${elements.length} elements for $url');

        var index = 0;
        for (final el in elements) {
          if (sectionFilterEnabled && allowedSectionTitles.isNotEmpty) {
            final sectionTitle = el.parent?.parent?.previousElementSibling?.text
                    .trim()
                    .toLowerCase() ??
                '';
            final isAllowed = allowedSectionTitles
                .any((needle) => sectionTitle.contains(needle));
            if (sectionTitle.isNotEmpty && !isAllowed) {
              continue;
            }
          }

          final fields = _extractElementFields(el, fieldsConfig);
          var item =
              GenericContentMapper.toListItem(fields, sourceId: _sourceId);
          if (item.id.isEmpty && idFallbackSelectors.isNotEmpty) {
            String fallbackHref = '';
            for (final selector in idFallbackSelectors) {
              final href =
                  (el.querySelector(selector)?.attributes['href'] ?? '').trim();
              if (href.isNotEmpty) {
                fallbackHref = href;
                break;
              }
            }
            final fallbackId = _extractSlugFromUrl(fallbackHref);
            if (fallbackId.isNotEmpty) {
              item = item.copyWith(id: fallbackId);
            }
          }
          if (defaultLanguage != null &&
              (item.language.isEmpty || item.language == 'unknown')) {
            item = item.copyWith(language: defaultLanguage);
          }
          if (item.id.isNotEmpty) {
            items.add(item);
          } else if (index < 5) {
            _logger.w(
                '$_sourceId list parse drop[$index]: empty id. fields=$fields');
          }
          index++;
        }
        _logger.i(
            '$_sourceId list parse: mapped ${items.length}/${elements.length} items for $url');
      } else {
        _logger.w('$_sourceId list parse: container null for $url');
      }

      final nextSel = paginationConfig['next'] as String?;
      final altSel = paginationConfig['alt'] as String?;
      final linksSel = paginationConfig['links'] as String?;
      final lastSel = paginationConfig['last'] as String?;

      final nextPageUrl = _extractEnabledLinkUrl(doc, nextSel, baseUrl: url) ??
          _extractEnabledLinkUrl(doc, altSel, baseUrl: url);
      // `pagination.mode=paged`: URL pattern is page-addressable but the page
      // renders an AJAX load-more control instead of real links — trust the
      // pattern while this page yielded items; stop at the first empty page.
      final forcedPaged =
          (paginationConfig['mode'] as String?) == 'paged' && items.isNotEmpty;
      final hasNext = forcedPaged ||
          nextPageUrl != null ||
          (nextSel != null && _hasEnabledLink(doc, nextSel)) ||
          (altSel != null && _hasEnabledLink(doc, altSel));

      if (paginationCacheKey != null) {
        final nextPageCacheKey =
            _paginationCacheEntryKey(paginationCacheKey, currentPage + 1);
        if (nextPageUrl != null && nextPageUrl.isNotEmpty) {
          _paginationCursorCache[nextPageCacheKey] = nextPageUrl;
        } else {
          _paginationCursorCache.remove(nextPageCacheKey);
        }
      }

      int? totalPages;
      if (linksSel != null) {
        final pageLinks = _parser.selectAll(doc, linksSel);
        for (final link in pageLinks) {
          final pageText = link.text.trim();
          final pageNum = int.tryParse(pageText);
          if (pageNum != null && (totalPages == null || pageNum > totalPages)) {
            totalPages = pageNum;
          }
        }
      }

      if (totalPages == null && lastSel != null && lastSel.isNotEmpty) {
        final lastHref = _parser.extractString(
          doc,
          FieldSelector(selector: lastSel, attribute: 'href'),
        );
        if (lastHref != null && lastHref.isNotEmpty) {
          final match = RegExp(r'/page/(\d+)/').firstMatch(lastHref);
          totalPages = int.tryParse(match?.group(1) ?? '');
        }
      }

      if (totalPages == null) {
        final pageLinks = _parser.selectAll(doc, 'a[href]');
        for (final link in pageLinks) {
          final href = (link.attributes['href'] ?? '').trim();
          if (href.isEmpty) continue;
          final match = RegExp(r'/page/(\d+)/').firstMatch(href);
          final pageNum = int.tryParse(match?.group(1) ?? '');
          if (pageNum != null && (totalPages == null || pageNum > totalPages)) {
            totalPages = pageNum;
          }
        }
      }

      return AdapterSearchResult(
        items: items,
        hasNextPage: hasNext,
        nextPageUrl: nextPageUrl,
        totalPages: totalPages,
      );
    } catch (e) {
      _logger.e('$_sourceId scraper list fetch failed: $url', error: e);
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }
  }

  // ── Private: field extraction ──────────────────────────────────────────────

  // Extract a fields map from a full [dom.Document] (detail pages).
  // ── chaotic_payload decoding (Next.js obfuscated JSON) ─────────────────────
  //
  // Nicomanga (2026-08 redesign) embeds detail/reader data as
  // `self.__next_f.push([1,"<obfuscated>"])` where each character is
  // `char - 0x4E00` then XOR'd with a rotating key byte:
  //   `(codePointAt(i) - 19968) ^ key.charCodeAt(i % key.length)`
  // The key is fixed per site (nicomanga: "NicoMangaX2"), config-driven
  // via `scraper.selectors.detail.chaoticKey` / `reader.chaoticKey`.


  Map<String, dynamic> _extractDocumentFields(
    dom.Document doc,
    Map<String, dynamic> fieldsConfig,
  ) {
    final result = <String, dynamic>{};
    _logger.d(
        '$_sourceId: extracting ${fieldsConfig.length} fields from detail page');

    for (final entry in fieldsConfig.entries) {
      final defMap = _toDefMap(entry.value);
      if (defMap == null) continue;

      final multi = defMap['multi'] as bool? ?? false;
      final transform = defMap['transform'] as String?;
      final sel = _readerImages.fieldDefToSelector(defMap);
      if (sel == null) continue;

      if (entry.key == 'tags' && defMap['extractTagObjects'] == true) {
        final elements = _parser.selectAll(doc, sel.selector);
        final tagObjects = <Tag>[];
        for (final el in elements) {
          // If the element contains multiple spans (like hentairead),
          // usually the first is the name and the second is the count.
          // Fallback to the element itself if no spans exist.
          final spans = el.querySelectorAll('span');
          final nameEl = spans.isNotEmpty ? spans.first : el;

          String name = nameEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (name.isEmpty) continue;

          String type = 'tag';
          String slug = '';
          final href = el.attributes['href'] ?? '';
          if (href.isNotEmpty) {
            final uri = Uri.tryParse(href);
            if (uri != null && uri.pathSegments.isNotEmpty) {
              final segments =
                  uri.pathSegments.where((s) => s.isNotEmpty).toList();
              if (segments.length >= 2) {
                type = segments[segments.length - 2].toLowerCase();
                slug = segments.last.toLowerCase();
              } else if (segments.isNotEmpty) {
                slug = segments.last.toLowerCase();
              }
            }
          }

          // Map source-specific path segments to standard app tag types if necessary
          if (type == 'circle') type = 'publisher';
          if (type == 'author') type = 'artist'; // fallback normalization

          int count = 0;
          if (spans.length > 1) {
            final countText = spans[1].text.trim().toLowerCase();
            if (countText.isNotEmpty) {
              double multiplier = 1.0;
              String numStr = countText;
              if (countText.endsWith('k')) {
                multiplier = 1000.0;
                numStr = countText.substring(0, countText.length - 1);
              } else if (countText.endsWith('m')) {
                multiplier = 1000000.0;
                numStr = countText.substring(0, countText.length - 1);
              }
              final parsedNum = double.tryParse(numStr);
              if (parsedNum != null) {
                count = (parsedNum * multiplier).toInt();
              }
            }
          } else {
            // Fallback for elements without separate spans for count
            // Try to extract trailing number like "Shiro Marimo 1" -> "Shiro Marimo", count 1
            final match =
                RegExp(r'^(.+?)\s+(\d+[.0-9]*[kKmM]?)$').firstMatch(name);
            if (match != null) {
              name = match.group(1)!.trim();
              final countText = match.group(2)!.trim().toLowerCase();
              double multiplier = 1.0;
              String numStr = countText;
              if (countText.endsWith('k')) {
                multiplier = 1000.0;
                numStr = countText.substring(0, countText.length - 1);
              } else if (countText.endsWith('m')) {
                multiplier = 1000000.0;
                numStr = countText.substring(0, countText.length - 1);
              }
              final parsedNum = double.tryParse(numStr);
              if (parsedNum != null) {
                count = (parsedNum * multiplier).toInt();
              }
            }
          }

          tagObjects.add(
              Tag(id: 0, name: name, type: type, slug: slug, count: count));
        }

        final seenValues = <String>{};
        final uniqueTags = tagObjects
            .where((t) => seenValues.add('${t.type}:${t.name}'))
            .toList();

        _logger.d(
            '$_sourceId: parsed ${uniqueTags.length} full Tag objects for "${entry.key}"');
        result[entry.key] = uniqueTags;
        continue;
      }

      if (multi) {
        var values = _parser.extractList(doc, sel);
        if (transform == 'slug') {
          values = values
              .map(_extractSlugFromUrl)
              .where((v) => v.isNotEmpty)
              .toList();
        } else if (transform == 'base64') {
          values = values
              .map((v) => _readerImages.decodeBase64(v) ?? v)
              .where((v) => v.isNotEmpty)
              .toList();
        }

        final seenValues = <String>{};
        values = values.where((v) => seenValues.add(v)).toList();

        // 🆕 parseTagNamespace: split "namespace:name" strings into typed Tags
        // Used by sources like E-Hentai where tag title attributes carry the
        // full "namespace:tagname" string (e.g. "artist:john", "other:ai generated").
        final parseNamespace = defMap['parseTagNamespace'] as bool? ?? false;
        if (parseNamespace && entry.key == 'tags') {
          final tagObjects = <Tag>[];
          for (final raw in values) {
            final colonIdx = raw.indexOf(':');
            if (colonIdx > 0 && colonIdx < raw.length - 1) {
              final ns = raw.substring(0, colonIdx).trim().toLowerCase();
              final name = raw.substring(colonIdx + 1).trim();
              if (ns.isNotEmpty && name.isNotEmpty) {
                tagObjects.add(Tag(id: 0, name: name, type: ns, count: 0));
                continue;
              }
            }
            tagObjects.add(Tag(id: 0, name: raw, type: 'tag', count: 0));
          }
          _logger.d(
              '$_sourceId: parsed ${tagObjects.length} namespace-typed tags for "${entry.key}"');
          result[entry.key] = tagObjects;
        } else {
          _logger.d(
              '$_sourceId: extracted field "${entry.key}" (multi): ${values.length} values = $values');
          result[entry.key] = values;
        }
      } else {
        var value = _parser.extractString(doc, sel) ?? '';
        if (transform == 'slug' && value.isNotEmpty) {
          value = _extractSlugFromUrl(value);
        } else if (transform == 'base64' && value.isNotEmpty) {
          value = _readerImages.decodeBase64(value) ?? value;
        }
        if (entry.key == 'coverUrl' && value.isNotEmpty) {
          value = _readerImages.sanitizeImageUrl(value);
        }
        _logger
            .d('$_sourceId: extracted field "${entry.key}" (single): "$value"');
        result[entry.key] = value;
      }
    }
    return result;
  }

  // Map a decoded chaotic detail payload to canonical detail fields.
  // Payload shape (nicomanga): `{"manga": {...}, "chapters_list": [...]}`.
  // All config keys are optional; missing keys fall back to existing
  // behavior. Multi-valued fields come through as comma-separated strings
  // for compatibility with the DOM extraction path.
  Map<String, dynamic> _extractChaoticDetailFields(
    Map<String, dynamic> payload,
    Map<String, dynamic> detailCfg,
  ) {
    final manga = (payload['manga'] as Map<String, dynamic>?) ?? const {};
    final cfg = (detailCfg['chaotic'] as Map<String, dynamic>?) ?? const {};
    String strVal(String key) => (manga[key]?.toString() ?? '').trim();
    List<String> listVal(String key) => strVal(key)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    List<Map<String, dynamic>> objectsOf(String listKey) =>
        ((manga[listKey] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    final fields = <String, dynamic>{};
    final title = strVal(cfg['title'] ?? 'n');
    if (title.isNotEmpty) fields['title'] = title;
    final cover = strVal(cfg['coverUrl'] ?? 'c');
    if (cover.isNotEmpty) fields['coverUrl'] = _readerImages.sanitizeImageUrl(cover);
    final author = strVal(cfg['author'] ?? 'a');
    if (author.isNotEmpty) fields['author'] = author;

    final tagObjs = objectsOf(cfg['genresList'] ?? 'genres_list');
    if (tagObjs.isNotEmpty) {
      fields['tagObjects'] = tagObjs.map((t) {
        final n = t['n']?.toString() ?? '';
        final ur = t['ur']?.toString() ?? '';
        var type = 'tag';
        var slug = '';
        final uri = Uri.tryParse(ur);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2) {
            type = segments[segments.length - 2].toLowerCase();
            slug = segments.last.toLowerCase();
          } else if (segments.isNotEmpty) {
            slug = segments.last.toLowerCase();
          }
        }
        return <String, dynamic>{
          'name': n,
          'type': type,
          'slug': slug,
          'count': 0,
        };
      }).toList();
    } else {
      final genreStr = strVal(cfg['genres'] ?? 'genres');
      if (genreStr.isNotEmpty) {
        fields['tags'] = listVal(cfg['genres'] ?? 'genres');
      }
    }

    final description = strVal(cfg['description'] ?? 'description');
    if (description.isNotEmpty) fields['description'] = description;
    final status = strVal(cfg['status'] ?? 'status_text');
    if (status.isNotEmpty) fields['status'] = status;

    return fields;
  }

  // Build chapter list from a decoded chaotic payload's `chapters_list`.
  // Each entry carries a display name (`n`) and absolute URL (`ur`) —
  // the URL is used verbatim as the chapter id (it already includes the
  // full `/manga{id}/{slug}/chapter-...` path).
  List<Chapter>? _chaoticChapters(Map<String, dynamic> payload) {
    final raw = (payload['chapters_list'] as List?) ?? const [];
    if (raw.isEmpty) return null;
    final chapters = <Chapter>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final url = entry['ur']?.toString() ?? '';
      final title = entry['n']?.toString() ?? '';
      if (url.isEmpty || title.isEmpty) continue;
      chapters.add(Chapter(id: url, title: title, url: url));
    }
    return chapters.isEmpty ? null : chapters;
  }

  // Extract a fields map from a single [dom.Element] (list items / chapters).
  Map<String, dynamic> _extractElementFields(
    dom.Element el,
    Map<String, dynamic> fieldsConfig,
  ) {
    final result = <String, dynamic>{};
    for (final entry in fieldsConfig.entries) {
      final defMap = _toDefMap(entry.value);
      if (defMap == null) continue;

      final multi = defMap['multi'] as bool? ?? false;
      final transform = defMap['transform'] as String?;
      final sel = _readerImages.fieldDefToSelector(defMap);
      if (sel == null) continue;

      if (multi) {
        var values = el
            .querySelectorAll(sel.selector)
            .map((c) => sel.attribute != null
                ? (c.attributes[sel.attribute] ?? '')
                : c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        // Apply regex filter if present
        if (sel.regex != null) {
          values = values
              .map((v) => _applyRegex(v, sel.regex!))
              .where((v) => v != null && v.isNotEmpty)
              .cast<String>()
              .toList();
        }

        if (transform == 'slug') {
          values = values
              .map(_extractSlugFromUrl)
              .where((v) => v.isNotEmpty)
              .toList();
        }
        result[entry.key] = values;
      } else if (sel.selector == 'self') {
        var value = sel.attribute != null
            ? (el.attributes[sel.attribute] ?? '')
            : el.text.trim();
        if (value.isEmpty) continue;
        if (sel.regex != null) {
          final matched = _applyRegex(value, sel.regex!);
          if (matched != null && matched.isNotEmpty) value = matched;
        }
        if (transform == 'slug' && value.isNotEmpty) {
          value = _extractSlugFromUrl(value);
        }
        result[entry.key] = value;
      } else {
        var value = _parser.extractFromElement(el, sel) ?? '';
        if (transform == 'slug' && value.isNotEmpty) {
          value = _extractSlugFromUrl(value);
        }
        if (entry.key == 'coverUrl' && value.isNotEmpty) {
          value = _readerImages.sanitizeImageUrl(value);
        }
        result[entry.key] = value;
      }
    }
    return result;
  }

  // ── Private helpers ────────────────────────────────────────────────────────


  // Route to the urlPattern declared on whichever form field carries a value
  // (e.g. `genre` → `genreSearch`). Sites ignore query-string filters like
  // `?genre=x`; they expose tag browsing as dedicated paths instead.
  String? _resolveFieldDrivenPatternKey({
    required Map<String, List<String>> rawMap,
    required Map<String, dynamic> formParamsCfg,
  }) {
    for (final entry in rawMap.entries) {
      if (entry.value.isEmpty || entry.value.first.trim().isEmpty) continue;
      final fieldCfg = formParamsCfg[entry.key];
      if (fieldCfg is! Map<String, dynamic>) continue;
      if (fieldCfg['type']?.toString() != 'tag') continue;
      final pattern = fieldCfg['urlPattern']?.toString();
      if (pattern != null && pattern.isNotEmpty) return pattern;
    }
    return null;
  }

  // Value for the `{tag}` path placeholder: prefer the tag-typed field whose
  // urlPattern routed to [patternKey] (e.g. `genre=action`), else null.
  String? _pathTagValueForPatternKey({
    required Map<String, List<String>> rawMap,
    required Map<String, dynamic> formParamsCfg,
    required String patternKey,
  }) {
    for (final entry in rawMap.entries) {
      if (entry.value.isEmpty || entry.value.first.trim().isEmpty) continue;
      final fieldCfg = formParamsCfg[entry.key];
      if (fieldCfg is! Map<String, dynamic>) continue;
      if (fieldCfg['type']?.toString() != 'tag') continue;
      if (fieldCfg['urlPattern']?.toString() == patternKey) {
        return entry.value.first;
      }
    }
    return null;
  }

  // Normalise a field definition value to `Map<String, dynamic>`.
  Map<String, dynamic>? _toDefMap(dynamic def) {
    if (def is Map<String, dynamic>) return def;
    if (def is Map) return def.cast<String, dynamic>();
    if (def is String) return <String, dynamic>{'selector': def};
    return null;
  }


  Content _emptyContent(String id) => Content(
        id: id,
        sourceId: _sourceId,
        title: '',
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

  // Normalize chapterId against template prefix to prevent double-prefix.
  ///
  // When a broad regex extracts an ID that already includes a URL path prefix
  // (e.g. `/manhwa/queen-bee/side-story-3`), and the template also has that
  // prefix (e.g. `/manhwa/{id}`), building the full URL produces
  // `/manhwa//manhwa/queen-bee/...`. Strip the template's static prefix from
  // the ID so substitution is clean.
  ///
  //  simple path-based stripping — works for all current configs.
  // Upgrade to template-aware AST parsing if exotic configs collide.
  String _normalizeChapterIdForTemplate(String chapterId, String template) {
    if (chapterId.isEmpty) return chapterId;

    final placeholder =
        template.contains('{contentId}') ? '{contentId}' : '{id}';
    if (!template.contains(placeholder)) return chapterId;

    final prefix = template.split(placeholder).first;
    if (prefix.isEmpty || prefix == '/') {
      // Template starts with placeholder — nothing to strip.
      // Still strip leading `/` if id starts with `/` and baseUrl is about to
      // prepend, so `https://host//path` doesn't appear.
      while (chapterId.startsWith('/')) {
        chapterId = chapterId.substring(1);
      }
      return chapterId;
    }

    // Strip prefix from the beginning of the id.
    final normPrefix = prefix.endsWith('/') ? prefix : '$prefix/';
    var stripped = chapterId;
    if (stripped.startsWith(normPrefix)) {
      stripped = stripped.substring(normPrefix.length);
    }
    // Strip any path separators at the start.
    while (stripped.startsWith('/')) {
      stripped = stripped.substring(1);
    }
    // Preserve a trailing slash: madara sites (mangaread.org) 301
    // `/manga/x/chapter-N` → `/manga/x/chapter-N/`, and their redirect chain
    // loops when followed, so dropping the slash breaks reader/download.
    // The `//path/` double-slash this once guarded against came from ids that
    // BOTH started and ended with `/` — leading slashes are already removed
    // above, so that case can't occur here.
    return stripped;
  }

  // Extract the last meaningful path slug from a URL.
  ///
  // We match the common `/manga/<slug>` and `/<slug>-chapter-<number>`
  // shapes before attempting [Uri.parse]. Regex matching tolerates raw
  // Unicode path characters such as `〜` and `ー`, which can appear in source
  // URLs and may throw inside `Uri.parse` when the path is not already
  // percent-encoded.
  ///
  // Examples:
  // - `https://komiku.org/manga/one-piece/` -> `one-piece`
  // - `https://komiku.org/manga/title-%E3%80%9Cspecial%E3%80%9C/` ->
  //   `title-〜special〜`
  // - `https://komiku.org/nishuume-cheat-〜-chapter-1/` ->
  //   `nishuume-cheat-〜-chapter-1`
  String _extractSlugFromUrl(String url) {
    if (url.isEmpty) return '';

    final patterns = <RegExp>[
      RegExp(r'/manga/([^/?#]+)'),
      RegExp(r'/manhwa/([^/?#]+(?:/[^/?#]+)?)'),
      RegExp(r'/([^/?#]+?-chapter-[\d.-]+)(?:/|[?#]|$)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      final slug = match?.group(1);
      if (slug != null && slug.isNotEmpty) {
        return _decodeSlugComponent(slug);
      }
    }

    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final mangaIndex = segments.indexOf('manga');
        final slug = mangaIndex != -1 && mangaIndex + 1 < segments.length
            ? segments[mangaIndex + 1]
            : segments.last;
        return _decodeSlugComponent(slug);
      }
    } catch (_) {}
    return '';
  }

  // Decode percent-encoded slugs without turning malformed inputs into errors.
  String _decodeSlugComponent(String slug) {
    if (!slug.contains('%')) return slug;
    try {
      return Uri.decodeComponent(slug);
    } catch (_) {
      return _searchRouting.decodePercentEncodedSegments(slug) ?? slug;
    }
  }


  // Apply a regex pattern to extract a substring.
  // Returns the first capture group if it exists, else the entire match (group 0).
  String? _applyRegex(String input, String pattern) {
    try {
      final match = RegExp(pattern).firstMatch(input);
      if (match == null) return null;
      return match.groupCount > 0 ? match.group(1) : match.group(0);
    } catch (e) {
      _logger.w('$_sourceId: regex pattern error: $pattern', error: e);
      return null;
    }
  }

  String? _extractNavChapterId(dom.Document doc, dynamic navDef) {
    if (navDef is String) {
      final href = _parser.extractString(
        doc,
        FieldSelector(selector: navDef, attribute: 'href'),
      );
      if (href == null || href.isEmpty || href.startsWith('#')) {
        return null;
      }
      return _extractSlugFromUrl(href);
    }

    final defMap = _toDefMap(navDef);
    if (defMap == null) return null;

    final transform = defMap['transform'] as String?;
    final selector = _readerImages.fieldDefToSelector(defMap);
    if (selector == null) return null;

    var value = _parser.extractString(doc, selector)?.trim() ?? '';
    if (value.isEmpty || value == '#') return null;
    if (transform == 'slug') {
      value = _extractSlugFromUrl(value);
    }

    return value.isEmpty ? null : value;
  }

  Future<List<String>> _fetchAjaxHtmlImages({
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> readerConfig,
    required dom.Document readerDocument,
    required String readerPageUrl,
  }) async {
    final requestConfig =
        (readerConfig['request'] as Map?)?.cast<String, dynamic>();
    if (requestConfig == null) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: missing reader.request config',
      );
      return const [];
    }

    final method =
        ((requestConfig['method'] as String?) ?? 'POST').trim().toUpperCase();
    final requestUrlTemplate = (requestConfig['url'] as String?)?.trim() ?? '';
    if (requestUrlTemplate.isEmpty) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: request.url is empty',
      );
      return const [];
    }

    final bodyFields = _readerImages.extractAjaxRequestFields(
      readerDocument: readerDocument,
      requestConfig: requestConfig,
      fieldGroup: 'body',
    );
    if (bodyFields == null) return const [];

    final queryFields = _readerImages.extractAjaxRequestFields(
      readerDocument: readerDocument,
      requestConfig: requestConfig,
      fieldGroup: 'query',
    );
    if (queryFields == null) return const [];

    final queryParameters = <String, dynamic>{...queryFields};
    if (method == 'GET' && bodyFields.isNotEmpty) {
      for (final entry in bodyFields.entries) {
        queryParameters.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final headers = _resolveRequestHeaders(
      rawConfig,
      fallbackReferer: readerPageUrl,
    );
    headers['Referer'] = readerPageUrl;

    final origin = Uri.tryParse(readerPageUrl)?.origin;
    if (origin != null && origin.isNotEmpty) {
      headers.putIfAbsent('Origin', () => origin);
    }

    final ajaxHeaders =
        (requestConfig['headers'] as Map?)?.cast<String, dynamic>() ?? {};
    headers.addAll(ajaxHeaders);

    final requestUrl = _urlBuilder.resolve(requestUrlTemplate, const {});
    final configuredContentType =
        (requestConfig['contentType'] as String?)?.trim();
    final contentType =
        configuredContentType == null || configuredContentType.isEmpty
            ? (method == 'POST' ? Headers.formUrlEncodedContentType : null)
            : configuredContentType;

    final response = await _executeRequest<Response<String>>(
      () => _dio.request<String>(
        requestUrl,
        data: method == 'GET' ? null : bodyFields,
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
        options: Options(
          method: method,
          headers: headers,
          contentType: contentType,
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      ),
    );

    if (!_isSuccessStatus(response.statusCode)) {
      if (response.statusCode == 403 &&
          (response.headers.value('cf-mitigated')?.isNotEmpty ?? false)) {
        _logger.w(
          '$_sourceId ajaxHtmlImages: blocked by site protection (403 cf-mitigated) for $requestUrl',
        );
      }
      _logger.w(
        '$_sourceId ajaxHtmlImages: request failed with status ${response.statusCode} for $requestUrl',
      );
      return const [];
    }

    final responseHtml = response.data ?? '';
    if (responseHtml.trim().isEmpty) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: empty HTML response for $requestUrl',
      );
      return const [];
    }

    final responseConfig =
        (readerConfig['response'] as Map?)?.cast<String, dynamic>() ?? {};
    final imagesDef = responseConfig['images'] ?? readerConfig['images'];
    final defMap = _toDefMap(imagesDef);
    if (defMap == null) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: response.images selector is missing',
      );
      return const [];
    }

    final selector = _readerImages.fieldDefToSelector(defMap);
    if (selector == null) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: response.images selector is invalid',
      );
      return const [];
    }

    final responseDoc = _parser.parse(responseHtml);
    final rawUrls = _parser.extractList(responseDoc, selector);
    final normalizedUrls = _readerImages.normalizeChapterImageUrls(rawUrls);
    if (normalizedUrls.isEmpty) {
      _logger.w(
        '$_sourceId ajaxHtmlImages: no images extracted using selector "${selector.selector}"',
      );
    }

    return normalizedUrls;
  }










  bool _hasEnabledLink(dom.Document doc, String selector) {
    final link = doc.querySelector(selector);
    if (link == null) return false;

    final href = (link.attributes['href'] ?? '').trim();
    final hxGet = (link.attributes['hx-get'] ?? '').trim();
    if ((href.isEmpty || href == '#') && hxGet.isEmpty) return false;

    final parentClass = link.parent?.attributes['class'] ?? '';
    if (parentClass.contains('disabled')) return false;

    return true;
  }

  String? _extractEnabledLinkUrl(
    dom.Document doc,
    String? selector, {
    required String baseUrl,
  }) {
    if (selector == null || selector.trim().isEmpty) return null;

    final link = doc.querySelector(selector);
    if (link == null) return null;

    final href = (link.attributes['href'] ?? '').trim();
    final hxGet = (link.attributes['hx-get'] ?? '').trim();
    if ((href.isEmpty || href == '#') && hxGet.isEmpty) return null;

    final parentClass = link.parent?.attributes['class'] ?? '';
    if (parentClass.contains('disabled')) return null;

    final candidate = href.isNotEmpty && href != '#' ? href : hxGet;
    return Uri.parse(baseUrl).resolve(candidate).toString();
  }

  String _buildPaginationCacheKey({
    required String scope,
    required SearchFilter filter,
  }) {
    final includeTags = filter.includeTags
        .map((tag) => tag.name.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();

    return [
      scope,
      'query=${filter.query.trim().toLowerCase()}',
      'category=${(filter.category ?? '').trim().toLowerCase()}',
      'tags=${includeTags.join(',')}',
      'sort=${filter.sort.name}',
    ].join('|');
  }

  String _buildRawPaginationCacheKey({
    required String scope,
    required Map<String, List<String>> rawMap,
  }) {
    final entries = rawMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final flattened = entries.map((entry) {
      final values = [...entry.value]..sort();
      return '${entry.key}=${values.join(',')}';
    }).join('&');

    return '$scope|raw=$flattened';
  }

  String _paginationScopeForPatternKey(String patternKey) {
    return patternKey.endsWith('Page')
        ? patternKey.substring(0, patternKey.length - 4)
        : patternKey;
  }

  String _paginationCacheEntryKey(String cacheKey, int page) {
    return '$cacheKey|page=$page';
  }

  // Tries to prime cursor pagination for [page] > 1 and returns the cached
  // URL. Returns null if cursor pagination doesn't apply or the cache wasn't
  // populated.
  //  maxPrimePages — add threshold if sources need deep pagination
  static const _maxPrimePages = 10;

  Future<String?> _tryPrimeCursorPagination({
    required String? requestUrl,
    required int page,
    required String patternKey,
    required Map<String, dynamic> listConfig,
    required Map<String, dynamic> rawConfig,
    required String paginationCacheKey,
    required String initialUrl,
  }) async {
    if (requestUrl != null || page <= 1 || patternKey.endsWith('Page')) {
      return null;
    }
    // Check if config has cursor pagination selectors
    final pagination =
        (listConfig['pagination'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hasCursor =
        (pagination['next'] as String?)?.trim().isNotEmpty == true ||
            (pagination['alt'] as String?)?.trim().isNotEmpty == true;
    if (!hasCursor) return null;
    //  serial N-1 requests — parallelise if source latency is high
    var currentUrl = initialUrl;
    final limit = math.min(page, _maxPrimePages);
    for (var currentPage = 1; currentPage < limit; currentPage++) {
      final cached = _resolveListRequestUrlFromCursorCache(
        page: currentPage,
        cacheKey: paginationCacheKey,
      );
      if (cached != null && cached.isNotEmpty) {
        currentUrl = cached;
      }

      final result = await _fetchListPage(
        currentUrl,
        rawConfig,
        listConfig,
        currentPage: currentPage,
        paginationCacheKey: paginationCacheKey,
        defaultLanguage: rawConfig['defaultLanguage'] as String?,
      );

      final nextUrl = result.nextPageUrl;
      if (nextUrl == null || nextUrl.isEmpty) return null;
      currentUrl = nextUrl;
    }

    return _resolveListRequestUrlFromCursorCache(
      page: page,
      cacheKey: paginationCacheKey,
    );
  }

  String? _resolveListRequestUrlFromCursorCache({
    required int page,
    required String cacheKey,
  }) {
    if (page <= 1) return null;
    return _paginationCursorCache[_paginationCacheEntryKey(cacheKey, page)];
  }




  DateTime? _parseRelativeOrAbsoluteDate(String raw) {
    if (raw.isEmpty) return null;

    final absolute = DateTime.tryParse(raw);
    if (absolute != null) return absolute;

    final now = DateTime.now();
    final normalized = raw
        .toLowerCase()
        .replaceFirst(RegExp(r'^(posted|date)\s*:\s*'), '')
        .trim();

    if (normalized == 'just now' || normalized == 'today') return now;
    if (normalized == 'yesterday') {
      return now.subtract(const Duration(days: 1));
    }

    final match = RegExp(
      r'^(\d+|a|an)\s+(second|minute|hour|day|week|month|year)s?\s+ago$',
    ).firstMatch(normalized);
    if (match == null) return null;

    final quantityRaw = match.group(1) ?? '0';
    final unit = match.group(2) ?? '';
    final quantity = (quantityRaw == 'a' || quantityRaw == 'an')
        ? 1
        : (int.tryParse(quantityRaw) ?? 0);
    if (quantity <= 0) return null;

    switch (unit) {
      case 'second':
        return now.subtract(Duration(seconds: quantity));
      case 'minute':
        return now.subtract(Duration(minutes: quantity));
      case 'hour':
        return now.subtract(Duration(hours: quantity));
      case 'day':
        return now.subtract(Duration(days: quantity));
      case 'week':
        return now.subtract(Duration(days: quantity * 7));
      case 'month':
        return now.subtract(Duration(days: quantity * 30));
      case 'year':
        return now.subtract(Duration(days: quantity * 365));
      default:
        return null;
    }
  }

  List<Comment> _parseApiComments(dynamic data) {
    List<dynamic> rows;

    if (data is List) {
      rows = data;
    } else if (data is String) {
      final decoded = json.decode(data);
      if (decoded is List) {
        rows = decoded;
      } else {
        return const [];
      }
    } else {
      return const [];
    }

    final comments = <Comment>[];
    final seenIds = <String>{};

    for (final row in rows) {
      if (row is! Map) continue;

      final id = (row['comment_id'] ?? '').toString().trim();
      final username = (row['user_name'] ?? '').toString().trim();
      final body = (row['comment'] ?? '').toString().trim();
      if (id.isEmpty || username.isEmpty || body.isEmpty) continue;
      if (seenIds.contains(id)) continue;

      final avatarRaw = (row['user_avatar'] ?? '').toString().trim();
      String? avatarUrl;
      if (avatarRaw.isNotEmpty) {
        if (avatarRaw.startsWith('http://') ||
            avatarRaw.startsWith('https://')) {
          avatarUrl = avatarRaw;
        } else if (avatarRaw.startsWith('/')) {
          avatarUrl = _urlBuilder.resolve(avatarRaw, const {});
        } else {
          avatarUrl = _urlBuilder.resolve('/uploads/$avatarRaw', const {});
        }
      }

      final postedRaw = (row['posted'] ?? '').toString().trim();

      comments.add(
        Comment(
          id: id,
          username: username,
          body: body,
          avatarUrl: avatarUrl,
          postDate: _parseRelativeOrAbsoluteDate(postedRaw),
        ),
      );
      seenIds.add(id);
    }

    return comments;
  }

  // Fallback: when chapterDataScript fails (e.g. Next.js SPA reader),
  // fetch the detail page and extract preview image URLs from
  // `hencover.xyz/preview/{mangaId}/{chapterId}/hr_NNNN.jpg`, then
  // rewrite them to the reader CDN (`henread.xyz`).
  Future<List<String>> _extractDetailPreviewImages({
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> readerConfig,
    required String chapterHtmlContent,
  }) async {
    final cdnHost = readerConfig['cdnHost'] as String?;
    if (cdnHost == null || cdnHost.isEmpty) return const [];

    final previewHost =
        (readerConfig['previewHost'] as String?)?.trim().isNotEmpty == true
            ? (readerConfig['previewHost'] as String).trim()
            : 'hencover.xyz';
    final imagePrefix = readerConfig['imagePrefix'] as String? ?? 'hr_';

    // Extract preview image URLs from the chapter page HTML.
    // Pattern: https://hencover.xyz/preview/{mangaId}/{chapterId}/hr_NNNN.jpg
    // CRITICAL: only match 4-digit page numbers (0001-9999) to avoid
    // matching cover images like hr_289618.jpg (6-digit manga ID).
    final previewRegex = RegExp(
      'https?://${RegExp.escape(previewHost)}/preview/(\\d+)/(\\d+)/'
      '${RegExp.escape(imagePrefix)}(\\d{4})\\.(jpg|jpeg|png|webp)',
      caseSensitive: false,
    );

    final matches = previewRegex.allMatches(chapterHtmlContent).toList();
    if (matches.isEmpty) {
      _logger.d(
          '$_sourceId detailPreviewImages: no preview URLs found in chapter HTML');
      return const [];
    }

    // Extract mangaId and chapterId from the first match.
    final mangaId = matches.first.group(1)!;
    final chapterId = matches.first.group(2)!;
    final maxPage = matches
        .map((m) => int.tryParse(m.group(3)!) ?? 0)
        .reduce((a, b) => a > b ? a : b);

    _logger
        .d('$_sourceId detailPreviewImages: found ${matches.length} previews, '
            'mangaId=$mangaId, chapterId=$chapterId, maxPage=$maxPage');

    // Build reader CDN URLs.
    final ext = matches.first.group(4)!;
    const width = 4; // always 4-digit padded

    final urls = <String>[];
    for (int i = 1; i <= maxPage; i++) {
      final padded = i.toString().padLeft(width, '0');
      urls.add(
        'https://$cdnHost/$mangaId/$chapterId/$imagePrefix$padded.$ext',
      );
    }

    return urls;
  }
}
