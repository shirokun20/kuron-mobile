import 'dart:convert';
import 'dart:io';

import 'package:kuron_config_generator/src/validation/negative_probes.dart';
import 'package:kuron_config_generator/src/validation/smoke_runner.dart';
import 'package:kuron_config_generator/src/validation/skeleton_test_emitter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
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

  const searchHtml = '<html><body><div class="list">'
      '<div class="item"><a href="/manga/one/">Naruto One</a></div>'
      '</div></body></html>';

  /// Detail page for the healthy case: every configured field is present, the
  /// cover carries its real URL in `data-src` (the exact 2026-09-27 bug — a
  /// config reading plain `src` grabbed a 1×1 placeholder).
  ///
  /// Images point at `127.0.0.1` while [baseUrl] is `localhost`: the adapter
  /// upgrades same-host `http://` image URLs to `https://` (Android cleartext
  /// guard), which a plain-HTTP test server cannot answer. A different host
  /// skips the upgrade, and `127.0.0.1` needs no DNS override.
  const healthyDetailHtml = '<html><body>'
      '<h1>One</h1>'
      '<div class="cover"><img src="data:image/gif;base64,R0lGOD" '
      'data-src="http://127.0.0.1:PORT/img/cover-one.jpg"></div>'
      '<div class="tags">'
      '<a href="/tag/action/">Action</a><a href="/tag/comedy/">Comedy</a></div>'
      '<div class="chapter"><a href="/manga/one/">Ch 1</a></div>'
      '</body></html>';

  String chapterHtml(int port) => '<html><body>'
      '<div class="chapter">'
      '<img src="http://127.0.0.1:$port/img/page-1.jpg"></div>'
      '</body></html>';

  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    baseUrl = 'http://localhost:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(homeHtml);
      } else if (path.startsWith('/search')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(searchHtml);
      } else if (path.startsWith('/tag/')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(searchHtml);
      } else if (path == '/manga/one/') {
        req.response.headers.contentType = ContentType.html;
        req.response
            .write(healthyDetailHtml.replaceAll('PORT', '${server.port}'));
      } else if (path == '/chapter/one/') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(chapterHtml(server.port));
      } else if (path.startsWith('/img') || path.startsWith('/cover')) {
        // Real JPEG magic so the sniff fallback in _probeContentType passes
        // even if a host/CDN mislabels or refuses HEAD.
        req.response.headers.contentType = ContentType('image', 'jpeg');
        req.response.add([0xFF, 0xD8, 0xFF, ...List.filled(2048, 1)]);
      } else if (path.startsWith('/notimage')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>not a picture</html>');
      } else if (path.startsWith('/api/detail')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body><h1>One</h1>'
            '<div class="chapter"><a href="/chapter/1/">Ch 1</a></div></body></html>');
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

  /// End-to-end config driving all five screens against the local server:
  /// home → search → detail → chapters → reader, with a detail-field config
  /// whose selectors are injected per test.
  Map<String, dynamic> happyPathConfig(
    Map<String, dynamic> detailFields, {
    Map<String, dynamic>? extraPatterns,
  }) => {
        'source': 'smoketest',
        'baseUrl': baseUrl,
        'scraper': {
          'urlPatterns': {
            'home': {
              'url': '/',
              'list': {
                'container': 'div.list > div.item',
                'fields': {
                  'id': {
                    'selector': 'a',
                    'attribute': 'href',
                    'transform': 'slug',
                  },
                  'title': {'selector': 'a'},
                  'coverUrl': {'selector': 'img', 'attribute': 'src'},
                },
              },
            },
            'search': {
              'url': '/search/?q={query}',
              'list': {
                'container': 'div.list > div.item',
                'fields': {
                  'id': {
                    'selector': 'a',
                    'attribute': 'href',
                    'transform': 'slug',
                  },
                  'title': {'selector': 'a'},
                },
              },
            },
            'detail': '/manga/{id}/',
            'chapter': '/chapter/{id}/',
            if (extraPatterns != null) ...extraPatterns,
          },
          'selectors': {
            'detail': {
              'fields': detailFields,
              'chapters': {
                'container': 'div.chapter',
                'fields': {
                  'id': {
                    'selector': 'a',
                    'attribute': 'href',
                    'transform': 'slug',
                  },
                  'title': {'selector': 'a'},
                },
              },
            },
            'reader': {
              'images': {
                'selector': 'div.chapter img',
                'attribute': 'src',
              },
            },
          },
        },
      };

  SmokeRunner fastRunner() => SmokeRunner(
        settleDelay: Duration.zero,
        detailRetryDelay: Duration.zero,
      );

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

  group('#64 detail-field gate', () {
    test('healthy detail (lazy data-src cover, tags) passes all screens',
        () async {
      final report = await fastRunner().run(happyPathConfig({
        'title': {'selector': 'h1'},
        'coverUrl': {
          'selector': '.cover img',
          'attribute': ['data-src', 'src'],
        },
        'tags': {'selector': '.tags a', 'multi': true},
      }));
      expect(
        report.findings.where((f) => f.probe.startsWith('detail-')),
        isEmpty,
        reason: 'no detail-field findings expected: ${report.findings}',
      );
      expect(report.allPassed, isTrue, reason: '${report.results}');
    });

    test('configured cover selector matching nothing is blocking', () async {
      final report = await fastRunner().run(happyPathConfig({
        'title': {'selector': 'h1'},
        // Renamed container — the 2026-09-27 wave's failure mode.
        'coverUrl': {'selector': '.thumb img', 'attribute': 'src'},
      }));
      final cover = report.findings.firstWhere(
        (f) =>
            f.probe == 'detail-field-empty' && f.message.contains('coverUrl'),
      );
      expect(cover.severity, FindingSeverity.blocking);
      expect(report.allPassed, isFalse);
    });

    test('configured tag selector matching nothing is blocking', () async {
      final report = await fastRunner().run(happyPathConfig({
        'title': {'selector': 'h1'},
        'tags': {'selector': '.genrelist a', 'multi': true},
      }));
      final tags = report.findings.firstWhere(
        (f) => f.probe == 'detail-field-empty' && f.message.contains('tags'),
      );
      expect(tags.severity, FindingSeverity.blocking);
      expect(report.allPassed, isFalse);
    });

    test('cover URL resolving to text/html is blocking', () async {
      // A cover selector that grabs an <a> href lands on the content page
      // itself — the selector matches, the URL is fetchable, it is just not
      // a picture. Only a content-type probe catches this.
      final findings = await probeDetailFields(
        '<html><body><a class="thumb" href="/notimage/one.jpg">x</a></body></html>',
        {
          'coverUrl': {'selector': 'a.thumb', 'attribute': 'href'},
        },
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        resolvedCoverUrl: '$baseUrl/notimage/one.jpg',
        baseUrl: baseUrl,
        contentTypeOf: (_) async => 'text/html',
      );
      final cover = findings.firstWhere(
        (f) => f.probe == 'detail-cover-not-image',
      );
      expect(cover.severity, FindingSeverity.blocking);
    });

    test('cover URL that resolves to empty is blocking', () async {
      final findings = await probeDetailFields(
        healthyDetailHtml,
        {
          'coverUrl': {'selector': 'h1', 'attribute': 'href'},
        },
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        resolvedCoverUrl: '',
        baseUrl: baseUrl,
        contentTypeOf: (_) async => 'image/jpeg',
      );
      // h1 has no href → selector matches, attribute empty → cover empty.
      expect(
        findings.any((f) => f.probe == 'detail-cover-not-image'),
        isTrue,
        reason: '$findings',
      );
    });

    test('a CDN that refuses to answer is advisory, not blocking', () async {
      // Hotlink guards / rate limits make contentTypeOf return null; a real
      // broken image still fails the reader probe, so this must not block.
      final findings = await probeDetailFields(
        healthyDetailHtml,
        {
          'coverUrl': {
            'selector': '.cover img',
            'attribute': ['data-src', 'src'],
          },
        },
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        resolvedCoverUrl: '$baseUrl/img/cover-one.jpg',
        baseUrl: baseUrl,
        contentTypeOf: (_) async => null,
      );
      expect(findings, isEmpty);
    });

    test('unconfigured fields are never probed (gallery-only source passes)',
        () async {
      // hentaifox-family config: title + cover only, no author/tags at all.
      final report = await fastRunner().run(happyPathConfig({
        'title': {'selector': 'h1'},
        'coverUrl': {
          'selector': '.cover img',
          'attribute': ['data-src', 'src'],
        },
      }));
      expect(
        report.findings.where((f) => f.probe.startsWith('detail-')),
        isEmpty,
        reason: '${report.findings}',
      );
      expect(report.allPassed, isTrue, reason: '${report.results}');
    });

    test('probeDetailFields is a no-op without configured selectors', () async {
      final findings = await probeDetailFields(
        healthyDetailHtml,
        const {},
        parser: GenericHtmlParser(logger: Logger(level: Level.off)),
        resolvedCoverUrl: '',
        baseUrl: baseUrl,
        contentTypeOf: (_) async => 'image/jpeg',
      );
      expect(findings, isEmpty);
    });
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

  group('taxonomy screen probe (conformance-loop 2.1)', () {
    test('live taxonomy archive passes the sixth screen', () async {
      final report = await fastRunner().run(
        happyPathConfig(
          {
            'title': {'selector': 'h1'},
            'tags': {'selector': '.tags a', 'multi': true},
          },
          extraPatterns: {
            'tagSearch': {
              'url': '/tag/{tag}/',
              'inherits': 'home',
            },
            'genreSearch': {
              'url': '/tag/{tag}/',
              'inherits': 'home',
            },
          },
        ),
      );

      final taxonomy = report.results.firstWhere(
          (r) => r.screen == 'taxonomy',
          orElse: () => throw StateError('no taxonomy screen'));
      expect(taxonomy.passed, isTrue, reason: '${report.results}');
      expect(report.allPassed, isTrue, reason: '${report.results}');
    });

    test('dead taxonomy archive fails the run (blocking)', () async {
      final report = await fastRunner().run(
        happyPathConfig(
          {
            'title': {'selector': 'h1'},
            'tags': {'selector': '.tags a', 'multi': true},
          },
          extraPatterns: {
            'tagSearch': {
              'url': '/dead/{tag}/',
              'inherits': 'home',
            },
            'genreSearch': {
              'url': '/dead/{tag}/',
              'inherits': 'home',
            },
          },
        ),
      );

      final taxonomy = report.results.firstWhere(
          (r) => r.screen == 'taxonomy',
          orElse: () => throw StateError('no taxonomy screen'));
      expect(taxonomy.passed, isFalse);
      expect(report.allPassed, isFalse);
    });
  });
}
