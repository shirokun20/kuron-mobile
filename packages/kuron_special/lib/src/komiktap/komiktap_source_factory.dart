import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../webview_session/webview_session_adapter.dart';

Map<String, dynamic> _withKomiktapBypassDefaults(Map<String, dynamic> config) {
  final patched = Map<String, dynamic>.from(config);
  final network = Map<String, dynamic>.from(
    (patched['network'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
  final siteProtection = Map<String, dynamic>.from(
    (network['siteProtection'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  network['requiresBypass'] = true;
  siteProtection.putIfAbsent('autoCloseOnCookie', () => 'sucuri_cloudproxy_');
  network['siteProtection'] = siteProtection;
  patched['network'] = network;

  return patched;
}

// Factory for KomikTap that routes GET requests through
// [WebViewSessionAdapter] so WAF challenges can trigger native bypass flow.
class KomiktapSourceFactory implements SourceFactory {
  KomiktapSourceFactory({
    required this._dio,
    required this._sessionAdapter,
    required this._logger,
  });

  final Dio _dio;
  final WebViewSessionAdapter _sessionAdapter;
  final Logger _logger;

  @override
  String get sourceId => 'komiktap';

  @override
  ContentSource create(Map<String, dynamic> config) {
    try {
      _dio.httpClientAdapter = NativeAdapter(
        createCupertinoConfiguration: () =>
            URLSessionConfiguration.ephemeralSessionConfiguration(),
      );
    } catch (e) {
      _logger.w('Failed to attach NativeAdapter for KomikTap: $e');
    }

    final interceptingDio = _KomiktapDioInterceptor(
      baseDio: _dio,
      sessionAdapter: _sessionAdapter,
    );

    return GenericHttpSource(
      rawConfig: _withKomiktapBypassDefaults(config),
      dio: interceptingDio,
      logger: _logger,
    );
  }
}

class _KomiktapDioInterceptor with DioMixin implements Dio {
  _KomiktapDioInterceptor({
    required Dio baseDio,
    required this._sessionAdapter,
  })  : _baseDio = baseDio {
    options = baseDio.options;
    interceptors.addAll(baseDio.interceptors);
    httpClientAdapter = baseDio.httpClientAdapter;
  }

  final Dio _baseDio;
  final WebViewSessionAdapter _sessionAdapter;

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
