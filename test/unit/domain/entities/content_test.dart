import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/domain/extensions/content_extensions.dart';

void main() {
  group('Content Entity', () {
    late Content sampleContent;

    setUp(() {
      sampleContent = Content(
        sourceId: 'nhentai',
        id: '12345',
        title: 'Sample Title',
        coverUrl: 'https://example.com/cover.jpg',
        tags: [
          const Tag(
              id: 1,
              name: 'romance',
              type: 'tag',
              count: 100,
              url: '/tag/romance'),
          const Tag(
              id: 2,
              name: 'comedy',
              type: 'tag',
              count: 50,
              url: '/tag/comedy'),
          const Tag(
              id: 3,
              name: 'doujinshi',
              type: 'category',
              count: 1000,
              url: '/category/doujinshi'),
        ],
        artists: ['Artist One', 'Artist Two'],
        characters: ['Character A'],
        parodies: ['Parody X'],
        groups: ['Group Alpha'],
        language: 'English',
        pageCount: 25,
        imageUrls: [],
        uploadDate: DateTime(2024, 1, 1),
        favorites: 1000,
        englishTitle: 'English Title',
        japaneseTitle: '日本語タイトル',
      );
    });

    group('getDisplayTitle', () {
      test(
          'returns englishTitle when preferEnglish is true and englishTitle exists',
          () {
        expect(sampleContent.getDisplayTitle(preferEnglish: true),
            'English Title');
      });

      test('returns japaneseTitle when preferEnglish is false', () {
        expect(sampleContent.getDisplayTitle(preferEnglish: false), '日本語タイトル');
      });

      test('returns japaneseTitle when englishTitle is empty', () {
        final content = Content(
          sourceId: 'nhentai',
          id: '12345',
          title: 'Sample Title',
          coverUrl: 'https://example.com/cover.jpg',
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: 'English',
          pageCount: 25,
          imageUrls: const [],
          uploadDate: DateTime(2024, 1, 1),
          japaneseTitle: '日本語タイトル',
          // No englishTitle
        );
        expect(content.getDisplayTitle(preferEnglish: true), '日本語タイトル');
      });

      test('returns title when both englishTitle and japaneseTitle are missing',
          () {
        final content = Content(
          sourceId: 'nhentai',
          id: '12345',
          title: 'Sample Title',
          coverUrl: 'https://example.com/cover.jpg',
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: 'English',
          pageCount: 25,
          imageUrls: const [],
          uploadDate: DateTime(2024, 1, 1),
          // No englishTitle or japaneseTitle
        );
        expect(content.getDisplayTitle(), 'Sample Title');
      });
    });

    group('hasTag', () {
      test('returns true when tag exists (case insensitive)', () {
        expect(sampleContent.hasTag('romance'), true);
        expect(sampleContent.hasTag('ROMANCE'), true);
        expect(sampleContent.hasTag('Romance'), true);
      });

      test('returns false when tag does not exist', () {
        expect(sampleContent.hasTag('action'), false);
      });
    });

    group('hasArtist', () {
      test('returns true when artist exists (case insensitive)', () {
        expect(sampleContent.hasArtist('Artist One'), true);
        expect(sampleContent.hasArtist('artist one'), true);
      });

      test('returns false when artist does not exist', () {
        expect(sampleContent.hasArtist('Unknown Artist'), false);
      });
    });

    group('getTagsByType', () {
      test('returns tags filtered by type', () {
        final tagsByType = sampleContent.getTagsByType('tag');
        expect(tagsByType.length, 2);
        expect(tagsByType.map((t) => t.name).toList(), ['romance', 'comedy']);
      });

      test('returns empty list when no tags of type exist', () {
        final tagsByType = sampleContent.getTagsByType('nonexistent');
        expect(tagsByType, isEmpty);
      });
    });

    group('category', () {
      test('returns category from tags', () {
        expect(sampleContent.category, 'doujinshi');
      });

      test('returns default doujinshi when no category tag exists', () {
        final content = sampleContent.copyWith(tags: [
          const Tag(
              id: 1,
              name: 'romance',
              type: 'tag',
              count: 100,
              url: '/tag/romance'),
        ]);
        expect(content.category, 'doujinshi');
      });
    });

    group('derivedContentPath', () {
      test('returns null when imageUrls is empty', () {
        expect(sampleContent.derivedContentPath, isNull);
      });

      test('returns null when imageUrls contains only http URLs', () {
        final content = sampleContent.copyWith(
          imageUrls: ['https://example.com/image.jpg'],
        );
        expect(content.derivedContentPath, isNull);
      });

      test('returns parent directory for local file paths', () {
        final content = sampleContent.copyWith(
          imageUrls: ['/storage/downloads/12345/001.jpg'],
        );
        expect(content.derivedContentPath, '/storage/downloads/12345');
      });

      test('returns grandparent when parent is images folder', () {
        final content = sampleContent.copyWith(
          imageUrls: ['/storage/downloads/12345/images/001.jpg'],
        );
        expect(content.derivedContentPath, '/storage/downloads/12345');
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final copy = sampleContent.copyWith(
          title: 'New Title',
          pageCount: 50,
        );

        expect(copy.title, 'New Title');
        expect(copy.pageCount, 50);
        expect(copy.id, sampleContent.id); // unchanged
        expect(copy.coverUrl, sampleContent.coverUrl); // unchanged
      });
    });

    group('equatable', () {
      test('two contents with same data are equal', () {
        final content1 = Content(
          sourceId: 'nhentai',
          id: '1',
          title: 'Same',
          coverUrl: 'url',
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: 'en',
          pageCount: 10,
          imageUrls: const [],
          uploadDate: DateTime(2024, 1, 1),
        );

        final content2 = Content(
          sourceId: 'nhentai',
          id: '1',
          title: 'Same',
          coverUrl: 'url',
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: 'en',
          pageCount: 10,
          imageUrls: const [],
          uploadDate: DateTime(2024, 1, 1),
        );

        expect(content1, equals(content2));
      });
    });

    group('getDisplayTitle whitespace normalization', () {
      Content dirtyContent({
        required String title,
        String? englishTitle,
        String? japaneseTitle,
      }) {
        return Content(
          sourceId: 'komikindo',
          id: 'one-piece-chapter-1',
          title: title,
          coverUrl: '',
          tags: const [],
          artists: const [],
          characters: const [],
          parodies: const [],
          groups: const [],
          language: 'id',
          pageCount: 0,
          imageUrls: const [],
          uploadDate: DateTime(2024, 1, 1),
          englishTitle: englishTitle,
          japaneseTitle: japaneseTitle,
        );
      }

      test('dirty primary title renders on one line in the Reader app bar', () {
        final content = dirtyContent(title: '  Komik\n   Indo   Chapter 1  ');
        expect(content.getDisplayTitle(), 'Komik Indo Chapter 1');
      });

      test('dirty englishTitle is normalized when preferred', () {
        final content = dirtyContent(
          title: 'Judul',
          englishTitle: '  One \n Piece   Vol. 1 ',
        );
        expect(content.getDisplayTitle(), 'One Piece Vol. 1');
      });

      test('dirty title is normalized for real-ID sources too', () {
        final content = dirtyContent(title: '  Nhentai \n 12345 ');
        expect(content.getDisplayTitle(), 'Nhentai 12345');
      });
    });
  });
}
