// Regression test for issue #66 — reader next-page BFS threw
// ConcurrentModificationError. `fetchChapterImages` drained a `toFetch` list
// with for-in while appending newly discovered next-links into that same
// list, so aggregation aborted after page 2 and long galleries (hentaikun
// `/read/N/`, 66 pages) could never be read.
//
// Fixed by draining the queue through an index cursor with a maxPages guard.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
// Run with:
//   dart test packages/kuron_generic/test/adapters/reader_pagination_bfs_test.dart
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/src/adapters/generic_scraper_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_html_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://hentaikun.example.com';

// Sequential next-link reader: page N exposes only a link to page N+1, so the
// aggregator must keep discovering through the BFS rather than from a
// truncated first-page link list.
String _pageHtml(int page, {int? next}) {
  final nextLink = next == null
      ? '<span class="end-of-gallery">End</span>'
      : '<div class="page-link">'
          '<a class="post-page-numbers" href="$_baseUrl/read/$next/">Next</a>'
          '</div>';
  return '<html><body>'
      '<div id="readerarea">'
      '<img src="https://cdn.example.com/${page}_a.jpg" />'
      '<img src="https://cdn.example.com/${page}_b.jpg" />'
      '</div>$nextLink</body></html>';
}

const _config = {
  'source': 'hentaikun',
  'baseUrl': _baseUrl,
  'scraper': {
    'urlPatterns': {
      'detail': '/series/{id}/',
      'chapter': '/read/{id}/',
    },
    'selectors': {
      'reader': {
        'container': '#readerarea',
        'images': {'selector': '#readerarea img', 'attribute': 'src'},
        'pagination': {
          'next': '.page-link a.post-page-numbers',
          'maxPages': 5,
        },
      },
    },
  },
};

GenericScraperAdapter _buildAdapter(Dio dio) => GenericScraperAdapter(
      dio: dio,
      urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
      parser: GenericHtmlParser(logger: Logger(level: Level.off)),
      logger: Logger(level: Level.off),
      sourceId: 'hentaikun',
    );

void main() {
  group('fetchChapterImages() — sequential next-page BFS (issue #66)', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericScraperAdapter adapter;

    // Pages actually requested during the test, in BFS order.
    final requested = <String>[];

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
      requested.clear();
    });

    /// Mock one gallery page. Each served page is recorded in [requested], so
    /// the assertions see the real BFS walk, not the pre-registered routes.
    void mockChain(int pageCount) {
      for (var p = 1; p <= pageCount; p++) {
        final next = p < pageCount ? p + 1 : null;
        dioAdapter.onGet(
          '$_baseUrl/read/$p/',
          (s) => s.replyCallback(200, (options) {
            requested.add(options.uri.toString());
            return _pageHtml(p, next: next);
          }, headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          }),
        );
      }
    }

    test('aggregates images across 4 sequential pages without throwing',
        () async {
      mockChain(4);

      final chapter = await adapter.fetchChapterImages('1', _config);

      expect(chapter, isNotNull);
      expect(
        chapter!.images,
        [
          for (var p = 1; p <= 4; p++) ...[
            'https://cdn.example.com/${p}_a.jpg',
            'https://cdn.example.com/${p}_b.jpg',
          ],
        ],
        reason: 'BFS must reach page 4, not abort at page 2',
      );
      expect(requested, hasLength(4));
    });

    test('stops at maxPages and does not fetch beyond the guard', () async {
      mockChain(8);

      final chapter = await adapter.fetchChapterImages('1', _config);

      // maxPages=5 → first page + 4 sub-pages = 10 images.
      expect(chapter!.images, hasLength(10));
      expect(requested, hasLength(5));
      expect(requested, isNot(contains('$_baseUrl/read/6/')));
    });
  });
}
