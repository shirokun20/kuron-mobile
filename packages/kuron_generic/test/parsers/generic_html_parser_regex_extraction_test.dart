// Unit tests for [GenericHtmlParser] regex extraction on multi-fields.
///
// This test suite validates that:
// 1. extractList() applies regex to each element when multi: true
// 2. Tag extraction works correctly with patterns like "tagname (count)"
// 3. Single string extraction applies regex correctly
// 4. Regex capture groups (group 1) are extracted properly
// 5. Elements that don't match regex are filtered out
///
// Example use case (HentaiNexus):
// HTML: `<span class="tag"><a>ahegao (123)</a></span>`
// Selector: `span.tag a`
// Regex: `^([a-z0-9 ]+)\s+\(`
// Expected: `["ahegao"]`
///
// Run with:
//   dart test packages/kuron_generic/test/parsers/generic_html_parser_regex_extraction_test.dart
library;

import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:kuron_generic/src/models/source_config_runtime.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

void main() {
  final logger = Logger();
  late GenericHtmlParser parser;

  setUp(() {
    parser = GenericHtmlParser(logger: logger);
  });

  /// Returns the HentaiNexus detail fixture, or `null` when it is absent.
  ///
  /// The fixture lives under `informations/`, which is gitignored
  /// (.gitignore line 69), so it is unavailable on a clean checkout.
  String? readFixtureHtml() {
    const candidates = <String>[
      'packages/kuron_generic/test/fixtures/nexus/html-halaman-detail.html',
      'informations/documentation/nexus/html-halaman-detail.html',
      '../informations/documentation/nexus/html-halaman-detail.html',
      '../../informations/documentation/nexus/html-halaman-detail.html',
      '../../../informations/documentation/nexus/html-halaman-detail.html',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }

    return null;
  }

  group('GenericHtmlParser — Regex extraction for multi-fields', () {
    group('extractList() with regex', () {
      test('HentaiNexus tag extraction: "ahegao (123)" → "ahegao" via regex',
          () {
        const html = '''
          <table class="view-page-details">
            <tr><td></td><td>
              <span class="tag">
                <a>ahegao (123)</a>
              </span>
              <span class="tag">
                <a>blowjob (456)</a>
              </span>
              <span class="tag">
                <a>creampie (789)</a>
              </span>
            </td></tr>
          </table>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'span.tag a',
          type: 'css',
          regex: r'^([a-z0-9 ]+)\s+\(',
        );

        final tags = parser.extractList(doc, selector);

        expect(tags, hasLength(3));
        expect(tags[0], 'ahegao');
        expect(tags[1], 'blowjob');
        expect(tags[2], 'creampie');
      });

      test('extractList() without regex returns raw values', () {
        const html = '''
          <div class="tags">
            <span>tag1</span>
            <span>tag2</span>
            <span>tag3</span>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'div.tags span',
          type: 'css',
        );

        final tags = parser.extractList(doc, selector);

        expect(tags, hasLength(3));
        expect(tags, ['tag1', 'tag2', 'tag3']);
      });

      test(
          'extractList() supports :contains() with adjacent-sibling descendant selector',
          () {
        const html = '''
          <div class="info-text-content">
            <div class="info-field-label">Genre(s)</div>
            <div class="info-field-value">
              <a>Adventure</a>
              <a>Comedy</a>
              <a>Fantasy</a>
            </div>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: '.info-field-label:contains(Genre) + .info-field-value a',
          type: 'css',
        );

        final tags = parser.extractList(doc, selector);

        expect(tags, ['Adventure', 'Comedy', 'Fantasy']);
      });

      test('extractList() with regex filters non-matching elements', () {
        const html = '''
          <ul>
            <li>valid-item (5)</li>
            <li>another-one (10)</li>
            <li>no-match-here</li>
            <li>third-item (3)</li>
          </ul>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'ul li',
          type: 'css',
          regex: r'^([a-z-]+)\s+\(',
        );

        final items = parser.extractList(doc, selector);

        expect(items, hasLength(3));
        expect(items, ['valid-item', 'another-one', 'third-item']);
      });

      test('extractList() extracts from attributes when specified', () {
        const html = '''
          <div>
            <a href="/tag/ahegao-123">ahegao</a>
            <a href="/tag/blowjob-456">blowjob</a>
            <a href="/tag/creampie-789">creampie</a>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'a',
          type: 'css',
          attribute: 'href',
          regex: r'/tag/([a-z-]+)-',
        );

        final tags = parser.extractList(doc, selector);

        expect(tags, hasLength(3));
        expect(tags, ['ahegao', 'blowjob', 'creampie']);
      });

      test('extractList() handles empty results gracefully', () {
        const html = '<div class="empty"></div>';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: '.empty span',
          type: 'css',
          regex: r'^([a-z]+)$',
        );

        final items = parser.extractList(doc, selector);

        expect(items, isEmpty);
      });

      test('extractList() handles group 0 when no capture group', () {
        const html = '''
          <div>
            <tag>abc-123</tag>
            <tag>def-456</tag>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'tag',
          type: 'css',
          regex: r'[a-z]+',
        );

        final items = parser.extractList(doc, selector);

        expect(items, hasLength(2));
        expect(items[0], 'abc');
        expect(items[1], 'def');
      });
    });

    group('extractString() with regex', () {
      test('extractString() applies regex to first matching element', () {
        const html = '''
          <div>
            <p class="description">Description text here</p>
            <p class="tags">tag1 (5) tag2 (3)</p>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'p.tags',
          type: 'css',
          regex: r'(\w+)\s+\(',
        );

        final result = parser.extractString(doc, selector);

        expect(result, 'tag1');
      });

      test('extractString() scans multiple elements until regex matches', () {
        const html = '''
          <div>
            <span class="count">not-a-number</span>
            <span class="count">also-invalid</span>
            <span class="count">Favorites: 1234</span>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'span.count',
          type: 'css',
          regex: r'(\d+)',
        );

        final result = parser.extractString(doc, selector);

        expect(result, '1234');
      });

      test('extractString() returns fallback when regex no match', () {
        const html = '<div><p>no match here</p></div>';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'p',
          type: 'css',
          regex: r'\d+',
          fallback: 'default-value',
        );

        final result = parser.extractString(doc, selector);

        expect(result, 'default-value');
      });

      test('extractString() returns null for failed selection', () {
        const html = '<div></div>';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: '.nonexistent',
          type: 'css',
        );

        final result = parser.extractString(doc, selector);

        expect(result, isNull);
      });
    });

    group('Real-world: HentaiNexus detail page fields', () {
      test('Extract all HentaiNexus detail fields with correct regex', () {
        const html = '''
          <table class="view-page-details">
            <tr>
              <td class="viewcolumn">Tags:</td>
              <td class="viewcontent">
                <span class="tag is-primary">
                  <a href="/tag/ahegao">ahegao (1234)</a>
                </span>
                <span class="tag is-primary">
                  <a href="/tag/blowjob">blowjob (5678)</a>
                </span>
                <span class="tag is-primary">
                  <a href="/tag/creampie">creampie (9012)</a>
                </span>
              </td>
            </tr>
          </table>
        ''';
        final doc = html_parser.parse(html);

        // Test tags (multi extraction with regex)
        const tagsSel = FieldSelector(
          selector: 'span.tag a',
          type: 'css',
          regex: r'^([a-z0-9 ]+)\s+\(',
        );
        final tags = parser.extractList(doc, tagsSel);
        expect(tags, hasLength(3));
        expect(tags, ['ahegao', 'blowjob', 'creampie']);
      });

      test('Extract text with numeric regex (e.g., favorites count)', () {
        const html = '''
          <div class="stat">
            <span class="label">Favorites:</span>
            <span class="value">733 people</span>
          </div>
        ''';
        final doc = html_parser.parse(html);

        // Test favorites extraction with regex
        const favSel = FieldSelector(
          selector: 'span.value',
          type: 'css',
          regex: r'(\d+)',
        );
        expect(parser.extractString(doc, favSel), '733');
      });

      test('Extract fields from real fixture html-halaman-detail.html', () {
        final html = readFixtureHtml();
        if (html == null) {
          markTestSkipped(
            'Missing fixture: informations/documentation/nexus/'
            'html-halaman-detail.html. The whole /informations/ tree is '
            'gitignored (.gitignore line 69), so this HentaiNexus detail page '
            'is absent from a clean checkout. Un-skips automatically once the '
            'fixture is committed to '
            'packages/kuron_generic/test/fixtures/nexus/.',
          );
          return;
        }
        final doc = html_parser.parse(html);

        const titleSel = FieldSelector(selector: 'h1.title', type: 'css');
        const coverSel = FieldSelector(
          selector: 'meta[property="og:image"]',
          type: 'css',
          attribute: 'content',
        );
        const artistSel = FieldSelector(
          selector: 'table.view-page-details a[href*="q=artist:%22"]',
          type: 'css',
        );
        const publisherSel = FieldSelector(
          selector: 'table.view-page-details a[href*="q=publisher:%22"]',
          type: 'css',
        );
        const favoritesSel = FieldSelector(
          selector: 'table.view-page-details tr',
          type: 'css',
          regex: r'Favorites\s*(\d+)',
        );
        const tagsSel = FieldSelector(
          selector: 'table.view-page-details span.tag a',
          type: 'css',
          regex: r'^([a-z0-9 ]+)\s+\(',
        );

        expect(parser.extractString(doc, titleSel), 'Raunchy Roommates 4');

        final coverUrl = parser.extractString(doc, coverSel);
        expect(coverUrl, isNotNull);
        expect(coverUrl, contains('images.hentainexus.com'));
        expect(coverUrl, contains('/000.'));
        expect(coverUrl, contains('.thumb.'));

        final artistRaw = parser.extractString(doc, artistSel) ?? '';
        final publisherRaw = parser.extractString(doc, publisherSel) ?? '';
        final artist = artistRaw.replaceAll(RegExp(r'\s+'), ' ').trim();
        final publisher = publisherRaw.replaceAll(RegExp(r'\s+'), ' ').trim();

        expect(artist, 'Satou Tomoyuki (6)');
        expect(publisher, 'Irodori Comics (2,622)');
        expect(parser.extractString(doc, favoritesSel), '733');

        final tags = parser.extractList(doc, tagsSel);
        expect(tags, isNotEmpty);
        expect(tags, contains('ahegao'));
        expect(tags, contains('blowjob'));
        expect(tags, contains('creampie'));

        // Ensure regex strips numeric counters from tags.
        expect(tags.any((tag) => tag.contains('(')), isFalse);
      });
    });

    group('Edge cases and error handling', () {
      test('extractList() ignores empty or whitespace-only values', () {
        const html = '''
          <div>
            <span></span>
            <span>   </span>
            <span>valid-tag (1)</span>
            <span></span>
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'span',
          type: 'css',
          regex: r'^([a-z-]+)',
        );

        final items = parser.extractList(doc, selector);

        expect(items, hasLength(1));
        expect(items.first, 'valid-tag');
      });

      test('extractString() returns fallback on exception', () {
        const html = '<div><p>test</p></div>';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'p',
          type: 'css',
          regex: '[invalid(regex',
          fallback: 'error-fallback',
        );

        // This should not crash and return fallback
        final result = parser.extractString(doc, selector);
        expect(result, 'error-fallback');
      });

      test('extractList() handles complex nested HTML', () {
        const html = '''
          <table>
            <tbody>
              <tr>
                <td>
                  <div class="wrapper">
                    <span class="tag">
                      <a href="#">fantasy (100)</a>
                    </span>
                  </div>
                </td>
                <td>
                  <div class="wrapper">
                    <span class="tag">
                      <a href="#">action (200)</a>
                    </span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: 'span.tag a',
          type: 'css',
          regex: r'^([a-z]+)',
        );

        final tags = parser.extractList(doc, selector);

        expect(tags, hasLength(2));
        expect(tags, ['fantasy', 'action']);
      });
    });

    group('Lazy-load placeholder resolution (mangaforfree _result.jpg)', () {
      // Regression: reader chapter images on mangaforfree resolve to the
      // image-optimizer placeholder `…_result.jpg` in `src`; the real chapter
      // image lives in `data-src`. The parser must treat `_result.*` as a
      // placeholder and fall back to `data-src` / lazy attrs so the reader
      // actually renders (blank bug had been traced to this).
      test(
          'img[src ends with _result.jpg] with data-src resolves to real data-src URL',
          () {
        const html = '''
          <div class="reading-content">
            <img class="wp-manga-chapter-img"
                 src="https://mangaforfree.net/wp-content/uploads/WP-manga/data/manga_6a7f029ee471e/953927f582fa0ff66cfe79285bedb324/Ideal-(1)_result.jpg"
                 data-src="https://mangaforfree.net/wp-content/uploads/WP-manga/data/manga_6a7f029ee471e/953927f582fa0ff66cfe79285bedb324/Ideal-(1).jpg">
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: '.reading-content img',
          type: 'css',
          attribute: 'src',
        );

        final urls = parser.extractList(doc, selector);

        expect(urls, hasLength(1));
        expect(
          urls.first,
          'https://mangaforfree.net/wp-content/uploads/WP-manga/data/manga_6a7f029ee471e/953927f582fa0ff66cfe79285bedb324/Ideal-(1).jpg',
          reason:
              '_result.jpg placeholder must fall back to the real data-src URL',
        );
        expect(urls.first.contains('_result.jpg'), isFalse);
      });

      test('real (non-placeholder) src is kept as-is', () {
        const html = '''
          <div class="reading-content">
            <img src="https://cdn.example.com/pages/0001/page_1.jpg">
          </div>
        ''';
        final doc = html_parser.parse(html);
        const selector = FieldSelector(
          selector: '.reading-content img',
          type: 'css',
          attribute: 'src',
        );

        final urls = parser.extractList(doc, selector);

        expect(urls, ['https://cdn.example.com/pages/0001/page_1.jpg']);
      });
    });
  });
}
