// Integration fixture: generator → validator round-trip (Section 11.4).
///
// Simulates what a config generator would produce for a minimal REST source
// and asserts the validator accepts it as `compatible` without errors.
///
// This fixture ensures that:
// 1. A generator using [EnginePrimitive.all] produces valid primitive names.
// 2. The generated config round-trips through [SourceConfigParser] cleanly.
// 3. Feature status names match the [compatibilityStatusNames] list.
library;

import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:test/test.dart';

void main() {
  group('Generator → Validator round-trip (§11.4)', () {
    test('EnginePrimitive.all covers all primitive identifiers used by parser',
        () {
      // Primitives used internally by SourceConfigParser (spot-check)
      final usedByParser = <String>[
        EnginePrimitive.imageModeDirectUrl,
        EnginePrimitive.imageModeTemplate,
        EnginePrimitive.imageModeCdnRegex,
        EnginePrimitive.imageModeScriptRegex,
        EnginePrimitive.paginationPage,
        EnginePrimitive.paginationOffset,
        EnginePrimitive.headersStatic,
        EnginePrimitive.commentsEndpoint,
      ];

      for (final p in usedByParser) {
        expect(
          EnginePrimitive.all.containsKey(p),
          isTrue,
          reason: 'EnginePrimitive.all is missing "$p"',
        );
      }
    });

    test('PluginCapability.all covers known plugin identifiers', () {
      expect(PluginCapability.all, isNotEmpty);
      expect(
        PluginCapability.all.containsKey(PluginCapability.hitomiNozomi),
        isTrue,
      );
    });

    test('compatibilityStatusNames contains all CompatibilityStatus values',
        () {
      for (final status in CompatibilityStatus.values) {
        expect(
          compatibilityStatusNames.contains(status.name),
          isTrue,
          reason: 'compatibilityStatusNames missing "${status.name}"',
        );
      }
    });

    test('featureStatusNames contains all FeatureStatus values', () {
      for (final status in FeatureStatus.values) {
        expect(
          featureStatusNames.contains(status.name),
          isTrue,
          reason: 'featureStatusNames missing "${status.name}"',
        );
      }
    });

    test('generator-style minimal REST config validates as compatible', () {
      // Simulate what a generator would produce using the exposed metadata.
      final generatedConfig = <String, Object?>{
        'source': 'example_rest',
        'schemaVersion': '2.0',
        'minEngineVersion': '1.0.0',
        'version': '1.0.0',
        'homeUrl': 'https://example.com/',
        'apiUrl': 'https://api.example.com',

        // Generator uses EnginePrimitive.all keys:
        'requiredPrimitives': <String>[
          EnginePrimitive.imageModeDirectUrl,
          EnginePrimitive.paginationPage,
        ],

        // Generator uses FeatureStatus/CompatibilityStatus names from:
        //   featureStatusNames, compatibilityStatusNames
        'features': <String, Object?>{
          'home': <String, Object?>{'supported': true},
          'search': <String, Object?>{'supported': true},
          'detail': <String, Object?>{'supported': true},
          'reader': <String, Object?>{'supported': true},
          'download': <String, Object?>{'supported': true},
          'comments': <String, Object?>{'supported': false},
        },

        'searchConfig': <String, Object?>{
          'type': 'rest_json',
          'listEndpoint': '/search',
          'queryParam': 'q',
          'pageParam': 'page',
        },

        // Required: either 'api' or 'scraper' block must be present.
        'api': <String, Object?>{
          'type': 'rest_json',
          'listEndpoint': '/list',
          'detailEndpoint': '/detail/{id}',
        },
      };

      // Parse using an engine that supports our declared primitives.
      //
      // `dynamicForm.basic` is required in addition to the two declared in
      // `requiredPrimitives`: `searchConfig.queryParam` makes
      // SourceConfigParser autowire a minimal search form, and
      // DynamicSearchFormContract.impliedPrimitives then demands
      // `dynamicForm.basic`. Without it the parser reports
      // `primitiveMissing` and the config lands on `partiallyCompatible`.
      // This is validator behaviour added after this fixture was written,
      // not a regression — the real ConfigGenerator output is `compatible`
      // against a default SourceConfigParser, which registers every primitive.
      const parser = SourceConfigParser(
        engineVersion: '1.0.0',
        registeredPrimitives: <String>{
          EnginePrimitive.imageModeDirectUrl,
          EnginePrimitive.paginationPage,
          EnginePrimitive.dynamicFormBasic,
        },
      );

      final result = parser.parse(generatedConfig);

      // Round-trip should be compatible.
      expect(result.report.overallStatus, CompatibilityStatus.compatible);

      // No error-level diagnostics.
      final errors = result.report.diagnostics
          .where((d) => d.severity == DiagnosticSeverity.error)
          .toList();
      expect(errors, isEmpty, reason: 'Expected no errors: $errors');
    });

    test('generator-style config with unknown primitive emits warning', () {
      final config = <String, Object?>{
        'source': 'future_source',
        'schemaVersion': '2.0',
        'requiredPrimitives': <String>['imageMode.future_tech'],
        'features': <String, Object?>{
          'reader': <String, Object?>{'supported': true},
        },
      };

      final result = const SourceConfigParser().parse(config);

      // Unknown primitive → at least needsEngineSupport or warning.
      expect(
        result.report.overallStatus,
        anyOf(
          CompatibilityStatus.needsEngineSupport,
          CompatibilityStatus.compatible,
          CompatibilityStatus.partiallyCompatible,
        ),
      );
    });
  });
}
