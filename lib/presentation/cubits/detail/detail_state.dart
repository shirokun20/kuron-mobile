part of 'detail_cubit.dart';

// Base state for DetailCubit
abstract class DetailState extends BaseCubitState {
  const DetailState();
}

// Initial state before loading content
class DetailInitial extends DetailState {
  const DetailInitial();

  @override
  List<Object?> get props => [];
}

// State when loading content detail
class DetailLoading extends DetailState {
  const DetailLoading();

  @override
  List<Object?> get props => [];
}

// State when content detail is loaded successfully
class DetailLoaded extends DetailState {
  const DetailLoaded({
    required this.content,
    required this.isFavorited,
    required this.lastUpdated,
    this.isTogglingFavorite = false,
    this.isChaptersLoading = false,
    this.imageMetadata,
    this.chapterHistory,
    this.relatedContent,
    this.comments,
    this.chaptersError,
    this.chaptersChallengeUrl,
    this.chaptersChallengeUserAgent,
  });

  final Content content;
  final bool isFavorited;
  final bool isTogglingFavorite;
  final bool isChaptersLoading;
  final DateTime lastUpdated;
  final List<ImageMetadata>? imageMetadata;
  final Map<String, History>? chapterHistory;
  final List<Content>? relatedContent;
  final List<Comment>? comments;
  /// Non-null when the last chapter load failed: user-visible message with
  /// a retry action (never a spinner forever).
  final String? chaptersError;
  /// Set when chapter loading hit a WAF/bot challenge: absolute URL the
  /// user must open to verify, then retry.
  final String? chaptersChallengeUrl;
  /// Request User-Agent to reuse for interactive verification: WAF cookies
  /// can be User-Agent bound, so the dialog must match the proxy request.
  final String? chaptersChallengeUserAgent;

  @override
  List<Object?> get props => [
        content,
        isFavorited,
        isTogglingFavorite,
        isChaptersLoading,
        lastUpdated,
        imageMetadata,
        chapterHistory,
        relatedContent,
        comments,
        chaptersError,
        chaptersChallengeUrl,
        chaptersChallengeUserAgent,
      ];

  // Create a copy with updated properties
  DetailLoaded copyWith({
    Content? content,
    bool? isFavorited,
    bool? isTogglingFavorite,
    bool? isChaptersLoading,
    DateTime? lastUpdated,
    List<ImageMetadata>? imageMetadata,
    Map<String, History>? chapterHistory,
    List<Content>? relatedContent,
    List<Comment>? comments,
    String? chaptersError,
    String? chaptersChallengeUrl,
    String? chaptersChallengeUserAgent,
    bool clearChaptersError = false,
    bool clearChaptersChallengeUrl = false,
    bool clearChaptersChallengeUserAgent = false,
  }) {
    return DetailLoaded(
      content: content ?? this.content,
      isFavorited: isFavorited ?? this.isFavorited,
      isTogglingFavorite: isTogglingFavorite ?? this.isTogglingFavorite,
      isChaptersLoading: isChaptersLoading ?? this.isChaptersLoading,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      imageMetadata: imageMetadata ?? this.imageMetadata,
      chapterHistory: chapterHistory ?? this.chapterHistory,
      relatedContent: relatedContent ?? this.relatedContent,
      comments: comments ?? this.comments,
      chaptersError:
          clearChaptersError ? null : (chaptersError ?? this.chaptersError),
      chaptersChallengeUrl: clearChaptersChallengeUrl
          ? null
          : (chaptersChallengeUrl ?? this.chaptersChallengeUrl),
      chaptersChallengeUserAgent: clearChaptersChallengeUserAgent
          ? null
          : (chaptersChallengeUserAgent ?? this.chaptersChallengeUserAgent),
    );
  }

  // Check if content can be read
  bool get canRead => content.imageUrls.isNotEmpty;

  // Check if content has tags
  bool get hasTags => content.tags.isNotEmpty;

  // Get formatted page count
  String get formattedPageCount => '${content.pageCount} pages';

  // Get formatted upload date
  String get formattedUploadDate {
    final now = DateTime.now();
    final difference = now.difference(content.uploadDate);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // Get tags by type
  List<Tag> getTagsByType(String type) {
    return content.tags.where((tag) => tag.type == type).toList();
  }

  // Get artists as tags
  List<Tag> get artistTags => getTagsByType('artist');

  // Get character tags
  List<Tag> get characterTags => getTagsByType('character');

  // Get parody tags
  List<Tag> get parodyTags => getTagsByType('parody');

  // Get group tags
  List<Tag> get groupTags => getTagsByType('group');

  // Get language tags
  List<Tag> get languageTags => getTagsByType('language');

  // Get category tags
  List<Tag> get categoryTags => getTagsByType('category');

  // Get regular tags (excluding special types)
  List<Tag> get regularTags {
    const specialTypes = {
      'artist',
      'character',
      'parody',
      'group',
      'language',
      'category'
    };
    return content.tags
        .where((tag) => !specialTypes.contains(tag.type))
        .toList();
  }
}

// State when there's an error loading content detail
class DetailError extends DetailState {
  const DetailError({
    required this.message,
    required this.errorType,
    required this.canRetry,
    this.contentId,
    this.error,
  });

  final String message;
  final String errorType;
  final bool canRetry;
  final String? contentId;
  final dynamic error;

  @override
  List<Object?> get props => [message, errorType, canRetry, contentId, error];

  // Get user-friendly error message
  String get userFriendlyMessage {
    switch (errorType) {
      case 'network':
        return 'No internet connection. Please check your network and try again.';
      case 'server':
        return 'Server is temporarily unavailable. Please try again later.';
      case 'cloudflare':
        return 'Content is temporarily blocked. Please try again in a moment.';
      case 'parsing':
        return 'Failed to load content data. The content may be unavailable.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // Get error icon based on type
  String get errorIcon {
    switch (errorType) {
      case 'network':
        return 'wifi_off';
      case 'server':
        return 'server_error';
      case 'cloudflare':
        return 'shield';
      case 'parsing':
        return 'data_error';
      default:
        return 'error';
    }
  }
}

// State when opening a chapter (loading images)
class DetailOpeningChapter extends DetailLoaded {
  const DetailOpeningChapter({
    required super.content,
    required super.isFavorited,
    required super.lastUpdated,
    super.imageMetadata,
    super.chapterHistory,
    super.relatedContent,
    super.comments,
  });
}

// State when chapter is ready to read
class DetailReaderReady extends DetailLoaded {
  const DetailReaderReady({
    required this.chapterContent,
    required super.content,
    required super.isFavorited,
    required super.lastUpdated,
    super.imageMetadata,
    super.chapterHistory,
    super.relatedContent,
    super.comments,
    this.chapterData,
    this.currentChapter,
    this.initialPage = 1,
  });

  final Content chapterContent;
  final ChapterData? chapterData;
  final Chapter? currentChapter;
  final int initialPage;

  @override
  List<Object?> get props => [
        ...super.props,
        chapterContent,
        chapterData,
        currentChapter,
        initialPage,
      ];
}

// State when login is required for an action
class DetailNeedsLogin extends DetailState {
  const DetailNeedsLogin();

  @override
  List<Object?> get props => [];
}

// State when an action fails but content is still loaded
class DetailActionFailure extends DetailLoaded {
  const DetailActionFailure({
    required this.message,
    required super.content,
    required super.isFavorited,
    required super.lastUpdated,
    super.imageMetadata,
    super.chapterHistory,
    super.relatedContent,
    super.comments,
    this.needsLogin = false,
    this.error,
  });

  final String message;
  final bool needsLogin;
  final dynamic error;

  @override
  List<Object?> get props => [...super.props, message, needsLogin, error];
}
