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

// Validate a single field definition value: either a String shorthand or
// a Map with at least a "selector" key.
void _validateFieldDef(dynamic def, String ctx) {
  if (def is String) {
    expect(def.trim(), isNotEmpty, reason: '$ctx: field def String is empty');
    return;
  }
  expect(def, isA<Map>(), reason: '$ctx: field def must be String or Map');
  final m = (def as Map).cast<String, dynamic>();
  _asString(m, 'selector', '$ctx fieldDef');
}

// Validate the `list` config block in a URL pattern.
void _validateListBlock(Map<String, dynamic> listConfig, String ctx) {
  _asString(listConfig, 'container', '$ctx.list');

  final fields = _asMap(listConfig, 'fields', '$ctx.list');
  expect(fields, isNotEmpty, reason: '$ctx.list.fields must not be empty');
  for (final entry in fields.entries) {
    _validateFieldDef(entry.value, '$ctx.list.fields.${entry.key}');
  }

  // pagination is optional, but if present must be a map
  if (listConfig.containsKey('pagination')) {
    expect(listConfig['pagination'], isA<Map>(),
        reason: '$ctx.list.pagination must be a JSON object');
    final pag = (listConfig['pagination'] as Map).cast<String, dynamic>();
    final hasNext = pag.containsKey('next') || pag.containsKey('alt');
    expect(hasNext, isTrue,
        reason: '$ctx.list.pagination must have "next" or "alt" key');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// komiktap-config.json
// ═══════════════════════════════════════════════════════════════════════════

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

    test('has scraper block', () {
      _asMap(komiktap, 'scraper', 'root');
    });

    test('has searchForm block', () {
      _asMap(komiktap, 'searchForm', 'root');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — scraper.urlPatterns
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json scraper.urlPatterns', () {
    late Map<String, dynamic> urlPatterns;

    setUp(() {
      final scraper = (komiktap['scraper'] as Map).cast<String, dynamic>();
      urlPatterns = _asMap(scraper, 'urlPatterns', 'scraper');
    });

    test(
        'has required pattern keys: home, homePage, search, genreSearch, detail, chapter',
        () {
      for (final key in [
        'home',
        'homePage',
        'search',
        'genreSearch',
        'detail',
        'chapter'
      ]) {
        expect(urlPatterns.containsKey(key), isTrue,
            reason: 'urlPatterns is missing "$key"');
      }
    });

    test('"detail" and "chapter" are plain String URL templates', () {
      expect(urlPatterns['detail'], isA<String>());
      expect(urlPatterns['chapter'], isA<String>());
      expect((urlPatterns['detail'] as String), contains('{id}'));
      expect((urlPatterns['chapter'] as String), contains('{id}'));
    });

    test('"home" pattern has valid list block', () {
      final home = urlPatterns['home'] as Map;
      final homeMap = home.cast<String, dynamic>();
      _asString(homeMap, 'url', 'home');
      final list = _asMap(homeMap, 'list', 'home');
      _validateListBlock(list, 'home');
    });

    test('"home" list has required content fields: id, title, coverUrl', () {
      final homeMap = (urlPatterns['home'] as Map).cast<String, dynamic>();
      final fields =
          ((homeMap['list'] as Map)['fields'] as Map).cast<String, dynamic>();
      for (final f in ['id', 'title', 'coverUrl']) {
        expect(fields.containsKey(f), isTrue,
            reason: 'home.list.fields is missing "$f" field');
      }
    });

    test('"home" id field has transform:slug (for URL→slug extraction)', () {
      final homeMap = (urlPatterns['home'] as Map).cast<String, dynamic>();
      final fields =
          ((homeMap['list'] as Map)['fields'] as Map).cast<String, dynamic>();
      final idDef = fields['id'];
      expect(idDef, isA<Map>(),
          reason: 'home.list.fields.id must be a Map with transform');
      expect((idDef as Map)['transform'], 'slug',
          reason: 'home.list.fields.id must have "transform":"slug"');
      expect(idDef['attribute'], 'href',
          reason: 'home.list.fields.id must extract "href" attribute');
    });

    test('"homePage" inherits from "home" and has {page} in url', () {
      final homePageVal = urlPatterns['homePage'];
      expect(homePageVal, isA<Map>());
      final homePageMap = (homePageVal as Map).cast<String, dynamic>();
      _asString(homePageMap, 'url', 'homePage');
      expect((homePageMap['url'] as String), contains('{page}'));
      expect(homePageMap['inherits'], 'home',
          reason: 'homePage should inherit from home');
    });

    test('"search" pattern has list block with {query} in url', () {
      final searchMap = (urlPatterns['search'] as Map).cast<String, dynamic>();
      _asString(searchMap, 'url', 'search');
      expect((searchMap['url'] as String), contains('{query}'));
      final list = _asMap(searchMap, 'list', 'search');
      _validateListBlock(list, 'search');
    });

    test('"genreSearch" inherits from "search" and has {tag} in url', () {
      final genreVal = urlPatterns['genreSearch'];
      expect(genreVal, isA<Map>());
      final genreMap = (genreVal as Map).cast<String, dynamic>();
      expect((genreMap['url'] as String), contains('{tag}'));
      expect(genreMap['inherits'], 'search');
    });

    test('"inherits" values reference existing pattern keys', () {
      for (final entry in urlPatterns.entries) {
        if (entry.value is! Map) continue;
        final patMap = (entry.value as Map).cast<String, dynamic>();
        final inherits = patMap['inherits'] as String?;
        if (inherits != null) {
          expect(urlPatterns.containsKey(inherits), isTrue,
              reason:
                  '"${entry.key}".inherits = "$inherits" but that key does not exist in urlPatterns');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — scraper.selectors.detail
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json scraper.selectors.detail', () {
    late Map<String, dynamic> detail;

    setUp(() {
      final scraper = (komiktap['scraper'] as Map).cast<String, dynamic>();
      final selectors = _asMap(scraper, 'selectors', 'scraper');
      detail = _asMap(selectors, 'detail', 'selectors');
    });

    test('detail has fields block with at least title, coverUrl, tags', () {
      final fields = _asMap(detail, 'fields', 'detail');
      for (final f in ['title', 'coverUrl', 'tags']) {
        expect(fields.containsKey(f), isTrue,
            reason: 'detail.fields is missing "$f"');
      }
    });

    test('tags field has multi:true', () {
      final fields = (detail['fields'] as Map).cast<String, dynamic>();
      final tagsDef = fields['tags'];
      expect(tagsDef, isA<Map>(), reason: 'tags field def must be a Map');
      expect((tagsDef as Map)['multi'], isTrue,
          reason:
              'tags field must have "multi":true for correct multi-value extraction');
    });

    test('detail has chapters block with container and fields', () {
      _hasKey(detail, 'chapters', 'detail');
      final chapters = _asMap(detail, 'chapters', 'detail');
      _asString(chapters, 'container', 'chapters');
      final chFields = _asMap(chapters, 'fields', 'chapters');
      expect(chFields, isNotEmpty);
    });

    test('chapter fields include id, title, date', () {
      final chapters = (detail['chapters'] as Map).cast<String, dynamic>();
      final chFields = (chapters['fields'] as Map).cast<String, dynamic>();
      for (final f in ['id', 'title', 'date']) {
        expect(chFields.containsKey(f), isTrue,
            reason: 'chapters.fields is missing "$f"');
      }
    });

    test('chapter id field has transform:slug', () {
      final chapters = (detail['chapters'] as Map).cast<String, dynamic>();
      final chFields = (chapters['fields'] as Map).cast<String, dynamic>();
      final idDef = chFields['id'];
      expect(idDef, isA<Map>());
      expect((idDef as Map)['transform'], 'slug',
          reason:
              'chapter id must have "transform":"slug" so chapter URLs become slugs');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // komiktap — scraper.selectors.reader
  // ─────────────────────────────────────────────────────────────────────────

  group('komiktap-config.json scraper.selectors.reader', () {
    late Map<String, dynamic> reader;

    setUp(() {
      final scraper = (komiktap['scraper'] as Map).cast<String, dynamic>();
      final selectors = _asMap(scraper, 'selectors', 'scraper');
      reader = _asMap(selectors, 'reader', 'selectors');
    });

    test('has tsReaderRegex (non-empty string)', () {
      _asString(reader, 'tsReaderRegex', 'reader');
    });

    test('tsReaderRegex is a parseable RegExp', () {
      final regexStr = reader['tsReaderRegex'] as String;
      expect(() => RegExp(regexStr), returnsNormally,
          reason: 'tsReaderRegex "$regexStr" is not a valid RegExp');
    });

    test('has nav block with next and prev CSS selectors', () {
      final nav = _asMap(reader, 'nav', 'reader');
      _asString(nav, 'next', 'reader.nav');
      _asString(nav, 'prev', 'reader.nav');
    });

    test('has container selector', () {
      _asString(reader, 'container', 'reader');
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

    test('urlPattern references an existing urlPatterns key', () {
      final scraper = (komiktap['scraper'] as Map).cast<String, dynamic>();
      final urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, dynamic>();
      final ref = searchForm['urlPattern'] as String;
      expect(urlPatterns.containsKey(ref), isTrue,
          reason:
              'searchForm.urlPattern "$ref" does not exist in scraper.urlPatterns');
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
