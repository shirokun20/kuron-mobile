library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

const _baseUrl = 'https://manga18.club';

Future<Map<String, dynamic>> _loadConfig() async =>
    (await loadConfigRemote('manga18.club-config.json'))
        .cast<String, dynamic>();

String _readFixture(String filename) {
  final candidates = [
    'informations/documentation/manhwa18.club/$filename',
    '../../informations/documentation/manhwa18.club/$filename',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  throw StateError('Cannot locate fixture $filename');
}

GenericScraperAdapter _buildAdapter(Dio dio) {
  final logger = Logger(printer: PrettyPrinter());
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: logger),
    logger: logger,
    sourceId: 'manga18.club',
  );
}

Dio _buildDio() => Dio(BaseOptions(baseUrl: _baseUrl));

const _latestReleasePage2Html = '''
<html>
  <body>
    <div class="section_title"><h5>Lastest Update</h5></div>
    <div class="recoment_box">
      <div class="row">
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/page-two-title" title="">
                <img src="https://cdn.manga18.club/manga/page-two-title/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/page-two-title">page two title</a>
              </div>
            </div>
          </div>
        </div>
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/page-two-second" title="">
                <img src="https://cdn.manga18.club/manga/page-two-second/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/page-two-second">page two second</a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <ul class="pagination">
      <li><a href="/latest-release/1">1</a></li>
      <li class="active"><a href="/latest-release/2">2</a></li>
      <li><a href="/latest-release/3">3</a></li>
      <li><a href="/latest-release/3">›</a></li>
      <li><a href="/latest-release/94">»</a></li>
    </ul>
  </body>
</html>
''';

const _searchPage1Html = '''
<html>
  <body>
    <div class="section_title"><h5>Browse Manga by Genres</h5></div>
    <div class="recoment_box">
      <div class="row">
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/ero-the-princess-submits">
                <img src="https://cdn.manga18.club/manga/ero-the-princess-submits/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/ero-the-princess-submits">Ero: The Princess Submits</a>
              </div>
            </div>
          </div>
        </div>
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/slave-diary">
                <img src="https://cdn.manga18.club/manga/slave-diary/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/slave-diary">Slave Diary</a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <ul class="pagination">
      <li class="active"><a href="/list-manga/?search=the&page=1">1</a></li>
      <li><a href="/list-manga/?search=the&page=2">2</a></li>
      <li><a href="/list-manga/?search=the&page=2">›</a></li>
      <li><a href="/list-manga/?search=the&page=36">»</a></li>
    </ul>
  </body>
</html>
''';

const _searchPage2Html = '''
<html>
  <body>
    <div class="section_title"><h5>Browse Manga by Genres</h5></div>
    <div class="recoment_box">
      <div class="row">
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/tell-me-the-future">
                <img src="https://cdn.manga18.club/manga/tell-me-the-future/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/tell-me-the-future">Tell Me the Future</a>
              </div>
            </div>
          </div>
        </div>
        <div class="col-md-3 col-sm-3 col-xs-6">
          <div class="story_item">
            <div class="story_images">
              <a href="/manhwa/the-alpha-blueprint">
                <img src="https://cdn.manga18.club/manga/the-alpha-blueprint/cover/cover_thumb_2.webp">
              </a>
            </div>
            <div class="mg_info">
              <div class="mg_name">
                <a href="/manhwa/the-alpha-blueprint">The Alpha Blueprint</a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <ul class="pagination">
      <li><a href="/list-manga/?search=the&page=1">«</a></li>
      <li><a href="/list-manga/?search=the&page=1">‹</a></li>
      <li><a href="/list-manga/?search=the&page=1">1</a></li>
      <li class="active"><a href="/list-manga/?search=the&page=2">2</a></li>
      <li><a href="/list-manga/?search=the&page=3">3</a></li>
      <li><a href="/list-manga/?search=the&page=3">›</a></li>
      <li><a href="/list-manga/?search=the&page=36">»</a></li>
    </ul>
  </body>
</html>
''';

const _readerHtml = '''
<html>
  <body>
    <script>
      var next_chapter = "https://manga18.club/manhwa/secret-class/chapter-308";
      var prev_chapter = "https://manga18.club/manhwa/secret-class/chapter-306";
    </script>
    <div class="chapter_boxImages" id="chapter_boxImages">
      <img src="https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/01.jpg">
      <img src="https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/02.jpg">
    </div>
  </body>
</html>
''';

void main() {
  late Map<String, dynamic> config;

  setUpAll(() async {
    config = await _loadConfig();
  });

  group('manga18.club homepage parsing', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('uses the main recoment_box cards and keeps titles non-empty',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/list-manga/1',
        (server) => server.reply(
          200,
          _readFixture('halaman-utama.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.search(const SearchFilter(), config);

      expect(result.items, isNotEmpty);
      expect(result.hasNextPage, isTrue);
      expect(result.items.first.id, 'ero-the-princess-submits');
      expect(result.items.first.title, 'ero: the princess submits');
      expect(
        result.items.every((item) => item.title.trim().isNotEmpty),
        isTrue,
      );
      expect(
        result.items.any((item) => item.title == 'Unknown'),
        isFalse,
        reason:
            'homepage titles must come from .mg_name a, not blank cover links',
      );

      final asmodeck = result.items.firstWhere(
        (item) => item.id == 'asmodeck-a-game-of-desire',
      );
      expect(asmodeck.title, 'asmodeck: a game of desire');
      expect(
        asmodeck.coverUrl,
        contains('/manga/asmodeck-a-game-of-desire/cover/'),
      );
    });

    test('homePage keeps working when page 2 header changes to Lastest Update',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/list-manga/2',
        (server) => server.reply(
          200,
          _latestReleasePage2Html,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.search(
        const SearchFilter(page: 2),
        config,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'page-two-title');
      expect(result.items.first.title, 'page two title');
      expect(result.hasNextPage, isTrue);
    });

    test('genre search keeps pagination and parses tag pages via recoment_box',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manga-list/adult',
        (server) => server.reply(
          200,
          _readFixture('halaman-content-by-tag.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.search(
        const SearchFilter(
          includeTags: [
            FilterItem(id: 0, name: 'adult', type: 'tag'),
          ],
        ),
        config,
      );

      expect(result.items, isNotEmpty);
      expect(result.hasNextPage, isTrue);
      expect(
        result.items.every((item) => item.title.trim().isNotEmpty),
        isTrue,
      );
      expect(result.items.first.coverUrl, isNotEmpty);
    });

    test('search uses list-manga search param and parses page 1 results',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/list-manga/?search=the',
        (server) => server.reply(
          200,
          _searchPage1Html,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.search(
        const SearchFilter(query: 'the'),
        config,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'ero-the-princess-submits');
      expect(result.items.first.title, 'Ero: The Princess Submits');
      expect(result.hasNextPage, isTrue);
    });

    test('search page 2 uses page query param and keeps pagination working',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/list-manga/?search=the&page=2',
        (server) => server.reply(
          200,
          _searchPage2Html,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.search(
        const SearchFilter(query: 'the', page: 2),
        config,
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'tell-me-the-future');
      expect(result.items.first.title, 'Tell Me the Future');
      expect(result.hasNextPage, isTrue);
    });
  });

  group('manga18.club detail and reader parsing', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('detail keeps full chapter IDs instead of dropping the series slug',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manhwa/secret-class',
        (server) => server.reply(
          200,
          _readFixture('halaman-detail.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result = await adapter.fetchDetail('secret-class', config);
      final chapters = result.content.chapters!;

      expect(result.content.title, 'Secret Class');
      expect(
        result.content.coverUrl,
        'https://cdn.manga18.club/manga/secret-class/cover/cover_250x350.jpg',
      );
      expect(chapters.first.id, 'secret-class/chapter-307');
      expect(
          chapters.any((chapter) => chapter.id == 'secret-class/299'), isTrue);
      expect(
        chapters.any((chapter) => chapter.id == 'secret-class/chap-289'),
        isTrue,
      );
      expect(
        chapters.any((chapter) => chapter.id == 'secret-class/chapter-54-o'),
        isTrue,
      );
    });

    test('reader builds the correct chapter URL and parses nav IDs from script',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/manhwa/secret-class/chapter-307',
        (server) => server.reply(
          200,
          _readerHtml,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result =
          await adapter.fetchChapterImages('secret-class/chapter-307', config);

      expect(result, isNotNull);
      expect(result!.images, [
        'https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/01.jpg',
        'https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/02.jpg',
      ]);
      expect(result.prevChapterId, 'secret-class/chapter-306');
      expect(result.nextChapterId, 'secret-class/chapter-308');
    });

    test('reader decodes slides_p_path script arrays from raw HTML', () async {
      dioAdapter.onGet(
        '$_baseUrl/manhwa/secret-class/chapter-307',
        (server) => server.reply(
          200,
          _readFixture('halaman-reader.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      final result =
          await adapter.fetchChapterImages('secret-class/chapter-307', config);

      expect(result, isNotNull);
      expect(result!.images, hasLength(5));
      expect(
        result.images.first,
        'https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/1.jpg',
      );
      expect(
        result.images.last,
        'https://cdn.manga18.club/manga/secret-class/chapters/chapter-307/5.jpg',
      );
      expect(result.prevChapterId, 'secret-class/chapter-306');
      expect(result.nextChapterId, isNull);
    });
  });
}
