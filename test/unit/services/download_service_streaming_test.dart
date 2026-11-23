import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/constants/app_constants.dart' as app_constants;
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/download_service.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:path/path.dart' as p;

// Regression tests for Fase 1 of `background-work-organization`:
// `_downloadSingleImage` streams to a `.part` file and publishes atomically,
// `downloadContent` keeps at most 3 HTTP requests in flight, and cancel
// aborts the batch instead of being swallowed into `continue`.
//
// A temp directory is used as `savePath` so no platform channel (MediaStore /
// path_provider) is needed. Network is simulated by a HttpClientAdapter that
// returns a byte stream, which is what Dio's download transformer writes.

const _kSourceId = 'stream-test-source';

const Map<String, String> _kSourceHeaders = {
  'Referer': 'https://example.com/',
  'User-Agent': 'Kuron-Streaming-Test-UA',
  'Cookie': 'session=abc123; token=xyz',
};

class _MockNotificationService extends Mock implements NotificationService {}

class _FakeSource extends ContentSource {
  _FakeSource(this.headers);

  final Map<String, String> headers;

  @override
  String get id => _kSourceId;
  @override
  String get displayName => _kSourceId;
  @override
  String get iconPath => '';
  @override
  String get baseUrl => 'https://example.com';
  @override
  bool get requiresBypass => false;
  @override
  SearchCapabilities get searchCapabilities =>
      SearchCapabilities.defaultCapabilities;

  @override
  Future<ContentListResult> search(
    SearchFilter filter, {
    OnCancelRegister? onCancel,
  }) =>
      throw UnimplementedError();
  @override
  Future<Content> getDetail(
    String contentId, {
    OnCancelRegister? onCancel,
  }) =>
      throw UnimplementedError();
  @override
  Future<ContentListResult> getList({
    int page = 1,
    SortOption sort = SortOption.newest,
    OnCancelRegister? onCancel,
  }) =>
      throw UnimplementedError();
  @override
  Future<ContentListResult> getPopular({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
    OnCancelRegister? onCancel,
  }) =>
      throw UnimplementedError();
  @override
  Future<List<Content>> getRandom({int count = 1}) =>
      throw UnimplementedError();
  @override
  Future<List<Content>> getRelated(
    String contentId, {
    OnCancelRegister? onCancel,
  }) =>
      throw UnimplementedError();
  @override
  String buildImageUrl({
    required String contentId,
    required String mediaId,
    required int page,
    required String extension,
    bool thumbnail = false,
  }) => throw UnimplementedError();
  @override
  String buildThumbnailUrl({
    required String contentId,
    required String mediaId,
  }) => throw UnimplementedError();
  @override
  String? parseContentIdFromUrl(String url) => null;
  @override
  bool isValidContentId(String contentId) => true;
  @override
  String get refererHeader => headers['Referer'] ?? '';
  @override
  Map<String, String> getImageDownloadHeaders({
    required String imageUrl,
    Map<String, String>? cookies,
  }) => headers;
}

typedef _FetchHandler = Future<ResponseBody> Function(
  RequestOptions options,
  Future<void>? cancelFuture,
);

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.handler);

  final _FetchHandler handler;
  final List<RequestOptions> seenRequests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    seenRequests.add(options);
    return handler(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _byteResponse(
  Uint8List bytes, {
  Map<String, List<String>> extraHeaders = const <String, List<String>>{},
}) {
  return ResponseBody(
    Stream<Uint8List>.value(bytes),
    HttpStatus.ok,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/octet-stream'],
      Headers.contentLengthHeader: <String>['${bytes.length}'],
      ...extraHeaders,
    },
  );
}

/// Observes the real `.part` temp filename while the download is in flight.
/// `RequestOptions.path` cannot be used for this: Dio keeps the *URL* there,
/// not the download destination.
Stream<Uint8List> _observedPartStream(
  Uint8List bytes, {
  required List<String> Function() collectParts,
  required Completer<void> observed,
  required Future<void> gate,
}) async* {
  // Dio's response-stream wrapper subscribes here, *before* `download`
  // creates the `.part` file, so wait a few event-loop turns for it to appear.
  for (var i = 0; i < 50 && collectParts().isEmpty; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  if (!observed.isCompleted) observed.complete();
  yield bytes;
  // Keep the file in its `.part` state until the test has observed it.
  await gate;
}

/// Emits a partial chunk (so the `.part` file really exists on disk) then
/// holds the stream open until cancellation. Deliberately does not throw:
/// Dio's own `whenCancel` handler raises the cancel error on the wrapped
/// response stream, and throwing here would race with its subscription
/// cancellation and surface as an unhandled async error in the test zone.
Stream<Uint8List> _cancelAwareStream(
  Uint8List bytes,
  Future<void>? cancelFuture,
) async* {
  yield bytes;
  await (cancelFuture ?? Completer<void>().future);
}

final class _Harness {
  late final Directory tempDir;
  late final Dio dio;
  late final _StreamAdapter adapter;
  late final ContentSourceRegistry registry;
  late final _MockNotificationService notifications;
  late final DownloadService service;
  final List<DownloadProgress> progress = <DownloadProgress>[];

  Future<void> init({
    required _FetchHandler handler,
    Map<String, String>? sourceHeaders,
  }) async {
    tempDir = await Directory.systemTemp.createTemp('kuron_dl_stream_');
    adapter = _StreamAdapter(handler);
    dio = Dio(BaseOptions(baseUrl: 'http://mock'))..httpClientAdapter = adapter;
    registry = ContentSourceRegistry()
      ..register(_FakeSource(sourceHeaders ?? _kSourceHeaders));

    notifications = _MockNotificationService();
    when(
      () => notifications.showDownloadStarted(
        contentId: any(named: 'contentId'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => notifications.showDownloadError(
        contentId: any(named: 'contentId'),
        title: any(named: 'title'),
        error: any(named: 'error'),
      ),
    ).thenAnswer((_) async {});

    service = DownloadService(
      httpClient: dio,
      notificationService: notifications,
      sourceRegistry: registry,
      logger: Logger(level: Level.off),
    );
  }

  Directory get imagesDir =>
      Directory(p.join(tempDir.path, app_constants.AppStorage.imagesSubfolder));

  List<String> get partFiles => imagesDir
      .listSync()
      .where((entity) => entity.path.endsWith('.part'))
      .map((entity) => entity.path)
      .toList();

  String pagePath(int page) =>
      p.join(imagesDir.path, 'page_${page.toString().padLeft(3, '0')}.jpg');

  Content content(int pages) => Content(
    id: 'stream-content',
    sourceId: _kSourceId,
    title: 'Streaming test',
    coverUrl: 'https://example.com/cover.jpg',
    tags: const <Tag>[],
    artists: const <String>[],
    characters: const <String>[],
    parodies: const <String>[],
    groups: const <String>[],
    language: 'en',
    pageCount: pages,
    imageUrls: List<String>.generate(
      pages,
      (i) =>
          'https://example.com/page_${(i + 1).toString().padLeft(3, '0')}.jpg',
    ),
    uploadDate: DateTime(2026),
    url: 'https://example.com/content',
  );

  Future<DownloadResult> run(int pages, {CancelToken? cancelToken}) =>
      service.downloadContent(
        content: content(pages),
        onProgress: progress.add,
        cancelToken: cancelToken,
        savePath: tempDir.path,
      );

  Future<void> dispose() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

/// Completes all registered waiters; used to await "N-th request started"
/// without polling with real delays.
final class _StartTracker {
  final List<int> started = <int>[];
  final List<Completer<void>> _waiters = <Completer<void>>[];

  void mark() {
    started.add(started.length);
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
  }

  Future<void> until(int count) async {
    while (started.length < count) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(level: Level.off));
    }
    // DownloadManager() is constructed by the page loop; keep its EventChannel
    // listener from producing a MissingPluginException in the test zone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'kuron_native/download_progress',
          (message) async => StandardMethodCodec().encodeSuccessEnvelope(null),
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('kuron_native/download_progress', null);
    getIt.reset();
  });

  group('DownloadService streaming', () {
    test('streams one page to .part, publishes bytes and preserves source '
        'headers (Cookie/UA)', () async {
      final expectedBytes = Uint8List.fromList(
        List<int>.generate(128, (i) => (i * 3 + 1) & 0xFF),
      );
      final observed = Completer<void>();
      final gate = Completer<void>();

      final h = _Harness();
      await h.init(
        handler: (options, cancelFuture) async {
          expect(options.responseType, ResponseType.stream);
          return ResponseBody(
            _observedPartStream(
              expectedBytes,
              collectParts: () => h.partFiles,
              observed: observed,
              gate: gate.future,
            ),
            HttpStatus.ok,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['image/jpeg'],
              Headers.contentLengthHeader: <String>['${expectedBytes.length}'],
            },
          );
        },
      );
      addTearDown(h.dispose);

      final downloadFuture = h.run(1);
      await observed.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          fail('Dio never created a .part file in ${h.imagesDir.path}');
        },
      );

      // While the stream is gated, the temp file must exist with the exact
      // .part name; this is what Dio receives as the download destination.
      expect(h.partFiles, hasLength(1));
      expect(h.partFiles.single, endsWith('page_001.jpg.part'));
      gate.complete();

      final result = await downloadFuture;

      expect(result.success, isTrue, reason: result.error);
      expect(result.totalFiles, 1);
      final published = File(h.pagePath(1));
      expect(published.existsSync(), isTrue);
      expect(await published.readAsBytes(), equals(expectedBytes));
      expect(h.partFiles, isEmpty, reason: 'no .part may remain');

      final seen = h.adapter.seenRequests.single;
      // RequestOptions.path is the URL (Dio does not expose savePath here) —
      // the real .part destination is asserted above via h.partFiles.
      expect(seen.path, contains('page_001.jpg'));
      expect(seen.headers['Cookie'], contains('session=abc123'));
      expect(seen.headers['User-Agent'], 'Kuron-Streaming-Test-UA');
      expect(seen.headers['Referer'], 'https://example.com/');
    });

    test('descrambles XOR-encoded .part bytes before publishing', () async {
      const seed = 12345;
      // Non-image dummy bytes: decodeXorOnly returns raw decoded bytes instead
      // of re-encoding a JPEG (which would be nondeterministic).
      final plain = Uint8List.fromList(
        List<int>.generate(64, (i) => (i + 1) & 0xFF),
      );
      // XOR is symmetric: applying the LCG keystream once scrambles, applying
      // it again descrambles.
      final scrambled = ComixDescrambler.decodeWithLcg(
        plain,
        seed,
        plain.length,
      );
      expect(scrambled, isNot(equals(plain)));

      final h = _Harness();
      await h.init(
        handler: (options, cancelFuture) async => _byteResponse(
          scrambled,
          extraHeaders: <String, List<String>>{
            'x-enc-seed': <String>['$seed'],
            'x-enc-len': <String>['${plain.length}'],
          },
        ),
      );
      addTearDown(h.dispose);

      final result = await h.run(1);

      expect(result.success, isTrue, reason: result.error);
      expect(await File(h.pagePath(1)).readAsBytes(), equals(plain));
      expect(h.partFiles, isEmpty);
    });

    test('empty body publishes nothing and cleans up the .part file', () async {
      final h = _Harness();
      await h.init(
        handler: (options, cancelFuture) async => ResponseBody(
          const Stream<Uint8List>.empty(),
          HttpStatus.ok,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/octet-stream'],
            Headers.contentLengthHeader: <String>['0'],
          },
        ),
      );
      addTearDown(h.dispose);

      final result = await h.run(1);

      expect(result.success, isFalse);
      expect(result.downloadedFiles, isEmpty);
      expect(File(h.pagePath(1)).existsSync(), isFalse);
      expect(h.partFiles, isEmpty, reason: 'empty .part must be deleted');
    });

    test(
      'caps concurrency at 3 and starts the next page when a slot frees',
      () async {
        final tracker = _StartTracker();
        final gates = <Completer<void>>[];
        var releaseAll = false;
        var active = 0;
        var maxActive = 0;

        final h = _Harness();
        await h.init(
          handler: (options, cancelFuture) async {
            final gate = Completer<void>();
            gates.add(gate);
            if (releaseAll) gate.complete();
            active++;
            if (active > maxActive) maxActive = active;
            tracker.mark();
            await gate.future;
            active--;
            return _byteResponse(Uint8List.fromList(const <int>[1, 2, 3]));
          },
        );
        addTearDown(h.dispose);

        final downloadFuture = h.run(7);

        await tracker.until(3);
        expect(active, 3);
        expect(maxActive, 3);

        // Free a single slot: a 4th page must be scheduled while the other two
        // are still held (a slow image does not stall the whole batch).
        gates.first.complete();
        await tracker.until(4);
        expect(maxActive, lessThanOrEqualTo(3));

        releaseAll = true;
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }

        final result = await downloadFuture.timeout(const Duration(seconds: 5));

        expect(result.success, isTrue, reason: result.error);
        expect(result.totalFiles, 7);
        expect(maxActive, 3, reason: 'never more than 3 in flight');
        for (var page = 1; page <= 7; page++) {
          expect(File(h.pagePath(page)).existsSync(), isTrue);
        }
        expect(h.partFiles, isEmpty);
      },
    );

    test('cancel aborts in-flight pages, schedules no more and removes .part '
        'files', () async {
      final tracker = _StartTracker();
      final cancelToken = CancelToken();
      final partial = Uint8List.fromList(const <int>[9, 8, 7, 6]);

      final h = _Harness();
      await h.init(
        handler: (options, cancelFuture) async {
          tracker.mark();
          return ResponseBody(
            _cancelAwareStream(partial, cancelFuture),
            HttpStatus.ok,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/octet-stream'],
              Headers.contentLengthHeader: <String>['${partial.length}'],
            },
          );
        },
      );
      addTearDown(h.dispose);

      final downloadFuture = h.run(7, cancelToken: cancelToken);

      await tracker
          .until(3)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              fail(
                'only ${tracker.started.length} pages started before cancel',
              );
            },
          );
      expect(tracker.started.length, 3);

      cancelToken.cancel();

      final result = await downloadFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          fail('download future did not settle after cancel');
        },
      );

      expect(result.success, isFalse, reason: 'cancel must fail the batch');
      expect(result.error, isNotNull);
      expect(
        tracker.started.length,
        3,
        reason: 'no page may be scheduled after cancel',
      );
      // The other workers' cleanup is async; give their delete operations a
      // short, deterministic window before inspecting the filesystem.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.partFiles, isEmpty, reason: 'partial files must be deleted');
      for (var page = 1; page <= 7; page++) {
        expect(File(h.pagePath(page)).existsSync(), isFalse);
      }
    });
  });
}
