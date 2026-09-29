// Video vs image signal separation (openspec: `video-and-image-separation`).
//
// A config may declare a `reader.video` block so streams are harvested from
// the chapter's own video element instead of a page-wide regex. Three things
// have to hold:
//   1. the scoped harvest finds the chapter stream and not the page's promos
//      (fixture: a live mangadistrict ep1 capture),
//   2. a config WITHOUT the block is byte-for-byte the legacy behaviour —
//      every published source depends on that,
//   3. dedupe runs after URL normalisation, so the wrapper + <source> pair a
//      video host emits collapse to one entry.
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/reader_video_scoped_test.dart
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://mangadistrict.test';

// Trailing slash on the id is deliberate (D6): chapter ids from the detail
// list carry it, and the template has none — `/series/{id}` + `x/ep1/` is
// exactly the live URL, with no `//` for the server to 301.
const _chapterId = 'ai-animation-a-catastrophic-christmas-date/ep1/';
const _chapterUrl = '$_baseUrl/series/$_chapterId';
const _stream = 'https://sv1-a7f3b.mangadistrict.com/videos/'
    'a-catastrophic-christmas-date-episode-1-59f61f/master.m3u8';

const _liveImagesSelector = '.reading-content img.wp-manga-chapter-img, '
    '.reading-content .page-break img';
const _scopedImagesSelector =
    '.reading-content img.wp-manga-chapter-img:not(#image-99999), '
    '.reading-content .page-break img:not(#image-99999)';

String _liveEp1() =>
    File('test/fixtures/mangadistrict_ep1.html').readAsStringSync();

/// mangadistrict's own config, minus everything unrelated to the reader.
/// [scoped] false = the shipped v1.0.0 reader block (page-wide video scan,
/// placeholder included) — the compatibility baseline.
Map<String, dynamic> _config({required bool scoped}) => <String, dynamic>{
      'source': 'mangadistrict',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/series/{id}/',
          'chapter': '/series/{id}',
        },
        'selectors': {
          'detail': {
            'fields': {
              'title': {'selector': 'h1'},
            },
          },
          'reader': {
            'mode': 'chapterDataScript',
            'images': {
              'selector': scoped ? _scopedImagesSelector : _liveImagesSelector,
              'attribute': 'data-src',
            },
            if (scoped)
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

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'mangadistrict',
    );

void _mockChapter(DioAdapter dioAdapter, String html) {
  dioAdapter.onGet(
    _chapterUrl,
    (s) => s.reply(200, html, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

// Synthetic shape: a real image page plus a scoped stream (the case that
// `bb72891` could not reach — placeholder or not, images were never empty
// together with a video).
const _mixedHtml = '''
<html><body>
<div class="c-page-content reading-content-wrap chapter-type-video">
  <div class="reading-content">
    <div class="page-break"><img id="image-1" src="https://cdn.example.com/p/001.jpg"></div>
    <div class="page-break"><img id="image-2" src="https://cdn.example.com/p/002.jpg"></div>
    <div class="chapter-video-frame" id="chapter-video-frame">
      <section class="vvl-info">
        <div class="videojs-vast-wrapper" data-vvl-src="//cdn.example.com/hls/master.m3u8">
          <video id="vjs-player">
            <source src="https://cdn.example.com/hls/master.m3u8" type="application/x-mpegURL">
          </video>
        </div>
      </section>
    </div>
  </div>
</div>
</body></html>
''';

void main() {
  group('reader.video scoped harvest — live ep1 fixture', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('finds the chapter stream alone, and no placeholder page', () async {
      _mockChapter(dioAdapter, _liveEp1());
      final chapter =
          await adapter.fetchChapterImages(_chapterId, _config(scoped: true));

      expect(chapter, isNotNull);
      // The only `.mp4`s on the page are previews of OTHER series, all of them
      // outside `.chapter-video-frame`.
      expect(
        chapter!.videoUrls,
        [_stream],
        reason: 'scoped harvest must yield the chapter stream alone',
      );
      expect(
        chapter.videoUrls.where((u) => u.endsWith('.mp4')),
        isEmpty,
        reason: 'promos live outside the video container',
      );
      // #image-99999 is excluded on both selector arms, so the reader's
      // `images.isEmpty && videoUrls.isNotEmpty` guard fires unchanged.
      expect(
        chapter.images,
        isEmpty,
        reason: '#image-99999 is excluded on both selector arms',
      );
      expect(chapter.images.isEmpty && chapter.videoUrls.isNotEmpty, isTrue,
          reason: 'the reader\'s isVideoChapter guard fires without changes');
    });

    test('config WITHOUT reader.video keeps the page-wide baseline', () async {
      _mockChapter(dioAdapter, _liveEp1());
      final chapter =
          await adapter.fetchChapterImages(_chapterId, _config(scoped: false));

      expect(chapter, isNotNull);
      // Legacy: the placeholder still counts as an image…
      expect(chapter!.images, hasLength(1));
      expect(chapter.images.single, contains('000001.jpg'));
      // …and the page-wide regex still sees every stream on the page.
      expect(chapter.videoUrls, contains(_stream));
      expect(
        chapter.videoUrls.where((u) => u.endsWith('.mp4')),
        hasLength(28),
        reason: 'baseline must not silently drop captures it used to return',
      );
    });

    test('an empty video block delegates to the legacy page-wide scan',
        () async {
      final resolver = ReaderImageResolver(
        urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'mangadistrict',
      );
      final html = _liveEp1();

      expect(
        resolver.extractVideoUrls(html, <String, dynamic>{}),
        resolver.extractChapterVideoUrls(html),
      );
      expect(
        resolver.extractVideoUrls(html, <String, dynamic>{
          'video': <String, dynamic>{},
        }),
        resolver.extractChapterVideoUrls(html),
      );
    });
  });

  group('normalisation and mixed chapters', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('wrapper and <source> copies of one stream collapse to one entry',
        () async {
      _mockChapter(dioAdapter, _mixedHtml);
      final chapter =
          await adapter.fetchChapterImages(_chapterId, _config(scoped: true));

      expect(chapter, isNotNull);
      // `data-vvl-src` is protocol-relative, `<source src>` absolute — same
      // stream, and dedupe happens after normalisation, not before.
      expect(chapter!.videoUrls, ['https://cdn.example.com/hls/master.m3u8']);
    });

    test('a chapter with pages AND a stream yields both (task 6.5)', () async {
      _mockChapter(dioAdapter, _mixedHtml);
      final chapter =
          await adapter.fetchChapterImages(_chapterId, _config(scoped: true));

      expect(chapter, isNotNull);
      expect(chapter!.images, [
        'https://cdn.example.com/p/001.jpg',
        'https://cdn.example.com/p/002.jpg',
      ]);
      expect(chapter.videoUrls, isNotEmpty);
    });
  });
}
