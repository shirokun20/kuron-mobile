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

const _baseUrl = 'https://www.tooncubus.top';
const _readerBaseUrl = 'https://www.tooncubus-read.my.id';

String _readFixture(String filename) {
  final candidates = [
    'informations/documentation/tooncubus/$filename',
    '../../informations/documentation/tooncubus/$filename',
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
    sourceId: 'tooncubus',
  );
}

void main() {
  late Map<String, dynamic> config;
  const nextPageUrl =
      '$_baseUrl/search/label/Series?updated-max=2025-12-09T02:03:00-08:00&max-results=16&start=16&by-date=false';

  setUpAll(() async {
    config = (await loadConfigRemote('tooncubus-config.json')).cast<String, dynamic>();
  });

  test('home fixture extracts Blogger cards from Series label page', () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);

    dioAdapter.onGet(
      '$_baseUrl/search/label/Series?max-results=16',
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
    expect(result.items.first.title, 'Love For Amalthea');
    expect(result.items.first.id, '2026/03/love-for-amalthea.html');
    expect(
      result.items.first.coverUrl,
      startsWith('https://blogger.googleusercontent.com/'),
    );
    expect(result.hasNextPage, isTrue);
  });

  test('page 2 uses Blogger cursor url instead of repeating page 1', () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);
    final page1Html = _readFixture('halaman-utama.html');
    final page2Html = page1Html.replaceFirst(
      'Love For Amalthea',
      'Page Two Title',
    );

    dioAdapter.onGet(
      '$_baseUrl/search/label/Series?max-results=16',
      (server) => server.reply(
        200,
        page1Html,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    dioAdapter.onGet(
      nextPageUrl,
      (server) => server.reply(
        200,
        page2Html,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    final firstPage = await adapter.search(const SearchFilter(page: 1), config);
    final secondPage =
        await adapter.search(const SearchFilter(page: 2), config);

    expect(firstPage.items.first.title, 'Love For Amalthea');
    expect(firstPage.nextPageUrl, nextPageUrl);
    expect(secondPage.items.first.title, 'Page Two Title');
  });

  test('page 2 can be opened directly by walking Blogger cursor pagination',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);

    dioAdapter.onGet(
      '$_baseUrl/search/label/Series?max-results=16',
      (server) => server.reply(
        200,
        _readFixture('halaman-utama.html'),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    dioAdapter.onGet(
      nextPageUrl,
      (server) => server.reply(
        200,
        _readFixture('halaman-utama-page-2.html'),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    final secondPage =
        await adapter.search(const SearchFilter(page: 2), config);

    expect(secondPage.items, isNotEmpty);
    expect(secondPage.items.first.title, isNot('Love For Amalthea'));
    expect(secondPage.hasNextPage, isTrue);
  });

  test('detail fixture extracts chapter reader URL from Baca Online block',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);

    dioAdapter.onGet(
      '$_baseUrl/2026/03/love-for-amalthea.html',
      (server) => server.reply(
        200,
        _readFixture('halaman-detail.html'),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    final result =
        await adapter.fetchDetail('2026/03/love-for-amalthea.html', config);

    expect(result.content.title, 'Love For Amalthea');
    expect(result.content.coverUrl,
        startsWith('https://blogger.googleusercontent.com/'));
    expect(result.content.chapters, isNotEmpty);
    expect(
      result.content.chapters!.first.id,
      '$_readerBaseUrl/2026/03/love-for-amalthea-1.html',
    );
    expect(result.content.chapters!.first.title, 'Baca Chapter 01');
  });

  test(
      'reader fallback follows explicit Baca Online link before scraping images',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);

    dioAdapter.onGet(
      '$_baseUrl/2023/01/konoha-shinobi-affair.html',
      (server) => server.reply(
        200,
        _readFixture('halaman-detail.html')
            .replaceAll(
              'https://www.tooncubus.top/2026/03/love-for-amalthea.html',
              '$_baseUrl/2023/01/konoha-shinobi-affair.html',
            )
            .replaceAll(
              'https://www.tooncubus-read.my.id/2026/03/love-for-amalthea-1.html',
              '$_readerBaseUrl/2026/01/konoha-shinobi-affair-04.html',
            ),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    dioAdapter.onGet(
      '$_readerBaseUrl/2026/01/konoha-shinobi-affair-04.html',
      (server) => server.reply(
        200,
        _readFixture('halaman-reader.html'),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    final result = await adapter.fetchChapterImages(
      '2023/01/konoha-shinobi-affair.html',
      config,
    );

    expect(result, isNotNull);
    expect(result!.images, isNotEmpty);
    expect(result.images.first, startsWith('https://images2.imgbox.com/'));
    expect(result.images.length, greaterThan(20));
  });

  test('tag query uses Blogger label route instead of keyword search',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _baseUrl));
    final dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    final adapter = _buildAdapter(dio);

    dioAdapter.onGet(
      '$_baseUrl/search/label/Full%20Color?max-results=20',
      (server) => server.reply(
        200,
        _readFixture('halaman-tag-click.html'),
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      ),
    );

    final result = await adapter.search(
      const SearchFilter(query: 'tag:Full Color', page: 1),
      config,
    );

    expect(result.items, isNotEmpty);
    expect(result.items.first.title, 'Love For Amalthea');
  });
}
