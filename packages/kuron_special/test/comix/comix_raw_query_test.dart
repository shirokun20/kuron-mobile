import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';
import 'package:logger/logger.dart';

// Regression tests for the Comix/MangaFire `raw:` query fixes:
//
// - `_parseTypeQuery` rejects `raw:keyword=the` (type `raw` is not a tag
//   kind), so comix never calls `/api/v1/tags/search` with it (was 404).
// - `_mangafireListUri` splits `raw:` into real browse params, so the SPA's
//   own `/api/titles?keyword=the` request matches the capture gate
//   (was a 120s WebView timeout).
// - `buildChapterListScript` matches the new `apicore-*.js` bundle and the
//   minified `$Q` chapters function (was `env-*.js` only).
//
// Private members are verified through the public `search()` API plus the
// generated script strings, mirroring `mangafire_flow_test.dart`.

class _RecordingClient implements HttpClientAdapter {
  _RecordingClient(this.html);

  final String html;
  final List<Uri> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(html, 200);
  }

  @override
  void close({bool force = false}) {}
}

const _comixBrowseHtml = '''
<html><head></head><body><script id="initial-data">{"queries":{"browse":{
"result":{"items":[{"hid":"5r8qz","title":"Island","status":"releasing"}],
"meta":{"page":1,"lastPage":1}}}}}</script></body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mfConfig = {'source': 'mangafire', 'baseUrl': 'https://mangafire.to'};
  const comixConfig = {'source': 'comix', 'baseUrl': 'https://comix.to'};
  const channel = MethodChannel('kuron_native');
  late Object payload;
  late Map<String, dynamic> arguments;

  setUp(() {
    payload = {};
    arguments = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      arguments = Map<String, dynamic>.from(call.arguments as Map);
      return jsonEncode({'payload': jsonEncode(payload), 'material': null});
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ComixAdapter mangafireAdapter(_RecordingClient client) => ComixAdapter(
        dio: Dio()..httpClientAdapter = client,
        engine: WebViewProxyEngine(
          sourceHost: 'mangafire.to',
          allowedHosts: mangafireAllowedHosts,
          logger: Logger(level: Level.off),
        ),
        logger: Logger(level: Level.off),
        defaultBaseUrl: 'https://mangafire.to',
        defaultSourceId: 'mangafire',
        originKind: 'mangafire',
      );

  ComixAdapter comixAdapter(_RecordingClient client) => ComixAdapter(
        dio: Dio()..httpClientAdapter = client,
        engine: WebViewProxyEngine(
          sourceHost: 'comix.to',
          allowedHosts: comixAllowedHosts,
          logger: Logger(level: Level.off),
        ),
        logger: Logger(level: Level.off),
      );

  test('mangafire raw:keyword decodes to a real keyword param', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [
        {'hid': 'ro8ro', 'title': 'One Piece'},
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };
    final result = await mangafireAdapter(
      client,
    ).search(const SearchFilter(query: 'raw:keyword=the'), mfConfig);
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['keyword'], 'the');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(url.queryParameters['content_rating'], 'none');
    expect(arguments['bootstrapScript'], contains('mf_content_prefs'));
    expect(url.queryParameters.containsKey('rawParam'), isFalse);
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);
    expect(url.toString(), isNot(contains('raw')));
    expect(result.items, hasLength(1));
    // No tags/search API call: MangaFire has no such endpoint (was 404).
    expect(
      client.requested.any((u) => u.path.contains('tags/search')),
      isFalse,
    );
  });

  test('mangafire raw:genres_in[] decodes to a real tag param without brackets', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [
        {'hid': 'ro8ro', 'title': 'One Piece'},
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(
      client,
    ).search(const SearchFilter(query: 'raw:genres_in[]=23'), mfConfig);
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['genres_in'], '23');
    expect(url.queryParameters.containsKey('genres_in[]'), isFalse);
    expect(
      client.requested.any((u) => u.path.contains('tags/search')),
      isFalse,
    );
  });

  test('mangafire unrolls rawParam and strips brackets for content_rating and keyword', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [
        {'hid': 'ro8ro', 'title': 'The Honor'},
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(client).search(
      const SearchFilter(
        query: 'raw:keyword=the%20honor&rawParam=content_rating%5B%5D%3Dpornographic',
      ),
      mfConfig,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['keyword'], 'the honor');
    expect(url.queryParameters['content_rating'], 'pornographic');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(url.queryParameters.containsKey('rawParam'), isFalse);
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);
  });

  test('mangafire rawParam order[...] maps to sort and keyword default relevance', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [
        {'hid': 'ro8ro', 'title': 'The Honor Student'},
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(client).search(
      const SearchFilter(
        query:
            'raw:keyword=the%20honor%20student&rawParam=order%5Brelevance%5D%3Ddesc',
      ),
      mfConfig,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['keyword'], 'the honor student');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(url.queryParameters.containsKey('rawParam'), isFalse);
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);
  });

  test('mangafire maps filter.sort to views/chapter_updated_at and keyword overrides to relevance', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [],
      'meta': {'page': 1, 'lastPage': 1},
    };

    await mangafireAdapter(client).search(
      const SearchFilter(query: '', sort: SortOption.popular),
      mfConfig,
    );
    var url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'views_total:desc');

    await mangafireAdapter(client).search(
      const SearchFilter(query: '', sort: SortOption.newest),
      mfConfig,
    );
    url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'chapter_updated_at:desc');
    expect(url.queryParameters['content_rating'], 'none');

    await mangafireAdapter(client).search(
      const SearchFilter(query: 'naruto', sort: SortOption.popular),
      mfConfig,
    );
    url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['keyword'], 'naruto');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(url.queryParameters['content_rating'], 'none');
  });

  test('mangafire defaults content_rating to none so ecchi/erotica/adult titles are unblocked', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [
        {
          'id': 16458,
          'hid': 'w1q37',
          'slug': 'the-honor-students-secret-jobb',
          'title': "The Honor Student's Secret Job",
        },
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };
    final result = await mangafireAdapter(client).search(
      const SearchFilter(query: 'the honor student'),
      mfConfig,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['content_rating'], 'none');
    expect(url.queryParameters['keyword'], 'the honor student');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(arguments['bootstrapScript'], contains('mf_content_prefs'));
    expect(result.items.first.title, "The Honor Student's Secret Job");
  });

  test('mangafire raw sort/order params normalize to sort field:direction', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(client).search(
      const SearchFilter(query: 'raw:keyword=the&sort=views_total:desc'),
      mfConfig,
    );
    var url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'views_total:desc');
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);

    await mangafireAdapter(client).search(
      const SearchFilter(query: 'raw:keyword=the&order[views_total]=desc'),
      mfConfig,
    );
    url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'views_total:desc');
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);
  });

  test('mangafire typed tag query maps known genre name to id without search API', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(
      client,
    ).search(const SearchFilter(query: 'tag:Romance'), mfConfig);
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['genres_in'], '26');
    expect(
      client.requested.any((u) => u.path.contains('tags/search')),
      isFalse,
    );
  });

  test('mangafire includeTags preserves real genre id', () async {
    final client = _RecordingClient('<html></html>');
    payload = {
      'items': [],
      'meta': {'page': 1, 'lastPage': 1},
    };
    await mangafireAdapter(client).search(
      const SearchFilter(
        includeTags: [FilterItem(id: 26, name: 'Romance', type: 'tag')],
      ),
      mfConfig,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['genres_in'], '26');
  });

  test('comix raw: query is not treated as a type query', () async {
    final client = _RecordingClient(_comixBrowseHtml);
    final result = await comixAdapter(
      client,
    ).search(const SearchFilter(query: 'raw:keyword=the'), comixConfig);
    expect(result.items, hasLength(1));
    expect(result.items.first.title, 'Island');
    // `raw` is not a tag kind: no /api/v1/tags/search call (was 404).
    expect(
      client.requested.any((u) => u.path.contains('tags/search')),
      isFalse,
    );
    final browseUrl = client.requested.singleWhere((u) => u.path == '/browse');
    expect(browseUrl.queryParameters['q'], 'the');
    expect(browseUrl.queryParameters['sort'], 'relevance:desc');
    expect(browseUrl.queryParameters['keyword'], isNull);
    expect(browseUrl.toString(), isNot(contains('raw')));
  });

  test('comix raw keyword from DynamicFormSearchUI uses clean q params', () async {
    final client = _RecordingClient(_comixBrowseHtml);
    final result = await comixAdapter(client).search(
      const SearchFilter(query: 'raw:keyword=the+honor+student'),
      comixConfig,
    );
    expect(result.items, hasLength(1));
    final browseUrl = client.requested.singleWhere((u) => u.path == '/browse');
    expect(browseUrl.queryParameters['q'], 'the honor student');
    expect(browseUrl.queryParameters['sort'], 'relevance:desc');
    expect(browseUrl.queryParameters['keyword'], isNull);
    expect(browseUrl.toString(), isNot(contains('raw')));

    final apiParams = comixAdapter(client).nativeMangaParamsForTest(browseUrl);
    expect(apiParams['keyword'], ['the honor student']);
    expect(apiParams['order[relevance]'], ['desc']);
  });

  test('chapter script matches env + apicore bundles and \$Q api', () {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('7z7ee'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
    );
    expect(script, contains('(?:env|apicore)'));
    expect(script, contains('env|apicore'));
    expect(script, contains(r"$Q"));
    expect(script, contains('fetchChapters'));
    // Minified K6 item normalization (id <- Od, number <- Iv, url <- ek, etc.).
    expect(script, contains('response?.K6'));
    expect(script, contains('item.Od'));
    expect(script, contains('item.Iv'));
    expect(script, contains('item.ek'));
    expect(script, contains('item._G'));
    expect(script, contains('item.ux'));
  });

  test('browse script decodes urls before the keyword gate', () {
    final script = buildBrowseScript(
      passPayloadName: 'passC',
      expectedKeywordJson: jsonEncode('the'),
      apiPathMarker: '/api/titles',
    );
    expect(script, contains('decodeURIComponent'));
  });

  test('mangafire honor-student search hits relevance sort and parses live payload', () async {
    // Regression: "The Honor Student's Secret Job" (finished 2012 manga, hid
    // w1q37) was invisible under the old config's default
    // `order[chapter_updated_at]=desc` sort — buried pages deep. With
    // `sort=relevance:desc` it ranks #5 on page 1 of the live
    // `/api/titles?keyword=the+honor+student` response.
    final client = _RecordingClient('<html></html>');
    final items = [
      for (var i = 0; i < 30; i++)
        if (i == 5)
          {
            'id': 16458,
            'hid': 'w1q37',
            'slug': 'the-honor-students-secret-jobb',
            'title': "The Honor Student's Secret Job",
            'type': 'manga',
            'url': '/title/w1q37-the-honor-students-secret-jobb',
            'latestChapter': 78,
            'poster': {
              'small': 'https://cdn.example.com/s.jpg',
              'large': 'https://cdn.example.com/l.jpg',
            },
            'rank': 9278,
            'status': 'finished',
            'year': 2012,
          }
        else
          {
            'hid': 'dummy$i',
            'title': 'Dummy Title $i',
            'url': '/title/dummy$i-dummy-title-$i',
            'status': 'releasing',
          },
    ];
    payload = {
      'items': items,
      'meta': {'page': 1, 'lastPage': 10},
    };
    final result = await mangafireAdapter(
      client,
    ).search(const SearchFilter(query: 'the honor student'), mfConfig);
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['keyword'], 'the honor student');
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(result.items, hasLength(30));
    final hit = result.items[5];
    expect(hit.id, 'w1q37');
    expect(hit.title, "The Honor Student's Secret Job");
    expect(
      hit.url,
      'https://mangafire.to/title/w1q37-the-honor-students-secret-jobb',
    );
  });

  test('page script captures data/pages/top-level shapes', () {
    final script = buildPageListScript(passPayloadName: 'passC');
    expect(script, contains('parsed.result?.pages'));
    expect(script, contains('parsed.data?.pages'));
    expect(script, contains('parsed.pages'));
    expect(script, contains('Array.isArray(parsed.items)'));
  });
}
