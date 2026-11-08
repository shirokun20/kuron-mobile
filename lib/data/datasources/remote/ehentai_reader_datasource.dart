import 'dart:async';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/reader_image_repair_utils.dart';
import 'package:nhasixapp/core/utils/capped_map.dart';

/// Remote datasource responsible for resolving E-Hentai reader page HTML into direct image URLs.
/// Encapsulates Dio network fetching, HTML token scraping, and timestamped in-memory caching.
class EhentaiReaderDataSource {
  EhentaiReaderDataSource({
    Dio? dio,
    Logger? logger,
    this._cacheTtl = const Duration(minutes: 2),
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                responseType: ResponseType.plain,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 15),
              ),
            ),
        _logger = logger ?? (getIt.isRegistered<Logger>() ? getIt<Logger>() : Logger());

  final Dio _dio;
  final Logger _logger;
  final Duration _cacheTtl;

  final Map<String, String> _imageCache = CappedMap<String, String>(200);
  final Map<String, DateTime> _imageCacheTime = CappedMap<String, DateTime>(200);
  final Map<String, Future<String?>> _resolveInFlight =
      CappedMap<String, Future<String?>>(200);

  bool shouldResolve(String url, {String? sourceId}) {
    if (sourceId != 'ehentai') {
      return false;
    }

    final lowered = url.toLowerCase();
    if (lowered.startsWith('/s/') || lowered.startsWith('/fullimg/')) {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (!(host.contains('e-hentai.org') || host.contains('exhentai.org'))) {
      return false;
    }

    final loweredPath = uri.path.toLowerCase();
    if (loweredPath.contains('/s/') || loweredPath.contains('/fullimg/')) {
      return true;
    }

    return !_looksLikeDirectImagePath(loweredPath);
  }

  bool _looksLikeDirectImagePath(String path) {
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.avif');
  }

  Future<String?> resolveImageUrl(
    String readerPageUrl, {
    Map<String, String>? headers,
    Map<String, dynamic>? rawConfig,
  }) async {
    final cached = _imageCache[readerPageUrl];
    final cachedAt = _imageCacheTime[readerPageUrl];
    if (cached != null && cached.isNotEmpty && cachedAt != null) {
      final age = DateTime.now().difference(cachedAt);
      if (age <= _cacheTtl) {
        return cached;
      }
      invalidate(readerPageUrl);
    }

    final inFlight = _resolveInFlight[readerPageUrl];
    if (inFlight != null) {
      return inFlight;
    }

    final resolver = _resolveImageUrlInternal(
      readerPageUrl,
      headers: headers,
      rawConfig: rawConfig,
    );
    _resolveInFlight[readerPageUrl] = resolver;
    try {
      return await resolver;
    } finally {
      _resolveInFlight.remove(readerPageUrl);
    }
  }

  Future<String?> _resolveImageUrlInternal(
    String readerPageUrl, {
    Map<String, String>? headers,
    Map<String, dynamic>? rawConfig,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        readerPageUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: true,
          validateStatus: (status) => (status ?? 0) < 400,
        ),
      );

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) {
        return null;
      }

      final imageUrl = extractEhentaiImageUrlFromHtml(
        html,
        readerPageUrl,
        rawConfig: rawConfig,
      );
      if (imageUrl != null && imageUrl.isNotEmpty) {
        _imageCache[readerPageUrl] = imageUrl;
        _imageCacheTime[readerPageUrl] = DateTime.now();
      }
      return imageUrl;
    } catch (e) {
      _logger.w('[EhentaiDataSource] Failed resolving $readerPageUrl: $e');
      return null;
    }
  }

  void invalidate(String readerPageUrl) {
    _imageCache.remove(readerPageUrl);
    _imageCacheTime.remove(readerPageUrl);
    _resolveInFlight.remove(readerPageUrl);
  }

  void clearCache() {
    _imageCache.clear();
    _imageCacheTime.clear();
    _resolveInFlight.clear();
  }
}
