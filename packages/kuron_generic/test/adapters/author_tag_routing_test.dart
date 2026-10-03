// Regression test for shirokun20/kuron-mobile#69:
// author/artist tag clicks reached genreSearch with the raw `type:value`
// prefix still attached (`/manga-genre/author:hanse/` → 404).
//
// Covers: includeTags type artist/author route to artistSearch/authorSearch
// when configured (fallback genreSearch otherwise), and the `xxx:` prefix
// is stripped before `{tag}` substitution.
//
// Run with:
//   rtk fvm flutter test packages/kuron_generic/test/adapters/author_tag_routing_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://tags.example.com';

const _listHtml = '''
<html><body>
<div class="bsx">
  <a href="https://tags.example.com/manga/result-one/">
    <div class="tt">Result One</div>
    <div class="limit"><img src="https://cdn.example.com/s1.jpg"></div>
  </a>
</div>
<div class="pagination"><a class="next page-numbers" href="/page/2/">2</a></div>
</body></html>
''';

Map<String, dynamic> _configWith(List<String> patterns) {
  const listBlock = {
    'container': 'div.bsx',
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
  };
  const urls = {
    'authorSearch': '/manga-author/{tag}/',
    'artistSearch': '/manga-artist/{tag}/',
    'genreSearch': '/manga-genre/{tag}/',
    'search': '/search/?q={query}',
  };
  return {
    'source': 'tag-routing',
    'baseUrl': _baseUrl,
    'scraper': {
      'urlPatterns': {
        for (final p in patterns) p: {'url': urls[p], 'list': listBlock},
      },
      'selectors': {
        'detail': {'fields': {}},
      },
    },
  };
}

(GenericScraperAdapter, DioAdapter) _buildAdapter(Dio dio) {
  final adapter = GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: Logger(level: Level.off)),
    logger: Logger(level: Level.off),
    sourceId: 'tag-routing',
  );
  return (adapter, DioAdapter(dio: dio, matcher: const UrlRequestMatcher()));
}

void _stub(DioAdapter dioAdapter, String url) {
  dioAdapter.onGet(
    url,
    (s) => s.reply(200, _listHtml, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

void main() {
  group('author/artist includeTags routing (#69)', () {
    test('artist type with prefix resolves artistSearch with stripped slug',
        () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/manga-artist/han-se/');

      // Shape produced by getContentByTag: value keeps `type:` prefix.
      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'artist:Han Se', type: 'artist')
          ],
        ),
        _configWith(const ['authorSearch', 'artistSearch', 'genreSearch']),
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Result One');
    });

    test('author type with prefix resolves authorSearch with stripped slug',
        () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/manga-author/hanse/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'author:Hanse', type: 'author')
          ],
        ),
        _configWith(const ['authorSearch', 'artistSearch', 'genreSearch']),
      );

      expect(result.items, hasLength(1));
    });

    test('falls back to genreSearch when artistSearch missing', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/manga-genre/han-se/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'artist:Han Se', type: 'artist')
          ],
        ),
        _configWith(const ['genreSearch']),
      );

      expect(result.items, hasLength(1));
    });

    test('prefix-free names still route as before', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/manga-artist/hanse/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [FilterItem(id: 0, name: 'Hanse', type: 'artist')],
        ),
        _configWith(const ['artistSearch', 'genreSearch']),
      );

      expect(result.items, hasLength(1));
    });

    test('author routes to authorSearch without genreSearch gate', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/manga-author/jeon-sun-wook/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'Jeon Sun-Wook', type: 'author')
          ],
        ),
        _configWith(const ['authorSearch']),
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Result One');
    });

    test('no taxonomy routes falls through to text search', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final (adapter, dioAdapter) = _buildAdapter(dio);
      _stub(dioAdapter, '$_baseUrl/search/?q=hanse');

      final result = await adapter.search(
        const SearchFilter(
          query: 'hanse',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'hanse', type: 'author')
          ],
        ),
        _configWith(const ['search']),
      );

      expect(result.items, hasLength(1));
    });
  });
}
