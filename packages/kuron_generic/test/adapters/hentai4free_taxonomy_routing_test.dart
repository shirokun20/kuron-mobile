// hentai4free taxonomy routing: `tag` and `genre` are separate archives
// (/hentai-tag/ vs /hentai-genre/), and artist/author have their own routes.
// A `tag`-typed tap must reach tagSearch, a `genre`-typed tap genreSearch —
// previously every typed tap fell through to genreSearch (the legacy
// single-taxonomy fallback treated `tag`+`genre`+`artist`+`author` alike).
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hentai4free.example.com';

const _listHtml = '''
<html><body>
<article class="h4f-genre-card h4f-genre-card--grid">
  <a class="h4f-genre-card__cover" href="https://hentai4free.example.com/hentai/some-title/">
    <img src="https://cdn.example.com/cover.jpg">
  </a>
  <h2 class="h4f-genre-card__title"><a href="https://hentai4free.example.com/hentai/some-title/">Some Title</a></h2>
</article>
</body></html>
''';

const _config = {
  'source': 'hentai4freenet',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'genreSearch': {
        'url': '/hentai-genre/{tag}/',
        'list': {
          'container': 'article.h4f-genre-card',
          'fields': {
            'id': {
              'selector': 'a.h4f-genre-card__cover',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': 'h2.h4f-genre-card__title a'},
            'coverUrl': {
              'selector': 'a.h4f-genre-card__cover img',
              'attribute': 'src',
            },
          },
        },
      },
      'tagSearch': {
        'url': '/hentai-tag/{tag}/',
        'list': {
          'container': 'article.h4f-genre-card',
          'fields': {
            'id': {
              'selector': 'a.h4f-genre-card__cover',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': 'h2.h4f-genre-card__title a'},
            'coverUrl': {
              'selector': 'a.h4f-genre-card__cover img',
              'attribute': 'src',
            },
          },
        },
      },
      'authorSearch': {
        'url': '/hentai-author/{tag}/',
        'list': {
          'container': 'article.h4f-genre-card',
          'fields': {
            'id': {
              'selector': 'a.h4f-genre-card__cover',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': 'h2.h4f-genre-card__title a'},
            'coverUrl': {
              'selector': 'a.h4f-genre-card__cover img',
              'attribute': 'src',
            },
          },
        },
      },
      'artistSearch': {
        'url': '/hentai-artist/{tag}/',
        'list': {
          'container': 'article.h4f-genre-card',
          'fields': {
            'id': {
              'selector': 'a.h4f-genre-card__cover',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': 'h2.h4f-genre-card__title a'},
            'coverUrl': {
              'selector': 'a.h4f-genre-card__cover img',
              'attribute': 'src',
            },
          },
        },
      },
    },
    'selectors': {
      'detail': {'fields': {}},
    },
  },
};

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'hentai4freenet',
    );

void _stub(DioAdapter dioAdapter, String url) {
  dioAdapter.onGet(
    url,
    (s) => s.reply(200, _listHtml, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

void main() {
  group('hentai4free taxonomy routing (tag vs genre vs author vs artist)',
      () {
    test('tag type reaches tagSearch, not genreSearch', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final adapter = _buildAdapter(dio);
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      _stub(dioAdapter, '$_baseUrl/hentai-tag/big-breasts/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'big-breasts', type: 'tag'),
          ],
        ),
        _config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Some Title');
    });

    test('genre type reaches genreSearch', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final adapter = _buildAdapter(dio);
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      _stub(dioAdapter, '$_baseUrl/hentai-genre/doujinshi/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'doujinshi', type: 'genre'),
          ],
        ),
        _config,
      );

      expect(result.items, hasLength(1));
    });

    test('author type reaches authorSearch', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final adapter = _buildAdapter(dio);
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      _stub(dioAdapter, '$_baseUrl/hentai-author/nyan-kotatsu/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'nyan-kotatsu', type: 'author'),
          ],
        ),
        _config,
      );

      expect(result.items, hasLength(1));
    });

    test('artist type reaches artistSearch', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final adapter = _buildAdapter(dio);
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      _stub(dioAdapter, '$_baseUrl/hentai-artist/nyaruko/');

      final result = await adapter.search(
        const SearchFilter(
          query: '',
          page: 1,
          includeTags: [
            FilterItem(id: 0, name: 'nyaruko', type: 'artist'),
          ],
        ),
        _config,
      );

      expect(result.items, hasLength(1));
    });
  });
}
