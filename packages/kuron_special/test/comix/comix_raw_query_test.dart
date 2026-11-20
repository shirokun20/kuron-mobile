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
// - `buildChapterListScript` captures chapters without relying on
//   obfuscated `apicore-*.js` symbol names (behavioral probing +
//   endpoint-URL hooks instead of the minified `$Q` function lookup).
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

const _comixShellHtml = '<html><head></head><body></body></html>';

/// Routes comix requests: tag-search and titles APIs get live-shaped JSON,
/// everything else gets a data-less shell (Tier-2 scrape finds nothing).
class _ComixApiClient implements HttpClientAdapter {
  final List<Uri> requested = [];
  final Map<Uri, Map<String, dynamic>> requestHeaders = {};
  static const tagJson =
      '{"result":[{"id":23,"label":"Romance","slug":"romance"}]}';
  static const titlesJson =
      '{"status":"ok","result":{"items":[{"hid":"n93ny","title":"The Crown I Will Claim",'
      '"type":"manhwa","status":"releasing","originalLanguage":"",'
      '"poster":{"medium":"/images/covers/49/3a/x@280.jpg","large":"/images/covers/49/3a/x.jpg"}}],'
      '"meta":{"total":1,"perPage":28,"page":1,"lastPage":1,"hasNext":false}}}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    requestHeaders[options.uri] = Map<String, dynamic>.from(options.headers);
    final path = options.uri.path;
    if (path.contains('tags/search')) {
      return ResponseBody.fromString(tagJson, 200);
    }
    if (path == '/api/v1/manga') {
      return ResponseBody.fromString(titlesJson, 200,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(_comixShellHtml, 200);
  }

  @override
  void close({bool force = false}) {}
}

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

  ComixAdapter comixAdapter(HttpClientAdapter client) => ComixAdapter(
        dio: Dio()..httpClientAdapter = client,
        directDio: Dio()..httpClientAdapter = client,
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

  test('comix empty originalLanguage defaults to en with absolute cover', () async {
    // Live `/api/v1/manga` sends `"originalLanguage": ""` for some items
    // and relative poster paths — cards must still show the EN flag and a
    // resolvable cover instead of 'unknown'/empty.
    const html = '''
<html><head></head><body><script id="initial-data">{"queries":{"browse":{
"result":{"items":[{"hid":"g1ml3","title":"The Second Time, Like a Pro",
"type":"manhwa","status":"releasing","originalLanguage":"",
"poster":{"medium":"/images/covers/3d/06/xxx@280.jpg",
"large":"/images/covers/3d/06/xxx.jpg"}}],
"meta":{"page":1,"lastPage":1}}}}}</script></body></html>
''';
    final client = _RecordingClient(html);
    final result = await comixAdapter(
      client,
    ).search(const SearchFilter(query: 'raw:keyword=the'), comixConfig);
    expect(result.items, hasLength(1));
    final item = result.items.first;
    expect(item.language, 'en');
    expect(
      item.coverUrl,
      'https://comix.to/images/covers/3d/06/xxx.jpg',
    );
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

  test('chapter script captures structurally without obfuscated names', () {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('7z7ee'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
    );
    expect(script, contains('(?:env|apicore)'));
    expect(script, contains('env|apicore'));
    // Relaxed endpoint-URL hooks + arity-first batched probing drive capture.
    expect(script, contains('/manga/'));
    expect(script, contains('chapters'));
    expect(script, contains('XMLHttpRequest'));
    expect(script, contains('Reflect.apply'));
    expect(script, contains('decryptWindowUntil'));
    expect(script, contains('batchSize'));
    expect(script, contains('Promise.all'));
    expect(script, contains('1500'));
    // No reliance on rotated export/property names or fn source text, and
    // no sequential 8s probe stalls before late exports are reached.
    expect(script, isNot(contains(r"$Q")));
    expect(script, isNot(contains(r"$g")));
    expect(script, isNot(contains('fetchChapters')));
    expect(script, isNot(contains('mangaApi')));
    expect(script, isNot(contains('toString')));
    expect(script, isNot(contains('timeoutAfter(8000)')));
    // Raw items are posted verbatim; Dart normalizes rotated keys.
    expect(script, contains('JSON.stringify(items)'));
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

  test('page script captures structurally without obfuscated names', () {
    final script = buildPageListScript(passPayloadName: 'passC');
    // URL-verified hooks for the chapter pages endpoint + strict blind
    // JSON.parse capture (base URL required) + behavioral probing.
    expect(script, contains('/api/v1/chapters'));
    expect(script, contains('XMLHttpRequest'));
    expect(script, contains('Reflect.apply'));
    expect(script, contains('initial-data'));
    expect(script, isNot(contains('chapterApi')));
    expect(script, isNot(contains('fetchPages')));
    expect(script, isNot(contains('toString')));
  });

  test('rawConfig drives dynamic genreMapping, searchConfig, and webView initialization', () async {
    payload = {
      'items': [
        {
          'hid': 'dyn1',
          'title': 'Dynamic Title',
          'status': 'releasing',
        }
      ],
      'meta': {'page': 1, 'lastPage': 1},
    };

    final client = _RecordingClient('<html><body>mock</body></html>');
    final dynamicConfig = <String, dynamic>{
      'source': 'mangafire',
      'baseUrl': 'https://mangafire.to',
      'network': {
        'detailTimeoutSeconds': 180,
        'allowedHosts': ['custom.domain.com'],
        'initializationScript': 'console.log("custom-script");',
      },
      'genreMapping': {
        'custom sci fi': '999',
      },
      'searchConfig': {
        'queryParam': 'keyword',
        'sortParam': 'sort',
        'keywordSort': 'custom_keyword_sort:asc',
        'sortValues': {
          'newest': 'custom_date:desc',
        },
        'defaultParams': {
          'content_rating': 'none',
          'custom_filter': 'enabled',
        },
      },
    };

    final adapter = ComixAdapter(
      dio: Dio()..httpClientAdapter = client,
      engine: WebViewProxyEngine(
        sourceHost: 'mangafire.to',
        allowedHosts: mangafireAllowedHosts,
        logger: Logger(level: Level.off),
      ),
      logger: Logger(level: Level.off),
      originKind: 'mangafire',
      configuredDetailTimeoutSeconds:
          (dynamicConfig['network'] as Map)['detailTimeoutSeconds'] as int,
    );

    expect(adapter.detailTimeout, const Duration(seconds: 180));

    // Test 1: Tag query uses dynamic genreMapping
    await adapter.search(
      const SearchFilter(query: 'tag:custom sci fi'),
      dynamicConfig,
    );
    var url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['genres_in'], '999');
    expect(url.queryParameters['custom_filter'], 'enabled');
    expect(
      arguments['bootstrapScript'],
      contains('console.log("custom-script");'),
    );
    expect(arguments['allowedHosts'], contains('custom.domain.com'));

    // Test 2: Sort mapping uses dynamic searchConfig
    await adapter.search(
      const SearchFilter(sort: SortOption.newest),
      dynamicConfig,
    );
    url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'custom_date:desc');

    // Test 3: Keyword search uses dynamic keywordSort
    await adapter.search(
      const SearchFilter(query: 'test query'),
      dynamicConfig,
    );
    url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.queryParameters['sort'], 'custom_keyword_sort:asc');
    expect(url.queryParameters['keyword'], 'test query');
  });

  test('comix genre tap hits direct titles API without WebView', () async {
    final client = _ComixApiClient();
    // Any WebView boot is a failure: the direct API must serve this.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCookies') {
        return 'session=abc123; cf_clearance=xyz';
      }
      throw StateError(
          'Tier-3 WebView must not run when the direct API works');
    });
    try {
      // Mirrors the live path: the repository maps `tag:X` to includeTags
      // with an empty query, so the adapter takes the else-branch and the
      // screen sort (rating here) is applied as order[score].
      final result = await comixAdapter(client).search(
        const SearchFilter(
          query: '',
          sort: SortOption.rating,
          includeTags: [FilterItem(id: 0, name: 'romance', type: 'tag')],
        ),
        comixConfig,
      );
      expect(result.items, hasLength(1));
      final item = result.items.single;
      expect(item.title, 'The Crown I Will Claim');
      expect(item.language, 'en');
      expect(item.coverUrl,
          'https://comix.to/images/covers/49/3a/x.jpg');
      final apiCall = client.requested
          .singleWhere((u) => u.path == '/api/v1/manga');
      expect(apiCall.queryParametersAll['genres_in[]'], ['23']);
      expect(
        apiCall.queryParameters['order[score]'],
        'desc',
      );
      final sentHeaders = client.requestHeaders[apiCall]!;
      expect(sentHeaders['Cookie'], 'session=abc123; cf_clearance=xyz');
      expect(sentHeaders['X-Requested-With'], 'XMLHttpRequest');
      expect(
        (sentHeaders['User-Agent'] as String).contains('Chrome/'),
        isTrue,
      );
    } finally {
      // Restore the suite-wide mock for subsequent tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        arguments = Map<String, dynamic>.from(call.arguments as Map);
        return jsonEncode({'payload': jsonEncode(payload), 'material': null});
      });
    }
  });
}
