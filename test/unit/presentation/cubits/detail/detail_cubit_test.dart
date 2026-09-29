import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/cubits/detail/detail_cubit.dart';

void main() {
  Content content({
    required String sourceId,
    List<Content> relatedContent = const [],
  }) {
    return Content(
      id: 'series',
      sourceId: sourceId,
      title: 'Series',
      coverUrl: '',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'en',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime(2026),
      relatedContent: relatedContent,
    );
  }

  test('reuses embedded related for mangafire even when list is empty', () {
    expect(
      shouldReuseEmbeddedRelated(content(sourceId: 'mangafire')),
      isTrue,
    );
  });

  test('reuses embedded related for other sources only when populated', () {
    expect(
      shouldReuseEmbeddedRelated(content(sourceId: 'nhentai')),
      isFalse,
    );
    expect(
      shouldReuseEmbeddedRelated(
        content(
          sourceId: 'nhentai',
          relatedContent: [
            Content(
              id: 'related',
              sourceId: 'nhentai',
              title: 'Related',
              coverUrl: '',
              tags: [],
              artists: [],
              characters: [],
              parodies: [],
              groups: [],
              language: 'en',
              pageCount: 0,
              imageUrls: [],
              uploadDate: DateTime(2026),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  test('mergeChaptersById appends only missing chapter ids', () {
    final merged = mergeChaptersById(
      const [
        Chapter(
          id: 'en-1',
          title: 'English 1',
          url: '/en-1',
          language: 'en',
        ),
      ],
      const [
        Chapter(
          id: 'en-1',
          title: 'English 1',
          url: '/en-1',
          language: 'en',
        ),
        Chapter(
          id: 'es-1',
          title: 'Spanish 1',
          url: '/es-1',
          language: 'es',
        ),
      ],
    );

    expect(
        merged.map((chapter) => chapter.id).toList(), const ['en-1', 'es-1']);
  });

  // Issue #68: a video chapter resolves to 0 images + N streams. Gating on
  // `images.isEmpty` alone refused to open the reader at all.
  test('stream-only chapter is readable, empty chapter is not', () {
    expect(
      isChapterReadable(images: const [], streamCount: 1),
      isTrue,
      reason: 'video/HLS chapter has no pages but is playable',
    );
    expect(isChapterReadable(images: const [], streamCount: 0), isFalse);
    expect(
      isChapterReadable(
          images: const ['https://cdn.example/1.jpg'], streamCount: 0),
      isTrue,
    );
    expect(
      isChapterReadable(
          images: const ['https://cdn.example/1.jpg'], streamCount: 3),
      isTrue,
      reason: 'mixed chapter keeps both',
    );
  });
}
