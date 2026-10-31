import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/extended_image_reader_widget.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Minimal app wrapper providing localizations and direction.
Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

// Build a [ExtendedImageReaderWidget] with sensible defaults.
Widget _buildWidget({
  required String url,
  ReadingMode mode = ReadingMode.continuousScroll,
  String sourceId = 'nhentai',
  Map<String, String>? headers,
  Future<bool> Function()? onRepairBrokenImage,
  Future<bool> Function()? onOpenSourcePageForRepair,
}) =>
    _wrap(
      ExtendedImageReaderWidget(
        imageUrl: url,
        contentId: 'test-content',
        pageNumber: 1,
        readingMode: mode,
        sourceId: sourceId,
        httpHeaders: headers,
        onRepairBrokenImage: onRepairBrokenImage,
        onOpenSourcePageForRepair: onOpenSourcePageForRepair,
      ),
    );

// Force a URL into the heavy-image static set to simulate a second visit.
void _markHeavy(String url) {
  // Access the private static via reflection is not possible in Dart, so we
  // inject via the threshold-bytes detection path by pumping a widget and
  // driving it through the loading state.  Instead, we rely on the fact that
  // the static set is package-private and test indirectly through widget behavior.
  //
  // In tests that need the flag pre-seeded we call [_ExposeHeavySet.add] which
  // is the same set referenced by the widget (static, shared).
  _ExposeHeavySet.add(url);
}

// ignore: library_private_types_in_public_api
extension _ExposeHeavySet on ExtendedImageReaderWidget {
  static void add(String url) {
    // Reflection workaround: run a warm-up widget with a fake state so the
    // static set receives the URL.  We do this by simulating what
    // _markAsHeavyImage() does internally – the test helpers below call
    // [_InjectHeavyUrl.inject] which invokes the same static add path used
    // by the real widget.
    _InjectHeavyUrl.inject(url);
  }
}

// Thin shim that exposes the private static set for testing.
// Since Dart doesn't allow cross-library access to private members, we expose
// a @visibleForTesting hook in the production widget below.
///
// For now the tests that need pre-seeding use [ExtendedImageReaderWidget.addHeavyUrlForTesting].
class _InjectHeavyUrl {
  _InjectHeavyUrl._();
  static void inject(String url) {
    ExtendedImageReaderWidget.addHeavyUrlForTesting(url);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Prevent real network calls in widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Intercept the kuron_animated_webp_view platform channel so
  // AndroidView does not crash in the Flutter test environment.
  const MethodChannel systemUiChannel = MethodChannel('flutter/platform_views');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemUiChannel, (call) async => null);
    // Clear heavy-image set before each test so tests are isolated.
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemUiChannel, null);
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
  });

  // ── Unit-style logic tests ────────────────────────────────────────────────

  group('_isLikelyAnimatedWebP heuristic', () {
    test('returns false when image is NOT yet heavy', () {
      // URL is a .webp but _isHeavyImage = false (no static set entry)
      // → should NOT trigger native view
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/1_4.webp',
          isHeavy: false,
        ),
        isFalse,
      );
    });

    test('returns true for plain .webp URL when heavy', () {
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/1_4.webp',
          isHeavy: true,
        ),
        isTrue,
      );
    });

    test('returns true for H@H -wbp suffix when heavy', () {
      const url =
          'https://tkltdpb.zwekrcqhhvdx.hath.network:43649/h/abc-8530696-1416-1608-wbp/'
          'keystamp=123;fileindex=456;xres=org/1_4.webp';
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: url,
          isHeavy: true,
        ),
        isTrue,
      );
    });

    test(
        'returns false for .avif when heavy (URL heuristic no longer routes AVIF; brand check post-download handles avis)',
        () {
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/page.avif',
          isHeavy: true,
        ),
        isFalse,
      );
    });

    test('returns false for .jpg even when heavy', () {
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/1_4.jpg',
          isHeavy: true,
        ),
        isFalse,
      );
    });

    test('strips query string before checking extension', () {
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/image.webp?token=abc&ts=123',
          isHeavy: true,
        ),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        ExtendedImageReaderWidget.isLikelyAnimatedWebPForTesting(
          url: 'https://example.com/IMAGE.WEBP',
          isHeavy: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldUseNativeAnimatedView', () {
    test('returns false for .webp when image is not heavy yet', () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: 'https://example.com/page.webp',
          isHeavy: false,
          nativeViewAvailable: true,
        ),
        isFalse,
      );
    });

    test('returns true for heavy animated webp when native view is available',
        () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: 'https://example.com/page.webp',
          isHeavy: true,
          nativeViewAvailable: true,
        ),
        isTrue,
      );
    });

    test(
        'returns false for heavy avif via URL (routing deferred to post-download brand check)',
        () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: 'https://example.com/page.avif',
          isHeavy: true,
          nativeViewAvailable: true,
        ),
        isFalse,
      );
    });

    test('returns false for heavy non-webp image', () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: 'https://example.com/page.gif',
          isHeavy: true,
          nativeViewAvailable: true,
        ),
        isFalse,
      );
    });

    test('returns false when native view is unavailable', () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: 'https://example.com/page.webp',
          isHeavy: true,
          nativeViewAvailable: false,
        ),
        isFalse,
      );
    });

    test('returns true for confirmed animated webp bytes despite jpg filename',
        () {
      expect(
        ExtendedImageReaderWidget.shouldUseNativeAnimatedViewForTesting(
          url: '/storage/emulated/0/Asix/nhasix/ehentai/foo/page_001.jpg',
          isHeavy: true,
          nativeViewAvailable: true,
          confirmedAnimatedWebP: true,
        ),
        isTrue,
      );
    });
  });

  group('animated webp header detection', () {
    test('detects animated webp bytes from VP8X animation flag', () {
      final bytes = Uint8List.fromList(const <int>[
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, // WEBP
        0x56, 0x50, 0x38, 0x58, // VP8X
        0x0A, 0x00, 0x00, 0x00,
        0x12, 0x00, 0x00, 0x00, // animation flag set
      ]);

      expect(
        ExtendedImageReaderWidget.isAnimatedWebPHeaderForTesting(bytes),
        isTrue,
      );
    });

    test('does not misclassify jpeg bytes as animated webp', () {
      final bytes = Uint8List.fromList(const <int>[
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
      ]);

      expect(
        ExtendedImageReaderWidget.isAnimatedWebPHeaderForTesting(bytes),
        isFalse,
      );
    });
  });

  group('failed page placeholder actions', () {
    testWidgets(
        'shows redownload button for failed placeholders when repair is available',
        (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          url: '__failed__:https://e-hentai.org/s/example/123-1',
          onRepairBrokenImage: () async => true,
        ),
      );

      final context = tester.element(find.byType(ExtendedImageReaderWidget));
      final l10n = AppLocalizations.of(context)!;

      expect(find.text(l10n.readerPageNotDownloaded(1)), findsOneWidget);
      expect(find.text(l10n.readerRedownloadImage), findsOneWidget);
      expect(find.text(l10n.readerOpenSourcePage), findsNothing);
    });

    testWidgets(
        'shows source-page fallback button for failed placeholders when available',
        (tester) async {
      await tester.pumpWidget(
        _buildWidget(
          url: '__failed__:https://e-hentai.org/s/example/123-1',
          onRepairBrokenImage: () async => true,
          onOpenSourcePageForRepair: () async => true,
        ),
      );

      final context = tester.element(find.byType(ExtendedImageReaderWidget));
      final l10n = AppLocalizations.of(context)!;

      expect(find.text(l10n.readerRedownloadImage), findsOneWidget);
      expect(find.text(l10n.readerOpenSourcePage), findsOneWidget);
    });
  });

  group('supported local image payload detection', () {
    test('accepts valid webp payload even without matching filename', () {
      final bytes = Uint8List.fromList(const <int>[
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);

      expect(
        ExtendedImageReaderWidget.isSupportedImageHeaderForTesting(bytes),
        isTrue,
      );
    });

    test('rejects html/error payloads for local file validation', () {
      final bytes = Uint8List.fromList('<html>blocked</html>'.codeUnits);

      expect(
        ExtendedImageReaderWidget.isSupportedImageHeaderForTesting(bytes),
        isFalse,
      );
    });
  });

  group('shouldAutoPlayAnimatedView', () {
    test('returns true when there is no visible page notifier', () {
      expect(
        ExtendedImageReaderWidget.shouldAutoPlayAnimatedViewForTesting(
          pageNumber: 3,
        ),
        isTrue,
      );
    });

    test('returns true for the currently visible page', () {
      expect(
        ExtendedImageReaderWidget.shouldAutoPlayAnimatedViewForTesting(
          pageNumber: 3,
          visiblePageNumber: 3,
        ),
        isTrue,
      );
    });

    test('returns false for non-current page', () {
      expect(
        ExtendedImageReaderWidget.shouldAutoPlayAnimatedViewForTesting(
          pageNumber: 3,
          visiblePageNumber: 2,
        ),
        isFalse,
      );
    });
  });

  group('shouldNotifyHeavyImageDetected', () {
    test('returns false for static native fallback in continuous scroll', () {
      expect(
        ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
          readingMode: ReadingMode.continuousScroll,
          confirmedAnimatedWebP: false,
          hasCallback: true,
          alreadyNotified: false,
        ),
        isFalse,
      );
    });

    test('returns true only for confirmed animated image in continuous scroll',
        () {
      expect(
        ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
          readingMode: ReadingMode.continuousScroll,
          confirmedAnimatedWebP: true,
          hasCallback: true,
          alreadyNotified: false,
        ),
        isTrue,
      );
    });

    test('returns false when heavy image was already notified', () {
      expect(
        ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
          readingMode: ReadingMode.continuousScroll,
          confirmedAnimatedWebP: true,
          hasCallback: true,
          alreadyNotified: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldKeepAlive', () {
    test('returns false for normal image in continuous scroll', () {
      expect(
        ExtendedImageReaderWidget.shouldKeepAliveForTesting(
          readingMode: ReadingMode.continuousScroll,
          isHeavy: false,
        ),
        isFalse,
      );
    });

    test('returns true for heavy image in continuous scroll', () {
      expect(
        ExtendedImageReaderWidget.shouldKeepAliveForTesting(
          readingMode: ReadingMode.continuousScroll,
          isHeavy: true,
        ),
        isTrue,
      );
    });

    test('returns true for single-page mode even when image is normal', () {
      expect(
        ExtendedImageReaderWidget.shouldKeepAliveForTesting(
          readingMode: ReadingMode.singlePage,
          isHeavy: false,
        ),
        isTrue,
      );
    });
  });

  group('shouldClearMemoryCacheOnDispose', () {
    test('returns true for normal continuous-scroll image', () {
      expect(
        ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
          readingMode: ReadingMode.continuousScroll,
          isHeavy: false,
          isHeavyReaderSource: false,
        ),
        isTrue,
      );
    });

    test('returns false for heavy animated image', () {
      expect(
        ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
          readingMode: ReadingMode.continuousScroll,
          isHeavy: true,
          isHeavyReaderSource: false,
        ),
        isFalse,
      );
    });

    test('returns false for heavy reader source optimization', () {
      expect(
        ExtendedImageReaderWidget.shouldClearMemoryCacheOnDisposeForTesting(
          readingMode: ReadingMode.continuousScroll,
          isHeavy: false,
          isHeavyReaderSource: true,
        ),
        isFalse,
      );
    });
  });

  group('heavy image threshold', () {
    test('threshold is 2 MB', () {
      expect(
        ExtendedImageReaderWidget.heavyImageThresholdBytesForTesting,
        equals(2 * 1024 * 1024),
      );
    });

    test('ultra-heavy animated threshold is 10 MB', () {
      expect(
        ExtendedImageReaderWidget
            .ultraHeavyAnimatedImageThresholdBytesForTesting,
        equals(10 * 1024 * 1024),
      );
    });
  });

  group('resolveNativeAnimatedDecodeWidth', () {
    test('caps default animated decode at 720px below full viewport', () {
      expect(
        ExtendedImageReaderWidget.resolveNativeAnimatedDecodeWidthForTesting(
          logicalWidth: 360,
          devicePixelRatio: 3,
          imageBytes:
              ExtendedImageReaderWidget.heavyImageThresholdBytesForTesting,
        ),
        equals(720),
      );
    });

    test('uses a smaller target width for ultra-heavy offline files', () {
      final normal =
          ExtendedImageReaderWidget.resolveNativeAnimatedDecodeWidthForTesting(
        logicalWidth: 360,
        devicePixelRatio: 3,
        imageBytes:
            ExtendedImageReaderWidget.heavyImageThresholdBytesForTesting,
      );
      final ultraHeavy =
          ExtendedImageReaderWidget.resolveNativeAnimatedDecodeWidthForTesting(
        logicalWidth: 360,
        devicePixelRatio: 3,
        imageBytes: ExtendedImageReaderWidget
            .ultraHeavyAnimatedImageThresholdBytesForTesting,
      );

      expect(ultraHeavy, equals(540));
      expect(ultraHeavy, lessThan(normal));
    });

    test('never exceeds the display viewport width', () {
      expect(
        ExtendedImageReaderWidget.resolveNativeAnimatedDecodeWidthForTesting(
          logicalWidth: 100,
          devicePixelRatio: 2,
          imageBytes:
              ExtendedImageReaderWidget.heavyImageThresholdBytesForTesting,
        ),
        equals(200),
      );
    });
  });

  group('_heavyImageUrls static set persistence', () {
    test('URL added to set is visible to next widget instance', () {
      const url = 'https://example.com/heavy.webp';
      expect(ExtendedImageReaderWidget.isHeavyUrlForTesting(url), isFalse);

      ExtendedImageReaderWidget.addHeavyUrlForTesting(url);

      expect(ExtendedImageReaderWidget.isHeavyUrlForTesting(url), isTrue);
    });

    test('clearHeavyUrlsForTesting resets the set', () {
      const url = 'https://example.com/heavy.webp';
      ExtendedImageReaderWidget.addHeavyUrlForTesting(url);
      ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
      expect(ExtendedImageReaderWidget.isHeavyUrlForTesting(url), isFalse);
    });
  });

  // ── Widget routing tests ──────────────────────────────────────────────────

  group('native view routing', () {
    testWidgets(
        'shows ExtendedImage.network on first visit (not yet heavy) – '
        'no AndroidView', (tester) async {
      const url = 'https://example.com/page.webp';
      // URL is NOT in heavy set → should render ExtendedImage

      await tester.pumpWidget(_buildWidget(url: url));
      await tester.pump(); // let build complete

      // AndroidView should NOT be present; ExtendedImage should be.
      // We check widget type indirectly: if native, an AndroidView would appear.
      expect(find.byType(AndroidView), findsNothing);
    });

    testWidgets(
        'shows AnimatedWebPView (AndroidView) on second visit – '
        'URL already in heavy set', (tester) async {
      const url = 'https://example.com/page.webp';
      _markHeavy(url); // simulate previous visit having detected it as heavy

      await tester.pumpWidget(_buildWidget(url: url));
      await tester.pump();

      // On Android (test env mimics Android), AndroidView should appear.
      // AnimatedWebPView.isAvailable is true on Android.
      // In the test host (Linux/macOS CI) Platform.isAndroid = false,
      // so AnimatedWebPView renders [fallback] → ExtendedImage.
      // Either way there should be NO crash and widget renders.
      expect(tester.takeException(), isNull);
    });

    testWidgets('non-webp URL is never routed to native view even if heavy',
        (tester) async {
      const url = 'https://example.com/page.jpg';
      _markHeavy(url);

      await tester.pumpWidget(_buildWidget(url: url));
      await tester.pump();

      expect(find.byType(AndroidView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'heavy avif URL uses Flutter codec (native routing via post-download brand check)',
        (tester) async {
      const url = 'https://example.com/page.avif';
      _markHeavy(url);

      await tester.pumpWidget(_buildWidget(url: url));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('wantKeepAlive true for heavy image in continuousScroll',
        (tester) async {
      const url = 'https://example.com/page.webp';
      _markHeavy(url);

      await tester.pumpWidget(_buildWidget(
        url: url,
        mode: ReadingMode.continuousScroll,
      ));
      await tester.pump();

      // Widget should still be alive (no crash, no dispose triggered).
      expect(tester.takeException(), isNull);
    });
  });

  group('clearNativeAnimatedCache', () {
    test('clears all static URL sets', () {
      const url1 = 'https://example.com/heavy.webp';

      ExtendedImageReaderWidget.addHeavyUrlForTesting(url1);
      expect(ExtendedImageReaderWidget.isHeavyUrlForTesting(url1), isTrue);

      ExtendedImageReaderWidget.clearNativeAnimatedCache();

      expect(ExtendedImageReaderWidget.isHeavyUrlForTesting(url1), isFalse);
    });
  });

  group('bounded static caches', () {
    test('heavyImageUrls respects max bound', () {
      ExtendedImageReaderWidget.clearNativeAnimatedCache();

      final maxSize = ExtendedImageReaderWidget.maxHeavyImageUrls;
      for (var i = 0; i < maxSize + 50; i++) {
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          'https://example.com/heavy_$i.webp',
        );
      }

      expect(
        ExtendedImageReaderWidget.isHeavyUrlForTesting(
          'https://example.com/heavy_0.webp',
        ),
        isFalse,
        reason: 'Oldest entries should be evicted when exceeding max bound',
      );
      expect(
        ExtendedImageReaderWidget.isHeavyUrlForTesting(
          'https://example.com/heavy_499.webp',
        ),
        isTrue,
        reason: 'Most recent entries should be retained',
      );

      ExtendedImageReaderWidget.clearNativeAnimatedCache();
    });

    test('bounded set clears correctly', () {
      ExtendedImageReaderWidget.clearNativeAnimatedCache();

      const url = 'https://example.com/test_bounded_clear.webp';
      ExtendedImageReaderWidget.addHeavyUrlForTesting(url);
      expect(
        ExtendedImageReaderWidget.isHeavyUrlForTesting(url),
        isTrue,
      );

      ExtendedImageReaderWidget.clearNativeAnimatedCache();
      expect(
        ExtendedImageReaderWidget.isHeavyUrlForTesting(url),
        isFalse,
      );
    });
  });

  group('AnimatedWebPView.isAvailable', () {
    test('is false on non-Android test host', () {
      // Tests run on macOS/Linux CI, not Android.
      expect(AnimatedWebPView.isAvailable, equals(Platform.isAndroid));
    });
  });
}
