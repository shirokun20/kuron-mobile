// Schema validation tests for komiktap-config.json and nhentai-config.json.
///
// These tests load the actual JSON config files from disk and validate that:
//   1. All required top-level keys are present with correct types.
//   2. Every list URL pattern has the new `list.{container, fields}` schema.
//   3. `fields` maps use the canonical `{selector, ...}` field definition format.
//   4. Detail selectors and chapter selectors are well-formed.
//   5. Reader config has the required sub-structure.
//   6. `searchForm` structure is valid.
//   7. `inherits` references point to existing patterns.
///
// Run with:
//   dart test packages/kuron_generic/test/config/komiktap_config_schema_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/config_test_harness.dart';

// nhentai is a bundled default shipped in `assets/configs/`; it is not an
// installable source, so the remote harness does not apply.
Map<String, dynamic> _loadBundledNhentai() {
  const candidates = [
    'assets/configs/nhentai-config.json', // running from project root
    '../../assets/configs/nhentai-config.json', // from packages/kuron_generic/
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) {
      return jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
      'Cannot locate nhentai-config.json under assets/configs/. Run tests from project root or packages/kuron_generic/.');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Assert that [map] has a non-null value at [key].
void _hasKey(Map<String, dynamic> map, String key, String context) {
  expect(map.containsKey(key), isTrue,
      reason: '$context: missing key "$key". Keys present: ${map.keys}');
}

// Assert [map][key] is a [Map<String,dynamic>].
Map<String, dynamic> _asMap(Map<String, dynamic> map, String key, String ctx) {
  _hasKey(map, key, ctx);
  expect(map[key], isA<Map>(),
      reason:
          '$ctx: "$key" should be a JSON object, got ${map[key].runtimeType}');
  return (map[key] as Map).cast<String, dynamic>();
}

// Assert [map][key] is a non-empty, non-blank [String].
void _asString(Map<String, dynamic> map, String key, String ctx) {
  _hasKey(map, key, ctx);
  expect(map[key], isA<String>(), reason: '$ctx: "$key" should be a String');
  expect((map[key] as String).trim(), isNotEmpty,
      reason: '$ctx: "$key" is present but empty');
}

// [_asString] but returns the validated value.
String _requireString(Map<String, dynamic> map, String key, String ctx) {
  _asString(map, key, ctx);
  return map[key] as String;
}

// ═══════════════════════════════════════════════════════════════════════════
// komiktap-config.json
// ═══════════════════════════════════════════════════════════════════════════

// Resolve an endpoint declared as either a plain string path or a
// `{path, params}` object (params are appended as a query string).
String _endpointPath(Map<String, dynamic> endpoints, String key) {
  final value = endpoints[key];
  if (value is String) return value;
  if (value is Map) {
    final path = (value['path'] as String?) ?? '';
    final params = value['params'];
    if (params is! Map || params.isEmpty) return path;
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$path${path.contains('?') ? '&' : '?'}$query';
  }
  return '';
}

void main() {
  late Map<String, dynamic> komiktap;
  late Map<String, dynamic> nhentai;

  setUpAll(() async {
    komiktap = (await loadConfigRemote('komiktap-config.json'))
        .cast<String, dynamic>();
    nhentai = _loadBundledNhentai();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — top-level keys
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json top-level', () {
    test('has required identity fields', () {
      _asString(komiktap, 'source', 'root');
      _asString(komiktap, 'version', 'root');
      _asString(komiktap, 'baseUrl', 'root');
    });

    test('source is "komiktap"', () {
      expect(komiktap['source'], 'komiktap');
    });

    test('has configUrl (for self-refresh)', () {
      _asString(komiktap, 'configUrl', 'root');
      expect((komiktap['configUrl'] as String).startsWith('https://'), isTrue,
          reason: 'configUrl should be an https URL');
    });

    test('baseUrl is a valid https URL', () {
      final url = komiktap['baseUrl'] as String;
      expect(url.startsWith('https://'), isTrue);
    });

    test('enabled is a boolean', () {
      expect(komiktap['enabled'], isA<bool>());
    });

    test('has api block (REST driver) and no scraper block', () {
      _asMap(komiktap, 'api', 'root');
      expect(komiktap.containsKey('scraper'), isFalse,
          reason: 'v2 config drives data via the api block');
    });

    test('has searchForm block', () {
      _asMap(komiktap, 'searchForm', 'root');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — api.endpoints
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json api.endpoints', () {
    late Map<String, dynamic> api;
    late Map<String, dynamic> endpoints;

    setUp(() {
      api = _asMap(komiktap, 'api', 'root');
      endpoints = _asMap(api, 'endpoints', 'api');
    });

    test('api.url is an https URL (REST base)', () {
      final url = _requireString(api, 'url', 'api');
      expect(url.startsWith('https://'), isTrue);
    });

    test('has required endpoint keys', () {
      for (final key in [
        'allGalleries',
        'search',
        'tagSearch',
        'detail',
        'images',
      ]) {
        expect(endpoints.containsKey(key), isTrue,
            reason: 'api.endpoints is missing "$key"');
      }
    });

    test('list endpoints carry {page} and search carries {query}', () {
      final all = _endpointPath(endpoints, 'allGalleries');
      final search = _endpointPath(endpoints, 'search');
      expect(all, contains('{page}'));
      expect(search, contains('{page}'));
      expect(search, contains('{query}'));
    });

    test('tagSearch path carries {tagId}', () {
      expect(_endpointPath(endpoints, 'tagSearch'), contains('{tagId}'));
    });

    test('detail and images paths carry {id}; images carries {chapter}', () {
      expect(_endpointPath(endpoints, 'detail'), contains('{id}'));
      final images = _endpointPath(endpoints, 'images');
      expect(images, contains('{id}'));
      expect(images, contains('{chapter}'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — api.list
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json api.list', () {
    late Map<String, dynamic> list;

    setUp(() {
      final api = _asMap(komiktap, 'api', 'root');
      list = _asMap(api, 'list', 'api');
    });

    test('items is a JSONPath array selector', () {
      final items = _requireString(list, 'items', 'list');
      expect(items, startsWith(r'$.'));
      expect(items, endsWith('[*]'));
    });

    test('pagination declares totalPages and currentPage paths', () {
      final pagination = _asMap(list, 'pagination', 'list');
      for (final key in ['totalPages', 'currentPage']) {
        final entry = _asMap(pagination, key, 'list.pagination');
        _asString(entry, 'path', 'list.pagination.$key');
      }
    });

    test('fields include id, title, coverUrl; tags is multi', () {
      final fields = _asMap(list, 'fields', 'list');
      for (final f in ['id', 'title', 'coverUrl']) {
        expect(fields.containsKey(f), isTrue,
            reason: 'list.fields is missing "$f"');
      }
      final tagsDef = fields['tags'];
      expect(tagsDef, isA<Map>());
      expect((tagsDef as Map)['multi'], isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — api.detail (inline chapters) + api.images
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json api.detail', () {
    late Map<String, dynamic> detail;

    setUp(() {
      final api = _asMap(komiktap, 'api', 'root');
      detail = _asMap(api, 'detail', 'api');
    });

    test('fields include title, coverUrl, tags; tags is multi', () {
      final fields = _asMap(detail, 'fields', 'detail');
      for (final f in ['title', 'coverUrl', 'tags']) {
        expect(fields.containsKey(f), isTrue,
            reason: 'detail.fields is missing "$f"');
      }
      final tagsDef = fields['tags'];
      expect(tagsDef, isA<Map>());
      expect((tagsDef as Map)['multi'], isTrue);
    });

    test('chapters parse inline (items JSONPath, no endpoint)', () {
      final chapters = _asMap(detail, 'chapters', 'detail');
      expect(chapters.containsKey('endpoint'), isFalse,
          reason: 'chapters come from the detail response itself');
      final items = _requireString(chapters, 'items', 'chapters');
      expect(items, startsWith(r'$.'));
      expect(chapters['composeIdWithContentId'], isTrue,
          reason: 'reader endpoint needs {slug}/{number} composite ids');
    });

    test('chapter fields include id, title', () {
      final chapters = (detail['chapters'] as Map).cast<String, dynamic>();
      final chFields = _asMap(chapters, 'fields', 'chapters');
      for (final f in ['id', 'title']) {
        expect(chFields.containsKey(f), isTrue,
            reason: 'chapters.fields is missing "$f"');
      }
    });

    test('api.images uses direct mode with a JSONPath items selector', () {
      final api = _asMap(komiktap, 'api', 'root');
      final images = _asMap(api, 'images', 'api');
      expect(images['mode'], 'direct');
      final items = _requireString(images, 'items', 'images');
      expect(items, startsWith(r'$.'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — navigation (genre taps → raw tag param)
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json navigation', () {
    test('tagQueryMapping default routes rawParam with a param name', () {
      final navigation = _asMap(komiktap, 'navigation', 'root');
      final mapping = _asMap(navigation, 'tagQueryMapping', 'navigation');
      final fallback = _asMap(mapping, 'default', 'tagQueryMapping');
      expect(fallback['mode'], 'rawParam');
      _asString(fallback, 'param', 'tagQueryMapping.default');
      expect(fallback['valueSource'], isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — searchForm
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json searchForm', () {
    late Map<String, dynamic> searchForm;

    setUp(() {
      searchForm = _asMap(komiktap, 'searchForm', 'root');
    });

    test('has urlPattern string', () {
      _asString(searchForm, 'urlPattern', 'searchForm');
    });

    test('urlPattern references the search endpoint', () {
      final ref = searchForm['urlPattern'] as String;
      expect(ref, 'search');
      final api = _asMap(komiktap, 'api', 'root');
      final endpoints = _asMap(api, 'endpoints', 'api');
      expect(endpoints.containsKey(ref), isTrue,
          reason: 'searchForm.urlPattern "$ref" is not an api endpoint');
    });

    test('has params block with at least query and page entries', () {
      final params = _asMap(searchForm, 'params', 'searchForm');
      expect(params.containsKey('query'), isTrue,
          reason: 'searchForm.params must contain "query"');
      expect(params.containsKey('page'), isTrue,
          reason: 'searchForm.params must contain "page"');
    });

    test('each param has queryParam and type fields', () {
      final params = (searchForm['params'] as Map).cast<String, dynamic>();
      for (final entry in params.entries) {
        final def = (entry.value as Map).cast<String, dynamic>();
        _asString(def, 'queryParam', 'searchForm.params.${entry.key}');
        _asString(def, 'type', 'searchForm.params.${entry.key}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // nhentai-config.json
  // ─────────────────────────────────────────────────────────────────────────

  group('nhentai-config.json', () {
    test('source is "nhentai"', () {
      expect(nhentai['source'], 'nhentai');
    });

    test('has api block (nhentai uses REST adapter)', () {
      _hasKey(nhentai, 'api', 'root');
      expect(nhentai['api'], isA<Map>());
    });

    test('api block has endpoints defined', () {
      final api = (nhentai['api'] as Map).cast<String, dynamic>();
      expect(api.containsKey('endpoints'), isTrue,
          reason: 'nhentai api block must have endpoints');
    });
  });
}
