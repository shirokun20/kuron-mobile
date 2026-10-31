import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';

void main() {
  group('AnimatedWebPView.shouldAutoPlayForTesting', () {
    test('falls back to autoPlay when there is no visible-page context', () {
      expect(AnimatedWebPView.shouldAutoPlayForTesting(autoPlay: true), isTrue);

      expect(
        AnimatedWebPView.shouldAutoPlayForTesting(autoPlay: false),
        isFalse,
      );
    });

    test(
      'plays only for the currently visible page when notifier is present',
      () {
        expect(
          AnimatedWebPView.shouldAutoPlayForTesting(
            autoPlay: false,
            pageNumber: 4,
            visiblePageNumber: 4,
          ),
          isTrue,
        );

        expect(
          AnimatedWebPView.shouldAutoPlayForTesting(
            autoPlay: false,
            pageNumber: 4,
            visiblePageNumber: 3,
          ),
          isFalse,
        );
      },
    );

    test('does not stay playing after the page scrolls off-screen', () {
      expect(
        AnimatedWebPView.shouldAutoPlayForTesting(
          autoPlay: true,
          pageNumber: 2,
          visiblePageNumber: 1,
        ),
        isFalse,
      );
    });
  });

  group('AnimatedWebPView.shouldRenderPlayingForTesting', () {
    test('renders playing view when playing and not user-paused', () {
      expect(
        AnimatedWebPView.shouldRenderPlayingForTesting(
          isPlaying: true,
          userPaused: false,
        ),
        isTrue,
      );
    });

    test('renders static thumbnail when user-paused even if playing', () {
      expect(
        AnimatedWebPView.shouldRenderPlayingForTesting(
          isPlaying: true,
          userPaused: true,
        ),
        isFalse,
      );
    });

    test('renders static thumbnail when not playing', () {
      expect(
        AnimatedWebPView.shouldRenderPlayingForTesting(
          isPlaying: false,
          userPaused: false,
        ),
        isFalse,
      );
    });
  });

  group('AnimatedWebPView.shouldShowPauseBadgeForTesting', () {
    test('shows badge for animated renders', () {
      expect(
        AnimatedWebPView.shouldShowPauseBadgeForTesting(staticOnly: false),
        isTrue,
      );
    });

    test('hides badge for static-only renders', () {
      expect(
        AnimatedWebPView.shouldShowPauseBadgeForTesting(staticOnly: true),
        isFalse,
      );
    });
  });

  group('AnimatedWebPView.shouldSkipThumbnailForTesting', () {
    test('returns false when autoplay is disabled', () {
      expect(
        AnimatedWebPView.shouldSkipThumbnailForTesting(
          shouldAutoPlay: false,
          fileBytes:
              AnimatedWebPView.largeLocalFileSkipThumbnailThresholdBytes + 1,
        ),
        isFalse,
      );
    });

    test('returns false for files below the large-local threshold', () {
      expect(
        AnimatedWebPView.shouldSkipThumbnailForTesting(
          shouldAutoPlay: true,
          fileBytes:
              AnimatedWebPView.largeLocalFileSkipThumbnailThresholdBytes - 1,
        ),
        isFalse,
      );
    });

    test('returns true for autoplaying local files above 10 MB', () {
      expect(
        AnimatedWebPView.shouldSkipThumbnailForTesting(
          shouldAutoPlay: true,
          fileBytes:
              AnimatedWebPView.largeLocalFileSkipThumbnailThresholdBytes + 1,
        ),
        isTrue,
      );
    });

    test('returns true when filePath is provided, even for small files', () {
      expect(
        AnimatedWebPView.shouldSkipThumbnailForTesting(
          shouldAutoPlay: true,
          fileBytes: 1024 * 1024,
          filePath: '/tmp/small.webp',
        ),
        isTrue,
      );
    });

    test('returns false when filePath is provided but autoplay is disabled',
        () {
      expect(
        AnimatedWebPView.shouldSkipThumbnailForTesting(
          shouldAutoPlay: false,
          fileBytes: 1024 * 1024,
          filePath: '/tmp/small.webp',
        ),
        isFalse,
      );
    });
  });
}
