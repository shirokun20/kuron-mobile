// Regression test for the detail-chapters "Read First/Last" filter in
// [GenericScraperAdapter.fetchDetail].
//
// The DOM chapter path used to drop EVERY chapter whose title starts with
// "Read First"/"Read Last" (madara nav-button dedup). Oneshot sources like
// hentai4free expose ONLY a "Read First" button, so detail always returned
// 0 chapters. The filter now applies only when a real chapter list exists
// alongside the buttons.
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/detail_oneshot_chapter_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://oneshot.example.com';

Map<String, dynamic> _config() => {
      'source': 'example',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/hentai/{id}/',
          'chapter': '/hentai/{id}/',
        },
        'selectors': {
          'detail': {
            'fields': {
              'title': {'selector': 'h1.entry-title'},
            },
            'chapters': {
              'container': 'a.read-btn, ul.chapters li a',
              'fields': {
                'id': {
                  'selector': 'self',
                  'attribute': 'href',
                  'regex': '/hentai/([^?#]+?)/?\$',
                },
                'title': {'selector': 'self'},
              },
            },
          },
        },
      },
    };

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'example',
    );

void _mockDetail(DioAdapter dioAdapter, String slug, String html) {
  dioAdapter.onGet(
    '$_baseUrl/hentai/$slug/',
    (s) => s.reply(200, html, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

// Oneshot shape (hentai4free): a single "Read First" anchor, no list.
const _oneshotHtml = '''
<html><body>
<h1 class="entry-title">Some Oneshot</h1>
<a class="read-btn" href="https://oneshot.example.com/hentai/some-oneshot/chapter-1/">Read First</a>
</body></html>
''';

// Madara shape: real chapter list PLUS nav shortcut buttons.
const _mixedHtml = '''
<html><body>
<h1 class="entry-title">Some Series</h1>
<a class="read-btn" href="https://oneshot.example.com/hentai/some-series/chapter-1/">Read First</a>
<a class="read-btn" href="https://oneshot.example.com/hentai/some-series/chapter-3/">Read Last</a>
<ul class="chapters">
<li><a href="https://oneshot.example.com/hentai/some-series/chapter-1/">Chapter 1</a></li>
<li><a href="https://oneshot.example.com/hentai/some-series/chapter-2/">Chapter 2</a></li>
<li><a href="https://oneshot.example.com/hentai/some-series/chapter-3/">Chapter 3</a></li>
</ul>
</body></html>
''';

void main() {
  group('fetchDetail() — Read First/Last chapter filter', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('keeps lone "Read First" button as the chapter', () async {
      _mockDetail(dioAdapter, 'some-oneshot', _oneshotHtml);
      final detail = await adapter.fetchDetail('some-oneshot', _config());
      final chapters = detail.content.chapters ?? [];
      expect(chapters, hasLength(1), reason: 'oneshot button is the chapter');
      expect(chapters.first.id, 'some-oneshot/chapter-1');
    });

    test('drops shortcut buttons when a real list exists', () async {
      _mockDetail(dioAdapter, 'some-series', _mixedHtml);
      final detail = await adapter.fetchDetail('some-series', _config());
      final chapters = detail.content.chapters ?? [];
      expect(chapters, hasLength(3), reason: 'only real chapters kept');
      expect(
        chapters.every((c) => !c.title.startsWith('Read ')),
        isTrue,
      );
    });
  });
}
