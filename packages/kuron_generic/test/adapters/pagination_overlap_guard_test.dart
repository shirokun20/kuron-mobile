library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://overlap.test';

Map<String, dynamic> _configWith({Map<String, dynamic>? overlapGuard}) {
  final pagination = <String, dynamic>{'alt': '.hpage a.r'};
  if (overlapGuard != null) pagination['overlapGuard'] = overlapGuard;
  return {
    'source': 'overlap',
    'baseUrl': _baseUrl,
    'scraper': {
      'urlPatterns': {
        'home': {
          'url': '/',
          'list': {
            'container': '.utao',
            'fields': {
              'id': {
                'selector': 'a.series',
                'attribute': 'href',
                'transform': 'slug',
              },
              'title': {'selector': '.luf > a > h4'},
            },
            'pagination': pagination,
          },
        },
        'homePage': {
          'url': '/page/{page}/',
          'inherits': 'home',
        },
      },
    },
  };
}

String _pageHtml(List<String> slugs, {bool withNext = true, String nextHref = '/page/2/'}) {
  final buf = StringBuffer('<html><body>');
  for (final slug in slugs) {
    buf.write(
      '<div class="utao">'
      '<a class="series" href="$_baseUrl/manga/$slug/"></a>'
      '<div class="luf"><a href="$_baseUrl/manga/$slug/"><h4>$slug</h4></a></div>'
      '</div>',
    );
  }
  if (withNext) {
    buf.write('<div class="hpage"><a class="r" href="$nextHref">Next</a></div>');
  }
  buf.write('</body></html>');
  return buf.toString();
}

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
  dio: dio,
  urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
  parser: GenericHtmlParser(logger: Logger()),
  logger: Logger(),
  sourceId: 'overlap',
);

Dio _buildDio() => Dio(BaseOptions(baseUrl: _baseUrl));

List<String> _slugs(String prefix, int count, {int start = 1}) =>
    List.generate(count, (i) => '$prefix-${start + i}');

void _stub(DioAdapter m, String path, String html) {
  m.onGet(
    '$_baseUrl$path',
    (s) => s.reply(200, html, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

void main() {
  group('pagination overlap guard', () {
    test('page-2 100% duplicate stops pagination but keeps items', () async {
      final dio = _buildDio();
      final m = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);
      final config = _configWith();
      final ids = _slugs('manga', 29);
      _stub(m, '/', _pageHtml(ids));
      _stub(m, '/page/2/', _pageHtml(ids, nextHref: '/page/3/'));

      final r1 = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      expect(r1.items, hasLength(29));

      final r2 = await adapter.search(
        const SearchFilter(query: '', page: 2),
        config,
      );
      expect(r2.items, hasLength(29));
      expect(r2.hasNextPage, isFalse);
    });

    test('50% overlap follows DOM signal', () async {
      final dio = _buildDio();
      final m = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);
      final config = _configWith();
      final first = _slugs('manga', 10);
      final second = [...first.take(5), ..._slugs('fresh', 5)];
      _stub(m, '/', _pageHtml(first));
      _stub(m, '/page/2/', _pageHtml(second, nextHref: '/page/3/'));

      await adapter.search(const SearchFilter(query: '', page: 1), config);
      final r2 = await adapter.search(
        const SearchFilter(query: '', page: 2),
        config,
      );
      expect(r2.items, hasLength(10));
      expect(r2.hasNextPage, isTrue);
    });

    test('fewer than 5 items never triggers guard', () async {
      final dio = _buildDio();
      final m = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);
      final config = _configWith();
      _stub(m, '/', _pageHtml(_slugs('manga', 3)));
      _stub(m, '/page/2/', _pageHtml(_slugs('manga', 3), nextHref: '/page/3/'));

      await adapter.search(const SearchFilter(query: '', page: 1), config);
      final r2 = await adapter.search(
        const SearchFilter(query: '', page: 2),
        config,
      );
      expect(r2.items, hasLength(3));
      expect(r2.hasNextPage, isTrue);
    });

    test('overlapGuard.enabled=false disables guard', () async {
      final dio = _buildDio();
      final m = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = _buildAdapter(dio);
      final config = _configWith(
        overlapGuard: {'enabled': false},
      );
      final ids = _slugs('manga', 29);
      _stub(m, '/', _pageHtml(ids));
      _stub(m, '/page/2/', _pageHtml(ids, nextHref: '/page/3/'));

      await adapter.search(const SearchFilter(query: '', page: 1), config);
      final r2 = await adapter.search(
        const SearchFilter(query: '', page: 2),
        config,
      );
      expect(r2.items, hasLength(29));
      expect(r2.hasNextPage, isTrue);
    });
  });
}
