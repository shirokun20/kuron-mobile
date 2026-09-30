// A normal (non-video) chapter must keep every page — the case the video work
// never covered.
//
// `reader_video_scoped_test.dart` only ever asserted the *video* branch, and
// its "mixed" fixture was synthetic. So the shipped reader block for
// mangadistrict was never run against a chapter that actually has pages, and
// nothing would have caught a selector or attribute change that silently
// dropped the start of a chapter (a reader opening at page 40 of 41 looks
// like "the source is broken", not like a config bug).
//
// Live capture: `everyones-man-uncensored/chapter-1`, 41 pages.
//   - 1 placeholder (`#image-99999`),
//   - pages 1–41 as `img.wp-manga-chapter-img` inside `.page-break`,
//   - roughly half of them lazy-loaded (`data-src`), the rest plain `src`,
//     which is why the config names `data-src` and relies on the parser's
//     lazy-load fallback chain for the rest.
// Dio is mocked ([DioAdapter]); no network.
//
// Run with:
//   dart test packages/kuron_generic/test/adapters/reader_chapter_pages_test.dart
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://mangadistrict.test';
const _chapterId = 'everyones-man-uncensored/chapter-1/';
const _chapterUrl = '$_baseUrl/series/$_chapterId';
const _pageCount = 41;

String _liveChapter() =>
    File('test/fixtures/mangadistrict_chapter_normal.html').readAsStringSync();

/// The shipped mangadistrict `reader` block (extensions 1.0.1), verbatim.
Map<String, dynamic> _shippedReaderConfig() => <String, dynamic>{
      'source': 'mangadistrict',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {'detail': '/series/{id}/', 'chapter': '/series/{id}'},
        'selectors': {
          'detail': {
            'fields': {
              'title': {'selector': 'h1'},
            },
          },
          'reader': {
            'mode': 'chapterDataScript',
            'images': {
              'selector': '.reading-content img.wp-manga-chapter-img:not(#image-99999), '
                  '.reading-content .page-break img:not(#image-99999)',
              'attribute': 'data-src',
            },
            'video': {
              'container': '.chapter-video-frame',
              'selector': 'video source, video',
              'attribute': 'src',
              'dataAttribute': 'data-vvl-src',
              'requireChapterType': 'chapter-type-video',
            },
            'nav': {
              'next': '.next_page, .nav-links .next',
              'prev': '.prev_page, .nav-links .prev',
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
      sourceId: 'mangadistrict',
    );
  });

  group('a chapter with pages keeps all of them', () {
    test('every page survives, in order, starting at page 1', () async {
      dioAdapter.onGet(
        _chapterUrl,
        (s) => s.reply(200, _liveChapter(), headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter =
          await adapter.fetchChapterImages(_chapterId, _shippedReaderConfig());
      expect(chapter, isNotNull);

      final images = chapter!.images;
      expect(
        images,
        hasLength(_pageCount),
        reason: 'the live chapter has $_pageCount pages; a short list means the '
            'selector or the attribute chain dropped some',
      );
      // Page 1 is the one that goes missing when an attribute chain is wrong —
      // the reader then opens halfway through and reads as "source is broken".
      expect(
        images.first,
        endsWith('/chapter-1/01.jpg'),
        reason: 'page 1 must be first',
      );
      expect(images.last, endsWith('/chapter-1/41.jpg'));
      expect(images.toSet(), hasLength(_pageCount), reason: 'no duplicates');

      // The placeholder is a 1x1 and must never become page 1.
      expect(
        images.where((u) => u.contains('000001.jpg')),
        isEmpty,
        reason: '#image-99999 placeholder leaked into the page list',
      );
      // FIFU lazy-load pairs put a `data:` SVG in `src`; the fallback chain has
      // to reach past it.
      expect(
        images.where((u) => u.startsWith('data:')),
        isEmpty,
        reason: 'a lazy-load placeholder reached the reader',
      );

      // A chapter with pages is never a video chapter, whatever else is on the
      // page — the reader's guard is `images.isEmpty && videoUrls.isNotEmpty`.
      expect(chapter.videoUrls, isEmpty);
      expect(
        chapter.images.isEmpty && chapter.videoUrls.isNotEmpty,
        isFalse,
        reason: 'a normal chapter must never render the video-only surface',
      );
    });
  });
}
