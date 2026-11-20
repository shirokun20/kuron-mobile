import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
import 'package:kuron_special/src/comix/comix_dto.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';
import 'package:logger/logger.dart';

// Regression tests for the `comix.to` obfuscated-bundle rotation that broke
// chapter loading (`PlatformException(WEBVIEW_PROXY, Could not find manga
// API)`): `apicore-*.js` exports/method names rotated and string literals
// went through an `oE(...)` lookup, so `fn.toString()` no longer contained
// `'$g'`, `'chapters'`, or `'/chapters'`. A second device-tested round
// hardened this further: signed responses arrive encrypted (`{"e":"..."}`,
// invisible to fetch/XHR text hooks until apicore decrypts them) and the
// chapters export sits at #39 of 46 behind hanging exports (sequential 8s
// probes burned the 60s deadline before reaching it).
//
// The fix captures structurally instead of by symbol name:
// - `buildChapterListScript` boots the SPA and hooks fetch/XHR for
//   `/manga/` (or `/api/`) + `chapters`; an encrypted chapters response
//   arms a short gated `JSON.parse` window for the decrypted re-parse.
// - Behavioral `apicore-*.js` probing is arity-first, batched, and
//   short-timed-out (identity from observed network behavior, never from
//   names or stringified source). Items post verbatim; Dart normalizes them.
// - `ComixChapter.fromJson` / `ChapterPagesResponse` fall back to
//   structural field inference when every known key alias misses.

class _TitleClient implements HttpClientAdapter {
  _TitleClient(this.html);

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

const _titleHtml = '''
<html><head>
<script type="module" src="/dist/main-abc123.js"></script>
</head><body><h1>Crown</h1></body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = {'source': 'comix', 'baseUrl': 'https://comix.to'};
  const channel = MethodChannel('kuron_native');
  late Object payload;
  late Map<String, dynamic> arguments;

  setUp(() {
    payload = [];
    arguments = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'runProxyWebView');
      arguments = Map<String, dynamic>.from(call.arguments as Map);
      return jsonEncode({'payload': jsonEncode(payload), 'material': null});
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ComixAdapter comixAdapter(_TitleClient client) => ComixAdapter(
        dio: Dio()..httpClientAdapter = client,
        engine: WebViewProxyEngine(
          sourceHost: 'comix.to',
          allowedHosts: comixAllowedHosts,
          logger: Logger(level: Level.off),
        ),
        logger: Logger(level: Level.off),
      );

  test('chapter script never matches on names or fn source', () {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('n93ny'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: 991122,
    );
    expect(script, contains('/manga/'));
    expect(script, contains('chapters'));
    expect(script, contains('XMLHttpRequest'));
    expect(script, contains('Reflect.apply'));
    expect(script, contains('991122'));
    // Encrypted-response gate arms JSON.parse capture for the decrypt.
    expect(script, contains('decryptWindowUntil'));
    expect(script, contains('__comixChaptersParseInstalled'));
    expect(script, contains('noteEncrypted'));
    // Arity-first probe in fast concurrent batches, no 8s stalls.
    expect(script, contains('batchSize'));
    expect(script, contains('Promise.all'));
    expect(script, contains('arity'));
    expect(script, contains('1500'));
    expect(script, isNot(contains('timeoutAfter(8000)')));
    // Manga/recommendation rejection: manga-only keys + 1-segment URLs.
    expect(script, contains('mangaOnlyKeys'));
    expect(script, contains('latestChapter'));
    expect(script, contains('ratedAvg'));
    expect(script, contains('/title/'));
    // Comment/thread rejection: comment-only keys + endpoint exclusions.
    expect(script, contains('commentOnlyKeys'));
    expect(script, contains('threadId'));
    expect(script, contains('replyCount'));
    expect(script, contains('/threads/'));
    expect(script, contains('/comments'));
    // Probe acceptance requires a fired `/chapters` request — shape alone
    // (which the recommendations API also satisfies) never wins, and
    // unconfirmed batch hits are dropped instead of trusted.
    expect(script, contains('if (!firedChapters(mark)) return null'));
    expect(script, isNot(contains('firedChapters(mark) || looksChapters')));
    expect(script, isNot(contains('return hits[j]')));
    // DOM-first collection: SSR list + npager pagination.
    expect(script, contains('.mchap-list'));
    expect(script, contains('npager'));
    expect(script, contains('mchap-row__primary'));
    expect(script, contains('collectDomChapters'));
    expect(script, isNot(contains(r'$g')));
    expect(script, isNot(contains(r'$Q')));
    expect(script, isNot(contains('fetchChapters')));
    expect(script, isNot(contains('mangaApi')));
    expect(script, isNot(contains('toString')));
  });
  test('ComixChapter parses fully-rotated keys structurally', () {
    final chapter = ComixChapter.fromJson({
      'zz': 991122,
      'qq': 12.0,
      'ww': 'A New Dawn',
      'ee': '/title/n93ny-the-crown/991122-chapter-12',
      'tt': '3 days ago',
      'grp': {'nm': 'Official'},
    });
    expect(chapter.id, 991122);
    expect(chapter.number, 12.0);
    expect(chapter.name, 'A New Dawn');
    expect(chapter.url, '/title/n93ny-the-crown/991122-chapter-12');
    expect(chapter.uploadDate(), isNotNull);
    expect(chapter.displayName(), 'Chapter 12: A New Dawn');
  });

  test('ComixChapter prefers known aliases over structural guess', () {
    final chapter = ComixChapter.fromJson({
      'id': 5,
      'zz': 999,
      'number': 3.0,
      'qq': 7.0,
      'name': 'Real',
      'ww': 'Longer Wrong Name That Must Lose',
    });
    expect(chapter.id, 5);
    expect(chapter.number, 3.0);
    expect(chapter.name, 'Real');
  });

  test('ChapterPagesResponse parses rotated pages envelope', () {
    final response = ChapterPagesResponse.fromJson({
      'result': {
        'pages': {
          'base': 'https://img.example/x/',
          'list': [
            {'link': 'https://img.example/x/1.webp'},
            {'link': 'https://img.example/x/2.webp'},
          ],
        },
      },
    });
    expect(response.baseUrl, 'https://img.example/x/');
    expect(
      response.items.map((e) => e.url).toList(),
      ['https://img.example/x/1.webp', 'https://img.example/x/2.webp'],
    );
  });

  test('fetchChapters keeps SPA bootable and normalizes rotated items',
      () async {
    payload = [
      {
        'zz': 991122,
        'qq': 12.0,
        'ww': 'A New Dawn',
        'ee': '/title/n93ny-the-crown/991122-chapter-12',
        'tt': '3 days ago',
      },
      {
        'zz': 991100,
        'qq': 11.0,
        'ww': 'Old Wounds',
        'ee': '/title/n93ny-the-crown/991100-chapter-11',
        'tt': '10 days ago',
      },
    ];
    final chapters =
        await comixAdapter(_TitleClient(_titleHtml)).fetchChapters(
      'n93ny-the-crown',
      config,
    );
    // The title HTML handed to the WebView still boots the SPA (the
    // capture script needs its signed requests + atob cipher material).
    expect(arguments['html'], contains('/dist/main-abc123.js'));
    expect(
      (arguments['captureScript'] as String),
      contains('/manga/'),
    );
    expect(chapters, hasLength(2));
    expect(chapters[0].id, '991122:n93ny-the-crown');
    expect(chapters[0].title, 'Chapter 12: A New Dawn');
    expect(chapters[1].id, '991100:n93ny-the-crown');
    expect(chapters[1].uploadDate, isNotNull);
  });

  test('page probe is arity-first batched without 8s stalls', () {
    final script = buildPageListScript(
      passPayloadName: 'passC',
      chapterIdJson: '11737225',
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
    );
    expect(script, contains('batchSize'));
    expect(script, contains('Promise.all'));
    expect(script, contains('arity'));
    expect(script, isNot(contains('timeoutAfter(8000)')));
    expect(script, isNot(contains('chapterApi')));
    expect(script, isNot(contains('toString')));
    // DOM-first reader collection: lazy `.rpage-page` scroll collector.
    expect(script, contains('.rpage-page'));
    expect(script, contains('scrollIntoView'));
    expect(script, contains('data-page'));
    expect(script, contains('collectDomPages'));
  });

  // Live-device failure, reproduced headlessly: signed chapters responses
  // arrive as `{"e":"..."}` (fetch/XHR text has no items), and apicore only
  // reveals the chapters list when it re-parses the decrypted plaintext.
  // The harness below runs the REAL generated script in node with stubbed
  // browser globals: an unrelated chapters-shaped parse BEFORE any
  // encrypted response must not win, then an encrypted chapters fetch
  // followed by the decrypted re-parse must deliver the items.
  test('encrypted fetch arms gated JSON.parse capture (node e2e)',
      () async {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('n93ny'),
      mainScriptUrlJson: jsonEncode(''),
      latestChapterId: null,
    );
    final dir = await Directory.systemTemp.createTemp('comix_e2e_');
    try {
      final scriptFile = File('${dir.path}/capture.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/harness.js')
        ..writeAsStringSync(_nodeHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 60));
      expect(
        result.stdout,
        contains('E2E_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
      expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  // Live-device failure, reproduced headlessly: an earlier apicore export
  // (recommendations/related API) returns item arrays WITHOUT firing any
  // `/chapters` request, while the real chapters export sits at #39 behind
  // hanging exports. The harness runs the REAL generated script with the
  // dynamic import intercepted to a fake 46-export module: only the export
  // that fires `/chapters` AND returns chapter items may win, and manga
  // objects must never count as chapters.
  test('probe ignores rec exports, selects chapters firer (node e2e)',
      () async {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('7gjzm'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
    );
    final dir = await Directory.systemTemp.createTemp('comix_probe_');
    try {
      final scriptFile = File('${dir.path}/capture.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/probe.js')
        ..writeAsStringSync(nodeProbeHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 120));
      expect(
        result.stdout,
        contains('PROBE_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
      expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  // Live-device observation: page-1 chapters are SSR-rendered in
  // `.mchap-list .mchap-item`, so no API call is needed — scrape the DOM
  // and drive `.npager` pagination. Runs the REAL generated script.
  test('chapter DOM collector scrapes list and npager (node e2e)', () async {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('7gjzm'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
    );
    final dir = await Directory.systemTemp.createTemp('comix_domch_');
    try {
      final scriptFile = File('${dir.path}/capture.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/domch.js')
        ..writeAsStringSync(nodeDomChapterHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 60));
      expect(
        result.stdout,
        contains('DOMCH_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
      expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  // Live-device observation: all 28 reader pages render as `.rpage-page`
  // divs with lazy `img.rpage-page__img`; scrolling each into view
  // materializes every src. Runs the REAL generated script.
  test('reader DOM collector scrolls lazy pages (node e2e)', () async {
    final script = buildPageListScript(
      passPayloadName: 'passC',
      chapterIdJson: '11261869',
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
    );
    final dir = await Directory.systemTemp.createTemp('comix_dompg_');
    try {
      final scriptFile = File('${dir.path}/pages.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/dompg.js')
        ..writeAsStringSync(nodeDomPagesHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 60));
      expect(
        result.stdout,
        contains('DOMPG_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
    expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  // Live-device hang: a broken/0-page chapter (no `.rpage-page`, no API
  // payload) never settled, hanging until the 120s native timeout. The
  // script must reject ~5s after DOM + probe finish instead.
  test('empty reader fails fast instead of hanging (node e2e)', () async {
    final script = buildPageListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      chapterIdJson: '2449063',
      mainScriptUrlJson: jsonEncode(''),
    );
    final dir = await Directory.systemTemp.createTemp('comix_pgempty_');
    try {
      final scriptFile = File('${dir.path}/pages.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/pgempty.js')
        ..writeAsStringSync(nodeEmptyPagesHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 60));
      expect(
        result.stdout,
        contains('PGEMPTY_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
      expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('custom webviewSelectors overrides are injected into scripts', () {
    final chapter = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('n93ny'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
      selectors: const {
        'item': '.x-list .x-item',
        'pagerButton': 'nav.x-pager .x-num',
      },
    );
    // Overrides win...
    expect(chapter, contains(jsonEncode('.x-list .x-item')));
    expect(chapter, contains(jsonEncode('nav.x-pager .x-num')));
    expect(chapter, isNot(contains(jsonEncode('.mchap-list .mchap-item'))));
    // ...while omitted keys fall back to the engine defaults.
    expect(chapter, contains(jsonEncode('a.mchap-row__primary')));
    expect(chapter, contains(jsonEncode('.mchap-row__likes')));

    final page = buildPageListScript(
      passPayloadName: 'passC',
      chapterIdJson: '11261869',
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      selectors: const {'pageContainer': '.x-page'},
    );
    expect(page, contains(jsonEncode('.x-page')));
    expect(page, isNot(contains(jsonEncode('.rpage-page'))));
    expect(page, contains(jsonEncode('img.rpage-page__img')));
    expect(page, contains(jsonEncode('data-page')));

    // Injection is jsonEncode-escaped: a quote-breaking selector can not
    // break out of the JS string literal.
    const sneaky = 'a";b';
    final sneakyScript = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('n93ny'),
      mainScriptUrlJson: jsonEncode('https://comix.to/dist/main-x.js'),
      latestChapterId: null,
      selectors: const {'link': sneaky},
    );
    expect(sneakyScript, contains(jsonEncode(sneaky)));
    expect(sneakyScript, isNot(contains(sneaky)));
  });

  // Live-device finding: `GET /api/v1/manga/{id}/chapters` can answer
  // `HTTP 403 {"error":"captcha_required","challenge":"/@waf/challenge"}`
  // while the SSR `.mchap-list` is absent. The script must reject
  // immediately with `CAPTCHA_REQUIRED:<path>` instead of waiting 30s.
  test('403 captcha_required rejects fast with challenge path (node e2e)',
      () async {
    final script = buildChapterListScript(
      passPayloadName: 'passC',
      rejectName: 'rejectD',
      mangaIdJson: jsonEncode('nnl80'),
      mainScriptUrlJson: jsonEncode(''),
      latestChapterId: null,
    );
    final dir = await Directory.systemTemp.createTemp('comix_waf_');
    try {
      final scriptFile = File('${dir.path}/capture.js')
        ..writeAsStringSync(script);
      final harnessFile = File('${dir.path}/waf.js')
        ..writeAsStringSync(nodeWafHarness);
      final result = await Process.run(
        'node',
        [harnessFile.path, scriptFile.path],
      ).timeout(const Duration(seconds: 60));
      expect(
        result.stdout,
        contains('WAF_PASS'),
        reason: 'exit=${result.exitCode}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
      expect(result.exitCode, 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

/// Node harness: stubs `window`/`document`/`XMLHttpRequest`/`fetch`, evals
/// the generated capture script, then replays the device-observed flow.
/// No `$` interpolation or backslash escapes are used, so this stays a
/// plain Dart string.
const _nodeHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
global.document = {querySelector: () => null, querySelectorAll: () => []};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get response() { return null; }
};
const ENCRYPTED = '{"e":"' + 'x'.repeat(200) + '"}';
window.fetch = async (url) => {
  const u = String((url && url.url) || url || '');
  return {url: u, ok: true, clone() { return {text: async () => ENCRYPTED}; }};
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('E2E_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  // Let the DOM wait (empty here) and probe skip finish first, so the
  // passive hooks below run with probeDone=true like on device.
  await sleep(6000);
  if (calls.reject.length > 0) fail('early reject: ' + calls.reject[0]);
  // 1. Unrelated chapters-shaped JSON with no encrypted response open:
  //    must NOT capture (blind wins would poison the chapter list).
  JSON.parse('{"items":[{"id":1,"number":1,"name":"Stray"}],"meta":{"hasNext":false}}');
  await sleep(300);
  if (calls.pass.length > 0) fail('blind JSON.parse won without decrypt window');
  // 2. Encrypted signed chapters response over fetch...
  await window.fetch('https://comix.to/api/v1/manga/n93ny/chapters?page=1&limit=5');
  await sleep(300);
  // 2b. Recommendations parsed DURING the open window must still lose:
  //     manga-only keys + 1-segment /title/ URLs reject them.
  JSON.parse('{"items":[{"id":42789,"hid":"zdq96","title":"Ikenai! Runa-sensei R","poster":{"small":"x"},"latestChapter":4,"ratedAvg":8.4,"synopsis":"s","contentRating":"safe","altTitles":["a"],"url":"/title/rg28-ikenai-runa-sensei-r"}],"meta":{"hasNext":false}}');
  await sleep(300);
  if (calls.pass.length > 0) fail('recommendations won during decrypt window');
  // 2c. Comments parsed DURING the open window must still lose: comment-only
  //     keys (threadId/body/user/...) reject thread payloads as chapters.
  JSON.parse('{"status":"ok","result":{"items":[{"id":3182907,"threadId":19782,"body":"Art style changes every 5 chapters","user":{"name":"u"},"createdAt":"2026-01-01"}],"meta":{"hasNext":false}}}');
  await sleep(300);
  if (calls.pass.length > 0) fail('comments won during decrypt window');
  // 3. ...followed by apicore re-parsing the decrypted plaintext.
  JSON.parse('{"items":[{"id":991122,"number":12,"name":"A New Dawn"}],"meta":{"hasNext":false}}');
  await sleep(9500);
  if (calls.reject.length > 0) fail('rejected: ' + calls.reject[0]);
  if (calls.pass.length !== 1) fail('expected 1 payload, got ' + calls.pass.length);
  if (calls.pass[0].indexOf('991122') === -1) fail('payload missing chapter id: ' + calls.pass[0]);
  if (calls.pass[0].indexOf('A New Dawn') === -1) fail('payload missing chapter name');
  if (calls.pass[0].indexOf('42789') !== -1) fail('recommendations leaked into payload');
  if (calls.pass[0].indexOf('3182907') !== -1) fail('comments leaked into payload: ' + calls.pass[0]);
  if (calls.pass[0].indexOf('Art style') !== -1) fail('comment body leaked into payload');
  console.log('E2E_PASS');
  process.exit(0);
})().catch((e) => fail('harness error: ' + ((e && e.stack) || e)));
''';

/// Node harness for the probe race: 46 fake apicore exports with the
/// recommendations API early (returns manga items, fires nothing), a
/// chapter-shaped decoy firing a NON-chapters URL, hanging exports, and
/// the real chapters export at #39. Only the `/chapters` firer may win.
/// No `$` interpolation or backslash escapes are used, so this stays a
/// plain Dart string.
const nodeProbeHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
const startedAt = Date.now();
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
global.document = {querySelector: () => null, querySelectorAll: () => []};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get response() { return null; }
};
window.fetch = async (url) => {
  const u = String((url && url.url) || url || '');
  if (u.indexOf('main-') !== -1) {
    return {url: u, ok: true, text: async () => 'import x from "./apicore-zzz.js";'};
  }
  return {url: u, ok: true, text: async () => '{}', clone() { return {text: async () => '{}'}; }};
};
// The script's driver uses bare `fetch` (== window.fetch in a WebView);
// alias it so the stub serves the main bundle in node too.
global.fetch = window.fetch;
const REC = {id: 42789, hid: 'zdq96', title: 'Ikenai! Runa-sensei R', poster: {small: 'x', large: 'y'}, latestChapter: 4, ratedAvg: 8.4, synopsis: 's', contentRating: 'safe', altTitles: ['a'], url: '/title/rg28-ikenai-runa-sensei-r'};
const CH = {id: 4988, number: 8.4, name: 'Ch 8.4', url: '/title/7gjzm-slug/4988-chapter-8.4'};
const fakeEnv = {};
for (let i = 0; i < 46; i++) {
  if (i === 5) {
    fakeEnv['e' + i] = {recs: async (a, b) => ({items: [REC], meta: {hasNext: false}})};
  } else if (i === 7) {
    fakeEnv['e' + i] = {rel: async (a, b) => { await window.fetch('https://comix.to/api/v1/manga/related'); return {items: [{id: 111, number: 1, name: 'Fake'}]}; }};
  } else if (i === 39) {
    fakeEnv['io'] = {io_e7: async (a, b) => { const r = await window.fetch('https://comix.to/api/v1/manga/7gjzm/chapters?page=1&limit=5'); await r.text(); return {items: [CH], meta: {hasNext: false}}; }};
  } else if (i % 3 === 0) {
    fakeEnv['e' + i] = {h: async (a, b) => new Promise(() => {})};
  } else if (i % 3 === 1) {
    fakeEnv['e' + i] = {t: async (a, b) => { throw new Error('nope'); }};
  } else {
    fakeEnv['e' + i] = {j: (a, b) => 42};
  }
}
const RealFunction = Function;
global.Function = function (...args) {
  if (args.length === 2 && args[1] === 'return import(url)') {
    return () => Promise.resolve(fakeEnv);
  }
  return new RealFunction(...args);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('PROBE_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  for (let waited = 0; waited < 60000; waited += 500) {
    await sleep(500);
    if (calls.pass.length > 0 || calls.reject.length > 0) break;
  }
  const elapsed = Date.now() - startedAt;
  if (calls.reject.length > 0) fail('rejected: ' + calls.reject[0]);
  if (calls.pass.length !== 1) fail('expected 1 payload, got ' + calls.pass.length + ' after ' + elapsed + 'ms');
  if (calls.pass[0].indexOf('4988') === -1) fail('chapters export did not win: ' + calls.pass[0]);
  if (calls.pass[0].indexOf('42789') !== -1) fail('recommendations leaked into payload');
  if (calls.pass[0].indexOf('"id":111') !== -1) fail('non-chapters decoy leaked into payload');
  if (elapsed > 45000) fail('probe too slow: ' + elapsed + 'ms');
  console.log('PROBE_PASS in ' + elapsed + 'ms');
  process.exit(0);
})();
''';

/// Node harness for the chapter DOM collector: fake `.mchap-list` across
/// two `.npager` pages and verify the scraped + paginated payload.
const nodeDomChapterHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
const startedAt = Date.now();
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
const mkLi = (d) => ({querySelector: (sel) => {
  if (sel.indexOf('mchap-row__primary') !== -1) return {getAttribute: (a) => a === 'href' ? d.href : null};
  if (sel.indexOf('mchap-row__ch') !== -1) return {textContent: d.ch};
  if (sel.indexOf('mchap-row__title') !== -1) return {textContent: d.title};
  if (sel.indexOf('mchap-row__time') !== -1) return {textContent: d.time};
  if (sel.indexOf('mchap-row__group') !== -1) return d.group ? {textContent: d.group, getAttribute: (a) => a === 'href' ? d.groupHref : null} : null;
  if (sel.indexOf('mchap-row__likes') !== -1) return {textContent: d.likes};
  return null;
}});
const domPages = {
  1: [
    mkLi({href: '/title/7gjzm-slug/11261869-chapter-40', ch: 'Ch. 40', title: 'Dawn', time: '3 days ago', group: 'Scan', groupHref: '/groups/10702-x', likes: '12'}),
    mkLi({href: '/title/7gjzm-slug/11261868-chapter-39', ch: 'Ch. 39', title: 'Dusk', time: '10 days ago', group: '', groupHref: '', likes: '5'}),
  ],
  2: [
    mkLi({href: '/title/7gjzm-slug/11261867-chapter-38', ch: 'Ch. 38', title: '', time: '1 month ago', group: 'Official', groupHref: '/groups/9', likes: '1,024'}),
  ],
};
let currentPage = 1;
const firstHref = () => domPages[currentPage][0].querySelector('a.mchap-row__primary').getAttribute('href');
global.document = {
  querySelector: (sel) => {
    if (sel.indexOf('is-active') !== -1) return {textContent: ' ' + currentPage + ' '};
    if (sel.indexOf('mchap-row__primary') !== -1) return {getAttribute: () => firstHref()};
    return null;
  },
  querySelectorAll: (sel) => {
    if (sel.indexOf('mchap-item') !== -1) return domPages[currentPage] || [];
    if (sel.indexOf('npager__num') !== -1) return [
      {textContent: '1', click: () => { currentPage = 1; }},
      {textContent: '2', click: () => { currentPage = 2; }},
    ];
    return [];
  },
};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get response() { return null; }
};
window.fetch = async () => ({url: '', ok: false, text: async () => ''});
global.fetch = window.fetch;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('DOMCH_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  for (let waited = 0; waited < 30000; waited += 500) {
    await sleep(500);
    if (calls.pass.length > 0 || calls.reject.length > 0) break;
  }
  const elapsed = Date.now() - startedAt;
  if (calls.reject.length > 0) fail('rejected: ' + calls.reject[0]);
  if (calls.pass.length !== 1) fail('expected 1 payload, got ' + calls.pass.length);
  for (const id of ['11261869', '11261868', '11261867']) {
    if (calls.pass[0].indexOf(id) === -1) fail('payload missing chapter ' + id + ': ' + calls.pass[0]);
  }
  if (calls.pass[0].indexOf('Dawn') === -1) fail('payload missing title');
  if (calls.pass[0].indexOf('1024') === -1) fail('payload missing parsed votes');
  if (elapsed > 20000) fail('DOM collection too slow: ' + elapsed + 'ms');
  console.log('DOMCH_PASS in ' + elapsed + 'ms');
  process.exit(0);
})();
''';

/// Node harness for the reader DOM collector: 5 `.rpage-page` divs, the
/// last three lazy (img appears on scrollIntoView). Verifies ordered urls.
const nodeDomPagesHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
const startedAt = Date.now();
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
const mkPage = (n, eager) => {
  let src = eager ? 'https://img/x/' + n + '.webp' : '';
  return {
    getAttribute: (a) => a === 'data-page' ? String(n) : null,
    querySelector: (s) => src ? {getAttribute: (a) => src} : null,
    scrollIntoView: (o) => { src = src || ('https://img/x/' + n + '.webp'); },
  };
};
const domPages = [mkPage(1, true), mkPage(2, true), mkPage(3, false), mkPage(4, false), mkPage(5, false)];
global.document = {
  querySelector: () => null,
  querySelectorAll: (sel) => sel.indexOf('rpage-page') !== -1 ? domPages : [],
};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get response() { return null; }
};
window.fetch = async () => ({url: '', ok: false, text: async () => ''});
global.fetch = window.fetch;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('DOMPG_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  for (let waited = 0; waited < 30000; waited += 500) {
    await sleep(500);
    if (calls.pass.length > 0 || calls.reject.length > 0) break;
  }
  const elapsed = Date.now() - startedAt;
  if (calls.reject.length > 0) fail('rejected: ' + calls.reject[0]);
  if (calls.pass.length !== 1) fail('expected 1 payload, got ' + calls.pass.length);
  let parsed = null;
  try {
    parsed = JSON.parse(calls.pass[0]);
  } catch (e) {
    fail('payload is not JSON');
  }
  const items = parsed && parsed.result && parsed.result.pages && parsed.result.pages.items;
  if (!items || items.length !== 5) fail('expected 5 page items, got ' + JSON.stringify(calls.pass[0]).slice(0, 200));
  for (let n = 1; n <= 5; n++) {
    if (items[n - 1].url !== 'https://img/x/' + n + '.webp') fail('page ' + n + ' out of order: ' + items[n - 1].url);
  }
  if (elapsed > 20000) fail('DOM collection too slow: ' + elapsed + 'ms');
  console.log('DOMPG_PASS in ' + elapsed + 'ms');
  process.exit(0);
})();
''';

/// Node harness for the WAF challenge fast-reject: the chapters API answers
/// `HTTP 403 {"error":"captcha_required","challenge":"/@waf/challenge"}`
/// while the DOM has no chapters. Runs the REAL generated script.
const nodeWafHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
const startedAt = Date.now();
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
global.document = {querySelector: () => null, querySelectorAll: () => []};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get status() { return 200; }
  get response() { return '{}'; }
};
window.fetch = async (url) => {
  const u = String((url && url.url) || url || '');
  if (u.indexOf('chapters') !== -1) {
    return {
      url: u, status: 403, ok: false,
      clone() { return {text: async () => '{"error":"captcha_required","challenge":"/@waf/challenge"}'}; },
      text: async () => '{"error":"captcha_required","challenge":"/@waf/challenge"}',
    };
  }
  return {url: u, status: 200, ok: true, clone() { return {text: async () => '{}'}; }, text: async () => '{}'};
};
global.fetch = window.fetch;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('WAF_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  await sleep(6000);
  if (calls.pass.length > 0) fail('unexpected payload before chapters fetch');
  await window.fetch('https://comix.to/api/v1/manga/nnl80/chapters?page=1&limit=5');
  for (let waited = 0; waited < 25000; waited += 250) {
    await sleep(250);
    if (calls.pass.length > 0 || calls.reject.length > 0) break;
  }
  const elapsed = Date.now() - startedAt;
  if (calls.pass.length > 0) fail('captured payload instead of rejecting: ' + calls.pass[0]);
  if (calls.reject.length !== 1) fail('expected 1 rejection, got ' + calls.reject.length);
  if (calls.reject[0].indexOf('CAPTCHA_REQUIRED:/@waf/challenge') === -1) {
    fail('wrong rejection (waited ' + elapsed + 'ms): ' + calls.reject[0]);
  }
  if (elapsed > 15000) fail('rejection too slow: ' + elapsed + 'ms');
  console.log('WAF_PASS in ' + elapsed + 'ms');
  process.exit(0);
})();
''';

/// Node harness for the empty-reader fast-fail: no `.rpage-page` divs and
/// no API payload. The script must reject within ~20s (5s grace after the
/// DOM wait) instead of hanging until the 120s native timeout.
const nodeEmptyPagesHarness = '''
const fs = require('fs');
const scriptSrc = fs.readFileSync(process.argv[2], 'utf8');
const calls = {pass: [], reject: []};
const startedAt = Date.now();
global.window = {};
window.passC = (payload) => { calls.pass.push(String(payload)); };
window.rejectD = (err) => { calls.reject.push(String((err && err.message) || err)); };
global.document = {querySelector: () => null, querySelectorAll: () => []};
global.XMLHttpRequest = class {
  open(method, url) { this.__url = String(url || ''); }
  send() {}
  addEventListener() {}
  get status() { return 200; }
  get response() { return '{}'; }
};
window.fetch = async (url) => {
  const u = String((url && url.url) || url || '');
  return {url: u, status: 200, ok: false, clone() { return {text: async () => '{}'}; }, text: async () => '{}'};
};
global.fetch = window.fetch;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (msg) => { console.log('PGEMPTY_FAIL: ' + msg); process.exit(1); };
(async () => {
  (0, eval)(scriptSrc);
  for (let waited = 0; waited < 40000; waited += 500) {
    await sleep(500);
    if (calls.pass.length > 0 || calls.reject.length > 0) break;
  }
  const elapsed = Date.now() - startedAt;
  if (calls.pass.length > 0) fail('captured payload for empty reader: ' + calls.pass[0]);
  if (calls.reject.length !== 1) fail('expected 1 rejection, got ' + calls.reject.length + ' after ' + elapsed + 'ms');
  if (calls.reject[0].indexOf('Could not capture reader pages') === -1) {
    fail('wrong rejection (waited ' + elapsed + 'ms): ' + calls.reject[0]);
  }
  if (elapsed > 30000) fail('rejection too slow (hung like the 120s bug): ' + elapsed + 'ms');
  console.log('PGEMPTY_PASS in ' + elapsed + 'ms');
  process.exit(0);
})();
''';
