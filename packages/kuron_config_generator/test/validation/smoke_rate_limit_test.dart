// Regression test for the live-smoke rate-limit false negative (#55).
//
// `SmokeRunner` used to fire home → search → detail → chapters → reader
// back-to-back. Burst-rate-limited hosts (akazascans/nginx) answer the later
// probes with 429 empty shells, so detail/chapters/reader FAIL intermittently
// even though the selectors are correct — the same config passes when probed
// with spacing.
//
// The fixture below answers the FIRST detail hit with a 429 empty shell and
// every later hit with the real page, exactly as the live host behaved. The
// detail retry after the settle delay turns the would-be FAIL into a pass.
//
// Delays are injected at zero so the test doesn't pay 11s of wall clock; the
// defaults (3s settle, 8s retry) are asserted separately.
// Run with:
//   dart test packages/kuron_config_generator/test/validation/smoke_rate_limit_test.dart
library;

import 'dart:io';

import 'package:kuron_config_generator/src/validation/smoke_runner.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  late int detailHits;
  /// When true the server answers the FIRST detail hit with the 429 empty
  /// shell (title only, no chapter list), exactly as akazascans/nginx did.
  late bool throttleFirstDetail;

  const homeHtml = '''
<html><body><div class="bsx">
  <div class="bs"><a href="/manga/one/">One</a>
    <img src="https://cdn.example.test/c1.jpg"/></div>
</div></body></html>''';

  const searchHtml = '''
<html><body><div class="bsx">
  <div class="bs"><a href="/manga/one/">One</a>
    <img src="https://cdn.example.test/c1.jpg"/></div>
</div></body></html>''';

  // Real chapters — the 429 shell answered with this markup minus the list.
  const detailGood = '''
<html><body><h1>One</h1>
<ul class="main-chapters">
  <li><a href="/manga/one/chapter-1/">Chapter 1</a></li>
  <li><a href="/manga/one/chapter-2/">Chapter 2</a></li>
</ul>
</body></html>''';

  // The 429 shell: title only, no chapter list.
  const detailThrottled = '<html><body><h1>One</h1></body></html>';

  const chapterHtml = '''
<html><body><div id="readerarea">
  <img src="https://cdn.example.test/p/1.jpg"/>
</div></body></html>''';

  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      res.headers.contentType = ContentType.html;
      switch (req.uri.path) {
        case '/':
          res.write(homeHtml);
        case '/manga/one/':
          detailHits++;
          final throttled = throttleFirstDetail && detailHits == 1;
          res.write(throttled ? detailThrottled : detailGood);
        case '/manga/one/chapter-1/':
        case '/manga/one/chapter-2/':
          res.write(chapterHtml);
        case '/search':
          res.write(searchHtml);
        default:
          if (req.uri.path.startsWith('/p/') ||
              req.uri.path.startsWith('/c1')) {
            res.headers.contentType = ContentType('image', 'jpeg');
            res.add(List.filled(64, 1));
          } else {
            res.statusCode = 404;
            res.write('nope');
          }
      }
      await res.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  setUp(() {
    detailHits = 0;
    throttleFirstDetail = false;
  });

  Map<String, dynamic> config() => {
        'source': 'ratelimit',
        'baseUrl': baseUrl,
        'scraper': {
          'urlPatterns': {
            'home': {
              'url': '/',
              'list': {
                'container': 'div.bsx',
                'fields': {
                  'id': {
                    'selector': 'a[href]',
                    'attribute': 'href',
                    'regex': r'/manga/([^/?#]+)/?$',
                  },
                  'title': {'selector': 'a[href]'},
                  'coverUrl': {'selector': 'img', 'attribute': 'src'},
                },
              },
            },
            'search': {
              'url': '/search',
              'list': {
                'container': 'div.bsx',
                'fields': {
                  'id': {
                    'selector': 'a[href]',
                    'attribute': 'href',
                    'regex': r'/manga/([^/?#]+)/?$',
                  },
                  'title': {'selector': 'a[href]'},
                  'coverUrl': {'selector': 'img', 'attribute': 'src'},
                },
              },
            },
            'detail': '/manga/{id}/',
            'chapter': '/manga/{id}/chapter-{page}/',
          },
          'selectors': {
            'detail': {
              'fields': {
                'title': {'selector': 'h1'},
              },
              'chapters': {
                'container': 'ul.main-chapters li a',
                'fields': {
                  'id': {
                    'selector': 'self',
                    'attribute': 'href',
                    'regex': r'/chapter-(\d+)/?$',
                  },
                  'title': {'selector': 'self'},
                },
              },
            },
            'reader': {
              'images': {
                'selector': '#readerarea img',
                'attribute': 'src',
              },
            },
          },
        },
      };

  test('detail is probed twice when the first hit is an empty shell', () async {
    throttleFirstDetail = true;
    final report = await SmokeRunner(
      settleDelay: Duration.zero,
      detailRetryDelay: Duration.zero,
    ).run(config());

    expect(detailHits, 2,
        reason: 'empty chapter list must trigger exactly one detail retry');
    final detail = report.results.firstWhere((r) => r.screen == 'detail');
    expect(detail.passed, isTrue,
        reason: 'retry sees the healthy page: ${detail.failure}');
    final chapters =
        report.results.firstWhere((r) => r.screen == 'chapters');
    expect(chapters.passed, isTrue);
    expect(chapters.itemCount, 2);
  });

  test('healthy first hit is probed once, no wasted retry', () async {
    final report = await SmokeRunner(
      settleDelay: Duration.zero,
      detailRetryDelay: Duration.zero,
    ).run(config());
    expect(detailHits, 1,
        reason: 'a healthy detail needs exactly one probe');
    expect(report.results.firstWhere((r) => r.screen == 'detail').passed,
        isTrue);
  });

  test('ships the 3s settle / 8s retry defaults', () {
    // The whole point of the fix is the real spacing; the tests above inject
    // Duration.zero only so they don't pay 11s of wall clock.
    final runner = SmokeRunner();
    expect(runner.settleDelay, const Duration(seconds: 3));
    expect(runner.detailRetryDelay, const Duration(seconds: 8));
  });
}
