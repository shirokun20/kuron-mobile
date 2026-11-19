import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_special/src/hentainexus/hentainexus_decrypt_adapter.dart';
import 'package:logger/logger.dart';

class _TestHentaiNexusDecryptAdapter extends HentaiNexusDecryptAdapter {
  _TestHentaiNexusDecryptAdapter()
      : super(
          dio: Dio(),
          urlBuilder:
              const GenericUrlBuilder(baseUrl: 'https://hentainexus.com'),
          parser: GenericHtmlParser(logger: Logger(level: Level.off)),
          logger: Logger(level: Level.off),
          sourceId: 'hentainexus',
        );

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) async {
    return AdapterDetailResult(
      content: Content(
        id: contentId,
        title: 'stub',
        sourceId: 'hentainexus',
        coverUrl: '',
        tags: const <Tag>[],
        artists: const <String>[],
        characters: const <String>[],
        parodies: const <String>[],
        groups: const <String>[],
        language: 'english',
        pageCount: 2,
        imageUrls: const <String>[
          'https://images.hentainexus.com/1.webp',
          'https://images.hentainexus.com/2.webp',
        ],
        uploadDate: DateTime(2024),
      ),
      imageUrls: const <String>[
        'https://images.hentainexus.com/1.webp',
        'https://images.hentainexus.com/2.webp',
      ],
    );
  }
}

void main() {
  test('fetchChapterImages reuses decrypted detail imageUrls', () async {
    final adapter = _TestHentaiNexusDecryptAdapter();

    final result = await adapter.fetchChapterImages(
      '21724',
      const <String, dynamic>{},
    );

    expect(result, isNotNull);
    expect(result!.images, hasLength(2));
    expect(result.images.first, 'https://images.hentainexus.com/1.webp');
  });
}
