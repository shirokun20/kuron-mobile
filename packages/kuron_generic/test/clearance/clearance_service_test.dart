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
  _FakeDriver? driver,
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
  });
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
