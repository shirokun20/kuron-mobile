import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' hide Comment;
import 'package:html/parser.dart' as html_parser;
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

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
    required this._dio,
    required this._engine,
    required this._logger,
    this.defaultBaseUrl = 'https://comix.to',
    this.defaultSourceId = 'comix',
    this.originKind = 'comix',
    this.configuredDetailTimeoutSeconds,
  });

  /// Mangafire boots a full SPA per detail fetch; comix usually answers
  /// from Tier-1/2 in seconds. Both stay under the 120s WebView deadline.
  @override
  Duration get detailTimeout => Duration(
        seconds: configuredDetailTimeoutSeconds ??
            (isMangafire ? 150 : 45),
      );

  final int? configuredDetailTimeoutSeconds;
  final Dio _dio;
  final WebViewProxyEngine _engine;
  final Logger _logger;
  final String defaultBaseUrl;
  final String defaultSourceId;

  /// Origin behavior: 'comix' (signed API + SSR scrape + WebView) or
  /// 'mangafire' (React SPA shell everywhere — Tier-3 WebView only; the
  /// SPA issues its own VRF-signed requests, Dart captures).
  final String originKind;

  bool get isMangafire => originKind == 'mangafire';

  final Map<String, List<String>> _tagIdCache = {};
  final Map<int, String> _chapterPathCache = {};

  /// Hid -> canonical title slug (e.g. `dwzjk-mediocre-mage-...`).
  /// Comix chapter URLs 404 without the full slug suffix.
  final Map<String, String> _canonicalSlugCache = {};

  void _cacheCanonicalSlug(String hid, String detailPathOrUrl) {
    if (hid.isEmpty || detailPathOrUrl.isEmpty) return;
    var slug = detailPathOrUrl;
    final titleIdx = slug.indexOf('/title/');
    if (titleIdx != -1) {
      slug = slug.substring(titleIdx + '/title/'.length);
    } else if (slug.startsWith('title/')) {
      slug = slug.substring('title/'.length);
    } else if (slug.startsWith('/')) {
      slug = slug.substring(1);
    }
    if (slug.isEmpty) return;
    _canonicalSlugCache[hid] = slug;
    if (_canonicalSlugCache.length > 500) {
      _canonicalSlugCache.remove(_canonicalSlugCache.keys.first);
    }
  }

  String _resolveCanonicalSlug(String contentId) {
    final slug = contentId.startsWith('title/')
        ? contentId.substring('title/'.length)
        : contentId;
    final hid = slug.split('-').first;
    return _canonicalSlugCache[hid] ?? slug;
  }

  static Map<String, String> _resolveGenreMapping(
    Map<String, dynamic> rawConfig,
  ) {
    final configured = (rawConfig['genreMapping'] as Map<String, dynamic>?) ??
        ((rawConfig['navigation'] as Map<String, dynamic>?)?['genreMapping']
            as Map<String, dynamic>?);
    if (configured != null && configured.isNotEmpty) {
      return configured.map((k, v) => MapEntry(k.toLowerCase(), v.toString()));
    }
    return _mangafireGenreNameToId;
  }

  static String? _resolveInitializationScript(
    Map<String, dynamic> rawConfig, {
    required bool isMangafire,
  }) {
    final network = rawConfig['network'] as Map<String, dynamic>?;
    final webView = rawConfig['webView'] as Map<String, dynamic>?;
    final script = (webView?['initializationScript'] as String?) ??
        (network?['initializationScript'] as String?) ??
        ((network?['webView'] as Map<String, dynamic>?)?['initializationScript']
            as String?);
    if (script != null && script.trim().isNotEmpty) {
      return script;
    }
    return isMangafire ? _mangafireContentFilterInit() : null;
  }

  static List<String>? _resolveAllowedHosts(Map<String, dynamic> rawConfig) {
    final network = rawConfig['network'] as Map<String, dynamic>?;
    final webView = rawConfig['webView'] as Map<String, dynamic>?;
    final hosts = (webView?['allowedHosts'] as List?) ??
        (network?['allowedHosts'] as List?) ??
        ((network?['webView'] as Map<String, dynamic>?)?['allowedHosts']
            as List?);
    return hosts?.map((e) => e.toString()).toList();
  }

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
    final params = await _searchParams(filter, rawConfig);
    final url = isMangafire
        ? _mangafireListUri(base, filter, rawConfig)
        : _browseUri(base, params);
    final page = await _mangaListFromBrowse(url, rawConfig);
    return AdapterSearchResult(
      items: page.items,
      hasNextPage: page.hasNext,
      totalPages: page.totalPages,
      totalItems: page.totalItems,
    );
  }

  /// Parses `type:name` queries produced by detail tag taps
  /// (navigation.tagQueryMapping mode=name, e.g. `tag:Romance`).
  /// Only recognized tag kinds parse — anything else (notably the `raw:`
  /// prefix produced by DynamicFormSearchUI / DetailTagQueryResolver)
  /// is NOT a type query and must fall through to keyword handling.
  static const _validTagTypes = {
    'tag',
    'genre',
    'author',
    'artist',
    'demographic',
  };

  static ({String type, String name})? _parseTypeQuery(String query) {
    final idx = query.indexOf(':');
    if (idx <= 0) return null;
    final type = query.substring(0, idx).trim().toLowerCase();
    final name = query.substring(idx + 1).trim();
    if (!_validTagTypes.contains(type) || name.isEmpty) return null;
    return (type: type, name: name);
  }

  /// API id-list param for a tag kind (keiyoushi Filters.kt mapping).
  static String _idsParam(String type) => switch (type) {
    'artist' => 'artists[]',
    'author' => 'authors[]',
    _ => 'genres_in[]',
  };

  /// tags/search API type for a tag kind.
  static String _resolveKind(String type) => switch (type) {
    'artist' => 'artist',
    'author' => 'author',
    _ => 'tag',
  };

  Future<Map<String, List<String>>> _searchParams(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    final params = <String, List<String>>{};
    final radios = filter.radioGroupSelections;

    var queryText = filter.query.trim();
    var sortFromRaw = false;

    void addRawParam(String rawKey, String rawValue) {
      final key = rawKey.trim();
      final value = rawValue.trim();
      if (key.isEmpty || value.isEmpty) return;
      if (key == 'sort') {
        final colon = value.indexOf(':');
        if (colon > 0 && colon < value.length - 1) {
          final field = value.substring(0, colon).trim();
          final direction = value.substring(colon + 1).trim();
          if (field.isNotEmpty && direction.isNotEmpty) {
            params['order[$field]'] = [direction];
            sortFromRaw = true;
          }
        }
        return;
      }
      if (key == 'keyword' || key == 'q') {
        queryText = value;
        return;
      }
      final values = value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (values.isEmpty) return;
      (params[key] ??= []).addAll(values);
    }

    if (queryText.startsWith('raw:')) {
      final rawPart = queryText.substring('raw:'.length);
      queryText = '';
      final parsed = Uri(query: rawPart).queryParametersAll;
      parsed.forEach((k, values) {
        for (final v in values) {
          if (k == 'rawParam') {
            final eqIdx = v.indexOf('=');
            if (eqIdx > 0) {
              addRawParam(v.substring(0, eqIdx), v.substring(eqIdx + 1));
            } else {
              addRawParam(v, '');
            }
          } else {
            addRawParam(k, v);
          }
        }
      });
    }

    final searchConfig = rawConfig['searchConfig'] as Map<String, dynamic>?;
    final sortValues = searchConfig?['sortValues'] as Map<String, dynamic>?;
    final defaultParams =
        searchConfig?['defaultParams'] as Map<String, dynamic>?;

    final typed = queryText.isEmpty ? null : _parseTypeQuery(queryText);
    if (typed != null) {
      if (isMangafire) {
        // MangaFire exposes no tags/search API — never resolve ids here.
        // The SPA route carries the tag itself (see _mangafireListUri).
        params['keyword'] = [typed.name];
        if (!sortFromRaw) {
          final keywordSort =
              (searchConfig?['keywordSort'] as String?) ?? 'relevance:desc';
          final colon = keywordSort.indexOf(':');
          if (colon > 0 && colon < keywordSort.length - 1) {
            params['order[${keywordSort.substring(0, colon)}]'] = [
              keywordSort.substring(colon + 1),
            ];
          } else {
            params['order[relevance]'] = ['desc'];
          }
        }
      } else {
        // Tag tap: resolve the name to API ids instead of title keyword.
        final ids = await resolveTagIds(
          _resolveKind(typed.type),
          typed.name,
          rawConfig,
        );
        if (ids.isNotEmpty) {
          params[_idsParam(typed.type)] = ids;
        } else {
          params['keyword'] = [typed.name];
          if (!sortFromRaw) {
            params['order[relevance]'] = ['desc'];
          }
        }
      }
    } else if (queryText.isNotEmpty) {
      params['keyword'] = [queryText];
      if (!sortFromRaw) {
        final keywordSort =
            (searchConfig?['keywordSort'] as String?) ?? 'relevance:desc';
        final colon = keywordSort.indexOf(':');
        if (colon > 0 && colon < keywordSort.length - 1) {
          params['order[${keywordSort.substring(0, colon)}]'] = [
            keywordSort.substring(colon + 1),
          ];
        } else {
          params['order[relevance]'] = ['desc'];
        }
      }
    } else {
      if (!sortFromRaw) {
        final mappedSort = sortValues?[filter.sort.name]?.toString();
        if (mappedSort != null && mappedSort.isNotEmpty) {
          final colon = mappedSort.indexOf(':');
          if (colon > 0 && colon < mappedSort.length - 1) {
            params['order[${mappedSort.substring(0, colon)}]'] = [
              mappedSort.substring(colon + 1),
            ];
          }
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
      }
    }

    // The API matches content_rating as an exact set, not a ceiling:
    // suggestive-only hides safe/erotica/pornographic results (proven
    // live: 1 vs 4 items for the same genre). Default to all ratings
    // when the UI specifies none; explicit radio choices still win.
    if (!params.containsKey('content_rating[]') &&
        !params.containsKey('content_rating')) {
      final defaultRatingFromConfig =
          defaultParams?['content_rating[]']?.toString() ??
              defaultParams?['content_rating']?.toString();
      final contentRating = radios['content_rating'] ??
          defaultRatingFromConfig ??
          'safe,suggestive,erotica,pornographic';
      for (final v in contentRating.split(',').map((e) => e.trim())) {
        if (v.isNotEmpty) {
          (params['content_rating[]'] ??= []).add(v);
        }
      }
    }
    if (!params.containsKey('types[]')) {
      for (final t in radios['types']?.split(',') ?? const []) {
        final v = t.trim();
        if (v.isNotEmpty) (params['types[]'] ??= []).add(v);
      }
    }
    if (!params.containsKey('demographics[]')) {
      for (final d in radios['demographics']?.split(',') ?? const []) {
        final v = d.trim();
        if (v.isNotEmpty) (params['demographics[]'] ??= []).add(v);
      }
    }
    // App-side FilterItems carry id=0 (no stored ids) — resolve by name.
    // MangaFire has no tags/search API, so skip resolution there entirely.
    for (final tag in filter.includeTags) {
      if (isMangafire) break;
      final ids = await resolveTagIds(
        _resolveKind(tag.type),
        tag.name,
        rawConfig,
      );
      if (ids.isNotEmpty) {
        (params[_idsParam(tag.type)] ??= []).addAll(ids);
      }
    }
    for (final tag in filter.excludeTags) {
      if (isMangafire) break;
      final ids = await resolveTagIds(
        _resolveKind(tag.type),
        tag.name,
        rawConfig,
      );
      if (ids.isNotEmpty) {
        (params['genres_ex[]'] ??= []).addAll(ids);
      }
    }
    params['page'] = [filter.page < 1 ? '1' : '${filter.page}'];
    return params;
  }

  Uri _browseUri(String base, Map<String, List<String>> params) {
    final query = <String, dynamic>{};
    params.forEach((key, values) {
      if (values.isEmpty) return;
      if (key == 'keyword') {
        query['q'] = values.last;
        return;
      }
      final orderMatch = RegExp(r'^order\[([^\]]+)\]$').firstMatch(key);
      if (orderMatch != null) {
        final field = orderMatch.group(1);
        final direction = values.last;
        if (field != null && field.isNotEmpty) {
          query['sort'] = '$field:$direction';
        }
        return;
      }
      if (values.length == 1 && !key.endsWith('[]')) {
        query[key] = values.single;
      } else {
        query[key.endsWith('[]') ? key : '$key[]'] = values;
      }
    });
    return Uri.parse('$base/browse').replace(queryParameters: query);
  }

  static const _mangafireGenreNameToId = <String, String>{
    'action': '1',
    'adult': '268929',
    'adventure': '78',
    'avant garde': '3',
    'boys love': '4',
    'comedy': '5',
    'crime': '268921',
    'demons': '77',
    'drama': '6',
    'ecchi': '7',
    'fantasy': '79',
    'girls love': '9',
    'gourmet': '10',
    'harem': '11',
    'hentai': '268930',
    'historical': '268922',
    'horror': '530',
    'isekai': '13',
    'iyashikei': '531',
    'josei': '15',
    'kids': '532',
    'magic': '539',
    'magical girls': '268923',
    'mahou shoujo': '533',
    'martial arts': '534',
    'mature': '268931',
    'mecha': '19',
    'medical': '268924',
    'military': '535',
    'music': '21',
    'mystery': '22',
    'parody': '23',
    'philosophical': '268925',
    'psychological': '536',
    'reverse harem': '25',
    'romance': '26',
    'school': '73',
    'sci-fi': '28',
    'seinen': '537',
    'shoujo': '30',
    'shounen': '31',
    'slice of life': '538',
    'smut': '268932',
    'space': '33',
    'sports': '34',
    'super power': '75',
    'superhero': '268926',
    'supernatural': '76',
    'suspense': '37',
    'thriller': '38',
    'tragedy': '268927',
    'vampire': '39',
    'wuxia': '268928',
  };

  /// MangaFire list route: `/browse` with keyword and page query parameters.
  /// The SPA boots on any route and issues its own `/api/titles` calls.
  /// MangaFire expects clean query parameters (no bracketed `order[...]`, no
  /// `rawParam` key). `raw:` queries produced by DynamicFormSearchUI /
  /// DetailTagQueryResolver are unpacked and normalized.
  Uri _mangafireListUri(
    String base,
    SearchFilter filter, [
    Map<String, dynamic>? rawConfig,
  ]) {
    final query = filter.query.trim();
    final page = filter.page;
    final params = <String, List<String>>{};
    final genreMap = rawConfig != null
        ? _resolveGenreMapping(rawConfig)
        : _mangafireGenreNameToId;
    final searchConfig = rawConfig?['searchConfig'] as Map<String, dynamic>?;
    final sortValues = searchConfig?['sortValues'] as Map<String, dynamic>?;
    final defaultParams =
        searchConfig?['defaultParams'] as Map<String, dynamic>?;
    String? explicitSort;

    void setSort(String sortValue) {
      final v = sortValue.trim();
      if (v.isNotEmpty) explicitSort = v;
    }

    void addParam(String rawKey, String rawValue) {
      final key = rawKey.trim();
      final val = rawValue.trim();
      if (key.isEmpty || val.isEmpty) return;

      // rawParam must never leak; caller should unwrap, but guard here too.
      if (key == 'rawParam') {
        final eqIdx = val.indexOf('=');
        if (eqIdx > 0) {
          addParam(val.substring(0, eqIdx), val.substring(eqIdx + 1));
        }
        return;
      }

      // sort=field:direction
      if (key == 'sort') {
        setSort(val);
        return;
      }

      // order[field]=direction -> sort=field:direction
      final orderMatch = RegExp(r'^order\[([^\]]+)\]$').firstMatch(key);
      if (orderMatch != null) {
        final field = orderMatch.group(1)?.trim() ?? '';
        if (field.isNotEmpty) {
          setSort('$field:$val');
        }
        return;
      }

      // keyword/q aliases
      if (key == 'keyword' || key == 'q') {
        (params['keyword'] ??= []).addAll(
          val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
        return;
      }

      // Strip trailing [] for MangaFire (e.g. genres_in[], content_rating[])
      var cleanKey = key;
      if (cleanKey.endsWith('[]')) {
        cleanKey = cleanKey.substring(0, cleanKey.length - 2);
      }
      if (cleanKey.isEmpty) return;
      (params[cleanKey] ??= []).addAll(
        val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }

    if (query.startsWith('raw:')) {
      final rawPart = query.substring('raw:'.length);
      final parsed = Uri(query: rawPart).queryParametersAll;
      parsed.forEach((k, values) {
        for (final v in values) {
          if (k == 'rawParam') {
            final eqIdx = v.indexOf('=');
            if (eqIdx > 0) {
              addParam(v.substring(0, eqIdx), v.substring(eqIdx + 1));
            }
            // malformed rawParam with no '=' is dropped
          } else {
            addParam(k, v);
          }
        }
      });
    } else if (query.isNotEmpty) {
      final typed = _parseTypeQuery(query);
      if (typed != null) {
        final normalizedName =
            typed.name.toLowerCase().replaceAll('-', ' ').trim();
        final genreId = genreMap[normalizedName];
        if (genreId != null) {
          addParam('genres_in', genreId);
        } else if (typed.type == 'author') {
          addParam('authors', typed.name);
        } else if (typed.type == 'artist') {
          addParam('artists', typed.name);
        } else {
          addParam('keyword', typed.name);
        }
      } else {
        final normalizedQuery =
            query.toLowerCase().replaceAll('-', ' ').trim();
        final genreId = genreMap[normalizedQuery];
        if (genreId != null) {
          addParam('genres_in', genreId);
        } else {
          addParam('keyword', query);
        }
      }
    }

    if (!params.containsKey('keyword') &&
        !params.containsKey('genres_in') &&
        !params.containsKey('authors') &&
        !params.containsKey('artists') &&
        filter.includeTags.isNotEmpty) {
      for (final firstTag in filter.includeTags) {
        if (firstTag.id > 0) {
          addParam('genres_in', '${firstTag.id}');
          break;
        } else {
          final normalizedTagName =
              firstTag.name.toLowerCase().replaceAll('-', ' ').trim();
          final genreId = genreMap[normalizedTagName];
          if (genreId != null) {
            addParam('genres_in', genreId);
            break;
          } else if (firstTag.type == 'author') {
            addParam('authors', firstTag.name);
            break;
          } else if (firstTag.type == 'artist') {
            addParam('artists', firstTag.name);
            break;
          } else {
            addParam('keyword', firstTag.name);
            break;
          }
        }
      }
    }

    final hasKeyword = (params['keyword'] ?? const []).isNotEmpty;
    if (explicitSort == null) {
      if (hasKeyword) {
        explicitSort =
            (searchConfig?['keywordSort'] as String?) ?? 'relevance:desc';
      } else {
        final mappedSort = sortValues?[filter.sort.name]?.toString();
        if (mappedSort != null && mappedSort.isNotEmpty) {
          explicitSort = mappedSort;
        } else {
          switch (filter.sort) {
            case SortOption.popular:
            case SortOption.popularToday:
            case SortOption.popularWeek:
            case SortOption.popularMonth:
            case SortOption.rating:
              explicitSort = 'views_total:desc';
            case SortOption.newest:
              explicitSort = 'chapter_updated_at:desc';
          }
        }
      }
    }
    if (explicitSort != null && explicitSort!.isNotEmpty) {
      params['sort'] = [explicitSort!];
    }

    // Default parameters from config or MangaFire defaults
    if (defaultParams != null && defaultParams.isNotEmpty) {
      defaultParams.forEach((k, v) {
        if (!params.containsKey(k)) {
          params[k] = [v.toString()];
        }
      });
    } else if (!params.containsKey('content_rating')) {
      params['content_rating'] = ['none'];
    }

    if (page > 1) {
      params['page'] = ['$page'];
    }

    final queryMap = <String, String>{};
    params.forEach((key, list) {
      // Never emit rawParam or bracketed order[...] keys.
      if (key == 'rawParam' || key.startsWith('order[')) return;
      final unique = list.toSet().toList();
      if (unique.isNotEmpty) {
        queryMap[key] = unique.join(',');
      }
    });

    return Uri.parse('$base/browse')
        .replace(queryParameters: queryMap.isEmpty ? null : queryMap);
  }

  /// Seeds MangaFire content preferences in localStorage before the SPA bundle boots.
  /// Unblocks ecchi/erotica/adult content ratings and clears blocked genres so titles
  /// like "The Honor Student's Secret Job" are not hidden by the SPA's default filters.
  static String _mangafireContentFilterInit() => '''
(function () {
    try {
        const key = 'mf_content_prefs';
        const prefs = {
            allowedTypes: null,
            allowedContentRatings: null,
            allowedDemographics: null,
            blockedGenres: [],
            blockedThemes: []
        };
        localStorage.setItem(key, JSON.stringify(prefs));
    } catch (e) {}
})();
''';

  /// Mangafire Tier-3 only: no cipher exists for the VRF API and the shell
  /// has no SSR blob, so boot the SPA and capture `/api/titles` traffic.
  /// Envelope is top-level `{items, meta}` (live `$.items[*]` selector).
  Future<
    ({List<Content> items, bool hasNext, int? totalItems, int? totalPages})
  >
  _mangafireListFromWebView(Uri url, Map<String, dynamic> rawConfig) async {
    final docResponse = await _dio.getUri(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final filterMarker = url.queryParameters['genres_in'] ??
        url.queryParameters['keyword'] ??
        url.queryParameters['authors'] ??
        url.queryParameters['artists'] ??
        (url.pathSegments.length > 1 &&
                url.pathSegments[url.pathSegments.length - 2] == 'search'
            ? url.pathSegments.last
            : '');
    final apiEndpoint =
        (rawConfig['api'] as Map<String, dynamic>?)?['endpoints'] != null
            ? ((rawConfig['api'] as Map<String, dynamic>)['endpoints']
                    as Map<String, dynamic>)['allGalleries']
                ?.toString()
                .split('?')
                .first
            : null;
    final payload = await _engine.runInWebView(
      pageUrl: url.toString(),
      html: docResponse.data as String,
      userAgent: _userAgent(),
      initializationScript: _resolveInitializationScript(
        rawConfig,
        isMangafire: isMangafire,
      ),
      extraAllowedHosts: _resolveAllowedHosts(rawConfig),
      buildScript: (pass, _) => buildBrowseScript(
        passPayloadName: pass,
        expectedKeywordJson: jsonEncode(filterMarker),
        apiPathMarker: apiEndpoint ?? '/api/titles',
      ),
    );
    final decoded = jsonDecode(payload);
    final map = decoded is Map<String, dynamic> ? decoded : {'result': decoded};
    final response = SearchResponse.fromJson(map);
    return (
      items: response.items.map((m) => _basicContent(m, rawConfig)).toList(),
      hasNext: response.hasNext,
      totalItems: response.totalItems,
      totalPages: response.totalPages,
    );
  }

  Future<
    ({List<Content> items, bool hasNext, int? totalItems, int? totalPages})
  >
  _mangaListFromBrowse(Uri url, Map<String, dynamic> rawConfig) async {
    if (isMangafire) {
      return _mangafireListFromWebView(url, rawConfig);
    }
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
          items: response.items
              .map((m) => _basicContent(m, rawConfig))
              .toList(),
          hasNext: response.hasNext,
          totalItems: response.totalItems,
          totalPages: response.totalPages,
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
        totalItems: scraped.totalItems,
        totalPages: scraped.totalPages,
      );
    }

    // Tier 3 — per-request WebView.
    final genreMarker = url.queryParametersAll.entries
        .where((e) => e.key.startsWith('genres_in'))
        .expand((e) => e.value)
        .firstOrNull;
    final keyword = url.queryParameters['q'] ??
        url.queryParameters['keyword'] ??
        genreMarker ??
        '';
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
    final webResponse = SearchResponse.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    return (
      items: webResponse.items.map((m) => _basicContent(m, rawConfig)).toList(),
      hasNext: webResponse.hasNext,
      totalItems: webResponse.totalItems,
      totalPages: webResponse.totalPages,
    );
  }

  Map<String, List<String>> _nativeMangaParams(Uri url) {
    final params = <String, List<String>>{};
    url.queryParametersAll.forEach((name, values) {
      final filtered = values.where((v) => v.isNotEmpty).toList();
      if (filtered.isEmpty) return;
      if (name == 'q') {
        params['keyword'] = [filtered.last];
        return;
      }
      if (name == 'sort') {
        final sort = filtered.last;
        final colon = sort.indexOf(':');
        if (colon > 0 && colon < sort.length - 1) {
          final field = sort.substring(0, colon).trim();
          final direction = sort.substring(colon + 1).trim();
          if (field.isNotEmpty && direction.isNotEmpty) {
            params['order[$field]'] = [direction];
          }
        }
        return;
      }
      final cleanName = name.replaceAll(RegExp(r'\[\d*\]'), '[]');
      params[cleanName] =
          cleanName == 'content_rating' || cleanName == 'content_rating[]'
              ? filtered.expand((v) => v.split(',')).toList()
              : filtered;
    });
    params.putIfAbsent('limit', () => ['$_defaultPageLimit']);
    return params;
  }

  @visibleForTesting
  Map<String, List<String>> nativeMangaParamsForTest(Uri url) =>
      _nativeMangaParams(url);

  String _effectiveContentRating(Uri url) {
    final raw = url.queryParameters['content_rating'];
    final parts = (raw ?? 'pornographic').split(',');
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim().isNotEmpty) return parts[i].trim();
    }
    return 'pornographic';
  }

  String _contentFilterInit(String rating) =>
      '''
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
    // Prefer explicit browse/search/list queries over the shell's
    // home/trending queries (which also decode as SearchResponse-shaped).
    // If no browse-shaped query is present, avoid home-like queries and
    // fall through to Tier 3 (WebView) when only shell sections remain.
    final entries = queries.entries.toList();
    final preferred = entries.where((e) {
      final key = e.key.toLowerCase();
      return key.contains('browse') ||
          key.contains('search') ||
          key.contains('"list"') ||
          key.contains('keyword');
    }).toList();
    final fallback = entries.where((e) {
      final key = e.key.toLowerCase();
      const homeMarkers = [
        'home',
        'trending',
        'featured',
        'spotlight',
        'banner',
        'recommend',
        'popular',
        'latest_update',
      ];
      return !homeMarkers.any(key.contains);
    }).toList();
    for (final group in [preferred, fallback]) {
      for (final entry in group) {
        try {
          final parsed = SearchResponse.fromJson(
            entry.value as Map<String, dynamic>,
          );
          if (parsed.items.isNotEmpty) return parsed;
        } catch (_) {
          // Not a SearchResponse-shaped query — keep looking.
        }
      }
      // If we had preferred keys but none yielded results, do not fall
      // back to generic/home-adjacent queries — let Tier 3 handle it.
      if (group == preferred && preferred.isNotEmpty) return null;
    }
    return null;
  }

  static String absolutizeUrl(String? url, String base) =>
      _absolutizeUrl(url, base);

  static String _absolutizeUrl(String? url, String base) {
    if (url == null) return '';
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    final cleanBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$cleanBase$cleanPath';
  }

  Content _basicContent(ComixManga manga, Map<String, dynamic> rawConfig) {
    final base = _baseUrl(rawConfig);
    final sourceId = _sourceId(rawConfig);
    return Content(
      id: manga.hid,
      sourceId: sourceId,
      title: manga.title,
      coverUrl: _absolutizeUrl(manga.poster?.from('large'), base),
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
    if (isMangafire) {
      return _mangafireDetail(contentId, rawConfig);
    }
    final base = _baseUrl(rawConfig);
    final slug = contentId.startsWith('title/')
        ? contentId.substring('title/'.length)
        : contentId;
    final response = await _dio.getUri(
      Uri.parse('$base/title/$slug'),
      options: Options(responseType: ResponseType.plain),
    );
    final document = html_parser.parse(response.data as String);
    final detail = _extractInitialQueries(document).entries
        .where((e) => e.key.contains('"detail"'))
        .map((e) => e.value)
        .firstOrNull;
    if (detail == null) {
      throw const FormatException('Could not find manga detail in queries');
    }
    final manga = ComixManga.fromJson(detail as Map<String, dynamic>);
    _cacheCanonicalSlug(manga.hid, manga.url ?? manga.detailPath);
    final authors = manga.authors?.map((e) => e.title).toList() ?? const [];
    final artists = manga.artists?.map((e) => e.title).toList() ?? const [];
    final content = Content(
      id: manga.hid,
      sourceId: _sourceId(rawConfig),
      title: manga.title,
      coverUrl: _absolutizeUrl(manga.poster?.from('large'), base),
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

  /// Mangafire detail: boot the SPA on `/manga/{slug}` and capture the
  /// `/api/titles/{hid}` response the page fetches itself (VRF-signed by
  /// page JS — Dart captures only). Field mapping mirrors the live
  /// `mangafire-config.json` detail selectors.
  Future<AdapterDetailResult> _mangafireDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    var slug = contentId.startsWith('manga/')
        ? contentId.substring('manga/'.length)
        : contentId;
    slug = slug.startsWith('title/') ? slug.substring('title/'.length) : slug;
    final pageUrl = '$base/title/$slug';
    final docResponse = await _dio.getUri(
      Uri.parse(pageUrl),
      options: Options(responseType: ResponseType.plain),
    );
    final apiEndpoint =
        (rawConfig['api'] as Map<String, dynamic>?)?['endpoints'] != null
            ? ((rawConfig['api'] as Map<String, dynamic>)['endpoints']
                    as Map<String, dynamic>)['detail']
                ?.toString()
                .split('{id}')
                .first
            : null;
    final payload = await _engine.runInWebView(
      pageUrl: pageUrl,
      html: docResponse.data as String,
      userAgent: _userAgent(),
      initializationScript: _resolveInitializationScript(
        rawConfig,
        isMangafire: isMangafire,
      ),
      extraAllowedHosts: _resolveAllowedHosts(rawConfig),
      buildScript: (pass, _) => buildApiCaptureScript(
        payloadKey: '__mfDetailPayload',
        passPayloadName: pass,
        captureTestJs:
            'parsed && parsed.data && typeof parsed.data.hid === "string"',
        apiPathMarker: apiEndpoint ?? '/api/titles/',
      ),
    );
    final detail = MangafireDetail.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    if (detail.hid.isEmpty) {
      throw const FormatException('Could not capture mangafire detail');
    }
    final genreMap = _resolveGenreMapping(rawConfig);
    final tags = <Tag>[
      for (final g in detail.genresWithIds)
        Tag(
          id: g.id > 0
              ? g.id
              : int.tryParse(
                    genreMap[g.name.toLowerCase()] ?? '0',
                  ) ??
                  0,
          name: g.name,
          type: 'tag',
          count: 0,
        ),
      for (final lang in detail.languages)
        Tag(
          id: 0,
          name: lang,
          type: '__mangafire_chapter_language',
          count: 0,
        ),
      const Tag(
        id: 0,
        name: 'Chapter',
        type: '__mangafire_chapter_group',
        count: 0,
      ),
      if (detail.hasVolumes)
        const Tag(
          id: 0,
          name: 'Volume',
          type: '__mangafire_chapter_group',
          count: 0,
        ),
    ];
    final content = Content(
      id: detail.hid,
      sourceId: _sourceId(rawConfig),
      title: detail.title,
      coverUrl: _absolutizeUrl(detail.posterLarge, base),
      tags: tags,
      artists: detail.authors,
      characters: const [],
      parodies: const [],
      groups: const [],
      language: detail.languages.contains('en')
          ? 'en'
          : (detail.languages.isNotEmpty
              ? detail.languages.first
              : 'unknown'),
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime.fromMillisecondsSinceEpoch(0),
      url: pageUrl,
      englishTitle: detail.title,
      contentType: ContentType.manga,
      status: _statusOf(detail.status),
      sourceUrl: pageUrl,
      totalChapters: 0,
    );
    return AdapterDetailResult(content: content, imageUrls: const []);
  }

  /// Resolves a tag name to API ids with a 50-entry LRU cache
  /// (`/api/v1/tags/search?type=&q=`). Returns at most ONE id: the genre
  /// namespace first (curated ids — Romance=23 with 48k items vs the tag
  /// namespace's 106871 with 24), then the requested type's exact
  /// label/slug match, else its first hit. Returning every near-synonym
  /// hit ANDs them on the server and empties the result.
  Future<List<String>> resolveTagIds(
    String type,
    String name,
    Map<String, dynamic> rawConfig,
  ) async {
    final key = '$type\x00${name.toLowerCase()}';
    final cached = _tagIdCache[key];
    if (cached != null) return cached;
    try {
      var ids = const <String>[];
      if (type == 'tag') {
        ids = await _searchTagIds('genre', name, rawConfig);
      }
      ids = ids.isNotEmpty ? ids : await _searchTagIds(type, name, rawConfig);
      return _cacheTagIds(key, ids);
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _searchTagIds(
    String type,
    String name,
    Map<String, dynamic> rawConfig,
  ) async {
    final response = await _dio.getUri(
      Uri.parse('${_baseUrl(rawConfig)}/api/v1/tags/search')
          .replace(queryParameters: {'type': type, 'q': name}),
    );
    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;
    final hits = TagSearchResponse.fromJson(data).result;
    for (final hit in hits) {
      if (hit.matchesName(name)) return [hit.id.toString()];
    }
    return hits.isEmpty ? const [] : [hits.first.id.toString()];
  }

  List<String> _cacheTagIds(String key, List<String> ids) {
    if (_tagIdCache.length >= _tagCacheSize) {
      _tagIdCache.remove(_tagIdCache.keys.first);
    }
    return _tagIdCache[key] = ids;
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
    if (isMangafire) {
      return _mangafireChapters(
        contentId,
        rawConfig,
        language: language,
        scanGroup: scanGroup,
        page: page,
      );
    }
    final base = _baseUrl(rawConfig);
    final slug = _resolveCanonicalSlug(contentId);
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

    final effectiveSlug = _resolveCanonicalSlug(slug);
    final chapters = _selectChapters(dtos, rawConfig)
        .map(
          (c) => Chapter(
            id: '${c.id}',
            title: c.displayName(),
            url: c.chapterPath(effectiveSlug),
            uploadDate: c.uploadDate(),
            scanGroup: c.scanlator(),
            language: (language != null && language.isNotEmpty)
                ? language
                : (c.language?.isNotEmpty == true ? c.language : 'en'),
            pages: null,
          ),
        )
        .toList();
    for (final c in dtos) {
      _chapterPathCache[c.id] = c.chapterPath(effectiveSlug);
      if (_chapterPathCache.length > 500) {
        _chapterPathCache.remove(_chapterPathCache.keys.first);
      }
    }
    return chapters;
  }

  /// Mangafire chapters: boot `/manga/{slug}`, capture the
  /// `/api/titles/{hid}/chapters?language=..` response the SPA fetches
  /// itself. Items match `mfw_ch.json` (`id/number/name/language/
  /// createdAt` epoch). Ascending per live endpoint default; sorted desc
  /// for the app list.
  Future<List<Chapter>> _mangafireChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
  }) async {
    final base = _baseUrl(rawConfig);
    var slug = contentId.startsWith('manga/')
        ? contentId.substring('manga/'.length)
        : contentId;
    slug = slug.startsWith('title/') ? slug.substring('title/'.length) : slug;
    final pageUrl = '$base/title/$slug';
    final detailMap = (rawConfig['api'] as Map<String, dynamic>?)?['detail']
        as Map<String, dynamic>?;
    final chapterGroup = (detailMap?['chapters'] as Map<String, dynamic>?)?[
                'fields']?['scanGroup']?['value']
            ?.toString() ??
        'Chapter';
    final volumeGroup = (detailMap?['volumes'] as Map<String, dynamic>?)?[
                'fields']?['scanGroup']?['value']
            ?.toString() ??
        'Volume';
    final isVolume = scanGroup == volumeGroup;
    final targetPage = isVolume ? null : (page != null && page > 1 ? page : 1);
    final docResponse = await _dio.getUri(
      Uri.parse(pageUrl),
      options: Options(responseType: ResponseType.plain),
    );
    final payload = await _engine.runInWebView(
      pageUrl: pageUrl,
      html: docResponse.data as String,
      userAgent: _userAgent(),
      initializationScript: _resolveInitializationScript(
        rawConfig,
        isMangafire: isMangafire,
      ),
      extraAllowedHosts: _resolveAllowedHosts(rawConfig),
      buildScript: (pass, _) => buildApiCaptureScript(
        payloadKey: isVolume
            ? '__mfVolumesPayload'
            : (targetPage != null && targetPage > 1
                ? '__mfChaptersPayload_p$targetPage'
                : '__mfChaptersPayload'),
        passPayloadName: pass,
        captureTestJs:
            'parsed && Array.isArray(parsed.items) && (parsed.items.length === 0 || typeof parsed.items[0].number === "number")',
        apiPathMarker: isVolume ? '/volumes' : '/chapters',
        targetPage: targetPage,
      ),
      extendDeadlineOnApiTraffic: true,
    );
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final items = (decoded['items'] as List? ?? [])
        .map((e) => ComixChapter.fromJson(e as Map<String, dynamic>))
        .toList();
    final lang = (language ?? 'en').toLowerCase();
    final filtered = items
        .where(
          (c) =>
              c.language == null ||
              c.language!.isEmpty ||
              c.language!.toLowerCase() == lang,
        )
        .toList();
    filtered.sort((a, b) => b.number.compareTo(a.number));
    final itemGroup = isVolume ? volumeGroup : chapterGroup;
    final urlSegment = isVolume ? 'volume' : 'chapter';
    final idPrefix = isVolume ? 'vol-' : '';
    final chapters = filtered
        .map(
          (c) => Chapter(
            id: '$idPrefix${c.id}:$slug',
            title: c.displayName(group: itemGroup),
            url: 'title/$slug/$urlSegment/${c.id}',
            uploadDate: c.uploadDate(),
            scanGroup: itemGroup,
            language: (language != null && language.isNotEmpty)
                ? language
                : (c.language?.isNotEmpty == true ? c.language : 'en'),
            pages: null,
          ),
        )
        .toList();
    for (final c in items) {
      _chapterPathCache[c.id] = slug;
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
    try {
      final detail = _extractInitialQueries(document).entries
          .where((e) => e.key.contains('"detail"'))
          .map((e) => e.value)
          .firstOrNull;
      if (detail is Map<String, dynamic>) {
        final manga = ComixManga.fromJson(detail);
        _cacheCanonicalSlug(
          manga.hid.isNotEmpty ? manga.hid : mangaId,
          manga.url ?? manga.detailPath,
        );
      }
    } catch (_) {
      // Best-effort canonical slug extraction from SSR queries.
    }
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
    if (isMangafire) {
      return _mangafireChapterImages(chapterId, rawConfig);
    }
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
          images: buildPages(ChapterPagesResponse.fromJson(pages)),
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
    final document = html_parser.parse(response.data as String);
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
      pageUrl: '$base/$path',
      html: document.outerHtml,
      userAgent: _userAgent(),
      buildScript: (pass, reject) => buildPageListScript(
        passPayloadName: pass,
        rejectName: reject,
        chapterIdJson: jsonEncode(numericId),
        mainScriptUrlJson: jsonEncode(mainScriptUrl),
      ),
    );
    return ChapterData(
      images: buildPages(
        ChapterPagesResponse.fromJson(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Mangafire reader: boot `/title/{titleId}/chapter/{numericId}`, capture the
  /// chapter-images API response. Supports `data.pages` DTO, comix-style
  /// `{result:{pages:{baseUrl,items}}}`, and generic `{items:[{url}]}`.
  Future<ChapterData?> _mangafireChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = _baseUrl(rawConfig);
    final isVolume =
        chapterId.startsWith('vol-') || chapterId.startsWith('vol:');
    final cleanId = isVolume ? chapterId.substring(4) : chapterId;
    final parts = cleanId.split(':');
    if (parts.length < 2 || parts[1].trim().isEmpty) {
      throw const FormatException(
        'Legacy numeric chapter ID without title context',
      );
    }
    final numericId = int.tryParse(parts[0]) ?? -1;
    final titleId = parts[1];
    final routeType = isVolume ? 'volume' : 'chapter';
    final apiMarker = isVolume ? '/api/volumes/' : '/api/chapters/';
    final pageUrl = '$base/title/$titleId/$routeType/$numericId';
    final docResponse = await _dio.getUri(
      Uri.parse(pageUrl),
      options: Options(responseType: ResponseType.plain),
    );
    final payload = await _engine.runInWebView(
      pageUrl: pageUrl,
      html: docResponse.data as String,
      userAgent: _userAgent(),
      initializationScript: _resolveInitializationScript(
        rawConfig,
        isMangafire: isMangafire,
      ),
      extraAllowedHosts: _resolveAllowedHosts(rawConfig),
      buildScript: (pass, _) => buildApiCaptureScript(
        payloadKey: '__mfPagesPayload',
        passPayloadName: pass,
        captureTestJs: 'parsed && ((parsed.data && parsed.data.pages) || (parsed.result && parsed.result.pages) || (Array.isArray(parsed.items) && parsed.items.length > 0 && typeof parsed.items[0].url === "string"))',
        apiPathMarker: apiMarker,
      ),
    );
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final data = decoded['data'];
    if (data is Map<String, dynamic> && data.containsKey('pages')) {
      final pages = data['pages'] as List?;
      if (pages == null || pages.isEmpty) {
        throw const FormatException('Empty or invalid reader pages');
      }
      final urls = pages
          .map((e) => (e is Map ? e['url'] : e)?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.isEmpty) {
        throw const FormatException('Empty or invalid reader pages');
      }
      return ChapterData(images: urls);
    }

    if (decoded['result'] is Map<String, dynamic>) {
      final pagesDto = ChapterPagesResponse.fromJson(decoded);
      if (pagesDto.items.isNotEmpty) {
        return ChapterData(images: buildPages(pagesDto));
      }
    }

    final items = decoded['items'] as List? ?? const [];
    final root = decoded['result'] is Map<String, dynamic>
        ? decoded['result'] as Map<String, dynamic>
        : decoded;
    final baseUrl = '${root['baseUrl'] ?? root['base_url'] ?? base}';
    final urls = items
        .map((e) => '${(e as Map)['url'] ?? ''}')
        .where((u) => u.isNotEmpty)
        .map((u) => u.startsWith('http') ? u : '$baseUrl/$u')
        .toList();
    if (urls.isEmpty) {
      throw const FormatException('Could not capture chapter images');
    }
    return ChapterData(images: urls);
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
          out.add(
            uri
                .replace(queryParameters: {...uri.queryParameters, 'v3': ''})
                .toString(),
          );
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
    final relatedFeature =
        (rawConfig['features'] as Map<String, dynamic>?)?['related'] as bool?;
    if (relatedFeature == false || isMangafire) return const [];
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
      final related = _extractInitialQueries(document).entries
          .where((e) => e.key.contains('"recommended"'))
          .map((e) => e.value)
          .firstOrNull;
      if (related == null) return const [];
      final items = (related as Map<String, dynamic>)['items'] as List? ?? [];
      if (items.isNotEmpty) {
        return items
            .map(
              (e) => _basicContent(
                ComixManga.fromJson(e as Map<String, dynamic>),
                rawConfig,
              ),
            )
            .toList();
      }
      return SearchResponse.fromJson(related).items
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
  ) async => const [];

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
