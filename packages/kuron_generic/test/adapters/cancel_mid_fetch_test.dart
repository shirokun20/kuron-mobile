// Fase 2b — cancel mid-fetch aborts the adapter call instead of returning an
// empty result, and GenericHttpSource bridges its pure-Dart onCancel hook to a
// Dio CancelToken. No real network: a blocking request interceptor holds the
// request until the token is cancelled.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://cancel.test';

/// Builds a Dio whose onRequest interceptor parks the request until released.
/// Exposes the RequestOptions of the parked request so tests can assert the
/// adapter forwarded a CancelToken into the Dio call.
class _ParkedDio {
  final Dio dio;
  final Completer<RequestOptions> seen = Completer<RequestOptions>();

  _ParkedDio()
      : dio = Dio(BaseOptions(baseUrl: _baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!seen.isCompleted) seen.complete(options);
          // Intentionally never call handler.next/ reject — cancelling the
          // token makes Dio reject this parked request with a cancel error.
        },
      ),
    );
  }
}

Map<String, dynamic> _restConfig() => {
  'source': 'cancelrest',
  'baseUrl': _baseUrl,
  'api': {
    'apiBase': '$_baseUrl/api/v2',
    'endpoints': {
      'search': '/api/v2/search?query={query}&page={page}',
      'detail': '/api/v2/gallery/{id}',
    },
  },
  'selectors': {
    'items': {'selector': r'$.result[*]', 'type': 'jsonpath'},
  },
};

GenericRestAdapter _restAdapter(Dio dio) => GenericRestAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericJsonParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'cancelrest',
    );

Matcher throwsCancel = throwsA(
  predicate<DioException>(
    (e) => e.type == DioExceptionType.cancel,
    'a DioException with type == cancel',
  ),
);

void main() {
  group('Fase 2b — cancel mid-fetch aborts', () {
    test('REST search forwards token and rethrows cancel', () async {
      final parked = _ParkedDio();
      final token = CancelToken();
      final future = _restAdapter(parked.dio).search(
        const SearchFilter(query: 'a'),
        _restConfig(),
        cancelToken: token,
      );

      final options = await parked.seen.future;
      expect(options.cancelToken, same(token),
          reason: 'adapter must forward cancelToken into _dio.get');
      token.cancel('cancelled mid-search');

      await expectLater(future, throwsCancel);
    });

    test('REST detail forwards token and rethrows cancel', () async {
      final parked = _ParkedDio();
      final token = CancelToken();
      final future = _restAdapter(parked.dio).fetchDetail(
        'g-1',
        _restConfig(),
        cancelToken: token,
      );

      final options = await parked.seen.future;
      expect(options.cancelToken, same(token));
      token.cancel('cancelled mid-detail');

      await expectLater(future, throwsCancel);
    });

    test('GenericHttpSource.getChapterImages bridges onCancel to adapter token',
        () async {
      final adapter = _TokenAwareAdapter();
      final source = GenericHttpSource(
        rawConfig: const {'source': 'bridgetest', 'baseUrl': _baseUrl},
        dio: Dio(),
        logger: Logger(level: Level.off),
        adapterOverride: adapter,
      );

      void Function()? cancelCallback;
      final future = source.getChapterImages(
        'ch-1',
        onCancel: (callback) => cancelCallback = callback,
      );

      // Let getChapterImages register the hook and hand the token to the adapter.
      await Future<void>.delayed(Duration.zero);
      expect(adapter.seenToken, isNotNull,
          reason: 'bridge must allocate a token for the adapter');
      expect(cancelCallback, isNotNull);
      cancelCallback!();

      await expectLater(future, throwsCancel);
    });
  });
}

/// Adapter that records the forwarded token and fails once it is cancelled.
class _TokenAwareAdapter implements GenericAdapter {
  CancelToken? seenToken;

  @override
  Duration get detailTimeout => const Duration(seconds: 30);

  @override
  Future<ChapterData?> fetchChapterImages(
    String chapterId,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) async {
    seenToken = cancelToken;
    await (cancelToken ?? CancelToken()).whenCancel;
    throw DioException(
      requestOptions: RequestOptions(path: chapterId),
      type: DioExceptionType.cancel,
    );
  }

  @override
  Future<AdapterSearchResult> search(
    SearchFilter filter,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<AdapterDetailResult> fetchDetail(
    String contentId,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Content>> fetchRelated(
    String contentId,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Comment>> fetchComments(
    String contentId,
    Map<String, dynamic> rawConfig, {
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Chapter>> fetchChapters(
    String contentId,
    Map<String, dynamic> rawConfig, {
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
    CancelToken? cancelToken,
  }) async =>
      const [];
}
