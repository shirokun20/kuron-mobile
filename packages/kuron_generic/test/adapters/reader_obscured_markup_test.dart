// Regression tests for reader markup that defeats plain DOM extraction.
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
//
// Covers two reader-path fixes in [GenericScraperAdapter.fetchChapterImages]:
//   1. `<noscript>` unwrap — mangareader themes (arenascan) stash chapter
//      `<img>` inside `<div id="readerarea"><noscript>…`; package:html
//      parses noscript content as text, so extraction found 0 images.
//   2. base64 `ts_reader` decode — some hosts (scythescans) encode the
//      inline `ts_reader.run({...})` script as
//      `<script src="data:text/javascript;base64,…">`, so tsReaderRegex
//      saw base64 text instead of JSON.
// Run with:
//   dart test packages/kuron_generic/test/adapters/reader_obscured_markup_test.dart
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://reader.example.com';

Map<String, dynamic> _configWithReader(Map<String, dynamic> reader) => {
      'source': 'example',
      'baseUrl': _baseUrl,
      'scraper': {
        'urlPatterns': {
          'detail': '/manga/{id}/',
          'chapter': '/{id}',
        },
        'selectors': {
          'detail': {
            'fields': {
              'title': {'selector': 'h1'},
            },
          },
          'reader': reader,
        },
      },
    };

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'example',
    );

void _mockChapter(DioAdapter dioAdapter, String html) {
  dioAdapter.onGet(
    '$_baseUrl/ch-1',
    (s) => s.reply(200, html, headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    }),
  );
}

// ── Fixture 1: images inside <noscript> (arenascan shape) ────────────────────

const _noscriptHtml = '''
<html><body>
<div id="readerarea"><noscript><p><img decoding="async" src="https://cdn.example.com/p/001.jpg" /><br />
<img decoding="async" src="https://cdn.example.com/p/002.jpg" /><br />
</p></noscript></div>
</body></html>
''';

// ── Fixture 2: ts_reader JSON base64-encoded (scythescans shape) ─────────────

String _base64TsReaderHtml() {
  const payload = 'ts_reader.run({"sources":[{"source":"Server 1","images":'
      '["https://cdn.example.com/c/01.webp","https://cdn.example.com/c/02.webp",'
      '"https://cdn.example.com/c/03.webp"]}],'
      '"prevUrl":"","nextUrl":"https://reader.example.com/ch-2/"});';
  final encoded = base64Encode(utf8.encode(payload));
  return '<html><body><div id="readerarea"></div>'
      '<script src="data:text/javascript;base64,$encoded"></script>'
      '</body></html>';
}

void main() {
  group('fetchChapterImages() — obscured reader markup', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('extracts <img> stashed inside <noscript>', () async {
      _mockChapter(dioAdapter, _noscriptHtml);
      final chapter = await adapter.fetchChapterImages(
        'ch-1',
        _configWithReader({
          'images': {'selector': '#readerarea img', 'attribute': 'src'},
        }),
      );
      expect(chapter, isNotNull);
      expect(
        chapter!.images,
        [
          'https://cdn.example.com/p/001.jpg',
          'https://cdn.example.com/p/002.jpg'
        ],
      );
    });

    test('decodes base64 ts_reader script before tsReaderRegex', () async {
      _mockChapter(dioAdapter, _base64TsReaderHtml());
      final chapter = await adapter.fetchChapterImages(
        'ch-1',
        _configWithReader({
          'tsReaderRegex': r'ts_reader\.run\((\{.*?\})\);',
          'images': {'selector': '#readerarea img', 'attribute': 'src'},
        }),
      );
      expect(chapter, isNotNull);
      expect(
        chapter!.images,
        [
          'https://cdn.example.com/c/01.webp',
          'https://cdn.example.com/c/02.webp',
          'https://cdn.example.com/c/03.webp',
        ],
      );
    });
  });
}
