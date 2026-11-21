import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/utils/chapter_order_utils.dart';

Chapter _chapter(
  String id, {
  required String title,
  String? url,
  String? scanGroup,
  bool isUnavailable = false,
  String? externalUrl,
  int? pages,
}) => Chapter(
  id: id,
  title: title,
  url: url ?? '/$id',
  scanGroup: scanGroup,
  isUnavailable: isUnavailable,
  externalUrl: externalUrl,
  pages: pages,
);

/// Deterministic, valid UUID (8-4-4-4-12 hex) for MangaDex-style IDs.
String _uuid(int n) =>
    '9f8e7d6c-1a2b-4c3d-8e4f-${n.toString().padLeft(12, '0')}';

void main() {
  group('parseChapterNumber / parseVolumeNumber', () {
    test('parses Chapter, Ch., Bab, Ep. and 第...話 formats', () {
      expect(ChapterOrderUtils.parseChapterNumber('Chapter 12'), 12);
      expect(ChapterOrderUtils.parseChapterNumber('Ch. 3'), 3);
      expect(ChapterOrderUtils.parseChapterNumber('Bab 1'), 1);
      expect(ChapterOrderUtils.parseChapterNumber('Ep. 2'), 2);
      expect(ChapterOrderUtils.parseChapterNumber('第3話'), 3);
      expect(ChapterOrderUtils.parseChapterNumber('Chapter 12.5'), 12.5);
      expect(ChapterOrderUtils.parseChapterNumber('Chapter 2,5'), 2.5);
    });

    test('never extracts a number from a UUID', () {
      expect(ChapterOrderUtils.parseChapterNumber(_uuid(9)), isNull);
      expect(ChapterOrderUtils.parseChapterNumber('Prologue'), isNull);
    });

    test('parses volume only for an explicit volume tag', () {
      expect(ChapterOrderUtils.parseVolumeNumber('Vol. 2 Ch. 3'), 2);
      expect(ChapterOrderUtils.parseVolumeNumber('Volume 4'), 4);
      expect(ChapterOrderUtils.parseVolumeNumber('Chapter 3'), isNull);
    });
  });

  group('extractOrder', () {
    test('title wins and volume is captured', () {
      final order = ChapterOrderUtils.extractOrder(
        _chapter('v1c1', title: 'Vol. 1 Ch. 1'),
      );
      expect(order?.chapter, 1);
      expect(order?.volume, 1);
    });

    test('falls back to a non-UUID url slug when the title has no number', () {
      final order = ChapterOrderUtils.extractOrder(
        _chapter('prologue-id', title: 'Prologue', url: '/chapter-12/prologue'),
      );
      expect(order?.chapter, 12);
      expect(order?.volume, isNull);
    });

    test('does not fall back into a UUID id/url', () {
      expect(
        ChapterOrderUtils.extractOrder(
          _chapter(_uuid(9), title: 'Prologue', url: _uuid(9)),
        ),
        isNull,
      );
    });
  });

  group('compareOrder', () {
    test('compares volume only when both chapters declare one', () {
      final withVolume = _chapter('v1c1', title: 'Vol. 1 Ch. 1');
      final withoutVolume = _chapter('c2', title: 'Ch. 2');

      expect(
        ChapterOrderUtils.compareOrder(withVolume, withoutVolume),
        lessThan(0),
      );
      expect(
        ChapterOrderUtils.compareOrder(withoutVolume, withVolume),
        greaterThan(0),
      );
    });

    test('returns null for unnumbered chapters', () {
      expect(
        ChapterOrderUtils.compareOrder(
          _chapter('a', title: 'Prologue'),
          _chapter('b', title: 'Epilogue'),
        ),
        isNull,
      );
    });
  });

  group('isAscendingPool', () {
    test('detects direction from a numbered pool', () {
      final c1 = _chapter('c1', title: 'Chapter 1');
      final c2 = _chapter('c2', title: 'Chapter 2');
      final c3 = _chapter('c3', title: 'Chapter 3');

      expect(ChapterOrderUtils.isAscendingPool([c1, c2, c3]), isTrue);
      expect(ChapterOrderUtils.isAscendingPool([c3, c2, c1]), isFalse);
    });

    test('returns null when nothing is numbered', () {
      expect(
        ChapterOrderUtils.isAscendingPool([
          _chapter('a', title: 'Prologue'),
          _chapter('b', title: 'Oneshot'),
        ]),
        isNull,
      );
    });
  });

  group('resolveAdjacentChapter', () {
    test('MangaDex descending order: lowest chapter has no previous', () {
      final pool = [
        for (var n = 10; n >= 1; n--)
          _chapter('id-$n', title: 'Ch. $n', url: _uuid(n)),
      ];
      final chapterOne = pool.last;

      final next = ChapterOrderUtils.resolveAdjacentChapter(
        pool: pool,
        currentChapter: chapterOne,
        step: 1,
      );
      final previous = ChapterOrderUtils.resolveAdjacentChapter(
        pool: pool,
        currentChapter: chapterOne,
        step: -1,
      );

      expect(next?.id, 'id-2');
      expect(previous, isNull);
    });

    test('mixed Vol. tag bug — ascending and descending pools', () {
      final v1c1 = _chapter('v1c1', title: 'Vol. 1 Ch. 1');
      final c2 = _chapter('c2', title: 'Ch. 2');
      final c3 = _chapter('c3', title: 'Ch. 3');

      for (final pool in [
        [v1c1, c2, c3],
        [c3, c2, v1c1],
      ]) {
        // In both pools the current chapter is the one declaring Vol. 1.
        expect(
          ChapterOrderUtils.resolveAdjacentChapter(
            pool: pool,
            currentChapter: v1c1,
            step: 1,
          )?.id,
          'c2',
        );
        expect(
          ChapterOrderUtils.resolveAdjacentChapter(
            pool: pool,
            currentChapter: v1c1,
            step: -1,
          ),
          isNull,
        );
      }
    });

    test('skips duplicate scanlation-group entries of the same chapter', () {
      final ch2GroupA = _chapter('ch2-a', title: 'Ch. 2', scanGroup: 'Group A');
      final ch1GroupB = _chapter('ch1-b', title: 'Ch. 1', scanGroup: 'Group B');
      final ch1GroupA = _chapter('ch1-a', title: 'Ch. 1', scanGroup: 'Group A');
      final pool = [ch2GroupA, ch1GroupB, ch1GroupA];

      final fromGroupA = ChapterOrderUtils.resolveAdjacentChapter(
        pool: pool,
        currentChapter: ch1GroupA,
        step: 1,
      );
      expect(fromGroupA?.id, 'ch2-a');
      expect(fromGroupA?.scanGroup, 'Group A');

      final fromGroupB = ChapterOrderUtils.resolveAdjacentChapter(
        pool: pool,
        currentChapter: ch1GroupB,
        step: 1,
      );
      expect(fromGroupB?.id, 'ch2-a');

      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: ch1GroupA,
          step: -1,
        ),
        isNull,
      );
    });

    test('skips external, unavailable and zero-page chapters', () {
      final c1 = _chapter('c1', title: 'Chapter 1');
      final pool = [
        c1,
        _chapter(
          'c2-ext',
          title: 'Chapter 2',
          externalUrl: 'https://example.com/ch2',
        ),
        _chapter('c3-unavailable', title: 'Chapter 3', isUnavailable: true),
        _chapter('c4-no-pages', title: 'Chapter 4', pages: 0),
        _chapter('c5', title: 'Chapter 5'),
      ];

      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: c1,
          step: 1,
        )?.id,
        'c5',
      );
      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: pool.last,
          step: -1,
        )?.id,
        'c1',
      );
    });

    test('unnumbered chapters fall back to index stepping', () {
      final pool = [
        _chapter('a', title: 'Prologue'),
        _chapter('b', title: 'Oneshot'),
        _chapter('c', title: 'Epilogue'),
      ];

      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: pool.first,
          step: 1,
        )?.id,
        'b',
      );
      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: pool.first,
          step: -1,
        ),
        isNull,
      );
      expect(
        ChapterOrderUtils.resolveAdjacentChapter(
          pool: pool,
          currentChapter: pool.last,
          step: -1,
        )?.id,
        'b',
      );
    });
  });
}
