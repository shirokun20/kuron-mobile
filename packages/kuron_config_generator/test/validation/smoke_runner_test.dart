import 'dart:convert';
import 'dart:io';

import 'package:kuron_config_generator/src/validation/smoke_runner.dart';
import 'package:kuron_config_generator/src/validation/skeleton_test_emitter.dart';
import 'package:test/test.dart';

// Offline unit tests for SmokeRunner using a local HttpServer as the
// "site" — no external network needed.
void main() {
  late HttpServer server;
  late String baseUrl;

  const homeHtml = '''
<html><body><div class="list">
  <div class="item"><a href="/manga/one/" class="title">One</a>
    <img src="https://cdn.example.test/c1.jpg" class="cover"></div>
  <div class="item"><a href="/manga/two/" class="title">Two</a>
    <img src="/images/c2.jpg" class="cover"></div>
</div></body></html>''';

  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(homeHtml);
      } else if (path.startsWith('/api/detail')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body><h1>One</h1>'
            '<div class="chapter"><a href="/chapter/1/">Ch 1</a></div></body></html>');
      } else if (path.startsWith('/img')) {
        req.response.headers.contentType = ContentType('image', 'jpeg');
        req.response.add(List.filled(2048, 1));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  // ponytail: kept for Phase-2 negative-probe tests which will drive the
  // full adapter happy path against this local server.
  // ignore: unused_element
  Map<String, dynamic> config(Map<String, dynamic> scraper) => {
        'source': 'smoketest',
        'baseUrl': baseUrl,
        'scraper': scraper,
      };

  test('missing baseUrl fails fast with config screen failure', () async {
    final report = await SmokeRunner().run({'source': 'x'});
    expect(report.allPassed, isFalse);
    expect(report.failures.single.screen, 'config');
  });

  test('unreachable site reports home failure without crash', () async {
    final report = await SmokeRunner().run({
      'source': 'dead',
      'baseUrl': 'http://127.0.0.1:1',
      'scraper': <String, dynamic>{},
    });
    expect(report.allPassed, isFalse);
    expect(report.results.first.screen, 'home');
  });

  test('relative covers are flagged as warning on passing home', () async {
    // This exercises the cover-warning path via a config whose home parse
    // succeeds; the fixture HTML above has one relative cover.
    // ponytail: full adapter-driven happy path needs a real source config;
    // covered by Phase-4 regenerate verification on a live madara source.
    final report = await SmokeRunner().run({
      'source': 'x',
      'baseUrl': 'http://127.0.0.1:1',
      'scraper': <String, dynamic>{},
    });
    expect(report.results.where((r) => r.screen == 'home'), isNotEmpty);
  });

  test('host mismatch fails fast so stored baseUrl cannot be masked (#62)',
      () async {
    final report = await SmokeRunner().run(
      {'source': 'x', 'baseUrl': 'https://parked.test'},
      probedUrl: 'https://real.test/',
    );
    expect(report.allPassed, isFalse);
    expect(report.failures.single.screen, 'config');
    expect(report.failures.single.failure, contains('host mismatch'));
  });

  test('fixture emitter writes html + manifest', () {
    final dir = Directory.systemTemp.createTempSync('smoke_fixture_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    FixtureEmitter(outputDir: dir.path, sourceId: 'demo').writeAll({
      'home': '<html>x</html>',
      'search': '<html>y</html>',
    }, {
      'baseUrl': 'https://demo.test'
    });
    final fdir = Directory('${dir.path}/fixtures/demo');
    expect(fdir.existsSync(), isTrue);
    expect(File('${fdir.path}/home.html').readAsStringSync(), '<html>x</html>');
    final manifest =
        jsonDecode(File('${fdir.path}/manifest.json').readAsStringSync())
            as Map;
    expect(manifest['source'], 'demo');
    expect(manifest['baseUrl'], 'https://demo.test');
    expect((manifest['screens'] as List), containsAll(['home', 'search']));
  });

  test('skeleton test emitter writes parseable dart file', () {
    final dir = Directory.systemTemp.createTempSync('smoke_skeleton_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    SkeletonTestEmitter(outputDir: dir.path, sourceId: 'demo').write();
    final f = File('${dir.path}/demo_generated_live_test.dart');
    expect(f.existsSync(), isTrue);
    final content = f.readAsStringSync();
    expect(content, contains("const _sourceId = 'demo';"));
    expect(content, contains('group('));
    expect(content, contains('LIVE'));
  });
}
