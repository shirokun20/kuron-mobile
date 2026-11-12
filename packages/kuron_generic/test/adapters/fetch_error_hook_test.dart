library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart' hide Content;
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/adapters/fetch_error_hook.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hook.test';

Map<String, dynamic> _config() => {
  'source': 'hook',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'home': {
        'url': '/',
        'list': {
          'container': '.utao',
          'fields': {
            'id': {
              'selector': 'a.series',
              'attribute': 'href',
              'transform': 'slug',
            },
            'title': {'selector': '.luf > a > h4'},
          },
        },
      },
    },
  },
};

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
  dio: dio,
  urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
  parser: GenericHtmlParser(logger: Logger()),
  logger: Logger(),
  sourceId: 'hook',
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

Map<String, dynamic> _detailConfig() => {
  'source': 'hook',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {'detail': '/manga/{id}/'},
    'selectors': {
      'detail': {
        'fields': {
          'title': {'selector': 'h1'},
        },
      },
    },
  },
};

Map<String, dynamic> _readerConfig() => {
  'source': 'hook',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {'chapter': '/c/{id}/'},
    'selectors': {
      'reader': {
        'images': {'selector': 'img', 'attribute': 'src'},
      },
    },
  },
};
Dio _okDio() {
  const html =
      '<html><body>'
      '<div class="utao">'
      '<a class="series" href="https://hook.test/manga/a/"></a>'
      '<div class="luf"><a href="https://hook.test/manga/a/"><h4>A</h4></a></div>'
      '</div>'
      '</body></html>';
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: html),
      ),
    ),
  );
  return dio;
}

void main() {
  tearDown(() {
    FetchErrorReporter.onError = null;
  });

  test('failed list fetch notifies the hook and still returns empty', () async {
    Object? seenError;
    String? seenSource;
    String? seenFeature;
    String? seenUrl;
    FetchErrorReporter.onError =
        (
          Object error, {
          String? sourceId,
          String? feature,
          String? url,
          int? statusCode,
        }) {
          seenError = error;
          seenSource = sourceId;
          seenFeature = feature;
          seenUrl = url;
        };

    final result = await _buildAdapter(_failingDio())
        .search(const SearchFilter(), _config());

    expect(result.items, isEmpty);
    expect(seenError, isA<DioException>());
    expect(seenSource, 'hook');
    expect(seenFeature, 'list');
    expect(seenUrl, contains(_baseUrl));
  });

  test('failed detail fetch notifies with feature detail', () async {
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
        .fetchDetail('some-manga', _detailConfig());

    expect(result.content.title, isEmpty);
    expect(seenFeature, 'detail');
  });

  test('failed reader fetch notifies with feature reader', () async {
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
        .fetchChapterImages('ch-1', _readerConfig());

    expect(result, isNull);
    expect(seenFeature, 'reader');
  });

  test('successful fetch does not notify the hook', () async {
    var called = false;
    FetchErrorReporter.onError =
        (
          Object error, {
          String? sourceId,
          String? feature,
          String? url,
          int? statusCode,
        }) {
          called = true;
        };

    final result = await _buildAdapter(_okDio())
        .search(const SearchFilter(), _config());

    expect(result.items, isNotEmpty);
    expect(called, isFalse);
  });

  test('throwing hook does not break the fetch', () async {
    FetchErrorReporter.onError =
        (
          Object error, {
          String? sourceId,
          String? feature,
          String? url,
          int? statusCode,
        }) {
          throw StateError('hook bug');
        };

    final result = await _buildAdapter(_failingDio())
        .search(const SearchFilter(), _config());

    expect(result.items, isEmpty);
  });
}
