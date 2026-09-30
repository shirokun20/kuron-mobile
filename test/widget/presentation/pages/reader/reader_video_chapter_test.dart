// Issue #68 — reader branch selection for a video/HLS chapter.
//
// Playback opens in the platform WebView (`KuronNative.openWebView` → Custom
// Tabs), so there is no platform view to stand up here and the widget test
// binding needs no WebView implementation. What is worth locking down is the
// *decision* — the reader swaps the image pager for [ReaderVideoChapter] only
// when the chapter has no pages at all, keeps paging images otherwise, and
// shows a poster card until the reader taps play.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_video_chapter.dart';

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('isVideoChapter()', () {
    test('is false for a normal image chapter', () {
      expect(
        isVideoChapter(const ChapterData(
          images: ['https://cdn.example.com/p/001.jpg'],
        )),
        isFalse,
      );
    });

    test('is false when there is no chapter data at all', () {
      expect(isVideoChapter(null), isFalse);
    });

    test('is true when the chapter carries an HLS stream', () {
      expect(
        isVideoChapter(const ChapterData(
          images: [],
          videoUrls: ['https://cdn.example.com/hls/master.m3u8'],
        )),
        isTrue,
      );
    });

    // videoUrls is harvested by a page-wide regex, so an ad embed or a "watch
    // the adaptation" teaser tags a chapter that has plenty of real pages.
    // Swapping the pager on that signal dropped every page of a 60-page
    // chapter — the reader showed a play card instead.
    test('is false for a chapter with both images and a stray stream', () {
      expect(
        isVideoChapter(const ChapterData(
          images: [
            'https://cdn.example.com/p/001.jpg',
            'https://cdn.example.com/p/002.jpg',
          ],
          videoUrls: ['https://ads.example.com/promo.mp4'],
        )),
        isFalse,
        reason: 'real pages must win over a page-wide video match',
      );
    });

    test('is false for a long chapter with one stream among many pages', () {
      expect(
        isVideoChapter(ChapterData(
          images: [
            for (var i = 1; i <= 60; i++) 'https://cdn.example.com/$i.jpg'
          ],
          videoUrls: const ['https://cdn.example.com/hls/master.m3u8'],
        )),
        isFalse,
      );
    });
  });

  group('poster card precedes playback', () {
    testWidgets('renders a play affordance, not a player, before a tap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _app(
          VideoPosterCard(
            streamCount: 2,
            onPlay: () async => tapped = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('Play video'), findsOneWidget);
      expect(find.text('2 streams available'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(tapped, isTrue);
    });

    testWidgets('hides the stream count for a single-stream chapter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const VideoPosterCard(streamCount: 1, onPlay: _noop)),
      );
      expect(find.text('Play video'), findsOneWidget);
      expect(find.textContaining('streams available'), findsNothing);
    });

    testWidgets('shows the chapter title when one is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const VideoPosterCard(
            streamCount: 1,
            onPlay: _noop,
            title: 'Episode 12 — The Arrival',
          ),
        ),
      );
      expect(find.text('Episode 12 — The Arrival'), findsOneWidget);
    });

    testWidgets('omits the title row for a blank title', (tester) async {
      await tester.pumpWidget(
        _app(
          const VideoPosterCard(streamCount: 1, onPlay: _noop, title: '   '),
        ),
      );
      expect(find.text('Play video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers Save only when a file can actually be saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const VideoPosterCard(streamCount: 1, onPlay: _noop)),
      );
      expect(
        find.byIcon(Icons.download_rounded),
        findsNothing,
        reason: 'nothing to offer without a downloadable file',
      );

      var saved = false;
      await tester.pumpWidget(
        _app(
          VideoPosterCard(
            streamCount: 1,
            onPlay: _noop,
            onSave: () async => saved = true,
          ),
        ),
      );
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.text('Save video'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(saved, isTrue);
    });
  });

  group('play strip for a chapter that has pages AND a stream', () {
    // The pager stays the reader; the stream is one compact tap above it.
    testWidgets('renders a play affordance with a single stream', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ReaderVideoStrip(
            chapterData: ChapterData(
              images: ['https://cdn.example.com/p/001.jpg'],
              videoUrls: ['https://cdn.example.com/hls/master.m3u8'],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('Play video'), findsOneWidget);
      expect(
        find.textContaining('streams available'),
        findsNothing,
        reason: 'one stream needs no count',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the stream count when there is more than one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ReaderVideoStrip(
            chapterData: ChapterData(
              images: ['https://cdn.example.com/p/001.jpg'],
              videoUrls: [
                'https://cdn.example.com/hls/master.m3u8',
                'https://cdn.example.com/hls/alt.m3u8',
              ],
            ),
          ),
        ),
      );

      expect(find.text('2 streams available'), findsOneWidget);
    });
  });
  group('isDirectFileStream()', () {
    // Only a file can be handed to the downloader as-is. An HLS playlist is a
    // list of segments, and an embed page computes its stream in JavaScript —
    // offering Save for those would be a button that cannot deliver.
    test('accepts a direct video file', () {
      expect(isDirectFileStream('https://cdn.example.com/clip.mp4'), isTrue);
      expect(isDirectFileStream('https://cdn.example.com/clip.WEBM'), isTrue);
    });

    test('survives a query string on the file', () {
      expect(
        isDirectFileStream('https://cdn.example.com/clip.mp4?token=abc'),
        isTrue,
      );
    });

    test('rejects an HLS playlist', () {
      expect(
        isDirectFileStream('https://cdn.example.com/hls/master.m3u8'),
        isFalse,
      );
    });

    test('rejects an embed page', () {
      expect(
        isDirectFileStream('https://cossora.stream/embed/c74c438d'),
        isFalse,
      );
    });
  });

  group('videoFileName()', () {
    test('names the file after the chapter, not after the host', () {
      expect(
        videoFileName(
          title: 'Episode 12 - The Arrival',
          url: 'https://cdn.example.com/v/8891.mp4',
        ),
        'Episode 12 - The Arrival.mp4',
      );
    });

    test('strips characters a filesystem rejects', () {
      expect(
        videoFileName(
          title: 'A/B: "C" <D> | E',
          url: 'https://cdn.example.com/v/8891.mp4',
        ),
        'AB C D  E.mp4',
      );
    });

    test('falls back when the chapter has no usable title', () {
      expect(
        videoFileName(title: '  ', url: 'https://cdn.example.com/v/8891.mp4'),
        'video.mp4',
      );
    });

    test('keeps a long CJK title inside the filesystem limit', () {
      final name = videoFileName(
        title: '\u4e00' * 200,
        url: 'https://cdn.example.com/v/8891.mp4',
      );
      expect(name.length, lessThanOrEqualTo(64));
    });
  });
}

Future<void> _noop() async {}
