import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/services/local_image_preloader.dart';
import 'package:nhasixapp/core/utils/download_storage_utils.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

/// Regression: chapter ids with a leading slash (Komikcast raw hrefs like
/// `/series/<slug>/<ch>`) must not escape the app dir. `package:path` drops
/// every segment before an absolute one, so the old raw join produced
/// `/series/.../images` and `create(recursive: true)` died with
/// `FileSystemException: Creation failed, path = '/series'` (errno 30).
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);
  final List<int> bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(bytes, 200, headers: {
        Headers.contentLengthHeader: [bytes.length.toString()],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safe_seg');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getExternalStorageDirectory') {
        return tempDir.path;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    }
    if (GetIt.I.isRegistered<Dio>()) GetIt.I.unregister<Dio>();
    GetIt.I.registerSingleton<Dio>(
      Dio()..httpClientAdapter = _BytesAdapter([0xFF, 0xD8, 0xFF, 0xD9]),
    );
    LocalImagePreloader.resetLookupCacheForTest();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (GetIt.I.isRegistered<Dio>()) GetIt.I.unregister<Dio>();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('safePathSegment', () {
    test('strips leading slash and flattens inner slashes', () {
      expect(DownloadStorageUtils.safePathSegment('/series/slug/ch-68'),
          'series__slug__ch-68');
    });

    test('clean ids are identity (existing libraries untouched)', () {
      expect(DownloadStorageUtils.safePathSegment('700700'), '700700');
      expect(DownloadStorageUtils.safePathSegment('my_manga.v2-1'),
          'my_manga.v2-1');
    });

    test('rejects empty and dot segments', () {
      expect(() => DownloadStorageUtils.safePathSegment('/'),
          throwsArgumentError);
      expect(
          () => DownloadStorageUtils.safePathSegment(''), throwsArgumentError);
      expect(() => DownloadStorageUtils.safePathSegment('..'),
          throwsArgumentError);
    });
  });

  group('getImagesFolderPath', () {
    test('leading-slash id stays under the app dir', () async {
      final p = await LocalImagePreloader.getImagesFolderPath(
          '/series/slug/ch-68');
      expect(p.startsWith(tempDir.path), isTrue);
      expect(p.contains('/series/'), isFalse);
      expect(p.endsWith('series__slug__ch-68/images'), isTrue);
    });
  });

  group('downloadAndCacheImageStreaming', () {
    test('leading-slash contentId caches a real file under app dir',
        () async {
      final out =
          await LocalImagePreloader.downloadAndCacheImageStreaming(
        'https://cdn.voratoon.com/x/0.jpg',
        '/series/slug/ch-68',
        1,
      );
      expect(out, isNotNull);
      expect(out!.startsWith(tempDir.path), isTrue,
          reason: 'must not escape to /series/...');
      expect(await File(out).exists(), isTrue);
    });

    test('documents the pre-fix escape shape (guard)', () {
      // This is what the old raw join produced: absolute segment wins.
      final escaped = path.join(tempDir.path, 'nhasix', '/series/x', 'images');
      expect(escaped.startsWith(tempDir.path), isFalse);
    });
  });
}
