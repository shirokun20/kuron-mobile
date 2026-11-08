import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_core/kuron_core.dart';
import '../webview_session/webview_session_adapter.dart';

// Factory to construct a CF-protected generic source with a fully wired
// WebViewSessionAdapter for Cloudflare bypass and auto-login capabilities.
///
// Designed for multi-source: any Cloudflare-protected provider can use this
// factory by providing its own [WebViewSessionAdapter] instance.
class CrotpediaSourceFactory implements SourceFactory {
  final Dio _dio;
  final WebViewSessionAdapter _sessionAdapter;
  final Logger _logger;

  CrotpediaSourceFactory({
    required this._dio,
    required this._sessionAdapter,
    required this._logger,
  });

  @override
  String get sourceId => 'crotpedia';

  @override
  ContentSource create(Map<String, dynamic> config) {
    // 1. Attach NativeAdapter to handle Cloudflare TLS fingerprinting
    try {
      _dio.httpClientAdapter = NativeAdapter(
        createCupertinoConfiguration: () =>
            URLSessionConfiguration.ephemeralSessionConfiguration(),
      );
    } catch (e) {
      _logger.w('Failed to attach NativeAdapter for Crotpedia: $e');
    }

    // 2. Create intercepting Dio that delegates GET → requestWithBypass
    final interceptingDio = _CrotpediaDioInterceptor(
      baseDio: _dio,
      sessionAdapter: _sessionAdapter,
    );

    // 3. Return the configured GenericHttpSource
    return GenericHttpSource(
      rawConfig: config,
      dio: interceptingDio,
      logger: _logger,
    );
  }
}

// A wrapper around Dio that delegates GET requests to WebViewSessionAdapter's
// `requestWithBypass` method. This allows `GenericScraperAdapter` to
// seamlessly benefit from Cloudflare bypass and Auth without modifying its code.
class _CrotpediaDioInterceptor with DioMixin implements Dio {
  final Dio _baseDio;
  final WebViewSessionAdapter _sessionAdapter;

  _CrotpediaDioInterceptor({
    required Dio baseDio,
    required this._sessionAdapter,
  })  : _baseDio = baseDio {
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
    // We delegate GET to the session adapter to handle 403 bypass
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(path).replace(queryParameters: queryParameters);
      path = uri.toString();
    }

    // Force 4xx to throw so WebViewSessionAdapter can detect Cloudflare 403
    // and trigger native bypass flow. Redirects (3xx) remain non-throwing.
    final passthroughOptions = (options ?? Options()).copyWith(
      validateStatus: (status) => status != null && status < 400,
    );

    // As `requestWithBypass` natively returns `Response<T>`, this works cleanly
    return _sessionAdapter.requestWithBypass<T>(
      path,
      options: passthroughOptions,
    );
  }

  // Delegate other core requests back to baseDio
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
  }) {
    return _baseDio.post<T>(
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
