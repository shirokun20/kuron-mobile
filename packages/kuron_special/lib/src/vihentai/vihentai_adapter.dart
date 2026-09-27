// ViHentai adapter — handles Livewire auth and packed JS image URL decode.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

import 'vihentai_livewire_auth.dart';
import 'vihentai_packed_js.dart';

class ViHentaiAdapter implements GenericAdapter {
  @override
  Duration get detailTimeout => _delegate.detailTimeout;

  final Dio _dio;
  final GenericScraperAdapter _delegate;
  final Logger _logger;
  final String _sourceId;
  final PersistCookieJar _cookieJar;

  bool _solved = false;

  ViHentaiAdapter({
    required Dio dio,
    required GenericScraperAdapter delegate,
    required Logger logger,
    required String sourceId,
    required PersistCookieJar cookieJar,
  })  : _dio = dio,
        _delegate = delegate,
        _logger = logger,
        _sourceId = sourceId,
        _cookieJar = cookieJar;

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) async {
    await _ensureAuthenticated(rawConfig);
    return _delegate.search(filter, rawConfig);
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    return _delegate.fetchRelated(contentId, rawConfig);
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    return _delegate.fetchComments(contentId, rawConfig);
  }

  @override
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async =>
      const [];

  Future<void> _ensureAuthenticated(Map<String, dynamic> rawConfig) async {
    if (_solved) return;

    final baseUrl = rawConfig['baseUrl'] as String? ?? '';
    final homeUrl = '$baseUrl/danh-sach?sort=-views';

    try {
      final response = await _dio.get<String>(homeUrl);
      final html = response.data ?? '';
      if (!ViHentaiLivewireAuth.needsPassword(html)) {
        _solved = true;
        return;
      }

      _logger.d('$_sourceId: password gate detected, solving...');
      final authData = ViHentaiLivewireAuth.extractAuthData(html);
      final sessionCookie =
          await ViHentaiLivewireAuth.solvePassword(_dio, baseUrl, authData);

      // Save laravel_session to the shared cookie jar so CookieManager on
      // global Dio includes it alongside cf_clearance.
      if (sessionCookie.isNotEmpty) {
        for (final part in sessionCookie.split(';')) {
          final eq = part.indexOf('=');
          if (eq < 0) continue;
          final key = part.substring(0, eq).trim();
          final value = part.substring(eq + 1).trim();
          if (key == 'laravel_session' || key == 'session') {
            await _cookieJar.saveFromResponse(
              Uri.parse(baseUrl),
              [
                Cookie(key, value)
                  ..path = '/'
                  ..domain = '.vi-hentai.moe'
              ],
            );
            _logger.d('$_sourceId: saved $key to shared cookie jar');
          }
        }
      }

      _solved = true;
      _logger.d('$_sourceId: password solved for session');
    } catch (e) {
      _logger.e('$_sourceId: password solve failed on home', error: e);
    }
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    await _ensureAuthenticated(rawConfig);
    return _delegate.fetchDetail(contentId, rawConfig);
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    await _ensureAuthenticated(rawConfig);

    final scraper = rawConfig['scraper'] as Map<String, dynamic>?;
    final urlPatternsCfg =
        (scraper?['urlPatterns'] as Map<String, dynamic>?) ?? {};
    final chapterTemplate = _patternUrl(urlPatternsCfg, 'chapter');
    final baseUrl = rawConfig['baseUrl'] as String? ?? '';

    var normalizedId = chapterId;
    if (normalizedId.startsWith('/')) normalizedId = normalizedId.substring(1);
    if (normalizedId.startsWith('truyen/')) {
      normalizedId = normalizedId.substring('truyen/'.length);
    }
    final slug = normalizedId.contains('/')
        ? normalizedId.split('/').first
        : normalizedId;
    final ch = normalizedId.contains('/')
        ? normalizedId.split('/').last
        : normalizedId;
    var url = chapterTemplate
        .replaceAll('{id}', slug)
        .replaceAll('{contentId}', slug);
    if (url.contains('{ch}')) {
      url = url.replaceAll('{ch}', ch);
    }
    if (!url.startsWith('http')) {
      url = '$baseUrl$url';
    }

    _logger.d('$_sourceId chapter URL: $url');

    try {
      // Use bypass Dio — handles CF via WebViewSessionAdapter. CookieManager
      // on the global Dio reads cf_vihentai jar which now has laravel_session.
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data ?? '';
      final imageUrls = ViHentaiPackedJs.extractImageUrls(html);
      return ChapterData(images: imageUrls);
    } on DioException catch (e) {
      _logger.e('$_sourceId chapter fetch failed for $chapterId', error: e);
      return null;
    }
  }

  static String _patternUrl(Map<String, dynamic> urlPatterns, String key) {
    final val = urlPatterns[key];
    if (val is String) return val;
    if (val is Map) return (val['url'] as String?) ?? '';
    return '';
  }
}
