import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';

void _expectSafeNetworkProviderCacheKey(
  WidgetTester tester,
  String expectedKey,
) {
  final extendedImage = tester.widget<ExtendedImage>(
    find.byType(ExtendedImage),
  );
  // gaplessPlayback keeps the previous frame visible instead of flashing the
  // placeholder when the provider key changes (flicker regression guard).
  expect(extendedImage.gaplessPlayback, isTrue);
  ImageProvider<Object> provider = extendedImage.image;
  if (provider is ExtendedResizeImage) {
    provider = provider.imageProvider;
  }
  expect(provider, isA<ExtendedNetworkImageProvider>());
  final cacheKey = (provider as ExtendedNetworkImageProvider).cacheKey;
  expect(cacheKey, expectedKey);
  expect(cacheKey, matches(RegExp(r'^[0-9a-f]{32}$')));
  expect(cacheKey, isNot(contains('/')));
  expect(cacheKey, isNot(contains(':')));
  expect(cacheKey, isNot(contains('?')));
  expect(cacheKey, isNot(contains(' ')));
}

Widget _harness(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProgressiveImageWidget.shouldSuppressOfflineThumbnailForTesting', () {
    test('returns true for animated fallback page image', () {
      expect(
        ProgressiveImageWidget.shouldSuppressOfflineThumbnailForTesting(
          localPath: '/storage/emulated/0/nhasix/ehentai/123/images/14.webp',
          fileBytes: 128 * 1024,
          isAnimated: true,
        ),
        isTrue,
      );
    });

    test('returns false for dedicated heavy cover asset', () {
      expect(
        ProgressiveImageWidget.shouldSuppressOfflineThumbnailForTesting(
          localPath: '/storage/emulated/0/nhasix/ehentai/123/images/cover.jpg',
          fileBytes:
              ProgressiveImageWidget
                  .heavyAnimatedThumbnailThresholdBytesForTesting +
              1,
          isAnimated: false,
        ),
        isFalse,
      );
    });

    test('returns true for heavy non-animated fallback thumbnail', () {
      expect(
        ProgressiveImageWidget.shouldSuppressOfflineThumbnailForTesting(
          localPath: '/storage/emulated/0/nhasix/ehentai/123/images/14.jpg',
          fileBytes:
              ProgressiveImageWidget
                  .heavyAnimatedThumbnailThresholdBytesForTesting +
              1,
          isAnimated: false,
        ),
        isTrue,
      );
    });

    test('returns false for lightweight static fallback thumbnail', () {
      expect(
        ProgressiveImageWidget.shouldSuppressOfflineThumbnailForTesting(
          localPath: '/storage/emulated/0/nhasix/ehentai/123/images/14.jpg',
          fileBytes:
              ProgressiveImageWidget
                  .heavyAnimatedThumbnailThresholdBytesForTesting -
              1,
          isAnimated: false,
        ),
        isFalse,
      );
    });
  });

  group(
    'ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting',
    () {
      test('returns true for webp URL', () {
        expect(
          ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting(
            'https://cdn.manga18.club/manga/title/cover/cover_thumb_2.webp',
            isThumbnail: true,
          ),
          isTrue,
        );
      });

      test('returns true for avif URL with query string', () {
        expect(
          ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting(
            'https://example.com/image.avif?token=123',
            isThumbnail: true,
          ),
          isTrue,
        );
      });

      test('returns false for jpeg URL', () {
        expect(
          ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting(
            'https://example.com/image.jpg',
            isThumbnail: true,
          ),
          isFalse,
        );
      });

      test('returns false for reader-like page image surface', () {
        expect(
          ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting(
            'https://images.hentainexus.com/v2/foo/001.webp',
            pageNumber: 1,
            isThumbnail: false,
          ),
          isFalse,
        );
      });

      test('returns false for malformed URL', () {
        expect(
          ProgressiveImageWidget.shouldUseStaticNetworkDecodeFallbackForTesting(
            'not a valid url',
            isThumbnail: true,
          ),
          isFalse,
        );
      });
    },
  );

  group('ProgressiveImageWidget.buildSafeDiskCacheKey', () {
    const url = 'https://cdn.example.com/a/b/cover.jpg?token=abc%20def';
    final safeKey = RegExp(r'^[0-9a-f]{32}$');

    test('raw URL becomes a 32-hex MD5 with no filename-unsafe characters', () {
      final key = ProgressiveImageWidget.buildSafeDiskCacheKey(url);

      expect(key, matches(safeKey));
      expect(key, isNot(contains('/')));
      expect(key, isNot(contains(':')));
      expect(key, isNot(contains('?')));
      expect(key, isNot(contains(' ')));
    });

    test('is deterministic and independent of header insertion order', () {
      final first = ProgressiveImageWidget.buildSafeDiskCacheKey(
        url,
        headers: const {
          'Referer': 'https://example.com/',
          'User-Agent': 'Mozilla/5.0',
        },
      );
      final reversed = ProgressiveImageWidget.buildSafeDiskCacheKey(
        url,
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://example.com/',
        },
      );

      expect(first, matches(safeKey));
      expect(reversed, first);
    });

    test('Referer changes the key but keeps it filesystem-safe', () {
      final bare = ProgressiveImageWidget.buildSafeDiskCacheKey(url);
      final withReferer = ProgressiveImageWidget.buildSafeDiskCacheKey(
        url,
        headers: const {'Referer': 'https://example.com/'},
      );
      final otherReferer = ProgressiveImageWidget.buildSafeDiskCacheKey(
        url,
        headers: const {'Referer': 'https://other.example.com/'},
      );

      expect(withReferer, matches(safeKey));
      expect(withReferer, isNot(bare));
      expect(withReferer, isNot(otherReferer));
    });

    test('composite reader key is hashed as well', () {
      final key = ProgressiveImageWidget.buildSafeDiskCacheKey(
        'content-42_page_7_-123456789',
      );

      expect(key, matches(safeKey));
    });
  });

  testWidgets(
    'ProgressiveImageWidget (no headers) renders with safe cacheKey',
    (tester) async {
      const url = 'https://cdn.example.com/a/cover.jpg?token=abc';

      await tester.pumpWidget(
        _harness(
          SizedBox(
            width: 120,
            height: 160,
            child: ProgressiveImageWidget(
              networkUrl: url,
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectSafeNetworkProviderCacheKey(
        tester,
        ProgressiveImageWidget.buildSafeDiskCacheKey(url),
      );
    },
  );

  testWidgets(
    'ProgressiveImageWidget with Referer renders with safe cacheKey',
    (tester) async {
      const url = 'https://cdn.example.com/a/cover.jpg';
      const headers = <String, String>{'Referer': 'https://example.com/'};

      await tester.pumpWidget(
        _harness(
          SizedBox(
            width: 120,
            height: 160,
            child: ProgressiveImageWidget(
              networkUrl: url,
              httpHeaders: headers,
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectSafeNetworkProviderCacheKey(
        tester,
        ProgressiveImageWidget.buildSafeDiskCacheKey(url, headers: headers),
      );
    },
  );

  testWidgets(
    'ProgressiveThumbnailWidget with Referer renders with safe cacheKey',
    (tester) async {
      const url = 'https://cdn.example.com/a/thumb.webp?x=1';
      const headers = <String, String>{
        'Referer': 'https://example.com/',
        'User-Agent': 'Mozilla/5.0',
      };

      await tester.pumpWidget(
        _harness(
          SizedBox(
            width: 120,
            child: ProgressiveThumbnailWidget(
              networkUrl: url,
              httpHeaders: headers,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectSafeNetworkProviderCacheKey(
        tester,
        ProgressiveImageWidget.buildSafeDiskCacheKey(url, headers: headers),
      );
    },
  );
}
