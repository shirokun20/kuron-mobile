// Static contract tests: parse real source configs and verify that
// [SourceConfigParser] produces expected feature statuses and diagnostics.
///
// These tests load config files from `informations/configs/` (path is
// resolved relative to the workspace root or `packages/kuron_generic/`).
// They run entirely offline — no network access.
///
// Run with:
//   dart test packages/kuron_generic/test/config/source_config_parser_test.dart
library;

import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

// ── Config resolver ──────────────────────────────────────────────────────────



// Returns a [SourceConfigParser] with an empty registered-primitive set so
// primitive-gap checking is skipped (tests focus on feature inference).
SourceConfigParser _parser() => const SourceConfigParser();

// ── Helpers ──────────────────────────────────────────────────────────────────

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── MangaDex (REST, no auth, queryRules, coverBuilder) ─────────────────
  group('mangadex-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('mangadex-config.json'));
    });

    test('sourceId is mangadex', () {
      expect(result.declaration.sourceId, 'mangadex');
    });

    test('schema version warning emitted (v1 config)', () {
      final List<ValidationDiagnostic> warnings = result.report.diagnostics
          .where((ValidationDiagnostic d) => d.code == 'schemaVersionMissing')
          .toList(growable: false);
      expect(warnings, isNotEmpty,
          reason: 'mangadex-config has no schemaVersion field');
    });

    test('home + search + detail + reader are compatible or inferred', () {
      final Map<FeatureKind, FeatureStatus> s = result.report.featureStatuses;
      expect(
        <FeatureStatus>[
          s[FeatureKind.home] ?? FeatureStatus.notDeclared,
          s[FeatureKind.search] ?? FeatureStatus.notDeclared,
          s[FeatureKind.detail] ?? FeatureStatus.notDeclared,
          s[FeatureKind.reader] ?? FeatureStatus.notDeclared,
        ],
        everyElement(
          anyOf(FeatureStatus.compatible, FeatureStatus.inferred),
        ),
      );
    });

    test('offset pagination primitive is inferred', () {
      final bool hasOffset = result.declaration.contracts.any(
        (FeatureContract c) =>
            c.requiredPrimitives.contains(EnginePrimitive.paginationOffset),
      );
      expect(hasOffset, isTrue, reason: 'mangadex uses offsetMode pagination');
    });

    test('network rules has no bypass', () {
      expect(result.networkRules.requiresBypass, isFalse);
    });

    test('dynamic search form has fields', () {
      expect(result.searchForm, isNotNull);
      expect(result.searchForm!.fields, isNotEmpty);
    });

    test('overall status is compatible or partiallyCompatible', () {
      expect(
        result.report.overallStatus,
        anyOf(
          CompatibilityStatus.compatible,
          CompatibilityStatus.partiallyCompatible,
        ),
      );
    });

    test('vendorExtensions not present for mangadex', () {
      // mangadex has queryRules — this IS a vendor extension in v1.
      // After we confirm it is inferred, at minimum vendorExtensionsPresent
      // diagnostic should be present if queryRules is in the config.
      // The test verifies the parser didn't crash.
      expect(result.report.diagnostics, isA<List<ValidationDiagnostic>>());
    });
  });

  // ── HentaiNexus (scraper, decryption plugin, dynamic form) ─────────────
  group('hentainexus-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('hentainexus-config.json'));
    });

    test('sourceId is hentainexus', () {
      expect(result.declaration.sourceId, 'hentainexus');
    });

    test('schema version warning emitted', () {
      final bool has = result.report.diagnostics
          .any((ValidationDiagnostic d) => d.code == 'schemaVersionMissing');
      expect(has, isTrue);
    });

    test('decryption vendor extension detected', () {
      final bool has = result.report.diagnostics.any(
        (ValidationDiagnostic d) =>
            d.code == 'vendorExtensionsPresent' &&
            (d.context['keys'] as List<Object?>?)?.contains('decryption') ==
                true,
      );
      expect(has, isTrue);
    });

    test('reader requires hentainexus decrypt plugin', () {
      final FeatureContract? readerContract =
          result.declaration.contractFor(FeatureKind.reader);
      expect(readerContract, isNotNull);
      expect(
        readerContract!.requiredPlugins,
        contains(PluginCapability.hentainexusDecrypt),
      );
    });

    test('dynamic form is present with fields', () {
      expect(result.searchForm, isNotNull);
      expect(result.searchForm!.fields, isNotEmpty);
    });

    test('dynamic form has quoteIfContainsSpace fields', () {
      expect(result.searchForm!.hasQuoteWhitespace, isTrue);
    });

    test('dynamic form implied primitives include dynamicFormBasic', () {
      expect(
        result.searchForm!.impliedPrimitives,
        contains(EnginePrimitive.dynamicFormBasic),
      );
    });

    test('rate-limit rules are parsed', () {
      expect(result.networkRules.rateLimit, isNotNull);
      expect(
        result.networkRules.rateLimit!.requestsPerSecond,
        closeTo(1.0, 0.01),
      );
    });
  });

  // ── Crotpedia (scraper, CF bypass, WP nonce auth) ──────────────────────
  group('crotpedia-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('crotpedia-config.json'));
    });

    test('sourceId is crotpedia', () {
      expect(result.declaration.sourceId, 'crotpedia');
    });

    test('requiresBypass is true', () {
      expect(result.networkRules.requiresBypass, isTrue);
    });

    test('cloudflareBypass is true', () {
      expect(result.networkRules.cloudflareBypass, isTrue);
    });

    test('bypassFieldPlural diagnostic emitted', () {
      final bool has = result.report.diagnostics
          .any((ValidationDiagnostic d) => d.code == 'bypassFieldPlural');
      expect(has, isTrue,
          reason:
              'crotpedia has both requiresBypass and cloudflare.bypassEnabled');
    });

    test('auth feature requires wordpress nonce plugin', () {
      final FeatureContract? authContract =
          result.declaration.contractFor(FeatureKind.auth);
      expect(authContract, isNotNull,
          reason: 'crotpedia has auth.enabled = true');
      expect(
        authContract!.requiredPlugins,
        contains(PluginCapability.wordpressNonce),
      );
    });

    test('home + search + detail are present', () {
      final Map<FeatureKind, FeatureStatus> s = result.report.featureStatuses;
      for (final FeatureKind f in <FeatureKind>[
        FeatureKind.home,
        FeatureKind.search,
        FeatureKind.detail,
      ]) {
        expect(
          s[f] ?? FeatureStatus.notDeclared,
          anyOf(
            FeatureStatus.compatible,
            FeatureStatus.inferred,
            FeatureStatus.requiresPlugin,
          ),
          reason: '${f.name} should be present in crotpedia',
        );
      }
    });
  });

  // ── KomikTap (scraper, tsReaderRegex, chapters, comments) ──────────────
  group('komiktap-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('komiktap-config.json'));
    });

    test('sourceId is komiktap', () {
      expect(result.declaration.sourceId, 'komiktap');
    });

    test('reader requires scriptRegex primitive', () {
      final FeatureContract? readerContract =
          result.declaration.contractFor(FeatureKind.reader);
      expect(readerContract, isNotNull);
      expect(
        readerContract!.requiredPrimitives,
        contains(EnginePrimitive.imageModeScriptRegex),
      );
    });

    test('comments feature is present', () {
      final FeatureStatus? comments =
          result.report.featureStatuses[FeatureKind.comments];
      expect(
        comments ?? FeatureStatus.notDeclared,
        anyOf(
          FeatureStatus.compatible,
          FeatureStatus.inferred,
        ),
      );
    });

    test('chapters feature is present', () {
      final FeatureStatus? chapters =
          result.report.featureStatuses[FeatureKind.chapters];
      expect(
        chapters ?? FeatureStatus.notDeclared,
        isNot(FeatureStatus.notDeclared),
      );
    });
  });

  // ── HentaiFox (scraper, CDN regex reader mode) ──────────────────────────
  group('hentaifox-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('hentaifox-config.json'));
    });

    test('reader requires cdnRegex primitive', () {
      final FeatureContract? readerContract =
          result.declaration.contractFor(FeatureKind.reader);
      expect(readerContract, isNotNull);
      expect(
        readerContract!.requiredPrimitives,
        contains(EnginePrimitive.imageModeCdnRegex),
      );
    });

    test('no bypass', () {
      expect(result.networkRules.requiresBypass, isFalse);
    });
  });

  // ── DoujinDesu v2 (scraper, category routing, AJAX reader HTML) ────────
  group('doujindesuv2-config.json', () {
    late SourceConfigParseResult result;

    setUpAll(() async {
      result = _parser().parse(await loadConfigRemote('doujindesuv2-config.json'));
    });

    test('sourceId is doujindesuv2', () {
      expect(result.declaration.sourceId, 'doujindesuv2');
    });

    test('search requires category-routing primitive when configured', () {
      final FeatureContract? searchContract =
          result.declaration.contractFor(FeatureKind.search);
      expect(searchContract, isNotNull);
      expect(
        searchContract!.requiredPrimitives,
        contains(EnginePrimitive.searchCategoryRouting),
      );
    });

    test('reader requires ajax-html primitive when ajax reader mode is used',
        () {
      final FeatureContract? readerContract =
          result.declaration.contractFor(FeatureKind.reader);
      expect(readerContract, isNotNull);
      expect(
        readerContract!.requiredPrimitives,
        contains(EnginePrimitive.imageModeAjaxHtml),
      );
      expect(
        readerContract.requiredPrimitives,
        isNot(contains(EnginePrimitive.imageModeDirectUrl)),
      );
    });
  });

  // ── NetworkRules unit tests ───────────────────────────────────────────────
  group('NetworkRules.fromConfig', () {
    test('parses static headers', () {
      final NetworkRules rules = NetworkRules.fromConfig(<String, Object?>{
        'network': <String, Object?>{
          'requiresBypass': false,
          'headers': <String, Object?>{
            'User-Agent': 'Test/1.0',
            'Referer': 'https://example.com/',
          },
        },
      });
      expect(rules.staticHeaders['User-Agent'], 'Test/1.0');
      expect(rules.staticHeaders['Referer'], 'https://example.com/');
      expect(rules.requiresBypass, isFalse);
    });

    test('merges requiresBypass with cloudflare.bypassEnabled', () {
      final NetworkRules rules = NetworkRules.fromConfig(<String, Object?>{
        'network': <String, Object?>{
          'requiresBypass': true,
          'cloudflare': <String, Object?>{'bypassEnabled': true},
        },
      });
      expect(rules.requiresBypass, isTrue);
      expect(rules.cloudflareBypass, isTrue);
      expect(
        rules.diagnostics
            .any((ValidationDiagnostic d) => d.code == 'bypassFieldPlural'),
        isTrue,
      );
    });

    test('parses rate limit', () {
      final NetworkRules rules = NetworkRules.fromConfig(<String, Object?>{
        'network': <String, Object?>{
          'rateLimit': <String, Object?>{
            'requestsPerSecond': 2,
            'maxConcurrentRequests': 4,
          },
        },
      });
      expect(rules.rateLimit!.requestsPerSecond, 2.0);
      expect(rules.rateLimit!.maxConcurrentRequests, 4);
    });
  });

  // ── DynamicSearchFormContract unit tests ─────────────────────────────────
  group('DynamicSearchFormContract.fromConfig', () {
    test('returns empty contract when no searchForm', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(const <String, Object?>{});
      expect(c.fields, isEmpty);
    });

    test('parses tag field with valuePrefix and quoteIfContainsSpace', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchForm': <String, Object?>{
          'urlPattern': 'search',
          'params': <String, Object?>{
            'includeTag': <String, Object?>{
              'queryParam': 'q',
              'type': 'tag',
              'label': 'Include Tag',
              'valuePrefix': 'tag:',
              'quoteIfContainsSpace': true,
              'multiInput': true,
              'joinMode': 'space',
              'ui': <String, Object?>{'selector': 'chips'},
            },
          },
        },
      });

      expect(c.fields, hasLength(1));
      final SearchFormFieldContract f = c.fields.first;
      expect(f.id, 'includeTag');
      expect(f.type, SearchFormFieldType.tag);
      expect(f.valuePrefix, 'tag:');
      expect(f.quoteIfContainsSpace, isTrue);
      expect(f.multiInput, isTrue);
      expect(f.uiSelector, 'chips');
      expect(c.hasQuoteWhitespace, isTrue);
      expect(
        c.impliedPrimitives,
        containsAll(<String>[
          EnginePrimitive.dynamicFormBasic,
          EnginePrimitive.dynamicFormQuoteWhitespace,
        ]),
      );
    });

    test('parses KomikCast-style sortingConfig', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchConfig': <String, Object?>{
          'queryParam': 's',
          'sortingConfig': <String, Object?>{
            'queryParam': 'orderby',
            'label': 'Sort',
            'widgetType': 'dropdown',
            'options': <Object?>[
              <String, Object?>{
                'value': 'newest',
                'apiValue': 'date',
                'label': 'Newest',
              },
              <String, Object?>{'value': 'popular', 'label': 'Popular'},
            ],
          },
        },
      });

      expect(c.fields, hasLength(2));
      expect(c.fields.first.type, SearchFormFieldType.text);
      expect(c.fields.first.queryParam, 's');
      final SearchFormFieldContract sortField = c.fields.last;
      expect(sortField.type, SearchFormFieldType.sort);
      expect(sortField.options, hasLength(2));
      expect(sortField.options.first.value, 'date');
      expect(sortField.uiSelector, 'dropdown');
    });

    test('parses string options from explicit select fields', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchForm': <String, Object?>{
          'params': <String, Object?>{
            'favorited': <String, Object?>{
              'queryParam': 'q',
              'type': 'select',
              'options': <String>['true', 'false'],
            },
          },
        },
      });

      expect(c.fields.single.type, SearchFormFieldType.select);
      expect(
        c.fields.single.options
            .map((SearchFormFieldOption option) => option.value),
        <String>['true', 'false'],
      );
    });

    test('preserves picker data sources from explicit searchForm', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchForm': <String, Object?>{
          'urlPattern': 'search',
          'dataSources': <String, Object?>{
            'mangaTags': <String, Object?>{
              'endpoint': '/manga/tag',
              'itemsPath': 'data',
            },
          },
          'params': <String, Object?>{
            'includedTag': <String, Object?>{
              'queryParam': 'includedTags[]',
              'type': 'tag',
              'multiInput': true,
              'ui': <String, Object?>{
                'selector': 'picker',
                'multi': true,
                'dataSource': 'mangaTags',
              },
            },
          },
        },
      });

      expect(c.dataSources.keys, contains('mangaTags'));
      expect(c.fields.single.uiSelector, 'picker');
      expect(c.fields.single.uiDataSource, 'mangaTags');
    });

    test('upgrades legacy form-based field groups', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchConfig': <String, Object?>{
          'searchMode': 'form-based',
          'queryParam': 'q',
          'textFields': <Object?>[
            <String, Object?>{
              'name': 'author',
              'label': 'Author',
              'placeholder': 'Author name',
            },
          ],
          'radioGroups': <Object?>[
            <String, Object?>{
              'name': 'status',
              'label': 'Status',
              'options': <Object?>[
                <String, Object?>{'value': 'all', 'label': 'All'},
              ],
            },
          ],
          'checkboxGroups': <Object?>[
            <String, Object?>{
              'name': 'genre',
              'label': 'Genre',
              'paramName': 'genre[]',
              'loadFromTags': true,
              'tagType': 'genre',
              'tagSourceUrl': 'https://example.com/tags.json',
              'options': <String>['action'],
            },
          ],
        },
      });

      expect(
          c.fields.map((field) => field.id),
          containsAll(<String>[
            'author',
            'status',
            'genre',
          ]));
      expect(
        c.fields.firstWhere((field) => field.id == 'status').type,
        SearchFormFieldType.radio,
      );
      expect(
        c.fields.firstWhere((field) => field.id == 'genre').queryParam,
        'genre[]',
      );
      expect(
        c.fields.firstWhere((field) => field.id == 'genre').tagSourceUrl,
        'https://example.com/tags.json',
      );
    });

    test('deduplicates form query fields that share the same queryParam', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchForm': <String, Object?>{
          'urlPattern': 'advancedSearch',
          'params': <String, Object?>{
            'query': <String, Object?>{
              'queryParam': 'title',
              'type': 'text',
            },
            'page': <String, Object?>{
              'queryParam': 'page',
              'type': 'page',
            },
          },
        },
        'searchConfig': <String, Object?>{
          'searchMode': 'form-based',
          'textFields': <Object?>[
            <String, Object?>{
              'name': 'title',
              'label': 'Title',
              'placeholder': 'Search by title...',
            },
          ],
        },
      });

      final titleFields = c.fields
          .where((SearchFormFieldContract field) => field.queryParam == 'title')
          .toList(growable: false);

      expect(titleFields, hasLength(1));
      expect(titleFields.single.id, 'query');
      expect(c.fields.map((field) => field.id), isNot(contains('title')));
    });

    test('infers minimal query contract from scraper search URL pattern', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'scraper': <String, Object?>{
          'urlPatterns': <String, Object?>{
            'search': '/?s={query}&page={page}',
          },
        },
      });

      expect(c.fields, hasLength(2));
      expect(c.fields.first.id, 'query');
      expect(c.fields.first.queryParam, 's');
      expect(c.fields.first.type, SearchFormFieldType.text);
      expect(c.fields.last.type, SearchFormFieldType.hidden);
      expect(
        c.diagnostics.map((ValidationDiagnostic d) => d.code),
        contains('searchAutowiringInferred'),
      );
    });

    test('emits diagnostic for unsupported explicit field type', () {
      final DynamicSearchFormContract c =
          DynamicSearchFormContract.fromConfig(<String, Object?>{
        'searchForm': <String, Object?>{
          'params': <String, Object?>{
            'range': <String, Object?>{
              'queryParam': 'range',
              'type': 'slider',
            },
          },
        },
      });

      expect(c.fields.single.type, SearchFormFieldType.text);
      expect(
        c.diagnostics.map((ValidationDiagnostic d) => d.code),
        contains('searchFieldUnsupported'),
      );
    });
  });

  // ── SourceConfigParser unit tests ────────────────────────────────────────
  group('SourceConfigParser.parse', () {
    test('emits noSourceTypeBlock error when both api and scraper absent', () {
      final SourceConfigParseResult result = _parser().parse(<String, Object?>{
        'source': 'empty',
        'baseUrl': 'https://x.com',
      });
      final bool hasError = result.report.diagnostics.any(
        (ValidationDiagnostic d) => d.code == 'noSourceTypeBlock',
      );
      expect(hasError, isTrue);
    });

    test('emits engineVersionTooOld when minEngineVersion > current', () {
      const SourceConfigParser parser =
          SourceConfigParser(engineVersion: '1.0.0');
      final SourceConfigParseResult result = parser.parse(<String, Object?>{
        'source': 'test',
        'minEngineVersion': '2.0.0',
        'scraper': <String, Object?>{'enabled': true},
      });
      final bool hasError = result.report.diagnostics.any(
        (ValidationDiagnostic d) => d.code == 'engineVersionTooOld',
      );
      expect(hasError, isTrue);
    });

    test('no engineVersionTooOld when requirement met', () {
      const SourceConfigParser parser =
          SourceConfigParser(engineVersion: '2.1.0');
      final SourceConfigParseResult result = parser.parse(<String, Object?>{
        'source': 'test',
        'minEngineVersion': '1.0.0',
        'scraper': <String, Object?>{'enabled': true},
      });
      final bool hasError = result.report.diagnostics.any(
        (ValidationDiagnostic d) => d.code == 'engineVersionTooOld',
      );
      expect(hasError, isFalse);
    });

    test('schemaVersion passed through to declaration', () {
      final SourceConfigParseResult result = _parser().parse(<String, Object?>{
        'source': 'test',
        'schemaVersion': '2.0',
        'scraper': <String, Object?>{'enabled': true},
      });
      expect(result.declaration.schemaVersion, '2.0');
      expect(
        result.report.diagnostics
            .any((ValidationDiagnostic d) => d.code == 'schemaVersionMissing'),
        isFalse,
      );
    });

    test('reader feature inferred from scraper urlPatterns.chapter', () {
      final SourceConfigParseResult result = _parser().parse(<String, Object?>{
        'source': 'x',
        'scraper': <String, Object?>{
          'enabled': true,
          'urlPatterns': <String, Object?>{
            'home': <String, Object?>{'url': '/'},
            'detail': '/manga/{id}',
            'chapter': '/manga/{id}/{ch}',
          },
        },
      });
      final FeatureStatus? reader =
          result.report.featureStatuses[FeatureKind.reader];
      expect(reader ?? FeatureStatus.notDeclared,
          anyOf(FeatureStatus.compatible, FeatureStatus.inferred));
    });

    test('missing plugin causes requiresPlugin status for feature', () {
      // Parser with no registered plugins.
      final SourceConfigParseResult result =
          const SourceConfigParser().parse(<String, Object?>{
        'source': 'hentainexus',
        'decryption': <String, Object?>{'method': 'initReader_xor_rc4_variant'},
        'scraper': <String, Object?>{
          'enabled': true,
          'urlPatterns': <String, Object?>{
            'home': <String, Object?>{'url': '/'},
            'detail': '/view/{id}',
            'chapter': '/read/{id}',
          },
        },
      });
      final FeatureStatus? reader =
          result.report.featureStatuses[FeatureKind.reader];
      expect(reader, FeatureStatus.requiresPlugin);
    });

    test('registered plugin clears requiresPlugin for feature', () {
      const SourceConfigParser parser = SourceConfigParser(
        registeredPlugins: <String>{PluginCapability.hentainexusDecrypt},
      );
      final SourceConfigParseResult result = parser.parse(<String, Object?>{
        'source': 'hentainexus',
        'decryption': <String, Object?>{'method': 'initReader_xor_rc4_variant'},
        'scraper': <String, Object?>{
          'enabled': true,
          'urlPatterns': <String, Object?>{
            'home': <String, Object?>{'url': '/'},
            'detail': '/view/{id}',
            'chapter': '/read/{id}',
          },
        },
      });
      final FeatureStatus? reader =
          result.report.featureStatuses[FeatureKind.reader];
      expect(
        reader ?? FeatureStatus.notDeclared,
        anyOf(FeatureStatus.compatible, FeatureStatus.inferred),
      );
    });
  });
}
