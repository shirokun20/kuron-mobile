import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';

import 'hentainexus_decryptor.dart';

// HentaiNexus adapter that decrypts reader payload from initReader().
class HentaiNexusDecryptAdapter implements GenericAdapter {
  @override
  Duration get detailTimeout => _delegate.detailTimeout;

  final Dio _dio;
  final GenericScraperAdapter _delegate;
  final Logger _logger;
  final String _sourceId;
  DateTime? _lastRequestAt;

  HentaiNexusDecryptAdapter({
    required Dio dio,
    required GenericUrlBuilder urlBuilder,
    required GenericHtmlParser parser,
    required Logger logger,
    required String sourceId,
  })  : _dio = dio,
        _logger = logger,
        _sourceId = sourceId,
        _delegate = GenericScraperAdapter(
          dio: dio,
          urlBuilder: urlBuilder,
          parser: parser,
          logger: logger,
          sourceId: sourceId,
        );

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
      const <Chapter>[];

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig,
  ) {
    return _delegate.search(filter, rawConfig);
  }

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) async {
    final base = await _delegate.fetchDetail(contentId, rawConfig);

    try {
      final baseUrl = (rawConfig['baseUrl'] as String?) ?? '';
      if (baseUrl.isEmpty) return base;

      final decryption =
          (rawConfig['decryption'] as Map<String, dynamic>?) ?? {};
      final method =
          (decryption['method'] as String?) ?? 'initReader_xor_rc4_variant';
      if (method != 'initReader_xor_rc4_variant') {
        return base;
      }

      final hostname = (decryption['hostname'] as String?) ?? 'hentainexus.com';
      final readerPath = (decryption['readerPath'] as String?) ?? '/read/{id}';
      final encryptedPattern =
          (decryption['encryptedDataPattern'] as String?) ??
              r'initReader\(\s*"([^"]+)"';

      final readerUrl = '$baseUrl${readerPath.replaceAll('{id}', contentId)}';
      await _throttle(rawConfig);
      final response = await _dio.get<String>(
        readerUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data ?? '';
      if (html.isEmpty) {
        _logger.w('[$_sourceId] reader HTML empty for $readerUrl');
        return base;
      }

      final encrypted = RegExp(encryptedPattern).firstMatch(html)?.group(1);
      List<String> imageUrls = const <String>[];

      if (encrypted == null || encrypted.isEmpty) {
        _logger.w(
          '[$_sourceId] initReader payload missing for $contentId, trying HTML image fallback',
        );
      } else {
        try {
          final decrypted = HentaiNexusDecryptor.decrypt(
            encrypted: encrypted,
            hostname: hostname,
          );
          imageUrls = HentaiNexusDecryptor.extractImageUrls(decrypted);
          if (imageUrls.isNotEmpty) {
            _logger.i(
              '[$_sourceId] extracted ${imageUrls.length} reader images from decrypted payload for $contentId',
            );
          }
        } catch (e) {
          _logger.w('[$_sourceId] decrypt failed for $contentId: $e');
        }
      }

      if (imageUrls.isEmpty) {
        imageUrls = HentaiNexusDecryptor.extractImageUrlsFromHtml(html);
        if (imageUrls.isNotEmpty) {
          _logger.i(
            '[$_sourceId] extracted ${imageUrls.length} reader images from HTML fallback for $contentId',
          );
        }
      }

      if (imageUrls.isEmpty) {
        _logger.w('[$_sourceId] no reader images resolved for $contentId');
        return base;
      }

      final updated = base.content.copyWith(
        imageUrls: imageUrls,
        pageCount: imageUrls.length,
      );

      return AdapterDetailResult(content: updated, imageUrls: imageUrls);
    } catch (e) {
      _logger.w('[$_sourceId] reader extraction failed for $contentId: $e');
      return base;
    }
  }

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) {
    return _delegate.fetchRelated(contentId, rawConfig);
  }

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig,
  ) {
    return _delegate.fetchComments(contentId, rawConfig);
  }

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig,
  ) async {
    final detail = await fetchDetail(chapterId, rawConfig);
    if (detail.imageUrls.isEmpty) {
      return null;
    }

    return ChapterData(images: detail.imageUrls);
  }

  Future<void> _throttle(Map<String, dynamic> rawConfig) async {
    final network = (rawConfig['network'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rateLimit = (network['rateLimit'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final requestsPerSecond =
        (rateLimit['requestsPerSecond'] as num?)?.toDouble() ?? 0;

    if (requestsPerSecond <= 0) {
      return;
    }

    final minIntervalMs = (1000 / requestsPerSecond).ceil();
    final now = DateTime.now();

    if (_lastRequestAt != null) {
      final elapsed = now.difference(_lastRequestAt!).inMilliseconds;
      final waitMs = minIntervalMs - elapsed;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }

    _lastRequestAt = DateTime.now();
  }
}
