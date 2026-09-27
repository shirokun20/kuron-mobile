import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Validates the publish-ready kuron-extensions payloads in the change
// directory (tasks 6/15/21/27) against the LIVE repo schema, fetched from
// https://github.com/shirokun20/kuron-extensions (manifest.json +
// config/en/mangafire-config.json + config/global/hitomi-config.json).
//
// Schema facts (do not re-invent keys):
// - manifest.json: {schemaVersion, lastUpdated, minimumAppVersion,
//   installableSources[{id, version, url, meta, checksum}]};
//   adapter sources set meta.requiresSpecialAdapter=true.
// - config: {source, version, enabled, defaultLanguage, baseUrl, ui,
//   network, api|scraper, navigation?, searchForm?, contentIdPattern?,
//   features, maintenance?, maintenanceMessage?}.
//   Adapter hint blocks are namespaced (e.g. hitomi `hitomiProtocol`).
// - maintenance is read from manifest meta AND config; no app code
//   consumes network.auth.authType=vrf (inert), so reactivation is a
//   minimal flag flip.
void main() {
  Map<String, dynamic> loadPayload(String name) {
    final candidates = [
      'openspec/changes/add-comix-webview-proxy-source/$name',
      '../../openspec/changes/add-comix-webview-proxy-source/$name',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    }
    fail('payload $name not found');
  }

  test('comix-config.json mirrors the live schema', () {
    final config = loadPayload('comix-config.json');
    expect(config['source'], 'comix');
    expect(config['version'], isNotEmpty);
    expect(config['enabled'], isTrue);
    expect(config['defaultLanguage'], 'en');
    expect(config['baseUrl'], 'https://comix.to');

    // No invented top-level keys (live schema has no schemaVersion,
    // configUrl, bypassType, webview, filters, fallbackBaseUrls here).
    expect(
      config.keys,
      containsAll([
        'source',
        'version',
        'enabled',
        'defaultLanguage',
        'baseUrl',
        'ui',
        'network',
        'api',
        'contentIdPattern',
        'features',
      ]),
    );
    expect(
      config.keys,
      isNot(
        containsAny([
          'schemaVersion',
          'configUrl',
          'bypassType',
          'webview',
          'filters',
          'fallbackBaseUrls',
          'maintenance',
        ]),
      ),
    );

    final ui = config['ui'] as Map<String, dynamic>;
    expect(
      ui.keys,
      containsAll([
        'displayName',
        'iconPath',
        'brandColor',
        'openInBrowserUrl',
      ]),
    );

    final network = config['network'] as Map<String, dynamic>;
    expect(network['requiresBypass'], isTrue);
    expect(
      (network['headers'] as Map).keys,
      containsAll(['Accept', 'Referer', 'User-Agent']),
    );
    expect(
      (network['rateLimit'] as Map)['requestsPerSecond'],
      5,
    );

    final api = config['api'] as Map<String, dynamic>;
    final endpoints = api['endpoints'] as Map<String, dynamic>;
    expect(endpoints['browse'], '/api/v1/manga');
    expect(endpoints['chapters'], '/api/v1/manga/{id}/chapters');
    expect(endpoints['pages'], '/api/v1/chapters/{id}');

    expect(config['contentIdPattern'], '/title/([^/?#]+)');

    final features = config['features'] as Map<String, dynamic>;
    for (final key in [
      'home',
      'search',
      'detail',
      'chapters',
      'reader',
      'download',
      'related',
    ]) {
      expect(features[key], isTrue, reason: key);
    }
    expect(features['comments'], isFalse);
    expect(features['favorite'], isFalse);
  });

  test('comix-manifest-entry.json is publish-ready', () {
    final doc = loadPayload('comix-manifest-entry.json');
    final entry = doc['entry'] as Map<String, dynamic>;
    expect(entry['id'], 'comix');
    expect(entry['url'], 'config/en/comix-config.json');
    final meta = entry['meta'] as Map<String, dynamic>;
    expect(meta['requiresSpecialAdapter'], isTrue);
    expect(meta['contentType'], 'manga');
    expect(meta['language'], 'en');
    expect(entry['checksum'], 'COMPUTE_AT_PUBLISH');
  });

  test('mangafire patch is a minimal flag flip', () {
    final doc = loadPayload('mangafire-config.patch.json');
    final patch = doc['configPatch'] as Map<String, dynamic>;
    // Only flag changes; the inert network.auth vrf block stays untouched.
    expect(patch['enabled'], isTrue);
    expect(patch['maintenance'], isFalse);
    expect(patch['maintenanceMessage'], isNull);
    expect(patch.keys, hasLength(3));
    final metaPatch = doc['manifestMetaPatch'] as Map<String, dynamic>;
    expect(metaPatch['maintenance'], isNull);
    expect(metaPatch['maintenanceMessage'], isNull);
  });
}

Matcher containsAny(List<String> values) => _ContainsAny(values);

class _ContainsAny extends Matcher {
  _ContainsAny(this.values);

  final List<String> values;

  @override
  Description describe(Description description) =>
      description.add('contains any of $values');

  @override
  bool matches(Object? item, Map matchState) {
    if (item is Iterable) {
      return item.any(values.contains);
    }
    return false;
  }
}
