// Parity between the calling-isolate sync extraction path and the
// `Isolate.run()` HTML parse jobs.
//
// The jobs must return byte-identical field maps and pagination signals to
// the shared pure functions, and `normalizeWhitespace` / `cleanText`
// behavior must be intact on both paths.
library;

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/parsers/html_field_extract.dart';
import 'package:kuron_generic/src/parsers/html_isolate_parse.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _listHtml = '''
<html><body>
<div class="section">Latest Updates</div>
<div class="manga-card">
  <a class="series" href="https://site.test/manga/one-piece/">link</a>
  <h4 class="ttl">  One\n   Piece   </h4>
  <img class="ts-post-image" src="/covers/one-piece.jpg" />
</div>
<div class="manga-card">
  <a class="series" href="https://site.test/manga/naruto/">link</a>
  <h4 class="ttl">Naruto</h4>
  <img class="ts-post-image" data-src="https://cdn.test/naruto.jpg" src="blank.png" />
</div>
<a class="next page-numbers" href="/page/2/">Next</a>
<a href="/page/3/">3</a>
</body></html>
''';

Map<String, dynamic> _fieldsConfig() => {
  'id': {'selector': 'a.series', 'attribute': 'href', 'transform': 'slug'},
  'title': {'selector': '.ttl', 'transform': 'cleanText'},
  'coverUrl': {'selector': 'img.ts-post-image', 'attribute': 'src'},
};

void main() {
  group('extractListPageInIsolate', () {
    test(
      'matches sync shared extraction incl. transforms + pagination',
      () async {
        final job = ListPageJob(
          container: '.manga-card',
          fields: _fieldsConfig(),
          nextSelector: 'a.next',
          linksSelector: 'a[href]',
        );
        final viaIsolate = await extractListPageInIsolate(
          _listHtml,
          job: job,
          pageUrl: 'https://site.test/page/1/',
          baseUrl: 'https://site.test',
        );

        final parser = GenericHtmlParser(logger: Logger(level: Level.off));
        final sync = extractListPage(
          parser,
          html_parser.parse(_listHtml),
          job,
          'https://site.test/page/1/',
          'https://site.test',
        );

        // JSON round-trip comparison: strict on values, immune to the
        // post-isolate runtime map/list generic signatures.
        expect(jsonEncode(viaIsolate['items']), jsonEncode(sync['items']));
        expect(viaIsolate['nextPageUrl'], sync['nextPageUrl']);
        expect(viaIsolate['hasNextByLink'], sync['hasNextByLink']);
        expect(viaIsolate['totalPages'], sync['totalPages']);

        final items = (viaIsolate['items'] as List)
            .cast<Map<String, dynamic>>();
        expect(items.length, 2);
        // slug transform trims + extracts the path slug.
        expect(items[0]['id'], 'one-piece');
        // cleanText collapses internal whitespace/newlines.
        expect(items[0]['title'], 'One Piece');
        // Relative cover resolves against baseUrl.
        expect(items[0]['coverUrl'], 'https://site.test/covers/one-piece.jpg');
        // Lazy-load fallback chain skips the placeholder src.
        expect(items[1]['coverUrl'], 'https://cdn.test/naruto.jpg');
        expect(viaIsolate['nextPageUrl'], 'https://site.test/page/2/');
        expect(viaIsolate['hasNextByLink'], isTrue);
        expect(viaIsolate['totalPages'], 3);
      },
    );

    test('empty container yields no items and no next page', () async {
      final job = ListPageJob(container: '.missing', fields: _fieldsConfig());
      final result = await extractListPageInIsolate(
        _listHtml,
        job: job,
        pageUrl: 'https://site.test/',
        baseUrl: 'https://site.test',
      );
      expect(result['items'], isEmpty);
      expect(result['nextPageUrl'], isNull);
      expect(result['hasNextByLink'], isFalse);
    });
  });

  group('extractDocumentFieldsInIsolate', () {
    const detailHtml = '''
<html><body>
<h1 class="entry-title">  Solo\n  Leveling  </h1>
<img class="cover" data-src="https://cdn.test/solo.jpg" src="blank.png" />
<div class="genres">
  <a href="https://site.test/genre/action/"><span>Action</span></a>
  <a href="https://site.test/genre/fantasy/"><span>Fantasy</span><span>12</span></a>
</div>
<div class="tagrow"><a title="artist:chugong">x</a><a title="other:op">y</a></div>
</body></html>
''';

    Map<String, dynamic> fieldsConfig() => {
      'title': {'selector': 'h1.entry-title'},
      'coverUrl': {'selector': 'img.cover', 'attribute': 'src'},
      'genres': {
        'selector': '.genres a',
        'multi': true,
        'extractTagObjects': true,
      },
      // NOTE: parseTagNamespace only fires for the literal 'tags' key
      // (same gate as the adapter) — the fixture honors that contract.
      'tags': {
        'selector': '.tagrow a',
        'attribute': 'title',
        'multi': true,
        'parseTagNamespace': true,
      },
    };

    test('matches sync extraction and keeps tag rows isolate-safe', () async {
      final viaIsolate = await extractDocumentFieldsInIsolate(
        detailHtml,
        fields: fieldsConfig(),
        baseUrl: 'https://site.test',
      );
      final parser = GenericHtmlParser(logger: Logger(level: Level.off));
      final sync = extractDocumentFields(
        parser,
        html_parser.parse(detailHtml),
        fieldsConfig(),
        'https://site.test',
      );
      expect(jsonEncode(viaIsolate), jsonEncode(sync));

      // Title goes through parser whitespace normalization (single spaces).
      expect(viaIsolate['title'], 'Solo Leveling');
      expect(viaIsolate['coverUrl'], 'https://cdn.test/solo.jpg');

      // Tag rows are plain maps (isolate-safe), listed in the marker.
      final marker = (viaIsolate[tagMapKeysMarker] as List).cast<String>();
      expect(marker, containsAll(['genres', 'tags']));
      final tagRows = (viaIsolate['genres'] as List)
          .cast<Map<String, dynamic>>();
      expect(tagRows.map((t) => '${t['type']}:${t['name']}').toList(), [
        'genre:Action',
        'genre:Fantasy',
      ]);
      // Span count "12" parsed as tag count.
      expect(tagRows[1]['count'], 12);
      expect(tagRows[0]['slug'], 'action');

      // tagFromRow rebuilds entities losslessly.
      final rebuilt = tagRows.map(tagFromRow).toList();
      expect(rebuilt[0].name, 'Action');
      expect(rebuilt[0].type, 'genre');
      expect(rebuilt[1].count, 12);

      // parseTagNamespace splits "ns:name" into typed rows.
      final labeled = (viaIsolate['tags'] as List).cast<Map<String, dynamic>>();
      expect(labeled.map((t) => '${t['type']}:${t['name']}').toList(), [
        'artist:chugong',
        'other:op',
      ]);

      // Merged tagObjects stay plain maps for the mapper.
      final merged = (viaIsolate['tagObjects'] as List)
          .cast<Map<String, dynamic>>();
      expect(merged.length, 2);
    });
  });

  group('shared transforms', () {
    test('cleanText collapses whitespace like the adapter contract', () {
      expect(applyFieldTransform('  A\n   B  ', 'cleanText'), 'A B');
    });

    test('slug extraction tolerates raw unicode path segments', () {
      expect(
        extractSlugFromUrl('https://site.test/manga/title-special〜/'),
        'title-special〜',
      );
    });

    test('decodeSlugComponent keeps malformed escapes raw', () {
      expect(decodeSlugComponent('a%2Fb'), 'a/b');
      expect(decodeSlugComponent('a%zzb'), 'a%zzb');
    });

    test('sanitizeImageUrl resolves relatives and keeps absolute', () {
      expect(
        sanitizeImageUrl('/covers/a.jpg', 'https://site.test'),
        'https://site.test/covers/a.jpg',
      );
      expect(
        sanitizeImageUrl('upload/p/1.jpg', 'https://site.test'),
        'https://site.test/upload/p/1.jpg',
      );
      expect(
        sanitizeImageUrl('https://cdn.test/1.jpg', 'https://site.test'),
        'https://cdn.test/1.jpg',
      );
    });
  });
}
