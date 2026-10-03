// reader.imageHostRewrite: dead image hosts are rewritten to a live host.
// Madarascans serves `ts_reader` payloads pointing at `madascans.com`
// (origin 520 on every image) while the same path is 200 on
// `madarascans.net`. Dio is mocked ([DioAdapter]); no real HTTP calls.
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://madarascans.example.com';

String _tsReaderHtml(String host) =>
    '<html><body><div id="readerarea"></div>'
    '<script>ts_reader.run({"post_id":1,"prevUrl":"","nextUrl":"",'
    '"sources":[{"source":"High Speed Server","images":['
    '"https://$host/wp-content/uploads/2026/02/01-11.jpg",'
    '"https://$host/wp-content/uploads/2026/02/02-11.jpg"'
    ']}]});</script></body></html>';

Map<String, Object?> _config({bool withRewrite = true}) => {
      'source': 'madarascans',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/series/{id}/',
          'chapter': '/{id}',
        },
        'selectors': {
          'reader': {
            'tsReaderRegex': 'ts_reader\\.run\\((\\{.*?\\})\\);</script>',
            'images': {'selector': '#readerarea img', 'attribute': 'src'},
            if (withRewrite)
              'imageHostRewrite': {
                'madascans.com': 'madarascans.net',
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
      sourceId: 'madarascans',
    );

void main() {
  group('fetchChapterImages() — reader.imageHostRewrite', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    void mockChapter(String body) {
      dioAdapter.onGet(
        '$_baseUrl/ch-1',
        (s) => s.reply(200, body, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
    }

    test('rewrites dead host to live host', () async {
      mockChapter(_tsReaderHtml('madascans.com'));

      final chapter = await adapter.fetchChapterImages('ch-1', _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, [
        'https://madarascans.net/wp-content/uploads/2026/02/01-11.jpg',
        'https://madarascans.net/wp-content/uploads/2026/02/02-11.jpg',
      ]);
    });

    test('leaves urls untouched when block is absent', () async {
      mockChapter(_tsReaderHtml('madascans.com'));

      final chapter = await adapter.fetchChapterImages(
        'ch-1',
        _config(withRewrite: false),
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, [
        'https://madascans.com/wp-content/uploads/2026/02/01-11.jpg',
        'https://madascans.com/wp-content/uploads/2026/02/02-11.jpg',
      ]);
    });

    test('ignores hosts not in the map', () async {
      mockChapter(_tsReaderHtml('cdn.example.com'));

      final chapter = await adapter.fetchChapterImages('ch-1', _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, [
        'https://cdn.example.com/wp-content/uploads/2026/02/01-11.jpg',
        'https://cdn.example.com/wp-content/uploads/2026/02/02-11.jpg',
      ]);
    });
  });
}
