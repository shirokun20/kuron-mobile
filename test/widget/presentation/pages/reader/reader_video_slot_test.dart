// Where the play card lands in a chapter that mixes photos and a video.
//
// The card was appended after the last page in all three reader modes, so a
// gallery whose site puts the embed first (cosplaytele: "110 photos and 1
// video" — the embed above every photo) showed it 110 pages too late. The
// arithmetic now lives in [readerVideoSlot] / [readerPageIndexFor] /
// [readerNavSlot] so all three modes share it and it can be checked without
// pumping the reader (which needs a cubit, two page controllers and a
// translation cubit).
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_video_chapter.dart';

void main() {
  group('the card sits at the video\'s own position', () {
    test('an embed above every photo takes slot 0', () {
      expect(
        readerVideoSlot(pageCount: 3, hasVideoStrip: true, videoIndex: 0),
        0,
      );
    });

    test('an embed after four photos takes slot 4', () {
      expect(
        readerVideoSlot(pageCount: 6, hasVideoStrip: true, videoIndex: 4),
        4,
      );
    });

    test('an unknown position falls back to after the last page', () {
      expect(
        readerVideoSlot(pageCount: 14, hasVideoStrip: true),
        14,
        reason: 'null = the parser could not attribute a position',
      );
    });

    test('a chapter without a stream has no card slot', () {
      expect(
        readerVideoSlot(pageCount: 14, hasVideoStrip: false, videoIndex: 3),
        -1,
      );
    });
  });

  group('pages after the card keep their own numbering', () {
    test('items before the card are not shifted', () {
      const videoAt = 4;
      expect(readerPageIndexFor(0, videoAt), 0);
      expect(readerPageIndexFor(3, videoAt), 3);
    });

    test('the card\'s own slot maps to the page it replaced', () {
      // The card slot is handled before this mapping is reached, but a
      // defensive answer keeps an off-by-one from silently skipping a page.
      expect(readerPageIndexFor(4, 4), 4);
    });

    test('every item after the card is shifted by one', () {
      const videoAt = 4;
      expect(readerPageIndexFor(5, videoAt), 4,
          reason: 'page 5 now lives at item 5');
      expect(readerPageIndexFor(6, videoAt), 5);
      expect(readerPageIndexFor(7, videoAt), 6);
    });

    test('with no card nothing shifts', () {
      for (var page = 0; page < 14; page++) {
        expect(readerPageIndexFor(page, -1), page);
      }
    });
  });

  group('the end-of-chapter nav follows the card', () {
    test('it takes the slot after the last page, not after the card', () {
      expect(
        readerNavSlot(pageCount: 14, hasVideoStrip: true),
        15,
        reason: 'a videoAt + 1 nav would land on page 1 when the card is at 0',
      );
      expect(readerNavSlot(pageCount: 14, hasVideoStrip: false), 14);
    });
  });

  group('a full 3-page chapter with the embed first, end to end', () {
    // cosplaytele's real shape: the card, then three photos, then the
    // end-of-chapter nav. Item → page must never drift.
    test('items map to pages 1..3 around slot 0', () {
      const pageCount = 3;
      const videoAt = 0;
      final navAt = readerNavSlot(pageCount: pageCount, hasVideoStrip: true);
      final seen = <int>[];
      final items = pageCount + 1 + 1; // pages + card + nav
      for (var item = 0; item < items; item++) {
        if (item == videoAt || item == navAt) continue;
        seen.add(readerPageIndexFor(item, videoAt) + 1);
      }

      expect(seen, [1, 2, 3], reason: 'every page exactly once, in order');
    });
  });
}
