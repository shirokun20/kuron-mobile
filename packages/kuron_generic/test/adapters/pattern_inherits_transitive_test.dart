// Tests for transitive `inherits` resolution in [GenericScraperAdapter].
///
// Dio is mocked using [DioAdapter] so no real HTTP calls are made.
//
// Covers `openspec/changes/generic-engine-hardening-76-79/specs/scraper-pattern-inheritance`:
//   1. `searchPage → search → home` inherits `fields` + `pagination` from the
//      grandparent while keeping the parent's `container` override.
//   2. An `inherits` cycle (`a → b → a`) stops safely instead of hanging.
//   3. An `inherits` target that is missing (or a plain URL string) falls
//      back to the local `list` block.
//
// Run with:
//   fvm dart test packages/kuron_generic/test/adapters/pattern_inherits_transitive_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://komiktap.info';

// ── Transitive chain: searchPage → search → home ─────────────────────────────
// `search` overrides only `container`; `fields` + `pagination` live on `home`.
// `searchPage` declares no `list` block at all.
const _transitiveConfig = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'home': {
        'url': '/',
        'list': {
          // Deliberately absent from the search HTML: if the child's
          // container override is lost, nothing matches.
          'container': '.home-item',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.tt'},
            'coverUrl': {'selector': '.limit img', 'attribute': 'src'},
          },
          'pagination': {'next': '.pagination .next.page-numbers'},
        },
      },
      'search': {
        'url': '/?s={query}&paged={page}',
        'inherits': 'home',
        'list': {
          'container': 'div.bsx',
        },
      },
      'searchPage': {
        'url': '/page/{page}/?s={query}',
        'inherits': 'search',
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
  },
};

// Search HTML using the `search` container (`div.bsx`), not home's.
const _searchPageHtml = '''
<html><body>
<div class="bsx">
  <a href="https://komiktap.info/manga/search-result-one/">
    <div class="tt">Search Result One</div>
    <div class="limit"><img src="https://cdn.example.com/s1.jpg"></div>
  </a>
</div>
<div class="bsx">
  <a href="https://komiktap.info/manga/search-result-two/">
    <div class="tt">Search Result Two</div>
    <div class="limit"><img src="https://cdn.example.com/s2.jpg"></div>
  </a>
</div>
<div class="pagination"><a class="next page-numbers" href="/page/3/?s=test">3</a></div>
</body></html>
''';

// ── Cycle: search ⇄ searchPage ───────────────────────────────────────────────
const _cycleConfig = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/?s={query}&paged={page}',
        'inherits': 'searchPage',
        'list': {
          'container': 'div.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.tt'},
          },
        },
      },
      'searchPage': {
        'url': '/page/{page}/?s={query}',
        'inherits': 'search',
        'list': {
          'container': 'div.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.tt'},
          },
        },
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
  },
};

// ── Missing parent ───────────────────────────────────────────────────────────
const _missingParentConfig = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'search': {
        'url': '/?s={query}&paged={page}',
        'inherits': 'ghost',
        'list': {
          'container': 'div.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.tt'},
          },
        },
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
  },
};

// ── String (URL-only) parent ─────────────────────────────────────────────────
const _stringParentConfig = {
  'source': 'komiktap',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'legacy': '/?legacy={query}',
      'search': {
        'url': '/?s={query}&paged={page}',
        'inherits': 'legacy',
        'list': {
          'container': 'div.bsx',
          'fields': {
            'id': {
              'selector': 'a[href]',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.tt'},
          },
        },
      },
      'detail': '/manga/{id}/',
      'chapter': '/{id}/',
    },
  },
};

GenericScraperAdapter _buildAdapter(Dio dio) {
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: Logger(printer: PrettyPrinter())),
    logger: Logger(printer: PrettyPrinter()),
    sourceId: 'komiktap',
  );
}

void main() {
  group('pattern inherits — transitive resolution', () {
    test('searchPage inherits fields+pagination from grandparent home',
        () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      dioAdapter.onGet(
        '$_baseUrl/page/2/?s=test',
        (s) => s.reply(200, _searchPageHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 2),
        _transitiveConfig,
      );

      // Container comes from `search`, fields from grandparent `home`.
      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'search-result-one');
      expect(result.items[0].title, 'Search Result One');
      expect(result.items[0].coverUrl, 'https://cdn.example.com/s1.jpg');
      // Pagination also inherited from grandparent `home`.
      expect(result.hasNextPage, isTrue);
    });

    test('inherits cycle stops safely instead of hanging', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchPageHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _cycleConfig,
      ).timeout(const Duration(seconds: 10));

      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'search-result-one');
    });

    test('missing inherits target falls back to local list', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchPageHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _missingParentConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'search-result-one');
    });

    test('string (URL-only) parent is skipped, local list used', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);

      dioAdapter.onGet(
        '$_baseUrl/?s=test&paged=1',
        (s) => s.reply(200, _searchPageHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'test', page: 1),
        _stringParentConfig,
      );

      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'search-result-one');
    });
  });
}
