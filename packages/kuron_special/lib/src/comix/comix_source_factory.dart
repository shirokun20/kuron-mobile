import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../webview_proxy/webview_proxy_engine.dart';
import 'comix_adapter.dart';
import 'comix_descrambler.dart';
import 'comix_network.dart';

// Factory wiring for comix-family sources (comix.to + mangafire.to).
//
// Each source gets an isolated [WebViewProxyEngine] (per-origin cipher
// cache) and a Dio stack mirroring keiyoushi `configureClient`:
// retry/fallbacks -> descrambler -> image Origin policy.

Dio _buildComixDio({
  required Dio base,
  required String baseUrlHost,
  required Logger logger,
}) {
  final dio = Dio(base.options.copyWith());
  dio.httpClientAdapter = base.httpClientAdapter;
  dio.interceptors.addAll(base.interceptors);
  dio.interceptors.add(ComixRetryInterceptor(dio));
  dio.interceptors.add(ComixDescramblerInterceptor(logger: logger));
  dio.interceptors.add(
    ComixImageHeaderInterceptor(baseUrlHost: baseUrlHost),
  );
  try {
    dio.httpClientAdapter = NativeAdapter(
      createCupertinoConfiguration: () =>
          URLSessionConfiguration.ephemeralSessionConfiguration(),
    );
  } catch (e) {
    logger.w('comix: Failed to attach NativeAdapter: $e');
  }
  return dio;
}

class ComixSourceFactory implements SourceFactory {
  ComixSourceFactory({
    required Dio dio,
    required WebViewProxyEngine engine,
    required Logger logger,
  })  : _dio = dio,
        _engine = engine,
        _logger = logger;

  final Dio _dio;
  final WebViewProxyEngine _engine;
  final Logger _logger;

  @override
  String get sourceId => 'comix';

  @override
  ContentSource create(Map<String, dynamic> config) {
    final baseUrl = (config['baseUrl'] as String?) ?? 'https://comix.to';
    final host = Uri.tryParse(baseUrl)?.host ?? 'comix.to';
    final dio = _buildComixDio(
      base: _dio,
      baseUrlHost: host,
      logger: _logger,
    );
    return GenericHttpSource(
      rawConfig: config,
      dio: dio,
      logger: _logger,
      adapterOverride: ComixAdapter(
        dio: dio,
        engine: _engine,
        logger: _logger,
      ),
    );
  }
}

/// MangaFire reactivation (Phase 5): sister platform of Comix sharing the
/// URL scheme (`/title/{slug}`) and community-upload model, so the same
/// WebView proxy + cipher + 3-tier pattern applies with an isolated engine.
class MangafireSourceFactory implements SourceFactory {
  MangafireSourceFactory({
    required Dio dio,
    required WebViewProxyEngine engine,
    required Logger logger,
  })  : _dio = dio,
        _engine = engine,
        _logger = logger;

  final Dio _dio;
  final WebViewProxyEngine _engine;
  final Logger _logger;

  @override
  String get sourceId => 'mangafire';

  @override
  ContentSource create(Map<String, dynamic> config) {
    final baseUrl = (config['baseUrl'] as String?) ?? 'https://mangafire.to';
    final host = Uri.tryParse(baseUrl)?.host ?? 'mangafire.to';
    final dio = _buildComixDio(
      base: _dio,
      baseUrlHost: host,
      logger: _logger,
    );
    return GenericHttpSource(
      rawConfig: {'baseUrl': baseUrl, ...config},
      dio: dio,
      logger: _logger,
      adapterOverride: ComixAdapter(
        dio: dio,
        engine: _engine,
        logger: _logger,
        defaultBaseUrl: baseUrl,
        defaultSourceId: 'mangafire',
        originKind: 'mangafire',
      ),
    );
  }
}
