// DoujinDesu.xxx source — encrypted `_enc_resp_` API.
// Minimal: factory + time-windowed decrypt + adapter over GenericHttpSource.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

const String _appSecret = 'dfdf72051dbfdc7d76889ebd31324e74';
const String _salt =
    'doujindesu-scrapers-cannot-read-this-super-secret-salt-2026-v2';

class DoujinDesuXxxSourceFactory implements SourceFactory {
  final Dio _dio;
  final Logger _logger;

  DoujinDesuXxxSourceFactory({required Dio dio, required Logger logger})
      : _dio = dio,
        _logger = logger;

  @override
  String get sourceId => 'doujindesuxxx';

  @override
  ContentSource create(Map<String, dynamic> config) {
    final dio = Dio(_dio.options);
    try {
      dio.httpClientAdapter = _dio.httpClientAdapter;
    } catch (_) {}
    for (final i in _dio.interceptors) {
      try {
        dio.interceptors.add(i);
      } catch (_) {}
    }
    return GenericHttpSource(
      rawConfig: config,
      dio: dio,
      logger: _logger,
      adapterOverride: DoujinDesuXxxAdapter(
        dio: dio,
        sourceId: sourceId,
      ),
    );
  }
}

// Time-windowed decrypt of `_enc_resp_` payloads.
// Retries the current, previous, and next Unix-hour keys (mirrors the SPA's
// `Ln()`, tolerating clock drift). Returns `null` if none succeed.
dynamic doujinDesuDecrypt(String hex) {
  final slot = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
  for (final slotKey in [_key(slot), _key(slot - 1), _key(slot + 1)]) {
    try {
      return jsonDecode(Uri.decodeComponent(_xor(hex, slotKey)));
    } catch (_) {}
  }
  return null;
}

// 32-char printable key for a Unix-hour slot: FNV-ish hash of `salt_slot`
// seeded into an LCG (same as the SPA bundle).
String _key(int slot) {
  final seed = '${_salt}_$slot';
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = (((hash << 5) - hash + c) & 0xFFFFFFFF).toSigned(32);
  }
  var m = hash.abs() == 0 ? 123456789 : hash.abs();
  final out = StringBuffer();
  for (var i = 0; i < 32; i++) {
    m = (m * 1664525 + 1013904223) % 4294967296;
    out.writeCharCode(33 + m % 93);
  }
  return out.toString();
}

// XOR stream with feedback: hex string, cycling key char, index*13, carry(n).
String _xor(String hex, String key) {
  final bytes = <int>[];
  for (var c = 0; c + 2 <= hex.length; c += 2) {
    bytes.add(int.parse(hex.substring(c, c + 2), radix: 16));
  }
  final out = StringBuffer();
  var n = 42;
  for (var c = 0; c < bytes.length; c++) {
    final b = bytes[c];
    out.writeCharCode(
      (b ^ key.codeUnitAt(c % key.length) ^ (c * 13) ^ n) & 0xFF,
    );
    n = (n + b) & 0xFF;
  }
  return out.toString();
}

class DoujinDesuXxxAdapter implements GenericAdapter {
  final Dio _dio;
  final String _sourceId;
  final String _base;
  final Map<String, String> _headers;

  DoujinDesuXxxAdapter({
    required Dio dio,
    required String sourceId,
    String base = 'https://doujin.desu.xxx',
  })  : _dio = dio,
        _sourceId = sourceId,
        _base = base,
        _headers = {
          'x-app-secret': _appSecret,
          'Referer': '$base/',
          'Origin': base,
        };

  dynamic _decode(Response<dynamic> res) {
    var data = res.data;
    if (data is String) data = jsonDecode(data);
    if (data is Map && data['_enc_resp_'] is String) {
      final dec = doujinDesuDecrypt(data['_enc_resp_'] as String);
      if (dec == null) {
        throw StateError('$_sourceId: failed to decrypt _enc_resp_');
      }
      return dec;
    }
    return data;
  }

  Future<dynamic> _get(String path) async {
    final res = await _dio.get<dynamic>(
      path.startsWith('http') ? path : '$_base$path',
      options: Options(headers: _headers),
    );
    return _decode(res);
  }

  // Like [_get] but also reads the `x-total-count` header for pagination.
  Future<(dynamic, int?)> _getWithTotal(String path) async {
    final res = await _dio.get<dynamic>(
      path.startsWith('http') ? path : '$_base$path',
      options: Options(headers: _headers),
    );
    return (
      _decode(res),
      int.tryParse(res.headers.value('x-total-count') ?? '')
    );
  }

  Map<int, String>? _genreSlugs;

  Future<Map<int, String>> _loadGenreSlugs() async {
    if (_genreSlugs != null) return _genreSlugs!;
    final data = await _get('/api/genres?limit=1000');
    final map = <int, String>{};
    if (data is List) {
      for (final g in data.whereType<Map>()) {
        final id = int.tryParse('${g['id']}');
        final slug = g['slug']?.toString();
        if (id != null && slug != null && slug.isNotEmpty) {
          map[id] = slug;
        }
      }
    }
    _genreSlugs = map;
    return map;
  }

  /// `searchForm.dataSources` key -> `/api/taxonomy/<namespace>` segment.
  /// The site only exposes `genres`, `authors` and `groups`; characters and
  /// series have no namespace, so they fall back to free-text search.
  static const Map<String, String> taxonomyNamespaces = {
    'taxonomy_genre': 'genres',
    'taxonomy_genres': 'genres',
    'taxonomy_author': 'authors',
    'taxonomy_authors': 'authors',
    'taxonomy_group': 'groups',
    'taxonomy_groups': 'groups',
  };

  static const int _taxonomyPageSize = 30;

  // Site slugs are lowercase-dashed. The app hands over display names for
  // author/group (Content.artists is a plain string list, no slug), so the
  // incoming value is normalized here.
  static String slugifyTerm(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  // The site honors only `latest` and `popular`; every other value (rating,
  // top-rated, ...) silently falls back to `latest`.
  static String taxonomySort(SortOption? sort) =>
      (sort?.apiValue ?? '').startsWith('popular') ? 'popular' : 'latest';

  // `tagQueryMapping` mode `name` yields `<type>:<name>`; the site has no
  // taxonomy route for those types, so keep the text and search it.
  static String stripTermPrefix(String query) {
    final i = query.indexOf(':');
    if (i <= 0) return query;
    const types = {
      'artist',
      'author',
      'character',
      'group',
      'circle',
      'parody',
      'series',
      'publisher',
      'magazine'
    };
    return types.contains(query.substring(0, i).toLowerCase())
        ? query.substring(i + 1).trim()
        : query;
  }

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    // Genre navigation from a genre tag (numeric genre_id in raw params or
    // `genre:`/`tag:` prefixed slugs) resolves to the site's `genre=<slug>`.
    final q = filter.query.trim();
    var genreSlug = '';
    var textQuery = '';
    String? taxonomyNamespace;
    var taxonomySlug = '';
    var rawSort = '';

    if (includeTagsGenre(filter) != null) {
      genreSlug = includeTagsGenre(filter)!;
    } else if (q.startsWith('raw:')) {
      final params = Uri.splitQueryString(q.substring(4));
      for (final entry in taxonomyNamespaces.entries) {
        final v = params[entry.key]?.trim() ?? '';
        if (v.isNotEmpty) {
          taxonomyNamespace = entry.value;
          taxonomySlug = v;
          break;
        }
      }
      rawSort = params['sort']?.trim() ?? '';
      if (taxonomyNamespace == null) {
        for (final key in const [
          'genre_id',
          'genreId',
          'tag_id',
          'tagId',
          'genre',
          'tag'
        ]) {
          final v = params[key]?.trim() ?? '';
          if (v.isNotEmpty) {
            genreSlug = v;
            break;
          }
        }
        if (genreSlug.isEmpty) {
          for (final key in const ['search', 'q', 's']) {
            final v = params[key]?.trim() ?? '';
            if (v.isNotEmpty) {
              textQuery = v;
              break;
            }
          }
        }
      }
    } else if (q.startsWith('genre:') || q.startsWith('tag:')) {
      genreSlug = q.substring(q.indexOf(':') + 1).trim();
    } else if (q.isNotEmpty) {
      textQuery = stripTermPrefix(q);
    }

    if (genreSlug.isNotEmpty && int.tryParse(genreSlug) != null) {
      final slugs = await _loadGenreSlugs();
      genreSlug = slugs[int.parse(genreSlug)] ?? '';
    }

    // Genre/author/group browsing: /api/taxonomy/<ns>/<slug> is the site's own
    // term page. It is page-based (not offset) and returns
    // {term, mangaList, pagination{total, page, limit, totalPages}}. Filtering
    // /api/manga?genre=<slug> also works but cannot sort and has no pagination.
    if (taxonomyNamespace != null && taxonomySlug.isNotEmpty) {
      var slug = slugifyTerm(taxonomySlug);
      // Configs that pass the genre id (not the slug) still resolve here.
      if (int.tryParse(slug) != null) {
        slug = (await _loadGenreSlugs())[int.parse(slug)] ?? '';
      }
      if (slug.isEmpty) {
        return const AdapterSearchResult(items: [], hasNextPage: false);
      }
      final page = filter.page > 1 ? filter.page : 1;
      final sort = rawSort.isNotEmpty
          ? (rawSort.toLowerCase().startsWith('popular') ? 'popular' : 'latest')
          : taxonomySort(filter.sort);
      final data = await _get('/api/taxonomy/$taxonomyNamespace/'
          '${Uri.encodeComponent(slug)}?page=$page&sort=$sort&limit=$_taxonomyPageSize');
      final map = data is Map
          ? data.cast<String, dynamic>()
          : const <String, dynamic>{};
      final list = (map['mangaList'] as List?) ?? const [];
      final items = list
          .whereType<Map>()
          .map((m) => _content(m.cast<String, dynamic>()))
          .toList();
      final pagination = map['pagination'];
      final total =
          pagination is Map ? int.tryParse('${pagination['total']}') : null;
      final totalPages = pagination is Map
          ? int.tryParse('${pagination['totalPages']}')
          : null;
      return AdapterSearchResult(
        items: items,
        hasNextPage: totalPages != null ? page < totalPages : items.isNotEmpty,
        totalPages: totalPages ??
            (total != null ? (total / _taxonomyPageSize).ceil() : 1),
        totalItems: total ?? items.length,
      );
    }

    // API pagination: `offset` (0-based) + `limit`; `x-total-count` header
    // exists but the page-size heuristic below is sufficient.
    const pageSize = 30;
    final offset = (filter.page > 1 ? filter.page - 1 : 0) * pageSize;
    final query = genreSlug.isNotEmpty
        ? 'genre=${Uri.encodeQueryComponent(genreSlug)}'
        : textQuery.isNotEmpty
            ? 'search=${Uri.encodeQueryComponent(textQuery)}'
            : '';
    final path =
        '/api/manga?limit=$pageSize&offset=$offset${query.isEmpty ? '' : '&$query'}';
    final (data, total) = await _getWithTotal(path);
    final items = data is List ? data : const [];
    // ponytail: when the site omits x-total-count, fall back to the
    // page-size heuristic; switch to header-only if the API stops sending it.
    final totalItems = total ?? items.length;
    final totalPages = totalItems == 0 ? 1 : (totalItems / pageSize).ceil();
    return AdapterSearchResult(
      items: items
          .whereType<Map>()
          .map((m) => _content(m.cast<String, dynamic>()))
          .toList(),
      hasNextPage: total != null
          ? offset + items.length < totalItems
          : items.length >= pageSize,
      totalPages: totalPages,
      totalItems: totalItems,
    );
  }

  // First genre-type included tag, as a slug (name when no id is available).
  String? includeTagsGenre(SearchFilter filter) {
    for (final t in filter.includeTags) {
      if (t.type == 'genre' || t.type == 'tag') {
        final slug = t.name
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'-+'), '-');
        return slug;
      }
    }
    return null;
  }

  // Builds a Kuron Content from a decoded manga object. `slug` is the content
  // id (detail endpoint is keyed by slug).
  Content _content(Map<String, dynamic> m) {
    final chapters = (m['chapters'] as List?) ?? const [];
    final type = switch (m['type']?.toString()) {
      'manga' => ContentType.manga,
      'manhwa' => ContentType.manhwa,
      'manhua' => ContentType.manhua,
      'doujinshi' => ContentType.doujinshi,
      _ => ContentType.unknown,
    };
    final tags = <Tag>[];
    final artists = <String>[];
    final characters = <String>[];
    final parodies = <String>[];
    final groups = <String>[];
    final genresRaw = m['manga_genres'];
    if (genresRaw is List) {
      for (final g in genresRaw) {
        if (g is! Map) continue;
        final genreMap = g['genres'];
        if (genreMap is! Map) continue;
        final name = genreMap['name']?.toString() ?? '';
        if (name.isEmpty || name == 'N/A') continue;
        tags.add(Tag(
          id: int.tryParse('${g['genre_id']}') ?? 0,
          name: name,
          type: 'genre',
          count: 0,
          slug: genreMap['slug']?.toString() ?? '',
        ));
      }
    }
    // Detail responses carry `term_list` ("Name:type:slug", pipe-separated);
    // list/search responses only carry `terms` ("Name:type", comma-separated,
    // genres only — no author/group/character). Accept both so the same Content
    // shape comes out of search results and from the detail page.
    final parsedTerms = <(String, String, String)>[];
    final termList = m['term_list'];
    final terms = m['terms'];
    if (termList is String && termList.isNotEmpty) {
      for (final part in termList.split('|')) {
        final seg = part.split(':');
        if (seg.length < 2) continue;
        parsedTerms.add((
          seg[0].trim(),
          seg[1].trim(),
          seg.length > 2 ? seg[2].trim() : '',
        ));
      }
    } else if (terms is String && terms.isNotEmpty) {
      for (final part in terms.split(',')) {
        final seg = part.split(':');
        if (seg.length < 2) continue;
        parsedTerms.add((seg[0].trim(), seg[1].trim(), ''));
      }
    }
    for (final (name, type, slug) in parsedTerms) {
      if (name.isEmpty || name == 'N/A') continue;
      switch (type) {
        case 'character':
          characters.add(name);
          break;
        case 'group':
          groups.add(name);
          break;
        case 'series':
          parodies.add(name);
          break;
        case 'author':
          artists.add(name);
          break;
        default:
          if (type == 'genre' &&
              !tags.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
            tags.add(
                Tag(id: 0, name: name, type: 'genre', count: 0, slug: slug));
          }
      }
    }
    // `author`/`artist` are plain strings on the detail payload.
    for (final key in const ['author', 'artist']) {
      final name = (m[key] ?? '').toString().trim();
      if (name.isEmpty || name == 'N/A') continue;
      if (!artists.contains(name)) artists.add(name);
    }
    return Content(
      id: (m['slug'] ?? m['id'] ?? '').toString(),
      sourceId: _sourceId,
      title: (m['title'] ?? '').toString(),
      coverUrl: (m['cover_url'] ?? '').toString(),
      tags: tags,
      artists: artists,
      characters: characters,
      parodies: parodies,
      groups: groups,
      language: 'id',
      pageCount: m['chapter_count'] is int
          ? m['chapter_count'] as int
          : chapters.length,
      imageUrls: const [],
      uploadDate:
          DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime(0),
      contentType: type,
      status: m['status']?.toString() == 'completed'
          ? ContentStatus.completed
          : ContentStatus.unknown,
    );
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final data = await _get('/api/manga/$contentId');
    final map = (data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{});
    return AdapterDetailResult(content: _content(map), imageUrls: const []);
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
  }) async {
    final data = await _get('/api/manga/$contentId');
    final map = (data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{});
    final list = (map['chapters'] as List?) ?? const [];
    final mangaTitle = (map['title'] ?? '').toString();
    return list.whereType<Map>().map((c) {
      final id = (c['id'] ?? '').toString();
      final title = (c['title'] ?? '').toString();
      return Chapter(
        id: id,
        title: title.isEmpty ? mangaTitle : title,
        url: id,
        uploadDate: DateTime.tryParse((c['created_at'] ?? '').toString()),
      );
    }).toList();
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final data = await _get('/api/chapters/$chapterId');
    final map = (data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{});
    final urls = (map['content_urls'] as List?)
            ?.whereType<String>()
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    return ChapterData(
      images: urls,
      prevChapterId: map['prev_id']?.toString(),
      nextChapterId: map['next_id']?.toString(),
    );
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async =>
      const [];

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async =>
      const [];
}
