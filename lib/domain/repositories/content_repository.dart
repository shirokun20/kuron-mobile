import '../entities/entities.dart';
import '../value_objects/value_objects.dart';

abstract class ContentRepository {
  Future<ContentListResult> getContentList({
    int page = 1,
    SortOption sortBy = SortOption.newest,
  });

  Future<Content> getContentDetail(ContentId contentId, {String? sourceId});

  Future<ContentListResult> searchContent(SearchFilter filter);

  Future<ContentListResult> getPopularContent({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
  });

  Future<ContentListResult> getContentByTag({
    required Tag tag,
    int page = 1,
    SortOption sortBy = SortOption.newest,
  });

  Future<List<Content>> getRelatedContent({
    required ContentId contentId,
    int limit = 10,
    String? sourceId,
  });

  Future<List<Content>> getRandomGalleries({
    String? sourceId,
    int count = 1,
  });

  Future<List<Tag>> getAllTags({
    String? type,
    TagSortOption sortBy = TagSortOption.count,
  });

  Future<bool> verifyContentExists(ContentId contentId);

  Future<ChapterData> getChapterImages(ContentId chapterId, {String? sourceId});

  Future<List<Chapter>> getContentChapters(
    ContentId contentId, {
    String? sourceId,
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  });

  Future<List<Comment>> getComments(String contentId);
}

class ContentListResult {
  const ContentListResult({
    required this.contents,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    this.hasNext = false,
    this.hasPrevious = false,
  });

  final List<Content> contents;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasNext;
  final bool hasPrevious;

  bool get isEmpty => contents.isEmpty;

  bool get isNotEmpty => contents.isNotEmpty;

  int get count => contents.length;

  factory ContentListResult.empty() {
    return const ContentListResult(
      contents: [],
      currentPage: 1,
      totalPages: 0,
      totalCount: 0,
    );
  }

  factory ContentListResult.single(List<Content> contents) {
    return ContentListResult(
      contents: contents,
      currentPage: 1,
      totalPages: 1,
      totalCount: contents.length,
    );
  }
}

enum PopularTimeframe {
  allTime,
  week,
  today,
}

enum TagSortOption {
  count,
  name,
  recent,
}

class ContentStatistics {
  const ContentStatistics({
    required this.totalContent,
    required this.totalTags,
    required this.totalArtists,
    required this.averagePages,
    required this.mostPopularTags,
    required this.mostPopularArtists,
    required this.languageDistribution,
    required this.categoryDistribution,
    this.lastUpdated,
  });

  final int totalContent;
  final int totalTags;
  final int totalArtists;
  final double averagePages;
  final List<Tag> mostPopularTags;
  final List<String> mostPopularArtists;
  final Map<String, int> languageDistribution;
  final Map<String, int> categoryDistribution;
  final DateTime? lastUpdated;

  int get totalPages => (totalContent * averagePages).round();

  String? get mostPopularLanguage {
    if (languageDistribution.isEmpty) return null;
    return languageDistribution.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String? get mostPopularCategory {
    if (categoryDistribution.isEmpty) return null;
    return categoryDistribution.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
}

extension PopularTimeframeExtension on PopularTimeframe {
  String get displayName {
    switch (this) {
      case PopularTimeframe.allTime:
        return 'All Time';
      case PopularTimeframe.week:
        return 'This Week';
      case PopularTimeframe.today:
        return 'Today';
    }
  }

  String get apiValue {
    switch (this) {
      case PopularTimeframe.allTime:
        return 'all';
      case PopularTimeframe.week:
        return 'week';
      case PopularTimeframe.today:
        return 'today';
    }
  }
}

extension TagSortOptionExtension on TagSortOption {
  String get displayName {
    switch (this) {
      case TagSortOption.count:
        return 'By Popularity';
      case TagSortOption.name:
        return 'By Name';
      case TagSortOption.recent:
        return 'Recently Used';
    }
  }
}
