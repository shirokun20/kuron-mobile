import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_screen.dart';

Map<String, dynamic> _config({bool? heavyImageAutoSwitch}) => {
      'source': 'example',
      'scraper': {
        'selectors': {
          'reader': {
            'heavyImageAutoSwitch': ?heavyImageAutoSwitch,
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
          rawConfig: _config(heavyImageAutoSwitch: false),
        ),
        isTrue,
        reason: 'webtoon / dual-page source keeps continuous scroll',
      );
    });

    test('config flag can also opt a source in', () {
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          rawConfig: _config(heavyImageAutoSwitch: true),
        ),
        isFalse,
        reason: 'declared true keeps auto-switch enabled',
      );
    });

    test('undeclared sources keep auto-switch enabled', () {
      // Purely config-driven: no hardcoded source list. Sources without
      // the flag (or without config) auto-switch on heavy images.
      for (final id in ['manga18.club', 'ehentai', 'komiktap', 'nhentai']) {
        expect(
          ReaderScreen.shouldSkipHeavyImageAutoSwitch(
            rawConfig: _config(),
          ),
          isFalse,
          reason: '$id without the flag must auto-switch',
        );
      }
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(),
        isFalse,
      );
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(rawConfig: null),
        isFalse,
      );
    });

    test('a non-boolean flag value falls back instead of guessing', () {
      final raw = _config();
      final reader = (((raw['scraper']! as Map)['selectors']! as Map)['reader']!
          as Map<String, dynamic>);
      reader['heavyImageAutoSwitch'] = 'false';
      expect(
        ReaderScreen.shouldSkipHeavyImageAutoSwitch(
          rawConfig: raw,
        ),
        isFalse,
      );
    });
  });
}
