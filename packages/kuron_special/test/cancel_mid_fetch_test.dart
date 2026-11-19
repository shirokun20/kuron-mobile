// Fase 2b — special adapters and the WebView-bypass Dio wrappers must thread
// the caller's CancelToken into their HTTP calls so cancel aborts instead of
// returning empty. Parked interceptor = no real network.
library;

import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_special/src/doujindesuxxx/doujindesuxxx_source_factory.dart';
import 'package:kuron_special/src/vihentai/vihentai_adapter.dart';
import 'package:logger/logger.dart';

const _baseUrl = 'https://cancel-special.test';

class _ParkedDio {
  final Dio dio;
  final Completer<RequestOptions> seen = Completer<RequestOptions>();

  _ParkedDio()
      : dio = Dio(BaseOptions(baseUrl: _baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!seen.isCompleted) seen.complete(options);
        },
      ),
    );
  }
}

Matcher throwsCancel = throwsA(
  predicate<DioException>(
    (e) => e.type == DioExceptionType.cancel,
    'a DioException with type == cancel',
  ),
);

void main() {
  group('Fase 2b — special adapters cancel mid-fetch', () {
    test('DoujinDesuXxxAdapter.search forwards token and rethrows cancel',
        () async {
      final parked = _ParkedDio();
      final token = CancelToken();
      final adapter = DoujinDesuXxxAdapter(
        dio: parked.dio,
        sourceId: 'ddx-cancel',
        base: _baseUrl,
      );

      final future = adapter.search(
        const SearchFilter(query: 'test'),
        const {'source': 'ddx-cancel', 'baseUrl': _baseUrl},
        cancelToken: token,
      );

      final options = await parked.seen.future;
      expect(options.cancelToken, same(token),
          reason: 'DoujinDesuXxxAdapter must forward cancelToken into _dio');
      token.cancel('cancelled mid-search');

      await expectLater(future, throwsCancel);
    });

    test('ViHentaiAdapter.fetchChapterImages forwards token and rethrows cancel',
        () async {
      final parked = _ParkedDio();
      final token = CancelToken();
      final delegate = GenericScraperAdapter(
        dio: parked.dio,
        urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        logger: Logger(level: Level.off),
        sourceId: 'vh-cancel',
      );
      final adapter = ViHentaiAdapter(
        dio: parked.dio,
        delegate: delegate,
        logger: Logger(level: Level.off),
        sourceId: 'vh-cancel',
        cookieJar: PersistCookieJar(),
      );

      final future = adapter.fetchChapterImages(
        'some-id',
        const {
          'source': 'vh-cancel',
          'baseUrl': _baseUrl,
          'scraper': {
            'urlPatterns': {'chapter': '/truyen/{id}/{ch}'},
          },
        },
        cancelToken: token,
      );

      final options = await parked.seen.future;
      expect(options.cancelToken, same(token),
          reason: 'ViHentaiAdapter must forward cancelToken into _dio');
      token.cancel('cancelled mid-chapter-fetch');

      await expectLater(future, throwsCancel);
    });
  });
}
