///
// An adapter handles the protocol-specific part of fetching and parsing
// content for a given source. The two built-in adapters are:
// - [GenericRestAdapter] — for JSON REST APIs
// - [GenericScraperAdapter] — for HTML scraping via CSS selectors
library;

import 'package:kuron_core/kuron_core.dart';

// Result of fetching and parsing a search/list page.
class AdapterSearchResult {
  final List<Content> items;
  final bool hasNextPage;
  final String? nextPageUrl;
  final int? totalPages;
  final int? totalItems;

  const AdapterSearchResult({
    required this.items,
    required this.hasNextPage,
    this.nextPageUrl,
    this.totalPages,
    this.totalItems,
  });
}

// Result of fetching and parsing a content detail page.
class AdapterDetailResult {
  final Content content;
  final List<String> imageUrls;

  const AdapterDetailResult({
    required this.content,
    required this.imageUrls,
  });
}

// Abstract interface all adapters must implement.
abstract class GenericAdapter {
  /// Wall-clock budget for a detail fetch. Sources that boot a headless
  /// WebView on first run (e.g. comix-family proxy sources: SPA boot +
  /// chunks + signed requests) override this beyond the 30s default so
  /// upstream deduplication does not kill a healthy slow capture.
  Duration get detailTimeout => const Duration(seconds: 30);

  // Fetch and parse a search/list page for [filter].
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  );

  // Fetch and parse a content detail (and its image list).
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  );

  // Fetch related content for [contentId].
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  );

  // Fetch comments for [contentId].
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  );

  // Fetch chapter image URLs and navigation data for [chapterId].
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  );

  // Fetch chapters for a specific content lane.
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async =>
      const [];
}
