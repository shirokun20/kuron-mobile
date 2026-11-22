// Global whitespace normalization for every HTML text-extraction path.
//
// Regression: a title like "Komik\n   Indo" reached DetailTitleSection with
// an awkward line break, and the one-line Reader app bar clipped it to
// "Komik". `trim()` alone never fixed internal newlines/repeated spaces.
library;

import 'package:html/parser.dart' as html_parser;
import 'package:kuron_generic/src/models/source_config_runtime.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

void main() {
  late GenericHtmlParser parser;

  setUp(() => parser = GenericHtmlParser(logger: Logger()));

  const dirty = '  Komik\n   Indo   Chapter 1  ';
  const clean = 'Komik Indo Chapter 1';

  test('extractString (no regex) collapses newlines and repeated spaces', () {
    final doc = html_parser.parse('<h1 class="title">$dirty</h1>');
    final result = parser.extractString(
      doc,
      const FieldSelector(selector: 'h1.title', type: 'css'),
    );
    expect(result, clean);
  });

  test('extractString (regex branch) normalizes before matching', () {
    final doc = html_parser.parse('<h1 class="title">$dirty</h1>');
    final result = parser.extractString(
      doc,
      const FieldSelector(
        selector: 'h1.title',
        type: 'css',
        regex: r'Komik\s+Indo\s+Chapter\s+(\d+)',
      ),
    );
    expect(result, '1');
  });

  test('extractList normalizes each extracted value', () {
    final doc = html_parser.parse(
      '<div class="titles"><span>$dirty</span><span>$dirty</span></div>',
    );
    final result = parser.extractList(
      doc,
      const FieldSelector(selector: '.titles span', type: 'css'),
    );
    expect(result, [clean, clean]);
  });

  test('extractFromElement normalizes element text', () {
    final doc = html_parser.parse('<div class="wrap"><h2>$dirty</h2></div>');
    final element = doc.querySelector('.wrap')!;
    final result = parser.extractFromElement(
      element,
      const FieldSelector(selector: 'h2', type: 'css'),
    );
    expect(result, clean);
  });

  test('non-breaking spaces are collapsed too', () {
    final doc = html_parser.parse('<h1>A\u00a0\u00a0B</h1>');
    final result = parser.extractString(
      doc,
      const FieldSelector(selector: 'h1', type: 'css'),
    );
    expect(result, 'A B');
  });
}
