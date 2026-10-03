// Regression tests for issue #65 (image attribute fallback chain),
// #67 (script-JSON image arrays) and #68 (video/HLS reader).
//
// Run with:
//   fvm flutter test packages/kuron_generic/test/readers/reader_attribute_chain_test.dart
library;

import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

ReaderImageResolver _resolver() => ReaderImageResolver(
      urlBuilder: const GenericUrlBuilder(baseUrl: 'https://example.com'),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'test',
    );

const _svgPlaceholder =
    'data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2E%3E';

/// Mixed lazy/non-lazy markup: one img carries the real URL only in
/// `data-src` (lazy), the next only in `src` (plain). A single-attribute
/// selector can only ever serve one of the two.
const _mixedHtml = '''
<html><body>
  <div class="reader-images">
    <img class="page" data-src="https://cdn.example.com/001.jpg"
         src="$_svgPlaceholder"/>
    <img class="page" src="https://cdn.example.com/002.jpg"/>
  </div>
</body></html>
''';

void main() {
  group('#65 attribute fallback chain', () {
    late GenericHtmlParser parser;

    setUp(() {
      parser = GenericHtmlParser(logger: Logger(level: Level.off));
    });

    test('list attribute reads lazy data-src and plain src', () {
      final doc = parser.parse(_mixedHtml);
      final urls = parser.extractList(
        doc,
        FieldSelector.fromMap({
          'selector': '.reader-images img.page',
          'type': 'css',
          'attribute': ['data-src', 'src'],
        }),
      );
      expect(urls, [
        'https://cdn.example.com/001.jpg',
        'https://cdn.example.com/002.jpg',
      ]);
    });

    test('string attribute chain skips to first non-empty', () {
      final doc = parser.parse(_mixedHtml);
      expect(
        parser.extractString(
          doc,
          FieldSelector.fromMap({
            'selector': 'img.page',
            'type': 'css',
            'attribute': ['data-src', 'src'],
          }),
        ),
        'https://cdn.example.com/001.jpg',
      );
    });

    test('chain short-circuits at first populated attribute', () {
      final doc = parser.parse(
        '<div><a href="https://a/1" data-href="https://a/2">x</a></div>',
      );
      expect(
        parser.extractString(
          doc,
          const FieldSelector(
            selector: 'a',
            type: 'css',
            attributes: ['href', 'data-href'],
          ),
        ),
        'https://a/1',
      );
      expect(
        parser.extractString(
          doc,
          const FieldSelector(
            selector: 'a',
            type: 'css',
            attributes: ['data-href', 'href'],
          ),
        ),
        'https://a/2',
      );
    });

    test('plain string attribute behaves exactly as before', () {
      final doc = parser.parse(_mixedHtml);
      // Legacy single-attribute selector: lazy img falls through the
      // built-in lazy-load list, plain img uses src directly.
      expect(
        parser.extractList(
          doc,
          const FieldSelector(
            selector: '.reader-images img.page',
            type: 'css',
            attribute: 'src',
          ),
        ),
        [
          'https://cdn.example.com/001.jpg',
          'https://cdn.example.com/002.jpg',
        ],
      );
    });

    test('FieldSelector.fromMap keeps first chain entry as attribute', () {
      final chain = FieldSelector.fromMap({
        'selector': 'img',
        'attribute': ['data-src', 'src'],
      });
      expect(chain.attribute, 'data-src');
      expect(chain.attributeChain, ['data-src', 'src']);

      final single = FieldSelector.fromMap({
        'selector': 'img',
        'attribute': 'src',
      });
      expect(single.attributes, isEmpty);
      expect(single.attributeChain, ['src']);

      final none = FieldSelector.fromMap({'selector': 'img'});
      expect(none.attributeChain, isEmpty);
    });

    test('reader field def map builds a chain selector', () {
      final sel = _resolver().fieldDefToSelector({
        'selector': 'img',
        'attribute': ['data-src', 'src'],
      });
      expect(sel?.attributeChain, ['data-src', 'src']);
      expect(
          _resolver().fieldDefToSelector({
            'selector': 'img',
            'attribute': 'data-src',
          })?.attributeChain,
          ['data-src']);
    });
  });

  group('#67 script-JSON image arrays', () {
    test('reads a JS variable object (hentailoop var ajax.pages)', () {
      final urls = _resolver().extractScriptJsonImages(
        '<script>var ajax = {"pages":'
        '["https://h/1.jpg","https://h/2.jpg"], "title":"x"};</script>',
        scriptId: 'ajax',
        itemsKey: 'pages',
        urlKey: '',
      );
      expect(urls, ['https://h/1.jpg', 'https://h/2.jpg']);
    });

    test('reads a flat JS array (decadence chapter_preloaded_images)', () {
      // `urlKey: 'src'` is the config default — a flat string array must
      // still resolve, the entry IS the URL.
      final urls = _resolver().extractScriptJsonImages(
        '<script>var chapter_preloaded_images = '
        '["https://d/001.jpg", "https://d/002.jpg"];</script>',
        scriptId: 'chapter_preloaded_images',
        itemsKey: '',
        urlKey: 'src',
      );
      expect(urls, ['https://d/001.jpg', 'https://d/002.jpg']);
    });

    test('element-with-id path still works and supports map items', () {
      final urls = _resolver().extractScriptJsonImages(
        '<script type="application/json" id="h4f-r2-data">'
        '{"images":[{"src":"https://h4f/1.webp"},{"src":"https://h4f/1.webp"}]}'
        '</script>',
        scriptId: 'h4f-r2-data',
        itemsKey: 'images',
        urlKey: 'src',
      );
      expect(urls, ['https://h4f/1.webp']);
    });

    test('brace/quote aware body capture survives nested objects', () {
      final urls = _resolver().extractScriptJsonImages(
        '<script>var pages = ["https://h/1.jpg"]; '
        'var other = {"a":"not-a-url"};</script>',
        scriptId: 'pages',
        itemsKey: '',
        urlKey: '',
      );
      expect(urls, ['https://h/1.jpg']);
    });

    test('missing variable returns empty, no throw', () {
      expect(
        _resolver().extractScriptJsonImages(
          '<html></html>',
          scriptId: 'ajax',
          itemsKey: 'pages',
          urlKey: '',
        ),
        isEmpty,
      );
    });
  });

  group('#68 video / HLS detection', () {
    test('finds HLS and mp4 sources in chapter html', () {
      const html = '''
        <div class="reading-content">
          <video poster="https://cdn/poster.jpg">
            <source src="https://cdn/hls/master.m3u8" type="application/x-mpegURL">
            <source src="https://cdn/video/clip.mp4" type="video/mp4">
          </video>
          <img src="https://cdn/001.jpg">
        </div>''';
      expect(
        _resolver().extractChapterVideoUrls(html),
        ['https://cdn/hls/master.m3u8', 'https://cdn/video/clip.mp4'],
      );
    });

    test('no video in an image chapter', () {
      expect(
        _resolver().extractChapterVideoUrls(
          '<div><img src="https://cdn/001.jpg"></div>',
        ),
        isEmpty,
      );
    });

    test('pwa .webmanifest link is not a video (hentai4free ghost card)', () {
      const html = '''
        <head>
          <link rel="manifest" href="https://hentai4free.net/h4f-pwa-manifest.webmanifest?rev=20260908-1">
        </head>
        <div><img src="https://cdn/001.jpg"></div>''';
      expect(_resolver().extractChapterVideoUrls(html), isEmpty);
    });

    test('video url with query string still matches', () {
      expect(
        _resolver().extractChapterVideoUrls(
          '<video><source src="https://cdn/clip.mp4?token=abc"></video>',
        ),
        ['https://cdn/clip.mp4?token=abc'],
      );
    });

    test('normalize drops video urls scraped by a broad selector', () {
      expect(
        _resolver().normalizeChapterImageUrls([
          'https://cdn/hls/master.m3u8',
          'https://cdn/video/clip.mp4',
          'https://cdn/001.jpg',
        ]),
        ['https://cdn/001.jpg'],
      );
    });
  });
}
