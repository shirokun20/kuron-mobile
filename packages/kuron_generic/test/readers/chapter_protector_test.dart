import 'dart:io';

import 'package:kuron_generic/src/readers/chapter_protector.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

// Real capture: octopusmanga.com/manga/alphas-trauma/chapter-48/ (mobile UA),
// 2026-09-27. Payload decrypts to 15 reader-CDN image URLs.
const _expectedPrefix =
    'https://octopusmanga.com/wp-content/uploads/WP-manga/data/'
    'manga_670dc3a015b3a/feb8d921babcd999796788e7e907aedf/';

ChapterProtectorDecoder _decoder() => ChapterProtectorDecoder(
      logger: Logger(level: Level.off),
      sourceId: 'octopusmanga',
    );

String? _readFixture() {
  const candidates = [
    'packages/kuron_generic/test/fixtures/'
        'octopusmanga_chapter_protector.html',
    '../packages/kuron_generic/test/fixtures/'
        'octopusmanga_chapter_protector.html',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  return null;
}

void main() {
  group('ChapterProtectorDecoder', () {
    test('decrypts the captured octopusmanga payload to its 15 image URLs', () {
      final html = _readFixture();
      if (html == null) {
        markTestSkipped('Missing fixture: '
            'packages/kuron_generic/test/fixtures/'
            'octopusmanga_chapter_protector.html');
        return;
      }

      final urls = _decoder().extractImageUrls(html);

      expect(urls, hasLength(15));
      expect(urls.first, '${_expectedPrefix}1-(1).jpg');
      expect(urls[7], '${_expectedPrefix}1-(8).jpg');
      expect(urls.last, '${_expectedPrefix}1-(15).jpg');
      // Sanity: the page itself has no usable <img> in .theimage — only loaders.
      expect(html.contains('dot-floating'), isTrue);
    });

    test('returns empty when the page has no protector payload', () {
      const html = '<html><body><div class="theimage">'
          '<img src="https://example.com/1.jpg"/></div></body></html>';
      expect(_decoder().extractImageUrls(html), isEmpty);
    });

    test('returns empty when the payload is garbled (no nonce)', () {
      const html = '<script id="chapter-protector-data">'
          "var chapter_data='{\"ct\":\"AAAA\",\"s\":\"2ee849522b8c8724\"}';"
          '</script>';
      expect(_decoder().extractImageUrls(html), isEmpty);
    });

    test('returns empty on a bad salt instead of throwing', () {
      const html = '<script id="chapter-protector-data">'
          "var chapter_data='{\"ct\":\"AAAA\",\"s\":\"zz\"}';"
          "var wpmangaprotectornonce='a1816aa470';"
          '</script>';
      expect(_decoder().extractImageUrls(html), isEmpty);
    });
  });
}
