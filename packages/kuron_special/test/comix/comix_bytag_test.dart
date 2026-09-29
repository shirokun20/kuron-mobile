import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';
import 'package:logger/logger.dart';

// Regression: tapping a tag on a comix detail screen navigates with a
// type-prefixed query (`tag:Romance`, produced by
// navigation.tagQueryMapping mode=name). The adapter must resolve it to a
// genre id via /api/v1/tags/search and browse with genres_in[] — sending
// it as keyword=Romance searches TITLES and returns empty (user symptom).
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({String? browseHtml})
      : browseHtml = browseHtml ?? _browseHtml;

  final String browseHtml;
  final List<Uri> browseUrls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri;
    if (url.path == '/api/v1/tags/search') {
      // Live shapes per type. The curated GENRE namespace holds the
      // high-coverage id (23 = 48k items); the TAG namespace holds
      // near-synonym mashups (106871 = 24 items). Genre wins on exact.
      final type = url.queryParameters['type'];
      final q = (url.queryParameters['q'] ?? '').toLowerCase();
      final body = type == 'genre'
          ? (q == 'romance'
              ? '{"result":[{"id":23,"label":"Romance","slug":"romance"}]}'
              : '{"result":[]}')
          : '{"result":[{"id":106871,"label":"Romance","slug":"romance-1"},'
              '{"id":112508,"label":"Romance, Thriller, Drama","slug":"romance-thriller-drama"},'
              '{"id":110061,"label":"Romance | Exclusive","slug":"romance-exclusive"}]}';
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }
    if (url.path == '/browse') {
      browseUrls.add(url);
      return ResponseBody.fromString(
        browseHtml,
        200,
        headers: {
          'content-type': ['text/html']
        },
      );
    }
    return ResponseBody.fromString('not found', 404);
  }

  @override
  void close({bool force = false}) {}
}

const _mangaJson =
    '{"hid":"5r8qz","title":"Island","poster":{"large":"https://static.comix.to/l.jpg"}}';

const _browseHtml =
    '<html><head></head><body><script id="initial-data" type="application/json">'
    '{"queries":{"q0":{"result":{"items":[$_mangaJson],"meta":{"page":1,"lastPage":1}}}}}'
    '</script></body></html>';

// Live by-tag shape: romance genre page 1 carries the full meta envelope
// (48.536 items / 1734 pages) — the UI pagination must reflect it instead
// of falling back to "Page 1 of 1".
const _browseHtmlPaged =
    '<html><head></head><body><script id="initial-data" type="application/json">'
    '{"queries":{"q0":{"result":{"items":[$_mangaJson],"meta":{"total":48536,'
    '"perPage":28,"page":1,"lastPage":1734,"from":1,"to":28,'
    '"hasNext":true,"hasPrev":false}}}}}'
    '</script></body></html>';

Map<String, dynamic> _config() => {
      'baseUrl': 'https://comix.to',
      'source': 'comix',
    };

ComixAdapter _adapter(_CapturingAdapter capturing) {
  final dio = Dio()..httpClientAdapter = capturing;
  return ComixAdapter(
    dio: dio,
    engine: WebViewProxyEngine(
      sourceHost: 'comix.to',
      allowedHosts: comixAllowedHosts,
    ),
    logger: Logger(level: Level.off),
  );
}

void main() {
  test('by-tag tap resolves genre id instead of keyword search', () async {
    final capturing = _CapturingAdapter();
    final result = await _adapter(capturing).search(
      const SearchFilter(query: 'tag:Romance', page: 1),
      _config(),
    );
    expect(result.items, hasLength(1));
    expect(capturing.browseUrls, hasLength(1));
    final url = capturing.browseUrls.single;
    // The curated genre id (23), not the low-coverage tag id (106871).
    final genreValues = url.queryParametersAll.entries
        .where((e) => e.key.startsWith('genres_in'))
        .expand((e) => e.value)
        .toList();
    expect(genreValues, ['23']);
    // ...and the raw tag text must NOT leak into a title keyword search.
    expect(url.queryParameters['keyword'], isNull);
    // No rating gate by default: suggestive-only hides safe/erotica/
    // pornographic results on the live API.
    expect(
      url.queryParametersAll.entries
          .where((e) => e.key.startsWith('content_rating'))
          .expand((e) => e.value)
          .toList(),
      containsAll(['safe', 'suggestive', 'erotica', 'pornographic']),
    );
  });

  test('plain title search still uses keyword', () async {
    final capturing = _CapturingAdapter();
    final result = await _adapter(capturing).search(
      const SearchFilter(query: 'crown island', page: 1),
      _config(),
    );
    expect(result.items, hasLength(1));
    final url = capturing.browseUrls.single;
    expect(url.queryParameters['keyword'], 'crown island');
  });

  test('by-tag result exposes meta totals for pagination', () async {
    final capturing = _CapturingAdapter(browseHtml: _browseHtmlPaged);
    final result = await _adapter(capturing).search(
      const SearchFilter(query: 'tag:Romance', page: 1),
      _config(),
    );
    expect(result.items, hasLength(1));
    expect(result.hasNextPage, isTrue);
    expect(result.totalItems, 48536);
    expect(result.totalPages, 1734);
  });

  test('home browse exposes meta totals too', () async {
    // Home/latest goes through the same search() with an empty query.
    final capturing = _CapturingAdapter(browseHtml: _browseHtmlPaged);
    final result = await _adapter(capturing).search(
      const SearchFilter(query: '', page: 1),
      _config(),
    );
    expect(result.items, hasLength(1));
    expect(result.hasNextPage, isTrue);
    expect(result.totalItems, 48536);
    expect(result.totalPages, 1734);
  });
}
