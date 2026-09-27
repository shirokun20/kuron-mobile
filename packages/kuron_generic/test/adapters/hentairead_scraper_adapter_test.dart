// Adapter contract for the published hentairead config
// (shirokun20/kuron-extensions → config/en/hentairead-config.json).
//
// The config is loaded live via `loadConfigRemote`, so these tests assert
// against whatever the published config actually declares. The expectations
// below were verified against the live site on 2026-09-27:
//   - baseUrl is https://hentairead.io (hentairead.com answers 403)
//   - detail URL is `/{id}/`; chapter URL is `/{id}` (no /hentai/ prefix)
//   - detail title is `h1`, cover is `meta[property="og:image"]`,
//     tags are `a[href*='/genres/']` with slug transform
//   - reader images are `img[data-index]@src`
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

// Mirrors the published config's baseUrl. Kept as a test constant so a
// published baseUrl change surfaces as a loud mismatch rather than a
// silently-unmatched mock route.
const _baseUrl = 'https://hentairead.io';

// Slug path shape is `/{slug}-{mangaId}`, and the chapter adds
// `/chapter-{n}-{chapterId}`. The config's `/{id}/` detail pattern keeps the
// whole slug (manga id included) as the content id.
const _slug = 'brass-eater-59697';
const _contentId = _slug;
const _chapterUrl = '$_baseUrl/$_slug/chapter-1-162735/';

const _detailHtml = '''
<html>
  <body>
    <h1 class="title-detail" id="title-detail-manga" data-manga="59697">BRASS EATER</h1>
    <meta property="og:image" content="https://hentairead.io/upload/pages/2026/09/1790413498-6ab78abadd82e-cover.jpg">
    <a href="/genres/adult/" class="list-group-item list-group-item-action-menu ">Adult</a>
    <a href="/genres/action/" class="list-group-item list-group-item-action-menu ">Action</a>
    <a href="/genres/adaptation/" class="list-group-item list-group-item-action-menu ">Adaptation</a>
    <ul id="nt_listchapter">
      <li>
        <a href="/$_slug/chapter-1-162735/" title="Chapter 1">Chapter 1</a>
      </li>
    </ul>
  </body>
</html>
''';

const _readerHtml = '''
<html>
  <body>
    <img alt="BRASS EATER Chapter 1 - page 1" data-index="1" src="https://ht.mgread.io/manga/2026/09/59697/162735/1.webp">
    <img alt="BRASS EATER Chapter 1 - page 2" data-index="2" src="https://ht.mgread.io/manga/2026/09/59697/162735/2.webp">
    <img alt="BRASS EATER Chapter 1 - page 3" data-index="3" src="https://ht.mgread.io/manga/2026/09/59697/162735/3.webp">
  </body>
</html>
''';

GenericScraperAdapter _buildAdapter(Dio dio) {
  final logger = Logger(level: Level.off);
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: logger),
    logger: logger,
    sourceId: 'hentairead',
  );
}

void main() {
  late Map<String, dynamic> config;

  setUpAll(() async {
    config = (await loadConfigRemote('hentairead-config.json'))
        .cast<String, dynamic>();
  });

  group('hentairead published config', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('declares the baseUrl the adapter is built against', () {
      expect(config['baseUrl'], _baseUrl);
    });

    test('detail routes to /{id}/ and reads h1 + og:image + genre tags',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/$_contentId/',
        (server) => server.reply(
          200,
          _detailHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchDetail(_contentId, config);

      expect(result.content.title, 'BRASS EATER');
      expect(
        result.content.coverUrl,
        'https://hentairead.io/upload/pages/2026/09/'
        '1790413498-6ab78abadd82e-cover.jpg',
      );
      expect(
        result.content.tags.map((tag) => tag.name),
        containsAll(['adult', 'action', 'adaptation']),
      );
    });

    test('detail chapter links keep the series slug in the chapter id',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/$_contentId/',
        (server) => server.reply(
          200,
          _detailHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchDetail(_contentId, config);

      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, isNotEmpty);
      expect(result.content.chapters!.first.id, contains(_slug));
    });

    test('reader reads img[data-index] src in document order', () async {
      dioAdapter.onGet(
        _chapterUrl,
        (server) => server.reply(
          200,
          _readerHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchChapterImages(_chapterUrl, config);

      expect(result, isNotNull);
      expect(result!.images, [
        'https://ht.mgread.io/manga/2026/09/59697/162735/1.webp',
        'https://ht.mgread.io/manga/2026/09/59697/162735/2.webp',
        'https://ht.mgread.io/manga/2026/09/59697/162735/3.webp',
      ]);
    });
  });
}
