// Regression test for issue #58 — scraper search had no POST/form method.
// `GenericScraperAdapter.search` only ever built GET URLs, so POST-only
// search endpoints (FoOlSlide `/search/` with field `search=…`) returned the
// site's empty search form and the source could never pass a search smoke.
//
// A urlPattern may now declare `"method": "post"` + `"form": {…}`; the
// pattern is fetched as a form POST and then goes through the same list
// extraction path as a GET. Patterns without `method` are unchanged.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/scraper_search_post_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://foolslide.example.com';

const _htmlHeaders = {
  Headers.contentTypeHeader: ['text/html; charset=utf-8'],
};

// Recorded FoOlSlide shape: home = `div.group`, search = POST `/search/`
// with form field `search`; the same URL on GET renders only the empty form.
const _listBlock = {
  'container': 'div.group',
  'fields': {
    'id': {
      'selector': 'div.title a[href*="/read/"]',
      'attribute': 'href',
      'transform': 'slug',
    },
    'title': {'selector': 'div.title a'},
    'coverUrl': {'selector': 'img', 'attribute': 'src'},
  },
};

const _postSearchConfig = {
  'source': 'foolslide',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/search/',
        'method': 'post',
        'form': {'search': '{query}'},
        'list': _listBlock,
      },
      'searchPage': {
        'url': '/search/page/{page}/',
        'method': 'post',
        'form': {'search': '{query}', 'page': '{page}'},
        'inherits': 'search',
      },
    },
  },
};

// Same source shape, but no `method`/`form` — the pre-#58 GET contract.
const _getSearchConfig = {
  'source': 'foolslide',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/search/?s={query}',
        'list': _listBlock,
      },
    },
  },
};

String _searchHtml(List<String> slugs) {
  final groups = slugs
      .map((slug) => '<div class="group">'
          '<img src="https://cdn.example.com/$slug.jpg" />'
          '<div class="title"><a href="/read/$slug/">Title $slug</a></div>'
          '</div>')
      .join('\n');
  return '<html><body>$groups</body></html>';
}

// GET on /search/ — the site replies with the bare, empty search form.
const _emptySearchFormHtml =
    '<html><body><form action="/search/"><input name="search" /></form>'
    'No results</body></html>';

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'foolslide',
    );

Dio _buildDio() => Dio(BaseOptions(baseUrl: _baseUrl));

void _mockGet(DioAdapter dioAdapter, String path, String html) {
  dioAdapter.onGet(
    '$_baseUrl$path',
    (s) => s.reply(200, html, headers: _htmlHeaders),
  );
}

/// Registers a POST mock and records the observed request so assertions can
/// run outside the mock callback (a throw inside it is swallowed by the
/// adapter's list-fetch error handling).
List<RequestOptions> _mockPost(
    DioAdapter dioAdapter, String path, String html) {
  final observed = <RequestOptions>[];
  dioAdapter.onPost(
    '$_baseUrl$path',
    (s) => s.replyCallback(200, (options) {
      observed.add(options);
      return html;
    }, headers: _htmlHeaders),
  );
  return observed;
}

void main() {
  group('search() — POST/form urlPattern (issue #58)', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(
          dio: dio, matcher: const UrlRequestMatcher(matchMethod: true));
      adapter = _buildAdapter(dio);
    });

    test('POSTs the form field and extracts the same list as a GET', () async {
      // GET returns the empty form — proves the GET path cannot serve search.
      _mockGet(dioAdapter, '/search/', _emptySearchFormHtml);
      final observed = _mockPost(
          dioAdapter, '/search/', _searchHtml(['alpha-one', 'alpha-two']));

      final result = await adapter.search(
        const SearchFilter(query: 'o', page: 1),
        _postSearchConfig,
      );

      expect(observed, hasLength(1),
          reason: 'search must issue a POST, not a GET');
      expect(
        observed.single.headers[Headers.contentTypeHeader],
        Headers.formUrlEncodedContentType,
      );
      expect(observed.single.data, {'search': 'o'},
          reason: 'form body must carry the query field');

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'alpha-one');
      expect(result.items.first.title, 'Title alpha-one');
      expect(result.items.map((i) => i.sourceId).toSet(), {'foolslide'});
    });

    test('substitutes {page} into the form body on page > 1', () async {
      final observed =
          _mockPost(dioAdapter, '/search/page/3/', _searchHtml(['alpha-nine']));

      final result = await adapter.search(
        const SearchFilter(query: 'o', page: 3),
        _postSearchConfig,
      );

      expect(observed, hasLength(1));
      expect(observed.single.data, {'search': 'o', 'page': '3'});
      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'alpha-nine');
    });

    test('config without "method" still uses GET (null-safe, unchanged)',
        () async {
      _mockGet(dioAdapter, '/search/?s=o', _searchHtml(['get-hit']));

      final result = await adapter.search(
        const SearchFilter(query: 'o', page: 1),
        _getSearchConfig,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'get-hit');
      expect(
        dioAdapter.history.every((m) => m.request.method?.name == 'GET'),
        isTrue,
        reason: 'no POST may be issued for a pattern without "method":"post"',
      );
    });
  });
}
