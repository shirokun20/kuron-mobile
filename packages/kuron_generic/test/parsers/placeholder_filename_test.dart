// Regression tests for placeholder filename detection in
// `GenericHtmlParser._resolveAttributeChain`.
//
// Lazy-load themes serve a placeholder in `src` (e.g. Madara `dflazy.jpg`,
// `blank.gif`, `transparent.png`) with the real image in `data-src`.
// The parser must treat the placeholder as empty so the fallback chain
// picks up the real URL, while genuine `src` values are kept as-is.
//
// Run with:
//   fvm flutter test packages/kuron_generic/test/parsers/placeholder_filename_test.dart
library;

import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _realCover = 'https://x/real-cover.jpg';

String _htmlFor({required String src, String? dataSrc}) {
  final dataAttr = dataSrc == null ? '' : '\n      data-src="$dataSrc"';
  return '''
<html><body>
  <div class="item-thumb">
    <img src="$src"$dataAttr class="img-responsive"/>
  </div>
</body></html>
''';
}

List<String> _covers(GenericHtmlParser parser, String html) {
  final doc = parser.parse(html);
  return parser.extractList(
    doc,
    const FieldSelector(selector: '.item-thumb img', attribute: 'src'),
  );
}

void main() {
  group('GenericHtmlParser placeholder filenames', () {
    late GenericHtmlParser parser;

    setUp(() {
      parser = GenericHtmlParser(logger: Logger(level: Level.off));
    });

    test('madara dflazy src falls back to data-src', () {
      final covers = _covers(
        parser,
        _htmlFor(
          src: 'https://x/wp-content/themes/madara/images/dflazy.jpg',
          dataSrc: _realCover,
        ),
      );
      expect(covers, [_realCover]);
    });

    test('genuine lazy-path src without fallback is kept', () {
      const src = '/lazy/gallery/real.jpg';
      final covers = _covers(parser, _htmlFor(src: src));
      expect(covers, [src]);
    });

    test('blank.gif with query string falls back to data-src', () {
      final covers = _covers(
        parser,
        _htmlFor(src: 'blank.gif?v=2', dataSrc: _realCover),
      );
      expect(covers, [_realCover]);
    });

    test('optimizer _result src with query string falls back to data-src', () {
      final covers = _covers(
        parser,
        _htmlFor(src: 'Ideal-(1)_result.jpg?v=2', dataSrc: _realCover),
      );
      expect(covers, [_realCover]);
    });

    test('common placeholder filenames fall back to data-src', () {
      const placeholders = [
        'transparent.png',
        'placeholder.jpg',
        'loading.gif',
        'grey.jpg',
        '1x1.png',
        'pixel.gif',
        'https://x/assets/placeholder.svg',
      ];
      for (final src in placeholders) {
        final covers = _covers(
          parser,
          _htmlFor(src: src, dataSrc: _realCover),
        );
        expect(covers, [_realCover], reason: 'src=$src');
      }
    });
  });
}
