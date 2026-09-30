// Where a mixed chapter's play card belongs.
//
// A gallery can carry a video among its photos. The reader used to append the
// card after the LAST page regardless, so a chapter whose site puts the video
// first (cosplaytele: "110 photos and 1 video", the embed above every photo)
// showed the card 110 pages too late. `extractVideoPlacement` counts the pages
// the chapter's own image selector matches before the stream element.
//
// The `iframe` cases matter too: a cross-origin embed carries no `.m3u8`, so
// `extractChapterVideoUrls` (the legacy regex) can never see it — only a
// scoped `reader.video` block can.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://cosplaytele.test';

/// cosplaytele's real shape: a gallery where the embed sits ABOVE every photo.
const _embedFirstHtml = '''
<html><body>
<div class="entry-content single-page">
  <iframe src="https://cossora.stream/embed/c74c438d-dfba-4b2d-845b-c2e471f5d1e3"
          width="720" height="300" allowfullscreen></iframe>
  <div class="gallery-item"><img src="https://cdn.example.com/01.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/02.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/03.jpg"></div>
</div>
</body></html>
''';

/// The shape the boss described: photos, video in the middle, photos again.
const _embedInMiddleHtml = '''
<html><body>
<div class="entry-content single-page">
  <div class="gallery-item"><img src="https://cdn.example.com/01.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/02.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/03.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/04.jpg"></div>
  <iframe src="https://cossora.stream/embed/aaa" allowfullscreen></iframe>
  <div class="gallery-item"><img src="https://cdn.example.com/05.jpg"></div>
  <div class="gallery-item"><img src="https://cdn.example.com/06.jpg"></div>
</div>
</body></html>
''';

/// A video-only chapter: nothing to be positioned between.
const _videoOnlyHtml = '''
<html><body>
<div class="entry-content single-page">
  <iframe src="https://cossora.stream/embed/bbb" allowfullscreen></iframe>
</div>
</body></html>
''';

/// The embed is inside the gallery, next to a promo from the same host.
const _promoOutsideHtml = '''
<html><body>
<div class="ad-slot"><iframe src="https://ads.example.com/promo.html"></iframe></div>
<div class="entry-content single-page">
  <div class="gallery-item"><img src="https://cdn.example.com/01.jpg"></div>
  <iframe src="https://cossora.stream/embed/ccc" allowfullscreen></iframe>
  <div class="gallery-item"><img src="https://cdn.example.com/02.jpg"></div>
</div>
</body></html>
''';

Map<String, dynamic> _config({
  String imageSelector = '.entry-content.single-page .gallery-item img',
  String container = '.entry-content.single-page',
  String videoSelector = 'iframe[src]',
}) =>
    <String, dynamic>{
      'images': {'selector': imageSelector, 'attribute': 'src'},
      'video': {
        'container': container,
        'selector': videoSelector,
        'attribute': 'src',
      },
    };

ReaderImageResolver _resolver() => ReaderImageResolver(
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'cosplaytele',
    );

void main() {
  final resolver = _resolver();

  group('the stream sits where the site put it', () {
    test('an embed above every photo reports index 0', () {
      final result = resolver.extractVideoPlacement(_embedFirstHtml, _config());

      expect(result.urls, [
        'https://cossora.stream/embed/c74c438d-dfba-4b2d-845b-c2e471f5d1e3'
      ]);
      expect(
        result.index,
        0,
        reason: 'no photo precedes the embed, so the card is first',
      );
    });

    test('an embed after four photos reports index 4', () {
      final result =
          resolver.extractVideoPlacement(_embedInMiddleHtml, _config());

      expect(result.urls, isNotEmpty);
      expect(
        result.index,
        4,
        reason: 'four pages come before the embed',
      );
    });

    test('a video-only chapter still reports 0 — nothing to be between', () {
      final result = resolver.extractVideoPlacement(_videoOnlyHtml, _config());

      expect(result.urls, hasLength(1));
      expect(result.index, 0);
    });

    test('an embed outside the gallery cannot shift the position', () {
      final result =
          resolver.extractVideoPlacement(_promoOutsideHtml, _config());

      expect(
        result.urls,
        ['https://cossora.stream/embed/ccc'],
        reason: 'the ad slot is outside the container',
      );
      expect(
        result.index,
        1,
        reason:
            'one gallery photo precedes the embed; the promo must not count',
      );
    });
  });

  group('no position when the config cannot attribute one', () {
    test('a config without a video block keeps the legacy page-wide scan', () {
      // The legacy regex cannot see an embed, and a page-wide scan has no
      // position to attribute — the reader falls back to the end of chapter.
      final result = resolver.extractVideoPlacement(
        _embedFirstHtml,
        <String, dynamic>{
          'images': {
            'selector': '.entry-content.single-page .gallery-item img',
            'attribute': 'src',
          },
        },
      );

      expect(result.urls, isEmpty, reason: 'no .m3u8 on the page at all');
      expect(result.index, isNull);
    });

    test('an unscoped video block has no position either', () {
      final result = resolver.extractVideoPlacement(
        _embedFirstHtml,
        _config(container: ''),
      );

      expect(result.index, isNull,
          reason: 'unscoped harvest ⇒ page-wide, nothing to count against');
    });

    test('a missing image selector leaves the position unknown', () {
      final result = resolver.extractVideoPlacement(
        _embedFirstHtml,
        <String, dynamic>{
          'video': {
            'container': '.entry-content.single-page',
            'selector': 'iframe[src]',
            'attribute': 'src',
          },
        },
      );

      expect(result.urls, isNotEmpty);
      expect(result.index, isNull);
    });
  });

  group('end to end through the adapter', () {
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
        sourceId: 'cosplaytele',
      );
    });

    test('a chapter reports both the pages and where the card goes', () async {
      dioAdapter.onGet(
        '$_baseUrl/gallery/hiyuki-2/',
        (s) => s.reply(200, _embedFirstHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter = await adapter.fetchChapterImages(
        'gallery/hiyuki-2/',
        <String, dynamic>{
          'source': 'cosplaytele',
          'baseUrl': _baseUrl,
          'scraper': {
            'urlPatterns': {
              'detail': '/{id}/',
              'chapter': '/{id}',
            },
            'selectors': {
              'detail': {
                'fields': {
                  'title': {'selector': 'h1'},
                },
              },
              'reader': _config(),
            },
          },
        },
      );

      expect(chapter, isNotNull);
      expect(chapter!.images, hasLength(3));
      expect(chapter.videoUrls, hasLength(1));
      expect(
        chapter.videoIndex,
        0,
        reason: 'the reader inserts the card as item 0, above every page',
      );
      // A gallery with pages is never the video-only surface.
      expect(
        chapter.images.isEmpty && chapter.videoUrls.isNotEmpty,
        isFalse,
      );
    });
  });

  group('live gallery: 110 photos and 1 video', () {
    // The shape that started this: cosplaytele's chapter pages title themselves
    // "<n> photos and 1 video" and put the embed ABOVE the gallery. Before
    // `reader.video` the embed was invisible (a cross-origin iframe carries no
    // `.m3u8`, so the legacy page-wide regex could never see it) and the card
    // had no way to know where it belonged.
    test('the shipped block finds the embed and puts it at slot 0', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      final adapter = GenericScraperAdapter(
        dio: dio,
        urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'cosplaytele',
      );
      final html =
          File('test/fixtures/cosplaytele_hiyuki2.html').readAsStringSync();
      dioAdapter.onGet(
        '$_baseUrl/hiyuki-2/',
        (s) => s.reply(200, html, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );

      final chapter = await adapter.fetchChapterImages(
        'hiyuki-2/',
        <String, dynamic>{
          'source': 'cosplaytele',
          'baseUrl': _baseUrl,
          'scraper': {
            'urlPatterns': {'detail': '/{id}/', 'chapter': '/{id}'},
            'selectors': {
              'detail': {
                'fields': {
                  'title': {'selector': 'h1'},
                },
              },
              'reader': {
                'container': '.entry-content.single-page',
                'images': {
                  'selector': '.entry-content.single-page .gallery-item img',
                  'attribute': 'src',
                },
                'video': {
                  'container': '.entry-content.single-page',
                  // Host-qualified: the page also carries GTM and ad iframes.
                  'selector': 'iframe[src*="cossora.stream"]',
                  'attribute': 'src',
                },
              },
            },
          },
        },
      );

      expect(chapter, isNotNull);
      expect(
        chapter!.images,
        hasLength(110),
        reason: 'the page titles itself "110 photos and 1 video"',
      );
      expect(chapter.videoUrls, [
        'https://cossora.stream/embed/c74c438d-dfba-4b2d-845b-c2e471f5d1e3',
      ]);
      expect(
        chapter.videoIndex,
        0,
        reason: 'the embed sits above every photo on the site',
      );
      expect(
        chapter.images.where((u) => u.startsWith('data:')),
        isEmpty,
        reason: 'a lazy-load placeholder reached the reader',
      );
      // 110 pages + a stream: the pager stays, the card is its first item.
      expect(
        chapter.images.isEmpty && chapter.videoUrls.isNotEmpty,
        isFalse,
      );
    });
  });

  group('the origin the player must be shown as', () {
    // cossora.stream answers `{"error":true,"message":"Unknown Error xD"}`
    // unless the request carries the embedder's origin as Referer, and it
    // validates the host — `example.com` is rejected, cosplaytele.com is not.
    // Custom Tabs cannot send headers, so the reader needs this value to route
    // playback through the plugin's own WebView instead.
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    Map<String, dynamic> configWithVideoBlock(Map<String, dynamic> video) => {
          'source': 'cosplaytele',
          'baseUrl': _baseUrl,
          'scraper': {
            'urlPatterns': {'detail': '/{id}/', 'chapter': '/{id}'},
            'selectors': {
              'detail': {
                'fields': {
                  'title': {'selector': 'h1'},
                },
              },
              'reader': {
                'container': '.entry-content.single-page',
                'images': {
                  'selector': '.entry-content.single-page .gallery-item img',
                  'attribute': 'src',
                },
                'video': video,
              },
            },
          },
        };

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = GenericScraperAdapter(
        dio: dio,
        urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'cosplaytele',
      );
      dioAdapter.onGet(
        '$_baseUrl/hiyuki-2/',
        (s) => s.reply(200, _embedFirstHtml, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        }),
      );
    });

    test('a declared referer reaches the chapter data', () async {
      final chapter = await adapter.fetchChapterImages(
        'hiyuki-2/',
        configWithVideoBlock({
          'container': '.entry-content.single-page',
          'selector': 'iframe[src]',
          'attribute': 'src',
          'referer': 'https://cosplaytele.com/',
        }),
      );

      expect(chapter?.videoReferer, 'https://cosplaytele.com/');
    });

    test('without one the chapter page itself is the origin', () async {
      final chapter = await adapter.fetchChapterImages(
        'hiyuki-2/',
        configWithVideoBlock({
          'container': '.entry-content.single-page',
          'selector': 'iframe[src]',
          'attribute': 'src',
        }),
      );

      expect(
        chapter?.videoReferer,
        '$_baseUrl/hiyuki-2/',
        reason: 'the page that framed the player is the truthful default',
      );
    });

    test('a chapter with no video carries no origin', () async {
      final chapter = await adapter.fetchChapterImages(
        'hiyuki-2/',
        configWithVideoBlock({
          'container': '.entry-content.single-page',
          'selector': 'iframe[src="https://ads.example/promo.html"]',
          'attribute': 'src',
        }),
      );

      expect(chapter?.videoUrls, isEmpty);
      expect(
        chapter?.videoReferer,
        isNull,
        reason: 'nothing to play means nothing to present an origin for',
      );
    });
  });
}
