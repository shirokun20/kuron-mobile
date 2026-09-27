// Issue #68 — reader branch selection for a video/HLS chapter.
//
// A full WebView widget test is impractical in this harness: `WebViewWidget`
// needs a platform view + `webview_flutter_android` channel, and the
// `flutter_test` binding has no WebView platform implementation. What is worth
// locking down is the *decision* — the reader swaps the image pager for
// [ReaderVideoChapter] only when the chapter carries a stream URL, and keeps
// paging images otherwise.
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
}
