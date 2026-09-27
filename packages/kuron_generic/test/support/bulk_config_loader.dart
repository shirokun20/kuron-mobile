// Shared config + fixture resolver for the generated `bulk_*_live_test.dart`
// files.
//
// Local paths win so offline `flutter test` keeps working whenever a
// generated config exists; otherwise the config comes from the remote
// kuron-extensions manifest (see [loadConfigRemote]). Callers that cannot
// continue without a config are expected to `markTestSkipped` rather than
// fail — an unpublished source is not a regression.
library;

import 'dart:convert';
import 'dart:io';

import 'config_test_harness.dart';

/// Directories searched for locally generated artifacts, relative to the Dart
/// working directory (workspace root or `packages/kuron_generic/`).
const List<String> kGeneratedDirCandidates = <String>[
  'build/generated',
  'packages/kuron_generic/build/generated',
];

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
/// Tries local generated configs first, then falls back to the remote
/// kuron-extensions manifest. Throws [StateError] when the source is not
/// available anywhere — callers turn that into a skip.
Future<Map<String, Object?>> loadBulkConfig(String sourceId) async {
  final String name = '$sourceId-config.json';
  final String? local = _readIfExists(kGeneratedDirCandidates, name);
  if (local != null) {
    return (jsonDecode(local) as Map).cast<String, Object?>();
  }
  try {
    return await loadConfigRemote(name);
  } on StateError catch (e) {
    throw StateError(
      'Cannot locate $name locally (looked in '
      '${kGeneratedDirCandidates.join(', ')}) or in the kuron-extensions '
      'manifest: ${e.message}',
    );
  }
}

/// Reads the golden `<screen>.html` fixture for [sourceId], or null when none
/// exists (or when running live, where fixtures are bypassed).
String? loadBulkFixture(String sourceId, String screen, {required bool live}) {
  if (live) return null;
  return _readIfExists(kFixtureDirCandidates, '$sourceId/$screen.html');
}
