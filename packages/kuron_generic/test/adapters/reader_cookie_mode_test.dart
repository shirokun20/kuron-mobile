// Reader cookie mode (hentaikun `{slug}/read=2` all-pages mode).
//
// `reader.cookies` templates (`{"{id}/read": "2"}`) are sent as a `Cookie`
// header on the chapter fetch + pagination sub-fetches, and the resulting
// `var jsondata=[...]` bare array resolves via the existing scriptJson
// contract. Dio is mocked ([DioAdapter]); no real HTTP calls are made.
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hentaikun.example.com';
const _slug = 'my-slug-18117';

String _jsondataHtml(int count) {
  final urls = [
    for (var i = 1; i <= count; i++) '"https://cdn.example.com/$i.jpg"',
  ];
  return '<html><body><script>var jsondata=[${urls.join(',')}];</script>'
      '</body></html>';
}

const _onePageHtml = '<html><body>'
    '<div class="image-show"><img src="https://cdn.example.com/1.jpg" /></div>'
    '<div class="next"><a href="/my-slug-18117/read/2/">Next</a></div>'
    '</body></html>';

const _page2Html = '<html><body>'
    '<div class="image-show"><img src="https://cdn.example.com/2.jpg" /></div>'
    '</body></html>';

Map<String, Object?> _config({bool withCookies = true}) => {
      'source': 'hentaikun',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/{id}/',
          'chapter': '/{id}/read/',
        },
        'selectors': {
          'reader': {
            // `{slug}` = last path segment: live hentaikun cookie name is the
            // bare slug (`<slug>/read=2`), while chapter ids carry the
            // category prefix (`original-doujins-series/<slug>`).
            if (withCookies) 'cookies': {'{slug}/read': '2'},
            'images': {
              'scriptJson': {'id': 'jsondata', 'items': ''},
              'selector': '.image-show img',
              'attribute': 'src',
            },
            'pagination': {'next': 'div.next a', 'maxPages': 100},
          },
        },
      },
    };

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'hentaikun',
    );

void main() {
  group('fetchChapterImages() — reader.cookies', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;
    final requestedCookies = <String?>[];

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
      requestedCookies.clear();
    });

    String? cookieOf(RequestOptions options) {
      final headers = options.headers;
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'cookie') return entry.value?.toString();
      }
      return null;
    }

    void mockChapter(String body) {
      dioAdapter.onGet(
        '$_baseUrl/$_slug/read/',
        (s) => s.replyCallback(200, (options) {
          requestedCookies.add(cookieOf(options));
          return body;
        }, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
    }

    test('sends substituted Cookie header on chapter fetch', () async {
      mockChapter(_jsondataHtml(25));

      final chapter = await adapter.fetchChapterImages(_slug, _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(25));
      expect(requestedCookies, ['$_slug/read=2']);
    });

    test('full-path chapter id sends bare-slug cookie (live hentaikun)', () async {
      const fullId = 'original-doujins-series/$_slug';
      dioAdapter.onGet(
        '$_baseUrl/$fullId/read/',
        (s) => s.replyCallback(200, (options) {
          requestedCookies.add(cookieOf(options));
          return _jsondataHtml(86);
        }, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter = await adapter.fetchChapterImages(fullId, _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(86));
      expect(requestedCookies, ['$_slug/read=2']);
    });

    test('sends no Cookie header when block is absent', () async {
      mockChapter(_jsondataHtml(25));

      final chapter = await adapter.fetchChapterImages(
        _slug,
        _config(withCookies: false),
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(25));
      expect(requestedCookies, [isNull]);
    });

    test('pagination sub-fetch carries the same cookie', () async {
      mockChapter(_onePageHtml);
      dioAdapter.onGet(
        '$_baseUrl/$_slug/read/2/',
        (s) => s.replyCallback(200, (options) {
          requestedCookies.add(cookieOf(options));
          return _page2Html;
        }, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter = await adapter.fetchChapterImages(_slug, _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(2));
      expect(requestedCookies, hasLength(2));
      expect(
        requestedCookies.every((c) => c == '$_slug/read=2'),
        isTrue,
        reason: 'every fetch, including pagination sub-pages, sends cookies',
      );
    });

    test('missing jsondata falls back to images selector', () async {
      mockChapter(_onePageHtml);
      dioAdapter.onGet(
        '$_baseUrl/$_slug/read/2/',
        (s) => s.reply(200, _page2Html, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter = await adapter.fetchChapterImages(_slug, _config());

      expect(chapter, isNotNull);
      expect(chapter!.images, isNotEmpty);
    });
  });
}
