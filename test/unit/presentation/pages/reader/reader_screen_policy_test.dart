import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_screen.dart';

Map<String, dynamic> _config({bool? heavyImageAutoSwitch}) => {
      'source': 'example',
      'scraper': {
        'selectors': {
          'reader': {
            if (heavyImageAutoSwitch != null)
              'heavyImageAutoSwitch': heavyImageAutoSwitch,
            'images': {'selector': 'img', 'attribute': 'src'},
          },
        },
      },
    };

void main() {
  group('ReaderScreen heavy-image auto-switch policy', () {
    test('config flag opts a source out', () {
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          sourceId: 'mangapedia',
          rawConfig: _config(heavyImageAutoSwitch: false),
        ),
        isTrue,
        reason: 'webtoon / dual-page source keeps continuous scroll',
      );
    });

    test('config flag can also opt a source in', () {
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          sourceId: 'manga18.club',
          rawConfig: _config(heavyImageAutoSwitch: true),
        ),
        isFalse,
        reason: 'declared true overrides the legacy source list',
      );
    });

    test('legacy source list still applies without the flag', () {
      for (final id in ['manga18.club', 'ehentai', 'komiktap']) {
        expect(
          ReaderScreen.shouldSkipHeavyImageAutoSwitch(
            sourceId: id,
            rawConfig: _config(),
          ),
          isTrue,
          reason: '$id must keep webtoon/dual-page mode',
        );
        expect(
          ReaderScreen.shouldSkipHeavyImageAutoSwitch(
              sourceId: id.toUpperCase()),
          isTrue,
        );
      }
    });

    test('other sources keep auto-switch enabled', () {
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          sourceId: 'nhentai',
          rawConfig: _config(),
        ),
        isFalse,
      );
      for (final id in [null, '', 'nhentai']) {
        expect(
          ReaderScreen.shouldSkipHeavyImageAutoSwitch(sourceId: id),
          isFalse,
        );
      }
    });

    test('a non-boolean flag value falls back instead of guessing', () {
      final raw = _config();
      final reader = (((raw['scraper']! as Map)['selectors']! as Map)['reader']!
          as Map<String, dynamic>);
      reader['heavyImageAutoSwitch'] = 'false';
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          sourceId: 'komiktap',
          rawConfig: raw,
        ),
        isTrue,
      );
    });
  });
}
