import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import 'package:nhasixapp/data/repositories/reader_image_repository_impl.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';

void main() {
  late Logger logger;

  setUp(() {
    logger = Logger(level: Level.off);
    // RequestDeduplicationService resolves a Logger from GetIt at construction.
    // Register once (guard against duplicate-type registration) without
    // resetting, so other tests sharing GetIt are not disrupted.
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(logger, dispose: (_) {});
    }
  });

  ReaderImageRepositoryImpl buildRepo({
    required Future<String?> Function(
            String url, String contentId, int pageNumber)
        download,
    Future<String?> Function(String url)? legacy,
  }) {
    return ReaderImageRepositoryImpl(
      logger: logger,
      legacyLookup: legacy ?? (_) async => null,
      networkDownload: ({
        required String url,
        required String contentId,
        required int pageNumber,
        Map<String, String>? headers,
        CancelToken? cancelToken,
      }) {
        return download(url, contentId, pageNumber);
      },
    );
  }

  test('local file-path URL resolves to ReadyFromDisk without network',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('rimg');
    final file = File('${tmpDir.path}/page_1.jpg');
    await file.writeAsBytes([1, 2, 3]);

    var networkCalls = 0;
    final repo = buildRepo(
      download: (url, cid, page) {
        networkCalls++;
        return Future.value(null);
      },
    );

    final result = await repo.resolvePage(
      url: file.path,
      contentId: 'cid',
      pageNumber: 1,
    );

    expect(result, isA<ReadyFromDisk>());
    expect((result as ReadyFromDisk).path, file.path);
    expect(networkCalls, 0, reason: 'local path must not trigger network');

    await tmpDir.delete(recursive: true);
  });

  test('legacy cache hit returns ReadyFromDisk and does not redownload',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('rimg_legacy');
    final legacyFile = File('${tmpDir.path}/legacy.jpg');
    await legacyFile.writeAsBytes([9, 9, 9]);

    var networkCalls = 0;
    final repo = buildRepo(
      legacy: (_) async => legacyFile.path,
      download: (url, cid, page) {
        networkCalls++;
        return Future.value(null);
      },
    );

    final result = await repo.resolvePage(
      url: 'https://cdn.example/p1.jpg',
      contentId: 'cid',
      pageNumber: 1,
    );

    expect(result, isA<ReadyFromDisk>());
    expect((result as ReadyFromDisk).legacy, isTrue,
        reason: 'a legacy cache hit should be flagged as legacy migration');
    expect(networkCalls, 0, reason: 'legacy hit must not redownload');

    await tmpDir.delete(recursive: true);
  });

  test('successful network download resolves to ReadyFresh', () async {
    final tmpDir = await Directory.systemTemp.createTemp('rimg_fresh');
    final downloaded = File('${tmpDir.path}/fresh.jpg');
    await downloaded.writeAsBytes([1, 2, 3, 4]);

    final repo = buildRepo(
      download: (url, cid, page) async => downloaded.path,
    );

    final result = await repo.resolvePage(
      url: 'https://cdn.example/p2.jpg',
      contentId: 'cid',
      pageNumber: 2,
    );

    expect(result, isA<ReadyFresh>());
    expect((result as ReadyFresh).path, downloaded.path);

    await tmpDir.delete(recursive: true);
  });

  test('network download returning no file resolves to FailedPage', () {
    final repo = buildRepo(
      download: (url, cid, page) async => null,
    );

    return repo
        .resolvePage(
            url: 'https://cdn.example/p3.jpg', contentId: 'cid', pageNumber: 3)
        .then((result) {
      expect(result, isA<FailedPage>());
      expect((result as FailedPage).originalUrl, 'https://cdn.example/p3.jpg');
    });
  });

  test('network download throwing resolves to FailedPage with reason', () {
    final repo = buildRepo(
      download: (url, cid, page) => throw Exception('HTTP 403'),
    );

    return repo
        .resolvePage(
            url: 'https://cdn.example/p4.jpg', contentId: 'cid', pageNumber: 4)
        .then((result) {
      expect(result, isA<FailedPage>());
      expect((result as FailedPage).reason.toString(), contains('403'));
    });
  });

  test('concurrent resolves for same URL trigger only one network download',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('rimg_dedup');
    final downloaded = File('${tmpDir.path}/dedup.jpg');
    await downloaded.writeAsBytes([7, 7, 7]);

    var downloadCalls = 0;
    final repo = buildRepo(
      download: (url, cid, page) async {
        downloadCalls++;
        // Simulate an in-flight window that overlaps the two callers.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return downloaded.path;
      },
    );

    final results = await Future.wait([
      repo.resolvePage(
          url: 'https://cdn.example/p5.jpg', contentId: 'c', pageNumber: 5),
      repo.resolvePage(
          url: 'https://cdn.example/p5.jpg', contentId: 'c', pageNumber: 5),
    ]);

    expect(downloadCalls, 1, reason: 'same URL in-flight must be deduplicated');
    expect(results.every((r) => r is ReadyFresh), isTrue);

    await tmpDir.delete(recursive: true);
  });
}
