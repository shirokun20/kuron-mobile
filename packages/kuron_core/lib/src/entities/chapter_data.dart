import 'package:equatable/equatable.dart';

// Data class to hold chapter images and navigation info
class ChapterData extends Equatable {
  const ChapterData({
    required this.images,
    this.videoUrls = const [],
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
  final String? prevChapterId;
  final String? nextChapterId;
  final String? prevChapterTitle;
  final String? nextChapterTitle;

  @override
  List<Object?> get props => [
        images,
        videoUrls,
        prevChapterId,
        nextChapterId,
        prevChapterTitle,
        nextChapterTitle,
      ];
}
