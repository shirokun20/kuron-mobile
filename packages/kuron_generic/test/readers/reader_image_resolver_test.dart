import 'package:html/parser.dart' show parse;
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/readers/reader_image_resolver.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

ReaderImageResolver _resolver() => ReaderImageResolver(
      urlBuilder: const GenericUrlBuilder(baseUrl: 'https://example.com'),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'test',
    );

void main() {
  group('ReaderImageResolver pure modes', () {
    test('decodeBase64 round-trips padded input, null on garbage', () {
      final r = _resolver();
      expect(r.decodeBase64('aGVsbG8='), 'hello');
      expect(r.decodeBase64('!!!not-base64!!!'), isNull);
    });

    test('decodeMaybeBase64Url passes https through, decodes, drops junk',
        () {
      final r = _resolver();
      expect(
        r.decodeMaybeBase64Url('https://a/1.jpg'),
        'https://a/1.jpg',
      );
      expect(r.decodeMaybeBase64Url('aGVsbG8='), isNull);
      expect(r.decodeMaybeBase64Url('!!!'), isNull);
    });

    test('inferImageExtension defaults and detects', () {
      final r = _resolver();
      expect(r.inferImageExtension(null), 'jpg');
      expect(r.inferImageExtension(''), 'jpg');
      expect(r.inferImageExtension('https://h/p/x.PNG?q=1'), 'png');
      expect(r.inferImageExtension('https://h/p/12t.webp'), 'webp');
    });

    test('hentaifox builder maps per-page extensions', () {
      final r = _resolver();
      expect(
        r.buildHentaiFoxImageUrlsFromSample(
          'https://h1.hentaifox.com/img/1.jpg',
          3,
          {2: 'webp'},
        ),
        [
          'https://h1.hentaifox.com/img/1.jpg',
          'https://h1.hentaifox.com/img/2.webp',
          'https://h1.hentaifox.com/img/3.jpg',
        ],
      );
      expect(r.buildHentaiFoxImageUrlsFromSample('', 3, {}), isEmpty);
      expect(
        r.buildHentaiFoxImageUrlsFromSample('https://h/i.jpg', 0, {}),
        isEmpty,
      );
    });

    test('hentaifox extensions parse g_th map', () {
      final r = _resolver();
      expect(
        r.extractHentaiFoxExtensionsByPage(
          '<script>var g_th = '
          '\$.parseJSON(\'{"1":"j,x","2":"w,y"}\');</script>',
        ),
        {1: 'jpg', 2: 'webp'},
      );
      expect(r.extractHentaiFoxExtensionsByPage(''), isEmpty);
      expect(r.extractHentaiFoxExtensionsByPage('<html></html>'), isEmpty);
    });

    test('script slides extract https items, [] without marker', () {
      final r = _resolver();
      expect(
        r.extractScriptSlidesImageUrls(
          '<script>slides_p_path = [\'https://a/1.jpg\'];</script>',
        ),
        ['https://a/1.jpg'],
      );
      expect(r.extractScriptSlidesImageUrls('<html></html>'), isEmpty);
    });

    test('preview CDN scan dedups hencover urls', () {
      final r = _resolver();
      const html = 'a https://hencover.xyz/preview/x.jpg b '
          'https://hencover.xyz/preview/x.jpg';
      expect(
        r.extractPreviewCdnImageUrls(html),
        ['https://hencover.xyz/preview/x.jpg'],
      );
      expect(r.extractPreviewCdnImageUrls('nothing'), isEmpty);
    });

    test('sanitize strips quotes, fixes hosts, resolves, upgrades', () {
      final r = _resolver();
      expect(r.sanitizeImageUrl('"https://a/1.jpg"'), 'https://a/1.jpg');
      expect(
        r.sanitizeImageUrl(r'https:\/\/a\/1.jpg'),
        'https://a/1.jpg',
      );
      expect(
        r.sanitizeImageUrl('//cdn.example.com/1.jpg'),
        'https://cdn.example.com/1.jpg',
      );
      expect(
        r.sanitizeImageUrl('/images/node/1.avif'),
        'https://example.com/images/node/1.avif',
      );
      expect(
        r.sanitizeImageUrl('http://example.com/1.jpg'),
        'https://example.com/1.jpg',
      );
      // Different host over http stays untouched.
      expect(
        r.sanitizeImageUrl('http://other.com/1.jpg'),
        'http://other.com/1.jpg',
      );
    });

    test('normalize expands json arrays and dedups', () {
      final r = _resolver();
      expect(
        r.normalizeChapterImageUrls(
          ['["https://a/1.jpg"]', 'https://a/1.jpg', ''],
        ),
        ['https://a/1.jpg'],
      );
      expect(r.normalizeChapterImageUrls([]), isEmpty);
    });

    test('decodeChaoticPayload null without key or push', () {
      final r = _resolver();
      expect(r.decodeChaoticPayload('<html></html>', key: null), isNull);
      expect(r.decodeChaoticPayload('<html></html>', key: ''), isNull);
      expect(
        r.decodeChaoticPayload('<html><body>no push</body></html>', key: 'k'),
        isNull,
      );
    });

    test('ajax fields honor required vs optional', () {
      final r = _resolver();
      final doc = parse(
        '<html><body><img id="cap" src="tok123"></body></html>',
      );
      expect(
        r.extractAjaxRequestFields(
          readerDocument: doc,
          requestConfig: {
            'must': {
              'cap': {
                'selector': '#missing',
                'attribute': 'src',
                'required': true,
              },
            },
          },
          fieldGroup: 'must',
        ),
        isNull,
      );
      expect(
        r.extractAjaxRequestFields(
          readerDocument: doc,
          requestConfig: {
            'cap': {
              'cap': {
                'selector': '#cap',
                'attribute': 'src',
                'required': true,
              },
              'fixed': 'const-value',
            },
          },
          fieldGroup: 'cap',
        ),
        {'cap': 'tok123', 'fixed': 'const-value'},
      );
    });
  });
}
