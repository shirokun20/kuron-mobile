import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' hide Comment;
import 'package:html/parser.dart' as html_parser;
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

import '../webview_proxy/webview_proxy_engine.dart';
import 'comix_cipher.dart';
import 'comix_dto.dart';

// 3-tier hybrid source adapter for comix.to (keiyoushi Comix.kt exact
// behavior, adapted to the GenericAdapter interface):
// Tier 1 — native signed API (only when the cipher was captured),
// Tier 2 — HTML scrape of `script#initial-data` queries,
// Tier 3 — per-request WebView capture.

const int _defaultPageLimit = 28;
const int _chapterPageLimit = 100;
const int _tagCacheSize = 50;
const int _officialGroupId = 10702;

class ComixAdapter implements GenericAdapter {
  ComixAdapter({
    required Dio dio,
    required WebViewProxyEngine engine,
    required Logger logger,
    this.defaultBaseUrl = 'https://comix.to',
    this.defaultSourceId = 'comix',
  })  : _dio = dio,
        _engine = engine,
        _logger = logger;

  final Dio _dio;
  final WebViewProxyEngine _engine;
  final Logger _logger;
  final String defaultBaseUrl;
  final String defaultSourceId;

  final Map<String, List<String>> _tagIdCache = {};
  final Map<int, String> _chapterPathCache = {};

  String _baseUrl(Map<String, dynamic> rawConfig) =>
      (rawConfig['baseUrl'] as String?) ?? defaultBaseUrl;

  String _sourceId(Map<String, dynamic> rawConfig) =>
      (rawConfig['source'] as String?)?.toString() ?? defaultSourceId;

  String _userAgent() =>
      _dio.options.headers['User-Agent']?.toString() ??
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  // ---------------------------------------------------------------- search

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    final params = _searchParams(filter, rawConfig);
    final url = _browseUri(base, params);
    final page = await _mangaListFromBrowse(url, rawConfig);
    return AdapterSearchResult(
      items: page.items,
      hasNextPage: page.hasNext,
      totalPages: null,
      totalItems: null,
    );
  }

  Map<String, List<String>> _searchParams(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) {
    final params = <String, List<String>>{};
    final radios = filter.radioGroupSelections;

    if (filter.query.trim().isNotEmpty) {
      params['keyword'] = [filter.query.trim()];
      params['order[relevance]'] = ['desc'];
    } else {
      switch (filter.sort) {
        case SortOption.popular:
        case SortOption.popularToday:
        case SortOption.popularWeek:
        case SortOption.popularMonth:
        case SortOption.rating:
          params['order[score]'] = ['desc'];
        case SortOption.newest:
          params['order[chapter_updated_at]'] = ['desc'];
      }
    }

    final contentRating = radios['content_rating'] ?? 'suggestive';
    for (final v in contentRating.split(',').map((e) => e.trim())) {
      if (v.isNotEmpty) {
        (params['content_rating[]'] ??= []).add(v);
      }
    }
    for (final t in radios['types']?.split(',') ?? const []) {
      final v = t.trim();
      if (v.isNotEmpty) (params['types[]'] ??= []).add(v);
    }
    for (final d in radios['demographics']?.split(',') ?? const []) {
      final v = d.trim();
      if (v.isNotEmpty) (params['demographics[]'] ??= []).add(v);
    }
    for (final tag in filter.includeTags) {
      (params['genres_in[]'] ??= []).add(tag.id.toString());
    }
    for (final tag in filter.excludeTags) {
      (params['genres_ex[]'] ??= []).add(tag.id.toString());
    }
    params['page'] = [filter.page < 1 ? '1' : '${filter.page}'];
    return params;
  }

  Uri _browseUri(String base, Map<String, List<String>> params) {
    final query = <String, String>{};
    params.forEach((key, values) {
      if (values.length == 1 && !key.endsWith('[]')) {
        query[key] = values.single;
      } else {
        for (var i = 0; i < values.length; i++) {
          query['${key.replaceAll('[]', '')}[$i]'] = values[i];
        }
      }
    });
    return Uri.parse('$base/browse').replace(queryParameters: query);
  }

  Future<({List<Content> items, bool hasNext})> _mangaListFromBrowse(
    Uri url,
    Map<String, dynamic> rawConfig,
  ) async {
    // Tier 1 — native signed API.
    final signed = await getSigned<Map<String, dynamic>>(
      '/api/v1/manga',
      _nativeMangaParams(url),
      rawConfig,
    );
    if (signed != null) {
      final response = SearchResponse.fromJson(signed);
      if (response.items.isNotEmpty) {
        return (
          items:
              response.items.map((m) => _basicContent(m, rawConfig)).toList(),
          hasNext: response.hasNext,
        );
      }
    }

    // Tier 2 — HTML scrape.
    final docResponse = await _dio.getUri(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final document = html_parser.parse(docResponse.data as String);
    final scraped = _extractBrowseResponse(document);
    if (scraped != null) {
      return (
        items: scraped.items.map((m) => _basicContent(m, rawConfig)).toList(),
        hasNext: scraped.hasNext,
      );
    }

    // Tier 3 — per-request WebView.
    final keyword =
        url.queryParameters['q'] ?? url.queryParameters['keyword'] ?? '';
    final contentRating = _effectiveContentRating(url);
    final payload = await _engine.runInWebView(
      pageUrl: url.toString(),
      html: docResponse.data as String,
      userAgent: _userAgent(),
      initializationScript: _contentFilterInit(contentRating),
      buildScript: (pass, _) => buildBrowseScript(
        passPayloadName: pass,
        expectedKeywordJson: jsonEncode(keyword),
      ),
    );
    final webResponse =
        SearchResponse.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    return (
      items: webResponse.items.map((m) => _basicContent(m, rawConfig)).toList(),
      hasNext: webResponse.hasNext,
    );
  }

  Map<String, List<String>> _nativeMangaParams(Uri url) {
    final params = <String, List<String>>{};
    url.queryParametersAll.forEach((name, values) {
      final filtered = values.where((v) => v.isNotEmpty).toList();
      if (filtered.isEmpty) return;
      params[name] = name == 'content_rating'
          ? filtered.expand((v) => v.split(',')).toList()
          : filtered;
    });
    params.putIfAbsent('limit', () => ['$_defaultPageLimit']);
    return params;
  }

  String _effectiveContentRating(Uri url) {
    final raw = url.queryParameters['content_rating'];
    final parts = (raw ?? 'pornographic').split(',');
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim().isNotEmpty) return parts[i].trim();
    }
    return 'pornographic';
  }

  String _contentFilterInit(String rating) => '''
(function () {
    const key = 'settings_v2';
    let settings = {};
    try {
        settings = JSON.parse(localStorage.getItem(key) || '{}');
    } catch (e) {}
    settings.state = {
        ...(settings.state || {}),
        contentFilter: '$rating'
    };
    if (settings.version === undefined) settings.version = 0;
    localStorage.setItem(key, JSON.stringify(settings));
})();
''';

  Map<String, dynamic> _extractInitialQueries(Document document) {
    final script = document.querySelector('script#initial-data');
    if (script == null) throw const FormatException('initial-data missing');
    final root = jsonDecode(script.text) as Map<String, dynamic>;
    final queries = root['queries'] as Map<String, dynamic>?;
    if (queries == null) throw const FormatException('queries missing');
    return queries;
  }

  SearchResponse? _extractBrowseResponse(Document document) {
    late final Map<String, dynamic> queries;
    try {
      queries = _extractInitialQueries(document);
    } catch (_) {
      return null;
    }
    for (final value in queries.values) {
      try {
        final parsed = SearchResponse.fromJson(value as Map<String, dynamic>);
        if (parsed.items.isNotEmpty) return parsed;
      } catch (_) {
        // Not a SearchResponse-shaped query — keep looking.
      }
    }
    return null;
  }

  Content _basicContent(ComixManga manga, Map<String, dynamic> rawConfig) {
    final base = _baseUrl(rawConfig);
    final sourceId = _sourceId(rawConfig);
    return Content(
      id: manga.hid,
      sourceId: sourceId,
      title: manga.title,
      coverUrl: manga.poster?.from('large') ?? '',
      tags: _contentTags(manga),
      artists: manga.artists?.map((e) => e.title).toList() ?? const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: manga.originalLanguage ?? 'unknown',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime.fromMillisecondsSinceEpoch(0),
      url: '$base/title${manga.detailPath}',
      contentType: ContentType.manga,
      status: _statusOf(manga.status),
      sourceUrl: '$base/title${manga.detailPath}',
      totalChapters: 0,
    );
  }

  List<Tag> _contentTags(ComixManga manga) {
    var id = 0;
    final tags = <Tag>[];
    void add(Iterable<Term>? terms, String type) {
      for (final t in terms ?? const <Term>[]) {
        tags.add(Tag(id: id++, name: t.title, type: type, count: 0));
      }
    }

    add(manga.genres, 'tag');
    add(manga.demographics, 'demographic');
    add(manga.tags, 'tag');
    return tags;
  }

  ContentStatus _statusOf(String status) => switch (status) {
        'releasing' => ContentStatus.ongoing,
        'on_hiatus' => ContentStatus.onHiatus,
        'finished' => ContentStatus.completed,
        'discontinued' => ContentStatus.cancelled,
        _ => ContentStatus.unknown,
      };

  // ---------------------------------------------------------------- detail

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    final slug = contentId.startsWith('title/')
        ? contentId.substring('title/'.length)
        : contentId;
    final response = await _dio.getUri(
      Uri.parse('$base/title/$slug'),
      options: Options(responseType: ResponseType.plain),
    );
    final document = html_parser.parse(response.data as String);
    final detail = _extractInitialQueries(document)
        .entries
        .where((e) => e.key.contains('"detail"'))
        .map((e) => e.value)
        .firstOrNull;
    if (detail == null) {
      throw const FormatException('Could not find manga detail in queries');
    }
    final manga = ComixManga.fromJson(detail as Map<String, dynamic>);
    final authors = manga.authors?.map((e) => e.title).toList() ?? const [];
    final artists = manga.artists?.map((e) => e.title).toList() ?? const [];
    final content = Content(
      id: manga.hid,
      sourceId: _sourceId(rawConfig),
      title: manga.title,
      coverUrl: manga.poster?.from('large') ?? '',
      tags: _contentTags(manga),
      artists: artists.isNotEmpty ? artists : authors,
      characters: const [],
      parodies: const [],
      groups: const [],
      language: manga.originalLanguage ?? 'unknown',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime.fromMillisecondsSinceEpoch(0),
      url: '$base/title${manga.detailPath}',
      englishTitle: manga.title,
      subTitle: authors.join(', '),
      contentType: ContentType.manga,
      status: _statusOf(manga.status),
      sourceUrl: '$base/title${manga.detailPath}',
      totalChapters: 0,
    );
    return AdapterDetailResult(content: content, imageUrls: const []);
  }

  /// Resolves tag names to API ids with a 50-entry LRU cache
  /// (`/api/v1/tags/search?type=&q=`).
  Future<List<String>> resolveTagIds(
      String type, String name, Map<String, dynamic> rawConfig) async {
    final key = '$type\x00${name.toLowerCase()}';
    final cached = _tagIdCache[key];
    if (cached != null) return cached;
    try {
      final response = await _dio.getUri(
        Uri.parse(
          '${_baseUrl(rawConfig)}/api/v1/tags/search',
        ).replace(queryParameters: {'type': type, 'q': name}),
      );
      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;
      final ids = TagSearchResponse.fromJson(data)
          .result
          .map((e) => e.id.toString())
          .toList();
      if (_tagIdCache.length >= _tagCacheSize) {
        _tagIdCache.remove(_tagIdCache.keys.first);
      }
      _tagIdCache[key] = ids;
      return ids;
    } catch (_) {
      return const [];
    }
  }

  // --------------------------------------------------------------- chapters

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
    final base = _baseUrl(rawConfig);
    final slug = contentId.startsWith('title/')
        ? contentId.substring('title/'.length)
        : contentId;
    final mangaId = slug.split('-').first;
    if (mangaId.isEmpty) {
      throw const FormatException('Refresh manga details');
    }

    var dtos = await _nativeChapterList(
      base: base,
      mangaSlug: slug,
      mangaId: mangaId,
    );
    dtos ??= await _webViewChapterList(
      base: base,
      mangaSlug: slug,
      mangaId: mangaId,
    );

    final chapters = _selectChapters(dtos, rawConfig)
        .map(
          (c) => Chapter(
            id: '${c.id}',
            title: c.displayName(),
            url: c.chapterPath(slug),
            uploadDate: c.uploadDate(),
            scanGroup: c.scanlator(),
            language: language,
            pages: null,
          ),
        )
        .toList();
    for (final c in dtos) {
      _chapterPathCache[c.id] = c.chapterPath(slug);
      if (_chapterPathCache.length > 500) {
        _chapterPathCache.remove(_chapterPathCache.keys.first);
      }
    }
    return chapters;
  }

  Future<List<ComixChapter>?> _nativeChapterList({
    required String base,
    required String mangaSlug,
    required String mangaId,
  }) async {
    if (!_engine.hasCipher) return null;
    final out = <ComixChapter>[];
    var page = 1;
    while (page <= maxChapterPages) {
      final json = await getSigned<Map<String, dynamic>>(
        '/api/v1/manga/$mangaId/chapters',
        {
          'limit': ['$_chapterPageLimit'],
          'order[number]': ['desc'],
          'page': ['$page'],
        },
        {'baseUrl': base},
      );
      if (json == null) return null;
      final response = ChapterDetailsResponse.fromJson(json);
      out.addAll(response.items);
      if (!response.hasNext || response.items.isEmpty) break;
      page++;
    }
    return out;
  }

  Future<List<ComixChapter>> _webViewChapterList({
    required String base,
    required String mangaSlug,
    required String mangaId,
  }) async {
    final response = await _dio.getUri(
      Uri.parse('$base/title/$mangaSlug'),
      options: Options(responseType: ResponseType.plain),
    );
    final html = response.data as String;
    final document = html_parser.parse(html);
    final mainScript = document.querySelector(
      'script[type=module][src*="/dist/main-"]',
    );
    var mainScriptUrl = '';
    if (mainScript != null) {
      final src = mainScript.attributes['src'] ?? '';
      mainScriptUrl = src.startsWith('http')
          ? src
          : '$base${src.startsWith('/') ? src : '/$src'}';
      mainScript.remove();
    }
    final payload = await _engine.runInWebView(
      pageUrl: '$base/title/$mangaSlug',
      html: document.outerHtml,
      userAgent: _userAgent(),
      buildScript: (pass, reject) => buildChapterListScript(
        passPayloadName: pass,
        rejectName: reject,
        mangaIdJson: jsonEncode(mangaId),
        mainScriptUrlJson: jsonEncode(mainScriptUrl),
        latestChapterId: null,
      ),
      extendDeadlineOnApiTraffic: true,
    );
    return ((jsonDecode(payload) as List))
        .map((e) => ComixChapter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<ComixChapter> _selectChapters(
    List<ComixChapter> all,
    Map<String, dynamic> rawConfig,
  ) {
    final seen = <String>{};
    final unique = all.where((c) => seen.add('${c.id}')).toList();
    final blacklist = ((rawConfig['scanlatorBlacklist'] as String?) ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final filtered = blacklist.isEmpty
        ? unique
        : unique.where((c) {
            final scanlator = c.scanlator().trim().toLowerCase();
            return !blacklist.contains(scanlator) &&
                !blacklist.contains('${c.groupId ?? ''}');
          }).toList();
    if ((rawConfig['deduplicateChapters'] as bool?) != true) {
      filtered.sort((a, b) => b.number.compareTo(a.number));
      return filtered;
    }
    final map = <double, ComixChapter>{};
    for (final c in filtered) {
      final current = map[c.number];
      if (current == null) {
        map[c.number] = c;
      } else if (_isBetter(c, current)) {
        map[c.number] = c;
      }
    }
    final out = map.values.toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    return out;
  }

  bool _isBetter(ComixChapter candidate, ComixChapter current) {
    if (candidate.isOfficial != current.isOfficial) {
      return candidate.isOfficial;
    }
    final candidateOfficialGroup = candidate.groupId == _officialGroupId;
    final currentOfficialGroup = current.groupId == _officialGroupId;
    if (candidateOfficialGroup != currentOfficialGroup) {
      return candidateOfficialGroup;
    }
    if (candidate.votes != current.votes) {
      return candidate.votes > current.votes;
    }
    return candidate.id > current.id;
  }

  // ----------------------------------------------------------------- reader

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    final numericId = int.tryParse(chapterId.split(':').first);
    if (numericId != null) {
      final pages = await getSigned<Map<String, dynamic>>(
        '/api/v1/chapters/$numericId',
        const {},
        rawConfig,
      );
      if (pages != null) {
        return ChapterData(
          images: buildPages(
            ChapterPagesResponse.fromJson(pages),
          ),
        );
      }
    }
    // Tier 3 fallback needs the chapter path cached from fetchChapters.
    final path = numericId == null ? null : _chapterPathCache[numericId];
    if (path == null) {
      throw const FormatException('Refresh chapter list and retry');
    }
    final response = await _dio.getUri(
      Uri.parse('$base/$path'),
      options: Options(responseType: ResponseType.plain),
    );
    final payload = await _engine.runInWebView(
      pageUrl: '$base/$path',
      html: response.data as String,
      userAgent: _userAgent(),
      buildScript: (pass, _) => buildPageListScript(passPayloadName: pass),
    );
    return ChapterData(
      images: buildPages(
        ChapterPagesResponse.fromJson(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Builds reader image URLs with V3 / legacy-scramble markers
  /// (Comix.kt `buildPages`).
  static List<String> buildPages(ChapterPagesResponse response) {
    final base = response.baseUrl.endsWith('/')
        ? response.baseUrl.substring(0, response.baseUrl.length - 1)
        : response.baseUrl;
    final out = <String>[];
    for (var index = 0; index < response.items.length; index++) {
      final dto = response.items[index];
      final full = dto.url.startsWith('http')
          ? dto.url
          : '$base/${dto.url.replaceFirst(RegExp(r'^/+'), '')}';
      final isV3 = dto.s == 1 || full.contains('?v3');
      final isLegacyScramble = !isV3 && (index + 1) % 4 == 0;
      if (isV3) {
        final uri = Uri.parse(full);
        if (uri.queryParameters.containsKey('v3')) {
          out.add(full);
        } else {
          out.add(uri.replace(
            queryParameters: {...uri.queryParameters, 'v3': ''},
          ).toString());
        }
      } else if (isLegacyScramble) {
        out.add('$full#scrambled');
      } else {
        out.add(full);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- related

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    final slug = contentId.startsWith('title/')
        ? contentId.substring('title/'.length)
        : contentId;
    try {
      final response = await _dio.getUri(
        Uri.parse('$base/title/$slug'),
        options: Options(responseType: ResponseType.plain),
      );
      final document = html_parser.parse(response.data as String);
      final related = _extractInitialQueries(document)
          .entries
          .where((e) => e.key.contains('"recommended"'))
          .map((e) => e.value)
          .firstOrNull;
      if (related == null) return const [];
      final items = (related as Map<String, dynamic>)['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items
            .map((e) => _basicContent(
                  ComixManga.fromJson(e as Map<String, dynamic>),
                  rawConfig,
                ))
            .toList();
      }
      return SearchResponse.fromJson(related)
          .items
          .map((m) => _basicContent(m, rawConfig))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async =>
      const [];

  // ----------------------------------------------------------------- signed

  /// Tier-1 signed GET. Returns null when no cipher is cached or the call
  /// fails (resets the cipher on failure, like upstream).
  Future<T?> getSigned<T>(
    String path,
    Map<String, List<String>> params,
    Map<String, dynamic> rawConfig,
  ) async {
    final cipher = _engine.cipher;
    if (cipher == null) return null;
    try {
      final entries = ComixCipher.canonicalEntries(params);
      final query = entries.map((e) => '${e.key}=${e.value.trim()}').join('&');
      final base = _baseUrl(rawConfig);
      final uri = Uri.parse('$base$path').replace(
        queryParameters: {
          for (final e in entries) e.key: e.value,
          '_': cipher.sign(path, query),
        },
      );
      final response = await _dio.getUri(uri);
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (data is Map<String, dynamic> && data.containsKey('e')) {
        final decrypted = cipher.decrypt(data['e'] as String);
        return jsonDecode(decrypted) as T;
      }
      return data as T;
    } catch (e) {
      _logger.w('comix: signed call failed, cipher reset: $e');
      _engine.resetCipher();
      return null;
    }
  }
}
