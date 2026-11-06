// ViHentai source factory — creates [GenericHttpSource] with ViHentaiAdapter.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../generic_bypass/generic_bypass_source_factory.dart';
import '../webview_session/webview_session_adapter.dart';
import 'vihentai_adapter.dart';

class ViHentaiSourceFactory implements SourceFactory {
  final Dio _dio;
  final WebViewSessionAdapter _sessionAdapter;
  final Logger _logger;
  final PersistCookieJar _cookieJar;

  ViHentaiSourceFactory({
    required Dio dio,
    required WebViewSessionAdapter sessionAdapter,
    required Logger logger,
    required PersistCookieJar cookieJar,
  })  : _dio = dio,
        _sessionAdapter = sessionAdapter,
        _logger = logger,
        _cookieJar = cookieJar;

  @override
  String get sourceId => 'vihentai';

  @override
  ContentSource create(Map<String, dynamic> config) {
    // Per-source Dio with CookieManager sharing cf_vihentai jar with
    // WebViewSessionAdapter. Both cookies (cf_clearance from bypass,
    // laravel_session from solve) go to the same jar.
    final vihentaiDio = Dio(_dio.options.copyWith());
    try {
      vihentaiDio.httpClientAdapter = NativeAdapter(
        createCupertinoConfiguration: () =>
            URLSessionConfiguration.ephemeralSessionConfiguration(),
      );
    } catch (e) {
      _logger.w('vihentai: Failed to attach NativeAdapter: $e');
    }

    // Use the SAME PersistCookieJar instance as WebViewSessionAdapter.
    // One jar, one memory cache — CF clearance + laravel_session coexist.
    vihentaiDio.interceptors.add(CookieManager(_cookieJar));

    // Copy global interceptors (logging, etc.)
    for (final interceptor in _dio.interceptors) {
      try {
        vihentaiDio.interceptors.add(interceptor);
      } catch (_) {}
    }

    // Bypass interceptor — shared master (POST gains 403-retry; previously
    // plain passthrough). Session cookie forwarding preserved via flag.
    final bypassDio = BypassDioInterceptor(
      baseDio: vihentaiDio,
      sessionAdapter: _sessionAdapter,
      logger: _logger,
      forwardSessionCookie: true,
    );

    final urlBuilder = GenericUrlBuilder(
      baseUrl: config['baseUrl'] as String? ?? '',
    );
    final parser = GenericHtmlParser(logger: _logger);
    final scraperAdapter = GenericScraperAdapter(
      dio: bypassDio,
      urlBuilder: urlBuilder,
      parser: parser,
      logger: _logger,
      sourceId: 'vihentai',
    );

    final vihentaiAdapter = ViHentaiAdapter(
      dio: bypassDio,
      delegate: scraperAdapter,
      logger: _logger,
      sourceId: 'vihentai',
      cookieJar: _cookieJar,
    );

    return GenericHttpSource(
      rawConfig: config,
      dio: bypassDio,
      logger: _logger,
      adapterOverride: vihentaiAdapter,
    );
  }
}
