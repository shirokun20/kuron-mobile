// Shared config validation test harness (task 4.7 + 4.8).
///
// Usage — in any test file, call [runConfigContractTests]:
// ```dart
// runConfigContractTests(
//   configName: 'mangadex-config.json',
//   expectedOverallStatus: CompatibilityStatus.compatible,
//   expectedFeatures: {FeatureKind.search: FeatureStatus.inferred},
//   expectedDiagCodes: {'schemaVersionMissing'},
// );
// ```
///
// The harness locates configs via a standard search path relative to the
// Dart working directory (works from both workspace root and from
// `packages/kuron_generic/`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:kuron_core/kuron_core.dart';
import 'package:test/test.dart';

import 'package:kuron_generic/src/config/source_config_parser.dart';

// Remote config source: kuron-extensions repo (replaces the retired local
// `informations/configs/` directory). Configs resolve through the published
// manifest, so `config/<lang>/<file>` bucketing never has to be hardcoded
// in tests.
const String kExtRepoRawBase =
    'https://raw.githubusercontent.com/shirokun20/kuron-extensions/main';

// Filename (`<id>-config.json`) → manifest `url` (`config/<lang>/<file>`).
// Fetched once per test run.
Map<String, String>? _extConfigUrls;

Future<Map<String, String>> _extConfigUrlMap() async {
  final cached = _extConfigUrls;
  if (cached != null) return cached;
  final request = await HttpClient().getUrl(
    Uri.parse('$kExtRepoRawBase/manifest.json'),
  );
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError(
      'Cannot fetch kuron-extensions manifest '
      '(HTTP ${response.statusCode}). Check network access.',
    );
  }
  final manifest = jsonDecode(body) as Map;
  final urls = <String, String>{};
  for (final entry in (manifest['installableSources'] as List)) {
    final url = (entry as Map)['url'] as String;
    urls[url.split('/').last] = url;
  }
  _extConfigUrls = urls;
  return urls;
}

// Load a config JSON by [name] (`<id>-config.json`) from kuron-extensions.
Future<Map<String, Object?>> loadConfigRemote(String name) async {
  final urls = await _extConfigUrlMap();
  final path = urls[name];
  if (path == null) {
    throw StateError(
      'Config $name is not registered in the kuron-extensions manifest.',
    );
  }
  final request =
      await HttpClient().getUrl(Uri.parse('$kExtRepoRawBase/$path'));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('Cannot fetch config $name (HTTP ${response.statusCode}).');
  }
  return (jsonDecode(body) as Map).cast<String, Object?>();
}

// Metadata describing the expected outcome for one source config.
class ConfigContractCase {
  const ConfigContractCase({
    required this.configName,
    this.expectedOverallStatus,
    this.expectedFeatures = const <FeatureKind, FeatureStatus>{},
    this.expectedDiagCodes = const <String>{},
    this.forbiddenDiagCodes = const <String>{},
    this.registeredPlugins = const <String>{},
  });

  // File name inside `informations/configs/`.
  final String configName;

  // If set, the overall [CompatibilityStatus] must match exactly.
  final CompatibilityStatus? expectedOverallStatus;

  // Per-feature expectations. Only listed features are verified.
  final Map<FeatureKind, FeatureStatus> expectedFeatures;

  // Diagnostic codes that MUST appear in the report.
  final Set<String> expectedDiagCodes;

  // Diagnostic codes that MUST NOT appear.
  final Set<String> forbiddenDiagCodes;

  // Plugins to register for this test run.
  final Set<String> registeredPlugins;
}

// Registers a `group` of tests from [cases] using the shared harness.
///
// Each [ConfigContractCase] becomes a `group` with individual `test` entries
// for overall status, per-feature status, and diagnostics.
///
// Pass [parserFactory] to use a custom [SourceConfigParser]; otherwise the
// default (no registered primitives / plugins) is used.
void runConfigContractTests(
  List<ConfigContractCase> cases, {
  SourceConfigParser Function(ConfigContractCase)? parserFactory,
}) {
  for (final ConfigContractCase c in cases) {
    group(c.configName, () {
      late SourceConfigParseResult result;

      setUpAll(() async {
        final SourceConfigParser parser = parserFactory != null
            ? parserFactory(c)
            : SourceConfigParser(registeredPlugins: c.registeredPlugins);
        result = parser.parse(await loadConfigRemote(c.configName));
      });

      if (c.expectedOverallStatus != null) {
        test('overall status is ${c.expectedOverallStatus!.name}', () {
          expect(result.report.overallStatus, c.expectedOverallStatus);
        });
      }

      for (final MapEntry<FeatureKind, FeatureStatus> e
          in c.expectedFeatures.entries) {
        test('feature ${e.key.name} is ${e.value.name}', () {
          expect(
            result.report.featureStatuses[e.key] ?? FeatureStatus.notDeclared,
            e.value,
            reason: '${e.key.name} should be ${e.value.name}',
          );
        });
      }

      for (final String code in c.expectedDiagCodes) {
        test('diagnostic $code is present', () {
          expect(
            result.report.diagnostics
                .any((ValidationDiagnostic d) => d.code == code),
            isTrue,
            reason: 'Expected diagnostic code $code to be present',
          );
        });
      }

      for (final String code in c.forbiddenDiagCodes) {
        test('diagnostic $code is absent', () {
          expect(
            result.report.diagnostics
                .any((ValidationDiagnostic d) => d.code == code),
            isFalse,
            reason: 'Diagnostic code $code should NOT be present',
          );
        });
      }
    });
  }
}
