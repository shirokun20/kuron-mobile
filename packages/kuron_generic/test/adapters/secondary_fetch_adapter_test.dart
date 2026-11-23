// Adapter-level tests for the generic two-step (`secondaryFetch`) flow.
//
// These pin the *fallback* contract as much as the happy path: when the
// one-time token expires (the real site answers 404 with a JSON error body)
// or the page carries no token at all, the adapter must fall back to the
// static HTML/SEO selectors instead of returning an empty result.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://site.test';

/// CJK-XOR encoder mirroring the ad-frame family obfuscation.
String obfuscate(String plain, String key) {
  final out = StringBuffer();
  for (var i = 0; i < plain.length; i++) {
    final mixed = plain.codeUnitAt(i) ^ key.codeUnitAt(i % key.length);
    out.writeCharCode(mixed + 0x4E00);
  }
  return out.toString();
}

Map<String, dynamic> _secondaryBlock({
  String payloadPath = 'items',
  String decodeKey = 'NicoManga',
  String itemsPath = 'items',
  String imagesPath = 'images',
}) =>
    <String, dynamic>{
      'enabled': true,
      'tokenPattern': r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)',
      'url': '{origin}/ad-frame/data?k={key}',
      'referer': 'page',
      'payloadPath': payloadPath,
      'decodeKey': decodeKey,
      'itemsPath': itemsPath,
      'imagesPath': imagesPath,
      'itemFields': {
        'id': {'path': 'ur', 'regex': r'^/?(.*)$'},
        'title': {'path': 'n', 'transform': 'cleanText'},
        'coverUrl': {'path': 'c'},
      },
      'pagination': {
        'page': 'pagination.page',
        'total': 'pagination.total',
        'lastPage': 'pagination.last_page',
      },
    };

const _listItemsJson =
    '[{"n":"  One\\n   Piece  ","c":"https://cdn.test/one.png",'
    '"ur":"/manga6529/7ce0bebd.html"},'
    '{"n":"Si Land","c":"https://cdn.test/si.png",'
    '"ur":"/manga6157/4be8ae35.html"}]';

/// Static SEO fallback markup the site still serves in the first response.
const _staticListHtml = '''
<html><body>
<div class="manga-grid">
  <div class="manga-card">
    <a class="manga-title" href="/manga7004/d4c90944.html">Static One</a>
    <img src="https://cdn.test/static1.png" />
  </div>
</div>
</body></html>
''';

Map<String, dynamic> _listConfig({bool withSecondary = true}) =>
    <String, dynamic>{
      'source': 'testfamily',
      'idType': 'slug',
      'baseUrl': _baseUrl,
      'network': {
        'headers': {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://site.test/',
        },
      },
      'scraper': {
        'enabled': true,
        'urlPatterns': {
          'home': {
            'url': '/manga-list.html?p={page}&v=grid',
            'list': {
              'container': '.manga-grid .manga-card',
              'fields': {
                'id': {
                  'selector': 'a.manga-title',
                  'attribute': 'href',
                  'regex': r'^/?(.*)$',
                },
                'title': {'selector': 'a.manga-title', 'transform': 'cleanText'},
                'coverUrl': {'selector': 'img', 'attribute': 'src'},
              },
              'pagination': {'next': '.custom-pagination .page-link.next'},
              if (withSecondary) 'secondaryFetch': _secondaryBlock(),
            },
          },
        },
      },
    };

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late GenericScraperAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    adapter = GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'testfamily',
    );
  });

  group('list surfaces', () {
    test('two-step fetch returns items + totals from the secondary payload',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-list.html?p=1&v=grid',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"l_3dc0424bfc1d0a9d377cb995\\"}</script>'
          '$_staticListHtml',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=l_3dc0424bfc1d0a9d377cb995',
        (server) => server.reply(
          200,
          json.encode({
            'status': 'success',
            'items': obfuscate(_listItemsJson, 'NicoManga'),
            'pagination': {'page': 1, 'total': 8771, 'last_page': 293},
          }),
          headers: {
            Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(page: 1),
        _listConfig(),
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'manga6529/7ce0bebd.html');
      expect(result.items.first.title, 'One Piece');
      expect(result.totalItems, 8771);
      expect(result.totalPages, 293);
      expect(result.hasNextPage, isTrue);
    });

    test('expired key (404 error body) falls back to static selectors',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-list.html?p=1&v=grid',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"l_deadbeef\\"}</script>'
          '$_staticListHtml',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=l_deadbeef',
        (server) => server.reply(
          404,
          json.encode({'error': 'Invalid or expired key'}),
          headers: {
            Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(page: 1),
        _listConfig(),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.id, 'manga7004/d4c90944.html');
      expect(result.items.single.title, 'Static One');
    });

    test('missing token falls back to static selectors', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-list.html?p=1&v=grid',
        (server) => server.reply(
          200,
          _staticListHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(page: 1),
        _listConfig(),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Static One');
    });

    test('config without secondaryFetch keeps single-step behaviour',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-list.html?p=1&v=grid',
        (server) => server.reply(
          200,
          _staticListHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(page: 1),
        _listConfig(withSecondary: false),
      );

      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Static One');
    });
  });

  group('detail surface', () {
    Map<String, dynamic> detailConfig() => <String, dynamic>{
          'source': 'testfamily',
          'idType': 'slug',
          'baseUrl': _baseUrl,
          'network': {
            'headers': {'Referer': 'https://site.test/'},
          },
          'scraper': {
            'enabled': true,
            'urlPatterns': {
              'detail': '/{id}',
              'chapter': '/{id}',
            },
            'selectors': {
              'detail': {
                'secondaryFetch': {
                  ..._secondaryBlock(
                    payloadPath: 'chaotic_payload',
                    decodeKey: 'NicoMangaX2',
                  ),
                  'itemFields': null,
                  'pagination': null,
                },
                'fields': {
                  'title': {
                    'selector': 'article.ssr-seo-content h1[itemprop="name"]',
                    'transform': 'cleanText',
                  },
                },
                'chapters': {
                  'container': 'nav[aria-label="Chapters"] > a',
                  'fields': {
                    'id': {'selector': 'self', 'attribute': 'href'},
                    'title': {'selector': 'self', 'transform': 'cleanText'},
                  },
                },
              },
              'reader': {
                'mode': 'chaoticPayload',
                'chaoticKey': 'NicoMangaX2',
              },
            },
          },
        };

    test('two-step detail returns title, tags and chapters', () async {
      const decoded = '{"manga":{"n":"  Detail   Title  ",'
          '"c":"https://cdn.test/cover.png","a":"Seiki Amano",'
          '"genres":"comedy,romance","description":"Desc",'
          '"status_text":"On going"},'
          '"chapters_list":[{"n":"Chapter 57.1",'
          '"ur":"https://site.test/manga1998/96542e68/chapter-c57.1.html"}]}';

      dioAdapter.onGet(
        '$_baseUrl/manga1998/96542e68.html',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"m_51eb5986fd0042e89e25180c\\"}</script></html>',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=m_51eb5986fd0042e89e25180c',
        (server) => server.reply(
          200,
          json.encode({
            'success': true,
            'chaotic_payload': obfuscate(decoded, 'NicoMangaX2'),
          }),
          headers: {
            Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchDetail(
        'manga1998/96542e68.html',
        detailConfig(),
      );

      expect(result.content.title, 'Detail Title');
      expect(result.content.coverUrl, 'https://cdn.test/cover.png');
      expect(result.content.chapters, hasLength(1));
      expect(
        result.content.chapters!.single.id,
        'https://site.test/manga1998/96542e68/chapter-c57.1.html',
      );
      expect(
        result.content.tags.map((t) => t.name),
        containsAll(<String>['comedy', 'romance']),
      );
    });

    test('expired detail key falls back to static SEO selectors', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga1998/96542e68.html',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"m_deadbeef\\"}</script>'
          '<article class="ssr-seo-content">'
          '<h1 itemprop="name">SEO Title</h1>'
          '<nav aria-label="Chapters">'
          '<a href="https://site.test/manga1998/96542e68/chapter-c1.html">'
          'Chapter 1</a>'
          '</nav></article></html>',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=m_deadbeef',
        (server) => server.reply(404, '{"error":"expired"}'),
      );

      final result = await adapter.fetchDetail(
        'manga1998/96542e68.html',
        detailConfig(),
      );

      expect(result.content.title, 'SEO Title');
      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.single.title, 'Chapter 1');
    });
  });

  group('reader surface', () {
    test('two-step reader returns image URLs', () async {
      final config = <String, dynamic>{
        'source': 'testfamily',
        'idType': 'slug',
        'baseUrl': _baseUrl,
        'network': {
          'headers': {'Referer': 'https://site.test/'},
        },
        'scraper': {
          'enabled': true,
          'urlPatterns': {
            'detail': '/{id}',
            'chapter': '/{id}',
          },
          'selectors': {
            'reader': {
              'mode': 'chaoticPayload',
              'chaoticKey': 'NicoMangaX2',
              'secondaryFetch': _secondaryBlock(
                payloadPath: 'chaotic_payload',
                decodeKey: 'NicoMangaX2',
                imagesPath: 'images',
              ),
              'images': {'selector': 'img.chapter-img', 'attribute': 'src'},
            },
          },
        },
      };

      final decoded = json.encode({
        'images': [
          'https://s2.cdn.test/images4/20261123/a.jpg',
          'https://cdn.test/images4/20261123/b.jpg',
        ],
      });

      dioAdapter.onGet(
        '$_baseUrl/manga1998/96542e68/chapter-c57.1.html',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"c_be56a4215058882794093bbc\\"}</script></html>',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=c_be56a4215058882794093bbc',
        (server) => server.reply(
          200,
          json.encode({
            'success': true,
            'chaotic_payload': obfuscate(decoded, 'NicoMangaX2'),
          }),
          headers: {
            Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
          },
        ),
      );

      final chapter = await adapter.fetchChapterImages(
        'manga1998/96542e68/chapter-c57.1.html',
        config,
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(2));
      expect(chapter.images.first, 'https://s2.cdn.test/images4/20261123/a.jpg');
    });

    test('expired reader key falls back to DOM images', () async {
      final config = <String, dynamic>{
        'source': 'testfamily',
        'idType': 'slug',
        'baseUrl': _baseUrl,
        'network': {
          'headers': {'Referer': 'https://site.test/'},
        },
        'scraper': {
          'enabled': true,
          'urlPatterns': {
            'detail': '/{id}',
            'chapter': '/{id}',
          },
          'selectors': {
            'reader': {
              'mode': 'chaoticPayload',
              'chaoticKey': 'NicoMangaX2',
              'secondaryFetch': _secondaryBlock(
                payloadPath: 'chaotic_payload',
                decodeKey: 'NicoMangaX2',
              ),
              'container': 'div.chapter-image-wrapper',
              'images': {
                'selector': 'img.chapter-img',
                'attribute': 'src',
              },
            },
          },
        },
      };

      dioAdapter.onGet(
        '$_baseUrl/manga1998/96542e68/chapter-c57.1.html',
        (server) => server.reply(
          200,
          '<html><script>{"payloadKey\\":\\"c_deadbeef\\"}</script>'
          '<div class="chapter-image-wrapper">'
          '<img class="chapter-img" src="https://cdn.test/dom-1.jpg" />'
          '</div></html>',
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );
      dioAdapter.onGet(
        '$_baseUrl/ad-frame/data?k=c_deadbeef',
        (server) => server.reply(404, '{"error":"expired"}'),
      );

      final chapter = await adapter.fetchChapterImages(
        'manga1998/96542e68/chapter-c57.1.html',
        config,
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, contains('https://cdn.test/dom-1.jpg'));
    });
  });
}
