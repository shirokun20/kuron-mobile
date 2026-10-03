import 'dart:convert';
import 'dart:io';

import 'fix_suggestion.dart';

// Applies deterministic fix suggestions to a config file.
//
// Only allowlisted diagnostics with exact values are applied
// (currently: `schemaVersionMissing` → `schemaVersion: '2.0'`).
// Everything else is reported as skipped with a reason — prose
// suggestions need human judgment and must never be auto-applied.
class FixApplier {
  FixApplier._();

  /// Deterministic values keyed by diagnostic code.
  static const Map<String, Map<String, Object?>> _allowlistedValues = {
    'schemaVersionMissing': {'schemaVersion': '2.0'},
  };

  /// Applies [suggestions] to the JSON config at [configPath].
  /// Returns applied codes and skipped codes with reasons.
  /// The file is rewritten only when at least one fix applies.
  static ({List<String> applied, List<String> skipped}) applyFile(
    String configPath,
    List<FixSuggestion> suggestions,
  ) {
    final applied = <String>[];
    final skipped = <String>[];
    final seen = <String>{};

    final file = File(configPath);
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    var changed = false;
    for (final suggestion in suggestions) {
      if (!seen.add(suggestion.diagnosticCode)) continue;
      final values = _allowlistedValues[suggestion.diagnosticCode];
      if (values == null) {
        skipped.add(
            '${suggestion.diagnosticCode}: needs human judgment — not auto-applied');
        continue;
      }
      for (final entry in values.entries) {
        if (raw[entry.key] != entry.value) {
          raw[entry.key] = entry.value;
          changed = true;
        }
      }
      applied.add(suggestion.diagnosticCode);
    }

    if (changed) {
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(raw));
    }
    return (applied: applied, skipped: skipped);
  }
}
