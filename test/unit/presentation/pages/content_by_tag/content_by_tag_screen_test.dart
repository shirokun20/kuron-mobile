import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/content_by_tag/content_by_tag_screen.dart';

void main() {
  group('ContentByTagScreen.splitTagQuery', () {
    test('author query keeps creator type', () {
      final split = ContentByTagScreen.splitTagQuery(
        'author:Jeon Sun-Wook',
        hasTagRoute: true,
      );

      expect(split.tags, isEmpty);
      expect(split.artists, hasLength(1));
      expect(split.artists.single.value, 'jeon-sun-wook');
      expect(split.artists.single.tagType, 'author');
    });

    test('artist query keeps creator type', () {
      final split = ContentByTagScreen.splitTagQuery(
        'artist:Yoo So-Nan',
        hasTagRoute: true,
      );

      expect(split.tags, isEmpty);
      expect(split.artists.single.tagType, 'artist');
      expect(split.artists.single.value, 'yoo-so-nan');
    });

    test('plain name becomes untyped tag', () {
      final split = ContentByTagScreen.splitTagQuery(
        'Big Breasts',
        hasTagRoute: true,
      );

      expect(split.tags, hasLength(1));
      expect(split.tags.single.value, 'big-breasts');
      expect(split.artists, isEmpty);
    });

    test('no routes stays text query', () {
      final split = ContentByTagScreen.splitTagQuery(
        'author:Jeon Sun-Wook',
        hasTagRoute: false,
      );

      expect(split.tags, isEmpty);
      expect(split.artists, isEmpty);
    });

    test('raw queries bypass splitting', () {
      final split = ContentByTagScreen.splitTagQuery(
        'raw:tag_id=9063',
        hasTagRoute: true,
      );

      expect(split.tags, isEmpty);
      expect(split.artists, isEmpty);
    });
  });
}
