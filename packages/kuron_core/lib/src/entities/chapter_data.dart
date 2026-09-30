import 'package:equatable/equatable.dart';

// Data class to hold chapter images and navigation info
class ChapterData extends Equatable {
  const ChapterData({
    required this.images,
    this.videoUrls = const [],
    this.videoIndex,
    this.prevChapterId,
    this.nextChapterId,
    this.prevChapterTitle,
    this.nextChapterTitle,
  });

  final List<String> images;

  /// Direct video/HLS streams (`.m3u8`, `.mp4`, `.webm`, `.mov`) referenced by
  /// the chapter page. Non-empty ⇒ this is a video chapter: the reader plays the
  /// stream instead of paging images (issue #68).
  final List<String> videoUrls;

  /// Where the stream sits in the chapter's own order: how many pages come
  /// before it, counted with the chapter's own image selector.
  ///
  /// A gallery can carry a video between its photos (cosplaytele: "110 photos
  /// and 1 video", the embed above every photo) and a video-only chapter has
  /// no position at all — the reader shows the play surface instead of a
  /// pager. Null means "unknown": the reader then falls back to the end of the
  /// chapter, which is where the old behaviour put it.
  final int? videoIndex;
  final String? prevChapterId;
  final String? nextChapterId;
  final String? prevChapterTitle;
  final String? nextChapterTitle;

  @override
  List<Object?> get props => [
        images,
        videoUrls,
        videoIndex,
        prevChapterId,
        nextChapterId,
        prevChapterTitle,
        nextChapterTitle,
      ];
}
