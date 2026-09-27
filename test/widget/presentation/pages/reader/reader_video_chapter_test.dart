// Issue #68 — reader branch selection for a video/HLS chapter.
//
// Playback opens in the platform WebView (`KuronNative.openWebView` → Custom
// Tabs), so there is no platform view to stand up here and the widget test
// binding needs no WebView implementation. What is worth locking down is the
// *decision* — the reader swaps the image pager for [ReaderVideoChapter] only
// when the chapter carries a stream URL, keeps paging images otherwise, and
// shows a poster card until the reader taps play.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_video_chapter.dart';

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
  });

  group('poster card precedes playback', () {
    testWidgets('renders a play affordance, not a player, before a tap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPosterCard(
              streamCount: 2,
              onPlay: () async => tapped = true,
            ),
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
        const MaterialApp(
          home: Scaffold(body: VideoPosterCard(streamCount: 1, onPlay: _noop)),
        ),
      );
      expect(find.text('Play video'), findsOneWidget);
      expect(find.textContaining('streams available'), findsNothing);
    });
  });
}

Future<void> _noop() async {}
