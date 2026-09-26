// Generic REST adapter — handles JSON API sources.
///
// Uses [GenericJsonParser] with JSONPath selectors from the config to map
// API responses to [Content] entities.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import '../mappers/generic_content_mapper.dart';
import '../nhentai/nhentai_shapes.dart';import '../models/source_config_runtime.dart';
import '../parsers/generic_html_parser.dart';
import '../parsers/generic_json_parser.dart';
import '../url_builder/generic_url_builder.dart';
import 'generic_adapter.dart';

// Function type for generating anti-detection headers dynamically.
// Returns a map of HTTP headers. Optional [referer] parameter can be passed.
typedef HeadersGenerator = Map<String, String> Function({String? referer});

// Function type for applying rate limiting delays before HTTP requests.
// Used to prevent IP banning by spreading out requests over time.
typedef DelayApplier = Future<void> Function();

class GenericRestAdapter implements GenericAdapter {
  final Dio _dio;
  final GenericUrlBuilder _urlBuilder;
  final GenericJsonParser _parser;
  final Logger _logger;
  final String _sourceId;
  final HeadersGenerator? _headersGenerator;
  final DelayApplier? _delayApplier;
  final RateLimiter? _rateLimiter;

  GenericRestAdapter({
    required Dio dio,
    required GenericUrlBuilder urlBuilder,
    required GenericJsonParser parser,
    required Logger logger,
    required String sourceId,
    HeadersGenerator? headersGenerator,
    DelayApplier? delayApplier,
    RateLimiter? rateLimiter,
  })  : _dio = dio,
        _urlBuilder = urlBuilder,
        _parser = parser,
        _logger = logger,
        _sourceId = sourceId,
        _headersGenerator = headersGenerator,
        _delayApplier = delayApplier,
        _rateLimiter = rateLimiter;

  @override
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    final detailCfg = api?['detail'] as Map<String, dynamic>? ?? {};
    final chaptersCfg = detailCfg['chapters'] as Map<String, dynamic>? ??
        api?['chapters'] as Map<String, dynamic>?;

    if (chaptersCfg == null) {
      _logger.d(
          '$_sourceId: fetchChapters called but no api.chapters config found');
      return const <Chapter>[];
    }

    final endpoint = _getEndpointPath(chaptersCfg['endpoint']);
    if (endpoint.isEmpty) return const <Chapter>[];

    final itemsSelector = _str(chaptersCfg, 'items');
    if (itemsSelector == null) return const <Chapter>[];

    final cFields = (chaptersCfg['fields'] as Map<String, dynamic>?) ?? {};
    final defaultLang = language ?? _str(rawConfig, 'defaultLanguage') ?? '';

    var chapterUrl = _urlBuilder.resolve(
      endpoint,
      {'id': contentId, 'language': defaultLang},
    );
    if (offset != null) {
      chapterUrl = _upsertQueryParam(chapterUrl, 'offset', offset.toString());
    }
    if (page != null) {
      chapterUrl = _upsertQueryParam(chapterUrl, 'page', page.toString());
    }
    if (limit != null) {
      chapterUrl = _upsertQueryParam(chapterUrl, 'limit', limit.toString());
    }

    // Inject language filter for APIs that use translatedLanguage[] instead
    // of a {language} placeholder (e.g. MangaDex).
    // Only inject when language is explicitly passed (not default fallback).
    if (language != null && !endpoint.contains('{language}')) {
      chapterUrl = _replaceMultiValueParam(
        chapterUrl,
        paramName: 'translatedLanguage[]',
        values: [language],
      );
    }

    final chapterQueryRules = (api?['queryRules']
        as Map<String, dynamic>?)?['chapters'] as Map<String, dynamic>?;
    chapterUrl = _applyQueryRules(chapterUrl, chapterQueryRules);

    final volumesCfg = detailCfg['volumes'] as Map<String, dynamic>? ??
        api?['volumes'] as Map<String, dynamic>?;

    try {
      var chapters = <Chapter>[];
      if (scanGroup != 'Volume') {
        chapters = await _fetchChapters(
          chapterUrl,
          itemsSelector: itemsSelector,
          cFields: cFields,
          rawConfig: rawConfig,
          autoPaginate: chaptersCfg['autoPaginate'] != false,
        );
        chapters = _composeChapterIdsWithContentId(
          chapters,
          chaptersCfg: chaptersCfg,
          contentId: contentId,
        );
      }

      if (scanGroup != 'Chapter' && volumesCfg != null) {
        final volEndpoint = _getEndpointPath(volumesCfg['endpoint']);
        final volItemsSelector = _str(volumesCfg, 'items');
        if (volEndpoint.isNotEmpty && volItemsSelector != null) {
          final volUrl = _urlBuilder.resolve(
            volEndpoint,
            {'id': contentId, 'language': defaultLang},
          );
          final vFields = (volumesCfg['fields'] as Map<String, dynamic>?) ?? {};
          var volumes = await _fetchChapters(
            volUrl,
            itemsSelector: volItemsSelector,
            cFields: vFields,
            rawConfig: rawConfig,
            autoPaginate: volumesCfg['autoPaginate'] != false,
          );
          volumes = _composeChapterIdsWithContentId(
            volumes,
            chaptersCfg: volumesCfg,
            contentId: contentId,
          );
          chapters = [...chapters, ...volumes];
        }
      }

      return chapters;
    } catch (e) {
      _logger.w('$_sourceId fetchChapters failed: $e');
      return const <Chapter>[];
    }
  }

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    // ── Schema detection ────────────────────────────────────────────────────
    // New schema: config has `api.list` block with `items` + `fields`.
    // Old schema (nhentai): config uses flat `selectors` map.
    final apiList = api?['list'] as Map<String, dynamic>?;
    if (apiList != null) {
      return _searchNewSchema(filter, rawConfig, api!, apiList);
    }

    final rawEndpoints = (api?['endpoints'] as Map<String, dynamic>?) ?? {};
    // Normalize: extract path from both old (string) and new (object) schemas
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };

    // Build effective query from all active filters using `queryTokenTemplates`
    // declared in the source config's `searchConfig`.
    //
    // Template variables:
    //   `{type}` — the filter type (tag, artist, language, category, etc.)
    //   `{name}` — the filter value
    //
    // Example nhentai config:
    //   include: `{type}:"{name}"` → `tag:"big breasts"`, `language:"english"`
    //   exclude: `-{type}:"{name}"` → `-tag:"netorare"`
    //
    // Covers: includeTags, excludeTags (all typed) + language + category fields.
    final searchConfig =
        (rawConfig['searchConfig'] as Map<String, dynamic>?) ?? {};
    final tokenTemplates =
        searchConfig['queryTokenTemplates'] as Map<String, dynamic>?;
    final includeTemplate = tokenTemplates?['include'] as String?;
    final excludeTemplate = tokenTemplates?['exclude'] as String?;

    String effectiveQuery = filter.query.trim();
    final embeddedTokens = <String>[];

    if (includeTemplate != null) {
      // Build tokens for included filter items (tags, artists, characters, etc.)
      for (final item in filter.includeTags) {
        embeddedTokens.add(
          includeTemplate
              .replaceAll('{type}', item.type.toLowerCase())
              .replaceAll('{name}', item.name),
        );
      }

      // Build tokens for excluded filter items
      final excl = excludeTemplate ?? '-$includeTemplate';
      for (final item in filter.excludeTags) {
        embeddedTokens.add(
          excl
              .replaceAll('{type}', item.type.toLowerCase())
              .replaceAll('{name}', item.name),
        );
      }

      // Embed language and category as typed tokens (e.g. language:"english")
      if (filter.language != null && filter.language!.isNotEmpty) {
        embeddedTokens.add(
          includeTemplate
              .replaceAll('{type}', 'language')
              .replaceAll('{name}', filter.language!),
        );
      }
      if (filter.category != null && filter.category!.isNotEmpty) {
        embeddedTokens.add(
          includeTemplate
              .replaceAll('{type}', 'category')
              .replaceAll('{name}', filter.category!),
        );
      }
    }

    if (embeddedTokens.isNotEmpty) {
      effectiveQuery = [effectiveQuery, ...embeddedTokens]
          .where((s) => s.isNotEmpty)
          .join(' ');
    }

    // Use 'allGalleries' endpoint ONLY when there are truly no active filters.
    // If language/category/tags are set (even with empty text query), use 'search'.
    final isEmptyQuery = effectiveQuery.isEmpty && !filter.hasFilters;

    final searchTemplate = isEmptyQuery
        ? (endpoints['allGalleries'] ?? endpoints['search'] ?? '')
        : (endpoints['search'] ?? '');

    _logger.d('$_sourceId REST search config: api=$api');
    _logger.d(
        '$_sourceId REST search: effectiveQuery="$effectiveQuery", useAllGalleries=$isEmptyQuery, template="$searchTemplate"');

    if (searchTemplate.isEmpty) {
      _logger.w('$_sourceId: no search endpoint configured');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    // Build URL using the effective query (with embedded filter tokens).
    // For raw tag_id searches (e.g. from detail tag tap), prefer dedicated
    // tagSearch endpoint when configured.
    final adjustedFilter = effectiveQuery != filter.query.trim()
        ? filter.copyWith(query: effectiveQuery)
        : filter;
    final sortValue = _resolveSearchSortValue(adjustedFilter, rawConfig);
    final rawParams = _extractRawSearchParams(adjustedFilter.query);
    String url;

    if (rawParams != null && rawParams.isNotEmpty) {
      final rawMap = _parseRawQueryParams(rawParams);
      // NHentai v2 search endpoint rejects requests without a non-empty query
      // param. When raw params have no text query (sort-only), route to
      // allGalleries endpoint which doesn't require a query string.
      final String rawBrowseTmpl;
      if (_sourceId == 'nhentai') {
        rawBrowseTmpl = (!rawMap.keys.any(
                    (k) => ['query', 'q', 'search', 'keyword'].contains(k)) &&
                endpoints['allGalleries'] is String
            ? endpoints['allGalleries'] as String
            : searchTemplate);
      } else {
        rawBrowseTmpl = searchTemplate;
      }
      final tagSearchTemplate = endpoints['tagSearch'] ?? '';

      // Check if we have a tagSearch endpoint and any raw params
      if (tagSearchTemplate.isNotEmpty && rawMap.isNotEmpty) {
        final tagValue = _extractTagValueFromRawParams(rawMap);

        if (tagValue != null && tagValue.isNotEmpty) {
          final page = adjustedFilter.page > 0 ? adjustedFilter.page : 1;
          final baseTaggedUrl = _urlBuilder.resolve(tagSearchTemplate, {
            'tagId': tagValue,
            'page': page.toString(),
            'sort': sortValue,
            'query': '',
          });

          final mergedParams = _parseUrlQueryParams(baseTaggedUrl);
          for (final entry in rawMap.entries) {
            mergedParams[entry.key] = entry.value;
          }

          if (sortValue.isNotEmpty &&
              !(mergedParams['sort']?.any((v) => v.trim().isNotEmpty) ??
                  false)) {
            mergedParams['sort'] = [sortValue];
          }

          url = _rebuildUrlWithQueryParams(baseTaggedUrl, mergedParams);
        } else {
          url = _buildRawSearchUrl(rawBrowseTmpl, rawParams, adjustedFilter);
        }
      } else {
        url = _buildRawSearchUrl(rawBrowseTmpl, rawParams, adjustedFilter);
      }
    } else {
      url = _urlBuilder.buildSearchUrl(
        searchTemplate,
        adjustedFilter,
        sortValue: sortValue,
      );
    }

    if (adjustedFilter.radioGroupSelections.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final newParams =
            Map<String, List<String>>.from(uri.queryParametersAll);
        for (final entry in adjustedFilter.radioGroupSelections.entries) {
          if (entry.value.trim().isNotEmpty) {
            newParams[entry.key] = [entry.value.trim()];
          }
        }
        url = _rebuildUrlWithQueryParams(url, newParams);
      }
    }

    _logger.d('$_sourceId REST search: Built URL: $url');

    try {
      // Prepare request: apply delays + set anti-detection headers
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));

      _logger.d('$_sourceId REST search: Fetching URL: $url');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(url));
      _logger.d(
          '$_sourceId REST search: Got response status=${response.statusCode}');

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final selectors = (rawConfig['selectors'] as Map<String, dynamic>?) ?? {};
      final items = _parseItemList(data, selectors, rawConfig);
      _logger.d('$_sourceId REST search: Parsed ${items.length} items');

      final hasNext = _parseHasNextPage(data, selectors);
      final totalPages = _parseTotalPages(data, selectors);
      final totalItems = _parseTotalItems(data, selectors);

      return AdapterSearchResult(
        items: items,
        hasNextPage: hasNext,
        totalPages: totalPages,
        totalItems: totalItems,
      );
    } catch (e, stackTrace) {
      _logger.e('$_sourceId REST search failed',
          error: e, stackTrace: stackTrace);
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    // ── Schema detection ────────────────────────────────────────────────────
    final apiDetail = api?['detail'] as Map<String, dynamic>?;
    if (apiDetail != null) {
      return _fetchDetailNewSchema(contentId, rawConfig, api!, apiDetail);
    }

    final rawEndpoints = (api?['endpoints'] as Map<String, dynamic>?) ?? {};
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };
    final detailTemplate =
        endpoints['detail'] ?? endpoints['galleryDetail'] ?? '';
    if (detailTemplate.isEmpty) {
      _logger.w('$_sourceId: no detail endpoint configured');
      return AdapterDetailResult(
        content: _emptyContent(contentId),
        imageUrls: [],
      );
    }

    final url = _urlBuilder.buildDetailUrl(detailTemplate, contentId);
    _logger.d('$_sourceId REST detail: $url');

    try {
      // Prepare request: apply delays + set anti-detection headers
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));

      _logger.d('$_sourceId REST detail: Fetching URL: $url');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(url));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final selectors = (rawConfig['selectors'] as Map<String, dynamic>?) ?? {};
      final imageUrls = _parseImageUrls(data, selectors, rawConfig);
      final content =
          _parseDetail(contentId, data, selectors, rawConfig, imageUrls);
      final contentWithLanguage =
          _applyDefaultLanguageIfMissing(content, rawConfig);

      return AdapterDetailResult(
        content: contentWithLanguage,
        imageUrls: imageUrls,
      );
    } catch (e) {
      _logger.e('$_sourceId REST detail failed for $contentId', error: e);
      return AdapterDetailResult(
        content: _emptyContent(contentId),
        imageUrls: [],
      );
    }
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final api = rawConfig['api'] as Map<String, dynamic>?;

    // Batch two-phase mode short-circuits before any `endpoints.related`
    // request: phase 1 fetches target ids (thin /recommendation wrapper),
    // phase 2 resolves full item data (incl. cover) via multi-value ids[].
    final apiRelatedSniff = (api?['related'] as Map<String, dynamic>?);
    final batchCfg = apiRelatedSniff?['batch'] as Map<String, dynamic>?;
    if (batchCfg != null) {
      return _fetchRelatedBatch(contentId, rawConfig, api!, batchCfg);
    }

    final rawEndpoints = (api?['endpoints'] as Map<String, dynamic>?) ?? {};
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };
    final relatedTemplate = endpoints['related'] ?? '';
    if (relatedTemplate.isEmpty) return const [];

    final url = _urlBuilder.buildDetailUrl(relatedTemplate, contentId);
    try {
      // Prepare request: apply delays + set anti-detection headers
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));

      _logger.d('$_sourceId REST related: Fetching URL: $url');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(url));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      // New schema: `api.related` block with `items` + `fields` (e.g. MangaDex
      // /recommendation returns wrapper objects whose manga lives in
      // relationships). Falls back to flat top-level `selectors`.
      final apiRelated = (api?['related'] as Map<String, dynamic>?);
      if (apiRelated != null) {
        final itemsPath = apiRelated['items'] as String?;
        if (itemsPath == null) return const [];
        final rawItems =
            _parser.extractItems(data, FieldSelector(selector: itemsPath));
        final fieldsConfig =
            (apiRelated['fields'] as Map<String, dynamic>?) ?? {};
        return rawItems
            .map((item) {
              final fields = _extractRestFields(item, fieldsConfig);
              final mapped = GenericContentMapper.toListItem(
                fields,
                sourceId: _sourceId,
              );
              return _applyDefaultLanguageIfMissing(mapped, rawConfig);
            })
            .where((c) => c.id.isNotEmpty && c.id != contentId)
            .toList();
      }

      final selectors = (rawConfig['selectors'] as Map<String, dynamic>?) ?? {};
      return _parseItemList(data, selectors, rawConfig);
    } catch (e) {
      _logger.w('$_sourceId: fetchRelated failed for $contentId', error: e);
      return const [];
    }
  }

  // Batch two-phase related (see config `api.related.batch`):
  //   Phase 1  — fetch `/manga/{id}/recommendation` (wrapper with target ids)
  //   Phase 2  — fetch `/manga?ids[]=...&includes[]=cover_art&...` resolving
  //              the recommended manga in a single multi-value request, parsed
  //              with the source's list fields (cover via coverBuilder),
  //              reordered back to the phase-1 (score) id order.
  Future<List<Content>> _fetchRelatedBatch(
    String contentId,
    Map<String, dynamic> rawConfig,
    Map<String, dynamic> api,
    Map<String, dynamic> batch,
  ) async {
    final idEndpoint = _getEndpointPath(batch['idEndpoint']);
    if (idEndpoint.isEmpty) return const [];
    final idItems = batch['idItems'] as String?;
    if (idItems == null || idItems.isEmpty) return const [];
    final idField = batch['idField'] as Map<String, dynamic>?;
    if (idField == null) return const [];

    // ── Phase 1: resolve ordered, de-duplicated target ids ───────────────
    final orderedIds = <String>[];
    try {
      final idUrl = _urlBuilder.buildDetailUrl(idEndpoint, contentId);
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
      _logger.d('$_sourceId REST related (batch phase1): $idUrl');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(idUrl));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final rawItems =
          _parser.extractItems(data, FieldSelector(selector: idItems));
      final idSelector = FieldSelector.fromMap(idField);
      final seen = <String>{};
      for (final item in rawItems) {
        final ids = _parser.extractList(item, idSelector);
        for (final raw in ids) {
          final id = raw.toString().trim();
          if (id.isNotEmpty && id != contentId && seen.add(id)) {
            orderedIds.add(id);
          }
        }
      }
    } catch (e) {
      _logger.w('$_sourceId: related batch phase1 failed for $contentId',
          error: e);
      return const [];
    }

    // Graceful degradation: nothing to resolve → no phase-2 request.
    if (orderedIds.isEmpty) return const [];

    // ── Phase 2: batch detail via ids[] ──────────────────────────────────
    final itemsEndpoint = _getEndpointPath(batch['itemsEndpoint']);
    if (itemsEndpoint.isEmpty) return const [];
    final itemsPath = batch['items'] as String?;
    if (itemsPath == null || itemsPath.isEmpty) return const [];

    // `{ids}` → repeated `ids[]=id&ids[]=id…` (relative to `api.list.fields`).
    final fieldsConfig = _resolveBatchFields(batch['fields'], rawConfig);
    if (fieldsConfig.isEmpty) return const [];

    final idsSegment = orderedIds.join('&ids[]=');
    final itemsUrl = _urlBuilder
        .resolve(itemsEndpoint.replaceAll('{ids}', idsSegment), const {});

    try {
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
      _logger.d('$_sourceId REST related (batch phase2): $itemsUrl');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(itemsUrl));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final rawItems =
          _parser.extractItems(data, FieldSelector(selector: itemsPath));
      final byId = <String, Content>{};
      for (final item in rawItems) {
        final fields = _extractRestFields(item, fieldsConfig);
        final mapped = GenericContentMapper.toListItem(
          fields,
          sourceId: _sourceId,
        );
        final content = _applyDefaultLanguageIfMissing(mapped, rawConfig);
        if (content.id.isNotEmpty) {
          byId[content.id] = content;
        }
      }
      // Preserve phase-1 (score) order; drop ids the phase-2 response omitted.
      final result = <Content>[];
      for (final id in orderedIds) {
        final content = byId[id];
        if (content != null) result.add(content);
      }
      return result;
    } catch (e) {
      _logger.w('$_sourceId: related batch phase2 failed for $contentId',
          error: e);
      return const [];
    }
  }

  // Resolves `api.related.batch.fields`, supporting the `"@list.fields"`
  // reference token that reuses the source's `api.list.fields` block.
  Map<String, dynamic> _resolveBatchFields(
    dynamic fieldsDef,
    Map<String, dynamic> rawConfig,
  ) {
    if (fieldsDef is Map<String, dynamic>) return fieldsDef;
    if (fieldsDef is String) {
      final token = fieldsDef.trim();
      if (token.startsWith('@')) {
        var cursor = rawConfig['api'];
        for (final part in token.substring(1).split('.')) {
          if (cursor is Map && cursor[part] is Map) {
            cursor = cursor[part];
          } else {
            return const {};
          }
        }
        return (cursor as Map<String, dynamic>?) ?? const {};
      }
    }
    return const {};
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    final rawEndpoints = (api?['endpoints'] as Map<String, dynamic>?) ?? {};
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };
    final commentsTemplate = endpoints['comments'] ?? '';
    if (commentsTemplate.isEmpty) return const [];

    final url = _urlBuilder.buildDetailUrl(commentsTemplate, contentId);
    try {
      // Prepare request: apply delays + set anti-detection headers
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));

      _logger.d('$_sourceId REST comments: Fetching URL: $url');
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(url));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final selectors = (rawConfig['selectors'] as Map<String, dynamic>?) ?? {};
      return _parseCommentList(data, selectors, rawConfig);
    } catch (e) {
      _logger.w('$_sourceId: fetchComments failed for $contentId', error: e);
      return const [];
    }
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final imagesCfg = rawConfig['api']?['images'] as Map<String, dynamic>?;
    if (imagesCfg == null) return null;

    final mode = imagesCfg['mode'] as String?;

    if (mode == 'atHome') {
      // Existing atHome mode implementation
      final endpoint = imagesCfg['atHomeEndpoint'] as String?;
      if (endpoint == null) return null;

      // Defensive guard: if the caller passed an external URL as the
      // chapterId (e.g. a Comikey link), skip at-home entirely. The
      // primary guard lives in DetailCubit.openChapter; this is a
      // safety net for any other caller.
      if (chapterId.startsWith('http://') || chapterId.startsWith('https://')) {
        _logger.d(
          '$_sourceId fetchChapterImages (atHome) skipped: chapterId is an external URL',
        );
        return null;
      }

      final baseApiUrl = _getBaseUrl(rawConfig);
      final fullPath = endpoint.startsWith('/') ? endpoint : '/$endpoint';
      final url = '$baseApiUrl${fullPath.replaceAll('{chapterId}', chapterId)}';
      _logger.d('$_sourceId REST at-home request: $url');

      try {
        final data = await _getAtHomePayloadWithRetry(
          url,
          rawConfig,
          maxAttempts: 3,
        );

        final baseUrl = data['baseUrl'] as String?;
        final chapterNode = data['chapter'] as Map<String, dynamic>?;
        if (baseUrl != null && chapterNode != null) {
          final hash = chapterNode['hash'] as String?;
          final dataFiles = (chapterNode['data'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList() ??
              const <String>[];
          final dataSaverFiles = (chapterNode['dataSaver'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList() ??
              const <String>[];
          final useDataSaver = dataFiles.isEmpty && dataSaverFiles.isNotEmpty;
          final fileNames = useDataSaver ? dataSaverFiles : dataFiles;

          // Defensive guard: empty at-home payload indicates an external
          // or unavailable chapter. Return null without retrying so the
          // caller can surface a clear error instead of retrying 3x.
          if (hash == null || hash.isEmpty || fileNames.isEmpty) {
            _logger.w(
              '$_sourceId fetchChapterImages (atHome) returned empty payload for $chapterId — likely external or unavailable chapter',
            );
            return null;
          }

          final imagePathSegment = useDataSaver ? 'data-saver' : 'data';
          final images = fileNames
              .map((fn) => '$baseUrl/$imagePathSegment/$hash/$fn')
              .toList();
          return ChapterData(
            images: images,
          );
        }
      } catch (e) {
        _logger.e('$_sourceId fetchChapterImages (atHome) failed', error: e);
      }
    } else if (mode == 'htmlContent') {
      // HTML-in-JSON mode: chapter response JSON contains HTML with data-src images.
      // Config:
      //   "mode": "htmlContent",
      //   "contentPath": "$.chapter_detail.chapter_content",
      //   "serverPath": "$.chapter_detail.server",
      //   "attribute": "data-src"
      _logger.d('$_sourceId REST htmlContent images mode');

      try {
        final itemsSelector = _extractJsonSelector(imagesCfg['items']);
        if (itemsSelector.isEmpty) {
          _logger.w(
              '$_sourceId htmlContent: missing "items" selector (CSS selector for img tags)');
          return null;
        }

        // Fetch chapter content to get images
        final dynamic chapterEndpointRaw = rawConfig['api']?['endpoints']
                ?['images'] ??
            rawConfig['api']?['endpoints']?['pages'];
        final chapterEndpoint = _getEndpointPath(chapterEndpointRaw);
        if (chapterEndpoint.isEmpty) {
          _logger.w('$_sourceId images endpoint not configured');
          return null;
        }

        final baseApiUrl = _getBaseUrl(rawConfig);
        final fullPath = chapterEndpoint.startsWith('/')
            ? chapterEndpoint
            : '/$chapterEndpoint';

        var imageUrl = '$baseApiUrl$fullPath';
        final chapterIdFull = chapterId.trim();

        if (chapterIdFull.contains('/')) {
          final parts = chapterIdFull.split('/');
          imageUrl = imageUrl
              .replaceAll('{id}', parts.first)
              .replaceAll('{chapter}', parts.skip(1).join('/'))
              .replaceAll('{chapterId}', parts.skip(1).join('/'))
              .replaceAll('{chapterIdFull}', chapterIdFull);
        } else {
          imageUrl = imageUrl
              .replaceAll('{id}', chapterIdFull)
              .replaceAll('{chapter}', chapterIdFull)
              .replaceAll('{chapterId}', chapterIdFull)
              .replaceAll('{chapterIdFull}', chapterIdFull);
        }

        imageUrl = _applyLanguagePlaceholder(imageUrl, rawConfig);

        _logger.d('$_sourceId htmlContent request: $imageUrl');

        await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
        final response =
            await _executeRequest<dynamic>(() => _dio.get<dynamic>(imageUrl));
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        // Extract HTML content from JSON
        final contentPath = (imagesCfg['contentPath'] as String?) ??
            r'$.chapter_detail.chapter_content';
        final serverPath = imagesCfg['serverPath'] as String?;
        final imgAttribute = (imagesCfg['attribute'] as String?) ?? 'data-src';

        final contentHtml =
            _parser.extractString(data, FieldSelector(selector: contentPath));
        if (contentHtml == null || contentHtml.isEmpty) {
          _logger.w(
              '$_sourceId htmlContent: no HTML content found at $contentPath');
          return null;
        }

        // Extract server prefix
        String? serverPrefix;
        if (serverPath != null) {
          serverPrefix =
              _parser.extractString(data, FieldSelector(selector: serverPath));
        }

        // Parse HTML with GenericHtmlParser to extract image URLs
        final htmlParser = GenericHtmlParser(logger: _logger);
        final doc = htmlParser.parse(contentHtml);
        final selector = FieldSelector(
          selector: itemsSelector,
          attribute: imgAttribute,
        );
        var images = htmlParser.extractList(doc, selector);

        // Prefix with server if configured
        if (serverPrefix != null && serverPrefix.isNotEmpty) {
          images = images.map((img) {
            if (img.startsWith('/') || !img.startsWith('http')) {
              final separator = serverPrefix!.endsWith('/') ? '' : '/';
              final cleanImg = img.startsWith('/') ? img.substring(1) : img;
              return '$serverPrefix$separator$cleanImg';
            }
            return img;
          }).toList();
        }

        if (images.isNotEmpty) {
          _logger.d(
              '$_sourceId extracted ${images.length} images via htmlContent');
          return ChapterData(images: images);
        }

        _logger.w('$_sourceId htmlContent: no images extracted');
        return null;
      } catch (e) {
        _logger.w('$_sourceId fetchChapterImages (htmlContent) failed: $e');
        return null;
      }
    } else if (mode == 'schaleData') {
      // Schale Network: two-step image fetch
      try {
        final parts = chapterId.split('/');
        if (parts.length < 2) {
          _logger.w('$_sourceId schaleData: chapterId not id/key: $chapterId');
          return null;
        }
        final bookId = parts[0];
        final bookKey = parts[1];
        final baseApiUrl = _getBaseUrl(rawConfig);
        final quality = imagesCfg['quality']?.toString() ?? '1280';
        final dataSel = imagesCfg['dataSelector']?.toString() ?? r'$.data.1280';

        // Step 1: POST detail to get quality-level IDs (id/key for the quality)
        final detailUrl = '$baseApiUrl/books/detail/$bookId/$bookKey';
        await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
        final detailResp = await _executeRequest<dynamic>(
          () => _dio.post<dynamic>(detailUrl),
        );
        final detailData = detailResp.data is String
            ? jsonDecode(detailResp.data as String)
            : detailResp.data;

        // Navigate to quality data: dataSel = "data.1280"
        final pathParts = dataSel.replaceAll(r'$.', '').split('.');
        Object? qNode = detailData;
        for (final k in pathParts) {
          if (k.isEmpty || qNode is! Map) {
            qNode = null;
            break;
          }
          qNode = qNode[k];
        }
        if (qNode is! Map) {
          _logger.w('$_sourceId schaleData: quality data not found');
          return null;
        }
        final qualId = qNode['id']?.toString();
        final qualKey = qNode['key']?.toString();
        if (qualId == null ||
            qualKey == null ||
            qualId.isEmpty ||
            qualKey.isEmpty) {
          _logger.w('$_sourceId schaleData: quality ID/Key missing');
          return null;
        }

        // Step 2: GET page data (CDN base + entries)
        final pageUrl =
            '$baseApiUrl/books/data/$bookId/$bookKey/$qualId/$qualKey/$quality';
        final pageResp = await _executeRequest<dynamic>(
          () => _dio.get<dynamic>(pageUrl),
        );
        final pageData = pageResp.data is String
            ? jsonDecode(pageResp.data as String)
            : pageResp.data;
        if (pageData is! Map) return null;

        final base = pageData['base']?.toString() ?? '';
        final fallback = pageData['fallback']?.toString();
        final entries = pageData['entries'];
        if (base.isEmpty || entries is! List) return null;

        final images = <String>[];
        for (final e in entries) {
          if (e is! Map) continue;
          final p = e['path']?.toString() ?? '';
          if (p.isNotEmpty) {
            final cleanBase =
                base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            final cleanPath = p.startsWith('/') ? p.substring(1) : p;
            var url = '$cleanBase/$cleanPath';

            // Append fallback URL if available
            if (fallback != null && fallback.isNotEmpty) {
              final cleanFallback = fallback.endsWith('/')
                  ? fallback.substring(0, fallback.length - 1)
                  : fallback;
              url = '$url|$cleanFallback/$cleanPath';
            }
            images.add(url);
          }
        }
        if (images.isEmpty) return null;
        _logger.d('$_sourceId schaleData: built ${images.length} CDN URLs');
        return ChapterData(images: images);
      } catch (e) {
        _logger.e('$_sourceId fetchChapterImages (schaleData) failed',
            error: e);
        return null;
      }
    } else if (mode == 'direct') {
      // Direct image URLs mode (e.g., DoujinDesu v2)
      _logger.d('$_sourceId REST direct images mode');

      try {
        final itemsSelector = _extractJsonSelector(imagesCfg['items']);
        if (itemsSelector.isEmpty) {
          _logger.w('$_sourceId direct images missing valid "items" selector');
          return null;
        }

        // Fetch chapter content to get images
        final dynamic chapterEndpointRaw = rawConfig['api']?['endpoints']
                ?['images'] ??
            rawConfig['api']?['endpoints']?['pages'];
        final chapterEndpoint = _getEndpointPath(chapterEndpointRaw);
        if (chapterEndpoint.isEmpty) {
          _logger.w('$_sourceId images endpoint not configured');
          return null;
        }

        final baseApiUrl = _getBaseUrl(rawConfig);
        final fullPath = chapterEndpoint.startsWith('/')
            ? chapterEndpoint
            : '/$chapterEndpoint';

        // Supported chapter ID formats:
        // - Single value: "{chapter}" or "{chapterId}" (legacy/simple sources)
        // - Composite value: "{contentId}/{chapterPart}" (e.g. slug/index)
        //   used by sources that require both series/content ID and chapter ID.
        var imageUrl = '$baseApiUrl$fullPath';
        final chapterIdFull = chapterId.trim();

        if (chapterIdFull.startsWith('http')) {
          imageUrl = chapterIdFull;
          _logger.d('$_sourceId absolute chapter format: $chapterIdFull');
        } else {
          String contentIdToken = chapterIdFull;
          String chapterToken = chapterIdFull;

          if (chapterIdFull.contains('/')) {
            final parts = chapterIdFull.split('/');
            if (parts.length >= 2) {
              contentIdToken = parts.first;
              chapterToken = parts.skip(1).join('/');
            }
          }

          imageUrl = imageUrl
              .replaceAll('{id}', contentIdToken)
              .replaceAll('{chapter}', chapterToken)
              .replaceAll('{chapterId}', chapterToken)
              .replaceAll('{chapterIdFull}', chapterIdFull);

          if (chapterIdFull.contains('/')) {
            _logger.d(
                '$_sourceId composite chapter format: content=$contentIdToken, chapter=$chapterToken');
          } else {
            _logger.d('$_sourceId single chapter format: $chapterIdFull');
          }
        }

        imageUrl = _applyLanguagePlaceholder(imageUrl, rawConfig);

        _logger.d('$_sourceId direct images request: $imageUrl');

        await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
        final response =
            await _executeRequest<dynamic>(() => _dio.get<dynamic>(imageUrl));
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        // Debug: Log the data structure
        _logger.d(
            '$_sourceId images response data keys: ${data is Map ? data.keys : 'not a map'}');

        // For direct mode, images are returned as array of strings (not array of objects)
        // Use extractList which returns List<String> directly
        try {
          var images =
              _parser.extractList(data, FieldSelector(selector: itemsSelector));

          _logger.d(
              '$_sourceId extracted ${images.length} direct images via extractList');

          // Apply proxy URL transformation if configured
          images = _applyImageProxy(images, imagesCfg);

          if (images.isNotEmpty) {
            return ChapterData(
              images: images,
            );
          }
        } catch (e) {
          _logger.w('$_sourceId failed to extract images via extractList: $e');
        }

        // Fallback: try extractItems (for array of objects)
        final rawImages =
            _parser.extractItems(data, FieldSelector(selector: itemsSelector));
        _logger.d(
            '$_sourceId raw images extracted (selector: $itemsSelector): ${rawImages.length} items');

        var images = rawImages
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();

        // Apply proxy URL transformation if configured
        images = _applyImageProxy(images, imagesCfg);

        _logger.d(
            '$_sourceId extracted ${images.length} direct images (fallback)');

        return ChapterData(
          images: images,
        );
      } catch (e) {
        _logger.w('$_sourceId fetchChapterImages (direct) failed: $e');
      }
    }

    return null;
  }

  Future<dynamic> _getAtHomePayloadWithRetry(
    String url,
    Map<String, dynamic> rawConfig, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
        final response = await _executeRequest<dynamic>(
          () => _dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              headers: const {
                'Accept': 'application/json',
                // For unstable mobile networks this can reduce half-closed
                // keep-alive socket issues on subsequent retries.
                'Connection': 'close',
              },
            ),
          ),
        );
        return response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
      } on DioException catch (e) {
        lastError = e;
        lastStackTrace = StackTrace.current;

        if (attempt >= maxAttempts || !_shouldRetryAtHomeDioError(e)) {
          rethrow;
        }

        _logger.w(
          '$_sourceId at-home transient error, retrying '
          '($attempt/$maxAttempts): ${e.message}',
        );
        await Future<void>.delayed(Duration(milliseconds: attempt * 250));
      } catch (e) {
        lastError = e;
        lastStackTrace = StackTrace.current;
        if (attempt >= maxAttempts) {
          rethrow;
        }
        _logger.w(
          '$_sourceId at-home unknown transient error, retrying '
          '($attempt/$maxAttempts): $e',
        );
        await Future<void>.delayed(Duration(milliseconds: attempt * 250));
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(
        lastError,
        lastStackTrace ?? StackTrace.current,
      );
    }
    throw StateError('Unexpected at-home retry flow termination');
  }

  bool _shouldRetryAtHomeDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }

    final message = (e.message ?? '').toLowerCase();
    if (message.contains('connection closed before full header') ||
        message.contains('connection reset by peer') ||
        message.contains('socket') ||
        message.contains('stream was terminated')) {
      return true;
    }

    final error = e.error;
    if (error is SocketException) return true;
    if (error is HttpException &&
        error.message.toLowerCase().contains(
              'connection closed before full header',
            )) {
      return true;
    }

    return false;
  }

  // ── New schema: api.list / api.detail ─────────────────────────────────────
  //
  // When `rawConfig['api']['list']` is present the adapter uses the declarative
  // field-map approach powered by [GenericContentMapper] instead of the
  // legacy flat-selectors path used by nhentai.
  //
  // New config shape:
  //   api.list.items      — JSONPath to items array   (e.g. "$.result[*]")
  //   api.list.fields     — map of fieldName → fieldDef  (see below)
  //   api.list.pagination — { totalPages: {path:…}, currentPage: {path:…} }
  //   api.detail.fields   — same field-map approach
  //   api.detail.images   — image URL builder config
  //
  // Field definitions (values in the `fields` map):
  //   { "selector": "$.id" }                    — scalar JSONPath extraction
  //   { "selector": "$.tags[*].name", "multi": true }  — list extraction
  //   { "type": "tagObjects", "selector": "$.tags[*]" } — nhentai tag split
  //   { "type": "coverBuilder", … }              — template cover URL

  Future<AdapterSearchResult> _searchNewSchema(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
    Map<String, dynamic> api,
    Map<String, dynamic> apiList,
  ) async {
    final rawEndpoints = (api['endpoints'] as Map<String, dynamic>?) ?? {};
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };
    final isEmptyQuery = filter.query.trim().isEmpty && !filter.hasFilters;
    final template = isEmptyQuery
        ? (endpoints['allGalleries'] ?? endpoints['search'] ?? '')
        : (endpoints['search'] ?? '');
    if (template.isEmpty) {
      _logger.w('$_sourceId (new schema): no search endpoint configured');
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }

    final rawParams = _extractRawSearchParams(filter.query);
    final sortValue = _resolveSearchSortValue(filter, rawConfig);
    String url;

    if (rawParams != null && rawParams.isNotEmpty) {
      final rawMap = _parseRawQueryParams(rawParams);
      // NHentai v2 search endpoint rejects requests without a non-empty query
      // param. When raw params have no text query (sort-only), route to
      // allGalleries endpoint which doesn't require a query string.
      final String rawBrowseTmpl;
      if (_sourceId == 'nhentai') {
        rawBrowseTmpl = (!rawMap.keys.any(
                    (k) => ['query', 'q', 'search', 'keyword'].contains(k)) &&
                endpoints['allGalleries'] is String
            ? endpoints['allGalleries'] as String
            : template);
      } else {
        rawBrowseTmpl = template;
      }
      final tagSearchTemplate = endpoints['tagSearch'] ?? '';

      // Check if we have a tagSearch endpoint and any raw params
      if (tagSearchTemplate.isNotEmpty && rawMap.isNotEmpty) {
        final tagValue = _extractTagValueFromRawParams(rawMap);

        if (tagValue != null && tagValue.isNotEmpty) {
          final page = filter.page > 0 ? filter.page : 1;
          final baseTaggedUrl = _urlBuilder.resolve(tagSearchTemplate, {
            'tagId': tagValue,
            'page': page.toString(),
            'sort': sortValue,
            'query': '',
          });

          final mergedParams = _parseUrlQueryParams(baseTaggedUrl);
          for (final entry in rawMap.entries) {
            mergedParams[entry.key] = entry.value;
          }

          if (sortValue.isNotEmpty &&
              !(mergedParams['sort']?.any((v) => v.trim().isNotEmpty) ??
                  false)) {
            mergedParams['sort'] = [sortValue];
          }

          url = _rebuildUrlWithQueryParams(baseTaggedUrl, mergedParams);
        } else {
          url = _buildRawSearchUrl(rawBrowseTmpl, rawParams, filter);
        }
      } else {
        url = _buildRawSearchUrl(rawBrowseTmpl, rawParams, filter);
      }
    } else {
      url = _urlBuilder.buildSearchUrl(
        template,
        filter,
        sortValue: sortValue,
      );
    }

    // 🔧 SORT FIX: Always override the `sort` query param with the resolved value.
    // Some endpoints (e.g. `allGalleries`) have a hardcoded `sort=X` param in their
    // config and no `{sort}` placeholder, so `buildSearchUrl` cannot inject sort.
    // We force-apply it here so the user's sort selection always takes effect.
    if (sortValue.isNotEmpty) {
      final sortParamName =
          (rawConfig['searchConfig']?['sortParamName'] as String?) ?? 'sort';
      // Only override if the URL already contains this param (i.e., the endpoint
      // supports sorting) or if the resolved sort differs from the template default.
      final templateHasSortParam =
          Uri.tryParse(url)?.queryParameters.containsKey(sortParamName) ??
              false;
      final templateHasSortPlaceholder = template.contains('{$sortParamName}');
      if (templateHasSortParam || templateHasSortPlaceholder) {
        final currentSortInUrl =
            Uri.tryParse(url)?.queryParameters[sortParamName] ?? '';
        if (currentSortInUrl != sortValue) {
          url = _upsertQueryParam(url, sortParamName, sortValue);
          _logger.d(
              '$_sourceId sort override: "$currentSortInUrl" → "$sortValue" (user selected)');
        }
      }
    }
    final paginationCfg =
        (apiList['pagination'] as Map<String, dynamic>?) ?? {};
    if (paginationCfg['offsetMode'] == true) {
      final pageSize = paginationCfg['pageSize'] as int? ?? 20;
      final maxOffset = paginationCfg['maxOffset'] as int?;
      var offset = ((filter.page > 0 ? filter.page : 1) - 1) * pageSize;
      // Guard offset-based sources that enforce strict query window caps.
      if (maxOffset != null && offset > maxOffset) {
        offset = maxOffset;
      }
      url = url.replaceAll('{offset}', offset.toString());
    }
    url = _applyLanguagePlaceholder(
      url,
      rawConfig,
      requestedLanguage: filter.language,
    );
    final queryRules = (api['queryRules'] as Map<String, dynamic>?)?['search']
        as Map<String, dynamic>?;
    url = _applyQueryRules(url, queryRules);

    if (filter.radioGroupSelections.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final newParams =
            Map<String, List<String>>.from(uri.queryParametersAll);
        for (final entry in filter.radioGroupSelections.entries) {
          if (entry.value.trim().isNotEmpty) {
            newParams[entry.key] = [entry.value.trim()];
          }
        }
        url = _rebuildUrlWithQueryParams(url, newParams);
      }
    }

    _logger.d('$_sourceId REST [new schema] search: $url');

    try {
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(url));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final itemsPath = apiList['items'] as String?;
      if (itemsPath == null) {
        return const AdapterSearchResult(items: [], hasNextPage: false);
      }

      final rawItems =
          _parser.extractItems(data, FieldSelector(selector: itemsPath));
      final fieldsConfig = (apiList['fields'] as Map<String, dynamic>?) ?? {};
      final items = rawItems
          .map((item) {
            final fields = _extractRestFields(item, fieldsConfig);
            _resolveLanguageTagMap(fields, rawConfig);
            final mapped = GenericContentMapper.toListItem(
              fields,
              sourceId: _sourceId,
            );
            return _applyDefaultLanguageIfMissing(mapped, rawConfig);
          })
          .where((c) => c.id.isNotEmpty)
          .toList();

      // Pagination
      final paginationCfg =
          (apiList['pagination'] as Map<String, dynamic>?) ?? {};
      bool hasNext = true;
      int? totalPages;
      int? totalItems;

      if (paginationCfg['offsetMode'] == true) {
        final totalStr = _extractRestScalar(data, paginationCfg['total']);
        final limitStr = _extractRestScalar(data, paginationCfg['limit']);
        final offsetStr = _extractRestScalar(data, paginationCfg['offset']);
        final maxOffset = paginationCfg['maxOffset'] as int?;

        final total = int.tryParse(totalStr ?? '');
        final limit = int.tryParse(limitStr ?? '');
        final offset = int.tryParse(offsetStr ?? '');
        totalItems = total;

        if (total != null && limit != null && offset != null) {
          hasNext = (offset + limit) < total;
          totalPages = (total / limit).ceil();

          if (maxOffset != null && limit > 0) {
            final maxReachablePages = (maxOffset ~/ limit) + 1;
            if (totalPages > maxReachablePages) {
              totalPages = maxReachablePages;
            }

            // Prevent next-page navigation beyond allowed offset window.
            final nextOffset = offset + limit;
            if (nextOffset > maxOffset) {
              hasNext = false;
            }
          }
        }
      } else {
        final totalPagesStr =
            _extractRestScalar(data, paginationCfg['totalPages']);
        final currentPageStr =
            _extractRestScalar(data, paginationCfg['currentPage']) ??
                _extractRestScalar(data, paginationCfg['page']);
        final totalItemsStr =
            _extractRestScalar(data, paginationCfg['total']) ??
                _extractRestScalar(data, paginationCfg['totalItems']) ??
                _extractRestScalar(data, paginationCfg['totalCount']);
        final limitStr = _extractRestScalar(data, paginationCfg['limit']) ??
            _extractRestScalar(data, paginationCfg['pageSize']);

        totalItems = int.tryParse(totalItemsStr ?? '');

        if (totalPagesStr != null && currentPageStr != null) {
          totalPages = int.tryParse(totalPagesStr);
          final current = int.tryParse(currentPageStr);
          if (totalPages != null && current != null) {
            hasNext = current < totalPages;
          }
        } else {
          totalPages = _deriveTotalPagesFromTotal(
            totalStr: totalItemsStr,
            limitStr: limitStr,
          );
          final current = int.tryParse(currentPageStr ?? '');
          if (totalPages != null && current != null) {
            hasNext = current < totalPages;
          }
        }
      }

      return AdapterSearchResult(
        items: items,
        hasNextPage: hasNext,
        totalPages: totalPages,
        totalItems: totalItems,
      );
    } catch (e) {
      _logger.e('$_sourceId REST new schema search failed', error: e);
      return const AdapterSearchResult(items: [], hasNextPage: false);
    }
  }

  Future<AdapterDetailResult> _fetchDetailNewSchema(
    String contentId,
    Map<String, dynamic> rawConfig,
    Map<String, dynamic> api,
    Map<String, dynamic> apiDetail,
  ) async {
    final rawEndpoints = (api['endpoints'] as Map<String, dynamic>?) ?? {};
    final endpoints = <String, String>{
      for (final e in rawEndpoints.entries) e.key: _getEndpointPath(e.value),
    };
    final template = endpoints['detail'] ?? endpoints['galleryDetail'] ?? '';
    if (template.isEmpty) {
      _logger.w('$_sourceId (new schema): no detail endpoint configured');
      return AdapterDetailResult(
          content: _emptyContent(contentId), imageUrls: []);
    }

    // When this source composes chapter IDs as "{parentSlug}/{chapterIndex}"
    // (i.e., `detail.chapters.composeIdWithContentId == true`), the detail
    // endpoint must only receive the parent slug — not the full composite ID.
    // Example: contentId = "doctors-rebirth/234" but the detail path is
    // "/series/{id}" → would build "/series/doctors-rebirth/234" (404).
    // Fix: strip the chapter part so the URL becomes "/series/doctors-rebirth".
    final chaptersCfg = apiDetail['chapters'] as Map<String, dynamic>?;
    final usesCompositeChapterIds =
        chaptersCfg?['composeIdWithContentId'] == true;
    final idForDetail = (usesCompositeChapterIds && contentId.contains('/'))
        ? contentId.substring(0, contentId.indexOf('/'))
        : contentId;

    final url = _urlBuilder.buildDetailUrl(template, idForDetail);
    final detailUrl = _applyLanguagePlaceholder(url, rawConfig);
    _logger.d('$_sourceId REST [new schema] detail: $detailUrl'
        '${idForDetail != contentId ? ' (stripped chapter from "$contentId" → "$idForDetail")' : ''}');

    try {
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
      final response =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(detailUrl));
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final fieldsConfig = (apiDetail['fields'] as Map<String, dynamic>?) ?? {};
      final fields = _extractRestFields(data, fieldsConfig);

      // Enrich tags/artists from configurable relationship mapping so UI chips
      // can carry stable IDs (e.g., UUID for authorOrArtist navigation).
      _applyConfiguredTagRelationsToFields(
        data: data,
        rawConfig: rawConfig,
        fields: fields,
      );

      // Optional statistics enrichment (e.g., MangaDex follows count).
      final statsCfg = api['statistics'] as Map<String, dynamic>?;
      if (statsCfg != null) {
        final followsEndpoint = statsCfg['followsEndpoint'] as String?;
        if (followsEndpoint != null && followsEndpoint.isNotEmpty) {
          final baseApiUrl = _getBaseUrl(rawConfig);
          final fullPath = followsEndpoint.startsWith('/')
              ? followsEndpoint
              : '/$followsEndpoint';
          final statsUrl =
              '$baseApiUrl${fullPath.replaceAll('{id}', contentId)}';

          try {
            final statsRes = await _executeRequest<dynamic>(
              () => _dio.get<dynamic>(statsUrl),
            );
            final statsData = statsRes.data is String
                ? jsonDecode(statsRes.data as String)
                : statsRes.data;

            final followsPath = statsCfg['followsPath'] as String?;
            final follows = _extractIntByPath(
              statsData,
              followsPath,
              dynamicId: contentId,
            );
            if (follows != null) {
              fields['favorites'] = follows;
            }
          } catch (e) {
            _logger.w('$_sourceId detail statistics fetch failed: $e');
          }
        }
      }

      // Image URLs
      List<String> imageUrls = const [];
      final imagesCfg = apiDetail['images'] as Map<String, dynamic>?;
      if (imagesCfg != null) {
        imageUrls = _buildImageUrlsFromTemplate(data, imagesCfg);
      }

      // Chapters
      List<Chapter>? chapters;
      // chaptersCfg is already declared above (used to detect composite IDs)
      if (chaptersCfg != null) {
        final chapterEndpoint = chaptersCfg['endpoint'] as String?;
        final itemsSelector = chaptersCfg['items'] as String?;

        if (chapterEndpoint != null) {
          // Fetch chapters from separate endpoint (existing behavior)
          final baseApiUrl = _getBaseUrl(rawConfig);
          final fullPath = chapterEndpoint.startsWith('/')
              ? chapterEndpoint
              : '/$chapterEndpoint';
          // Use idForDetail (parent slug) for chapter URL – the raw contentId
          // may be composite ("slug/234") which would yield an invalid URL.
          var chapterUrl =
              '$baseApiUrl${fullPath.replaceAll('{id}', idForDetail)}';
          chapterUrl = _applyLanguagePlaceholder(chapterUrl, rawConfig);
          final chapterQueryRules = (api['queryRules']
              as Map<String, dynamic>?)?['chapters'] as Map<String, dynamic>?;
          chapterUrl = _applyQueryRules(chapterUrl, chapterQueryRules);

          // Inject translatedLanguage[] from availableTranslatedLanguages so
          // only one language is fetched initially. The chips in the UI read
          // from availableTranslatedLanguages (from manga detail), not chapters.
          if (!chapterUrl.contains('{language}')) {
            final availLangs = fields['availableTranslatedLanguages'];
            String? lang;
            if (availLangs is List) {
              lang = availLangs.cast<String>().firstWhere(
                    (l) => l == 'en',
                    orElse: () => availLangs.isNotEmpty
                        ? availLangs.first.toString()
                        : '',
                  );
            }
            lang = (lang != null && lang.isNotEmpty && lang != 'unknown')
                ? lang
                : _resolveLanguageCode(
                    defaultLanguage: rawConfig['defaultLanguage'] as String?,
                  );
            chapterUrl = _replaceMultiValueParam(
              chapterUrl,
              paramName: 'translatedLanguage[]',
              values: [lang],
            );
          }

          try {
            if (itemsSelector != null) {
              final cFields =
                  (chaptersCfg['fields'] as Map<String, dynamic>?) ?? {};
              final fallbackFields =
                  (chaptersCfg['fallbackFields'] as Map<String, dynamic>?);
              chapters = await _fetchChapters(
                chapterUrl,
                itemsSelector: itemsSelector,
                cFields: cFields,
                rawConfig: rawConfig,
                fallbackFields: fallbackFields,
                autoPaginate: chaptersCfg['autoPaginate'] != false,
              );
              chapters = _composeChapterIdsWithContentId(
                chapters,
                chaptersCfg: chaptersCfg,
                contentId: idForDetail,
              );
            }
          } catch (e) {
            _logger.w('$_sourceId detail chapters fetch failed: $e');
          }
        } else if (itemsSelector != null) {
          // Parse chapters inline from detail response (NEW: for sources like DoujinDesu v2)
          try {
            final cFields =
                (chaptersCfg['fields'] as Map<String, dynamic>?) ?? {};
            chapters = _parseChaptersInline(
              data,
              contentId: contentId,
              itemsSelector: itemsSelector,
              cFields: cFields,
              rawConfig: rawConfig,
            );
            if (chapters != null) {
              chapters = _composeChapterIdsWithContentId(
                chapters,
                chaptersCfg: chaptersCfg,
                contentId: idForDetail,
              );
            }
            _logger.d(
                '$_sourceId: Parsed ${chapters?.length ?? 0} chapters inline from detail response');
          } catch (e) {
            _logger.w('$_sourceId detail inline chapters parse failed: $e');
          }
        }
      }

      // Volumes
      final volumesCfg = apiDetail['volumes'] as Map<String, dynamic>?;
      if (volumesCfg != null) {
        final volEndpoint = volumesCfg['endpoint'] as String?;
        final volItemsSelector = volumesCfg['items'] as String?;
        if (volEndpoint != null && volItemsSelector != null) {
          final baseApiUrl = _getBaseUrl(rawConfig);
          final fullPath =
              volEndpoint.startsWith('/') ? volEndpoint : '/$volEndpoint';
          var volUrl = '$baseApiUrl${fullPath.replaceAll('{id}', idForDetail)}';
          volUrl = _applyLanguagePlaceholder(volUrl, rawConfig);

          try {
            final vFields =
                (volumesCfg['fields'] as Map<String, dynamic>?) ?? {};
            final fallbackFields =
                (volumesCfg['fallbackFields'] as Map<String, dynamic>?);
            var volumes = await _fetchChapters(
              volUrl,
              itemsSelector: volItemsSelector,
              cFields: vFields,
              rawConfig: rawConfig,
              fallbackFields: fallbackFields,
              autoPaginate: volumesCfg['autoPaginate'] != false,
            );
            volumes = _composeChapterIdsWithContentId(
              volumes,
              chaptersCfg: volumesCfg,
              contentId: idForDetail,
            );
            chapters = [...(chapters ?? []), ...volumes];
          } catch (e) {
            _logger.w('$_sourceId detail volumes fetch failed: $e');
          }
        }
      }

      final content = GenericContentMapper.toDetail(
        idForDetail,
        fields,
        sourceId: _sourceId,
        imageUrls: imageUrls,
        chapters: chapters,
      );
      final contentWithLanguage =
          _applyDefaultLanguageIfMissing(content, rawConfig);
      return AdapterDetailResult(
        content: contentWithLanguage,
        imageUrls: imageUrls,
      );
    } catch (e) {
      _logger.e('$_sourceId REST new schema detail failed for $contentId',
          error: e);
      return AdapterDetailResult(
          content: _emptyContent(contentId), imageUrls: []);
    }
  }

  // Extract all `fields` from a JSON [data] object according to `fieldsConfig`.
  ///
  // Field def types:
  // - default (`path`)  — JSONPath scalar (or list if `multi: true`)
  // - `tagObjects`      — extract list of tag Maps and store as `tagObjects`
  //   key so [GenericContentMapper] can split by type.
  // - `coverBuilder`    — build cover URL via template (same as old adapter).
  Map<String, dynamic> _extractRestFields(
    dynamic data,
    Map<String, dynamic> fieldsConfig,
  ) {
    final result = <String, dynamic>{};
    for (final entry in fieldsConfig.entries) {
      final fieldName = entry.key;
      final def = entry.value;
      if (def is! Map<String, dynamic>) continue;

      final type = def['type'] as String? ?? 'path';
      final path = def['selector'] as String? ?? def['path'] as String? ?? '';

      switch (type) {
        case 'tagObjects':
          if (path.isNotEmpty) {
            final rawObjs =
                _parser.extractItems(data, FieldSelector(selector: path));
            // Support field remapping via `fields` config (e.g., API returns
            // `tag_name` but mapper expects `name`).
            final fieldMap = (def['fields'] as Map<String, dynamic>?)
                ?.cast<String, Map<String, dynamic>>();
            if (fieldMap != null && fieldMap.isNotEmpty) {
              final objs = rawObjs.map((obj) {
                final mapped = <String, dynamic>{};
                for (final entry in fieldMap.entries) {
                  final srcSel = entry.value['selector'] as String? ?? '';
                  if (srcSel.isNotEmpty) {
                    // Use extractRaw to preserve original types (int for IDs).
                    final raw = _parser.extractRaw(
                      obj,
                      FieldSelector(selector: srcSel),
                    );
                    if (raw != null) {
                      // Flatten single-element lists.
                      if (raw is List && raw.length == 1) {
                        mapped[entry.key] = raw.first;
                      } else {
                        mapped[entry.key] = raw;
                      }
                    }
                  }
                }
                return mapped;
              }).toList();
              result['tagObjects'] = objs;
            } else {
              result['tagObjects'] = rawObjs;
            }
          }
          break;

        case 'coverBuilder':
          result[fieldName] = _buildCoverUrl(data, def, null) ?? '';
          break;

        default:
          if (def.containsKey('value')) {
            result[fieldName] = def['value'];
            break;
          }
          if (path.isEmpty) continue;
          final multi = def['multi'] as bool? ?? false;
          final sel = FieldSelector.fromMap(def);
          if (multi) {
            result[fieldName] = _parser.extractList(data, sel);
          } else {
            result[fieldName] = _parser.extractRaw(data, sel);
          }

          // Support field composition: compose `id` from `$.id` + `$.key`.
          // Config: `"id": { "selector": "$.id", "composeWith": { "field": "key", "joiner": "/" } }`
          final composeWith = def['composeWith'] as Map<String, dynamic>?;
          if (composeWith != null) {
            final sourceField = composeWith['field'] as String? ?? '';
            final joiner = composeWith['joiner'] as String? ?? '/';
            if (sourceField.isNotEmpty) {
              final sourceDef = fieldsConfig[sourceField];
              if (sourceDef is Map<String, dynamic>) {
                final sourceSel = FieldSelector.fromMap(sourceDef);
                final sourceValue = _parser.extractString(data, sourceSel);
                if (sourceValue != null && sourceValue.isNotEmpty) {
                  final baseValue = (result[fieldName]?.toString() ?? '');
                  if (baseValue.isNotEmpty) {
                    result[fieldName] = '$baseValue$joiner$sourceValue';
                  }
                }
              }
            }
          }

          break;
      }
    }
    return result;
  }

  // Extract a scalar string from [data] using a field def `{path: "…"}`.
  String? _extractRestScalar(dynamic data, dynamic fieldDef) {
    if (fieldDef == null) return null;
    if (fieldDef is Map && fieldDef.containsKey('value')) {
      return fieldDef['value']?.toString();
    }
    final path = _extractJsonSelector(fieldDef);
    if (path.isEmpty) return null;
    return _parser.extractString(data, FieldSelector(selector: path));
  }

  // ── Private parsers ────────────────────────────────────────────────────────

  List<Content> _parseItemList(
    dynamic data,
    Map<String, dynamic> selectors,
    Map<String, dynamic> rawConfig,
  ) {
    final itemsSelector = _selectorOrNull(selectors, 'items') ??
        _selectorOrNull(selectors, 'results');
    if (itemsSelector == null) return const [];

    final items = _parser.extractItems(data, itemsSelector);
    return items
        .map((item) => _parseItem(item, selectors, rawConfig))
        .map((item) => _applyDefaultLanguageIfMissing(item, rawConfig))
        .toList();
  }

  List<Comment> _parseCommentList(dynamic data, Map<String, dynamic> selectors,
      Map<String, dynamic> rawConfig) {
    final commentsSelector = _selectorOrNull(selectors, 'comments');
    if (commentsSelector == null) return const [];

    final baseUrl = _getBaseUrl(rawConfig);
    final avatarBaseUrl = rawConfig['avatarBaseUrl'] as String? ?? baseUrl;
    final items = _parser.extractItems(data, commentsSelector);
    return items
        .map((item) => _parseComment(item, selectors, avatarBaseUrl))
        .toList();
  }

  Comment _parseComment(
      Map<String, dynamic> item, Map<String, dynamic> selectors,
      [String? baseUrl]) {
    final id = _extract(item, selectors, 'commentId') ?? '';
    final username =
        _extract(item, selectors, 'commentUsername') ?? 'Anonymous';
    final body = _extract(item, selectors, 'commentBody') ?? '';
    final rawAvatarUrl = _extract(item, selectors, 'commentAvatarUrl');
    final avatarUrl = _resolveAvatarUrl(rawAvatarUrl, baseUrl);
    _logger.t(
        '$_sourceId comment avatar: raw=$rawAvatarUrl → resolved=$avatarUrl');
    final postDateStr = _extract(item, selectors, 'commentPostDate');

    DateTime? postDate;
    if (postDateStr != null) {
      // Unix timestamp (seconds)
      final timestamp = int.tryParse(postDateStr);
      if (timestamp != null) {
        postDate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      }
    }

    return Comment(
      id: id,
      username: username,
      body: body,
      avatarUrl: avatarUrl,
      postDate: postDate,
    );
  }

  Content _parseItem(
    Map<String, dynamic> item,
    Map<String, dynamic> selectors,
    Map<String, dynamic> rawConfig,
  ) {
    final id = _extract(item, selectors, 'id') ?? '';
    final title = _extract(item, selectors, 'listTitle') ??
        _extract(item, selectors, 'title') ??
        extractNhentaiV2ListTitle(item, sourceId: _sourceId);
    final mediaId = _extract(item, selectors, 'mediaId');

    // Build cover URL: prefer config-driven relative asset path, then legacy fields.
    final coverUrl = _extractResolvedAsset(
          item,
          selectors,
          key: 'listThumbnailPath',
          rawConfig: rawConfig,
          hostKey: 'thumbnail',
        ) ??
        _extractResolvedAsset(
          item,
          selectors,
          key: 'listCoverPath',
          rawConfig: rawConfig,
          hostKey: 'thumbnail',
        ) ??
        resolveNhentaiV2CoverUrl(item, sourceId: _sourceId) ??
        _extract(item, selectors, 'thumbnail') ??
        _extract(item, selectors, 'coverUrl') ??
        _buildCoverUrl(item, selectors, mediaId) ??
        '';

    final tagsRaw = _parser.extractList(
      item,
      _selectorOrDefault(
          selectors, 'tags', const FieldSelector(selector: r'$.tags[*].name')),
    );
    final tags = _stringsToTags(tagsRaw, 'tag');

    final artistsRaw = _parser.extractList(
      item,
      _selectorOrDefault(selectors, 'artists',
          const FieldSelector(selector: r'$.artists[*].name')),
    );

    final charactersRaw = _parser.extractList(
      item,
      _selectorOrDefault(selectors, 'characters',
          const FieldSelector(selector: r'$.characters[*].name')),
    );

    final tagIdsRaw = _selectorOrNull(selectors, 'tagIds') != null
        ? _parser.extractList(item, _selectorOrNull(selectors, 'tagIds')!)
        : const <String>[];
    final tagIdTokens = tagIdsRaw
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final blacklistCharacterTokens = tagIdTokens.isEmpty
        ? charactersRaw
        : <String>{...charactersRaw, ...tagIdTokens}.toList(growable: false);

    return Content(
      id: id,
      sourceId: _sourceId,
      title: title,
      coverUrl: coverUrl,
      tags: tags,
      artists: artistsRaw,
      characters: blacklistCharacterTokens,
      parodies: const [],
      groups: const [],
      language: _extractLanguage(item, selectors, rawConfig: rawConfig),
      pageCount:
          int.tryParse(_extract(item, selectors, 'pageCount') ?? '') ?? 0,
      imageUrls: const [],
      uploadDate: _parseDate(_extract(item, selectors, 'uploadDate')),
      mediaId: mediaId,
    );
  }

  Content _parseDetail(
    String contentId,
    dynamic data,
    Map<String, dynamic> selectors,
    Map<String, dynamic> rawConfig,
    List<String> imageUrls,
  ) {
    final id = _extract(data, selectors, 'id') ?? contentId;
    final title = _extract(data, selectors, 'detailTitle') ??
        _extract(data, selectors, 'title') ??
        extractNhentaiV2DetailTitle(data, sourceId: _sourceId);
    final mediaId = _extract(data, selectors, 'mediaId');
    final coverUrl = _extractResolvedAsset(
          data,
          selectors,
          key: 'detailCoverPath',
          rawConfig: rawConfig,
          hostKey: 'thumbnail',
        ) ??
        _extractResolvedAsset(
          data,
          selectors,
          key: 'detailThumbnailPath',
          rawConfig: rawConfig,
          hostKey: 'thumbnail',
        ) ??
        resolveNhentaiV2CoverUrl(data, sourceId: _sourceId) ??
        _extract(data, selectors, 'thumbnail') ??
        _extract(data, selectors, 'coverUrl') ??
        _buildCoverUrl(data, selectors, mediaId) ??
        (imageUrls.isNotEmpty ? imageUrls.first : '');

    // If the source puts ALL metadata (artists, characters, etc.) into a
    // single `tags[]` array differentiated by a `type` field (e.g. nhentai),
    // the config can declare a `tagObjects` selector pointing to that array.
    // The adapter will parse full objects and split by type, preserving id/count.
    final tagObjectsSel = _selectorOrNull(selectors, 'tagObjects');
    late List<Tag> tags;
    late List<String> artistsRaw;
    late List<String> charactersRaw;
    late List<String> parodiesRaw;
    late List<String> groupsRaw;
    String? splitLanguage;

    if (tagObjectsSel != null) {
      final split = _parseTagObjects(data, tagObjectsSel);
      tags = split.tags;
      artistsRaw = split.artists;
      charactersRaw = split.characters;
      parodiesRaw = split.parodies;
      groupsRaw = split.groups;
      splitLanguage = split.language.isNotEmpty ? split.language : null;
    } else {
      final tagsRaw = _parser.extractList(
        data,
        _selectorOrDefault(selectors, 'tags',
            const FieldSelector(selector: r'$.tags[*].name')),
      );
      tags = _stringsToTags(tagsRaw, 'tag');
      artistsRaw = _parser.extractList(
        data,
        _selectorOrDefault(selectors, 'artists',
            const FieldSelector(selector: r'$.artists[*].name')),
      );
      charactersRaw = _parser.extractList(
        data,
        _selectorOrDefault(selectors, 'characters',
            const FieldSelector(selector: r'$.characters[*].name')),
      );
      parodiesRaw = _parser.extractList(
        data,
        _selectorOrDefault(selectors, 'parodies',
            const FieldSelector(selector: r'$.parodies[*].name')),
      );
      groupsRaw = _parser.extractList(
        data,
        _selectorOrDefault(selectors, 'groups',
            const FieldSelector(selector: r'$.groups[*].name')),
      );

      _applyConfiguredTagRelations(
        data: data,
        rawConfig: rawConfig,
        tags: tags,
        artistsRaw: artistsRaw,
      );
    }

    final pageCountStr = _extract(data, selectors, 'pageCount');
    final pageCount = int.tryParse(pageCountStr ?? '') ?? imageUrls.length;
    final favoritesFromSelector =
        int.tryParse(_extract(data, selectors, 'favorites') ?? '');
    final favoritesFromNhentai = (data is Map)
        ? int.tryParse(data['num_favorites']?.toString() ?? '')
        : null;
    final favorites = favoritesFromSelector ?? favoritesFromNhentai ?? 0;

    return Content(
      id: id,
      sourceId: _sourceId,
      title: title,
      coverUrl: coverUrl,
      tags: tags,
      artists: artistsRaw,
      characters: charactersRaw,
      parodies: parodiesRaw,
      groups: groupsRaw,
      language: splitLanguage ??
          _extractLanguage(data, selectors, rawConfig: rawConfig),
      pageCount: pageCount,
      imageUrls: imageUrls,
      uploadDate: _parseDate(_extract(data, selectors, 'uploadDate')),
      favorites: favorites,
      englishTitle: _extract(data, selectors, 'detailEnglishTitle') ??
          _extract(data, selectors, 'englishTitle') ??
          extractNhentaiV2Field(data, 'english', sourceId: _sourceId),
      japaneseTitle: _extract(data, selectors, 'detailJapaneseTitle') ??
          _extract(data, selectors, 'japaneseTitle') ??
          extractNhentaiV2Field(data, 'japanese', sourceId: _sourceId),
      mediaId: mediaId,
    );
  }

  // Extract image URLs from the response.
  ///
  // Supports two modes:
  // 1. Direct JSONPath selector under `selectors['imageUrls']` or `selectors['images']`
  // 2. Template-based URL building via `selectors['imageUrlBuilder']` — used for sources
  //    like nhentai where image URLs must be constructed from `media_id` + page extensions.
  List<String> _parseImageUrls(
    dynamic data,
    Map<String, dynamic> selectors,
    Map<String, dynamic> rawConfig,
  ) {
    final configuredPaths = _extractResolvedAssetList(
      data,
      selectors,
      key: 'imagePaths',
      rawConfig: rawConfig,
      hostKey: 'image',
    );
    if (configuredPaths.isNotEmpty) {
      return configuredPaths;
    }

    final nhentaiV2Urls = resolveNhentaiV2ImageUrls(data, sourceId: _sourceId);
    if (nhentaiV2Urls.isNotEmpty) {
      return nhentaiV2Urls;
    }

    // Mode 2: imageUrlBuilder (template + per-page extension list)
    final builder = selectors['imageUrlBuilder'] as Map<String, dynamic>?;
    if (builder != null) {
      return _buildImageUrlsFromTemplate(data, builder);
    }

    // Mode 1: direct JSONPath selector
    final imageSelector = _selectorOrNull(selectors, 'imageUrls') ??
        _selectorOrNull(selectors, 'images');
    if (imageSelector == null) return const [];
    return _parser.extractList(data, imageSelector);
  }

  bool _parseHasNextPage(dynamic data, Map<String, dynamic> selectors) {
    final totalPagesStr = _extract(data, selectors, 'totalPages');
    final currentPageStr = _extract(data, selectors, 'currentPage') ??
        _extract(data, selectors, 'page');
    if (totalPagesStr != null && currentPageStr != null) {
      final total = int.tryParse(totalPagesStr);
      final current = int.tryParse(currentPageStr);
      if (total != null && current != null) return current < total;
    }

    final derivedTotalPages = _deriveTotalPagesFromTotal(
      totalStr: _extract(data, selectors, 'totalItems') ??
          _extract(data, selectors, 'totalCount') ??
          _extract(data, selectors, 'total'),
      limitStr: _extract(data, selectors, 'pageSize') ??
          _extract(data, selectors, 'limit'),
    );
    if (derivedTotalPages != null && currentPageStr != null) {
      final current = int.tryParse(currentPageStr);
      if (current != null) {
        return current < derivedTotalPages;
      }
    }

    // If no pagination info, assume more pages unless empty result.
    return true;
  }

  int? _parseTotalPages(dynamic data, Map<String, dynamic> selectors) {
    final totalPagesStr = _extract(data, selectors, 'totalPages');
    if (totalPagesStr != null) {
      return int.tryParse(totalPagesStr);
    }
    return _deriveTotalPagesFromTotal(
      totalStr: _extract(data, selectors, 'totalItems') ??
          _extract(data, selectors, 'totalCount') ??
          _extract(data, selectors, 'total'),
      limitStr: _extract(data, selectors, 'pageSize') ??
          _extract(data, selectors, 'limit'),
    );
  }

  int? _parseTotalItems(dynamic data, Map<String, dynamic> selectors) {
    final totalItemsStr = _extract(data, selectors, 'totalItems') ??
        _extract(data, selectors, 'totalCount') ??
        _extract(data, selectors, 'total');
    if (totalItemsStr != null) {
      return int.tryParse(totalItemsStr);
    }
    return null;
  }

  int? _deriveTotalPagesFromTotal({
    required String? totalStr,
    required String? limitStr,
  }) {
    final total = int.tryParse(totalStr ?? '');
    final limit = int.tryParse(limitStr ?? '');
    if (total == null || limit == null || limit <= 0) {
      return null;
    }
    return (total / limit).ceil();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Extract headers from network.headers configuration block.
  Map<String, String> _extractHeaders(Map<String, dynamic> rawConfig) {
    _logger.d(
        '$_sourceId: _extractHeaders called, rawConfig keys: ${rawConfig.keys.toList()}');

    final network = rawConfig['network'] as Map<String, dynamic>?;
    if (network == null) {
      _logger.w('$_sourceId: network config is null');
      return const {};
    }

    _logger.d('$_sourceId: network keys: ${network.keys.toList()}');

    final headersRaw = network['headers'] as Map<String, dynamic>?;
    if (headersRaw == null) {
      _logger.w('$_sourceId: network.headers is null');
      return const {};
    }

    _logger.d('$_sourceId: Found ${headersRaw.length} headers in config');

    // Convert all values to strings
    final headers =
        headersRaw.map((key, value) => MapEntry(key, value.toString()));
    _logger.d('$_sourceId: Extracted headers: ${headers.keys.toList()}');
    return headers;
  }

  // Merge Dio's default headers with configured headers.
  // Configured headers take precedence for conflicts (e.g., override User-Agent).
  // Preserves critical headers like cookies from Cloudflare bypass.
  Map<String, dynamic> _mergeHeaders(
    Map<String, dynamic> dioDefaultHeaders,
    Map<String, String> configuredHeaders,
  ) {
    final merged = <String, dynamic>{...dioDefaultHeaders};
    configuredHeaders.forEach((key, value) {
      merged[key] = value;
    });
    _logger.d(
        '$_sourceId: Merged headers - Dio: ${dioDefaultHeaders.length}, Configured: ${configuredHeaders.length}, Total: ${merged.length}');
    return merged;
  }

  // Get request headers with proper priority:
  // 1. If HeadersGenerator provided (AntiDetection), use it (highest priority)
  // 2. Otherwise, merge config headers with Dio defaults
  // 3. If no config headers, use Dio defaults only
  // Prepare HTTP request by applying delays and setting anti-detection headers.
  ///
  // This method mimics NhentaiApiClient's per-request preparation:
  // 1. Apply rate limiting delay (if configured)
  // 2. Generate and apply fresh headers to Dio instance (if configured)
  ///
  // CRITICAL: Headers are set DIRECTLY on `_dio.options.headers`, not via `Options()`,
  // to match the behavior of specialized sources like NhentaiSource.
  Future<void> _prepareRequest(
    Map<String, dynamic> rawConfig, {
    String? referer,
  }) async {
    // Step 1: Apply rate limiting delay (mimics AntiDetection.applyRandomDelay)
    if (_delayApplier != null) {
      await _delayApplier();
    }

    // Step 2: Apply anti-detection headers (mimics NhentaiApiClient behavior)
    if (_headersGenerator != null) {
      final generatedHeaders = _headersGenerator(referer: referer);
      _logger.d(
          '$_sourceId: Using dynamic headers generator (${generatedHeaders.length} headers)');

      // SET headers directly on Dio instance (not via Options)
      _dio.options.headers =
          _mergeHeaders(_dio.options.headers, generatedHeaders);
      return;
    }

    // Fallback: Use static config headers if no generator provided
    final configHeaders = _extractHeaders(rawConfig);
    if (configHeaders.isNotEmpty) {
      _logger.d(
          '$_sourceId: Using config headers (${configHeaders.length} headers)');
      _dio.options.headers = _mergeHeaders(_dio.options.headers, configHeaders);
      return;
    }

    // Priority 3: Dio defaults only (no modification needed)
    _logger.d('$_sourceId: Using Dio default headers only');
  }

  Future<T> _executeRequest<T>(Future<T> Function() request) {
    if (_rateLimiter == null) {
      return request();
    }
    return _rateLimiter.execute(request);
  }

  // Extract base URL from config for referer header.
  String? _getBaseUrl(Map<String, dynamic> rawConfig) {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    final apiUrl = (api?['url'] ?? api?['apiBase'])?.toString().trim();
    if (apiUrl != null && apiUrl.isNotEmpty) {
      return apiUrl;
    }

    final fallback = rawConfig['baseUrl']?.toString().trim();
    if (fallback == null || fallback.isEmpty) {
      return null;
    }
    return fallback;
  }

  // Resolves an avatar URL that may be:
  //  - protocol-relative  (`//i1.nhentai.net/avatars/…`)
  //  - root-relative      (`/avatars/…`)
  //  - bare relative      (`avatars/177627.png?_=…`)  ← nhentai API format
  //  - already absolute   (`https://…`)
  ///
  // [avatarBaseUrl] should be the CDN origin declared in the source config
  // as `avatarBaseUrl` (e.g. `https://i1.nhentai.net`).
  String? _resolveAvatarUrl(String? raw, String? avatarBaseUrl) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('https://') || raw.startsWith('http://')) return raw;
    if (raw.startsWith('//')) return 'https:$raw';

    final base = (avatarBaseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) {
      return base.isNotEmpty ? '$base$raw' : 'https:/$raw';
    }
    // Bare relative path (nhentai: `avatars/3407292.png?_=…`)
    return base.isNotEmpty ? '$base/$raw' : raw;
  }

  String? _extractResolvedAsset(
    dynamic data,
    Map<String, dynamic> selectors, {
    required String key,
    required Map<String, dynamic> rawConfig,
    required String hostKey,
  }) {
    final value = _extract(data, selectors, key);
    if (value == null || value.trim().isEmpty) return null;
    return _resolveConfiguredAssetUrl(value, rawConfig, hostKey: hostKey);
  }

  List<String> _extractResolvedAssetList(
    dynamic data,
    Map<String, dynamic> selectors, {
    required String key,
    required Map<String, dynamic> rawConfig,
    required String hostKey,
  }) {
    final selector = _selectorOrNull(selectors, key);
    if (selector == null) return const [];

    return _parser
        .extractList(data, selector)
        .where((value) => value.trim().isNotEmpty)
        .map((value) =>
            _resolveConfiguredAssetUrl(value, rawConfig, hostKey: hostKey))
        .toList();
  }

  String _resolveConfiguredAssetUrl(
    String rawPath,
    Map<String, dynamic> rawConfig, {
    required String hostKey,
  }) {
    if (rawPath.startsWith('https://') || rawPath.startsWith('http://')) {
      return rawPath;
    }

    final assetHosts =
        (rawConfig['assetHosts'] as Map<String, dynamic>?) ?? const {};
    final host = assetHosts[hostKey]?.toString().trim() ?? '';
    if (host.isEmpty) return rawPath;

    final normalizedHost = host.replaceAll(RegExp(r'/+$'), '');
    final normalizedPath =
        rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    return '$normalizedHost/$normalizedPath';
  }








  // Convert raw string tag names to [Tag] entities with default values.
  List<Tag> _stringsToTags(List<String> names, String type) {
    return names
        .map((name) => Tag(id: 0, name: name, type: type, count: 0))
        .toList();
  }

  // Parse full tag objects from a selector that points to an array like
  // `[{"id":1,"name":"english","type":"language","count":12345}, …]`.
  ///
  // Splits the list by `type` field so callers can populate separate
  // entity fields (artists, characters, etc.) while keeping proper
  // id/count on the pure-tag entries.
  _TagSplit _parseTagObjects(dynamic data, FieldSelector selector) {
    final objects = _parser.extractItems(data, selector);
    final tags = <Tag>[];
    final artists = <String>[];
    final characters = <String>[];
    final parodies = <String>[];
    final groups = <String>[];
    final languages = <String>[];

    for (final obj in objects) {
      final name = obj['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final type =
          obj['type']?.toString() ?? obj['namespace']?.toString() ?? 'tag';
      final id = (obj['id'] as num?)?.toInt() ?? 0;
      final count = (obj['count'] as num?)?.toInt() ?? 0;

      // Always add to tags list (preserves id/count for display).
      // Also populate the typed string lists used by metadata section.
      switch (type) {
        case 'artist':
          artists.add(name);
          tags.add(Tag(id: id, name: name, type: type, count: count));
        case 'character':
          characters.add(name);
          tags.add(Tag(id: id, name: name, type: type, count: count));
        case 'parody':
          parodies.add(name);
          tags.add(Tag(id: id, name: name, type: type, count: count));
        case 'group':
          groups.add(name);
          tags.add(Tag(id: id, name: name, type: type, count: count));
        case 'language':
          if (name != 'translated') {
            languages.add(name);
            tags.add(Tag(id: id, name: name, type: type, count: count));
          }
        default:
          // 'tag', 'category', any unknown type
          tags.add(Tag(id: id, name: name, type: type, count: count));
      }
    }

    return _TagSplit(
      tags: tags,
      artists: artists,
      characters: characters,
      parodies: parodies,
      groups: groups,
      language: languages.isNotEmpty ? languages.first : '',
    );
  }

  // Parse a date string, defaulting to epoch on failure.
  DateTime _parseDate(String? raw) {
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    // Try unix timestamp (seconds)
    final seconds = int.tryParse(raw);
    if (seconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? _extract(dynamic data, Map<String, dynamic> selectors, String key) {
    final sel = _selectorOrNull(selectors, key);
    if (sel == null) return null;
    return _parser.extractString(data, sel);
  }

  // Extract language, skipping "translated" — matches native CommentModel.fromApi logic.
  // nhentai tags often include both the real language (e.g. "chinese") AND "translated",
  // so the plain JSONPath selector may return "translated" first depending on tag order.
  // This method uses extractList and picks the first non-"translated" value.
  String _extractLanguage(
    dynamic data,
    Map<String, dynamic> selectors, {
    Map<String, dynamic>? rawConfig,
  }) {
    final sel = _selectorOrNull(selectors, 'language');
    if (sel != null) {
      final values = _parser.extractList(data, sel);
      final language =
          values.firstWhere((v) => v != 'translated', orElse: () => '');
      if (language.isNotEmpty) return language;
    }

    final tagIdLanguage =
        _extractLanguageFromTagIds(data, selectors, rawConfig: rawConfig);
    if (tagIdLanguage != null && tagIdLanguage.isNotEmpty) {
      return tagIdLanguage;
    }

    return 'unknown';
  }

  Content _applyDefaultLanguageIfMissing(
    Content content,
    Map<String, dynamic> rawConfig,
  ) {
    final language = content.language.trim().toLowerCase();
    if (language.isNotEmpty && language != 'unknown') {
      return content;
    }

    final defaultLanguage =
        (rawConfig['defaultLanguage'] as String?)?.trim().toLowerCase() ?? '';
    if (defaultLanguage.isEmpty || defaultLanguage == 'unknown') {
      return content;
    }

    return content.copyWith(language: defaultLanguage);
  }

  String? _extractLanguageFromTagIds(
    dynamic data,
    Map<String, dynamic> selectors, {
    Map<String, dynamic>? rawConfig,
  }) {
    final tagIdsSelector = _selectorOrNull(selectors, 'tagIds');
    if (tagIdsSelector == null) return null;

    final rawTagIds = _parser.extractList(data, tagIdsSelector);
    if (rawTagIds.isEmpty) return null;

    final rawLanguageTagMap =
        (rawConfig?['languageTagMap'] as Map<String, dynamic>?) ?? const {};
    if (rawLanguageTagMap.isEmpty) return null;

    final languageTagMap = <String, String>{};
    rawLanguageTagMap.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      final normalizedValue = value.toString().trim();
      if (normalizedKey.isNotEmpty && normalizedValue.isNotEmpty) {
        languageTagMap[normalizedKey] = normalizedValue;
      }
    });
    if (languageTagMap.isEmpty) return null;

    for (final tagId in rawTagIds) {
      final normalizedTagId = tagId.toString().trim();
      if (normalizedTagId.isEmpty) continue;

      final language = languageTagMap[normalizedTagId] ?? '';
      if (language.isNotEmpty && language.toLowerCase() != 'translated') {
        return language;
      }
    }

    return null;
  }

  FieldSelector? _selectorOrNull(Map<String, dynamic> selectors, String key) {
    final raw = selectors[key];
    if (raw == null) return null;
    if (raw is String) return FieldSelector(selector: raw);
    if (raw is Map<String, dynamic>) return FieldSelector.fromMap(raw);
    return null;
  }

  FieldSelector _selectorOrDefault(
      Map<String, dynamic> selectors, String key, FieldSelector fallback) {
    return _selectorOrNull(selectors, key) ?? fallback;
  }

  String _extractJsonSelector(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      final selector = value['selector'] ?? value['path'] ?? value['jsonPath'];
      return selector?.toString().trim() ?? '';
    }
    return value.toString().trim();
  }

  // Extract string value from fields map, returning null if not found or empty.
  String? _str(Map<String, dynamic> fields, String key) {
    final value = fields[key];
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
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

  void _applyConfiguredTagRelationsToFields({
    required dynamic data,
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> fields,
  }) {
    final currentTags = fields['tags'];
    final tags = <Tag>[];

    if (currentTags is List<Tag>) {
      tags.addAll(currentTags);
    } else if (currentTags is List) {
      tags.addAll(
        currentTags
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .map((name) => Tag(id: 0, name: name, type: 'tag', count: 0)),
      );
    }

    final artists = <String>[];
    final currentArtists = fields['artists'];
    if (currentArtists is List) {
      artists.addAll(
        currentArtists
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty),
      );
    }

    _applyConfiguredTagRelations(
      data: data,
      rawConfig: rawConfig,
      tags: tags,
      artistsRaw: artists,
    );

    fields['tags'] = tags;
    fields['artists'] = artists;
  }

  void _applyConfiguredTagRelations({
    required dynamic data,
    required Map<String, dynamic> rawConfig,
    required List<Tag> tags,
    required List<String> artistsRaw,
  }) {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    final detail = api?['detail'] as Map<String, dynamic>?;
    final relationConfig = detail?['tagRelations'] as Map<String, dynamic>?;
    if (relationConfig == null) return;

    final globalSourcePath = relationConfig['sourcePath'] as String?;
    final mappings = relationConfig['mappings'] as List<dynamic>?;
    if (mappings == null) return;

    for (final rawMapping in mappings.whereType<Map<String, dynamic>>()) {
      final mappingSourcePath =
          rawMapping['sourcePath'] as String? ?? globalSourcePath;
      if (mappingSourcePath == null || mappingSourcePath.isEmpty) continue;

      final relations = _parser.extractItems(
          data, FieldSelector(selector: mappingSourcePath));
      if (relations.isEmpty) continue;

      final relationType =
          (rawMapping['relationshipType'] as String? ?? '').toLowerCase();
      final tagType = (rawMapping['tagType'] as String? ?? relationType)
          .trim()
          .toLowerCase();
      final namePath =
          (rawMapping['namePath'] as String? ?? 'attributes.name').trim();
      final idPath = (rawMapping['idPath'] as String? ?? 'id').trim();
      final appendToArtists = rawMapping['appendToArtists'] == true;

      if (tagType.isEmpty) continue;

      for (final rel in relations.whereType<Map<String, dynamic>>()) {
        if (relationType.isNotEmpty) {
          final relType = (rel['type'] as String? ?? '').trim().toLowerCase();
          if (relType != relationType) continue;
        }

        final relName =
            _extractSimplePathValue(rel, namePath)?.toString().trim() ?? '';
        if (relName.isEmpty) continue;

        final relId =
            _extractSimplePathValue(rel, idPath)?.toString().trim() ?? '';
        final slug = relId.isEmpty ? null : relId;
        final numericId = int.tryParse(relId) ?? 0;

        if (appendToArtists && !artistsRaw.contains(relName)) {
          artistsRaw.add(relName);
        }

        final exists = tags.any((t) =>
            t.type.toLowerCase() == tagType &&
            t.name.toLowerCase() == relName.toLowerCase());
        if (!exists) {
          tags.add(Tag(
            id: numericId,
            name: relName,
            type: tagType,
            count: 0,
            slug: slug,
          ));
        }
      }
    }
  }

  // ── URL builder helpers ────────────────────────────────────────────────────

  // Build a cover/thumbnail URL for a list item using the `coverUrlBuilder`
  // config block. Returns null if the block is absent or required data is
  // missing.
  ///
  // Config shape:
  // ```json
  // "coverUrlBuilder": {
  //   "mediaIdSelector": "$.media_id",
  //   "coverExtSelector": "$.images.cover.t",
  //   "template": "https://t.nhentai.net/galleries/{mediaId}/cover.{ext}",
  //   "extensionMapping": { "j": "jpg", "p": "png", "g": "gif", "w": "webp" }
  // }
  // ```
  String? _buildCoverUrl(
    dynamic data,
    Map<String, dynamic> selectors,
    String? alreadyExtractedMediaId,
  ) {
    final builder = selectors.containsKey('mangaIdPath')
        ? selectors
        : selectors['coverUrlBuilder'] as Map<String, dynamic>?;
    if (builder == null) return null;

    final template = builder['template'] as String?;
    if (template == null) return null;

    if (builder.containsKey('mangaIdPath')) {
      final mangaIdSel = builder['mangaIdPath'] as String?;
      final filenameSel = builder['filenamePath'] as String?;

      final mangaId = mangaIdSel != null
          ? _parser.extractString(data, FieldSelector(selector: mangaIdSel))
          : alreadyExtractedMediaId;
      final filename = filenameSel != null
          ? _parser.extractString(data, FieldSelector(selector: filenameSel))
          : null;

      if (mangaId != null && filename != null) {
        return template
            .replaceAll('{mangaId}', mangaId)
            .replaceAll('{fileName}', filename);
      }
      return null;
    }

    // Resolve media_id
    final mediaIdSel = builder['mediaIdSelector'] as String?;
    final mediaId = alreadyExtractedMediaId ??
        (mediaIdSel != null
            ? _parser.extractString(data, FieldSelector(selector: mediaIdSel))
            : null);
    if (mediaId == null) return null;

    // Resolve extension
    final extSel = builder['coverExtSelector'] as String?;
    String ext = 'jpg'; // safe default
    if (extSel != null) {
      final extCode =
          _parser.extractString(data, FieldSelector(selector: extSel));
      if (extCode != null) {
        final mapping = (builder['extensionMapping'] as Map<String, dynamic>?)
            ?.cast<String, String>();
        ext = mapping?[extCode] ?? ext;
      }
    }

    // Smart webp handling: some CDNs (like nhentai) convert originals to webp
    // and serve them with double extension (e.g., thumb.jpg.webp)
    // If preferWebpSuffix is true, append .webp to the resolved extension
    final preferWebp = builder['preferWebpSuffix'] as bool? ?? false;
    String finalUrl =
        template.replaceAll('{mediaId}', mediaId).replaceAll('{ext}', ext);

    if (preferWebp && !finalUrl.endsWith('.webp')) {
      finalUrl = '$finalUrl.webp';
    }

    return finalUrl;
  }

  int? _extractIntByPath(
    dynamic data,
    String? path, {
    String? dynamicId,
  }) {
    final value = _extractDynamicPathValue(data, path, dynamicId: dynamicId);
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  dynamic _extractDynamicPathValue(
    dynamic data,
    String? path, {
    String? dynamicId,
  }) {
    if (path == null || path.isEmpty) return null;

    if (path.contains('{id}') && dynamicId != null) {
      final normalized = path.replaceAll('{id}', dynamicId);
      return _extractSimplePathValue(data, normalized);
    }

    return _parser.extractRaw(data, FieldSelector(selector: path));
  }

  dynamic _extractSimplePathValue(dynamic data, String path) {
    var current = data;
    final normalized = path.trim().replaceFirst(r'$.', '');
    if (normalized.isEmpty) return null;

    final keys = normalized
        .split('.')
        .map((k) => k.replaceAll("'", '').replaceAll('"', '').trim())
        .where((k) => k.isNotEmpty)
        .toList();

    for (final key in keys) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else if (current is Map) {
        current = current[key];
      } else {
        return null;
      }
    }

    return current;
  }

  String _applyLanguagePlaceholder(
    String url,
    Map<String, dynamic> rawConfig, {
    String? requestedLanguage,
  }) {
    if (!url.contains('{language}')) return url;
    final language = _resolveLanguageCode(
      requestedLanguage: requestedLanguage,
      defaultLanguage: rawConfig['defaultLanguage'] as String?,
    );
    if (language == 'all') {
      return _removeLanguagePlaceholderParam(url);
    }
    return url.replaceAll('{language}', language);
  }

  // Apply proxy URL transformation to image URLs if configured.
  ///
  // The proxy URL template should contain `{url}` placeholder which will be
  // replaced with the URL-encoded original image URL.
  ///
  // If `proxyPatterns` is specified, only URLs matching those patterns will be proxied.
  // If `proxyPatterns` is empty or not specified, all URLs will be proxied.
  ///
  // Example config:
  // ```json
  // "images": {
  //   "proxyUrl": "https://v2.doujindesu.fun/api/image-proxy?url={url}",
  //   "proxyPatterns": ["desu.photos", "cdn.doujindesu"]
  // }
  // ```
  List<String> _applyImageProxy(
    List<String> images,
    Map<String, dynamic> imagesCfg,
  ) {
    final proxyUrl = imagesCfg['proxyUrl'] as String?;
    if (proxyUrl == null || proxyUrl.isEmpty) {
      return images;
    }

    _logger.d('$_sourceId applying image proxy: $proxyUrl');

    final proxyPatterns = (imagesCfg['proxyPatterns'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return images.map((imageUrl) {
      final shouldProxy = proxyPatterns.isEmpty ||
          proxyPatterns.any((pattern) => imageUrl.contains(pattern));

      if (!shouldProxy) {
        _logger.d('$_sourceId skipping proxy for: $imageUrl');
        return imageUrl;
      }

      final encodedUrl = Uri.encodeComponent(imageUrl);
      return proxyUrl.replaceAll('{url}', encodedUrl);
    }).toList();
  }

  String _resolveLanguageCode({
    String? requestedLanguage,
    String? defaultLanguage,
  }) {
    final raw = (requestedLanguage ?? defaultLanguage ?? '').trim();

    final normalized = raw.toLowerCase().replaceAll('_', '-');
    // `global` (mixed/unverified content) means no language filter — same
    // wire semantics as `all`. Never coerced to a specific code.
    if (normalized.isEmpty || normalized == 'global') return 'all';

    if (RegExp(r'^[a-z]{2}(-[a-z0-9]+)?$').hasMatch(normalized)) {
      return normalized;
    }

    const mapping = <String, String>{
      'all': 'all',
      'all languages': 'all',
      'indonesian': 'id',
      'indonesia': 'id',
      'japanese': 'ja',
      'korean': 'ko',
      'chinese': 'zh',
      'simplified chinese': 'zh-hans',
      'traditional chinese': 'zh-hant',
      'vietnamese': 'vi',
      'thai': 'th',
      'spanish': 'es',
      'portuguese': 'pt',
      'french': 'fr',
      'german': 'de',
      'italian': 'it',
      'russian': 'ru',
      'turkish': 'tr',
      'arabic': 'ar',
      'polish': 'pl',
    };

    return mapping[normalized] ?? 'all';
  }

  Future<List<Chapter>> _fetchChapters(
    String url, {
    required String itemsSelector,
    required Map<String, dynamic> cFields,
    required Map<String, dynamic> rawConfig,
    Map<String, dynamic>? fallbackFields,
    bool autoPaginate = true,
  }) async {
    final chapters = <Chapter>[];
    var pageUrl = url;
    var guard = 0;

    while (true) {
      await _prepareRequest(rawConfig, referer: _getBaseUrl(rawConfig));
      final chapterRes =
          await _executeRequest<dynamic>(() => _dio.get<dynamic>(pageUrl));
      final cData = chapterRes.data is String
          ? jsonDecode(chapterRes.data as String)
          : chapterRes.data;

      final rawChapters =
          _parser.extractItems(cData, FieldSelector(selector: itemsSelector));
      for (final c in rawChapters) {
        final cFieldsExtracted = _extractRestFields(c, cFields);
        _applyFallbackFields(cFieldsExtracted, c, fallbackFields);
        chapters.add(GenericContentMapper.toChapter(cFieldsExtracted));
      }

      final nextUrl = autoPaginate ? _nextOffsetPageUrl(pageUrl, cData) : null;
      if (nextUrl == null) {
        break;
      }

      pageUrl = nextUrl;
      guard += 1;
      if (guard > 200) {
        _logger.w(
          '$_sourceId chapter pagination guard reached, stopping at ${chapters.length} items',
        );
        break;
      }
    }

    return chapters;
  }

  // Parse chapters inline from the detail response (no separate API call needed).
  // Used for sources like DoujinDesu v2 that include chapters in the detail response.
  ///
  // For multi-chapter works, chapter ID is formatted as: {mangaSlug}/{chapterSlug}
  // to support the API endpoint: /api/read/{id}/{chapter}
  List<Chapter>? _parseChaptersInline(
    dynamic data, {
    required String contentId,
    required String itemsSelector,
    required Map<String, dynamic> cFields,
    required Map<String, dynamic> rawConfig,
  }) {
    if (data is! Map<String, dynamic>) return null;

    final rawChapters =
        _parser.extractItems(data, FieldSelector(selector: itemsSelector));
    if (rawChapters.isEmpty) return null;

    final chapters = <Chapter>[];
    for (final c in rawChapters) {
      final cFieldsExtracted = _extractRestFields(c, cFields);

      // For multi-chapter works, prepend manga slug to chapter slug
      // Format: {mangaSlug}/{chapterSlug}
      final originalId = _str(cFieldsExtracted, 'id');
      if (originalId != null && originalId.isNotEmpty) {
        final chapterSlug = originalId;
        final mangaSlug = contentId;

        // If chapter slug is DIFFERENT from manga slug, it's a multi-chapter work
        // Format chapter ID as: {mangaSlug}/{chapterSlug}
        if (chapterSlug != mangaSlug) {
          cFieldsExtracted['id'] = '$mangaSlug/$chapterSlug';
          _logger.d(
              '$_sourceId: Multi-chapter detected, chapter ID: ${cFieldsExtracted['id']}');
        }
      }

      chapters.add(GenericContentMapper.toChapter(cFieldsExtracted));
    }

    return chapters;
  }

  List<Chapter> _composeChapterIdsWithContentId(
    List<Chapter> chapters, {
    required Map<String, dynamic> chaptersCfg,
    required String contentId,
  }) {
    final shouldCompose = chaptersCfg['composeIdWithContentId'] == true;
    if (!shouldCompose || contentId.trim().isEmpty || chapters.isEmpty) {
      return chapters;
    }

    final joiner = (chaptersCfg['idJoiner'] as String?) ?? '/';
    final composeUrl = chaptersCfg['composeUrlWithContentId'] == true;
    final normalizedContentId = contentId.trim();

    String composeToken(String raw) {
      final token = raw.trim();
      if (token.isEmpty) return token;
      if (token.startsWith('$normalizedContentId$joiner')) return token;
      return '$normalizedContentId$joiner$token';
    }

    return chapters.map((chapter) {
      final nextId = composeToken(chapter.id);
      final nextUrl = composeUrl ? composeToken(chapter.url) : chapter.url;
      return chapter.copyWith(id: nextId, url: nextUrl);
    }).toList(growable: false);
  }

  String? _nextOffsetPageUrl(String currentUrl, dynamic data) {
    if (data is! Map<String, dynamic>) return null;

    final total = (data['total'] as num?)?.toInt();
    final limit = (data['limit'] as num?)?.toInt();
    final offset = (data['offset'] as num?)?.toInt();

    if (total == null || limit == null || offset == null || limit <= 0) {
      return null;
    }

    final nextOffset = offset + limit;
    if (nextOffset >= total) return null;

    return _upsertQueryParam(currentUrl, 'offset', nextOffset.toString());
  }

  String _upsertQueryParam(String url, String key, String value) {
    final stripped = _removeQueryParam(url, key);
    final separator = stripped.contains('?') ? '&' : '?';
    return '$stripped$separator'
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}';
  }

  String _removeLanguagePlaceholderParam(String url) {
    return url
        .replaceAll(RegExp(r'([?&])[^=&]*=\{language\}(?=&|$)'), '')
        .replaceAll('?&', '?')
        .replaceAll(RegExp(r'[?&]$'), '');
  }

  String _resolveSearchSortValue(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) {
    final searchConfig =
        (rawConfig['searchConfig'] as Map<String, dynamic>?) ?? const {};
    final searchForm =
        (rawConfig['searchForm'] as Map<String, dynamic>?) ?? const {};

    final sortingConfig =
        (searchConfig['sortingConfig'] as Map<String, dynamic>?) ?? const {};

    var options =
        (sortingConfig['options'] as List<dynamic>?) ?? const <dynamic>[];

    if (options.isEmpty) {
      final params = searchForm['params'] as Map<String, dynamic>? ?? const {};
      final sortParam = params['sort'] as Map<String, dynamic>? ?? const {};
      options = (sortParam['options'] as List<dynamic>?) ?? const <dynamic>[];
    }

    final candidates = <String>{
      filter.sort.name,
      filter.sort.apiValue,
      _toKebabCase(filter.sort.name),
    }..removeWhere((value) => value.trim().isEmpty);

    for (final option in options) {
      if (option is! Map<String, dynamic>) continue;

      final value = option['value']?.toString().trim() ?? '';
      final apiValue = option['apiValue']?.toString().trim() ?? '';
      final name = option['name']?.toString().trim() ?? '';

      if (candidates.contains(value) ||
          candidates.contains(apiValue) ||
          candidates.contains(name) ||
          candidates.contains(name.toLowerCase())) {
        return value;
      }
    }

    if (_isNhentaiV2Search(rawConfig)) {
      switch (filter.sort) {
        case SortOption.newest:
          return 'date';
        case SortOption.popular:
        case SortOption.popularToday:
        case SortOption.popularWeek:
        case SortOption.popularMonth:
        case SortOption.rating:
          return filter.sort.apiValue;
      }
    }

    return '';
  }

  // Resolve [fields]`tagIds` → `language` via config `languageTagMap`.
  // Called after [_extractRestFields] for the new schema path.
  void _resolveLanguageTagMap(
    Map<String, dynamic> fields,
    Map<String, dynamic> rawConfig,
  ) {
    final rawIds = fields['tagIds'];
    if (rawIds == null) return;
    final tagMap = (rawConfig['languageTagMap'] as Map<String, dynamic>?) ?? {};
    if (tagMap.isEmpty) return;

    final ids = rawIds is List
        ? rawIds.map((e) => e.toString().trim()).where((s) => s.isNotEmpty)
        : [rawIds.toString().trim()];
    for (final id in ids) {
      final lang = tagMap[id]?.toString().trim();
      if (lang != null && lang.isNotEmpty && lang != 'translated') {
        fields['language'] = lang;
        return;
      }
    }
  }

  bool _isNhentaiV2Search(Map<String, dynamic> rawConfig) {
    final api = rawConfig['api'] as Map<String, dynamic>?;
    final apiBase = api?['apiBase']?.toString() ?? '';
    final endpoints = (api?['endpoints'] as Map<String, dynamic>?) ?? const {};
    final searchEndpoint = endpoints['search']?.toString() ?? '';

    return _sourceId == 'nhentai' &&
        (apiBase.contains('/api/v2') || searchEndpoint.contains('/api/v2/'));
  }

  String _toKebabCase(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}-${match.group(2)}',
        )
        .toLowerCase();
  }

  String _removeQueryParam(String url, String paramName) {
    final escaped = RegExp.escape(paramName);
    return url
        .replaceAll(RegExp('([?&])$escaped=[^&]*(?=&|\$)'), '')
        .replaceAll('?&', '?')
        .replaceAll(RegExp(r'[?&]$'), '');
  }

  String? _extractRawSearchParams(String query) {
    if (!query.startsWith('raw:')) return null;
    return query.substring(4);
  }

  String? _extractTagValueFromRawParams(Map<String, List<String>> rawMap) {
    const candidates = <String>[
      'tag_id',
      'tagId',
      'genreIds',
      'genre_ids',
      'genreId',
      'genre_id',
      'genre',
      'category',
      'tag',
    ];

    for (final paramName in candidates) {
      final values = rawMap[paramName] ?? const <String>[];
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }

    return null;
  }

  String _buildRawSearchUrl(
    String template,
    String rawParams,
    SearchFilter filter,
  ) {
    final page = filter.page > 0 ? filter.page : 1;
    final rawMap = _parseRawQueryParams(rawParams);
    final placeholderParams = <String, String>{
      'query': '',
      'page': page.toString(),
      'sort': '',
    };

    for (final entry in rawMap.entries) {
      final firstValue = entry.value.isEmpty ? '' : entry.value.first.trim();
      if (firstValue.isEmpty) continue;
      placeholderParams[entry.key] = firstValue;
    }

    final baseUrl = _urlBuilder.resolve(template, placeholderParams);

    if (rawParams.trim().isEmpty) {
      return baseUrl;
    }

    final templateParams = _parseUrlQueryParams(baseUrl);
    final consumedPlaceholderKeys =
        _extractPlaceholders(template).where(rawMap.containsKey).toSet();

    final merged = <String, List<String>>{};

    for (final entry in templateParams.entries) {
      final hasAnyValue =
          entry.value.any((v) => v.trim().isNotEmpty || v == '{offset}');
      if (hasAnyValue || rawMap.containsKey(entry.key)) {
        merged[entry.key] = entry.value;
      }
    }

    for (final entry in rawMap.entries) {
      if (consumedPlaceholderKeys.contains(entry.key)) continue;
      merged[entry.key] = entry.value;
    }

    return _rebuildUrlWithQueryParams(baseUrl, merged);
  }

  Set<String> _extractPlaceholders(String template) {
    return RegExp(r'\{([A-Za-z0-9_\[\].-]+)\}')
        .allMatches(template)
        .map((match) => match.group(1))
        .whereType<String>()
        .toSet();
  }

  Map<String, List<String>> _parseUrlQueryParams(String url) {
    final qIdx = url.indexOf('?');
    if (qIdx < 0 || qIdx + 1 >= url.length) {
      return {};
    }
    return _parseRawQueryParams(url.substring(qIdx + 1));
  }

  Map<String, List<String>> _parseRawQueryParams(String raw) {
    final result = <String, List<String>>{};
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) continue;
      final key = Uri.decodeQueryComponent(pair.substring(0, idx));
      final value = Uri.decodeQueryComponent(pair.substring(idx + 1));
      result.putIfAbsent(key, () => <String>[]).add(value);
    }
    return result;
  }

  String _rebuildUrlWithQueryParams(
      String baseUrl, Map<String, List<String>> p) {
    final qIdx = baseUrl.indexOf('?');
    final path = qIdx >= 0 ? baseUrl.substring(0, qIdx) : baseUrl;
    if (p.isEmpty) return path;

    final pairs = <String>[];
    for (final entry in p.entries) {
      if (entry.key == 'rawParam') {
        for (final value in entry.value) {
          pairs.add(value);
        }
        continue;
      }
      if (entry.value.isEmpty) {
        pairs.add('${entry.key}=');
        continue;
      }
      for (final value in entry.value) {
        final encodedValue = (value.startsWith('{') && value.endsWith('}'))
            ? value
            : Uri.encodeQueryComponent(value);
        pairs.add('${entry.key}=$encodedValue');
      }
    }

    return '$path?${pairs.join('&')}';
  }

  String _applyQueryRules(String url, Map<String, dynamic>? rules) {
    if (rules == null) return url;

    var normalized = url;

    final enforceMulti =
        rules['enforceMultiValueParams'] as Map<String, dynamic>?;
    if (enforceMulti != null) {
      for (final entry in enforceMulti.entries) {
        final values = _toStringList(entry.value);
        if (values.isEmpty) continue;
        normalized = _replaceMultiValueParam(
          normalized,
          paramName: entry.key,
          values: values,
        );
      }
    }

    final ensureSingle = rules['ensureParams'] as Map<String, dynamic>?;
    if (ensureSingle != null) {
      for (final entry in ensureSingle.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        normalized = _ensureQueryParam(normalized, entry.key, value);
      }
    }

    final ensureMultiIfMissing =
        rules['ensureMultiValueParamsIfMissing'] as Map<String, dynamic>?;
    if (ensureMultiIfMissing != null) {
      for (final entry in ensureMultiIfMissing.entries) {
        final values = _toStringList(entry.value);
        if (values.isEmpty) continue;
        normalized = _ensureMultiValueParamIfMissing(
          normalized,
          paramName: entry.key,
          values: values,
        );
      }
    }

    return normalized;
  }

  List<String> _toStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _replaceMultiValueParam(
    String url, {
    required String paramName,
    required List<String> values,
  }) {
    var normalized = _removeQueryParam(url, paramName);
    for (final value in values) {
      normalized = normalized.contains('?')
          ? '$normalized&$paramName=$value'
          : '$normalized?$paramName=$value';
    }
    return normalized;
  }

  String _ensureQueryParam(String url, String paramName, String value) {
    if (url.contains('$paramName=')) return url;
    return url.contains('?')
        ? '$url&$paramName=$value'
        : '$url?$paramName=$value';
  }

  String _ensureMultiValueParamIfMissing(
    String url, {
    required String paramName,
    required List<String> values,
  }) {
    if (url.contains('$paramName=')) return url;
    var normalized = url;
    for (final value in values) {
      normalized = normalized.contains('?')
          ? '$normalized&$paramName=$value'
          : '$normalized?$paramName=$value';
    }
    return normalized;
  }

  void _applyFallbackFields(
    Map<String, dynamic> extracted,
    dynamic item,
    Map<String, dynamic>? fallbackFields,
  ) {
    if (fallbackFields == null || fallbackFields.isEmpty) return;

    for (final entry in fallbackFields.entries) {
      final fieldName = entry.key;
      final selector = entry.value?.toString().trim() ?? '';
      if (selector.isEmpty) continue;

      final current = extracted[fieldName]?.toString().trim() ?? '';
      if (current.isNotEmpty) continue;

      final value = _parser.extractString(
        item,
        FieldSelector(selector: selector),
      );
      if (value != null && value.trim().isNotEmpty) {
        extracted[fieldName] = value.trim();
      }
    }
  }

  // Build the full list of image URLs for a detail response using the
  // `imageUrlBuilder` config block.
  ///
  // Config shape:
  // ```json
  // "imageUrlBuilder": {
  //   "mediaIdSelector": "$.media_id",
  //   "pageExtSelector": "$.images.pages[*].t",
  //   "template": "https://i.nhentai.net/galleries/{mediaId}/{page}.{ext}",
  //   "extensionMapping": { "j": "jpg", "p": "png", "g": "gif", "w": "webp" }
  // }
  // ```
  List<String> _buildImageUrlsFromTemplate(
    dynamic data,
    Map<String, dynamic> builder,
  ) {
    final template = builder['template'] as String?;
    if (template == null) {
      // Support per-entry paths with base URL prefix or direct entry extraction.
      // Config: `"entryPaths": "$.thumbnails.entries[*].path", "baseSelector": "$.thumbnails.base"`
      // Config: `"entriesKey": "thumbnails.entries", "pathKey": "path", "baseKey": "thumbnails.base"`
      final entryPaths = builder['entryPaths'] as String?;
      if (entryPaths != null && entryPaths.isNotEmpty) {
        final paths = _parser.extractList(
          data,
          FieldSelector(selector: entryPaths),
        );
        if (paths.isNotEmpty) {
          final baseSel = builder['baseSelector'] as String?;
          final base = baseSel != null
              ? _parser.extractString(data, FieldSelector(selector: baseSel))
              : null;
          if (base != null) {
            return paths.map((p) => '$base${p.toString()}').toList();
          }
          // Fallback: return paths as-is if no base
          return paths.map((p) => p.toString()).toList();
        }
        // Fallback: manual traversal if JSONPath fails
        try {
          if (data is Map && entryPaths.contains('[*]')) {
            final dotIdx = entryPaths.indexOf('[*]');
            final prefix = dotIdx > 0 ? entryPaths.substring(0, dotIdx) : '';
            final suffix = entryPaths.substring(dotIdx + 3);
            // Navigate JSON tree manually: prefix is "$.thumbnails.entries"
            Object? node = data;
            for (final key in prefix.split('.')) {
              final clean = key.replaceAll(r'$', '').trim();
              if (clean.isEmpty || node is! Map) continue;
              node = node[clean];
            }
            if (node is List && node.isNotEmpty) {
              final urls = <String>[];
              final baseSel = builder['baseSelector'] as String?;
              final base = baseSel != null
                  ? _parser.extractString(
                      data, FieldSelector(selector: baseSel))
                  : null;
              final pathKey = suffix.startsWith('.')
                  ? suffix.substring(1).trim()
                  : suffix.trim();
              if (pathKey.isNotEmpty) {
                for (final entry in node) {
                  if (entry is Map) {
                    final val = entry[pathKey];
                    if (val != null) {
                      urls.add(base != null ? '$base$val' : val.toString());
                    }
                  }
                }
              }
              if (urls.isNotEmpty) return urls;
            }
          }
        } catch (e) {
          _logger.w('Manual entry path traversal failed: $e');
        }
      }

      // Ultimate fallback: try data['thumbnails']['entries'] directly
      if (data is Map) {
        try {
          final tn = data['thumbnails'];
          if (tn is Map) {
            final entries = tn['entries'];
            if (entries is List && entries.isNotEmpty) {
              final tb = tn['base'] as String?;
              if (tb != null) {
                final ul = <String>[];
                for (final e in entries) {
                  if (e is Map) {
                    final p = e['path'];
                    if (p != null) ul.add('$tb$p');
                  }
                }
                if (ul.isNotEmpty) {
                  _logger.d('ultimate fallback extracted \${ul.length} URLs');
                  return ul;
                }
              }
            }
          }
        } catch (e) {
          _logger.w('Ultimate fallback failed: \$e');
        }
      }
      return const [];
    }

    // Entry-based reader image URL builder for sources like Schale Network.
    // Config:
    //   "template": "/books/data/{bookId}/{bookKey}/{pageId}/{pageKey}/1280",
    //   "entriesSelector": "$.thumbnails.entries[*]",
    //   "entryIdKey": "id", "entryKeyKey": "key",
    //   "bookIdSelector": "$.id", "bookKeySelector": "$.key",
    //   "crt": "{token}"
    final entriesSelector = builder['entriesSelector'] as String?;
    if (entriesSelector != null && entriesSelector.isNotEmpty) {
      final entries =
          _parser.extractItems(data, FieldSelector(selector: entriesSelector));
      if (entries.isNotEmpty) {
        final urls = <String>[];
        final entryIdKey = builder['entryIdKey'] as String? ?? 'id';
        final entryKeyKey = builder['entryKeyKey'] as String? ?? 'key';
        final idSel = builder['bookIdSelector'] as String?;
        final keySel = builder['bookKeySelector'] as String?;
        final bookId = idSel != null
            ? _parser.extractString(data, FieldSelector(selector: idSel))
            : null;
        final bookKey = keySel != null
            ? _parser.extractString(data, FieldSelector(selector: keySel))
            : null;
        final crt = builder['crt'] as String? ?? '';
        if (bookId != null && bookKey != null) {
          for (final entry in entries) {
            final pageId = entry[entryIdKey]?.toString() ?? '';
            final pageKey = entry[entryKeyKey]?.toString() ?? '';
            if (pageId.isEmpty || pageKey.isEmpty) continue;
            var url = template
                .replaceAll('{bookId}', bookId)
                .replaceAll('{bookKey}', bookKey)
                .replaceAll('{pageId}', pageId)
                .replaceAll('{pageKey}', pageKey)
                .replaceAll('{crt}', crt);
            urls.add(url);
          }
          if (urls.isNotEmpty) {
            _logger.d('entry-based builder extracted \${urls.length} URLs');
            return urls;
          }
        }
      }
    }

    final mediaIdSel = builder['mediaIdSelector'] as String?;
    final mediaId = mediaIdSel != null
        ? _parser.extractString(data, FieldSelector(selector: mediaIdSel))
        : null;
    if (mediaId == null) {
      _logger.w('$_sourceId: imageUrlBuilder — media_id not found');
      return const [];
    }

    final pageExtSel = builder['pageExtSelector'] as String?;
    if (pageExtSel != null && pageExtSel.isNotEmpty) {
      final extCodes = _parser.extractList(
        data,
        FieldSelector(selector: pageExtSel),
      );
      if (extCodes.isEmpty) {
        _logger.w('$_sourceId: imageUrlBuilder — no page extensions found');
        return const [];
      }

      final mapping = (builder['extensionMapping'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          const {};

      final urls = <String>[];
      for (int i = 0; i < extCodes.length; i++) {
        final extCode = extCodes[i];
        final ext = mapping[extCode] ?? 'jpg';
        final url = template
            .replaceAll('{mediaId}', mediaId)
            .replaceAll('{page}', (i + 1).toString())
            .replaceAll('{ext}', ext);
        urls.add(url);
      }
      return urls;
    }

    final pageCountSel = builder['pageCountSelector'] as String?;
    if (pageCountSel != null && pageCountSel.isNotEmpty) {
      final pageCountStr =
          _parser.extractString(data, FieldSelector(selector: pageCountSel));
      final pageCount = int.tryParse(pageCountStr ?? '');
      if (pageCount == null || pageCount <= 0) {
        _logger.w('$_sourceId: imageUrlBuilder — invalid page count');
        return const [];
      }

      final pageStart =
          int.tryParse(builder['pageStart']?.toString() ?? '') ?? 1;
      final defaultExt = builder['defaultExtension']?.toString() ?? 'jpg';

      final urls = <String>[];
      for (int i = 0; i < pageCount; i++) {
        final page = pageStart + i;
        var url = template
            .replaceAll('{mediaId}', mediaId)
            .replaceAll('{page}', page.toString());
        if (url.contains('{ext}')) {
          url = url.replaceAll('{ext}', defaultExt);
        }
        urls.add(url);
      }
      return urls;
    }

    _logger.w(
        '$_sourceId: imageUrlBuilder — neither page extensions nor page count found');
    return const [];
  }
}

// Internal DTO used by [GenericRestAdapter._parseTagObjects] to return the
// result of splitting a unified tags array by type.
class _TagSplit {
  const _TagSplit({
    required this.tags,
    required this.artists,
    required this.characters,
    required this.parodies,
    required this.groups,
    required this.language,
  });

  final List<Tag> tags;
  final List<String> artists;
  final List<String> characters;
  final List<String> parodies;
  final List<String> groups;
  final String language;
}

// Extract endpoint path from config value.
///
// Supports both old schema (string) and new schema (object with `path` +
// optional `params` map).
String _getEndpointPath(dynamic endpoint) {
  if (endpoint == null) return '';
  if (endpoint is String) return endpoint;
  if (endpoint is Map<String, dynamic>) {
    final path = endpoint['path']?.toString() ?? '';
    if (path.isEmpty) return '';

    final rawParams = endpoint['params'];
    if (rawParams is! Map) return path;

    final params = <String, String>{};
    rawParams.forEach((key, value) {
      if (key == null || value == null) return;
      final keyStr = key.toString().trim();
      final valueStr = value.toString().trim();
      if (keyStr.isEmpty || valueStr.isEmpty) return;
      params[keyStr] = valueStr;
    });

    if (params.isEmpty) return path;

    final separator = path.contains('?') ? '&' : '?';
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$path$separator$query';
  }
  return endpoint.toString();
}
