// Nonce-bootstrapped POST search (Rawkuma `admin-ajax.php`).
// The search endpoint requires a rotating `search_nonce` that is only
// obtainable from a separate bootstrap GET (`?type=search_form&action=
// get_nonce`). A urlPattern declares this as a `nonce` block:
//
//   "search": {
//     "url": "/wp-admin/admin-ajax.php?action=advanced_search",
//     "method": "post",
//     "form": {"action": "advanced_search", "nonce": "{nonce}", ...},
//     "nonce": {"url": "/wp-admin/admin-ajax.php?type=search_form&action=get_nonce"},
//     "list": {...}
//   }
//
// The adapter GETs the bootstrap URL, extracts the first regex group
// (default pattern matches `name='search_nonce' value='…'`), substitutes
// `{nonce}` into the form, caches the value for one hour, and — when a
// cached nonce yields an empty page (server-side rotation) — refreshes
// once and retries.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/scraper_search_nonce_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://rawkuma.example.com';

const _htmlHeaders = {
  Headers.contentTypeHeader: ['text/html; charset=utf-8'],
};

// Recorded Rawkuma `advanced_search` card shape: flat
// `div.flex.rounded-lg.overflow-hidden` cards, no anchor pagination — the
// pager is `button[onclick*=addSingularFilter('page','N')]`, covered by
// `pagination.mode=paged` (trust the pattern while pages yield items).
const _ajaxListBlock = {
  'container': 'div.flex.rounded-lg.overflow-hidden',
  'fields': {
    'id': {
      'selector': 'a',
      'attribute': 'href',
      'transform': 'slug',
    },
    'title': {'selector': 'a.text-base'},
    'coverUrl': {'selector': 'a img', 'attribute': 'src'},
    'latestChapter': {'selector': 'span.text-sm'},
  },
  'pagination': {'mode': 'paged'},
};

const _nonceBlock = {
  'url': '/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
};

const _nonceSearchConfig = {
  'source': 'rawkuma',
  'baseUrl': _baseUrl,
  'defaultLanguage': 'japanese',
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/wp-admin/admin-ajax.php?action=advanced_search',
        'method': 'post',
        'form': {
          'action': 'advanced_search',
          'nonce': '{nonce}',
          'page': '{page}',
          'query': '{query}',
          'order': 'desc',
          'orderby': 'popular',
        },
        'nonce': _nonceBlock,
        'list': _ajaxListBlock,
      },
      'genreSearch': {
        'url': '/wp-admin/admin-ajax.php?action=advanced_search',
        'method': 'post',
        'form': {
          'action': 'advanced_search',
          'nonce': '{nonce}',
          'page': '{page}',
          'genre': '["{tag}"]',
          'order': 'desc',
          'orderby': 'popular',
        },
        'nonce': _nonceBlock,
        'inherits': 'search',
      },
    },
  },
};

const _nonceHtml =
    "<input type='hidden' name='search_nonce' value='live-nonce-1'>";

String _ajaxHtml(List<String> slugs) {
  final cards = slugs
      .map((slug) => '<div class="flex rounded-lg overflow-hidden h-46">'
          '<a href="$_baseUrl/manga/$slug/" class="cover">'
          '<img src="$_baseUrl/wp-content/uploads/$slug.jpg" />'
          '</a>'
          '<div class="flex flex-col"><div>'
          '<a href="$_baseUrl/manga/$slug/" class="text-base font-medium">'
          'Title $slug</a>'
          '<div><span class="text-sm text-gray-300 mr-4">Chapter 12</span></div>'
          '</div></div></div>')
      .join('\n');
  // Pager buttons carry no href — mode=paged must still report hasNext.
  const pager = '<div class="flex justify-center my-8 col-span-full">'
      '<button type="button" class="w-10 h-10">1</button>'
      '<button type="button" '
      'onclick="window[\'addSingularFilter\'](\'page\', \'2\', this)">2</button>'
      '</div>';
  return '<html><body><div>$cards$pager</div></body></html>';
}

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'rawkuma',
    );

void main() {
  group('search() — nonce-bootstrapped POST (Rawkuma advanced_search)', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(
          dio: dio, matcher: const UrlRequestMatcher(matchMethod: true));
      adapter = _buildAdapter(dio);
    });

    test('bootstraps the nonce via GET, then POSTs it and extracts items',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
        (s) => s.reply(200, _nonceHtml, headers: _htmlHeaders),
      );
      final observed = <RequestOptions>[];
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
        (s) => s.replyCallback(200, (options) {
          observed.add(options);
          return _ajaxHtml(['slug-one', 'slug-two']);
        }, headers: _htmlHeaders),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'tensei', page: 1),
        _nonceSearchConfig,
      );

      expect(observed, hasLength(1));
      expect(observed.single.data['nonce'], 'live-nonce-1',
          reason: '{nonce} must be replaced with the bootstrapped value');
      expect(observed.single.data['query'], 'tensei');
      expect(observed.single.data['page'], '1');
      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'slug-one');
      expect(result.items.first.title, 'Title slug-one');
      expect(result.hasNextPage, isTrue,
          reason: 'mode=paged trusts the pattern while items are yielded');
    });

    test('genre: prefix routes to genreSearch and reuses the cached nonce',
        () async {
      var bootstrapGets = 0;
      dioAdapter.onGet(
        '$_baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
        (s) => s.replyCallback(200, (options) {
          bootstrapGets++;
          return _nonceHtml;
        }, headers: _htmlHeaders),
      );
      final observed = <RequestOptions>[];
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
        (s) => s.replyCallback(200, (options) {
          observed.add(options);
          return _ajaxHtml(['comedy-hit']);
        }, headers: _htmlHeaders),
      );

      await adapter.search(
        const SearchFilter(query: 'tensei', page: 1),
        _nonceSearchConfig,
      );
      final genreResult = await adapter.search(
        const SearchFilter(query: 'genre:comedy', page: 1),
        _nonceSearchConfig,
      );

      expect(bootstrapGets, 1,
          reason: 'the second search must reuse the cached nonce');
      expect(observed, hasLength(2));
      expect(observed.last.data['genre'], '["comedy"]');
      expect(observed.last.data['nonce'], 'live-nonce-1');
      expect(genreResult.items.single.id, 'comedy-hit');
    });

    test('empty page on a cached nonce refreshes once and retries', () async {
      var bootstrapGets = 0;
      dioAdapter.onGet(
        '$_baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
        (s) => s.replyCallback(200, (options) {
          bootstrapGets++;
          final value = bootstrapGets == 1 ? 'stale-nonce' : 'fresh-nonce';
          return "<input type='hidden' name='search_nonce' value='$value'>";
        }, headers: _htmlHeaders),
      );
      var posts = 0;
      final observed = <RequestOptions>[];
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
        (s) => s.replyCallback(200, (options) {
          posts++;
          observed.add(options);
          // The stale nonce yields an empty page (server-side rotation);
          // only the refreshed nonce yields items.
          final sentNonce = (options.data as Map?)?['nonce'];
          return sentNonce == 'fresh-nonce'
              ? _ajaxHtml(['recovered-hit'])
              : '<html><body><div></div></body></html>';
        }, headers: _htmlHeaders),
      );

      // Prime the cache with the stale nonce.
      await adapter.search(
        const SearchFilter(query: 'warmup-empty', page: 1),
        _nonceSearchConfig,
      );
      // Cache is now primed; force the rotation path with a fresh query.
      final result = await adapter.search(
        const SearchFilter(query: 'tensei', page: 1),
        _nonceSearchConfig,
      );

      expect(bootstrapGets, 2,
          reason: 'one priming GET plus one forced refresh');
      expect(posts, 3, reason: 'warmup POST + attempt + one retry');
      expect(observed.last.data['nonce'], 'fresh-nonce');
      expect(result.items.single.id, 'recovered-hit');
    });

    test('missing nonce in bootstrap response aborts without POSTing',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
        (s) => s.reply(200, '<html><body>no nonce here</body></html>',
            headers: _htmlHeaders),
      );
      // NOTE: DioAdapter.history records mock registrations, not performed
      // requests, so actual POSTs are tracked with an observer instead.
      final observed = <RequestOptions>[];
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
        (s) => s.replyCallback(200, (options) {
          observed.add(options);
          return _ajaxHtml(['unreachable']);
        }, headers: _htmlHeaders),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'tensei', page: 1),
        _nonceSearchConfig,
      );

      expect(result.items, isEmpty);
      expect(observed, isEmpty,
          reason: 'no POST may be issued without a bootstrapped nonce');
    });
  });

  group('search() — raw: form params routed to POST patterns', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(
          dio: dio, matcher: const UrlRequestMatcher(matchMethod: true));
      adapter = _buildAdapter(dio);
    });

    // Mirrors the real Rawkuma searchForm: a text query field bound to the
    // `search` urlPattern plus the page field every searchForm carries.
    Map<String, dynamic> rawTextConfig() =>
        Map<String, dynamic>.from(_nonceSearchConfig)
          ..['searchForm'] = {
            'urlPattern': 'search',
            'params': {
              'query': {'queryParam': 'query', 'type': 'text'},
              'page': {'queryParam': 'page', 'type': 'page'},
            },
          };

    // Same, plus a tag-typed field driving the genreSearch urlPattern.
    Map<String, dynamic> rawGenreConfig() =>
        Map<String, dynamic>.from(_nonceSearchConfig)
          ..['searchForm'] = {
            'urlPattern': 'search',
            'params': {
              'query': {'queryParam': 'query', 'type': 'text'},
              'page': {'queryParam': 'page', 'type': 'page'},
              'genre': {
                'queryParam': 'genre',
                'type': 'tag',
                'urlPattern': 'genreSearch',
              },
            },
          };

    void mockNonceFlow(
      List<RequestOptions> observed, {
      required String hitSlug,
    }) {
      dioAdapter.onGet(
        '$_baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce',
        (s) => s.reply(200, _nonceHtml, headers: _htmlHeaders),
      );
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
        (s) => s.replyCallback(200, (options) {
          observed.add(options);
          return _ajaxHtml([hitSlug]);
        }, headers: _htmlHeaders),
      );
    }

    test('raw:query posts the text through the nonce flow', () async {
      final observed = <RequestOptions>[];
      mockNonceFlow(observed, hitSlug: 'raw-hit');

      final result = await adapter.search(
        const SearchFilter(query: 'raw:query=tensei', page: 1),
        rawTextConfig(),
      );

      expect(observed, hasLength(1));
      expect(observed.single.data['query'], 'tensei');
      expect(observed.single.data['nonce'], 'live-nonce-1');
      expect(observed.single.data['page'], '1');
      expect(result.items.single.id, 'raw-hit');
      expect(result.hasNextPage, isTrue);
    });

    test('raw:query carries the page into the form body on page 2', () async {
      final observed = <RequestOptions>[];
      mockNonceFlow(observed, hitSlug: 'raw-page-two');

      final result = await adapter.search(
        const SearchFilter(query: 'raw:query=tensei', page: 2),
        rawTextConfig(),
      );

      expect(observed, hasLength(1));
      expect(observed.single.data['query'], 'tensei');
      expect(observed.single.data['page'], '2');
      expect(result.items.single.id, 'raw-page-two');
    });

    test('raw:genre routes to genreSearch and fills the tag placeholder',
        () async {
      final observed = <RequestOptions>[];
      mockNonceFlow(observed, hitSlug: 'genre-hit');

      final result = await adapter.search(
        const SearchFilter(query: 'raw:genre=comedy', page: 1),
        rawGenreConfig(),
      );

      expect(observed, hasLength(1));
      expect(observed.single.data['genre'], '["comedy"]');
      expect(observed.single.data['nonce'], 'live-nonce-1');
      expect(result.items.single.id, 'genre-hit');
    });
  });
}
