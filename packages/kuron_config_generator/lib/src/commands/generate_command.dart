import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:logger/logger.dart';

import '../wizard/wizard_builder.dart';
import '../wizard/wizard_runner.dart';
import '../generator/config_generator.dart';
import '../discovery/http_probe.dart';
import '../discovery/cms_detector.dart';
import '../discovery/api_detector.dart';
import '../discovery/api_endpoint_hunter.dart';
import '../validation/validation_orchestrator.dart';
import '../validation/smoke_runner.dart';
import '../validation/skeleton_test_emitter.dart';
import 'package:html/parser.dart' show parse;
import 'package:kuron_config_generator/src/validation/search_key_probe.dart';

// Generate a Kuron source config through interactive questions or URL-assisted discovery.
class GenerateCommand extends Command<void> {
  GenerateCommand() {
    argParser
      ..addOption(
        'url',
        abbr: 'u',
        help: 'Source URL to assist generation (optional).',
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        negatable: false,
        help: 'Run in interactive wizard mode.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output directory for generated config.',
        defaultsTo: 'build/generated',
      )
      ..addFlag(
        'capture-fixtures',
        negatable: false,
        help: 'Save HTTP/browser fixtures for validation.',
      )
      ..addFlag(
        'validate',
        negatable: false,
        help: 'Run validation on the generated config.',
      )
      ..addFlag(
        'live',
        negatable: false,
        help: 'Run live smoke validation through the real adapter '
            '(requires --validate). Emits fixtures + skeleton test.',
      )
      ..addOption(
        'validate-format',
        help: 'Output format for validation report.',
        allowed: ['text', 'json', 'markdown'],
        defaultsTo: 'text',
      )
      ..addOption(
        'template',
        abbr: 't',
        help: 'Clone a live-proven config from your local informations/configs/'
            ' as the theme (e.g. --template hentaiera). Selectors/URL '
            'patterns are copied verbatim; only identity fields change.',
      )
      ..addFlag(
        'fix-suggestions',
        negatable: false,
        help: 'Show fix suggestions even when config is compatible.',
      );
  }

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate a source config through interactive questions or URL discovery.';

  @override
  Future<void> run() async {
    // ponytail: DevelopmentFilter (logger default) drops ALL output when
    // asserts are off — plain `dart run` disables them. ProductionFilter
    // respects the level unconditionally. Swap to PrettyPrinter if this
    // ever runs inside Flutter debug mode again.
    final logger = Logger(
      filter: ProductionFilter(),
      printer: SimplePrinter(),
      level: Level.info,
    );
    final url = argResults?['url'] as String?;
    final interactive = argResults?['interactive'] as bool? ?? false;
    final output = argResults?['output'] as String;
    final template = argResults?['template'] as String?;

    if (url == null && !interactive) {
      stderr.writeln('Error: Must specify --url or --interactive.');
      stderr.writeln(usage);
      exit(64);
    }

    logger.i('Generate command - output: $output');

    if (template != null) {
      await _runTemplateClone(template, url, output, logger);
    } else if (interactive) {
      await _runInteractiveWizard(output, logger);
    } else {
      await _runUrlAssistedGeneration(url!, output, logger);
    }
  }

  /// Clones a live-proven config from local informations/configs/ and swaps
  /// identity fields. Selectors, urlPatterns, reader mode — copied verbatim.
  /// ponytail: proven configs stay PRIVATE (gitignored) — no tracked copies.
  /// Fresh clones get URL-assisted generation instead; --template is a
  /// local-only convenience for machines that have the private configs.
  Future<void> _runTemplateClone(
    String templateId,
    String? url,
    String output,
    Logger logger,
  ) async {
    final candidates = [
      'informations/configs/$templateId-config.json',
      '../../informations/configs/$templateId-config.json',
    ];
    File? source;
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) {
        source = f;
        break;
      }
    }
    if (source == null) {
      stderr.writeln('Error: template "$templateId" not found. Searched:');
      for (final c in candidates) {
        stderr.writeln('  $c');
      }
      stderr.writeln(
        'Proven configs are private (gitignored). Copy one from your private '
        'backup into informations/configs/, or use URL-assisted generation:\n'
        '  generate --url <site-url> --validate',
      );
      exit(66);
    }

    final config =
        (jsonDecode(source.readAsStringSync()) as Map).cast<String, dynamic>();
    final oldBase = config['baseUrl'] as String?;

    if (url != null) {
      final uri = Uri.tryParse(url);
      final host = uri?.host.replaceAll(RegExp(r'^www\.'), '') ?? 'unknown';
      config['source'] = host.replaceAll(RegExp(r'[^a-z0-9]'), '');
      config['baseUrl'] = '${uri?.scheme}://${uri?.host}';
      config.remove('configUrl');
      // Icon path points at the template's asset — drop it.
      config['ui']?.remove('iconPath');
      logger.i('📋 Template: $templateId (${oldBase ?? '?'}) → '
          '${config['baseUrl']}');
    } else {
      stderr.writeln('Error: --template requires --url for the new source.');
      exit(64);
    }

    final outputDir = Directory(output);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    final configFile = File('$output/${config['source']}-config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    logger.i('✓ Config cloned from $templateId: ${configFile.path}');

    await _maybeRunValidation(configFile.path);
  }

  Future<void> _runInteractiveWizard(String output, Logger logger) async {
    final flow = WizardBuilder.buildFlow();
    final runner = WizardRunner(flow: flow);

    logger.i('Starting interactive wizard...\n');
    final answers = await runner.run();

    logger.i('Generating config...');
    final config = ConfigGenerator.generateConfig(answers);

    // Write config to output directory
    final outputDir = Directory(output);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final configFile = File('$output/${answers['sourceId']}-config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    logger.i('✓ Config generated: ${configFile.path}');

    await _maybeRunValidation(configFile.path);
  }

  Future<void> _runUrlAssistedGeneration(
    String url,
    String output,
    Logger logger,
  ) async {
    logger.i('🔍 Probing $url...');
    final probe = await probeUrl(url);

    if (!probe.isSuccess) {
      if (probe.isBlocked) {
        logger.w('Site blocked automated probe (${probe.statusCode}). '
            'Cloudflare or WAF detected. Use --interactive to enter selectors manually.');
      } else {
        logger.e('Probe failed: ${probe.error ?? probe.statusCode}');
      }
      return;
    }

    logger.i(
        '✓ HTTP ${probe.statusCode}, ${probe.body.length} bytes received (${probe.contentType.name})');

    if (probe.contentType == ProbeContentType.json) {
      await _handleApiResponse(probe, output, logger);
      return;
    }

    // API-first: the site shell is clean HTML (no CF/WAF — blocked sites
    // already returned above). Hunt for a hidden JSON API before falling
    // back to scraper selectors: an API endpoint is the patokan when found.
    final pageUri = Uri.tryParse(url);
    if (pageUri != null) {
      logger.i('📡 Hunting for JSON API endpoints...');
      final hunt = await huntApiEndpoints(
        base: pageUri,
        htmlBody: probe.body,
      );
      if (hunt != null) {
        logger.i('✓ API found: ${hunt.endpointUrl} (${hunt.kind.name}, '
            '${(hunt.inference.confidence * 100).round()}% confidence) — '
            'API jadi patokan, bukan scraper.');
        await _emitRestConfig(
          api: hunt.inference,
          host: pageUri.host.replaceAll(RegExp(r'^www\.'), ''),
          homeBase:
              '${pageUri.scheme}://${pageUri.host}',
          output: output,
          logger: logger,
        );
        return;
      }
      logger.i('Tidak ada JSON API terdeteksi — lanjut mode scraper.');
    }

    // Detect CMS from HTML
    final cms = detectCms(probe.body);
    logger.i(
        '📋 CMS detected: ${cms.cmsId} (${(cms.confidence * 100).round()}% confidence)');
    // Phase 3: low-confidence CMS guess → needsReview marker. Selectors are
    // generic guesses; user must review before import.
    final cmsConfidence = CmsConfidence(
      cmsId: cms.cmsId,
      hits: (cms.confidence * 100).round(),
      totalHints: 100,
    );
    if (!cms.isKnown || !cmsConfidence.confident) {
      logger.w('⚠️ CMS confidence below '
          '${(CmsConfidence.confidentThreshold * 100).round()}% — needsReview: '
          'verify all suggested selectors manually.');
    }

    if (cms.isKnown) {
      logger.i('Suggested selectors for $url (${cms.cmsId}):');
      for (final e in cms.selectors.entries) {
        logger.i('  ${e.key}: "${e.value}"');
      }
      logger.i('\nUse --interactive to enter selectors manually, '
          'or edit the generated config to adjust selectors.');
    } else {
      logger.w('Unknown CMS — selectors will be generic guesses.');
    }

    // Detect Search Form dynamically
    final document = parse(probe.body);
    final searchForm = detectSearchForm(document);
    if (searchForm != null) {
      logger.i(
          '🔍 Detected Search Form: endpoint="${searchForm['searchEndpoint']}", param="${searchForm['queryParam']}"');
    }

    // Surface `<html lang>` as a HINT only — spec: it is not proof of
    // content language. The wizard lets the user confirm/override before
    // generation; unverified sources fall back to `global` downstream.
    String? langFromHtml;
    final langMatch =
        RegExp(r'<html[^>]+lang="([^"]+)"').firstMatch(probe.body);
    if (langMatch != null) {
      final raw = langMatch.group(1)!.toLowerCase();
      if (raw == 'id' || raw == 'id-id' || raw == 'in') {
        langFromHtml = 'indonesian';
      } else if (raw.startsWith('en')) {
        langFromHtml = 'english';
      } else if (raw == 'vi' || raw == 'vi-vn') {
        langFromHtml = 'vietnamese';
      } else if (raw == 'ja' || raw == 'ja-jp') {
        langFromHtml = 'japanese';
      }
    }

    // Extract favicon and theme-color from probe HTML
    String? faviconPath;
    final faviconMatch = RegExp(
      r'<link[^>]*rel="(?:shortcut )?icon"[^>]*href="([^"]+)"',
    ).firstMatch(probe.body);
    if (faviconMatch != null) {
      var f = faviconMatch.group(1)!;
      if (f.startsWith('//')) f = 'https:$f';
      faviconPath = f;
    }
    String? themeColor;
    final colorMatch =
        RegExp(r'<meta[^>]*name="theme-color"[^>]*content="([^"]+)"')
            .firstMatch(probe.body);
    if (colorMatch != null) themeColor = colorMatch.group(1)!;

    // Build wizard answers from probe
    final answers = <String, String?>{
      'sourceId': Uri.tryParse(url)?.host.replaceAll(RegExp(r'^www\.'), '') ??
          'unknown',
      'displayName': Uri.tryParse(url)?.host ?? 'Unknown',
      'homeUrl': url,
      'version': '1.0.0',
      'contentType': 'manga',
      'mode': 'scraper',
      'supportsSearch': 'y',
      'supportsChapters': 'y',
      'supportsComments': 'n',
      'needsHeaders': probe.isBlocked ? 'y' : 'n',
      if (langFromHtml != null) 'defaultLanguage': langFromHtml,
      if (faviconPath != null) 'faviconPath': faviconPath,
      if (themeColor != null) 'themeColor': themeColor,
      if (searchForm != null) 'searchEndpoint': searchForm['searchEndpoint'],
      if (searchForm != null) 'searchQueryParam': searchForm['queryParam'],
    };

    // Fill selectors from CMS detection where available
    if (cms.isKnown) {
      //  merge CMS selectors into wizard answer slots
      // Using the first matched selector category for each slot
      final cats = <String, String>{
        'listSelector':
            cms.selectors['list.item'] ?? cms.selectors['list.title'] ?? '',
        'detailTitleSelector': cms.selectors['detail.title'] ?? 'h1',
      };
      answers['listSelector'] = cats['listSelector'];
      answers['detailTitleSelector'] = cats['detailTitleSelector'];
    }

    // Detect chapterData script for reader mode
    final hasChapterData = RegExp(r'chapterData\s*=\s*\{').hasMatch(probe.body);
    String? cdnBase;
    if (hasChapterData) {
      final baseMatch =
          RegExp(r'"base"\s*:\s*"([^"]+)"').firstMatch(probe.body);
      cdnBase = baseMatch?.group(1);
      logger.i('📖 chapterData script detected — '
          '${cdnBase != null ? "CDN base: $cdnBase" : "no CDN base found"}');
    }

    // Fill CMS defaults into answers
    if (cms.isKnown) {
      answers['cmsThemeType'] = cms.themeType;
      answers['listSelector'] =
          cms.selectors['list.item'] ?? cms.selectors['list.title'] ?? '';
      answers['listTitleSelector'] = cms.selectors['list.title'] ?? '';
      answers['detailTitleSelector'] = cms.selectors['detail.title'] ?? 'h1';
      answers['detailCoverSelector'] = cms.selectors['detail.cover'] ?? 'img';
      answers['chapterContainer'] =
          cms.selectors['chapters.item'] ?? 'a[href*="chapter"]';
      answers['readerImageSel'] = cms.selectors['reader.image'] ?? 'img';

      if (cms.searchDefaults != null) {
        answers['searchUrl'] ??= cms.searchDefaults!['searchUrl'] as String?;
        answers['searchQueryParam'] ??=
            cms.searchDefaults!['queryParam'] as String?;
      }

      if (cms.readerDefaults != null) {
        answers['readerMode'] =
            cms.readerDefaults!['mode'] as String? ?? 'directUrl';
      } else {
        answers['readerMode'] = 'directUrl';
      }

      if (answers['readerMode'] == 'directUrl' && hasChapterData) {
        answers['readerMode'] = 'chapterDataScript';
        if (cdnBase != null) answers['cdnBase'] = cdnBase;
        logger.i(
            '📖 Using chapterDataScript reader mode${cdnBase != null ? " (base: $cdnBase)" : ""}');
      }
    }

    if (probe.isBlocked) {
      answers['needsCloudflare'] = 'y';
    }

    logger.i('Generating config...');
    final config = ConfigGenerator.generateConfig(answers);

    // Write config
    final outputDir = Directory(output);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    final sourceId = answers['sourceId'] ?? 'unknown';
    final configFile = File('$output/$sourceId-config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );

    logger.i('✓ Config generated: ${configFile.path}');
    if (cms.isKnown) {
      logger.i('💡 Review suggested selectors in the config — '
          'adjust paths, CSS classes, and image selectors as needed.');
    }

    await _maybeRunValidation(configFile.path);
  }

  Future<void> _handleApiResponse(
    ProbeResult probe,
    String output,
    Logger logger,
  ) async {
    final url = argResults?['url'] as String;
    final json = probe.jsonBody;
    if (json == null) {
      logger.w('JSON body is empty or malformed.');
      return;
    }

    final api = inferApi(url, json);
    logger.i('📡 API mode detected — inferred structure:');
    logger.i(
        '  isList=${api.hasList} isDetail=${api.hasDetail} confidence=${(api.confidence * 100).round()}%');

    final uri = Uri.tryParse(url);
    final host = uri?.host.replaceAll(RegExp(r'^www\.'), '') ?? 'unknown';
    await _emitRestConfig(
      api: api,
      host: host,
      homeBase: '${uri?.scheme}://${uri?.host}',
      output: output,
      logger: logger,
    );
  }

  // Shared REST-config emitter: API responses are the patokan (no CF
  // bypass, no theme-specific reader modes — the "general" mode).
  Future<void> _emitRestConfig({
    required ApiInference api,
    required String host,
    required String homeBase,
    required String output,
    required Logger logger,
  }) async {
    final answers = <String, String?>{
      'sourceId': host,
      'displayName': host,
      'homeUrl': homeBase,
      'version': '1.0.0',
      'contentType': 'manga',
      'mode': 'rest_json',
      'supportsSearch': 'y',
      'supportsChapters': 'n',
      'supportsComments': 'n',
      'needsHeaders': 'n',
      if (api.listEndpoint != null) 'listEndpoint': api.listEndpoint,
      if (api.detailEndpoint != null) 'detailEndpoint': api.detailEndpoint,
      'apiBase': api.baseUrl,
    };

    logger.i('Generating config with REST API mode...');
    final config = ConfigGenerator.generateConfig(answers);

    // Write config
    final outputDir = Directory(output);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    final configFile = File('$output/$host-config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    logger.i('✓ Config generated: ${configFile.path}');
    logger.i('💡 This is a draft — review endpoints, paths, and pagination.');

    await _maybeRunValidation(configFile.path);
  }

  // If --validate flag is set, run the validation loop on [configPath].
  Future<void> _maybeRunValidation(String configPath) async {
    final validate = argResults?['validate'] as bool? ?? false;
    if (!validate) return; // R1.4: preserve existing behavior

    final format = argResults?['validate-format'] as String? ?? 'text';

    // R5.5: validate format value is already enforced by argParser allowed list
    final showAll = argResults?['fix-suggestions'] as bool? ?? false;

    final orchestrator = ValidationOrchestrator();
    await orchestrator.runValidationLoop(
      configPath: configPath,
      reportFormat: format,
      showAllSuggestions: showAll,
    );

    await _maybeRunLiveSmoke(configPath);
  }

  // If --live flag is set, run live smoke validation through the real
  // adapter and emit fixtures + skeleton test on success.
  Future<void> _maybeRunLiveSmoke(String configPath) async {
    final live = argResults?['live'] as bool? ?? false;
    if (!live) return;

    final logger = Logger(
      filter: ProductionFilter(),
      printer: SimplePrinter(),
      level: Level.info,
    );
    final file = File(configPath);
    if (!file.existsSync()) {
      logger.e('Live smoke skipped — config not found: $configPath');
      return;
    }
    final config =
        (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
    final sourceId = config['source'] as String? ??
        Uri.tryParse(config['baseUrl'] as String? ?? '')
            ?.host
            .replaceAll(RegExp(r'^www\.'), '') ??
        'unknown';
    final outputDir = File(configPath).parent.path;

    logger.i('🌐 Live smoke validation via real adapter...');
    final report = await SmokeRunner().run(config);

    for (final r in report.results) {
      logger.i('  ${r.passed ? "✓" : "✗"} $r');
    }

    // Phase 2/3: negative-case findings + search-key/CMS confidence.
    if (report.findings.isNotEmpty) {
      logger.i('🔎 Probe findings:');
      for (final f in report.findings) {
        logger.w('  $f');
      }
    }

    if (!report.allPassed) {
      logger.e(
          '✗ Live smoke FAILED — ${report.failures.length} screen(s) failing. '
          'Fix selectors and re-run before importing.');
      exitCode = 1;
      return;
    }

    FixtureEmitter(outputDir: outputDir, sourceId: sourceId)
        .writeAll(report.fixtures, config);
    SkeletonTestEmitter(outputDir: outputDir, sourceId: sourceId).write();
    logger.i('✓ Live smoke passed. Fixtures + skeleton test emitted to '
        '$outputDir/fixtures/$sourceId and ${sourceId}_generated_live_test.dart');
  }
}
