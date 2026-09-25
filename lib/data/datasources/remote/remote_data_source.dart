import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart' show registrableDomain;
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart'
    hide NetworkException;
import 'package:nhasixapp/data/datasources/remote/cloudflare_bypass_no_webview.dart';
import 'package:nhasixapp/domain/services/app_initializer.dart';
import 'dart:math';

import '../../models/content_model.dart';
import '../../models/tag_model.dart';
import '../../models/comment_model.dart';
import '../../../domain/entities/search_filter.dart';
import '../../../../core/config/api_config.dart';
import 'api/nhentai_api_client.dart';
import 'api/nhentai_api_models.dart';
import 'nhentai_scraper.dart';
import 'anti_detection.dart';
import 'request_rate_manager.dart';
import 'exceptions.dart';
import '../../../../core/config/remote_config_service.dart';

// Remote data source for nhentai.net
// Supports both API and HTML scraping with automatic fallback
class RemoteDataSource implements AppInitializer {
  RemoteDataSource({
    required this.httpClient,
    required this.scraper,
    required this.cloudflareBypass,
    required this.antiDetection,
    required RequestRateManager rateManager,
    required RemoteConfigService remoteConfigService,
    this.apiClient,
    Logger? logger,
  })  : _logger = logger ?? Logger(),
        _rateManager = rateManager,
        _remoteConfigService = remoteConfigService;

  final Dio httpClient;
  final NhentaiScraper scraper;
  final CloudflareBypassNoWebView cloudflareBypass;
  final AntiDetection antiDetection;
  final NhentaiApiClient? apiClient;
  final Logger _logger;
  final RequestRateManager _rateManager;
  final RemoteConfigService _remoteConfigService;

  // Whether to prefer API over scraping
  bool _useApi = true;

  String get baseUrl =>
      _remoteConfigService.getConfig('nhentai')?.baseUrl ??
      'https://nhentai.net';

  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;

  // Public method to fetch HTML content from a specific path
  // Used by feature-specific repositories (e.g., Crotpedia)
  Future<String> fetchHtml(String path) async {
    // Trust boundary: only relative paths may be fetched. Absolute URLs
    // (including protocol-relative `//host/path`) are rejected unless they
    // target the source's own registrable domain over https.
    if (path.startsWith('//')) {
      throw StateError('fetchHtml rejected: protocol-relative URL: $path');
    }
    if (!path.startsWith('/')) {
      final parsed = Uri.tryParse(path);
      if (parsed == null || parsed.host.isEmpty) {
        throw StateError('fetchHtml rejected: not a valid path: $path');
      }
      if (parsed.scheme != 'https') {
        throw StateError('fetchHtml rejected: non-https: $path');
      }
      if (registrableDomain(parsed) != registrableDomain(Uri.parse(baseUrl))) {
        throw StateError('fetchHtml rejected: host not allowed: $path');
      }
    }
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    return _getPageHtml(url);
  }

  bool _isRedirectStatus(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  // Same rules as kuron_generic's redirect guard (task 3.3): target must
  // stay on the origin's registrable domain, no https -> http downgrade.
  bool _isAllowedRedirect(Uri origin, Uri target) {
    if (target.scheme != 'https' && origin.scheme == 'https') {
      return false; // protocol downgrade
    }
    final originDomain = registrableDomain(origin);
    final targetDomain = registrableDomain(target);
    if (originDomain == null || targetDomain == null) return false;
    return originDomain == targetDomain;
  }

  // Initialize the remote data source
  @override
  Future<bool> initialize() async {
    try {
      _logger.i('Initializing RemoteDataSource...');

      // Configure HTTP client
      _configureHttpClient();

      // Initialize anti-detection measures
      await antiDetection.initialize();

      // Attempt Cloudflare bypass
      final bypassSuccess =
          await cloudflareBypass.attemptBypass(targetUrl: baseUrl);
      if (!bypassSuccess) {
        _logger.w('Cloudflare bypass failed, some requests may fail');
        return false;
      }
      return true;
    } catch (e, stackTrace) {
      _logger.e('Failed to initialize RemoteDataSource',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get content list from homepage or specific page (with tag resolution)
  Future<List<ContentModel>> getContentList({int page = 1}) async {
    try {
      _logger.i('Fetching content list for page $page');

      final url = '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      // For homepage (page 1), use the specialized parser to get only index containers
      final contents = page == 1
          ? await scraper.parseFromIndexContainers(html)
          : await scraper.parseContentList(html);

      _logger
          .i('Successfully parsed ${contents.length} contents from page $page');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to get content list for page $page',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get content list with pagination information (with tag resolution)
  Future<Map<String, dynamic>> getContentListWithPagination(
      {int page = 1}) async {
    try {
      _logger.i('Fetching content list with pagination for page $page');

      final url = '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      // Parse content list
      final contents = page == 1
          ? await scraper.parseFromIndexContainers(html)
          : await scraper.parseContentList(html);

      // Parse pagination info
      final paginationInfo = scraper.parsePaginationInfo(html);

      _logger.i(
          'Successfully parsed ${contents.length} contents and pagination info for page $page');

      return {
        'contents': contents,
        'pagination': paginationInfo,
      };
    } catch (e, stackTrace) {
      _logger.e('Failed to get content list with pagination for page $page',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get content list from homepage or specific page (sync version without tag resolution)
  // Use this for better performance when tag resolution is not needed
  Future<List<ContentModel>> getContentListSync({int page = 1}) async {
    try {
      _logger.i('Fetching content list (sync) for page $page');

      final url = page == 1 ? baseUrl : '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      // For homepage (page 1), use the specialized parser to get only index containers
      final contents = page == 1
          ? scraper.parseFromIndexContainersSync(html)
          : scraper.parseContentListSync(html);

      _logger.i(
          'Successfully parsed ${contents.length} contents from page $page (sync)');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to get content list (sync) for page $page',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get homepage content separated by sections (with tag resolution)
  Future<Map<String, List<ContentModel>>> getHomepageContent() async {
    try {
      _logger.i('Fetching homepage content with sections');

      final html = await _getPageHtml(baseUrl);
      final result = await scraper.parseHomepage(html);

      _logger.i(
          'Successfully parsed homepage: ${result['popular']!.length} popular, ${result['new_uploads']!.length} new uploads');

      return result;
    } catch (e, stackTrace) {
      _logger.e('Failed to get homepage content',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get homepage content separated by sections (sync version without tag resolution)
  // Use this for better performance when tag resolution is not needed
  Future<Map<String, List<ContentModel>>> getHomepageContentSync() async {
    try {
      _logger.i('Fetching homepage content with sections (sync)');

      final html = await _getPageHtml(baseUrl);
      final result = scraper.parseHomepageSync(html);

      _logger.i(
          'Successfully parsed homepage (sync): ${result['popular']!.length} popular, ${result['new_uploads']!.length} new uploads');

      return result;
    } catch (e, stackTrace) {
      _logger.e('Failed to get homepage content (sync)',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get detailed content information
  Future<ContentModel> getContentDetail(String contentId) async {
    try {
      _logger.i('Fetching content detail for ID: $contentId');

      final url = '$baseUrl/g/$contentId/';
      final html = await _getPageHtml(url);

      final content = scraper.parseContentDetail(html, contentId);
      _logger.i('Successfully parsed content detail for ID: $contentId');

      return content;
    } catch (e, stackTrace) {
      _logger.e('Failed to get content detail for ID: $contentId',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Search content with filters (with tag resolution)
  Future<List<ContentModel>> searchContent(SearchFilter filter) async {
    try {
      _logger.i('Searching content with filter: ${filter.toQueryString()}');

      final url = _buildSearchUrl(filter);
      final html = await _getPageHtml(url);

      final contents = await scraper.parseSearchResults(html);
      _logger.i('Successfully found ${contents.length} search results');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to search content', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Search content with filters and pagination info (with tag resolution)
  Future<Map<String, dynamic>> searchContentWithPagination(
      SearchFilter filter) async {
    try {
      _logger.i(
          'Searching content with pagination for filter: ${filter.toQueryString()}');

      final url = _buildSearchUrl(filter);
      final html = await _getPageHtml(url);

      // Parse search results
      final contents = await scraper.parseSearchResults(html);

      //
      final totalData = await scraper.parseTotalData(html);

      // Parse pagination info
      final paginationInfo = scraper.parsePaginationInfo(html);

      _logger.i(
          'Successfully found ${contents.length} search results with pagination info');

      return {
        'contents': contents,
        'pagination': paginationInfo,
        'totalData': totalData,
      };
    } catch (e, stackTrace) {
      _logger.e('Failed to search content with pagination',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Search content with filters (sync version without tag resolution)
  // Use this for better performance when tag resolution is not needed
  Future<List<ContentModel>> searchContentSync(SearchFilter filter) async {
    try {
      _logger
          .i('Searching content (sync) with filter: ${filter.toQueryString()}');

      final url = _buildSearchUrl(filter);
      final html = await _getPageHtml(url);

      final contents = scraper.parseSearchResultsSync(html);
      _logger.i('Successfully found ${contents.length} search results (sync)');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to search content (sync)',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get random content
  Future<ContentModel> getRandomContent() async {
    try {
      _logger.i('Fetching random content ID (scraping /random/)');

      final url = '$baseUrl/random/';
      final html = await _getPageHtml(url);

      // Extract content ID from the redirected URL or page content
      final contentId = scraper.extractContentIdFromPage(html);
      if (contentId == null) {
        _logger.e('Failed to extract content ID from random page');
        _logger.d(
            'HTML content preview: ${html.length > 500 ? html.substring(0, 500) : html}...');
        throw Exception('Failed to extract content ID from random page');
      }

      _logger.i(
          'Successfully extracted content ID: $contentId from random page. Fetching details via API...');

      // Use API-enabled method to get details
      return await getContentDetailViaApi(contentId);
    } catch (e, stackTrace) {
      _logger.e('Failed to get random content',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get popular content (with tag resolution)
  Future<List<ContentModel>> getPopularContent({
    String period = 'all', // all, week, today
    int page = 1,
  }) async {
    try {
      _logger.i('Fetching popular content for period: $period, page: $page');

      // nhentai doesn't support empty query search, use homepage for browsing
      // Homepage shows latest content - for actual popularity sorting, we'd need different logic
      final url = '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      final contents = await scraper.parseContentList(html);
      _logger.i('Successfully parsed ${contents.length} popular contents');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to get popular content',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get popular content with pagination info (with tag resolution)
  Future<Map<String, dynamic>> getPopularContentWithPagination({
    String period = 'all', // all, week, today
    int page = 1,
  }) async {
    try {
      _logger.i(
          'Fetching popular content with pagination for period: $period, page: $page');

      // nhentai doesn't support empty query search, use homepage for browsing
      // Homepage shows latest content - for actual popularity sorting, we'd need different logic
      final url = '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      // Parse content list
      final contents = await scraper.parseContentList(html);

      // Parse pagination info
      final paginationInfo = scraper.parsePaginationInfo(html);

      _logger.i(
          'Successfully parsed ${contents.length} popular contents with pagination info');

      return {
        'contents': contents,
        'pagination': paginationInfo,
      };
    } catch (e, stackTrace) {
      _logger.e('Failed to get popular content with pagination',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get popular content (sync version without tag resolution)
  // Use this for better performance when tag resolution is not needed
  Future<List<ContentModel>> getPopularContentSync({
    String period = 'all', // all, week, today
    int page = 1,
  }) async {
    try {
      _logger.i(
          'Fetching popular content (sync) for period: $period, page: $page');

      // nhentai doesn't support empty query search, use homepage for browsing
      // Homepage shows latest content - for actual popularity sorting, we'd need different logic
      final url = '$baseUrl/?page=$page';
      final html = await _getPageHtml(url);

      final contents = scraper.parseContentListSync(html);
      _logger
          .i('Successfully parsed ${contents.length} popular contents (sync)');

      return contents;
    } catch (e, stackTrace) {
      _logger.e('Failed to get popular content (sync)',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get all available tags
  Future<List<TagModel>> getAllTags() async {
    try {
      _logger.i('Fetching all tags');

      final url = '$baseUrl/tags/';
      final html = await _getPageHtml(url);

      final tags = scraper.parseTagsPage(html);
      _logger.i('Successfully parsed ${tags.length} tags');

      return tags;
    } catch (e, stackTrace) {
      _logger.e('Failed to get all tags', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get tags by type (artist, character, etc.)
  Future<List<TagModel>> getTagsByType(String type) async {
    try {
      _logger.i('Fetching tags for type: $type');

      final url = '$baseUrl/${type}s/'; // artists/, characters/, etc.
      final html = await _getPageHtml(url);

      final tags = scraper.parseTagsPage(html, type: type);
      _logger.i('Successfully parsed ${tags.length} $type tags');

      return tags;
    } catch (e, stackTrace) {
      _logger.e('Failed to get tags for type: $type',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Check if Cloudflare bypass is needed
  @override
  Future<bool> checkCloudflareStatus() async {
    _logger.i('Checking Cloudflare status... from $baseUrl');
    try {
      final response = await httpClient.get(baseUrl);

      _logger.i('Cloudflare status: ${response.statusCode}');

      return !cloudflareBypass.isCloudflareChallenge(response.data) ||
          response.statusCode == 200;
    } catch (e, stackTrace) {
      _logger.w('Failed to check Cloudflare status: $e, and $stackTrace');
      return false;
    }
  }

  // Attempt to bypass Cloudflare protection
  @override
  Future<bool> bypassCloudflare() async {
    try {
      _logger.i('Attempting Cloudflare bypass...');
      return await cloudflareBypass.attemptBypass(targetUrl: baseUrl);
    } catch (e, stackTrace) {
      _logger.e('Cloudflare bypass failed', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // Get HTML content from URL with retry logic
  Future<String> _getPageHtml(String url) async {
    RemoteDataSourceException? lastException;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.d('Fetching HTML from: $url (attempt $attempt/$maxRetries)');

        // Check intelligent rate manager
        if (!_rateManager.canMakeRequest()) {
          if (_rateManager.isInCooldown) {
            final remainingTime = _rateManager.remainingCooldown;
            _logger
                .w('In cooldown, ${remainingTime?.inSeconds ?? 0}s remaining');
            throw const RateLimitException('In cooldown period', '429');
          } else {
            _logger.w('Rate limit protection triggered');
            _rateManager.triggerCooldown();
            throw const RateLimitException(
                'Request rate limit exceeded', '429');
          }
        }

        // Apply intelligent delay
        final delay = _rateManager.calculateDelay();
        _logger.d('Applying intelligent delay: ${delay.inMilliseconds}ms');
        await Future.delayed(delay);

        // Check if we should throttle requests (backup check)
        if (antiDetection.shouldThrottleRequests()) {
          _logger.w('Rate limit protection triggered, waiting 30 seconds...');
          await Future.delayed(const Duration(seconds: 30));
          antiDetection.resetCounters(); // Reset counters after cooldown
          throw const RateLimitException(
              'Request rate limit exceeded - cooldown applied');
        }

        // Apply anti-detection measures
        await antiDetection.applyRandomDelay();

        // Calculate referer based on URL
        final uri = Uri.parse(url);
        final referer = '${uri.scheme}://${uri.host}/';

        final headers = antiDetection.getRandomHeaders(referer: referer);

        // Scoped per-host bypass cookies (never global). Count only in logs.
        final bypassCookie = cloudflareBypass.cookieHeaderFor(uri.host) ?? '';
        if (bypassCookie.isNotEmpty) {
          headers.putIfAbsent('Cookie', () => bypassCookie);
        }

        // Redirect allowlist (task 3.3): only same-registrable-domain
        // targets, no https -> http downgrade. Manual hop loop because dio
        // 5.x has no onRedirect callback; each hop is validated, rejected
        // hops throw -> retry loop.
        var currentResponse = await httpClient.get(
          url,
          options: Options(
            headers: headers,
            sendTimeout: requestTimeout,
            receiveTimeout: requestTimeout,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
            responseType: ResponseType.plain,
          ),
        );
        var hopCount = 0;
        while (currentResponse.statusCode != null &&
            _isRedirectStatus(currentResponse.statusCode!) &&
            hopCount < 5) {
          final location = currentResponse.headers.value('location')?.trim();
          if (location == null || location.isEmpty) break;
          final next = Uri.parse(url).resolve(location);
          if (!_isAllowedRedirect(Uri.parse(url), next)) {
            _logger.w('Redirect rejected: $url -> $next');
            throw NetworkException('Redirect rejected: $url -> $next',
                '${currentResponse.statusCode}');
          }
          hopCount++;
          currentResponse = await httpClient.get(
            next.toString(),
            options: Options(
              headers: headers,
              sendTimeout: requestTimeout,
              receiveTimeout: requestTimeout,
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
              responseType: ResponseType.plain,
            ),
          );
        }
        final response = currentResponse;

        if (response.statusCode == 200) {
          final html = response.data as String;

          // Record successful request
          _rateManager.recordRequest();

          // Check if Cloudflare challenge is present
          if (cloudflareBypass.isCloudflareChallenge(html)) {
            _logger.w(
                'Cloudflare challenge detected, attempting bypass for $url...');
            final bypassSuccess =
                await cloudflareBypass.attemptBypass(targetUrl: url);
            if (!bypassSuccess) {
              throw const CloudflareException(
                  'Failed to bypass Cloudflare protection');
            }
            // Retry the request after bypass
            continue;
          }

          return html;
        } else if (response.statusCode == 404) {
          throw ContentNotFoundException(
              'Content not found: $url', response.statusCode.toString());
        } else if (response.statusCode == 429) {
          // Server returned rate limit, trigger our cooldown
          _rateManager.triggerCooldown();
          throw RateLimitException(
              'Rate limit exceeded: $url', response.statusCode.toString());
        } else if (response.statusCode! >= 500) {
          throw ServerException('Server error: ${response.statusCode}',
              response.statusCode.toString());
        } else {
          throw NetworkException(
              'HTTP ${response.statusCode}: ${response.statusMessage}',
              response.statusCode.toString());
        }
      } on DioException catch (e, stackTrace) {
        lastException = _handleDioException(e, url);
        _logger.w('Attempt $attempt failed: $lastException, $stackTrace');

        if (attempt < maxRetries && _shouldRetry(lastException)) {
          // Exponential backoff with jitter
          final delay = Duration(
            milliseconds:
                (1000 * pow(2, attempt - 1)).toInt() + Random().nextInt(1000),
          );
          _logger.d('Waiting ${delay.inMilliseconds}ms before retry...');
          await Future.delayed(delay);
        } else {
          break;
        }
      } catch (e) {
        lastException = ParseException('Unexpected error: $e');
        _logger.w('Attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          final delay = Duration(
            milliseconds:
                (1000 * pow(2, attempt - 1)).toInt() + Random().nextInt(1000),
          );
          _logger.d('Waiting ${delay.inMilliseconds}ms before retry...');
          await Future.delayed(delay);
        }
      }
    }

    throw lastException ??
        const NetworkException(
            'Failed to fetch HTML after $maxRetries attempts');
  }

  // Handle Dio exceptions and convert to appropriate exception types
  RemoteDataSourceException _handleDioException(DioException e, String url) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException('Request timeout for: $url', e.type.toString());

      case DioExceptionType.connectionError:
        return NetworkException(
            'Connection error for: $url', e.type.toString());

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 404) {
          return ContentNotFoundException(
              'Content not found: $url', statusCode.toString());
        } else if (statusCode == 429) {
          return RateLimitException(
              'Rate limit exceeded: $url', statusCode.toString());
        } else if (statusCode != null && statusCode >= 500) {
          return ServerException(
              'Server error $statusCode for: $url', statusCode.toString());
        } else {
          return NetworkException(
              'Bad response for: $url', statusCode.toString());
        }

      case DioExceptionType.cancel:
        return NetworkException(
            'Request cancelled for: $url', e.type.toString());

      case DioExceptionType.unknown:
      default:
        return NetworkException(
            'Unknown error for: $url - ${e.message}', e.type.toString());
    }
  }

  // Check if exception should trigger a retry
  bool _shouldRetry(RemoteDataSourceException exception) {
    return exception is NetworkException ||
        exception is TimeoutException ||
        exception is ServerException ||
        exception is CloudflareException;
  }

  // Configure HTTP client with default settings and enhanced error handling
  void _configureHttpClient() {
    httpClient.options.baseUrl = baseUrl;

    // Only set timeouts if they haven't been configured already
    httpClient.options.connectTimeout ??= requestTimeout;
    httpClient.options.receiveTimeout ??= requestTimeout;
    httpClient.options.sendTimeout ??= requestTimeout;

    httpClient.options.followRedirects = true;
    httpClient.options.maxRedirects = 5;
    httpClient.options.responseType = ResponseType.plain;

    // Use NativeAdapter for the main HTTP client as well to fix scraping issues
    httpClient.httpClientAdapter = NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.ephemeralSessionConfiguration(),
    );

    // Add enhanced error handling interceptor
    httpClient.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _logger.d('HTTP Request: ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.d(
              'HTTP Response: ${response.statusCode} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (error, handler) {
          _logger.e('HTTP Error: ${error.message}');

          // Enhanced error handling for connection issues
          if (error.type == DioExceptionType.connectionError) {
            _logger.w(
                'Connection error detected - HTTP client may need reinitialization');
          } else if (error.type == DioExceptionType.connectionTimeout) {
            _logger
                .w('Connection timeout - network may be slow or unavailable');
          } else if (error.type == DioExceptionType.receiveTimeout) {
            _logger.w('Receive timeout - server may be overloaded');
          }

          handler.next(error);
        },
      ),
    );

    // Add logging interceptor (after error handling)
    httpClient.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => _logger.d(obj),
      ),
    );
  }

  // Build search URL from filter
  String _buildSearchUrl(SearchFilter filter) {
    final buffer = StringBuffer('$baseUrl/search/?');

    // Get tag mappings from config
    final mapping =
        _remoteConfigService.tagsManifest?.sources['nhentai']?.mappings ?? {};

    // Use the full query string from SearchFilter.toQueryString()
    final queryString = filter.toQueryString(prefixMap: mapping);

    if (queryString.isNotEmpty) {
      buffer.write(queryString);
    } else {
      buffer.write('q=');
    }

    return buffer.toString();
  }

  // Check HTTP client health and connection status
  Future<bool> checkConnectionHealth() async {
    try {
      _logger.d('Checking HTTP client connection health...');

      // Simple connectivity test
      final response = await httpClient.get(
        'https://httpbin.org/status/200',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final isHealthy = response.statusCode == 200;
      _logger.d(
          'HTTP client health check: ${isHealthy ? 'HEALTHY' : 'UNHEALTHY'}');

      return isHealthy;
    } catch (e) {
      _logger.w('HTTP client health check failed: $e');
      return false;
    }
  }

  // Get HTTP client statistics for monitoring
  Map<String, dynamic> getHttpClientStats() {
    return {
      'base_url': httpClient.options.baseUrl,
      'connect_timeout': httpClient.options.connectTimeout?.inMilliseconds,
      'receive_timeout': httpClient.options.receiveTimeout?.inMilliseconds,
      'send_timeout': httpClient.options.sendTimeout?.inMilliseconds,
      'interceptors_count': httpClient.interceptors.length,
      'headers_count': httpClient.options.headers.length,
    };
  }

  // IMPORTANT: RemoteDataSource should NEVER dispose the HTTP client
  // The HTTP client is managed as a singleton and should persist throughout
  // the application lifecycle to prevent connection errors
  ///
  // This method is intentionally removed to prevent accidental disposal
  // If cleanup is needed, it should be handled at the application level

  // ============ API Methods with Fallback ============

  // Toggle API mode on/off
  void setApiMode(bool enabled) {
    _useApi = enabled && apiClient != null;
    _logger.i('API mode ${_useApi ? 'enabled' : 'disabled'}');
  }

  // Check if API client is available and healthy
  Future<bool> isApiAvailable() async {
    if (apiClient == null) return false;
    try {
      return await apiClient!.checkHealth();
    } catch (e) {
      _logger.w('API health check failed: $e');
      return false;
    }
  }

  // Get content list via API with fallback to scraping
  Future<List<ContentModel>> getContentListViaApi({
    int page = 1,
    SortOption sortBy = SortOption.newest,
  }) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        _logger.i(
            '🚀 [API MODE] Fetching content list for page $page with sort $sortBy');

        NhentaiListResponse response;

        if (sortBy == SortOption.newest) {
          response = await apiClient!.getAllGalleries(page: page);
        } else {
          // Map SortOption to popular period
          String period = 'all';
          if (sortBy == SortOption.popularWeek) period = 'week';
          if (sortBy == SortOption.popularToday) period = 'today';

          response = await apiClient!.getPopular(period: period, page: page);
        }

        final contents = response.result
            .map((g) => ContentModel.fromNhentaiApiPreview(g))
            .toList();
        _logger.i(
            '✅ [API SUCCESS] Fetched ${contents.length} contents from page $page');
        return contents;
      } catch (e) {
        _logger.w('⚠️ [API FAILED] Falling back to HTML scraping: $e');
        // Fall through to scraping
      }
    } else {
      _logger.d('📄 [SCRAPER MODE] API disabled or unavailable');
    }

    // Fallback to HTML scraping
    if (sortBy == SortOption.newest) {
      _logger.i('📄 [SCRAPER MODE] Fetching content list for page $page');
      return getContentList(page: page);
    } else {
      _logger.i('📄 [SCRAPER MODE] Fetching popular content for page $page');
      // Map to existing scraper method for popular
      String period = 'all';
      if (sortBy == SortOption.popularWeek) period = 'week';
      if (sortBy == SortOption.popularToday) period = 'today';
      return getPopularContent(period: period, page: page);
    }
  }

  // Get content list with pagination via API with fallback
  Future<Map<String, dynamic>> getContentListWithPaginationViaApi({
    int page = 1,
    SortOption sortBy = SortOption.newest,
  }) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        _logger.i(
            '🚀 [API MODE] Fetching content list with pagination for page $page with sort $sortBy');

        NhentaiListResponse response;

        if (sortBy == SortOption.newest) {
          response = await apiClient!.getAllGalleries(page: page);
        } else {
          // Map SortOption to popular period
          String period = 'all';
          if (sortBy == SortOption.popularWeek) period = 'week';
          if (sortBy == SortOption.popularToday) period = 'today';

          response = await apiClient!.getPopular(period: period, page: page);
        }

        final contents = response.result
            .map((g) => ContentModel.fromNhentaiApiPreview(g))
            .toList();
        // Workaround: nhentai API sometimes doesn't return num_pages
        // If null, assume there's always a next page if we got results
        // nhentai typically returns 25 items per page
        final totalPages = response.numPages ?? 9999; // Large number if unknown
        final hasNext = response.numPages != null
            ? page < totalPages
            : contents.isNotEmpty; // Assume more if we got results

        _logger.i(
            '✅ [API SUCCESS] Fetched ${contents.length} contents | Page: $page/${response.numPages ?? "???"} | HasNext: $hasNext');

        return {
          'contents': contents,
          'pagination': {
            'currentPage': page,
            'totalPages': totalPages,
            'totalCount': 0, // Not provided by API explicitly usually
            'hasNext': hasNext,
            'hasPrevious': page > 1,
          }
        };
      } catch (e) {
        _logger.w('⚠️ [API FAILED] Falling back to HTML scraping: $e');
        // Fall through to scraping
      }
    } else {
      _logger.d('📄 [SCRAPER MODE] API disabled or unavailable');
    }

    // Fallback to HTML scraping
    if (sortBy == SortOption.newest) {
      _logger.i(
          '📄 [SCRAPER MODE] Fetching content list with pagination for page $page');
      return getContentListWithPagination(page: page);
    } else {
      _logger.i(
          '📄 [SCRAPER MODE] Fetching popular content with pagination for page $page');
      // Map to existing scraper method for popular
      String period = 'all';
      if (sortBy == SortOption.popularWeek) period = 'week';
      if (sortBy == SortOption.popularToday) period = 'today';
      return getPopularContentWithPagination(period: period, page: page);
    }
  }

  // Get content detail via API with fallback
  Future<ContentModel> getContentDetailViaApi(String contentId) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        _logger.i('🚀 [API MODE] Fetching content detail for ID: $contentId');
        final response = await apiClient!.getGallery(contentId);
        final content = ContentModel.fromNhentaiApi(response);
        _logger.i('✅ [API SUCCESS] Fetched content detail for ID: $contentId');
        return content;
      } catch (e) {
        _logger.w('⚠️ [API FAILED] Falling back to HTML scraping: $e');
        // Fall through to scraping
      }
    } else {
      _logger.d('📄 [SCRAPER MODE] API disabled or unavailable');
    }

    // Fallback to HTML scraping
    _logger.i('📄 [SCRAPER MODE] Fetching content detail for ID: $contentId');
    return getContentDetail(contentId);
  }

  // Search content via API with fallback
  Future<List<ContentModel>> searchContentViaApi(SearchFilter filter) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        // Build full query string including tags, artists, language, etc.
        final fullQuery = filter.buildQueryString();
        _logger.i('🔍 [API SEARCH] Query: "$fullQuery"');

        // Build API-compatible sort
        final sort = ApiConfig.mapSortOption(filter.sortBy.name);

        final response = await apiClient!.search(
          fullQuery,
          sort: sort,
          page: filter.page,
        );

        final contents = response.result
            .map((g) => ContentModel.fromNhentaiApiPreview(g))
            .toList();

        _logger.i('✅ [API SEARCH SUCCESS] Returned ${contents.length} results');
        return contents;
      } catch (e) {
        _logger.w('⚠️ [API SEARCH FAILED] Falling back to scraping: $e');
        // Fall through to scraping
      }
    }

    // Fallback to HTML scraping
    _logger.i('📄 [SCRAPER SEARCH] Using HTML scraping for search');
    return searchContent(filter);
  }

  // Search content with pagination via API with fallback
  Future<Map<String, dynamic>> searchContentWithPaginationViaApi(
      SearchFilter filter) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        // Build full query string including tags, artists, language, etc.
        final fullQuery = filter.buildQueryString();
        _logger.i('🔍 [API SEARCH] Query: "$fullQuery" | Page: ${filter.page}');

        final sort = ApiConfig.mapSortOption(filter.sortBy.name);

        final response = await apiClient!.search(
          fullQuery,
          sort: sort,
          page: filter.page,
        );

        final contents = response.result
            .map((g) => ContentModel.fromNhentaiApiPreview(g))
            .toList();

        // Workaround for null numPages
        final totalPages = response.numPages ?? 9999;
        final hasNext = response.numPages != null
            ? filter.page < totalPages
            : contents.isNotEmpty;

        _logger.i(
            '✅ [API SEARCH SUCCESS] ${contents.length} results | Page: ${filter.page}/${response.numPages ?? "???"} | HasNext: $hasNext');

        return {
          'contents': contents,
          'pagination': {
            'currentPage': filter.page,
            'totalPages': totalPages,
            'hasNext': hasNext,
            'hasPrevious': filter.page > 1,
          },
          'totalData': response.numPages != null
              ? (response.numPages! * 25)
              : contents.length,
        };
      } catch (e) {
        _logger.w('⚠️ [API SEARCH FAILED] Falling back to scraping: $e');
        // Fall through to scraping
      }
    }

    // Fallback to HTML scraping
    _logger.i('📄 [SCRAPER SEARCH] Using HTML scraping for search');
    return searchContentWithPagination(filter);
  }

  // Get popular content via API with fallback
  Future<List<ContentModel>> getPopularContentViaApi({
    String period = 'all',
    int page = 1,
  }) async {
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        _logger
            .i('Fetching popular content via API: period=$period, page=$page');
        final response =
            await apiClient!.getPopular(period: period, page: page);

        final contents = response.result
            .map((g) => ContentModel.fromNhentaiApiPreview(g))
            .toList();

        _logger
            .i('API: Successfully fetched ${contents.length} popular contents');
        return contents;
      } catch (e) {
        _logger.w('API failed, falling back to scraping: $e');
        // Fall through to scraping
      }
    }

    // Fallback to HTML scraping
    return getPopularContent(period: period, page: page);
  }

  // Get related content via API (API only, no scraping equivalent)
  Future<List<ContentModel>> getRelatedContentViaApi(String contentId) async {
    if (apiClient == null) {
      _logger.w('API client not available for related content');
      return [];
    }

    try {
      _logger.i('Fetching related content via API for ID: $contentId');
      final response = await apiClient!.getRelated(contentId);

      final contents = response.result
          .map((g) => ContentModel.fromNhentaiApiPreview(g))
          .toList();

      _logger.i('API: Found ${contents.length} related contents');
      return contents;
    } catch (e) {
      _logger.e('Failed to get related content: $e');
      return [];
    }
  }

  // Get comments for a gallery (API preferred, fallback to Scraping)
  Future<List<CommentModel>> getComments(String contentId) async {
    // 1. Try API first
    if (_useApi && apiClient != null && ApiConfig.enableApiFallback) {
      try {
        _logger.i('🚀 [API MODE] Fetching comments for ID: $contentId');
        final apiComments = await apiClient!.getComments(contentId);

        final comments =
            apiComments.map((c) => CommentModel.fromApi(c)).toList();

        _logger.i(
            '✅ [API SUCCESS] Fetched ${comments.length} comments for ID: $contentId');
        return comments;
      } catch (e) {
        _logger.w(
            '⚠️ [API FAILED] Falling back to HTML scraping for comments: $e');
        // Fall through to scraping
      }
    } else {
      _logger.d('📄 [SCRAPER MODE] API disabled or unavailable');
    }

    return [];
  }
}
