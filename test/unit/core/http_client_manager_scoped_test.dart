// Per-source Dio scope isolation for [HttpClientManager].
//
// Guards issue #86: a bypass/rate-limit interceptor or header mutation on one
// source's client must never leak into another source or the global client.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/network/http_client_manager.dart';

class _TagInterceptor extends Interceptor {
  _TagInterceptor(this.tag);

  final String tag;
}

void main() {
  setUp(() {
    HttpClientManager.resetForTesting();
    HttpClientManager.initializeHttpClient(logger: Logger(level: Level.off));
  });

  tearDown(HttpClientManager.resetForTesting);

  test('scoped clients isolate headers and interceptors per source', () {
    final a = HttpClientManager.scopedClientForSource(
      'source-a',
      extraHeaders: const {'X-Source': 'a'},
      extraInterceptors: [_TagInterceptor('a')],
    );
    final b = HttpClientManager.scopedClientForSource('source-b');

    // Same source ID returns the cached instance.
    expect(identical(a, HttpClientManager.scopedClientForSource('source-a')),
        isTrue);
    expect(identical(a, b), isFalse);

    // Headers are cloned per source.
    expect(a.options.headers['X-Source'], 'a');
    expect(b.options.headers.containsKey('X-Source'), isFalse);
    expect(HttpClientManager.httpClient.options.headers
        .containsKey('X-Source'), isFalse);

    // Interceptors are isolated per source.
    expect(
      a.interceptors.whereType<_TagInterceptor>().map((e) => e.tag),
      ['a'],
    );
    expect(b.interceptors.whereType<_TagInterceptor>(), isEmpty);
    expect(
      HttpClientManager.httpClient.interceptors
          .whereType<_TagInterceptor>(),
      isEmpty,
    );
  });

  test('mutating one scoped client does not leak into others', () {
    final a = HttpClientManager.scopedClientForSource('source-a');
    final b = HttpClientManager.scopedClientForSource('source-b');

    a.options.headers['X-Mutated'] = '1';
    a.interceptors.add(_TagInterceptor('late'));

    expect(b.options.headers.containsKey('X-Mutated'), isFalse);
    expect(b.interceptors.whereType<_TagInterceptor>(), isEmpty);
    expect(
      HttpClientManager.httpClient.options.headers
          .containsKey('X-Mutated'),
      isFalse,
    );
  });

  test('deprecated clearInterceptors no longer mutates the list', () {
    final global = HttpClientManager.httpClient;
    // Snapshot (Dio itself ships built-in interceptors, e.g.
    // ImplyContentTypeInterceptor, plus our default error/logging wrapper).
    final snapshot = List<Interceptor>.of(global.interceptors);
    expect(snapshot, isNotEmpty);

    global.interceptors.add(_TagInterceptor('temp'));

    // ignore: deprecated_member_use
    HttpClientManager.clearInterceptors();

    // No-op by design: per-source isolation replaced global mutation.
    expect(
      global.interceptors,
      orderedEquals([...snapshot, isA<_TagInterceptor>()]),
    );
  });

  test('disposeScopedClient drops the cached instance', () {
    final a = HttpClientManager.scopedClientForSource('source-a');
    HttpClientManager.disposeScopedClient('source-a');
    final recreated = HttpClientManager.scopedClientForSource('source-a');
    expect(identical(a, recreated), isFalse);
    expect(
      HttpClientManager.getStatistics()['scoped_clients'],
      contains('source-a'),
    );
  });
}
