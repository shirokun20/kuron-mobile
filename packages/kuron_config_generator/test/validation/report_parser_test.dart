import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:kuron_config_generator/src/validation/report_parser.dart';
import 'package:kuron_core/src/compat/feature_kind.dart';

void main() {
  group('ReportParser', () {
    group('parse valid JSON (R2.1)', () {
      test('extracts all fields from full valid report', () {
        final json = '''{
          "sourceId": "mangadex",
          "overallStatus": "configError",
          "featureStatuses": {
            "home": "compatible",
            "search": "compatible",
            "reader": "configError",
            "download": "compatible"
          },
          "diagnostics": [
            {
              "severity": "error",
              "code": "reader.configError",
              "message": "No image selector matched for reader.",
              "feature": "reader"
            }
          ]
        }''';

        final report = ReportParser.parse(json);

        expect(report.sourceId, 'mangadex');
        expect(report.overallStatus, 'configError');
        expect(report.featureStatuses, {
          'home': 'compatible',
          'search': 'compatible',
          'reader': 'configError',
          'download': 'compatible',
        });
        expect(report.diagnostics, hasLength(1));
        expect(report.diagnostics[0].severity, 'error');
        expect(report.diagnostics[0].code, 'reader.configError');
        expect(report.diagnostics[0].message,
            'No image selector matched for reader.');
        expect(report.diagnostics[0].feature, 'reader');
      });
    });

    group('edge cases', () {
      test('empty diagnostics list', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "compatible",
          "diagnostics": []
        }''';

        final report = ReportParser.parse(json);
        expect(report.diagnostics, isEmpty);
      });

      test('null diagnostics defaults to empty list', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "compatible"
        }''';

        final report = ReportParser.parse(json);
        expect(report.diagnostics, isEmpty);
      });

      test('null featureStatuses defaults to empty map', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "compatible"
        }''';

        final report = ReportParser.parse(json);
        expect(report.featureStatuses, isEmpty);
      });
    });

    group('missing required fields → FormatException (R2.4)', () {
      test('missing sourceId throws FormatException', () {
        final json = '''{
          "overallStatus": "compatible"
        }''';

        expect(() => ReportParser.parse(json), throwsA(isA<FormatException>()));
      });

      test('missing overallStatus throws FormatException', () {
        final json = '''{
          "sourceId": "test"
        }''';

        expect(() => ReportParser.parse(json), throwsA(isA<FormatException>()));
      });

      test('both missing throws FormatException', () {
        final json = '''{
          "diagnostics": []
        }''';

        expect(() => ReportParser.parse(json), throwsA(isA<FormatException>()));
      });

      test('sourceId is non-string throws FormatException', () {
        final json = '''{
          "sourceId": 123,
          "overallStatus": "compatible"
        }''';

        expect(() => ReportParser.parse(json), throwsA(isA<FormatException>()));
      });
    });

    group('feature field handling (R2.2)', () {
      test('feature set to null when absent', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {
              "severity": "error",
              "code": "some.code",
              "message": "Something failed."
            }
          ]
        }''';

        final report = ReportParser.parse(json);
        expect(report.diagnostics[0].feature, isNull);
      });

      test('feature set to null when null', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {
              "severity": "error",
              "code": "some.code",
              "message": "Something failed.",
              "feature": null
            }
          ]
        }''';

        final report = ReportParser.parse(json);
        expect(report.diagnostics[0].feature, isNull);
      });

      test('feature set to null when empty string', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {
              "severity": "error",
              "code": "some.code",
              "message": "Something failed.",
              "feature": ""
            }
          ]
        }''';

        final report = ReportParser.parse(json);
        expect(report.diagnostics[0].feature, isNull);
      });

      test('unknown feature name is set to null (R2.2)', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {
              "severity": "error",
              "code": "some.code",
              "message": "Something failed.",
              "feature": "nonexistentFeature"
            }
          ]
        }''';

        final report = ReportParser.parse(json);
        // Per R2.2: unknown feature names should be null
        expect(report.diagnostics[0].feature, isNull);
      });
    });

    group('severity levels', () {
      test('parses error severity', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {"severity": "error", "code": "c1", "message": "m"}
          ]
        }''';
        expect(ReportParser.parse(json).diagnostics[0].severity, 'error');
      });

      test('parses warning severity', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {"severity": "warning", "code": "c1", "message": "m"}
          ]
        }''';
        expect(ReportParser.parse(json).diagnostics[0].severity, 'warning');
      });

      test('parses info severity', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {"severity": "info", "code": "c1", "message": "m"}
          ]
        }''';
        expect(ReportParser.parse(json).diagnostics[0].severity, 'info');
      });

      test('defaults to error when severity missing', () {
        final json = '''{
          "sourceId": "test",
          "overallStatus": "configError",
          "diagnostics": [
            {"code": "c1", "message": "m"}
          ]
        }''';
        expect(ReportParser.parse(json).diagnostics[0].severity, 'error');
      });
    });
  });

  group('ParsedReport.fromJson', () {
    test('empty map throws FormatException', () {
      expect(
        () => ParsedReport.fromJson({}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ReportDiagnostic.fromJson', () {
    test('defaults for missing fields', () {
      final diag = ReportDiagnostic.fromJson({});
      expect(diag.severity, 'error');
      expect(diag.code, 'unknown');
      expect(diag.message, '');
      expect(diag.feature, isNull);
    });
  });

  // ── Property test: Report Parsing Completeness ───────────────────
  //
  // **Validates: Requirements 2.1, 2.3**
  // For any valid JSON report with sourceId and overallStatus,
  // ParsedReport.fromJson returns non-null fields with all diagnostics
  // faithfully preserved.

  final rng = Random(42); // seeded for reproducibility

  String randomString(int min, int max) {
    final len = min + rng.nextInt(max - min + 1);
    return String.fromCharCodes(List.generate(
        len,
        (_) => rng.nextBool()
            ? rng.nextInt(26) + (rng.nextBool() ? 65 : 97) // A-Z/a-z
            : rng.nextInt(10) + 48)); // 0-9
  }

  String randomStatus() {
    const s = [
      'compatible',
      'partiallyCompatible',
      'configError',
      'needsEngineSupport',
      'needsAuthSupport',
      'blockedBySiteProtection',
    ];
    return s[rng.nextInt(s.length)];
  }

  String randomFeatureKindName() {
    final kinds = FeatureKind.values;
    return kinds[rng.nextInt(kinds.length)].name;
  }

  bool isValidFeatureKindName(String? name) {
    if (name == null || name.isEmpty) return false;
    try {
      FeatureKind.values.byName(name);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  Map<String, Object?> randomDiagnostic() {
    final severity = ['error', 'warning', 'info'][rng.nextInt(3)];
    final code = randomString(3, 20);
    final message = randomString(5, 40);
    final hasFeature = rng.nextBool();
    // 50/50: valid FeatureKind name or invalid string
    final feature = hasFeature
        ? (rng.nextBool() ? randomFeatureKindName() : randomString(5, 10))
        : null;
    return {
      'severity': severity,
      'code': code,
      'message': message,
      if (hasFeature) 'feature': feature,
    };
  }

  group('Property: Report Parsing Completeness (R2.1, R2.3)', () {
    test(
        'ParsedReport.fromJson faithfully preserves all fields for random valid inputs',
        () {
      for (var i = 0; i < 200; i++) {
        // ── Generate random input ─────────────────────
        final sourceId = randomString(1, 20);
        final overallStatus = randomStatus();
        final diagCount = rng.nextInt(10);
        final diagnostics = List.generate(diagCount, (_) => randomDiagnostic());
        final haveFeatureStatuses = rng.nextBool();
        final featureStatuses = haveFeatureStatuses
            ? {
                for (var j = 0; j < rng.nextInt(6); j++)
                  randomFeatureKindName(): randomStatus(),
              }
            : null;

        final json = <String, Object?>{
          'sourceId': sourceId,
          'overallStatus': overallStatus,
          'featureStatuses': ?featureStatuses,
          if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
        };

        // ── Parse ─────────────────────────────────────
        final report = ParsedReport.fromJson(json);

        // ── Assertions ────────────────────────────────
        expect(report.sourceId, sourceId, reason: 'iteration $i: sourceId');
        expect(report.overallStatus, overallStatus,
            reason: 'iteration $i: overallStatus');

        // featureStatuses: entries faithfully preserved when present
        if (featureStatuses != null) {
          for (final entry in featureStatuses.entries) {
            expect(report.featureStatuses[entry.key], entry.value,
                reason: 'iteration $i: featureStatuses["${entry.key}"]');
          }
        } else {
          expect(report.featureStatuses, isEmpty,
              reason: 'iteration $i: featureStatuses absent → empty');
        }

        // diagnostics: same count
        expect(report.diagnostics, hasLength(diagCount),
            reason: 'iteration $i: diagnostic count');

        // diagnostics: each entry faithfully preserved
        for (var j = 0; j < diagCount; j++) {
          final d = report.diagnostics[j];
          final expected = diagnostics[j];
          expect(d.severity, expected['severity'] as String,
              reason: 'iteration $i, diag $j: severity');
          expect(d.code, expected['code'] as String,
              reason: 'iteration $i, diag $j: code');
          expect(d.message, expected['message'] as String,
              reason: 'iteration $i, diag $j: message');

          final rawFeature = expected['feature'] as String?;
          if (isValidFeatureKindName(rawFeature)) {
            expect(d.feature, rawFeature,
                reason: 'iteration $i, diag $j: valid feature');
          } else {
            expect(d.feature, isNull,
                reason:
                    'iteration $i, diag $j: null feature (was $rawFeature)');
          }
        }
      }
    });

    test(
        'Round-trip through ReportParser.parse (JSON encode/decode) preserves fields',
        () {
      for (var i = 0; i < 100; i++) {
        final sourceId = randomString(1, 20);
        final overallStatus = randomStatus();
        final diagCount = rng.nextInt(5);
        final diagnostics = List.generate(diagCount, (_) => randomDiagnostic());

        final jsonMap = <String, Object?>{
          'sourceId': sourceId,
          'overallStatus': overallStatus,
          if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
        };

        // Encode to JSON string, then parse through ReportParser.parse
        final jsonString = jsonEncode(jsonMap);
        final report = ReportParser.parse(jsonString);

        expect(report.sourceId, sourceId, reason: 'roundtrip $i: sourceId');
        expect(report.overallStatus, overallStatus,
            reason: 'roundtrip $i: overallStatus');
        expect(report.diagnostics, hasLength(diagCount),
            reason: 'roundtrip $i: count');
      }
    });
  });
}
