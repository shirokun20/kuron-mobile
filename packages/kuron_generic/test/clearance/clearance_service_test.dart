import 'dart:async';
import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/clearance/clearance_service.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

class _FakeDriver implements ClearanceDriver {
  int calls = 0;
  ClearanceSolution? solution;
  @override
  Future<ClearanceSolution?> solve(String domainUrl) async {
    calls++;
    return solution;
  }
}

ClearanceService _service({
  SecureValueStore? store,
  ClearanceDriver? driver,
}) {
  return ClearanceService(
    store: store ?? InMemorySecureValueStore(),
    driver: driver ?? _FakeDriver(),
    logger: Logger(level: Level.off),
    sourceId: 'schale-network',
    domainUrl: 'https://niyaniya.moe/',
  );
}

void main() {
  group('ClearanceService', () {
    test('returns cached token without solving', () async {
      final driver = _FakeDriver();
      final svc = _service(driver: driver);
      await svc.setToken('cached-crt');
      expect(await svc.acquire(), 'cached-crt');
      expect(driver.calls, 0);
    });

    test('solves once and persists token, ua, cookies', () async {
      final store = InMemorySecureValueStore();
      final driver = _FakeDriver()
        ..solution = const ClearanceSolution(
          token: 'fresh-crt',
          userAgent: 'ua-1',
          cookies: 'cf=1',
        );
      final svc = _service(store: store, driver: driver);

      expect(await svc.acquire(), 'fresh-crt');
      expect(driver.calls, 1);

      // Second acquire uses memory cache.
      expect(await svc.acquire(), 'fresh-crt');
      expect(driver.calls, 1);

      // A new instance restores from the store without solving.
      final fresh = _service(store: store, driver: driver);
      expect(await fresh.acquire(), 'fresh-crt');
      expect(driver.calls, 1);
      expect(fresh.cachedUserAgent, 'ua-1');
    });

    test('returns null when driver fails', () async {
      final svc = _service();
      expect(await svc.acquire(), isNull);
    });

    test('clearToken wipes memory and store', () async {
      final store = InMemorySecureValueStore();
      final svc = _service(store: store);
      await svc.setToken('crt');
      await svc.clearToken();
      expect(svc.cached, isNull);
      expect(
        ClearanceService(
          store: store,
          driver: _FakeDriver(),
          logger: Logger(level: Level.off),
          sourceId: 'schale-network',
          domainUrl: 'https://niyaniya.moe/',
        ).cached,
        isNull,
      );
    });

    test('interceptor injects crt + auth on POST detail endpoint', () async {
      final svc = _service();
      await svc.setToken('crt-9');
      final dio = Dio()..interceptors.add(svc.createInterceptor());
      dio.httpClientAdapter = _CaptureAdapter();
      await dio.post('https://niyaniya.moe/books/detail/123');
      final captured = _CaptureAdapter.lastRequest!;
      expect(captured.queryParameters['crt'], 'crt-9');
      expect(
        captured.headers['Authorization'],
        'Bearer crt-9',
      );
    });

    test('interceptor passes unrelated hosts through untouched', () async {
      final svc = _service();
      final dio = Dio()..interceptors.add(svc.createInterceptor());
      dio.httpClientAdapter = _CaptureAdapter();
      await dio.get('https://example.com/other');
      final captured = _CaptureAdapter.lastRequest!;
      expect(captured.headers['Authorization'], isNull);
      expect(captured.headers['Referer'], isNull);
    });

    test('5 concurrent acquire calls call driver.solve exactly 1x (single-flight)', () async {
      final driver = _FakeDriver()
        ..solution = const ClearanceSolution(
          token: 'single-flight-crt',
          userAgent: 'ua-1',
          cookies: 'cf=1',
        );
      final svc = _service(driver: driver);

      final results = await Future.wait([
        svc.acquire(),
        svc.acquire(),
        svc.acquire(),
        svc.acquire(),
        svc.acquire(),
      ]);

      expect(driver.calls, 1);
      for (final r in results) {
        expect(r, 'single-flight-crt');
      }
    });

    test('interceptor continues via handler.next when driver throws exception without hanging', () async {
      final throwingDriver = _ThrowingDriver();
      final svc = _service(driver: throwingDriver);
      final dio = Dio()..interceptors.add(svc.createInterceptor());
      dio.httpClientAdapter = _CaptureAdapter();

      // POST to endpoint triggers acquire() which throws.
      // Must not hang, must call handler.next(options).
      await dio.post('https://niyaniya.moe/books/detail/123');
      final captured = _CaptureAdapter.lastRequest!;
      expect(captured.uri.toString(), 'https://niyaniya.moe/books/detail/123');
    });

    test('acquire returns token and caches in memory when store writes fail',
        () async {
      final driver = _FakeDriver()
        ..solution = const ClearanceSolution(token: 'fresh-crt');
      final svc = _service(store: _ThrowingStore(), driver: driver);

      // Must not throw (-34018 on unsigned macOS dev builds).
      expect(await svc.acquire(), 'fresh-crt');
      expect(svc.cached, 'fresh-crt');
      // Second acquire serves from memory without re-solving.
      expect(await svc.acquire(), 'fresh-crt');
      expect(driver.calls, 1);
    });

    test('setToken caches in memory when store write fails', () async {
      final svc = _service(store: _ThrowingStore());
      await svc.setToken('memory-crt');
      expect(svc.cached, 'memory-crt');
      expect(await svc.acquire(), 'memory-crt');
    });

    test('clearToken clears memory cache even when store deletes fail',
        () async {
      final svc = _service(store: _ThrowingStore());
      await svc.setToken('memory-crt');
      await svc.clearToken();
      expect(svc.cached, isNull);
    });

    test('clearToken() while solve is in-flight does not resurrect token into cache', () async {
      final completer = Completer<ClearanceSolution?>();
      final slowDriver = _DelayedDriver(completer.future);
      final svc = _service(driver: slowDriver);

      final acquireFuture = svc.acquire();
      // Wait for solver to be invoked
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 403 or logout triggers clearToken while solver is still running
      await svc.clearToken();
      expect(svc.cached, isNull);

      // Solver completes late
      completer.complete(const ClearanceSolution(token: 'orphaned-token'));
      final token = await acquireFuture;

      expect(token, isNull);
      expect(svc.cached, isNull);
    });
  });
}

class _DelayedDriver implements ClearanceDriver {
  final Future<ClearanceSolution?> future;
  _DelayedDriver(this.future);

  @override
  Future<ClearanceSolution?> solve(String domainUrl) => future;
}

/// Simulates unsigned macOS dev builds where every keychain access
/// throws PlatformException(-34018).
class _ThrowingStore implements SecureValueStore {
  @override
  Future<String?> read(String key) async =>
      throw Exception('keychain unavailable (-34018)');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('keychain unavailable (-34018)');

  @override
  Future<void> delete(String key) async =>
      throw Exception('keychain unavailable (-34018)');
}

class _ThrowingDriver implements ClearanceDriver {
  @override
  Future<ClearanceSolution?> solve(String domainUrl) async {
    throw Exception('Simulated WebView solver crash');
  }
}

class _CaptureAdapter implements HttpClientAdapter {
  static RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
