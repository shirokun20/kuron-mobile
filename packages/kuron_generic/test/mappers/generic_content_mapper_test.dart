// Unit tests for [GenericContentMapper].
///
// These tests validate that raw field maps extracted from HTML / JSON are
// correctly converted into typed domain entities.  No HTTP calls, no Dio,
// no Flutter — pure Dart.
library;

import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/mappers/generic_content_mapper.dart';
import 'package:test/test.dart';

void main() {
  const sourceId = 'komiktap';

  // ─────────────────────────────────────────────────────────────────────────
  // toListItem
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericContentMapper.toListItem', () {
    test('maps basic scalar fields correctly', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'manga-slug-1',
          'title': 'Great Manga',
          'coverUrl': 'https://cdn.example.com/cover.jpg',
          'language': 'indonesian',
        },
        sourceId: sourceId,
      );

      expect(result.id, 'manga-slug-1');
      expect(result.sourceId, sourceId);
      expect(result.title, 'Great Manga');
      expect(result.coverUrl, 'https://cdn.example.com/cover.jpg');
      expect(result.language, 'indonesian');
    });

    test('uses "Unknown" as title fallback when title is missing', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'slug', 'coverUrl': ''},
        sourceId: sourceId,
      );
      expect(result.title, 'Unknown');
    });

    test('uses "unknown" as language fallback when language is missing', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'slug'},
        sourceId: sourceId,
      );
      expect(result.language, 'unknown');
    });

    test('empty map produces empty id and default values', () {
      final result = GenericContentMapper.toListItem({}, sourceId: sourceId);
      expect(result.id, '');
      expect(result.title, 'Unknown');
      expect(result.coverUrl, '');
      expect(result.pageCount, 0);
      expect(result.tags, isEmpty);
    });

    test('maps pageCount from int', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'pageCount': 24},
        sourceId: sourceId,
      );
      expect(result.pageCount, 24);
    });

    test('maps favorites from int', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'favorites': 123},
        sourceId: sourceId,
      );
      expect(result.favorites, 123);
    });

    test('maps pageCount from numeric string', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'pageCount': '48'},
        sourceId: sourceId,
      );
      expect(result.pageCount, 48);
    });

    test('pageCount is 0 when not parseable', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'pageCount': 'unknown'},
        sourceId: sourceId,
      );
      expect(result.pageCount, 0);
    });

    test('maps uploadDate from unix timestamp string', () {
      // 2024-01-01T00:00:00Z in seconds
      const ts = 1704067200;
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': ts.toString()},
        sourceId: sourceId,
      );
      expect(
        result.uploadDate,
        DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      );
    });

    test('maps uploadDate from ISO 8601 string', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': '2024-06-15T00:00:00Z'},
        sourceId: sourceId,
      );
      expect(result.uploadDate.year, 2024);
      expect(result.uploadDate.month, 6);
      expect(result.uploadDate.day, 15);
    });

    test('maps uploadDate from day-first abbreviated month string', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': '11 Sep 2026'},
        sourceId: sourceId,
      );
      expect(result.uploadDate.year, 2026);
      expect(result.uploadDate.month, 9);
      expect(result.uploadDate.day, 11);
    });

    test('maps uploadDate from month-first full name string', () {
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': 'September 11, 2026'},
        sourceId: sourceId,
      );
      expect(result.uploadDate.year, 2026);
      expect(result.uploadDate.month, 9);
      expect(result.uploadDate.day, 11);
    });

    test('maps uploadDate from relative string', () {
      final before = DateTime.now();
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': '19 days ago'},
        sourceId: sourceId,
      );
      final after = DateTime.now();

      final minExpected = before.subtract(const Duration(days: 19, minutes: 1));
      final maxExpected = after.subtract(const Duration(days: 18, hours: 23));

      expect(result.uploadDate.isAfter(minExpected), isTrue);
      expect(result.uploadDate.isBefore(maxExpected), isTrue);
    });

    test('maps uploadDate from posted relative label', () {
      final before = DateTime.now();
      final result = GenericContentMapper.toListItem(
        {'id': 'x', 'uploadDate': 'Posted: 2 months ago'},
        sourceId: sourceId,
      );
      final after = DateTime.now();

      final minExpected = before.subtract(const Duration(days: 61));
      final maxExpected = after.subtract(const Duration(days: 59));

      expect(result.uploadDate.isAfter(minExpected), isTrue);
      expect(result.uploadDate.isBefore(maxExpected), isTrue);
    });

    test('maps tags as List<String> to List<Tag> with type "tag"', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          'tags': ['shounen', 'action', 'comedy'],
        },
        sourceId: sourceId,
      );
      expect(result.tags, hasLength(3));
      expect(result.tags[0].name, 'shounen');
      expect(result.tags[0].type, 'tag');
      expect(result.tags[1].name, 'action');
    });

    test('maps genre alias to tags when tags key is absent', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          'genre': ['isekai', 'fantasy'],
        },
        sourceId: sourceId,
      );
      expect(result.tags, hasLength(2));
      expect(
          result.tags.map((t) => t.name), containsAll(['isekai', 'fantasy']));
    });

    test('maps artists/characters/parodies/groups as plain string lists', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          'artists': ['artist-a'],
          'characters': ['char-b'],
          'parodies': ['parody-c'],
          'groups': ['group-d'],
        },
        sourceId: sourceId,
      );
      expect(result.artists, ['artist-a']);
      expect(result.characters, ['char-b']);
      expect(result.parodies, ['parody-c']);
      expect(result.groups, ['group-d']);
    });

    test('maps singular artist/publisher aliases and strips trailing counts',
        () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          'artist': 'Satou Tomoyuki (6)',
          'publisher': 'Irodori Comics (2,622)',
        },
        sourceId: sourceId,
      );

      expect(result.artists, ['Satou Tomoyuki']);
      expect(result.groups, ['Irodori Comics']);
    });

    group('with tagObjects (nhentai-style)', () {
      final tagObjects = [
        {'id': 1, 'name': 'english', 'type': 'language', 'count': 0},
        {'id': 2, 'name': 'translated', 'type': 'language', 'count': 0},
        {'id': 3, 'name': 'studio-x', 'type': 'group', 'count': 5},
        {'id': 4, 'name': 'artist-y', 'type': 'artist', 'count': 10},
        {'id': 5, 'name': 'char-z', 'type': 'character', 'count': 2},
        {'id': 6, 'name': 'parody-w', 'type': 'parody', 'count': 1},
        {'id': 7, 'name': 'school', 'type': 'tag', 'count': 99},
      ];

      late Content result;
      setUp(() {
        result = GenericContentMapper.toListItem(
          {'id': 'x', 'tagObjects': tagObjects},
          sourceId: sourceId,
        );
      });

      test('picks language from tagObjects (excluding "translated")', () {
        expect(result.language, 'english');
      });

      test('populates artists from tagObjects', () {
        expect(result.artists, contains('artist-y'));
      });

      test('populates groups from tagObjects', () {
        expect(result.groups, contains('studio-x'));
      });

      test('populates characters from tagObjects', () {
        expect(result.characters, contains('char-z'));
      });

      test('populates parodies from tagObjects', () {
        expect(result.parodies, contains('parody-w'));
      });

      test('includes all tags types in result.tags', () {
        expect(result.tags,
            hasLength(tagObjects.length - 1)); // excluding "translated"
        expect(result.tags.any((t) => t.name == 'school'), isTrue);
      });

      test('tagObjects override direct "artists" field', () {
        // Even if 'artists' field is set, tagObjects wins for artists list.
        final r = GenericContentMapper.toListItem(
          {
            'id': 'x',
            'artists': ['wrong-artist'],
            'tagObjects': [
              {
                'id': 99,
                'name': 'correct-artist',
                'type': 'artist',
                'count': 1
              },
            ],
          },
          sourceId: sourceId,
        );
        expect(r.artists, ['correct-artist']);
        expect(r.artists, isNot(contains('wrong-artist')));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // toDetail
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericContentMapper.toDetail', () {
    test('uses contentId param as id when field id is empty', () {
      final result = GenericContentMapper.toDetail(
        'manga-slug-from-param',
        {'title': 'A Title'},
        sourceId: sourceId,
      );
      expect(result.id, 'manga-slug-from-param');
    });

    test('uses field id when it is non-empty', () {
      final result = GenericContentMapper.toDetail(
        'param-id',
        {'id': 'field-id', 'title': 'A Title'},
        sourceId: sourceId,
      );
      expect(result.id, 'field-id');
    });

    test('falls back coverUrl to first imageUrl when coverUrl is empty', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {'title': 'T', 'coverUrl': ''},
        sourceId: sourceId,
        imageUrls: ['https://cdn.example.com/page-1.jpg'],
      );
      expect(result.coverUrl, 'https://cdn.example.com/page-1.jpg');
    });

    test('uses field coverUrl when non-empty (ignores imageUrls[0])', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {'coverUrl': 'https://real-cover.com/c.jpg'},
        sourceId: sourceId,
        imageUrls: ['https://cdn.example.com/page-1.jpg'],
      );
      expect(result.coverUrl, 'https://real-cover.com/c.jpg');
    });

    test('imageUrls stored on result', () {
      final urls = [
        'https://cdn.example.com/1.jpg',
        'https://cdn.example.com/2.jpg',
      ];
      final result = GenericContentMapper.toDetail(
        'x',
        {},
        sourceId: sourceId,
        imageUrls: urls,
      );
      expect(result.imageUrls, urls);
    });

    test('pageCount = chapters.length when chapters provided', () {
      final chapters = [
        const Chapter(id: 'ch-1', title: 'Chapter 1', url: '/ch-1/'),
        const Chapter(id: 'ch-2', title: 'Chapter 2', url: '/ch-2/'),
      ];
      final result = GenericContentMapper.toDetail(
        'x',
        {'pageCount': '999'}, // should be ignored when chapters present
        sourceId: sourceId,
        chapters: chapters,
      );
      expect(result.pageCount, 2); // chapters.length
    });

    test('pageCount = imageUrls.length when no chapters and no field pageCount',
        () {
      final result = GenericContentMapper.toDetail(
        'x',
        {},
        sourceId: sourceId,
        imageUrls: List.generate(18, (i) => 'img-$i.jpg'),
      );
      expect(result.pageCount, 18);
    });

    test('pageCount from field when no chapters and no imageUrls', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {'pageCount': 42},
        sourceId: sourceId,
      );
      expect(result.pageCount, 42);
    });

    test('chapters stored on result', () {
      final chapters = [
        const Chapter(id: 'ch-1', title: 'Chapter 1', url: '/ch-1/'),
      ];
      final result = GenericContentMapper.toDetail(
        'x',
        {},
        sourceId: sourceId,
        chapters: chapters,
      );
      expect(result.chapters, chapters);
    });

    test('maps englishTitle and japaneseTitle', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {
          'englishTitle': 'The English Title',
          'japaneseTitle': '日本語タイトル',
        },
        sourceId: sourceId,
      );
      expect(result.englishTitle, 'The English Title');
      expect(result.japaneseTitle, '日本語タイトル');
    });

    test('maps mediaId', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {'mediaId': '3456789'},
        sourceId: sourceId,
      );
      expect(result.mediaId, '3456789');
    });

    test('accepts object-based optional string fields without cast errors', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {
          'mediaId': 3456789,
          'englishTitle': {'en': 'The English Title'},
          'japaneseTitle': {'jp': '日本語タイトル'},
        },
        sourceId: sourceId,
      );

      expect(result.mediaId, '3456789');
      expect(result.englishTitle, 'The English Title');
      expect(result.japaneseTitle, '日本語タイトル');
    });

    test('maps favorites on detail', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {'favorites': '77'},
        sourceId: sourceId,
      );
      expect(result.favorites, 77);
    });

    test('detail supports singular artist/publisher aliases', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {
          'artist': 'Satou Tomoyuki (6)',
          'publisher': 'Irodori Comics (2,622)',
        },
        sourceId: sourceId,
      );

      expect(result.artists, ['Satou Tomoyuki']);
      expect(result.groups, ['Irodori Comics']);
    });

    test('detail maps genre alias into tags', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {
          'genre': ['romance', 'drama'],
        },
        sourceId: sourceId,
      );
      expect(result.tags, hasLength(2));
      expect(result.tags.map((t) => t.name), containsAll(['romance', 'drama']));
      // `genre` keeps its own type so taps route to genreSearch, and both
      // keys merge instead of first-key-wins (hentai4free tags + genres).
      expect(result.tags.map((t) => t.type).toSet(), {'genre'});
    });

    test('detail merges tags and genres with their own types', () {
      final result = GenericContentMapper.toDetail(
        'x',
        {
          'tags': ['big-breasts'],
          'genres': ['doujinshi'],
        },
        sourceId: sourceId,
      );
      expect(result.tags, hasLength(2));
      final byName = {for (final t in result.tags) t.name: t.type};
      expect(byName['big-breasts'], 'tag');
      expect(byName['doujinshi'], 'genre');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // toChapter
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericContentMapper.toChapter', () {
    test('maps all fields correctly', () {
      final result = GenericContentMapper.toChapter({
        'id': 'manga-slug-chapter-1',
        'title': 'Chapter 1',
        'url': '/manga-slug-chapter-1/',
        'date': '2024-03-01T00:00:00Z',
        'language': 'en',
      });

      expect(result.id, 'manga-slug-chapter-1');
      expect(result.title, 'Chapter 1');
      expect(result.url, '/manga-slug-chapter-1/');
      expect(result.uploadDate?.year, 2024);
      expect(result.language, 'en');
    });

    test('falls back id to url when id is empty', () {
      final result = GenericContentMapper.toChapter({
        'id': '',
        'url': '/slug-chapter-5/',
        'title': 'Chapter 5',
      });
      expect(result.id, '/slug-chapter-5/');
    });

    test('date is null when not provided', () {
      final result = GenericContentMapper.toChapter({
        'id': 'ch-1',
        'title': 'Ch 1',
        'url': '/ch-1/',
      });
      expect(result.uploadDate, isNull);
    });

    test('date from unix timestamp string', () {
      const ts = 1704067200; // 2024-01-01T00:00:00Z
      final result = GenericContentMapper.toChapter({
        'id': 'ch-1',
        'url': '/ch-1/',
        'title': 'Ch 1',
        'date': ts.toString(),
      });
      expect(
        result.uploadDate,
        DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      );
    });

    test('date from named month format', () {
      final result = GenericContentMapper.toChapter({
        'id': 'ch-1',
        'url': '/ch-1/',
        'title': 'Ch 1',
        'date': 'April 11, 2026',
      });

      expect(result.uploadDate, DateTime(2026, 4, 11));
    });

    test('empty fields produce safe defaults', () {
      final result = GenericContentMapper.toChapter({});
      expect(result.id, ''); // both id and url are empty
      expect(result.title, 'Oneshot');
      expect(result.uploadDate, isNull);
    });

    test('external chapter maps externalUrl/pages/isUnavailable', () {
      final result = GenericContentMapper.toChapter({
        'id': 'db996812-7984-4d1d-bd8b-af76c5b083b3',
        'title': 'Ch.1.5',
        'url': 'db996812-7984-4d1d-bd8b-af76c5b083b3',
        'externalUrl':
            'https://comikey.com/read/isekai-returnee-is-too-op-manga/kj2PPk/chapter-1-5/',
        'pages': 0,
        'isUnavailable': false,
      });
      expect(result.externalUrl,
          'https://comikey.com/read/isekai-returnee-is-too-op-manga/kj2PPk/chapter-1-5/');
      expect(result.pages, isNull);
      expect(result.isUnavailable, isFalse);
      expect(result.isExternal, isTrue);
      expect(result.isReadableInApp, isFalse);
    });

    test('internal chapter maps pages and isReadableInApp true', () {
      final result = GenericContentMapper.toChapter({
        'id': 'fb164cb9-0d50-4ffd-9763-968d7862e209',
        'title': 'Ch.34',
        'url': 'fb164cb9-0d50-4ffd-9763-968d7862e209',
        'pages': 19,
      });
      expect(result.externalUrl, isNull);
      expect(result.pages, 19);
      expect(result.isExternal, isFalse);
      expect(result.isReadableInApp, isTrue);
    });

    test('missing externalUrl/pages fields default to null/false', () {
      final result = GenericContentMapper.toChapter({
        'id': 'legacy',
        'title': 'Ch.1',
        'url': '/legacy/',
      });
      expect(result.externalUrl, isNull);
      expect(result.pages, isNull);
      expect(result.isUnavailable, isFalse);
      expect(result.isExternal, isFalse);
      expect(result.isReadableInApp, isTrue);
    });

    test('isUnavailable=true is propagated', () {
      final result = GenericContentMapper.toChapter({
        'id': 'x',
        'title': 'Ch.1',
        'url': '/x/',
        'pages': 10,
        'isUnavailable': true,
      });
      expect(result.isUnavailable, isTrue);
      expect(result.isReadableInApp, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // splitTagObjects
  // ─────────────────────────────────────────────────────────────────────────

  group('GenericContentMapper.splitTagObjects', () {
    test('splits mixed types into correct buckets', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': 'english', 'type': 'language', 'count': 0},
        {'id': 2, 'name': 'artist-a', 'type': 'artist', 'count': 5},
        {'id': 3, 'name': 'group-b', 'type': 'group', 'count': 2},
        {'id': 4, 'name': 'char-c', 'type': 'character', 'count': 1},
        {'id': 5, 'name': 'parody-d', 'type': 'parody', 'count': 3},
        {'id': 6, 'name': 'romance', 'type': 'tag', 'count': 100},
      ]);

      expect(split.language, 'english');
      expect(split.artists, ['artist-a']);
      expect(split.groups, ['group-b']);
      expect(split.characters, ['char-c']);
      expect(split.parodies, ['parody-d']);
      expect(split.tags, hasLength(6)); // all tag types included in master list
    });

    test('"translated" language is excluded from language list', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': 'translated', 'type': 'language', 'count': 0},
      ]);
      // "translated" goes into tags but NOT into languages list
      expect(split.language, '');
      expect(split.tags, hasLength(0)); // 'translated' is skipped entirely
    });

    test('first language wins when multiple languages present', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': 'english', 'type': 'language', 'count': 0},
        {'id': 2, 'name': 'translated', 'type': 'language', 'count': 0},
        {'id': 3, 'name': 'chinese', 'type': 'language', 'count': 0},
      ]);
      expect(split.language, 'english');
    });

    test('entries with empty name are skipped', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': '', 'type': 'tag', 'count': 5},
        {'id': 2, 'name': 'valid', 'type': 'tag', 'count': 5},
      ]);
      expect(split.tags, hasLength(1));
      expect(split.tags.first.name, 'valid');
    });

    test('unknown type defaults to "tag" bucket', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': 'misc-item', 'type': 'unknown-type', 'count': 1},
      ]);
      expect(split.tags, hasLength(1));
      expect(split.tags.first.type, 'unknown-type');
      expect(split.artists, isEmpty);
    });

    test('empty list produces empty split', () {
      final split = GenericContentMapper.splitTagObjects([]);
      expect(split.tags, isEmpty);
      expect(split.artists, isEmpty);
      expect(split.language, '');
    });

    test('Tag objects carry correct id and count', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 42, 'name': 'harem', 'type': 'tag', 'count': 1337},
      ]);
      expect(split.tags.first.id, 42);
      expect(split.tags.first.count, 1337);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Tag resolution priority
  // ─────────────────────────────────────────────────────────────────────────

  group('Tag resolution priority', () {
    test('tagObjects take priority over plain tags list', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          // tagObjects should win
          'tagObjects': [
            {'id': 1, 'name': 'from-tagObjects', 'type': 'tag', 'count': 1},
          ],
          'tags': ['from-tags'],
        },
        sourceId: sourceId,
      );
      expect(result.tags.length, 1);
      expect(result.tags.first.name, 'from-tagObjects');
    });

    test('plain List<String> tags used when no tagObjects', () {
      final result = GenericContentMapper.toListItem(
        {
          'id': 'x',
          'tags': ['action', 'drama'],
        },
        sourceId: sourceId,
      );
      expect(result.tags.map((t) => t.name), containsAll(['action', 'drama']));
      expect(result.tags.every((t) => t.type == 'tag'), isTrue);
    });
  });
}
