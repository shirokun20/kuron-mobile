import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
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

  group('ReaderScreen initial offline detection policy', () {
    Content buildTestContent({
      required String id,
      required String coverUrl,
      required List<String> imageUrls,
    }) {
      return Content(
        id: id,
        sourceId: 'test_source',
        title: 'Title',
        coverUrl: coverUrl,
        tags: const [],
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: 'english',
        pageCount: imageUrls.length,
        imageUrls: imageUrls,
        uploadDate: DateTime.parse('2026-01-01T00:00:00Z'),
      );
    }

    test('returns true when fromOffline is true regardless of preloaded content', () {
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: true,
          preloadedContent: null,
        ),
        isTrue,
      );

      final onlineContent = buildTestContent(
        id: 'c1',
        coverUrl: 'https://example.com/cover.jpg',
        imageUrls: const ['https://example.com/1.jpg'],
      );
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: true,
          preloadedContent: onlineContent,
        ),
        isTrue,
      );
    });

    test('returns false when fromOffline is false and content is null or remote', () {
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: false,
          preloadedContent: null,
        ),
        isFalse,
      );

      final onlineContent = buildTestContent(
        id: 'c1',
        coverUrl: 'https://example.com/cover.jpg',
        imageUrls: const [
          'https://example.com/1.jpg',
          'https://example.com/2.jpg',
        ],
      );
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: false,
          preloadedContent: onlineContent,
        ),
        isFalse,
      );
    });

    test('returns true when fromOffline is false but preloaded images are local', () {
      final offlineContent = buildTestContent(
        id: 'c1',
        coverUrl: '/data/user/0/id.nhasix.app/app_flutter/covers/c1.jpg',
        imageUrls: const [
          '/data/user/0/id.nhasix.app/app_flutter/downloads/c1/1.jpg',
          '/data/user/0/id.nhasix.app/app_flutter/downloads/c1/2.jpg',
        ],
      );
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: false,
          preloadedContent: offlineContent,
        ),
        isTrue,
      );

      final fileUriContent = buildTestContent(
        id: 'c2',
        coverUrl: 'file:///path/to/cover.jpg',
        imageUrls: const ['file:///path/to/1.jpg'],
      );
      expect(
        ReaderScreen.determineInitialIsOffline(
          fromOffline: false,
          preloadedContent: fileUriContent,
        ),
        isTrue,
      );
    });
  });
}
