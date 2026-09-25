import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../webview_session/webview_session_adapter.dart';

// Reusable factory for any source that needs Cloudflare bypass via
// [WebViewSessionAdapter]. Wraps Dio with an interceptor that delegates
// GET requests through `requestWithBypass`.
///
// Register one instance per source ID, passing a pre-configured
// [WebViewSessionAdapter] with isolated cookie storage.
class GenericBypassSourceFactory implements SourceFactory {
  final String _sourceId;
  final Dio _dio;
  final WebViewSessionAdapter _sessionAdapter;
  final Logger _logger;

  GenericBypassSourceFactory({
    required String sourceId,
    required Dio dio,
    required WebViewSessionAdapter sessionAdapter,
    required Logger logger,
  })  : _sourceId = sourceId,
        _dio = dio,
        _sessionAdapter = sessionAdapter,
        _logger = logger;

  @override
  String get sourceId => _sourceId;

  @override
  ContentSource create(Map<String, dynamic> config) {
    // NativeAdapter improves TLS fingerprint to avoid CF detection
    try {
      _dio.httpClientAdapter = NativeAdapter(
        createCupertinoConfiguration: () =>
            URLSessionConfiguration.ephemeralSessionConfiguration(),
      );
    } catch (e) {
      _logger.w('$_sourceId: Failed to attach NativeAdapter: $e');
    }

    final interceptingDio = _BypassDioInterceptor(
      baseDio: _dio,
      sessionAdapter: _sessionAdapter,
      logger: _logger,
    );

    return GenericHttpSource(
      rawConfig: config,
      dio: interceptingDio,
      logger: _logger,
      bypassCookieProvider: WebViewSessionAdapter.getCachedCookieHeaderForUrl,
      bypassUaProvider: WebViewSessionAdapter.getCachedUserAgentForUrl,
    );
  }
}

// Dio wrapper that routes GET through [WebViewSessionAdapter.requestWithBypass]
// so Cloudflare 403 triggers native WebView bypass.
class _BypassDioInterceptor with DioMixin implements Dio {
  final Dio _baseDio;
  final WebViewSessionAdapter _sessionAdapter;
  final Logger _logger;

  _BypassDioInterceptor({
    required Dio baseDio,
    required WebViewSessionAdapter sessionAdapter,
    required Logger logger,
  })  : _baseDio = baseDio,
        _sessionAdapter = sessionAdapter,
        _logger = logger {
    options = baseDio.options;
    interceptors.addAll(baseDio.interceptors);
    httpClientAdapter = baseDio.httpClientAdapter;
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(path).replace(queryParameters: queryParameters);
      path = uri.toString();
    }

    // Force 4xx to throw so WebViewSessionAdapter can detect CF 403
    // Redirects (3xx) remain non-throwing.
    final passthroughOptions = (options ?? Options()).copyWith(
      validateStatus: (status) => status != null && status < 400,
    );

    return _sessionAdapter.requestWithBypass<T>(
      path,
      options: passthroughOptions,
    );
  }

  @override
  Future<Response<T>> request<T>(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _baseDio.request<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: options,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    // cf_clearance is UA-bound and the site challenges every endpoint —
    // inject the cached clearance + matching UA BEFORE the first attempt so a
    // valid session never trips the challenge (and never voids the clearance
    // by sending it under a mismatched UA).
    var effectiveOptions = options;
    final bypassCookie =
        WebViewSessionAdapter.getCachedCookieHeaderForUrl(path);
    final bypassUa = WebViewSessionAdapter.getCachedUserAgentForUrl(path);
    if ((bypassCookie?.isNotEmpty ?? false) ||
        (bypassUa?.isNotEmpty ?? false)) {
      final preHeaders = Map<String, dynamic>.from(options?.headers ?? {});
      if ((bypassCookie?.isNotEmpty ?? false) &&
          !(preHeaders['Cookie']?.toString().contains('cf_clearance') ??
              false)) {
        preHeaders['Cookie'] = bypassCookie;
      }
      if (bypassUa?.isNotEmpty ?? false) {
        preHeaders['User-Agent'] = bypassUa;
      }
      effectiveOptions = (options ?? Options()).copyWith(headers: preHeaders);
    }

    try {
      return await _baseDio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: effectiveOptions,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode != 403) rethrow;
      _logger.w('POST 403, triggering WebView bypass for $path');
      // Refresh cf_clearance for the base domain via GET, then retry POST
      await _sessionAdapter.requestWithBypass<dynamic>(
        _sessionAdapter.baseUrl,
        options: Options(headers: options?.headers),
      );
      final freshCookie =
          WebViewSessionAdapter.getCachedCookieHeaderForUrl(path);
      final freshUa = WebViewSessionAdapter.getCachedUserAgentForUrl(path);
      final retryHeaders = Map<String, dynamic>.from(options?.headers ?? {});
      if (freshCookie != null && freshCookie.isNotEmpty) {
        retryHeaders['Cookie'] = freshCookie;
      }
      if (freshUa != null && freshUa.isNotEmpty) {
        retryHeaders['User-Agent'] = freshUa;
      }
      final retryOptions =
          (options ?? Options()).copyWith(headers: retryHeaders);
      // Retry POST with fresh cookies/UA after bypass
      return await _baseDio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: retryOptions,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    }
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _baseDio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  @override
  Future<Response<T>> head<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _baseDio.head<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _baseDio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) {
    return _baseDio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
