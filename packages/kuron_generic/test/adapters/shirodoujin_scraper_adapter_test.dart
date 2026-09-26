library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

const _baseUrl = 'https://shirodoujin.com';

String _readFixture(String filename) {
  final candidates = [
    'informations/documentation/shirodoujin/$filename',
    '../../informations/documentation/shirodoujin/$filename',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }

  throw StateError('Cannot locate fixture $filename');
}

GenericScraperAdapter _buildAdapter(Dio dio) {
  final logger = Logger(level: Level.off);
  return GenericScraperAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericHtmlParser(logger: logger),
    logger: logger,
    sourceId: 'shirodoujin',
  );
}

void main() {
  late Map<String, dynamic> config;

  setUpAll(() async {
    config = (await loadConfigRemote('shirodoujin-config.json')).cast<String, dynamic>();
  });

  group('shirodoujin scraper config', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('home fixture extracts plain titles and real cover urls', () async {
      dioAdapter.onGet(
        '$_baseUrl/',
        (server) => server.reply(
          200,
          _readFixture('halaman-utama.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(const SearchFilter(page: 1), config);

      expect(result.items, isNotEmpty);
      expect(
        result.items.first.title,
        'Teacher Yoonji',
      );
      expect(result.items.first.title, isNot(startsWith('<img')));
      expect(
        result.items.first.coverUrl,
        startsWith('https://'),
      );
      expect(
        result.items.first.coverUrl,
        contains('shiro'),
      );
    });

    test('search fixture uses flexbox2 layout instead of home layout',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/?s=the',
        (server) => server.reply(
          200,
          _readFixture('halaman-search.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'the', page: 1),
        config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.title, 'The Hottie’s Good at Football');
      expect(result.items.first.title, isNot(startsWith('<img')));
    });

    test('genre fixture uses content-by-tag flexbox2 layout', () async {
      dioAdapter.onGet(
        '$_baseUrl/genre/ahegao/',
        (server) => server.reply(
          200,
          _readFixture('halaman-tag-click.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'genre:ahegao', page: 1),
        config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.title, 'Nama Panggilannya…');
      expect(
        result.items.any((item) => item.title == 'Village Special Ordinance'),
        isTrue,
      );
      expect(
        result.items.every((item) => !item.title.trimLeft().startsWith('<img')),
        isTrue,
      );
    });

    test(
        'detail fixture extracts title cleanly even when chapter date is inline',
        () async {
      dioAdapter.onGet(
        '$_baseUrl/series/my-body-is-atop-her-tongue-bahasa-indonesia',
        (server) => server.reply(
          200,
          _readFixture('halaman-detail.html'),
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        ),
      );

      final result = await adapter.fetchDetail(
        'my-body-is-atop-her-tongue-bahasa-indonesia',
        config,
      );

      expect(
        result.content.title,
        'My Body is Atop Her Tongue Bahasa Indonesia',
      );
      expect(result.content.language, 'id');
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.first.title, 'Chapter 1');
      expect(result.content.chapters!.first.uploadDate, isNull);
    });
  });
}
