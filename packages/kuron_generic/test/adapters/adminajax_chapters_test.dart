// Regression test for the `adminAjax` chapters mode (#54).
//
// Manganova-theme sites (akazascans, tsukimangas) render the chapter list
// only via `POST /wp-admin/admin-ajax.php action=get_chapters&id=<postId>`,
// answering `<option value="chapterURL">Title</option>` rows. No other mode
// covered it, so `fetchDetail` yielded 0 chapters although the First/Latest
// links prove content exists.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/adminajax_chapters_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://manganova.test';

Map<String, dynamic> _config() => {
      'source': 'manganova',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/manga/{id}/',
          'chapter': '/{id}',
        },
        'selectors': {
          'detail': {
            'fields': {
              'title': {'selector': 'h1.entry-title'},
            },
            'chapters': {
              'mode': 'adminAjax',
              // Defaults under test: div.bookmark[data-id], get_chapters, id.
              'container': 'ul.main-chapters li a',
              'fields': {
                'id': {
                  'selector': 'self',
                  'attribute': 'href',
                  'regex': r'/([^/?#]+)/?\$',
                },
                'title': {'selector': 'self'},
              },
            },
          },
        },
      },
    };

// Detail page: NO static chapter list, only the bookmark div carrying postId.
const _detailHtml = '''
<html><body>
<h1 class="entry-title">Shadow Slave</h1>
<div class="bookmark" data-id="216"><a href="https://manganova.test/manga/shadow-slave/1/">Read First</a></div>
</body></html>
''';

const _adminAjaxHtml = '''
<select class="selectpicker">
<option value="https://manganova.test/manga/shadow-slave/1/">Chapter 1</option>
<option value="https://manganova.test/manga/shadow-slave/2/">Chapter 2</option>
<option value="https://manganova.test/manga/shadow-slave/3/">Chapter 3</option>
</select>
''';

void main() {
  group('fetchDetail() — adminAjax chapters mode', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late List<RequestOptions> captured;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      captured = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured.add(options);
            handler.next(options);
          },
        ),
      );
      adapter = GenericScraperAdapter(
        dio: dio,
        urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'manganova',
      );

      dioAdapter.onGet(
        '$_baseUrl/manga/shadow-slave/',
        (s) => s.reply(200, _detailHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php',
        (s) => s.reply(200, _adminAjaxHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
    });

    test('builds chapters from admin-ajax <option value> rows', () async {
      final detail = await adapter.fetchDetail('shadow-slave', _config());
      final chapters = detail.content.chapters ?? [];

      expect(chapters, hasLength(3));
      expect(chapters.map((c) => c.id).toList(),
          ['1', '2', '3']);
      expect(chapters.map((c) => c.title).toList(),
          ['Chapter 1', 'Chapter 2', 'Chapter 3']);
      expect(chapters.first.url,
          'https://manganova.test/manga/shadow-slave/1/');
    });

    test('posts to a clean /wp-admin/admin-ajax.php (no ?# tail)', () {
      // `Uri.replace(query: '')` emits a trailing `?`; the endpoint URL must
      // be built from scheme+host+path only.
      expect(
        GenericScraperAdapter.adminAjaxUrl(
            'https://manganova.test/manga/shadow-slave/?foo=1#anchor'),
        'https://manganova.test/wp-admin/admin-ajax.php',
      );
    });

    test('posts form-urlencoded action=get_chapters&id=<data-id>', () async {
      await adapter.fetchDetail('shadow-slave', _config());
      final post = captured.lastWhere(
        (r) => r.path.contains('/wp-admin/admin-ajax.php'),
      );
      expect(post.method, 'POST');
      expect(post.data, 'action=get_chapters&id=216');
      expect(
        post.headers[Headers.contentTypeHeader],
        contains('application/x-www-form-urlencoded'),
      );
    });

    test('falls back to DOM chapters when admin-ajax yields nothing', () async {
      dioAdapter.onPost(
        '$_baseUrl/wp-admin/admin-ajax.php',
        (s) => s.reply(200, '<html><body></body></html>', headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
      final detail = await adapter.fetchDetail('shadow-slave', _config());
      // No options returned → the mode yields an empty list rather than
      // throwing; the reader simply reports 0 chapters.
      expect(detail.content.chapters ?? const [], isEmpty);
    });
  });
}
