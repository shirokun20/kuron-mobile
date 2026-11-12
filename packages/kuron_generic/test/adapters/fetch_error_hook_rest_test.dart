library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';

import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hook-rest.test';

Map<String, dynamic> _config() => {
  'source': 'hookrest',
  'baseUrl': _baseUrl,
  'api': {
    'apiBase': '$_baseUrl/api/v2',
    'endpoints': {
      'search': '/api/v2/search?query={query}&page={page}',
      'allGalleries': '/api/v2/galleries?page={page}',
      'detail': '/api/v2/gallery/{id}',
    },
  },
  'selectors': {
    'items': {'selector': r'$.result[*]', 'type': 'jsonpath'},
  },
};

GenericRestAdapter _buildAdapter(Dio dio) => GenericRestAdapter(
  dio: dio,
  urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
  parser: GenericJsonParser(logger: Logger(level: Level.off)),
  logger: Logger(level: Level.off),
  sourceId: 'hookrest',
);

Dio _failingDio() {
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          error: const SocketException('DNS down'),
          type: DioExceptionType.unknown,
        ),
      ),
    ),
  );
  return dio;
}

void main() {
  tearDown(() {
    FetchErrorReporter.onError = null;
  });

  test('failed REST search notifies with feature list', () async {
    String? seenFeature;
    String? seenSource;
    FetchErrorReporter.onError =
        (
          Object error, {
          String? sourceId,
          String? feature,
          String? url,
          int? statusCode,
        }) {
          seenFeature = feature;
          seenSource = sourceId;
        };

    final result = await _buildAdapter(_failingDio())
        .search(const SearchFilter(query: 'a'), _config());

    expect(result.items, isEmpty);
    expect(seenFeature, 'list');
    expect(seenSource, 'hookrest');
  });

  test('failed REST detail notifies with feature detail', () async {
    String? seenFeature;
    FetchErrorReporter.onError =
        (
          Object error, {
          String? sourceId,
          String? feature,
          String? url,
          int? statusCode,
        }) {
          seenFeature = feature;
        };

    final result = await _buildAdapter(_failingDio())
        .fetchDetail('abc123', _config());

    expect(result.content.title, isEmpty);
    expect(seenFeature, 'detail');
  });
}
