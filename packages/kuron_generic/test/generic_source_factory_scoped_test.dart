// Per-source Dio scope isolation for [GenericSourceFactory].
//
// Guards issue #86: each config-driven source must fetch through its own Dio
// clone, so late header/interceptor mutations on the shared client (bypass or
// rate-limit behaviour for one source) never leak into other sources.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://iso.test';

Map<String, dynamic> _configFor(String source) => {
  'source': source,
  'baseUrl': _baseUrl,
  'api': {
    'apiBase': '$_baseUrl/api/v2',
    'endpoints': {
      'search': '/api/v2/search?query={query}&sort={sort}&page={page}',
      'allGalleries': '/api/v2/galleries?page={page}',
    },
  },
  'selectors': {
    'items': {'selector': r'$.result[*]', 'type': 'jsonpath'},
    'totalPages': {'selector': r'$.num_pages', 'type': 'jsonpath'},
  },
  'searchConfig': {
    'sortingConfig': {
      'options': [
        {'value': 'newest', 'apiValue': 'date'},
      ],
    },
  },
};

String _searchUrl(String query) =>
    // apiBase + endpoint template concatenate (double /api/v2), and the
    // `newest` sort passes through (see scratch probe 2026-11-24).
    '$_baseUrl/api/v2/api/v2/search?query=$query&sort=newest&page=1';

void main() {
  group('GenericSourceFactory per-source Dio scope', () {
    test(
      'late shared-client mutations do not leak into created sources',
      () async {
        final seen = <RequestOptions>[];
        final shared = Dio(
          BaseOptions(baseUrl: _baseUrl, headers: const {'X-Base': 'yes'}),
        );
        final dioAdapter = DioAdapter(
          dio: shared,
          matcher: const UrlRequestMatcher(),
        );
        for (final query in ['a', 'b']) {
          dioAdapter.onGet(
            _searchUrl(query),
            (server) => server.replyCallback(200, (opts) {
              seen.add(opts);
              return {'result': <dynamic>[], 'num_pages': 0};
            }),
          );
        }

        final factory = GenericSourceFactory(
          dio: shared,
          logger: Logger(level: Level.off),
        );
        final sourceA = factory.create(_configFor('source-a'));
        final sourceB = factory.create(_configFor('source-b'));

        // Mutations applied to the shared client AFTER create (e.g. a
        // bypass interceptor or per-source header for another extension).
        shared.options.headers['X-Late'] = 'late';
        shared.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              options.headers['X-Injected'] = 'yes';
              handler.next(options);
            },
          ),
        );

        await sourceA.search(
          const SearchFilter(query: 'a', page: 1, sort: SortOption.newest),
        );
        await sourceB.search(
          const SearchFilter(query: 'b', page: 1, sort: SortOption.newest),
        );

        expect(seen, hasLength(2));
        for (final opts in seen) {
          expect(
            opts.headers['X-Base'],
            'yes',
            reason: 'clone keeps headers snapshotted at create time',
          );
          expect(
            opts.headers.containsKey('X-Late'),
            isFalse,
            reason: 'late shared header mutation must not leak per source',
          );
          expect(
            opts.headers.containsKey('X-Injected'),
            isFalse,
            reason: 'late shared interceptor must not run for scoped sources',
          );
        }
      },
    );

    test(
      'disposeScopedClient detaches without closing shared adapter',
      () async {
        final shared = Dio(BaseOptions(baseUrl: _baseUrl));
        final adapter = _TrackingAdapter();
        shared.httpClientAdapter = adapter;

        final factory = GenericSourceFactory(
          dio: shared,
          logger: Logger(level: Level.off),
        );
        final sourceA = factory.create(_configFor('source-a'));
        final sourceB = factory.create(_configFor('source-b'));

        factory.disposeScopedClient('source-a');

        // Shared adapter must stay open; surviving sourceB still works.
        expect(adapter.closed, isFalse);
        await sourceB.search(
          const SearchFilter(query: 'b', page: 1, sort: SortOption.newest),
        );
        expect(adapter.fetchCount, 1);

        // Late request on disposed sourceA never touches the shared adapter
        // (GenericRestAdapter swallows connection errors as empty results).
        final disposedResult = await sourceA.search(
          const SearchFilter(query: 'a', page: 1, sort: SortOption.newest),
        );
        expect(disposedResult.contents, isEmpty);
        expect(adapter.fetchCount, 1);

        // Re-creating source-a gets a fresh client backed by the still-open adapter.
        final recreatedA = factory.create(_configFor('source-a'));
        await recreatedA.search(
          const SearchFilter(query: 'a', page: 1, sort: SortOption.newest),
        );
        expect(adapter.fetchCount, 2);

        factory.disposeAll();
        expect(adapter.closed, isFalse);
      },
    );
  });
}

class _TrackingAdapter implements HttpClientAdapter {
  bool closed = false;
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromString(
      '{"result":[],"num_pages":0}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}
