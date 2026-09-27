// Issue #68: a chapter that serves `<video>`/HLS instead of `<img>` must be
// tagged with `ChapterData.videoUrls` so the reader can play it. Dio is mocked
// ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/reader_video_chapter_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://reader.example.com';

Map<String, dynamic> _config() => {
      'source': 'example',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/manga/{id}/',
          'chapter': '/{id}',
        },
        'selectors': {
          'reader': {
            'images': {'selector': '#readerarea img', 'attribute': 'src'},
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

void _mockChapter(DioAdapter dioAdapter, String html) {
  dioAdapter.onGet(
    '$_baseUrl/ch-1',
    (s) => s.reply(200, html, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

const _videoChapterHtml = '''
<html><body>
<div id="readerarea">
  <video controls poster="https://cdn.example.com/p/poster.jpg">
    <source src="https://cdn.example.com/hls/master.m3u8" type="application/x-mpegURL">
  </video>
</div>
</body></html>
''';

const _imageChapterHtml = '''
<html><body>
<div id="readerarea">
  <img decoding="async" src="https://cdn.example.com/p/001.jpg" />
  <img decoding="async" src="https://cdn.example.com/p/002.jpg" />
</div>
</body></html>
''';

void main() {
  group('fetchChapterImages() — video/HLS chapter (issue #68)', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('populates videoUrls and leaves images empty', () async {
      _mockChapter(dioAdapter, _videoChapterHtml);
      final chapter = await adapter.fetchChapterImages('ch-1', _config());

      expect(chapter, isNotNull);
      expect(
        chapter!.videoUrls,
        ['https://cdn.example.com/hls/master.m3u8'],
      );
      // A video chapter has no pages to page — the HLS URL must not leak
      // into the image list (normalizeChapterImageUrls drops it).
      expect(chapter.images, isEmpty);
    });

    test('image-only chapter yields empty videoUrls (regression guard)',
        () async {
      _mockChapter(dioAdapter, _imageChapterHtml);
      final chapter = await adapter.fetchChapterImages('ch-1', _config());

      expect(chapter, isNotNull);
      expect(chapter!.videoUrls, isEmpty);
      expect(
        chapter.images,
        [
          'https://cdn.example.com/p/001.jpg',
          'https://cdn.example.com/p/002.jpg',
        ],
      );
    });
  });
}
