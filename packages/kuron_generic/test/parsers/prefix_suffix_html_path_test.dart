// Regression test for the HTML-path prefix/suffix sync gap (#53).
//
// `FieldSelector.prefix`/`suffix` were honored by the JSON parser only;
// every HTML consumer dropped them:
//   1. `GenericHtmlParser.extractString` / `extractList` never applied them.
//   2. `ReaderImageResolver.fieldDefToSelector` rebuilt the selector without
//      them, so a config prefix never reached the reader.
//   3. `GenericScraperAdapter`'s container-scoped + pagination FieldSelector
//      reconstructions (`'$containerSel ${sel.selector}'`) dropped them.
//   4. `sanitizeImageUrl` resolved `/abs` but not bare relatives
//      (`upload/pages/1.jpg`), leaving covers non-absolute.
//
// Each test below fails without the corresponding fix.
// Run with:
//   dart test packages/kuron_generic/test/parsers/prefix_suffix_html_path_test.dart
library;

import 'package:kuron_generic/src/models/source_config_runtime.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/readers/reader_image_resolver.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hentairead.test';

const _html = '''
<html><body>
<div class="item-thumb"><img src="upload/pages/2026/09/001.jpg"></div>
</body></html>
''';

ReaderImageResolver _resolver() => ReaderImageResolver(
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'hentairead',
    );

void main() {
  late GenericHtmlParser parser;

  setUp(() {
    parser = GenericHtmlParser(logger: Logger(level: Level.off));
  });

  group('#53 prefix/suffix on the HTML path', () {
    test('extractList applies prefix and suffix to every value', () {
      final doc = parser.parse(_html);
      final values = parser.extractList(
        doc,
        const FieldSelector(
          selector: '.item-thumb img',
          attribute: 'src',
          prefix: 'https://cdn.test/',
          suffix: '?v=1',
        ),
      );
      expect(
        values,
        ['https://cdn.test/upload/pages/2026/09/001.jpg?v=1'],
      );
    });

    test('extractString applies prefix only, regex path too', () {
      final doc = parser.parse(
        '<html><body><span class="slug">my-manga</span></body></html>',
      );
      expect(
        parser.extractString(
          doc,
          const FieldSelector(
              selector: '.slug', prefix: 'https://site.test/'),
        ),
        'https://site.test/my-manga',
      );
      // regex branch must apply affixes to the MATCH, not the raw text.
      expect(
        parser.extractString(
          doc,
          const FieldSelector(
            selector: '.slug',
            regex: r'manga',
            prefix: '<',
            suffix: '>',
          ),
        ),
        '<manga>',
      );
    });

    test('null affixes leave values untouched (batch-1 parity)', () {
      final doc = parser.parse(_html);
      expect(
        parser.extractList(
          doc,
          const FieldSelector(selector: '.item-thumb img', attribute: 'src'),
        ),
        ['upload/pages/2026/09/001.jpg'],
      );
    });
  });

  group('#53 prefix carried by fieldDefToSelector', () {
    test('reader selector rebuild keeps prefix/suffix', () {
      final sel = _resolver().fieldDefToSelector({
        'selector': '.item-thumb img',
        'attribute': 'src',
        'prefix': 'https://cdn.test/',
        'suffix': '?v=1',
      });
      expect(sel, isNotNull);
      expect(sel!.prefix, 'https://cdn.test/');
      expect(sel.suffix, '?v=1');
    });
  });

  group('#53 bare-relative sanitize', () {
    test('resolves bare relative against baseUrl (hentairead cover shape)', () {
      final r = _resolver();
      expect(
        r.sanitizeImageUrl('upload/pages/2026/09/001.jpg'),
        '$_baseUrl/upload/pages/2026/09/001.jpg',
      );
    });

    test('prefix turns the bare relative absolute; no double-slash', () {
      final r = _resolver();
      // With a config prefix (the shipped hentairead shape) the parser hands
      // the resolver an absolute URL — that must stay untouched.
      expect(
        r.sanitizeImageUrl('https://hentairead.io/upload/pages/1.jpg'),
        'https://hentairead.io/upload/pages/1.jpg',
      );
      // Leading-slash relatives keep the single-slash join.
      expect(
        r.sanitizeImageUrl('/upload/pages/1.jpg'),
        '$_baseUrl/upload/pages/1.jpg',
      );
      // Unrelated hosts untouched.
      expect(
        r.sanitizeImageUrl('https://other.test/1.jpg'),
        'https://other.test/1.jpg',
      );
    });
  });
}
