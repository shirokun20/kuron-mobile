import '../base_usecase.dart';
import '../../entities/entities.dart';
import '../../value_objects/value_objects.dart';
import '../../repositories/repositories.dart';

// Use case for adding content to reading history
class AddToHistoryUseCase extends UseCase<void, AddToHistoryParams> {
  AddToHistoryUseCase(this._userDataRepository);

  final UserDataRepository _userDataRepository;

  @override
  Future<void> call(AddToHistoryParams params) async {
    try {
      // Validate parameters
      if (!params.contentId.isValid) {
        throw ValidationException(
            'Invalid content ID: ${params.contentId.value}');
      }

      if (params.page < 1) {
        throw const ValidationException('Page number must be greater than 0');
      }

      if (params.totalPages < 1) {
        throw const ValidationException('Total pages must be greater than 0');
      }

      if (params.page > params.totalPages) {
        throw const ValidationException(
            'Current page cannot exceed total pages');
      }

      if (params.timeSpent != null && params.timeSpent!.isNegative) {
        throw const ValidationException('Time spent cannot be negative');
      }

      // Create history entry and save it
      final history = History(
        contentId: params.contentId.value,
        lastViewed: DateTime.now(),
        lastPage: params.page,
        totalPages: params.totalPages,
        timeSpent: params.timeSpent ?? Duration.zero,
        isCompleted: params.page >= params.totalPages,
        coverUrl: params.coverUrl,
        title: params.title,
        sourceId: params.sourceId,
        parentId: params.parentId,
        chapterId: params.chapterId,
        chapterIndex: params.chapterIndex,
        chapterTitle: params.chapterTitle,
      );

      await _userDataRepository.saveHistory(history);

      // Best-effort tag seeding for the recommendation engine. History is
      // the primary write — tag loss is recoverable on the next save, so a
      // tag failure must never fail the history write (already logged inside
      // the repository).
      final content = params.content;
      if (content != null) {
        try {
          await _userDataRepository.saveContentTags(
            ContentTag.seedsFromContent(
              content: content,
              contentId: params.contentId.value,
              sourceId: params.sourceId,
              origin: 'history',
            ),
          );
        } catch (_) {
          // Intentionally ignored — see comment above.
        }
      }
    } on UseCaseException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to add to history: ${e.toString()}');
    }
  }
}

// Parameters for AddToHistoryUseCase
class AddToHistoryParams extends UseCaseParams {
  const AddToHistoryParams({
    required this.contentId,
    required this.page,
    required this.totalPages,
    this.timeSpent,
    this.coverUrl,
    this.title,
    this.sourceId = 'nhentai',
    this.parentId,
    this.chapterId,
    this.chapterIndex,
    this.chapterTitle,
    this.content,
  });

  final ContentId contentId;
  final int page;
  final int totalPages;
  final Duration? timeSpent;
  final String? coverUrl;
  final String? title;
  final String sourceId;
  final String? parentId; // Parent/series ID for chapter mode
  final String? chapterId;
  final int? chapterIndex;
  final String? chapterTitle;

  /// Full content for recommendation tag seeding (optional, best-effort).
  final Content? content;

  @override
  List<Object?> get props => [
        contentId,
        page,
        totalPages,
        timeSpent,
        sourceId,
        parentId,
        chapterId,
        chapterIndex,
        chapterTitle,
      ];

  AddToHistoryParams copyWith({
    ContentId? contentId,
    int? page,
    int? totalPages,
    Duration? timeSpent,
    String? coverUrl,
    String? title,
    String? sourceId,
    String? parentId,
    String? chapterId,
    int? chapterIndex,
    String? chapterTitle,
    Content? content,
  }) {
    return AddToHistoryParams(
      contentId: contentId ?? this.contentId,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      timeSpent: timeSpent ?? this.timeSpent,
      title: title,
      coverUrl: coverUrl,
      sourceId: sourceId ?? this.sourceId,
      parentId: parentId ?? this.parentId,
      chapterId: chapterId ?? this.chapterId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      content: content ?? this.content,
    );
  }

  // Create params from string ID
  factory AddToHistoryParams.fromString(
    String contentId,
    int page,
    int totalPages, {
    Duration? timeSpent,
    String? coverUrl,
    String? title,
    String sourceId = 'nhentai',
    String? parentId,
    String? chapterId,
    int? chapterIndex,
    String? chapterTitle,
    Content? content,
  }) {
    return AddToHistoryParams(
      contentId: ContentId.fromString(contentId),
      page: page,
      totalPages: totalPages,
      timeSpent: timeSpent,
      title: title,
      coverUrl: coverUrl,
      sourceId: sourceId,
      parentId: parentId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      content: content,
    );
  }

  // Create params from int ID
  factory AddToHistoryParams.fromInt(
    int contentId,
    int page,
    int totalPages, {
    Duration? timeSpent,
    String? coverUrl,
    String? title,
    String sourceId = 'nhentai',
    String? parentId,
    String? chapterId,
    int? chapterIndex,
    String? chapterTitle,
  }) {
    return AddToHistoryParams(
      contentId: ContentId.fromInt(contentId),
      page: page,
      totalPages: totalPages,
      timeSpent: timeSpent,
      title: title,
      coverUrl: coverUrl,
      sourceId: sourceId,
      parentId: parentId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
    );
  }

  // Create params for starting to read (page 1)
  factory AddToHistoryParams.startReading(
    ContentId contentId,
    int totalPages,
  ) {
    return AddToHistoryParams(
      contentId: contentId,
      page: 1,
      totalPages: totalPages,
    );
  }

  // Create params for completing reading (last page)
  factory AddToHistoryParams.completeReading(
    ContentId contentId,
    int totalPages, {
    Duration? timeSpent,
    String? coverUrl,
    String? title,
    String sourceId = 'nhentai',
  }) {
    return AddToHistoryParams(
      contentId: contentId,
      page: totalPages,
      totalPages: totalPages,
      timeSpent: timeSpent,
      title: title,
      coverUrl: coverUrl,
      sourceId: sourceId,
    );
  }

  // Create params with reading time
  AddToHistoryParams withTimeSpent(Duration timeSpent) {
    return copyWith(timeSpent: timeSpent);
  }

  // Create params for next page
  AddToHistoryParams nextPage({Duration? additionalTime}) {
    return copyWith(
      page: page < totalPages ? page + 1 : totalPages,
      timeSpent: additionalTime,
    );
  }

  // Create params for previous page
  AddToHistoryParams previousPage({Duration? additionalTime}) {
    return copyWith(
      page: page > 1 ? page - 1 : 1,
      timeSpent: additionalTime,
    );
  }

  // Check if this is the first page
  bool get isFirstPage => page == 1;

  // Check if this is the last page
  bool get isLastPage => page == totalPages;

  // Get reading progress percentage
  double get progressPercentage => page / totalPages;
}
