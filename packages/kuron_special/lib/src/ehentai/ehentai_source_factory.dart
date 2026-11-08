import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import 'ehentai_scraper_adapter.dart';
import 'ehentai_session_adapter.dart';
import '../webview_session/webview_session_adapter.dart';

class EHentaiSourceFactory implements SourceFactory {
  final Dio _dio;
  final PersistCookieJar _cookieJar;
  final Logger _logger;

  EHentaiSourceFactory({
    required this._dio,
    required this._cookieJar,
    required this._logger,
  });

  @override
  String get sourceId => 'ehentai';

  @override
  ContentSource create(Map<String, dynamic> config) {
    final network = config['network'] as Map<String, dynamic>? ?? {};
    final auth = config['auth'] as Map<String, dynamic>? ?? {};

    final baseUrl = (config['baseUrl'] as String?) ?? 'https://e-hentai.org';
    final exBaseUrl =
        (network['exBaseUrl'] as String?) ?? 'https://exhentai.org';
    final useExhentai = auth['preferExhentai'] == true;

    try {
      _dio.httpClientAdapter = NativeAdapter(
        createCupertinoConfiguration: () =>
            URLSessionConfiguration.ephemeralSessionConfiguration(),
      );
    } catch (e) {
      _logger.w('Failed to attach NativeAdapter for E-Hentai: $e');
    }

    final sessionAdapter = EHentaiSessionAdapter(
      dio: _dio,
      cookieJar: _cookieJar,
      config: WebViewSessionConfig.fromJson(config),
      baseUrl: baseUrl,
      primaryBaseUrl: baseUrl,
      exBaseUrl: exBaseUrl,
      useExhentai: useExhentai,
      logger: _logger,
    );

    final bypassDio = _EHentaiDioInterceptor(
      baseDio: _dio,
      sessionAdapter: sessionAdapter,
    );

    final sourceId = config['source'] as String? ?? 'ehentai';
    final urlBuilder = GenericUrlBuilder(baseUrl: baseUrl);
    final htmlParser = GenericHtmlParser(logger: _logger);

    final adapter = EHentaiScraperAdapter(
      dio: bypassDio,
      urlBuilder: urlBuilder,
      parser: htmlParser,
      logger: _logger,
      sourceId: sourceId,
    );

    if (auth['contentWarningBypass'] == true) {
      sessionAdapter.setContentWarningBypass();
    }

    return GenericHttpSource(
      rawConfig: config,
      dio: bypassDio,
      logger: _logger,
      adapterOverride: adapter,
    );
  }
}

class _EHentaiDioInterceptor with DioMixin implements Dio {
  final Dio _baseDio;
  final EHentaiSessionAdapter _sessionAdapter;

  _EHentaiDioInterceptor({
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
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(path).replace(queryParameters: queryParameters);
      path = uri.toString();
    }

    return _sessionAdapter.requestWithBypass<T>(path, options: options);
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
}
