import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/presentation/pages/detail/detail_screen.dart';

void main() {
  group('DetailScreen.resolveDetailHeaderImageUrlForTesting', () {
    test('prefers cover url for hentainexus detail header', () {
      final content = Content(
        id: '21723',
        sourceId: 'hentainexus',
        title: 'Test',
        coverUrl: 'https://cdn.example.com/cover.jpg',
        tags: const <Tag>[],
        artists: const <String>[],
        characters: const <String>[],
        parodies: const <String>[],
        groups: const <String>[],
        language: 'en',
        pageCount: 1,
        imageUrls: const <String>[
          'https://images.hentainexus.com/v2/foo/001.webp',
        ],
        uploadDate: DateTime(2026),
      );

      expect(
        DetailScreen.resolveDetailHeaderImageUrlForTesting(content),
        'https://cdn.example.com/cover.jpg',
      );
    });

    test('keeps first image for non-hentainexus source', () {
      final content = Content(
        id: '1',
        sourceId: 'other',
        title: 'Test',
        coverUrl: 'https://cdn.example.com/cover.jpg',
        tags: const <Tag>[],
        artists: const <String>[],
        characters: const <String>[],
        parodies: const <String>[],
        groups: const <String>[],
        language: 'en',
        pageCount: 1,
        imageUrls: const <String>[
          'https://cdn.example.com/page-1.webp',
        ],
        uploadDate: DateTime(2026),
      );

      expect(
        DetailScreen.resolveDetailHeaderImageUrlForTesting(content),
        'https://cdn.example.com/page-1.webp',
      );
    });

    test('derives hentainexus thumb jpg when cover url is empty', () {
      final content = Content(
        id: '21723',
        sourceId: 'hentainexus',
        title: 'Test',
        coverUrl: '',
        tags: const <Tag>[],
        artists: const <String>[],
        characters: const <String>[],
        parodies: const <String>[],
        groups: const <String>[],
        language: 'en',
        pageCount: 1,
        imageUrls: const <String>[
          'https://images.hentainexus.com/v2/foo/001.webp',
        ],
        uploadDate: DateTime(2026),
      );

      expect(
        DetailScreen.resolveDetailHeaderImageUrlForTesting(content),
        'https://images.hentainexus.com/v2/foo/001.png.thumb.jpg',
      );
    });
  });
  group('DetailScreen creator split (artist/author)', () {
    Content content({
      List<Tag> tags = const [],
      List<String> artists = const [],
      String? subTitle,
    }) {
      return Content(
        id: '1',
        sourceId: 'nhentai',
        title: 'Test',
        coverUrl: 'https://cdn.example.com/cover.jpg',
        tags: tags,
        artists: artists,
        characters: const <String>[],
        parodies: const <String>[],
        groups: const <String>[],
        language: 'en',
        pageCount: 1,
        imageUrls: const <String>[],
        uploadDate: DateTime(2026),
        subTitle: subTitle,
      );
    }

    test('3.1 tags hide artist/author, keep the rest', () {
      final visible = DetailScreen.visibleDetailTagsForTesting([
        const Tag(id: 9063, name: 'koari', type: 'artist', count: 53),
        const Tag(id: 7, name: 'somebody', type: 'Author', count: 1),
        const Tag(id: 1, name: 'sole female', type: 'tag', count: 5),
        const Tag(id: 2, name: 'japanese', type: 'language', count: 9),
      ]);

      expect(visible.map((t) => t.name), ['sole female', 'japanese']);
    });

    test('3.2 creator names resolve from tags, artists supplement legacy', () {
      final c = content(
        tags: const [
          Tag(id: 9063, name: 'koari', type: 'artist', count: 53),
        ],
        artists: const ['koari', 'legacy-artist'],
      );

      expect(
        DetailScreen.creatorNamesForTesting(c, 'artist'),
        ['koari', 'legacy-artist'],
      );
      expect(DetailScreen.creatorNamesForTesting(c, 'author'), isEmpty);
    });

    test('3.2 creator tag resolves numeric id for search', () {
      const tag = Tag(
        id: 9063,
        name: 'koari',
        type: 'artist',
        count: 53,
        slug: 'koari',
        url: '/artist/koari/',
      );
      final c = content(tags: const [tag]);

      final resolved =
          DetailScreen.resolveCreatorTagForTesting(c, 'Koari', 'artist');
      expect(resolved?.id, 9063);
      expect(
        DetailScreen.resolveCreatorTagForTesting(c, 'unknown', 'artist'),
        isNull,
      );
    });

    test('3.3 synopsis empty for nhentai, text otherwise', () {
      expect(
        DetailScreen.synopsisForTesting(content()),
        isEmpty,
      );
      expect(
        DetailScreen.synopsisForTesting(content(subTitle: '  hello  ')),
        'hello',
      );
    });
  });
}
