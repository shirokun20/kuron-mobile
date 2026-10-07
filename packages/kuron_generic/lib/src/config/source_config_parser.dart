// Source Config v2 Parser.
///
// Parses a raw source config JSON map into a [SourceConfigParseResult]
// containing:
//   - [SourceCapabilityDeclaration] — typed feature contracts with required
//     primitives and plugin capabilities.
//   - [ValidationReport] — static diagnostics (no network access).
//   - [NetworkRules] — typed network/header/referer rules.
//   - [DynamicSearchFormContract]? — typed dynamic search form, if declared.
///
// ## v1 → v2 Compatibility (task 3.2)
///
// v1 configs (no `schemaVersion` field) are accepted. Missing declarations
// are inferred from config block presence and each inference emits a
// [DiagnosticSeverity.warning] with code `featureInferred`.
///
// ## Required-Primitive Inference (task 3.1)
///
// For every feature the parser identifies, it infers the set of
// [EnginePrimitive] identifiers and [PluginCapability] identifiers that
// the runtime must support.
library;

import 'package:kuron_core/kuron_core.dart';

import 'typed_config/dynamic_search_form.dart';
import 'typed_config/network_rules.dart';

// Return type of [SourceConfigParser.parse].
class SourceConfigParseResult {
  const SourceConfigParseResult({
    required this.declaration,
    required this.report,
    required this.networkRules,
    this.searchForm,
  });

  final SourceCapabilityDeclaration declaration;
  final ValidationReport report;
  final NetworkRules networkRules;
  final DynamicSearchFormContract? searchForm;
}

// Parses a raw source config map into typed contracts and a static
// validation report.
class SourceConfigParser {
  const SourceConfigParser({
    String engineVersion = '1.0.0',
    Set<String> registeredPrimitives = const <String>{},
    Set<String> registeredPlugins = const <String>{},
  })  : _engineVersion = engineVersion,
        _registeredPrimitives = registeredPrimitives,
        _registeredPlugins = registeredPlugins;

  final String _engineVersion;

  // Engine primitives the current runtime supports. Used to compute
  // `missingPrimitives` → `needsEngineSupport` status.
  final Set<String> _registeredPrimitives;

  // Plugin capabilities registered by the host app. Used to compute
  // `missingPlugins` → `requiresPlugin` feature status.
  final Set<String> _registeredPlugins;

  // Parse [rawConfig] and return a [SourceConfigParseResult].
  ///
  // Never throws. All anomalies are captured as [ValidationDiagnostic]s.
  SourceConfigParseResult parse(Map<String, Object?> rawConfig) {
    final List<ValidationDiagnostic> diags = <ValidationDiagnostic>[];

    final String sourceId = rawConfig['source']?.toString() ??
        rawConfig['sourceId']?.toString() ??
        'unknown';

    // ── Schema version (3.1) ────────────────────────────────────────────────
    final String? schemaVersion = rawConfig['schemaVersion']?.toString();
    final String? minEngineVersion = rawConfig['minEngineVersion']?.toString();

    if (schemaVersion == null) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'schemaVersionMissing',
        message: 'Config does not declare a schemaVersion field. '
            'Treating as v1 and inferring feature contracts.',
        path: 'schemaVersion',
      ));
    }

    if (minEngineVersion != null) {
      if (!_isEngineVersionCompatible(minEngineVersion, _engineVersion)) {
        diags.add(ValidationDiagnostic(
          severity: DiagnosticSeverity.error,
          code: 'engineVersionTooOld',
          message: 'Config requires engine >= $minEngineVersion but current '
              'engine is $_engineVersion.',
          path: 'minEngineVersion',
          context: <String, Object?>{
            'required': minEngineVersion,
            'current': _engineVersion,
          },
        ));
      }
    }

    // ── Content ID pattern (v1 compat) ─────────────────────────────────────
    final bool hasContentIdPattern = rawConfig.containsKey('contentIdPattern');
    if (!hasContentIdPattern) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.info,
        code: 'contentIdPatternMissing',
        message:
            'contentIdPattern not declared; adapter will fall back to URL-tail extraction.',
        path: 'contentIdPattern',
      ));
    }

    // ── Network rules (3.4) ─────────────────────────────────────────────────
    final NetworkRules networkRules = NetworkRules.fromConfig(rawConfig);
    diags.addAll(networkRules.diagnostics);

    // ── Source type detection ───────────────────────────────────────────────
    final Object? apiBlock = rawConfig['api'];
    final Object? scraperBlock = rawConfig['scraper'];
    final bool hasApi =
        apiBlock is Map && (apiBlock['enabled'] as bool? ?? true);
    final bool hasScraper =
        scraperBlock is Map && (scraperBlock['enabled'] as bool? ?? true);

    if (!hasApi && !hasScraper) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'noSourceTypeBlock',
        message: 'Config must have either an `api` or a `scraper` block.',
      ));
    }

    // ── Auth declaration (v1 compat) ────────────────────────────────────────
    final Object? authRaw = rawConfig['auth'];
    final bool authEnabled = authRaw is Map
        ? (authRaw.cast<String, Object?>()['enabled'] as bool? ?? false)
        : false;
    final bool supportsAuthFlag = rawConfig['supportsAuth'] as bool? ?? false;
    final bool hasNonceRegex = authRaw is Map &&
        (authRaw.cast<String, Object?>())['nonceRegex'] != null;

    if (authRaw is Map && !authEnabled && supportsAuthFlag) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'authDeclarationAmbiguous',
        message:
            'auth.enabled is false but supportsAuth is true. Treating as no auth.',
        path: 'auth.enabled',
      ));
    }

    // ── Vendor extensions (escape hatches) ─────────────────────────────────
    final Map<String, Object?> vendorExtensions =
        _extractVendorExtensions(rawConfig);
    if (vendorExtensions.isNotEmpty) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.info,
        code: 'vendorExtensionsPresent',
        message:
            'Config uses non-standard fields: ${vendorExtensions.keys.join(', ')}. '
            'These may require kuron_special plugins.',
        context: <String, Object?>{
          'keys': vendorExtensions.keys.toList(growable: false),
        },
      ));
    }

    // ── Dynamic search form (3.3) ───────────────────────────────────────────
    DynamicSearchFormContract? searchForm;
    final bool hasSearchForm = rawConfig.containsKey('searchForm') ||
        rawConfig.containsKey('searchConfig') ||
        _hasSearchEndpoint(rawConfig);
    if (hasSearchForm) {
      searchForm = DynamicSearchFormContract.fromConfig(rawConfig);
      diags.addAll(searchForm.diagnostics);
    }

    // ── Feature contracts (3.1 + 3.2) ──────────────────────────────────────
    final List<FeatureContract> contracts = _buildFeatureContracts(
      rawConfig: rawConfig,
      hasApi: hasApi,
      hasScraper: hasScraper,
      authEnabled: authEnabled,
      hasNonceRegex: hasNonceRegex,
      networkRules: networkRules,
      searchForm: searchForm,
      vendorExtensions: vendorExtensions,
      diags: diags,
    );

    // ── Plugin gap detection ────────────────────────────────────────────────
    final Set<String> allRequiredPlugins = <String>{
      for (final FeatureContract c in contracts) ...c.requiredPlugins,
    };
    final Set<String> missingPlugins = allRequiredPlugins
        .where((String p) => !_registeredPlugins.contains(p))
        .toSet();

    // ── Primitive gap detection ─────────────────────────────────────────────
    final Set<String> allRequiredPrimitives = <String>{
      for (final FeatureContract c in contracts) ...c.requiredPrimitives,
    };
    final Set<String> missingPrimitives = _registeredPrimitives.isNotEmpty
        ? allRequiredPrimitives
            .where((String p) => !_registeredPrimitives.contains(p))
            .toSet()
        : const <String>{};

    for (final String mp in missingPrimitives) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'primitiveMissing',
        message: 'Engine does not support primitive: $mp',
        context: <String, Object?>{'primitive': mp},
      ));
    }

    // ── Per-feature status map ──────────────────────────────────────────────
    final Map<FeatureKind, FeatureStatus> featureStatuses =
        _computeFeatureStatuses(
      contracts: contracts,
      missingPlugins: missingPlugins,
      missingPrimitives: missingPrimitives,
      authEnabled: authEnabled,
      networkRules: networkRules,
    );

    // ── Overall status ──────────────────────────────────────────────────────
    final Set<FeatureKind> requiredFeatures = <FeatureKind>{
      for (final FeatureContract c in contracts)
        if (c.required) c.feature,
    };

    final CompatibilityStatus overall = ValidationReport.computeOverallStatus(
      featureStatuses: featureStatuses,
      requiredFeatures: requiredFeatures,
      diagnostics: diags,
      missingPlugins: missingPlugins,
    );

    final SourceCapabilityDeclaration declaration = SourceCapabilityDeclaration(
      sourceId: sourceId,
      schemaVersion: schemaVersion ?? 'v1-inferred',
      minEngineVersion: minEngineVersion,
      contracts: contracts,
      vendorExtensions: vendorExtensions,
    );

    final ValidationReport report = ValidationReport(
      sourceId: sourceId,
      overallStatus: overall,
      featureStatuses: featureStatuses,
      schemaVersion: schemaVersion,
      engineVersion: _engineVersion,
      minEngineVersion: minEngineVersion,
      diagnostics: diags,
      requiredPlugins: allRequiredPlugins,
      detectedPlugins: allRequiredPlugins
          .where((String p) => _registeredPlugins.contains(p))
          .toSet(),
      missingPlugins: missingPlugins,
      mode: ValidationMode.staticMode,
    );

    return SourceConfigParseResult(
      declaration: declaration,
      report: report,
      networkRules: networkRules,
      searchForm: searchForm,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  bool _hasSearchEndpoint(Map<String, Object?> rawConfig) {
    final scraper = rawConfig['scraper'];
    if (scraper is Map) {
      final urlPatterns = scraper.cast<String, Object?>()['urlPatterns'];
      if (urlPatterns is Map &&
          urlPatterns.cast<String, Object?>().containsKey('search')) {
        return true;
      }
    }

    final api = rawConfig['api'];
    if (api is Map) {
      final endpoints = api.cast<String, Object?>()['endpoints'];
      if (endpoints is Map &&
          endpoints.cast<String, Object?>().containsKey('search')) {
        return true;
      }
    }

    return false;
  }

  List<FeatureContract> _buildFeatureContracts({
    required Map<String, Object?> rawConfig,
    required bool hasApi,
    required bool hasScraper,
    required bool authEnabled,
    required bool hasNonceRegex,
    required NetworkRules networkRules,
    required DynamicSearchFormContract? searchForm,
    required Map<String, Object?> vendorExtensions,
    required List<ValidationDiagnostic> diags,
  }) {
    final Object? featuresRaw = rawConfig['features'];
    final Map<String, Object?> features = featuresRaw is Map
        ? featuresRaw.cast<String, Object?>()
        : const <String, Object?>{};
    final bool featuresExplicit = featuresRaw is Map;

    final List<FeatureContract> contracts = <FeatureContract>[];

    // Helper: add a feature contract, warning when inferred.
    void addFeature({
      required FeatureKind feature,
      required bool declared,
      required bool present,
      bool required = false,
      Set<String> primitives = const <String>{},
      Set<String> plugins = const <String>{},
    }) {
      if (!present) return;
      if (!declared && !featuresExplicit) {
        diags.add(ValidationDiagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'featureInferred',
          message:
              'Feature ${feature.name} was not explicitly declared; inferred '
              'from config block presence.',
          feature: feature,
          context: <String, Object?>{'feature': feature.name},
        ));
      }
      contracts.add(FeatureContract(
        feature: feature,
        declared: declared,
        required: required,
        requiredPrimitives: primitives,
        requiredPlugins: plugins,
      ));
    }

    // ── Scraper-specific helpers ──────────────────────────────────────────
    final Map<String, Object?> scraper = hasScraper
        ? (rawConfig['scraper']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final Map<String, Object?> urlPatterns = scraper['urlPatterns'] is Map
        ? (scraper['urlPatterns']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final Map<String, Object?> selectors = scraper['selectors'] is Map
        ? (scraper['selectors']! as Map).cast<String, Object?>()
        : const <String, Object?>{};

    // ── API-specific helpers ─────────────────────────────────────────────
    final Map<String, Object?> api = hasApi
        ? (rawConfig['api']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final Map<String, Object?> apiEndpoints = api['endpoints'] is Map
        ? (api['endpoints']! as Map).cast<String, Object?>()
        : const <String, Object?>{};

    // ── Detect reader mode and required primitives ────────────────────────
    final Map<String, Object?> readerSelectors = selectors['reader'] is Map
        ? (selectors['reader']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final bool hasTsReaderRegex = readerSelectors.containsKey('tsReaderRegex');
    final bool hasCdnPathRegex = readerSelectors.containsKey('cdnPathRegex');
    final bool hasAjaxHtmlReader =
        readerSelectors['mode']?.toString() == 'ajaxHtmlImages';

    final Map<String, Object?> scraperRouting = scraper['routing'] is Map
        ? (scraper['routing']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final bool hasCategoryRouting = scraperRouting['categoryPatterns'] is Map &&
        (scraperRouting['categoryPatterns'] as Map).isNotEmpty;

    // API image modes.
    final Map<String, Object?> apiImages = api['images'] is Map
        ? (api['images']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final String? apiImagesMode = apiImages['mode']?.toString();
    final bool hasImagesTemplate = rawConfig.containsKey('imageUrlTemplate') ||
        apiImages.containsKey('template');
    final bool hasImagesProxy = apiImages.containsKey('proxyUrl');

    // Plugin requirements from vendor extensions.
    final bool hasDecryption = vendorExtensions.containsKey('decryption');
    final bool hasHitomiProtocol =
        vendorExtensions.containsKey('hitomiProtocol');
    final bool hasEhentaiPageFetch = readerSelectors['imageUrls'] is Map &&
        ((readerSelectors['imageUrls']! as Map).cast<String, Object?>())['mode']
                ?.toString() ==
            'ehentai_page_fetch';

    Set<String> readerPrimitives() {
      return <String>{
        if (hasTsReaderRegex) EnginePrimitive.imageModeScriptRegex,
        if (hasCdnPathRegex) EnginePrimitive.imageModeCdnRegex,
        if (hasAjaxHtmlReader) EnginePrimitive.imageModeAjaxHtml,
        if (hasImagesTemplate) EnginePrimitive.imageModeTemplate,
        if (hasImagesProxy) EnginePrimitive.imageModeProxy,
        if (apiImagesMode == 'atHome') EnginePrimitive.imageModeDirectUrl,
        if (!hasTsReaderRegex &&
            !hasCdnPathRegex &&
            !hasAjaxHtmlReader &&
            !hasImagesTemplate &&
            !hasImagesProxy &&
            apiImagesMode != 'atHome')
          EnginePrimitive.imageModeDirectUrl,
      };
    }

    Set<String> readerPlugins() {
      return <String>{
        if (hasEhentaiPageFetch) PluginCapability.ehentaiPageTokenFetch,
        if (hasHitomiProtocol) PluginCapability.hitomiNozomi,
        if (hasDecryption) PluginCapability.hentainexusDecrypt,
      };
    }

    // ── Feature: home ────────────────────────────────────────────────────
    final bool homePresent = urlPatterns.containsKey('home') ||
        apiEndpoints.containsKey('allGalleries');
    addFeature(
      feature: FeatureKind.home,
      declared: features['home'] is bool,
      present: homePresent,
      required: true,
      primitives: <String>{
        _paginationPrimitive(rawConfig, hasScraper: hasScraper, hasApi: hasApi),
      }.where((String s) => s.isNotEmpty).toSet(),
    );

    // ── Feature: search ─────────────────────────────────────────────────
    final bool searchPresent =
        urlPatterns.containsKey('search') || apiEndpoints.containsKey('search');
    addFeature(
      feature: FeatureKind.search,
      declared: features['search'] is bool,
      present: searchPresent,
      required: true,
      primitives: <String>{
        _paginationPrimitive(rawConfig, hasScraper: hasScraper, hasApi: hasApi),
        if (hasCategoryRouting) EnginePrimitive.searchCategoryRouting,
      }.where((String s) => s.isNotEmpty).toSet(),
    );

    // ── Feature: dynamicForm ────────────────────────────────────────────
    addFeature(
      feature: FeatureKind.dynamicForm,
      declared:
          features['advancedSearch'] is bool || features['dynamicForm'] is bool,
      present: searchForm != null && searchForm.fields.isNotEmpty,
      primitives: searchForm?.impliedPrimitives ?? const <String>{},
    );

    // ── Feature: contentByTag ───────────────────────────────────────────
    final bool tagPresent = urlPatterns.containsKey('genreSearch') ||
        urlPatterns.containsKey('tagSearch') ||
        apiEndpoints.containsKey('tagSearch') ||
        apiEndpoints.containsKey('allContent');
    addFeature(
      feature: FeatureKind.contentByTag,
      declared: features['contentByTag'] is bool,
      present: tagPresent,
    );

    // ── Feature: detail ─────────────────────────────────────────────────
    final bool detailPresent =
        urlPatterns.containsKey('detail') || apiEndpoints.containsKey('detail');
    addFeature(
      feature: FeatureKind.detail,
      declared: features['detail'] is bool,
      present: detailPresent,
      required: true,
    );

    // ── Feature: chapters ───────────────────────────────────────────────
    final bool chaptersPresent = urlPatterns.containsKey('chapter') ||
        apiEndpoints.containsKey('chapters') ||
        (api['detail'] is Map &&
            (api['detail']! as Map).containsKey('chapters')) ||
        (selectors['detail'] is Map &&
            (selectors['detail']! as Map).containsKey('chapters'));
    addFeature(
      feature: FeatureKind.chapters,
      declared: features['chapters'] is bool,
      present: chaptersPresent,
    );

    // ── Feature: reader ─────────────────────────────────────────────────
    final bool readerPresent = detailPresent &&
        (urlPatterns.containsKey('chapter') ||
            apiEndpoints.containsKey('pages') ||
            apiEndpoints.containsKey('chapters') ||
            selectors.containsKey('reader') ||
            api.containsKey('images')); // REST at-home / CDN style
    addFeature(
      feature: FeatureKind.reader,
      declared: features['reader'] is bool,
      present: readerPresent,
      required: true,
      primitives: readerPrimitives(),
      plugins: readerPlugins(),
    );

    // ── Feature: download ────────────────────────────────────────────────
    final bool downloadDeclared = features['download'] is bool;
    final bool downloadPresent = downloadDeclared
        ? (features['download'] as bool? ?? false)
        : readerPresent;
    addFeature(
      feature: FeatureKind.download,
      declared: downloadDeclared,
      present: downloadPresent,
      primitives: <String>{
        if (networkRules.staticHeaders.isNotEmpty)
          EnginePrimitive.headersStatic,
      },
    );

    // ── Feature: comments ────────────────────────────────────────────────
    final Map<String, Object?> detailSel = selectors['detail'] is Map
        ? (selectors['detail']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final bool hasEmbeddedComments = detailSel.containsKey('comments');
    final bool hasCommentsEndpoint = rawConfig.containsKey('comments') ||
        (scraper.containsKey('comments') &&
            (scraper['comments']! as Map).containsKey('endpoint'));
    final bool commentsPresent = hasEmbeddedComments || hasCommentsEndpoint;
    final bool commentsDeclared = features['comments'] is bool;
    addFeature(
      feature: FeatureKind.comments,
      declared: commentsDeclared,
      present: commentsPresent,
      primitives: <String>{
        if (hasEmbeddedComments) EnginePrimitive.commentsEmbedded,
        if (hasCommentsEndpoint) EnginePrimitive.commentsEndpoint,
      },
    );

    // ── Feature: related ────────────────────────────────────────────────
    final bool relatedPresent = (features['related'] as bool? ?? false) ||
        (detailSel.containsKey('related')) ||
        (api['detail'] is Map &&
            (api['detail']! as Map).containsKey('related'));
    addFeature(
      feature: FeatureKind.related,
      declared: features['related'] is bool,
      present: relatedPresent,
    );

    // ── Feature: headers ────────────────────────────────────────────────
    addFeature(
      feature: FeatureKind.headers,
      declared: features['headers'] is bool,
      present: networkRules.staticHeaders.isNotEmpty,
      primitives: networkRules.impliedPrimitives,
    );

    // ── Feature: auth ────────────────────────────────────────────────────
    addFeature(
      feature: FeatureKind.auth,
      declared: features['supportsAuth'] is bool ||
          features['auth'] is bool ||
          (rawConfig['auth'] is Map),
      present: authEnabled,
      plugins: <String>{
        if (hasNonceRegex) PluginCapability.wordpressNonce,
        if (networkRules.cloudflareBypass) PluginCapability.cloudflareWebview,
      },
    );

    return contracts;
  }

  Map<FeatureKind, FeatureStatus> _computeFeatureStatuses({
    required List<FeatureContract> contracts,
    required Set<String> missingPlugins,
    required Set<String> missingPrimitives,
    required bool authEnabled,
    required NetworkRules networkRules,
  }) {
    final Map<FeatureKind, FeatureStatus> statuses =
        <FeatureKind, FeatureStatus>{};
    for (final FeatureContract c in contracts) {
      final bool hasMissingPlugin =
          c.requiredPlugins.any((String p) => missingPlugins.contains(p));
      final bool hasMissingPrimitive =
          c.requiredPrimitives.any((String p) => missingPrimitives.contains(p));

      FeatureStatus status;
      if (c.feature == FeatureKind.auth &&
          c.requiredPlugins.any(
            (String p) => p == PluginCapability.cloudflareWebview,
          ) &&
          missingPlugins.contains(PluginCapability.cloudflareWebview)) {
        status = FeatureStatus.blockedBySiteProtection;
      } else if (hasMissingPlugin || hasMissingPrimitive) {
        status = FeatureStatus.requiresPlugin;
      } else if (!c.declared) {
        status = FeatureStatus.inferred;
      } else {
        status = FeatureStatus.compatible;
      }
      statuses[c.feature] = status;
    }
    return statuses;
  }

  // Extract non-standard escape-hatch fields from the config.
  Map<String, Object?> _extractVendorExtensions(
      Map<String, Object?> rawConfig) {
    const Set<String> knownKeys = <String>{
      'source',
      'sourceId',
      'version',
      'schemaVersion',
      'minEngineVersion',
      'enabled',
      'defaultLanguage',
      'baseUrl',
      'configUrl',
      'iconPath',
      'ui',
      'network',
      'auth',
      'api',
      'scraper',
      'features',
      'searchForm',
      'searchConfig',
      'contentIdPattern',
      'imageUrlTemplate',
      'navigation',
      'tagNamespaces',
      'notes',
    };
    return Map<String, Object?>.fromEntries(
      rawConfig.entries.where(
        (MapEntry<String, Object?> e) => !knownKeys.contains(e.key),
      ),
    );
  }

  // Infer the pagination primitive from config.
  String _paginationPrimitive(
    Map<String, Object?> rawConfig, {
    required bool hasScraper,
    required bool hasApi,
  }) {
    if (hasApi) {
      final Map<String, Object?> api =
          (rawConfig['api']! as Map).cast<String, Object?>();
      final Map<String, Object?> list = api['list'] is Map
          ? (api['list']! as Map).cast<String, Object?>()
          : const <String, Object?>{};
      final Map<String, Object?> pagination = list['pagination'] is Map
          ? (list['pagination']! as Map).cast<String, Object?>()
          : const <String, Object?>{};
      if (pagination['offsetMode'] == true) {
        return EnginePrimitive.paginationOffset;
      }
    }
    return EnginePrimitive.paginationPage;
  }

  // Simple semver "greater-or-equal" check (major.minor.patch only).
  bool _isEngineVersionCompatible(String required, String current) {
    try {
      final List<int> req = required
          .split('.')
          .map<int>((String s) => int.parse(s))
          .toList(growable: false);
      final List<int> cur = current
          .split('.')
          .map<int>((String s) => int.parse(s))
          .toList(growable: false);
      for (int i = 0; i < req.length && i < cur.length; i++) {
        if (cur[i] > req[i]) return true;
        if (cur[i] < req[i]) return false;
      }
      return true;
    } catch (_) {
      return true; // If unparseable, assume compatible.
    }
  }
}
