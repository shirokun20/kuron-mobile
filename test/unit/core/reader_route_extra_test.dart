import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/models/image_metadata.dart';
import 'package:nhasixapp/core/routing/reader_route_extra.dart';

void main() {
  group('ReaderRouteExtra', () {
    test('round-trips serialized image metadata and chapter payloads', () {
      const imageMetadata = [
        ImageMetadata(
          imageUrl: 'https://example.com/1.webp',
          contentId: 'gallery-1',
          pageNumber: 1,
          imageType: ImageType.online,
        ),
        ImageMetadata(
          imageUrl: 'https://example.com/2.webp',
          contentId: 'gallery-1',
          pageNumber: 2,
          imageType: ImageType.cached,
        ),
      ];
      const chapterData = ChapterData(
        images: ['1.webp', '2.webp'],
        prevChapterId: 'prev',
        nextChapterId: 'next',
        prevChapterTitle: 'Previous',
        nextChapterTitle: 'Next',
      );
      final allChapters = [
        Chapter(
          id: 'c1',
          title: 'Chapter 1',
          url: '/c1',
          uploadDate: DateTime.parse('2026-04-20T10:00:00Z'),
          scanGroup: 'Group A',
          language: 'en',
        ),
      ];

      final extra = buildReaderRouteExtra(
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        allChapters: allChapters,
        currentChapter: allChapters.first,
        activeChapterLanguage: 'en-US',
      );

      final parsedExtra = asReaderRouteExtra(extra);
      expect(parsedExtra, isNotNull);

      final parsedImageMetadata =
          readReaderImageMetadata(parsedExtra!['imageMetadata']);
      final parsedChapterData =
          readReaderChapterData(parsedExtra['chapterData']);
      final parsedAllChapters = readReaderChapters(parsedExtra['allChapters']);
      final parsedCurrentChapter =
          readReaderChapter(parsedExtra['currentChapter']);
      final parsedActiveLanguage =
          readReaderActiveChapterLanguage(parsedExtra['activeChapterLanguage']);

      expect(parsedImageMetadata, imageMetadata);
      expect(parsedChapterData, chapterData);
      expect(parsedAllChapters, allChapters);
      expect(parsedCurrentChapter, allChapters.first);
      expect(parsedActiveLanguage, 'en-US');
    });

    test('parses mixed dynamic image metadata lists safely', () {
      const metadata = ImageMetadata(
        imageUrl: 'https://example.com/1.webp',
        contentId: 'gallery-2',
        pageNumber: 1,
        imageType: ImageType.online,
      );

      final parsed = readReaderImageMetadata([
        metadata,
        metadata.toJson(),
        {'invalid': true},
        42,
      ]);

      expect(parsed, [metadata, metadata]);
    });

    test('returns null for malformed chapter payloads', () {
      expect(readReaderChapterData({'images': 'not-a-list'}), isNull);
      expect(readReaderChapter({'title': 'Missing id'}), isNull);
      expect(readReaderChapters('not-a-list'), isNull);
    });

    test('decodes percent-encoded E-Hentai virtual identifiers safely', () {
      final chapterData = readReaderChapterData({
        'images': ['1.webp'],
        'prevChapterId': '__ehpart__%3A3906586%3A971a6d4051%3A0',
        'nextChapterId': '__ehpart__%3A3906586%3A971a6d4051%3A2',
        'prevChapterTitle': 'Part 1',
        'nextChapterTitle': 'Part 3',
      });

      expect(chapterData, isNotNull);
      expect(chapterData!.prevChapterId, '__ehpart__:3906586:971a6d4051:0');
      expect(chapterData.nextChapterId, '__ehpart__:3906586:971a6d4051:2');
    });

    test('preserves malformed internal identifiers without throwing', () {
      final chapterData = readReaderChapterData({
        'images': ['1.webp'],
        'nextChapterId': '__ehchunk__:%ZZ:bad',
      });

      expect(chapterData, isNotNull);
      expect(chapterData!.nextChapterId, '__ehchunk__:%ZZ:bad');
    });

    // Issue #68: the reader needs the stream after route navigation, so the
    // field has to survive serialize → parse.
    test('round-trips video chapter stream URLs', () {
      const chapterData = ChapterData(
        images: [],
        videoUrls: ['https://cdn.example.com/hls/master.m3u8'],
        nextChapterId: 'next',
      );

      final extra = buildReaderRouteExtra(chapterData: chapterData);
      final parsed = readReaderChapterData(asReaderRouteExtra(extra)!['chapterData']);

      expect(parsed, chapterData);
      expect(parsed!.videoUrls, ['https://cdn.example.com/hls/master.m3u8']);
    });

    // The reader is entered from the detail screen through this route, so a
    // dropped videoIndex/videoReferer silently moved the card to the end of the
    // chapter and sent playback without the origin the player demands.
    test('round-trips a mixed chapter video position and origin', () {
      const chapterData = ChapterData(
        images: ['https://cosplaytele.example/01.webp'],
        videoUrls: ['https://cossora.stream/embed/c74c438d'],
        videoIndex: 0,
        videoReferer: 'https://cosplaytele.example/hiyuki-2/',
      );

      final extra = buildReaderRouteExtra(chapterData: chapterData);
      final parsed =
          readReaderChapterData(asReaderRouteExtra(extra)!['chapterData']);

      expect(parsed, chapterData);
      expect(parsed!.videoIndex, 0);
      expect(parsed.videoReferer, 'https://cosplaytele.example/hiyuki-2/');
    });
  });
}
