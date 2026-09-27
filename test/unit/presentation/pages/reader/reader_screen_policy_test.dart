import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_screen.dart';

void main() {
  group('ReaderScreen heavy-image auto-switch policy', () {
    test('skips auto-switch for heavy-image sources', () {
      for (final id in ['manga18.club', 'ehentai', 'komiktap']) {
        expect(
          ReaderScreen.shouldSkipHeavyImageAutoSwitchForSource(id),
          isTrue,
          reason: '$id must keep webtoon/dual-page mode',
        );
      }
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitchForSource('MANGA18.CLUB'),
        isTrue,
      );
    });

    test('keeps auto-switch enabled for other sources', () {
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitchForSource('nhentai'),
        isFalse,
      );
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitchForSource(''),
        isFalse,
      );
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitchForSource(null),
        isFalse,
      );
    });
  });
}
