import '../entities/content.dart';
import '../entities/content_list_result.dart';
import '../entities/chapter.dart';
import '../entities/comment.dart';
import '../entities/search_filter.dart';
import '../entities/chapter_data.dart';
import '../entities/autocomplete_suggestion.dart';
import '../filters/source_filter.dart';
import '../value_objects/sort_option.dart';
import '../value_objects/popular_timeframe.dart';
import 'cancel_hook.dart';
import 'search_capabilities.dart';

export 'cancel_hook.dart';

// Abstract interface for content sources.
///
// Each content source (nhentai, crotpedia, etc.) must implement this interface
// to provide content fetching capabilities.
abstract class ContentSource {
  // Unique identifier for this source (e.g., 'nhentai', 'crotpedia')
  String get id;

  // Display name shown in UI (e.g., 'nhentai', 'Crotpedia')
  String get displayName;

  // Asset path to source icon
  String get iconPath;

  // Base URL for this source
  String get baseUrl;

  // Whether this source requires cloudflare bypass
  bool get requiresBypass;

  // Search capabilities supported by this source
  SearchCapabilities get searchCapabilities;

  // Search content with the given filter.
  //
  // [onCancel] lets callers abort an in-flight fetch (e.g. a superseded
  // home-grid load). Pure-Dart bridge: adapters convert it to their own
  // cancellation primitive (Dio `CancelToken`).
  Future<ContentListResult> search(
    SearchFilter filter, {
    OnCancelRegister? onCancel,
  });

  // Get content detail by ID
  Future<Content> getDetail(
    String contentId, {
    OnCancelRegister? onCancel,
  });

  // Get paginated list of content
  Future<ContentListResult> getList({
    int page = 1,
    SortOption sort = SortOption.newest,
    OnCancelRegister? onCancel,
  });

  // Get popular content
  Future<ContentListResult> getPopular({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
    OnCancelRegister? onCancel,
  });

  // Get random content
  Future<List<Content>> getRandom({int count = 1});

  // Get related content for a specific content ID
  Future<List<Content>> getRelated(
    String contentId, {
    OnCancelRegister? onCancel,
  });

  // Get comments for a specific content ID
  Future<List<Comment>> getComments(String contentId) async => [];

  // Get chapter image URLs and navigation data for a specific chapter ID.
  // Used primarily by manga/manhwa sources. Default implementation returns null.
  Future<ChapterData?> getChapterImages(
    String chapterId, {
    OnCancelRegister? onCancel,
  }) async => null;

  // Get chapters for a specific content lane.
  ///
  // Default implementation returns an empty list so sources can opt in only
  // when they support lazy lane fetching.
  Future<List<Chapter>> getChapters(
    String contentId, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async => const [];

  // Build full image URL for this source
  String buildImageUrl({
    required String contentId,
    required String mediaId,
    required int page,
    required String extension,
    bool thumbnail = false,
  });

  // Build thumbnail URL for this source
  String buildThumbnailUrl({
    required String contentId,
    required String mediaId,
  });

  // Parse content ID from a URL string
  String? parseContentIdFromUrl(String url);

  // Validate content ID format for this source
  bool isValidContentId(String contentId);

  // Get referer header value for requests
  String get refererHeader;

  // ============ NEW: Download & Display Customization ============

  // Get HTTP headers required for downloading images from this source.
  ///
  // This method returns all necessary headers (Referer, User-Agent, cookies, etc.)
  // needed to successfully download images. Each source may have different
  // requirements.
  ///
  // Example:
  // ```dart
  // // nhentai
  // {'Referer': 'https://nhentai.net/', 'User-Agent': 'Mozilla/5.0...'}
  ///
  // // crotpedia with auth
  // {'Referer': 'https://crotpedia.com/', 'Cookie': 'session=...'}
  // ```
  Map<String, String> getImageDownloadHeaders({
    required String imageUrl,
    Map<String, String>? cookies,
  });

  /// Whether this source's image CDN rejects requests carrying
  /// Referer/Origin (answers 403 — live-proven on comix `rxn.*` hosts).
  /// Download clients must not inject dynamic referer/origin for such
  /// sources; mirrors `ComixImageHeaderInterceptor` on the reader path.
  /// NOTE: mangafire is the opposite case — its CDN REQUIRES a Referer.
  /// Defaults to false (referer allowed).
  bool get omitImageReferer => false;

  // Brand color for this source, used in UI decorations.
  ///
  // This color is used for:
  // - Download item progress bars
  // - Source badges
  // - Accent colors in source-specific screens
  ///
  // Default returns null, which means use app's default theme color.
  int? get brandColor => null;

  // Whether this source displays page counts in list/grid views.
  ///
  // - nhentai: true (shows "123 pages")
  // - manga sources (crotpedia, komiktap): false (shows chapters instead)
  bool get showsPageCountInList => true;

  // Whether this source supports user authentication.
  ///
  // If true, the app will show login/logout menu items for this source.
  bool get supportsAuthentication => false;

  // Whether this source supports bookmarking/favoriting content.
  ///
  // If true, bookmark buttons will be shown in detail screens.
  bool get supportsBookmarks => false;

  // Whether this source implements getRelated with real data.
  ///
  // Default false — sources opt in by overriding. Used to skip useless
  // related-content API calls on detail screens.
  bool get supportsRelated => false;

  // ============ NEW: FilterList & Global Search Support ============

  // Filters available for this source (for advanced search UI).
  ///
  // Returns an empty list by default — backward compatible.
  // Override to expose source-specific filters.
  ///
  // Example:
  // ```dart
  // @override
  // FilterList get filterList => [
  //   SortSourceFilter('Sort By', ['Newest', 'Popular']),
  //   SelectSourceFilter('Language', ['All', 'English', 'Japanese']),
  // ];
  // ```
  FilterList get filterList => const [];

  // Whether this source participates in global search.
  ///
  // Global search dispatches the same query to all enabled sources in parallel
  // and shows results per-source in a single scrollable screen.
  bool get participatesInGlobalSearch => true;

  // Priority in global search results (lower number = shown first).
  ///
  // Default 100. Override to boost or demote in global search ordering.
  int get globalSearchPriority => 100;

  // Maximum results to return in global search context.
  ///
  // Global search shows a preview (not full pagination) per source.
  int get globalSearchMaxResults => 5;

  // Whether this source can handle the given query in global search.
  ///
  // Use this to opt out of global search for certain query formats.
  // Default: always true.
  bool canHandleGlobalQuery(String query) => true;

  // Get autocomplete suggestions for a partial search query.
  ///
  // Returns empty list by default — backward compatible.
  // Override for sources that support tag/artist autocomplete (e.g., nhentai).
  ///
  // [query] is the partial text typed by the user.
  Future<List<AutocompleteSuggestion>> getAutocompleteSuggestions(
    String query,
  ) async => const [];
}
