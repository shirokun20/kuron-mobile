import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_special/src/webview_dom/webview_chapter_extractor.dart';
import 'package:kuron_special/src/webview_dom/webview_dom_reader_source.dart';
import 'package:logger/logger.dart';

GenericHttpSource _inner() => GenericHttpSource(
  rawConfig: const {
    'source': 'komikcast',
    'baseUrl': 'https://13.voratoon.com',
  },
  dio: Dio(),
  logger: Logger(level: Level.off),
);

WebViewDomReaderSource _source({
  required Future<ChapterData> Function() fetch,
  InteractivePageCollector? interactiveCollect,
}) {
  return WebViewDomReaderSource(
    inner: _inner(),
    extractor: _FakeExtractor(fetch),
    baseUrl: 'https://13.voratoon.com/',
    imageSelectors: const ['img[data-chapter-page]'],
    imageAttributes: const ['data-chapter-page', 'src'],
    interactiveCollect: interactiveCollect,
    logger: Logger(level: Level.off),
  );
}

class _FakeExtractor extends WebViewChapterExtractor {
  _FakeExtractor(this._fetch);

  final Future<ChapterData> Function() _fetch;

  @override
  Future<ChapterData> fetchChapterImages({
    required String pageUrl,
    required List<String> imageSelectors,
    List<String> imageAttributes = const ['src'],
    Duration timeout = const Duration(seconds: 20),
    HeadlessEval? headlessEval,
    Future<bool?> Function({required String url, required String cookies})?
    cookieSync,
    String? cookies,
  }) => _fetch();
}

void main() {
  test('pageUrlFor handles path, bare and absolute ids', () {
    final s = _source(fetch: () async => const ChapterData(images: []));
    expect(
      s.pageUrlFor('/series/slug/chapter/137'),
      'https://13.voratoon.com/series/slug/chapter/137',
    );
    expect(
      s.pageUrlFor('series/slug/chapter/137'),
      'https://13.voratoon.com/series/slug/chapter/137',
    );
    expect(s.pageUrlFor('https://other.com/c/1'), 'https://other.com/c/1');
  });

  test('non-empty images pass through', () async {
    final s = _source(
      fetch: () async => const ChapterData(images: ['https://cdn/x/0.jpg']),
    );
    final data = await s.getChapterImages('/series/s/chapter/1');
    expect(data?.images, ['https://cdn/x/0.jpg']);
  });

  test('empty images stay empty (drift candidate for detector)', () async {
    final s = _source(fetch: () async => const ChapterData(images: []));
    final data = await s.getChapterImages('/series/s/chapter/1');
    expect(data, isNotNull);
    expect(data!.images, isEmpty);
  });

  test('challenge error propagates (never swallowed)', () async {
    final s = _source(
      fetch: () async => throw ReaderChallengeException('https://x/y'),
    );
    expect(
      () => s.getChapterImages('/series/s/chapter/1'),
      throwsA(isA<ReaderChallengeException>()),
    );
  });

  test('delegates identity to inner source', () {
    final s = _source(fetch: () async => const ChapterData(images: []));
    expect(s.id, 'komikcast');
    expect(s.baseUrl, 'https://13.voratoon.com');
  });

  test('falls back to interactive WebView on challenge and returns images', () async {
    String? capturedUrl;
    String? capturedScript;
    final s = _source(
      fetch: () async => throw ReaderChallengeException(
        'https://13.voratoon.com/series/s/chapter/1',
      ),
      interactiveCollect: (pageUrl, script) async {
        capturedUrl = pageUrl;
        capturedScript = script;
        return r'"{\"images\":[\"https://cdn/x/0.jpg\"],\"challenge\":false}"';
      },
    );
    final data = await s.getChapterImages('/series/s/chapter/1');
    expect(capturedUrl, 'https://13.voratoon.com/series/s/chapter/1');
    expect(capturedScript, contains('var challenge = false;'));
    expect(data?.images, ['https://cdn/x/0.jpg']);
  });

  test(
    'falls back to interactive WebView when headless returns empty',
    () async {
      final s = _source(
        fetch: () async => const ChapterData(images: []),
        interactiveCollect: (pageUrl, script) async =>
            '{"images":["https://cdn/x/1.jpg"],"challenge":false}',
      );
      final data = await s.getChapterImages('/series/s/chapter/1');
      expect(data?.images, ['https://cdn/x/1.jpg']);
    },
  );

  test(
    'rethrows ReaderChallengeException if interactive fallback is cancelled',
    () async {
      final s = _source(
        fetch: () async => throw ReaderChallengeException('https://x/y'),
        interactiveCollect: (pageUrl, script) async => null,
      );
      expect(
        () => s.getChapterImages('/series/s/chapter/1'),
        throwsA(isA<ReaderChallengeException>()),
      );
    },
  );

  test('caches chapter images and skips headless on same host after fallback', () async {
    var headlessCalls = 0;
    var interactiveCalls = 0;
    final s = _source(
      fetch: () async {
        headlessCalls++;
        return const ChapterData(images: []);
      },
      interactiveCollect: (pageUrl, script) async {
        interactiveCalls++;
        return '{"images":["https://cdn/x/$interactiveCalls.jpg"],"challenge":false}';
      },
    );

    final ch1a = await s.getChapterImages('/series/s/chapter/1');
    expect(ch1a?.images, ['https://cdn/x/1.jpg']);
    expect(headlessCalls, 1);
    expect(interactiveCalls, 1);

    final ch1b = await s.getChapterImages('/series/s/chapter/1');
    expect(ch1b?.images, ['https://cdn/x/1.jpg']);
    expect(headlessCalls, 1);
    expect(interactiveCalls, 1);

    final ch2 = await s.getChapterImages('/series/s/chapter/2');
    expect(ch2?.images, ['https://cdn/x/2.jpg']);
    expect(headlessCalls, 1);
    expect(interactiveCalls, 2);
  });
}
