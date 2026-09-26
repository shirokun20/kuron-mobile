import 'package:test/test.dart';
import 'package:kuron_config_generator/src/discovery/api_endpoint_hunter.dart';
import 'package:kuron_config_generator/src/discovery/http_probe.dart';

ProbeResult jsonHit(String url, String body) => ProbeResult(
      url: url,
      statusCode: 200,
      body: body,
      contentType: ProbeContentType.json,
    );

ProbeResult miss(String url) => ProbeResult(
      url: url,
      statusCode: 404,
      body: 'not found',
      contentType: ProbeContentType.unknown,
    );

void main() {
  final base = Uri.parse('https://example.com/');

  group('ApiEndpointHunter', () {
    test('finds WordPress REST via /wp-json/ index', () async {
      Future<ProbeResult> fetch(String url) async {
        if (url == 'https://example.com/wp-json/') {
          return jsonHit(url, '{"namespaces":["oembed/1.0","wp/v2"]}');
        }
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><head>'
            '<meta name="generator" content="WordPress 6.5" />'
            '</head><body><link rel="stylesheet" href="/wp-content/x.css">'
            '</body></html>',
        fetch: fetch,
      );
      expect(hit, isNotNull);
      expect(hit!.kind, ApiEndpointKind.wpRest);
      expect(hit.endpointUrl, 'https://example.com/wp-json/');
      expect(hit.inference.queryParam, 'search');
    });

    test('skips WP candidates when HTML has no WP smell', () async {
      final probed = <String>[];
      Future<ProbeResult> fetch(String url) async {
        probed.add(url);
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><div>Hello</div></body></html>',
        fetch: fetch,
      );
      expect(hit, isNull);
      expect(probed.any((u) => u.contains('wp-json')), isFalse);
      // Generic fallbacks are still tried.
      expect(probed, contains('https://example.com/api/'));
    });

    test('finds generic JSON list at /api/', () async {
      Future<ProbeResult> fetch(String url) async {
        if (url == 'https://example.com/api/') {
          return jsonHit(
            url,
            '{"data":[{"id":1,"title":"One"}],"page":1}',
          );
        }
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><div>Hello</div></body></html>',
        fetch: fetch,
      );
      expect(hit, isNotNull);
      expect(hit!.kind, ApiEndpointKind.genericJson);
      expect(hit.inference.hasList, isTrue);
      expect(hit.inference.listItemsPath, 'data');
    });

    test('prefers /api/ path hinted by page scripts', () async {
      Future<ProbeResult> fetch(String url) async {
        if (url == 'https://example.com/api/parse-chapter') {
          return jsonHit(
            url,
            '{"id":7,"title":"Ch 7","images":["a.jpg"]}',
          );
        }
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><script>'
            'fetch("/api/parse-chapter",{method:"POST"})'
            '</script></body></html>',
        fetch: fetch,
      );
      expect(hit, isNotNull);
      expect(hit!.kind, ApiEndpointKind.scriptApi);
      expect(
        hit.endpointUrl,
        'https://example.com/api/parse-chapter',
      );
    });

    test('caps script-hint candidates at 3', () async {
      final probed = <String>[];
      Future<ProbeResult> fetch(String url) async {
        probed.add(url);
        return miss(url);
      }

      await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><script>'
            'fetch("/api/a");fetch("/api/b");fetch("/api/c");'
            'fetch("/api/d");fetch("/api/e");'
            '</script></body></html>',
        fetch: fetch,
      );
      for (final p in ['/api/a', '/api/b', '/api/c']) {
        expect(probed, contains('https://example.com$p'));
      }
      // Beyond the cap: never probed as script hints.
      expect(probed, isNot(contains('https://example.com/api/d')));
      expect(probed, isNot(contains('https://example.com/api/e')));
    });

    test('tries Next.js data endpoint from buildId, skips on 404', () async {
      final probed = <String>[];
      Future<ProbeResult> fetch(String url) async {
        probed.add(url);
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><script id="__NEXT_DATA__" type='
            '"application/json">{"buildId":"abc123"}</script></body></html>',
        fetch: fetch,
      );
      expect(hit, isNull);
      expect(
        probed,
        contains('https://example.com/_next/data/abc123/index.json'),
      );
    });

    test('skips blocked and non-JSON candidates', () async {
      Future<ProbeResult> fetch(String url) async {
        if (url == 'https://example.com/api/') {
          return ProbeResult(
            url: url,
            statusCode: 200,
            body: '<title>Just a moment...</title>'
                'Performing security verification'
                '<script>window._cf_chl_opt={}</script>',
            contentType: ProbeContentType.html,
          );
        }
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><div>Hello</div></body></html>',
        fetch: fetch,
      );
      expect(hit, isNull);
    });

    test('rejects low-confidence JSON (status wrappers)', () async {
      Future<ProbeResult> fetch(String url) async {
        if (url == 'https://example.com/api/') {
          return jsonHit(url, '{"status":"ok","message":"hi"}');
        }
        return miss(url);
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><div>Hello</div></body></html>',
        fetch: fetch,
      );
      expect(hit, isNull);
    });

    test('tolerates fetch throwing', () async {
      Future<ProbeResult> fetch(String url) async {
        throw Exception('dns fail');
      }

      final hit = await huntApiEndpoints(
        base: base,
        htmlBody: '<html><body><div>Hello</div></body></html>',
        fetch: fetch,
      );
      expect(hit, isNull);
    });
  });
}
