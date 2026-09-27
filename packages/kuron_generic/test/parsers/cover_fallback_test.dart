// Regression test for image lazy-load fallback via `data-default-src`.
// FIFU-mature cards (e.g. mangadistrict) serve an inline SVG placeholder in
// `src` with the real thumbnail in `data-default-src`. The parser must skip
// the `data:` placeholder and pick up the fallback attribute.
// Run with:
//   dart test packages/kuron_generic/test/parsers/cover_fallback_test.dart
library;

import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _svgSrc =
    'data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%201%201%22%2F%3E';
const _realCover = 'https://cdn.example.com/thumbnail/moby-dick-official.webp';

const _html = '''
<html><body>
<div class="page-item-detail">
  <div class="item-thumb"><a href="https://m.example.com/series/moby-dick/">
    <img alt="Moby Dick" width="340" height="476"
      data-default-src="$_realCover"
      src="$_svgSrc" class="img-responsive"/>
  </a></div>
  <div class="post-title"><h3><a href="https://m.example.com/series/moby-dick/">Moby Dick</a></h3></div>
</div>
<div class="page-item-detail">
  <div class="item-thumb"><a href="https://m.example.com/series/plain-joe/">
    <img alt="Plain Joe" width="340" height="476"
      src="https://cdn.example.com/thumbnail/plain-joe.webp" class="img-responsive"/>
  </a></div>
  <div class="post-title"><h3><a href="https://m.example.com/series/plain-joe/">Plain Joe</a></h3></div>
</div>
</body></html>
''';

void main() {
  group('GenericHtmlParser image fallback', () {
    late GenericHtmlParser parser;

    setUp(() {
      parser = GenericHtmlParser(logger: Logger(level: Level.off));
    });

    test('picks data-default-src over inline SVG placeholder', () {
      final doc = parser.parse(_html);
      final covers = parser.extractList(
        doc,
        const FieldSelector(selector: '.item-thumb img', attribute: 'src'),
      );
      expect(
        covers,
        [_realCover, 'https://cdn.example.com/thumbnail/plain-joe.webp'],
      );
    });
  });
}
