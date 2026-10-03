import 'dart:convert';
import 'dart:io';

import 'package:kuron_config_generator/src/validation/fix_applier.dart';
import 'package:kuron_config_generator/src/validation/fix_suggestion.dart';
import 'package:test/test.dart';

void main() {
  group('FixApplier (conformance-loop 2.2)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fix_applier_test');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    String writeConfig(Map<String, Object?> json) {
      final file = File('${dir.path}/x-config.json');
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(json));
      return file.path;
    }

    Map<String, dynamic> readConfig(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    test('applies schemaVersionMissing without touching anything else', () {
      final path = writeConfig({'source': 'x', 'baseUrl': 'https://x.test'});
      final result = FixApplier.applyFile(path, const [
        FixSuggestion(
          diagnosticCode: 'schemaVersionMissing',
          suggestionText: 'Add schemaVersion.',
        ),
      ]);

      expect(result.applied, ['schemaVersionMissing']);
      expect(result.skipped, isEmpty);
      final after = readConfig(path);
      expect(after['schemaVersion'], '2.0');
      expect(after['source'], 'x');
    });

    test('prose suggestions are skipped, file untouched', () {
      final path = writeConfig({'source': 'x'});
      final before = File(path).readAsStringSync();
      final result = FixApplier.applyFile(path, const [
        FixSuggestion(
          diagnosticCode: 'reader.configError',
          suggestionText: 'Check the reader selector.',
          targetFeature: 'reader',
        ),
      ]);

      expect(result.applied, isEmpty);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single, contains('reader.configError'));
      expect(File(path).readAsStringSync(), before);
    });

    test('without --fix semantics: no suggestions means no write', () {
      final path = writeConfig({'source': 'x'});
      final before = File(path).readAsStringSync();
      final result = FixApplier.applyFile(path, const []);

      expect(result.applied, isEmpty);
      expect(result.skipped, isEmpty);
      expect(File(path).readAsStringSync(), before);
    });
  });
}
