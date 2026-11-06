part of 'reader_cubit.dart';

// Reader status enum — replaces subclass pattern (ReaderLoading/Loaded/Error)
enum ReaderStatus { initial, loading, loaded, error }

// State for reader screen
class ReaderState extends BaseCubitState {
  const ReaderState({
    this.status = ReaderStatus.initial,
    this.content,
    this.currentPage,
    this.readingMode,
    this.showUI,
    this.keepScreenOn,
    this.enableZoom,
    this.readingTimer = Duration.zero,
    this.message,
    this.isOfflineMode = false,
    this.imageMetadata,
    this.chapterData,
    this.currentChapter,
    this.tapDirection = TapDirection.normal,
  });

  final ReaderStatus status;
  final Content? content;
  final int? currentPage;
  final ReadingMode? readingMode;
  final bool? showUI;
  final bool? keepScreenOn;
  final bool? enableZoom;
  final Duration? readingTimer;
  final String? message;
  final bool? isOfflineMode;
  final List<ImageMetadata>? imageMetadata;
  final ChapterData? chapterData;
  final Chapter? currentChapter;
  final TapDirection? tapDirection;

  bool get isLoaded => status == ReaderStatus.loaded && content != null;

  // Get reading progress as percentage (0.0 to 1.0)
  double get progress {
    if (content?.pageCount == null || content!.pageCount == 0) return 0.0;
    return (currentPage ?? 1) / content!.pageCount;
  }

  // Get reading progress as percentage (0 to 100)
  int get progressPercentage => (progress * 100).round();

  // Check if this is the first page
  bool get isFirstPage => (currentPage ?? 1) <= 1;

  // Check if this is the last page
  bool get isLastPage => (currentPage ?? 1) >= (content?.pageCount ?? 1);

  // Get current image URL
  String get currentImageUrl {
    if (content == null ||
        currentPage == null ||
        currentPage! <= 0 ||
        currentPage! > content!.imageUrls.length) {
      return content?.coverUrl ?? '';
    }
    return content!.imageUrls[currentPage! - 1];
  }

  // === Focused copy methods (no sentinel, no generic copyWith) ===

  ReaderState copyWithPage(int page) => ReaderState(
        status: status,
        content: content,
        currentPage: page,
        readingMode: readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection,
      );

  ReaderState copyWithUI({
    bool? showUI,
    bool? keepScreenOn,
    bool? enableZoom,
  }) =>
      ReaderState(
        status: status,
        content: content,
        currentPage: currentPage,
        readingMode: readingMode,
        showUI: showUI ?? this.showUI,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        enableZoom: enableZoom ?? this.enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection,
      );

  ReaderState copyWithContent({
    Content? content,
    List<ImageMetadata>? imageMetadata,
    ChapterData? chapterData,
    Chapter? currentChapter,
  }) =>
      ReaderState(
        status: status,
        content: content ?? this.content,
        currentPage: currentPage,
        readingMode: readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata ?? this.imageMetadata,
        chapterData: chapterData ?? this.chapterData,
        currentChapter: currentChapter ?? this.currentChapter,
        tapDirection: tapDirection,
      );

  ReaderState copyWithMessage(String? message) => ReaderState(
        status: status,
        content: content,
        currentPage: currentPage,
        readingMode: readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection,
      );

  ReaderState copyWithMode({
    ReadingMode? readingMode,
    TapDirection? tapDirection,
  }) =>
      ReaderState(
        status: status,
        content: content,
        currentPage: currentPage,
        readingMode: readingMode ?? this.readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection ?? this.tapDirection,
      );

  ReaderState copyWithTimer(Duration readingTimer) => ReaderState(
        status: status,
        content: content,
        currentPage: currentPage,
        readingMode: readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection,
      );

  ReaderState copyWithOffline(bool isOfflineMode) => ReaderState(
        status: status,
        content: content,
        currentPage: currentPage,
        readingMode: readingMode,
        showUI: showUI,
        keepScreenOn: keepScreenOn,
        enableZoom: enableZoom,
        readingTimer: readingTimer,
        message: message,
        isOfflineMode: isOfflineMode,
        imageMetadata: imageMetadata,
        chapterData: chapterData,
        currentChapter: currentChapter,
        tapDirection: tapDirection,
      );

  @override
  List<Object?> get props => [
        status,
        content?.id,
        currentPage,
        readingMode,
        showUI,
        keepScreenOn,
        enableZoom,
        isOfflineMode,
        currentChapter,
        tapDirection,
      ];
}
