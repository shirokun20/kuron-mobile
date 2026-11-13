import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import 'webview_chapter_extractor.dart';
import '../webview_session/webview_session_adapter.dart';

/// Interactive fallback callback when headless WebView hits a Turnstile/CF
/// wall or fails to render images. Returns the `pageFinishedScriptResult` JSON.
typedef InteractivePageCollector = Future<String?> Function(
  String pageUrl,
  String script,
);

/// [ContentSource] decorator that serves chapter images from a headless
/// WebView render instead of static HTTP parsing.
///
/// Used when the source's reader config declares
/// `scraper.selectors.reader.mode == 'webviewDom'` (JS-rendered readers
/// such as voratoon's Next.js Server Action chapters, where the HTML
/// carries zero image URLs). Everything else delegates to [inner], so
/// list/detail/search/tag behavior is byte-for-byte identical.
class WebViewDomReaderSource implements ContentSource {
  WebViewDomReaderSource({
    required this._inner,
    required this._extractor,
    required String baseUrl,
    required this._imageSelectors,
    required this._imageAttributes,
    InteractivePageCollector? interactiveCollect,
    Logger? logger,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _interactiveCollect = interactiveCollect,
       _logger = logger ?? Logger();

  final ContentSource _inner;
  final WebViewChapterExtractor _extractor;
  final String _baseUrl;
  final List<String> _imageSelectors;
  final List<String> _imageAttributes;
  final InteractivePageCollector? _interactiveCollect;
  final Logger _logger;
  // ponytails: in-memory chapter cache (capped at 20) + host latch so
  // re-opening/downloading a chapter or moving to the next chapter doesn't
  // re-wait 10s on headless Turnstile once interactive mode was needed.
  final Map<String, ChapterData> _chapterCache = {};
  final Set<String> _interactiveHosts = {};

  /// Chapter page URL: absolute ids pass through, path ids join baseUrl.
  /// (Komikcast chapter ids are raw hrefs like `/series/<slug>/<chapter>`.)
  String pageUrlFor(String chapterId) {
    final id = chapterId.trim();
    if (id.startsWith('http://') || id.startsWith('https://')) return id;
    final path = id.startsWith('/') ? id : '/$id';
    return '$_baseUrl$path';
  }

  @override
  Future<ChapterData?> getChapterImages(String chapterId) async {
    final pageUrl = pageUrlFor(chapterId);
    final cached = _chapterCache[pageUrl];
    if (cached != null && cached.images.isNotEmpty) {
      return cached;
    }

    final host = Uri.tryParse(pageUrl)?.host ?? '';
    try {
      var hitChallenge = false;
      var data = const ChapterData(images: []);

      if (_interactiveCollect == null || !_interactiveHosts.contains(host)) {
        // The native WebView shares no cookies with Dio's jar: seed it so
        // the headless load passes Cloudflare with the same clearance.
        final cookies = WebViewSessionAdapter.getCachedCookieHeaderForUrl(
          pageUrl,
        );
        try {
          data = await _extractor.fetchChapterImages(
            pageUrl: pageUrl,
            imageSelectors: _imageSelectors,
            imageAttributes: _imageAttributes,
            timeout: _interactiveCollect != null
                ? const Duration(seconds: 10)
                : const Duration(seconds: 20),
            cookies: cookies,
          );
        } on ReaderChallengeException {
          hitChallenge = true;
        }
      }

      if (data.images.isEmpty && _interactiveCollect != null) {
        _logger.i(
          'WebViewDomReader: falling back to interactive WebView for $pageUrl',
        );
        final script = WebViewChapterExtractor.buildCollectorScript(
          selectors: _imageSelectors,
          attributes: _imageAttributes,
          detectChallenge: false,
        );
        final raw = await _interactiveCollect(pageUrl, script);
        final collected = WebViewChapterExtractor.parseCollected(raw);
        if (collected.images.isNotEmpty) {
          if (host.isNotEmpty) _interactiveHosts.add(host);
          final result = ChapterData(images: collected.images);
          _cacheChapter(pageUrl, result);
          return result;
        }
      }

      if (hitChallenge) {
        throw ReaderChallengeException(pageUrl);
      }

      if (data.images.isNotEmpty) {
        _cacheChapter(pageUrl, data);
      }

      // Empty stays empty (not an exception): the repository's reader
      // detector + health gate decide anomaly vs network, same as HTTP.
      return data;
    } catch (e) {
      // Challenge walls and platform failures propagate so the
      // repository records them via the error log instead of
      // misreporting an empty chapter.
      _logger.w('WebViewDomReader failed for $chapterId: $e');
      rethrow;
    }
  }

  void _cacheChapter(String pageUrl, ChapterData data) {
    if (_chapterCache.length >= 20) {
      _chapterCache.remove(_chapterCache.keys.first);
    }
    _chapterCache[pageUrl] = data;
  }

  @override
  String get id => _inner.id;

  @override
  String get displayName => _inner.displayName;

  @override
  String get iconPath => _inner.iconPath;

  @override
  String get baseUrl => _inner.baseUrl;

  @override
  bool get requiresBypass => _inner.requiresBypass;

  @override
  String get refererHeader => _inner.refererHeader;

  @override
  bool get showsPageCountInList => _inner.showsPageCountInList;

  @override
  bool get supportsAuthentication => _inner.supportsAuthentication;

  @override
  bool get supportsBookmarks => _inner.supportsBookmarks;

  @override
  bool get supportsRelated => _inner.supportsRelated;

  @override
  bool get participatesInGlobalSearch => _inner.participatesInGlobalSearch;

  @override
  int? get brandColor => _inner.brandColor;

  @override
  String buildImageUrl({
    required String contentId,
    required String mediaId,
    required int page,
    required String extension,
    bool thumbnail = false,
  }) => _inner.buildImageUrl(
    contentId: contentId,
    mediaId: mediaId,
    page: page,
    extension: extension,
    thumbnail: thumbnail,
  );

  @override
  String buildThumbnailUrl({
    required String contentId,
    required String mediaId,
  }) => _inner.buildThumbnailUrl(contentId: contentId, mediaId: mediaId);

  @override
  String? parseContentIdFromUrl(String url) =>
      _inner.parseContentIdFromUrl(url);

  @override
  bool isValidContentId(String contentId) => _inner.isValidContentId(contentId);

  @override
  Map<String, String> getImageDownloadHeaders({
    required String imageUrl,
    Map<String, String>? cookies,
  }) => _inner.getImageDownloadHeaders(imageUrl: imageUrl, cookies: cookies);

  @override
  FilterList get filterList => _inner.filterList;

  @override
  int get globalSearchPriority => _inner.globalSearchPriority;

  @override
  int get globalSearchMaxResults => _inner.globalSearchMaxResults;

  @override
  SearchCapabilities get searchCapabilities => _inner.searchCapabilities;
  @override
  bool canHandleGlobalQuery(String query) => _inner.canHandleGlobalQuery(query);

  @override
  Future<ContentListResult> search(SearchFilter filter) =>
      _inner.search(filter);

  @override
  Future<Content> getDetail(String contentId) => _inner.getDetail(contentId);

  @override
  Future<ContentListResult> getList({
    int page = 1,
    SortOption sort = SortOption.newest,
  }) => _inner.getList(page: page, sort: sort);

  @override
  Future<ContentListResult> getPopular({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
  }) => _inner.getPopular(timeframe: timeframe, page: page);

  @override
  Future<List<Content>> getRandom({int count = 1}) =>
      _inner.getRandom(count: count);

  @override
  Future<List<Content>> getRelated(String contentId) =>
      _inner.getRelated(contentId);

  @override
  Future<List<Comment>> getComments(String contentId) =>
      _inner.getComments(contentId);

  @override
  Future<List<Chapter>> getChapters(
    String contentId, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) => _inner.getChapters(
    contentId,
    language: language,
    scanGroup: scanGroup,
    page: page,
    offset: offset,
    limit: limit,
  );

  @override
  Future<List<AutocompleteSuggestion>> getAutocompleteSuggestions(
    String query,
  ) => _inner.getAutocompleteSuggestions(query);
}
