// Plugin seam passthrough (conformance-loop 4.2): with no plugin
// registered, chapter images flow through untouched.
library;

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

class _StubAdapter implements GenericAdapter {
  const _StubAdapter(this.data);

  final ChapterData? data;

  @override
  Duration get detailTimeout => const Duration(seconds: 30);

  @override
  Future<AdapterSearchResult> search(
          SearchFilter filter, Map<String, dynamic> rawConfig) =>
      throw UnimplementedError();

  @override
  Future<AdapterDetailResult> fetchDetail(
          String contentId, Map<String, dynamic> rawConfig) =>
      throw UnimplementedError();

  @override
  Future<List<Content>> fetchRelated(
          String contentId, Map<String, dynamic> rawConfig) =>
      throw UnimplementedError();

  @override
  Future<List<Comment>> fetchComments(
          String contentId, Map<String, dynamic> rawConfig) =>
      throw UnimplementedError();

  @override
  Future<ChapterData?> fetchChapterImages(
          String chapterId, Map<String, dynamic> rawConfig) async =>
      data;

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
}

void main() {
  group('GenericHttpSource plugin seam (4.2)', () {
    test('no plugin registered passes images through untouched', () async {
      SourcePluginRegistry.instance.reset();
      const data = ChapterData(
        images: ['https://cdn.test/1.jpg', 'https://cdn.test/2.jpg'],
        nextChapterId: 'next-1',
      );
      final source = GenericHttpSource(
        rawConfig: const {'source': 'seamtest', 'baseUrl': 'https://t.test'},
        dio: Dio(),
        logger: Logger(level: Level.off),
        adapterOverride: const _StubAdapter(data),
      );

      final out = await source.getChapterImages('ch-1');

      expect(out, isNotNull);
      expect(out!.images, data.images);
      expect(out.nextChapterId, 'next-1');
    });

    test('null adapter data stays null', () async {
      SourcePluginRegistry.instance.reset();
      final source = GenericHttpSource(
        rawConfig: const {'source': 'seamtest', 'baseUrl': 'https://t.test'},
        dio: Dio(),
        logger: Logger(level: Level.off),
        adapterOverride: const _StubAdapter(null),
      );

      expect(await source.getChapterImages('ch-1'), isNull);
    });
  });
}
