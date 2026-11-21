// Shared config + fixture resolver for the generated `bulk_*_live_test.dart`
// files.
//
// Default mode (`LIVE != 1`) is **strictly offline**:
//   * configs come from locally generated files or the local kuron-extensions
//     checkout (READ-ONLY — never copied into / committed to this repo),
//   * golden HTML fixtures are replayed through a fail-fast [HttpClientAdapter],
//   * any request whose URL is not covered by a fixture throws immediately,
//     so no site HTTP can escape to the network.
//
// If no local config source exists (e.g. CI), loading throws a StateError and
// the generated test group is skipped — an unavailable source is not a failure.
// `LIVE=1` keeps the original behaviour: configs come from the kuron-extensions
// manifest and the adapter talks to the real site (no fixtures, no mock).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'config_test_harness.dart';

/// True only when the caller explicitly opted into real-site tests.
final bool isBulkLive = Platform.environment['LIVE'] == '1';

/// Directories searched for locally generated artifacts, relative to the Dart
/// working directory (workspace root or `packages/kuron_generic/`).
const List<String> kGeneratedDirCandidates = <String>[
  'build/generated',
  'packages/kuron_generic/build/generated',
];

/// Default location of the local kuron-extensions checkout. Override with the
/// `KURON_EXTENSIONS_DIR` environment variable on other machines.
const String kDefaultExtensionsDir =
    '/Users/asix/Documents/ektensi/kuron-extensions';

/// Language-bucketed config directories inside the kuron-extensions checkout.
/// Resolved at call time so the env override is honoured.
List<String> _externalConfigDirs() {
  final String root =
      Platform.environment['KURON_EXTENSIONS_DIR'] ?? kDefaultExtensionsDir;
  return <String>[
    '$root/config',
    for (final String lang
        in <String>['en', 'id', 'global', 'ja', 'vi', 'ch', 'new'])
      '$root/config/$lang',
  ];
}

const List<String> kFixtureDirCandidates = <String>[
  'test/integration/fixtures',
  'packages/kuron_generic/test/integration/fixtures',
];

/// Reads `<dir>/<file>` if it exists, else returns null.
String? _readIfExists(List<String> dirs, String file) {
  for (final String dir in dirs) {
    final File f = File('$dir/$file');
    if (f.existsSync()) return f.readAsStringSync();
  }
  return null;
}

/// Loads `<sourceId>-config.json` for a bulk test.
///
/// Offline mode reads a locally generated config, then the READ-ONLY local
/// kuron-extensions checkout; a missing config is reported as [StateError] so
/// callers can skip instead of reaching the network. LIVE mode additionally
/// falls back to the published kuron-extensions manifest.
Future<Map<String, Object?>> loadBulkConfig(String sourceId) async {
  final String name = '$sourceId-config.json';
  final String? local = _readIfExists(kGeneratedDirCandidates, name);
  if (local != null) {
    return (jsonDecode(local) as Map).cast<String, Object?>();
  }
  final String? external = _readIfExists(_externalConfigDirs(), name);
  if (external != null) {
    return (jsonDecode(external) as Map).cast<String, Object?>();
  }
  if (isBulkLive) {
    try {
      return await loadConfigRemote(name);
    } on StateError catch (e) {
      throw StateError('config unavailable: $name (${e.message})');
    }
  }
  throw StateError(
    'config unavailable: $name (looked in '
    '${[...kGeneratedDirCandidates, ..._externalConfigDirs()].join(', ')}). '
    'Set KURON_EXTENSIONS_DIR or use LIVE=1.',
  );
}

/// Reads the golden `<screen>.html` fixture for [sourceId], or null when none
/// exists (or when running live, where fixtures are bypassed).
String? loadBulkFixture(String sourceId, String screen, {required bool live}) {
  if (live) return null;
  return _readIfExists(kFixtureDirCandidates, '$sourceId/$screen.html');
}

/// True when a screen can be replayed without network access.
///
/// * `home` needs a home fixture.
/// * `search` needs a search fixture (or a home fixture the config reuses for
///   browse/search).
/// * `detail` needs home + detail fixtures.
/// * `reader` needs home + detail + reader fixtures, except gallery-only
///   sources whose images come from the detail page itself.
bool canReplayBulkScreen(
  String sourceId,
  Map<String, Object?> config,
  String screen, {
  required bool live,
}) {
  if (live) return true;
  final home = loadBulkFixture(sourceId, 'home', live: false);
  if (home == null) return false;
  // A saved fixture whose list container no longer exists in the published
  // config is stale, not a parser regression — skip instead of failing.
  if (!_homeSelectorPresent(home, config)) return false;
  if (screen == 'home') return true;
  final search = loadBulkFixture(sourceId, 'search', live: false);
  if (screen == 'search') {
    return search != null || _searchReusesHome(config);
  }
  final detail = loadBulkFixture(sourceId, 'detail', live: false);
  if (detail == null) return false;
  if (screen == 'detail') return true;
  if (_isGalleryOnly(config)) return true;
  return loadBulkFixture(sourceId, 'reader', live: false) != null;
}

/// True when the fixture still contains the config's home list container.
/// Uses the first CSS class token in the container selector so compound
/// selectors like `.listupd .bsx` or `div.grid a[...]` work too.
bool _homeSelectorPresent(String fixtureHtml, Map<String, Object?> config) {
  final home = ((config['scraper'] as Map?)?['urlPatterns'] as Map?)?['home'];
  String? container;
  if (home is Map) {
    final list = home['list'];
    if (list is Map) container = list['container']?.toString();
  }
  if (container == null || container.isEmpty) return true;
  final token = RegExp(r'[.]([A-Za-z0-9_-]+)').firstMatch(container)?.group(1);
  if (token == null || token.isEmpty) return true;
  return fixtureHtml.contains(token);
}

bool _searchReusesHome(Map<String, Object?> config) {
  final patterns =
      ((config['scraper'] as Map?)?['urlPatterns'] as Map?) ?? const {};
  final search = patterns['search'];
  if (search is Map && search['inherits'] == 'home') return true;
  return false;
}

bool _isGalleryOnly(Map<String, Object?> config) {
  final reader = ((config['scraper'] as Map?)?['selectors'] as Map?)?['reader'];
  if (reader is! Map) return false;
  final mode = reader['mode']?.toString();
  return mode == 'hentaifoxCdn' || mode == 'gallery';
}

/// Builds permissive regular expressions for the config's *list* URL patterns
/// (home / homePage / search / tag / genre). Detail and chapter patterns are
/// deliberately excluded: requests to them are unmocked and fail fast.
List<RegExp> _listUrlPatterns(Map<String, Object?> config) {
  final patterns =
      ((config['scraper'] as Map?)?['urlPatterns'] as Map?) ?? const {};
  final result = <RegExp>[];
  for (final entry in patterns.entries) {
    final key = entry.key.toString().toLowerCase();
    if (key == 'detail' ||
        key == 'chapter' ||
        key.startsWith('detail') ||
        key.startsWith('chapter')) {
      continue;
    }
    final raw = switch (entry.value) {
      final String s => s,
      final Map m => m['url']?.toString() ?? '',
      _ => '',
    };
    if (raw.isEmpty) continue;
    // Replace `{placeholder}` segments with a permissive wildcard, escape the
    // static parts, and match anywhere in the full URL (baseUrl may carry a
    // path prefix).
    final parts = raw.split(RegExp(r'\{[^}]+\}'));
    final source = parts.map(RegExp.escape).join(r'.+?');
    if (source.isEmpty) continue;
    result.add(RegExp(source));
  }
  return result;
}

/// Offline [HttpClientAdapter] that serves [homeHtml] for list-pattern GET
/// requests and throws on everything else — guaranteeing no HTTP escapes.
HttpClientAdapter createBulkOfflineAdapter(
  Map<String, Object?> config,
  String homeHtml,
) {
  return _OfflineFixtureAdapter(
    body: homeHtml,
    allowed: _listUrlPatterns(config),
  );
}

class _OfflineFixtureAdapter implements HttpClientAdapter {
  _OfflineFixtureAdapter({required this.body, required this.allowed});

  final String body;
  final List<RegExp> allowed;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    if (options.method.toUpperCase() == 'GET' &&
        allowed.any((pattern) => pattern.hasMatch(url))) {
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        },
      );
    }
    throw StateError('Offline replay: unmocked ${options.method} request $url');
  }

  @override
  void close({bool force = false}) {}
}
