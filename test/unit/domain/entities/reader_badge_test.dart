import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';

void main() {
  group('readerTierFor thresholds', () {
    test('zero completions is santai', () {
      expect(readerTierFor(completedCount: 0), ReaderTier.santai);
    });

    test('boundary values map to the right tier', () {
      expect(readerTierFor(completedCount: 1), ReaderTier.santai);
      expect(readerTierFor(completedCount: 9), ReaderTier.santai);
      expect(readerTierFor(completedCount: 10), ReaderTier.kutubuku);
      expect(readerTierFor(completedCount: 49), ReaderTier.kutubuku);
      expect(readerTierFor(completedCount: 50), ReaderTier.otaku);
      expect(readerTierFor(completedCount: 199), ReaderTier.otaku);
      expect(readerTierFor(completedCount: 200), ReaderTier.resi);
      expect(readerTierFor(completedCount: 5000), ReaderTier.resi);
    });

    test('non-hentai top source never overrides', () {
      expect(
        readerTierFor(completedCount: 150, topSourceId: 'komikcast'),
        ReaderTier.otaku,
      );
    });
  });

  group('shaker override', () {
    test('curated hentai ids override any count', () {
      for (final id in [
        'nhentai',
        'ehentai',
        'hentainexus',
        'hitomi',
        'manga18.club',
        'NHENTAI',
        ' komikdewasa ',
      ]) {
        expect(
          readerTierFor(completedCount: 150, topSourceId: id),
          ReaderTier.shaker,
          reason: id,
        );
      }
    });

    test('hentai/hanime prefixes override', () {
      expect(
        readerTierFor(completedCount: 3, topSourceId: 'hentai-abc'),
        ReaderTier.shaker,
      );
      expect(
        readerTierFor(completedCount: 3, topSourceId: 'hanime_xyz'),
        ReaderTier.shaker,
      );
    });

    test('lookalikes do not override', () {
      expect(
        readerTierFor(completedCount: 60, topSourceId: 'hentong'),
        ReaderTier.otaku,
      );
      expect(
        readerTierFor(completedCount: 60, topSourceId: ''),
        ReaderTier.otaku,
      );
      expect(readerTierFor(completedCount: 60), ReaderTier.otaku);
    });
  });

  group('isHentaiSource', () {
    test('case and whitespace insensitive', () {
      expect(isHentaiSource('NHeNtAi'), isTrue);
      expect(isHentaiSource('komikcast'), isFalse);
    });
  });
}
