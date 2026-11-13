import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/webview_dom/webview_chapter_extractor.dart';

void main() {
  group('buildCollectorScript', () {
    test('embeds selectors and attributes', () {
      final script = WebViewChapterExtractor.buildCollectorScript(
        selectors: const ['img[data-chapter-page]'],
        attributes: const ['data-chapter-page', 'src'],
      );
      expect(script, contains('img[data-chapter-page]'));
      expect(script, contains('data-chapter-page'));
      expect(script, contains('verifikasi keamanan gagal'));
      expect(script, contains('challenge'));
    });

    test('disables challenge detection when detectChallenge is false', () {
      final script = WebViewChapterExtractor.buildCollectorScript(
        selectors: const ['img[data-chapter-page]'],
        attributes: const ['data-chapter-page'],
        detectChallenge: false,
      );
      expect(script, contains('var challenge = false;'));
      expect(script, isNot(contains('just a moment')));
    });
  });

  group('parseCollected', () {
    test('parses direct JSON object', () {
      final r = WebViewChapterExtractor.parseCollected(
        '{"images":["https://cdn/x/0.jpg"],"challenge":false}',
      );
      expect(r.images, ['https://cdn/x/0.jpg']);
      expect(r.challenge, isFalse);
    });

    test('parses double-encoded string (Android evaluateJavascript)', () {
      final r = WebViewChapterExtractor.parseCollected(
        r'"{\"images\":[\"https://cdn/x/0.jpg\"],\"challenge\":false}"',
      );
      expect(r.images, ['https://cdn/x/0.jpg']);
      expect(r.challenge, isFalse);
    });

    test('empty, null and null-string yield no images', () {
      for (final raw in <String?>[null, '', 'null']) {
        final r = WebViewChapterExtractor.parseCollected(raw);
        expect(r.images, isEmpty);
        expect(r.challenge, isFalse);
      }
    });

    test('challenge flag survives', () {
      final r = WebViewChapterExtractor.parseCollected(
        '{"images":[],"challenge":true}',
      );
      expect(r.images, isEmpty);
      expect(r.challenge, isTrue);
    });

    test('non-http URLs are dropped', () {
      final r = WebViewChapterExtractor.parseCollected(
        '{"images":["data:image/png;base64,AAA","/rel/path.jpg","https://cdn/x/1.jpg"],"challenge":false}',
      );
      expect(r.images, ['https://cdn/x/1.jpg']);
    });

    test('garbage never throws', () {
      final r = WebViewChapterExtractor.parseCollected('not json {{{');
      expect(r.images, isEmpty);
      expect(r.challenge, isFalse);
    });
  });

  group('fetchChapterImages', () {
    test('returns images from headless eval', () async {
      final extractor = WebViewChapterExtractor();
      final data = await extractor.fetchChapterImages(
        pageUrl: 'https://13.voratoon.com/series/s/chapter/137',
        imageSelectors: const ['img[data-chapter-page]'],
        headlessEval: ({
          required url,
          required script,
          required timeoutMs,
        }) async => '{"images":["https://cdn/x/0.jpg"],"challenge":false}',
      );
      expect(data.images, ['https://cdn/x/0.jpg']);
    });

    test('challenge response throws ReaderChallengeException', () async {
      final extractor = WebViewChapterExtractor();
      expect(
        () => extractor.fetchChapterImages(
          pageUrl: 'https://13.voratoon.com/series/s/chapter/137',
          imageSelectors: const ['img'],
          headlessEval: ({
            required url,
            required script,
            required timeoutMs,
          }) async => '{"images":[],"challenge":true}',
        ),
        throwsA(isA<ReaderChallengeException>()),
      );
    });

    test('empty result yields empty ChapterData (drift candidate)', () async {
      final extractor = WebViewChapterExtractor();
      final data = await extractor.fetchChapterImages(
        pageUrl: 'https://13.voratoon.com/series/s/chapter/137',
        imageSelectors: const ['img'],
        headlessEval: ({
          required url,
          required script,
          required timeoutMs,
        }) async => '',
      );
      expect(data.images, isEmpty);
    });

    test('syncs cookies before eval when provided', () async {
      String? syncedUrl;
      String? syncedCookies;
      final extractor = WebViewChapterExtractor();
      await extractor.fetchChapterImages(
        pageUrl: 'https://13.voratoon.com/series/s/chapter/137',
        imageSelectors: const ['img'],
        cookies: 'cf_clearance=abc; other=1',
        cookieSync: ({required url, required cookies}) async {
          syncedUrl = url;
          syncedCookies = cookies;
          return true;
        },
        headlessEval: ({
          required url,
          required script,
          required timeoutMs,
        }) async => '{"images":[],"challenge":false}',
      );
      expect(syncedUrl, 'https://13.voratoon.com/series/s/chapter/137');
      expect(syncedCookies, 'cf_clearance=abc; other=1');
    });

    test('skips sync when cookies absent', () async {
      var called = false;
      final extractor = WebViewChapterExtractor();
      await extractor.fetchChapterImages(
        pageUrl: 'https://13.voratoon.com/series/s/chapter/137',
        imageSelectors: const ['img'],
        cookieSync: ({required url, required cookies}) async {
          called = true;
          return true;
        },
        headlessEval: ({
          required url,
          required script,
          required timeoutMs,
        }) async => '',
      );
      expect(called, isFalse);
    });

    test('challenge message contains the word challenge', () {
      final e = ReaderChallengeException('https://x/y');
      expect(e.toString().toLowerCase(), contains('challenge'));
    });
  });
}
