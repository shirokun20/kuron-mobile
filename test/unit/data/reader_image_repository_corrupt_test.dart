import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import 'package:nhasixapp/data/repositories/reader_image_repository_impl.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';

void main() {
  late Logger logger;

  setUp(() {
    logger = Logger(level: Level.off);
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(logger, dispose: (_) {});
    }
  });

  test('corrupt disk hit is evicted and falls through to redownload',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('rimg_corrupt');
    final corrupt = File('${tmpDir.path}/page_2.jpg');
    await corrupt.writeAsBytes([0, 1, 2, 3]);
    final fresh = File('${tmpDir.path}/fresh_2.jpg');
    await fresh.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 1, 2, 3, 4]);

    final repo = ReaderImageRepositoryImpl(
      logger: logger,
      localLookup: (contentId, pageNumber) async => corrupt.path,
      legacyLookup: (_) async => null,
      networkDownload: ({
        required String url,
        required String contentId,
        required int pageNumber,
        Map<String, String>? headers,
        cancelToken,
      }) async =>
          fresh.path,
    );

    final result = await repo.resolvePage(
      url: 'https://cdn.example/p2.jpg',
      contentId: 'cid',
      pageNumber: 2,
    );

    expect(result, isA<ReadyFresh>());
    expect((result as ReadyFresh).path, fresh.path);
    expect(await corrupt.exists(), isFalse,
        reason: 'corrupt bytes must be deleted, not retried forever');

    await tmpDir.delete(recursive: true);
  });
}
