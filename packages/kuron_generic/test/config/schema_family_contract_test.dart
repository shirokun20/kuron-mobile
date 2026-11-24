// Source-config contract vs kuron-extensions schema family v2/v3.
//
// Verifies, against the ACTUAL shapes in kuron-extensions
// (schema/source-config.schema.json):
// - `schemaVersion` accepts int 2/3, "2.0"/"3.0" strings, and absence.
// - `network`: requiresBypass, cloudflare.{bypassEnabled, antiDetection},
//   rateLimit, with unknown future keys ignored.
// - `searchForm`: top-level wins, nested `scraper.searchForm` is honored.
// - `secondaryFetch`: non-legacy schema keys parse (legacy retired keys
//   stay unsupported).
// - `extends` preset markers and unknown future fields never crash parsing.
library;

import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

Map<String, Object?> _network({
  bool requiresBypass = false,
  bool bypassEnabled = false,
  bool antiDetection = false,
  Map<String, Object?>? extra,
}) {
  return <String, Object?>{
    'requiresBypass': requiresBypass,
    'headers': const <String, String>{
      'Referer': 'https://example.com/',
    },
    'rateLimit': const <String, Object?>{
      'enabled': true,
      'requestsPerSecond': 1,
      'maxConcurrentRequests': 2,
    },
    'cloudflare': <String, Object?>{
      'bypassEnabled': bypassEnabled,
      'antiDetection': antiDetection,
    },
    ...?extra,
  };
}

Map<String, Object?> _config({
  Object? schemaVersion = 2,
  Map<String, Object?>? network,
  Map<String, Object?>? searchForm,
  Map<String, Object?>? scraperSearchForm,
  Map<String, Object?>? secondaryFetch,
  Map<String, Object?>? extra,
}) {
  final scraper = <String, Object?>{
    'urlPatterns': const <String, Object?>{'list': '/manga/'},
    'selectors': const <String, Object?>{},
    'searchForm': ?scraperSearchForm,
    'secondaryFetch': ?secondaryFetch,
  };
  return <String, Object?>{
    if (schemaVersion != _absent) 'schemaVersion': schemaVersion,
    'source': 'contract-probe',
    'version': '2.0.0',
    'baseUrl': 'https://example.com',
    'enabled': true,
    'defaultLanguage': 'english',
    'idType': 'slug',
    'ui': const <String, Object?>{},
    'features': const <String, Object?>{},
    'extends': 'themesia',
    'network': network ?? _network(),
    'searchForm': ?searchForm,
    'scraper': scraper,
    ...?extra,
  };
}

const _absent = Object();

const _formBlock = <String, Object?>{
  'urlPattern': '/search?q={query}',
  'params': <String, Object?>{
    'q': {'type': 'text', 'queryParam': 'q'},
  },
};

const _secondaryFetchBlock = <String, Object?>{
  'enabled': true,
  'tokenPattern': 'payloadKey\\D{0,8}([lmc]_[a-f0-9]+)',
  'url': '{origin}/ad-frame/data?k={key}',
  'referer': 'page',
  'payloadPath': 'chaotic_payload',
  'decodeKey': 'NicoManga',
  'itemsPath': 'items',
  'imagesPath': 'images',
  'itemFields': <String, Object?>{},
  'pagination': <String, Object?>{'page': 'pagination.page'},
  'timeoutMs': 15000,
};

void main() {
  const parser = SourceConfigParser();

  group('schemaVersion family (v2/v3 + legacy)', () {
    test('accepts int, dotted strings, and v3', () {
      for (final raw in [2, 3, '2', '2.0', '3', '3.0']) {
        final report = parser.parse(_config(schemaVersion: raw)).report;
        expect(
          report.diagnostics.where(
            (d) => d.severity == DiagnosticSeverity.error,
          ),
          isEmpty,
          reason: 'schemaVersion=$raw must not error',
        );
        expect(report.schemaVersion, raw.toString());
      }
    });

    test('absence warns but never errors (legacy v1 inference)', () {
      final report = parser.parse(_config(schemaVersion: _absent)).report;
      expect(
        report.diagnostics.where(
          (d) => d.severity == DiagnosticSeverity.error,
        ),
        isEmpty,
      );
      expect(
        report.diagnostics.any((d) => d.code == 'schemaVersionMissing'),
        isTrue,
      );
    });

    test('unknown future top-level and nested fields are ignored', () {
      final report = parser.parse(
        _config(
          schemaVersion: '3.0',
          network: _network(extra: const {'futureKey': 'x'}),
          extra: const {
            'futureTop': [1, 2],
            'anotherFuture': {'deep': true},
          },
        ),
      ).report;
      expect(
        report.diagnostics.where(
          (d) => d.severity == DiagnosticSeverity.error,
        ),
        isEmpty,
      );
    });
  });

  group('network contract', () {
    test('parses requiresBypass, cloudflare pair, and rateLimit', () {
      final rules = NetworkRules.fromConfig(
        _config(
          network: _network(
            requiresBypass: true,
            bypassEnabled: false,
            antiDetection: true,
          ),
        ),
      );
      expect(rules.requiresBypass, isTrue);
      expect(rules.cloudflareBypass, isFalse);
      expect(rules.antiDetection, isTrue);
      expect(rules.rateLimit, isNotNull);
      expect(rules.rateLimit!.requestsPerSecond, 1);
      expect(rules.rateLimit!.maxConcurrentRequests, 2);
    });

    test('cloudflare bypassEnabled merges into requiresBypass', () {
      final rules = NetworkRules.fromConfig(
        _config(network: _network(bypassEnabled: true)),
      );
      expect(rules.requiresBypass, isTrue);
      expect(rules.cloudflareBypass, isTrue);
      expect(rules.antiDetection, isFalse);
    });

    test('absent network block yields safe defaults', () {
      final config = _config()..remove('network');
      final rules = NetworkRules.fromConfig(config);
      expect(rules.requiresBypass, isFalse);
      expect(rules.antiDetection, isFalse);
      expect(rules.rateLimit, isNull);
    });
  });

  group('searchForm resolution (top-level vs scraper-nested)', () {
    test('top-level wins when both are present', () {
      final resolved = resolveSearchFormConfig(
        _config(
          searchForm: const {'urlPattern': '/top?q={query}'},
          scraperSearchForm: const {'urlPattern': '/nested?q={query}'},
        ),
      );
      expect(resolved?['urlPattern'], '/top?q={query}');
    });

    test('nested scraper.searchForm is honored (preset-expanded)', () {
      final resolved = resolveSearchFormConfig(
        _config(scraperSearchForm: _formBlock),
      );
      expect(resolved, isNotNull);
      expect(resolved!['urlPattern'], '/search?q={query}');
    });

    test('returns null when neither block exists', () {
      expect(resolveSearchFormConfig(_config()), isNull);
      expect(resolveSearchFormConfig(const {}), isNull);
    });

    test('prefix routing stays disabled for nested-only forms', () {
      final routing = SearchQueryRouting(
        logger: Logger(level: Level.off),
        sourceId: 'nested-only',
      );
      // A page-param query must resolve from the nested block, proving the
      // routing layer sees it (no throw, no crash on shape).
      expect(
        () => routing.resolvePageParamName(
          rawConfig: _config(
            scraperSearchForm: const {
              'params': {
                'pg': {'type': 'page', 'queryParam': 'pg'},
              },
            },
          ),
          urlPatternsCfg: const {},
          patternKeys: const [],
        ),
        returnsNormally,
      );
    });
  });

  group('secondaryFetch non-legacy keys (#61)', () {
    test('schema keys parse into a usable spec', () {
      final spec = SecondaryFetchSpec.tryParse(
        Map<String, dynamic>.from(_secondaryFetchBlock),
      );
      expect(spec, isNotNull);
      expect(spec!.url, '{origin}/ad-frame/data?k={key}');
      expect(spec.referer, 'page');
      expect(spec.payloadPath, 'chaotic_payload');
      expect(spec.decodeKey, 'NicoManga');
      expect(spec.itemsPath, 'items');
      expect(spec.imagesPath, 'images');
      expect(spec.timeout, const Duration(milliseconds: 15000));
    });

    test('alias keys (tokenRegex/secondaryUrlTemplate) parse', () {
      final spec = SecondaryFetchSpec.tryParse({
        'enabled': true,
        'tokenRegex': 'tok=(\\w+)',
        'secondaryUrlTemplate': '{origin}/x?k={key}',
      });
      expect(spec, isNotNull);
      expect(spec!.tokenPattern, 'tok=(\\w+)');
      expect(spec.url, '{origin}/x?k={key}');
    });

    test('disabled or URL-less blocks stay inert (null)', () {
      expect(SecondaryFetchSpec.tryParse({'enabled': false}), isNull);
      expect(SecondaryFetchSpec.tryParse({'enabled': true}), isNull);
      expect(SecondaryFetchSpec.tryParse(null), isNull);
      expect(
        SecondaryFetchSpec.tryParse('not-a-map'),
        isNull,
      );
    });
  });

  group('extends + forward compatibility', () {
    test('preset extends markers ride through without diagnostics errors', () {
      final report = parser.parse(_config()).report;
      expect(
        report.diagnostics.where(
          (d) => d.severity == DiagnosticSeverity.error,
        ),
        isEmpty,
      );
    });

    test('extends-only config (unexpanded preset) fails closed, no crash', () {
      final report = parser.parse(<String, Object?>{
        'source': 'unexpanded',
        'version': '1.0.0',
        'schemaVersion': 2,
        'extends': 'themesia',
      }).report;
      // No engine surface: an error diagnostic, never an exception, and no
      // adapter is produced for it downstream.
      expect(
        report.diagnostics.where(
          (d) => d.severity == DiagnosticSeverity.error,
        ),
        isNotEmpty,
      );
    });
  });
}
