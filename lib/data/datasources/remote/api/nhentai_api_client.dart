library;

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../../../../core/config/remote_config_service.dart';
import '../../../../core/config/api_config.dart';
import '../anti_detection.dart';
import '../request_rate_manager.dart';
import 'nhentai_api_models.dart';
import 'nhentai_api_comments_model.dart';

class NhentaiApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const NhentaiApiException(
    this.message, {
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'NhentaiApiException: $message (status: $statusCode)';

  bool get isRateLimited => statusCode == 429;

  bool get isNotFound => statusCode == 404;

  bool get isServerError => statusCode != null && statusCode! >= 500;

  bool get shouldRetry => isServerError || isRateLimited;
}

class NhentaiApiClient {
  final Dio _dio;
  final Logger _logger = getIt<Logger>();
  final RequestRateManager _rateManager;
  final RemoteConfigService _remoteConfigService;
  final AntiDetection _antiDetection;

  NhentaiApiClient({
    Dio? dio,
    required this._rateManager,
    required RemoteConfigService remoteConfigService,
  })  : _dio = dio ??
            _createDefaultDio(
              timeout: remoteConfigService.getConfig('nhentai')?.api?.timeout,
            ),
        _remoteConfigService = remoteConfigService,
        _antiDetection = AntiDetection();

  static Dio _createDefaultDio({int? timeout}) {
    final antiDetection = AntiDetection();
    final dio = Dio(BaseOptions(
      connectTimeout: Duration(milliseconds: timeout ?? ApiConfig.apiTimeout),
      receiveTimeout: Duration(milliseconds: timeout ?? ApiConfig.apiTimeout),
      headers: antiDetection.getRandomHeaders(),
    ));

    // Use NativeAdapter to avoid TLS fingerprinting issues (Cloudflare 403/Connection Reset)
    dio.httpClientAdapter = NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.ephemeralSessionConfiguration(),
    );

    // Add logging interceptor in debug mode
    dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (object) {
        // return Logger().d(object.toString());
        // return;
      },
    ));

    return dio;
  }

  // ============ Dynamic Endpoints ============

  String get _apiBaseUrl => ApiConfig.nhentaiApiBase;

  String _getGalleryEndpoint(String id) => '$_apiBaseUrl/gallery/$id';

  String _getAllGalleriesEndpoint({int page = 1}) =>
      '$_apiBaseUrl/galleries/all?page=$page';

  String _getSearchEndpoint({
    required String query,
    String sort = 'date',
    int page = 1,
  }) {
    final encodedQuery = Uri.encodeComponent(query);
    return '$_apiBaseUrl/galleries/search?query=$encodedQuery&sort=$sort&page=$page';
  }

  String _getRelatedEndpoint(String id) => '$_apiBaseUrl/gallery/$id/related';

  String _getCommentsEndpoint(String id) => '$_apiBaseUrl/gallery/$id/comments';

  Future<void> _waitForRateLimit() async {
    while (!_rateManager.canMakeRequest()) {
      if (_rateManager.isInCooldown) {
        final remaining = _rateManager.remainingCooldown;
        final seconds = remaining?.inSeconds ?? 0;
        throw NhentaiApiException(
          'In cooldown period (${seconds}s remaining)',
          statusCode: 429,
        );
      }

      final delay = _rateManager.calculateDelay();
      if (delay <= Duration.zero) {
        break;
      }
      _logger.d('Rate limiting: waiting ${delay.inMilliseconds}ms');
      await Future.delayed(delay);
    }

    await _antiDetection.applyRandomDelay();
  }

  Future<NhentaiGalleryResponse> getGallery(String id) async {
    final url = _getGalleryEndpoint(id);
    _logger.d('NhentaiApiClient: Fetching gallery $id');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      final gallery = NhentaiGalleryResponse.fromJson(response.data);
      _logger.i('NhentaiApiClient: Successfully fetched gallery $id');
      return gallery;
    } catch (e) {
      _logger.e('NhentaiApiClient: Failed to fetch gallery $id', error: e);
      rethrow;
    }
  }

  Future<NhentaiListResponse> getAllGalleries({int page = 1}) async {
    final url = _getAllGalleriesEndpoint(page: page);
    _logger
        .d('NhentaiApiClient: Fetching all galleries page $page with url $url');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      final listResponse = NhentaiListResponse.fromJson(response.data);
      _logger.i(
          'NhentaiApiClient: Fetched ${listResponse.result.length} galleries from page $page');
      return listResponse;
    } catch (e) {
      _logger.e('NhentaiApiClient: Failed to fetch galleries page $page',
          error: e);
      rethrow;
    }
  }

  Future<NhentaiListResponse> search(
    String query, {
    String sort = 'date',
    int page = 1,
  }) async {
    final mappedSort = ApiConfig.mapSortOption(sort);
    final url = _getSearchEndpoint(
      query: query,
      sort: mappedSort,
      page: page,
    );
    _logger.d(
        'NhentaiApiClient: Searching "$query" (sort: $mappedSort, page: $page)');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      final listResponse = NhentaiListResponse.fromJson(response.data);
      _logger.i(
          'NhentaiApiClient: Search returned ${listResponse.result.length} results');
      return listResponse;
    } catch (e) {
      _logger.e('NhentaiApiClient: Search failed for "$query"', error: e);
      rethrow;
    }
  }

  Future<NhentaiRelatedResponse> getRelated(String id) async {
    final url = _getRelatedEndpoint(id);
    _logger.d('NhentaiApiClient: Fetching related for gallery $id');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      final relatedResponse = NhentaiRelatedResponse.fromJson(response.data);
      _logger.i(
          'NhentaiApiClient: Found ${relatedResponse.result.length} related galleries');
      return relatedResponse;
    } catch (e) {
      _logger.e('NhentaiApiClient: Failed to fetch related for $id', error: e);
      rethrow;
    }
  }

  Future<List<NhentaiComment>> getComments(String id) async {
    final url = _getCommentsEndpoint(id);
    _logger.d('NhentaiApiClient: Fetching comments for gallery $id');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      if (response.data is List) {
        final comments = (response.data as List)
            .map((e) => NhentaiComment.fromJson(e as Map<String, dynamic>))
            .toList();
        _logger.i(
            'NhentaiApiClient: Fetched ${comments.length} comments for gallery $id');
        return comments;
      }
      return [];
    } catch (e) {
      _logger.e('NhentaiApiClient: Failed to fetch comments for $id', error: e);
      rethrow;
    }
  }

  Future<NhentaiListResponse> getPopular({
    String period = 'all',
    int page = 1,
  }) async {
    // Use the all galleries endpoint for popular content
    // nhentai API doesn't support empty query, but all galleries endpoint returns latest
    // For actual popular sorting, we need to use HTML scraping (RemoteDataSource handles this)
    final url = _getAllGalleriesEndpoint(page: page);
    _logger.d(
        'NhentaiApiClient: Fetching popular galleries (period: $period, page: $page)');

    try {
      await _waitForRateLimit();
      final response = await _makeRequest(url);

      final listResponse = NhentaiListResponse.fromJson(response.data);
      _logger.i(
          'NhentaiApiClient: Fetched ${listResponse.result.length} popular galleries');
      return listResponse;
    } catch (e) {
      _logger.e('NhentaiApiClient: Failed to fetch popular galleries',
          error: e);
      rethrow;
    }
  }

  Future<Response> _makeRequest(String url) async {
    int attempts = 0;
    NhentaiApiException? lastException;

    // Get retry config from remote config service
    final retryConfig =
        _remoteConfigService.getConfig('nhentai')?.network?.retry;
    final maxAttempts = retryConfig?.maxAttempts ?? ApiConfig.maxRetryAttempts;
    final baseDelayMs = retryConfig?.delayMs ?? ApiConfig.retryDelayMs;
    final exponentialBackoff = retryConfig?.exponentialBackoff ?? true;

    while (attempts < maxAttempts) {
      attempts++;

      try {
        // Refresh headers to avoid detection
        _dio.options.headers = _antiDetection.getRandomHeaders();

        final response = await _dio.get(url);

        if (response.statusCode == 200 && response.data != null) {
          _rateManager.recordRequest();
          return response;
        }

        throw NhentaiApiException(
          'Unexpected response',
          statusCode: response.statusCode,
        );
      } on DioException catch (e) {
        lastException = _handleDioException(e, url);

        if (!lastException.shouldRetry || attempts >= maxAttempts) {
          throw lastException;
        }

        // Trigger cooldown if rate limited
        if (lastException.isRateLimited) {
          _rateManager.triggerCooldown();
        }

        _logger.w(
            'NhentaiApiClient: Retry attempt $attempts/$maxAttempts for $url');

        // Calculate delay with optional exponential backoff
        final delay = exponentialBackoff ? baseDelayMs * attempts : baseDelayMs;
        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    throw lastException ??
        const NhentaiApiException('Max retry attempts exceeded');
  }

  NhentaiApiException _handleDioException(DioException e, String url) {
    final statusCode = e.response?.statusCode;

    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        NhentaiApiException(
          'Request timeout',
          statusCode: statusCode,
          originalError: e,
        ),
      DioExceptionType.badResponse => NhentaiApiException(
          _getErrorMessage(statusCode),
          statusCode: statusCode,
          originalError: e,
        ),
      DioExceptionType.cancel => NhentaiApiException(
          'Request cancelled',
          statusCode: statusCode,
          originalError: e,
        ),
      _ => NhentaiApiException(
          'Network error: ${e.message}',
          statusCode: statusCode,
          originalError: e,
        ),
    };
  }

  String _getErrorMessage(int? statusCode) {
    return switch (statusCode) {
      400 => 'Bad request',
      403 => 'Access forbidden (possible Cloudflare block)',
      404 => 'Content not found',
      429 => 'Rate limited - please wait',
      500 => 'Server error',
      502 => 'Bad gateway',
      503 => 'Service unavailable',
      _ => 'HTTP error $statusCode',
    };
  }

  Future<bool> checkHealth() async {
    try {
      await _waitForRateLimit();
      final response = await _dio.get(
        _getAllGalleriesEndpoint(page: 1),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      _logger.w('NhentaiApiClient: Health check failed', error: e);
      return false;
    }
  }

  void dispose() {
    _rateManager.dispose();
    _antiDetection.dispose();
  }
}
