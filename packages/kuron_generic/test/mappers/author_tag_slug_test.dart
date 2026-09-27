// Regression test for shirokun20/kuron-mobile#69 — author/artist tag clicks
// must keep the site's own archive slug.
//
// `splitTagObjects` receives objects carrying `slug` (the last path segment
// of the detail href, e.g. `/manga-author/hanse/` → `hanse`). Dropping it
// forced the app to re-slugify the display name, which breaks for any name
// that is not plain latin lowercase (CJK, parentheses, truncation).
library;

import 'package:kuron_generic/src/mappers/generic_content_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('splitTagObjects preserves href slug (#69)', () {
    test('author/artist keep their archive slug', () {
      final split = GenericContentMapper.splitTagObjects([
        {
          'id': 0,
          'name': 'Hanse',
          'type': 'author',
          'slug': 'hanse',
          'count': 0,
        },
        {
          'id': 0,
          'name': 'Jungeon',
          'type': 'artist',
          'slug': 'jungeon',
          'count': 0,
        },
      ]);

      expect(split.tags.firstWhere((t) => t.type == 'author').slug, 'hanse');
      expect(split.tags.firstWhere((t) => t.type == 'artist').slug, 'jungeon');
    });

    test('slug survives a display name that would re-slugify differently', () {
      // "Pig On a Journey (慢漫的猫)" — the adapter only captures the truncated
      // text, so re-slugifying cannot reproduce the site's own segment.
      final split = GenericContentMapper.splitTagObjects([
        {
          'id': 0,
          'name': 'Pig On a Journey (',
          'type': 'artist',
          'slug': 'pig-on-a-journey-%e6%85%a2%e9%80%94%e7%9a%84%e7%8c%aa',
          'count': 0,
        },
      ]);

      expect(split.tags.first.slug,
          'pig-on-a-journey-%e6%85%a2%e9%80%94%e7%9a%84%e7%8c%aa');
    });

    test('non-string / empty slug degrades to null', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 0, 'name': 'A', 'type': 'artist', 'slug': 7, 'count': 0},
        {'id': 0, 'name': 'B', 'type': 'artist', 'slug': '   ', 'count': 0},
        {'id': 0, 'name': 'C', 'type': 'artist', 'count': 0},
      ]);

      expect(split.tags.every((t) => t.slug == null), isTrue);
    });

    test('tagObjects flow through toDetail with slug intact', () {
      final content = GenericContentMapper.toDetail(
        'series-1',
        {
          'title': 'Series',
          'tagObjects': [
            {
              'id': 0,
              'name': 'Hanse',
              'type': 'author',
              'slug': 'hanse',
              'count': 0,
            },
          ],
        },
        sourceId: 'tag-routing',
      );

      expect(
        content.tags.firstWhere((t) => t.type == 'author').slug,
        'hanse',
      );
    });
  });
}
