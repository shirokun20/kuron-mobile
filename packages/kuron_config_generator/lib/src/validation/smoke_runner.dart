import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'negative_probes.dart';
import 'search_key_probe.dart';

/// Result of a single screen probe during live smoke validation.
class ScreenResult {
  const ScreenResult({
    required this.screen,
    required this.passed,
    this.itemCount = 0,
    this.failure,
  });

  final String screen;
  final bool passed;
  final int itemCount;
  final String? failure;

  @override
  String toString() =>
      passed ? '$screen: OK ($itemCount items)' : '$screen: FAIL — $failure';
}

/// Aggregate outcome of the 6-screen live smoke run.
class SmokeReport {
  const SmokeReport({
    required this.results,
    required this.fixtures,
    this.findings = const [],
  });

  final List<ScreenResult> results;

  /// Raw HTML per probed screen, for golden fixture emission.
  final Map<String, String> fixtures;

  /// Negative-case probe findings (D4) — advisory unless blocking.
  final List<ProbeFinding> findings;

  bool get allPassed =>
      results.every((r) => r.passed) && !findings.any((f) => f.isBlocking);
  List<ScreenResult> get failures =>
      results.where((r) => !r.passed).toList(growable: false);
}

/// One taxonomy value to walk through tag-routing in the smoke probe.
class _TaxonomyTarget {
  const _TaxonomyTarget(this.type, this.value);

  final String type;
  final String value;
}
/// Runs a generated scraper config through the real [GenericScraperAdapter]
/// and asserts the six app screens (home, search, detail, taxonomy, chapters,
/// reader) return usable data. Captures raw HTML per screen for fixture emission.
///
/// ponytail: probes are sequential and shallow (first item walked into
/// detail/reader); upgrade to parallel + multi-item sampling when a source
/// needs deeper coverage than "does the happy path work".
class SmokeRunner {
  SmokeRunner({
    Logger? logger,
    this.settleDelay = const Duration(seconds: 3),
    this.detailRetryDelay = const Duration(seconds: 8),
  }) : _logger = logger ?? Logger(level: Level.off);

  final Logger _logger;

  /// Delay between screen probes. Rate-limited hosts (akazascans/nginx) answer
  /// a burst of back-to-back probes with 429 empty shells, so probes are
  /// spaced. ponytail: injectable so tests don't pay the wall-clock.
  final Duration settleDelay;

  /// Extra wait before the one detail retry when chapters come back empty.
  final Duration detailRetryDelay;

  Future<SmokeReport> run(Map<String, dynamic> config,
      {String? probedUrl}) async {
    final baseUrl = config['baseUrl'] as String?;
    if (baseUrl == null || baseUrl.isEmpty) {
      return SmokeReport(
        results: [
          ScreenResult(
              screen: 'config', passed: false, failure: 'missing baseUrl'),
        ],
        fixtures: const {},
      );
    }

    // #62: live smoke must run the stored config, not --url. A parked-domain
    // config passes 5/5 against the wrong host and masks the rot.
    final storedHost = Uri.tryParse(baseUrl)?.host ?? '';
    final probedHost = Uri.tryParse(probedUrl ?? '')?.host ?? '';
    if (probedHost.isNotEmpty && storedHost != probedHost) {
      return SmokeReport(
        results: [
          ScreenResult(
              screen: 'config',
              passed: false,
              failure:
                  'baseUrl host mismatch: stored $storedHost vs probed $probedHost'),
        ],
        fixtures: const {},
      );
    }

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: ((config['network'] as Map?)?['headers'] as Map?)
          ?.cast<String, dynamic>(),
      // Live sites flake; treat any status as parseable so parser behavior
      // is what's under test, not HTTP status codes.
      validateStatus: (status) => status != null && status < 500,
    ));
    final urlBuilder = GenericUrlBuilder(baseUrl: baseUrl);
    final parser = GenericHtmlParser(logger: _logger);
    final adapter = GenericScraperAdapter(
      dio: dio,
      urlBuilder: urlBuilder,
      parser: parser,
      logger: _logger,
      sourceId: config['source'] as String? ?? 'smoke',
    );

    final results = <ScreenResult>[];
    final fixtures = <String, String>{};
    final findings = <ProbeFinding>[];

    final settle = settleDelay;

    // ── home ────────────────────────────────────────────────────────────────
    List<Content> homeItems = const [];
    var homeHtml = '';
    try {
      final result = await adapter.search(
        const SearchFilter(query: '', page: 1),
        config,
      );
      homeItems = result.items;
      homeHtml = await _fetchRaw(dio, baseUrl);
      if (homeItems.isEmpty) {
        results.add(
            ScreenResult(screen: 'home', passed: false, failure: '0 items'));
      } else if (homeItems.first.id.isEmpty || homeItems.first.title.isEmpty) {
        results.add(ScreenResult(
            screen: 'home',
            passed: false,
            itemCount: homeItems.length,
            failure: 'first item missing id/title'));
      } else {
        final relCovers = homeItems
            .where((c) =>
                c.coverUrl.startsWith('/') && !c.coverUrl.startsWith('//'))
            .length;
        results.add(ScreenResult(
            screen: 'home',
            passed: true,
            itemCount: homeItems.length,
            failure: relCovers > 0
                ? 'warning: $relCovers relative cover URLs'
                : null));
      }
    } catch (e) {
      results.add(
          ScreenResult(screen: 'home', passed: false, failure: e.toString()));
    }
    if (homeHtml.isNotEmpty) fixtures['home'] = homeHtml;
    findings.addAll(runDomProbes(homeHtml));
    final relFinding =
        probeRelativeCovers(homeItems.map((c) => c.coverUrl).toList(), baseUrl);
    if (relFinding != null) findings.add(relFinding);
    final badgeFinding =
        probeTitleBadges(homeItems.map((c) => c.title).toList());
    if (badgeFinding != null) findings.add(badgeFinding);

    // ── search ──────────────────────────────────────────────────────────────
    await Future<void>.delayed(settle);
    try {
      // ponytail: single-char queries ('a') are ignored by many WP search
      // backends (min keyword length) and return a legit empty page. Use a
      // word from the first home title instead — real-world search behavior.
      final firstWord = homeItems.isEmpty
          ? 'a'
          : (homeItems.first.title
                      .split(RegExp(r'[^A-Za-z0-9]+'))
                      .where((w) => w.length >= 4)
                      .toList()
                    ..sort((x, y) => y.length.compareTo(x.length)))
                  .firstOrNull ??
              'a';
      final result = await adapter.search(
        SearchFilter(query: firstWord, page: 1),
        config,
      );
      results.add(ScreenResult(
          screen: 'search',
          passed: result.items.isNotEmpty,
          itemCount: result.items.length,
          failure: result.items.isEmpty
              ? '0 results for query "$firstWord"'
              : null));
      if (result.items.isNotEmpty) {
        // Phase 3: verify the search key actually filtered (keiyoushi ?q=
        // trap — wrong param silently returns unfiltered recents).
        final key = verifySearchKey(
          query: firstWord,
          titles: result.items.map((c) => c.title).toList(),
        );
        if (key.finding != null) findings.add(key.finding!);
      }
    } catch (e) {
      results.add(
          ScreenResult(screen: 'search', passed: false, failure: e.toString()));
    }

    // Detail/chapters/reader need an id from home.
    if (homeItems.isEmpty) {
      for (final s in ['detail', 'chapters', 'reader']) {
        results.add(ScreenResult(
            screen: s,
            passed: false,
            failure: 'skipped — home yielded no items'));
      }
      return SmokeReport(
          results: results, fixtures: fixtures, findings: findings);
    }

    // ── detail ──────────────────────────────────────────────────────────────
    await Future<void>.delayed(settle);
    final contentId = homeItems.first.id;
    AdapterDetailResult? detail;
    try {
      detail = await adapter.fetchDetail(contentId, config);
      if (detail.content.chapters?.isEmpty ?? true) {
        // ponytail: 429-prone hosts serve an empty shell on the first hit.
        await Future<void>.delayed(detailRetryDelay);
        detail = await adapter.fetchDetail(contentId, config);
      }
      final hasPages = detail.content.pageCount > 0 ||
          detail.imageUrls.isNotEmpty ||
          (detail.content.chapters?.isNotEmpty ?? false);
      results.add(ScreenResult(
          screen: 'detail',
          passed: detail.content.title.isNotEmpty && hasPages,
          itemCount: detail.imageUrls.length,
          failure: !hasPages
              ? 'no pages or chapters for $contentId'
              : (detail.content.title.isEmpty ? 'empty title' : null)));
    } catch (e) {
      results.add(
          ScreenResult(screen: 'detail', passed: false, failure: e.toString()));
    }

    // #64: `detail: OK` only proved title + pages, so a dead cover/tag/author
    // selector still shipped 5/5 green. Re-read the live detail page and probe
    // the remaining configured fields against it. Title is excluded — the
    // detail screen assertion above already fails on an empty one.
    if (detail != null) {
      final fields = _detailFieldsConfig(config)..remove('title');
      if (fields.isNotEmpty) {
        final detailUrl = _detailUrl(config, contentId, urlBuilder);
        if (detailUrl.isNotEmpty) {
          await Future<void>.delayed(settle);
          final html = await _fetchRaw(dio, detailUrl);
          if (html.isNotEmpty) {
            findings.addAll(await probeDetailFields(
              html,
              fields,
              parser: parser,
              resolvedCoverUrl: detail.content.coverUrl,
              baseUrl: baseUrl,
              contentTypeOf: (url) => _probeContentType(dio, url, config),
            ));
          }
        }
      }
    }
    // ── taxonomy (6th screen) ─────────────────────────────────────────────
    // A green detail screen once masked dead taxonomy archives (authorSearch
    // 404 etc.). Walk one live value per taxonomy type through the real
    // tag-routing path; empty results fail the run (blocking).
    if (detail != null) {
      final patterns =
          (config['scraper'] as Map?)?['urlPatterns'] as Map?;
      final hasTaxonomyRoute = patterns != null &&
          (patterns.containsKey('genreSearch') ||
              patterns.containsKey('tagSearch') ||
              patterns.containsKey('authorSearch') ||
              patterns.containsKey('artistSearch'));
      if (!hasTaxonomyRoute) {
        findings.add(ProbeFinding(
          probe: 'taxonomy-skipped',
          severity: FindingSeverity.info,
          message: 'no taxonomy patterns configured — screen skipped',
        ));
      } else {
        final taxonomyTargets = _taxonomyTargets(detail.content);
        var taxonomyOk = true;
        String? taxonomyFailure;
        for (final target in taxonomyTargets.take(4)) {
          await Future<void>.delayed(settle);
          try {
            final res = await adapter.search(
              SearchFilter(query: '', page: 1, includeTags: [
                FilterItem(id: 0, name: target.value, type: target.type),
              ]),
              config,
            );
            if (res.items.isEmpty) {
              taxonomyOk = false;
              taxonomyFailure = '${target.type}:${target.value} → 0 items';
              break;
            }
          } catch (e) {
            taxonomyOk = false;
            taxonomyFailure = '${target.type}:${target.value} → $e';
            break;
          }
        }
        results.add(ScreenResult(
          screen: 'taxonomy',
          passed: taxonomyOk,
          itemCount: taxonomyTargets.length,
          failure: taxonomyFailure,
        ));
      }
    }

    final chapters = detail?.content.chapters;
    if (chapters == null || chapters.isEmpty) {
      // Gallery-only source (hentaifox family etc.): reader images come from
      // the detail page itself via reader mode (hentaifoxCdn). Probe reader
      // directly with the content id instead of failing.
      final readerMode = ((config['scraper'] as Map?)?['selectors']
          as Map?)?['reader'] as Map?;
      final isGallery = readerMode?['mode'] == 'hentaifoxCdn';
      results.add(ScreenResult(
          screen: 'chapters',
          passed: isGallery,
          failure: isGallery ? null : 'no chapters (gallery-only source?)'));
      if (!isGallery) {
        results.add(const ScreenResult(
            screen: 'reader', passed: false, failure: 'skipped — no chapters'));
        return SmokeReport(
            results: results, fixtures: fixtures, findings: findings);
      }
      try {
        final chapterData = await adapter.fetchChapterImages(contentId, config);
        final images = chapterData?.images ?? const <String>[];
        final impurityFinding = probeReaderScopeImpurity(images);
        if (impurityFinding != null) findings.add(impurityFinding);
        if (images.isEmpty) {
          results.add(ScreenResult(
              screen: 'reader', passed: false, failure: '0 images'));
        } else {
          final contentType =
              await _probeContentType(dio, images.first, config);
          final ok = contentType != null && contentType.startsWith('image/');
          results.add(ScreenResult(
              screen: 'reader',
              passed: ok,
              itemCount: images.length,
              failure: ok
                  ? null
                  : 'first image content-type "${contentType ?? 'error'}" '
                      'not image/*'));
        }
      } catch (e) {
        results.add(ScreenResult(
            screen: 'reader', passed: false, failure: e.toString()));
      }
      return SmokeReport(
          results: results, fixtures: fixtures, findings: findings);
    }
    results.add(ScreenResult(
        screen: 'chapters', passed: true, itemCount: chapters.length));

    try {
      // ponytail: some hosts password-lock the newest chapter(s) (bunmanga
      // mhcl gate). Sample up to 3 recent chapters; note the lock.
      var images = const <String>[];
      var sampledId = '';
      for (final ch in chapters.take(3)) {
        await Future<void>.delayed(settle);
        final chapterData = await adapter.fetchChapterImages(ch.id, config);
        images = chapterData?.images ?? const <String>[];
        sampledId = ch.id;
        if (images.isNotEmpty) break;
      }
      if (sampledId != chapters.first.id) {
        findings.add(ProbeFinding(
          probe: 'reader-sampled-older',
          severity: FindingSeverity.info,
          message:
              'reader sampled "$sampledId" — newest chapter(s) locked/empty',
        ));
      }
      final impurityFinding = probeReaderScopeImpurity(images);
      if (impurityFinding != null) findings.add(impurityFinding);
      if (images.isEmpty) {
        results.add(
            ScreenResult(screen: 'reader', passed: false, failure: '0 images'));
      } else {
        // Spot-check first image resolves to image/* content.
        final contentType = await _probeContentType(dio, images.first, config);
        final ok = contentType != null && contentType.startsWith('image/');
        results.add(ScreenResult(
            screen: 'reader',
            passed: ok,
            itemCount: images.length,
            failure: ok
                ? null
                : 'first image content-type "${contentType ?? 'error'}" '
                    'not image/*'));
      }
    } catch (e) {
      results.add(
          ScreenResult(screen: 'reader', passed: false, failure: e.toString()));
    }

    return SmokeReport(
        results: results, fixtures: fixtures, findings: findings);
  }
  /// One live value per taxonomy type present on the detail [content],
  /// for the taxonomy screen probe. Artist names supplement from the
  /// typed string field for cached configs whose tags lack the type.
  List<_TaxonomyTarget> _taxonomyTargets(Content content) {
    const types = ['tag', 'genre', 'author', 'artist'];
    final seen = <String>{};
    final targets = <_TaxonomyTarget>[];
    void add(String type, String name) {
      final value = name.trim();
      if (value.isEmpty) return;
      if (seen.add('$type:${value.toLowerCase()}')) {
        targets.add(_TaxonomyTarget(type, value));
      }
    }

    for (final tag in content.tags) {
      final type = tag.type.toLowerCase().trim();
      if (types.contains(type)) add(type, tag.name);
    }
    for (final name in content.artists) {
      add('artist', name);
    }
    return targets;
  }

  /// Detail page URL for [contentId], resolved exactly the way
  /// `GenericScraperAdapter.fetchDetail` does. Empty when the config has no
  /// `scraper.urlPatterns.detail` entry (REST sources take a different path).
  /// `scraper.selectors.detail.fields` as a mutable copy, empty when absent.
  Map<String, dynamic> _detailFieldsConfig(Map<String, dynamic> config) {
    final selectors = (config['scraper'] as Map?)?['selectors'] as Map?;
    final detailCfg = selectors?['detail'] as Map?;
    return Map<String, dynamic>.from(
        (detailCfg?['fields'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{});
  }

  String _detailUrl(
    Map<String, dynamic> config,
    String contentId,
    GenericUrlBuilder urlBuilder,
  ) {
    final patterns = (config['scraper'] as Map?)?['urlPatterns'] as Map?;
    final value = patterns?['detail'];
    final template = value is String
        ? value
        : value is Map
            ? value['url'] as String? ?? ''
            : '';
    return template.isEmpty
        ? ''
        : urlBuilder.buildDetailUrl(template, contentId);
  }

  Future<String> _fetchRaw(Dio dio, String path) async {
    try {
      final res = await dio.get<String>(
        path.startsWith('http') ? path : '/',
        options: Options(responseType: ResponseType.plain),
      );
      return res.data ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Magic-byte sniffing for mislabeled CDNs (e.g. WebP served as
  /// `text/plain; charset=koi8-r`). Returns `image/<fmt>` on match.
  String? _sniffImageMagic(List<int> bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return 'image/webp';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 && // P
        bytes[2] == 0x4E && // N
        bytes[3] == 0x47) {
      // G
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 && // G
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46) {
      // F
      return 'image/gif';
    }
    return null;
  }

  Future<String?> _probeContentType(
    Dio dio,
    String url,
    Map<String, dynamic> config,
  ) async {
    Map<String, dynamic>? headersOf() =>
        (((config['network'] as Map?)?['imageHeaders'] as Map?) ??
                (config['network'] as Map?)?['headers'] as Map?)
            ?.cast<String, dynamic>();
    Future<String?> sniff() async {
      try {
        final res = await dio.get<List<int>>(
          url,
          options: Options(
            headers: {...?headersOf(), 'range': 'bytes=0-1023'},
            responseType: ResponseType.bytes,
          ),
        );
        return _sniffImageMagic(res.data ?? const <int>[]);
      } catch (_) {
        return null;
      }
    }

    try {
      final res = await dio.head<Object?>(
        url,
        options: Options(headers: headersOf(), followRedirects: true),
      );
      final contentType = res.headers.value('content-type');
      if (contentType != null && contentType.startsWith('image/')) {
        return contentType;
      }
      // Header lies (or is missing) — verify actual bytes.
      return await sniff();
    } catch (_) {
      // Some CDNs reject HEAD; fall back to ranged GET + magic sniff.
      return await sniff();
    }
  }
}

// ── #64: detail-field gate ───────────────────────────────────────────────

/// Detail fields the gate probes when a config declares them. Fields the
/// config omits are never probed, so a gallery-only source (hentaifox family:
/// no author, no tags) keeps passing untouched.
const _probedDetailFields = [
  'coverUrl',
  'title',
  'description',
  'author',
  'artist',
  'genres',
  'tags',
  'publisher',
  'status',
];

/// Issue #64 — `detail: OK` proved only title + pages, so a config whose cover
/// selector read `src` where the markup carries `data-src` (or whose tag
/// selector pointed at a renamed container) shipped 5/5 green. 2026-09-27 wave:
/// ~35 sources. For every declared detail field, confirm the selector matches
/// the live page, and that a declared cover resolves to `image/*`.
///
/// Severity: **blocking** when a declared selector matches nothing (the config
/// is provably wrong) or when the cover is empty / resolves to a non-image. A
/// selector that matches but extracts nothing is a **warning** — hosts
/// rate-limit and hotlink-protect, and a title/status block can legally render
/// empty on one entry without the selector being dead.
///
/// [resolvedCoverUrl] is what the adapter actually resolved (after its lazy-attr
/// fallback chain), so a relative or placeholder src it fixed up is not
/// double-reported. [contentTypeOf] is injected to keep the DOM half pure.
Future<List<ProbeFinding>> probeDetailFields(
  String rawHtml,
  Map<String, dynamic> fieldsConfig, {
  required GenericHtmlParser parser,
  required String resolvedCoverUrl,
  required String baseUrl,
  required Future<String?> Function(String url) contentTypeOf,
}) async {
  if (rawHtml.isEmpty || fieldsConfig.isEmpty) return const [];
  final doc = parser.parse(rawHtml);
  final findings = <ProbeFinding>[];

  for (final key in _probedDetailFields) {
    final def = fieldsConfig[key];
    if (def is! Map) continue;
    final selector = (def['selector'] as String?)?.trim();
    if (selector == null || selector.isEmpty) continue;
    // A declared fallback means the config already tolerates a miss.
    if ((def['fallback'] as String?)?.isNotEmpty == true) continue;

    final fieldSelector = FieldSelector.fromMap(def.cast<String, dynamic>());
    final matched = parser.selectAll(doc, selector);
    if (matched.isEmpty) {
      findings.add(ProbeFinding(
        probe: 'detail-field-empty',
        severity: FindingSeverity.blocking,
        message: 'detail field "$key" selector "$selector" matched 0 elements '
            'on the live page',
        suggestion: 'fix the selector or drop the field in '
            'scraper.selectors.detail.fields',
      ));
      continue;
    }

    // Matched, but nothing usable came out of it.
    final values = key == 'coverUrl'
        ? [parser.extractFromElement(matched.first, fieldSelector) ?? '']
        : parser.extractList(doc, fieldSelector);
    if (values.every((v) => v.trim().isEmpty)) {
      findings.add(ProbeFinding(
        probe: 'detail-field-empty',
        severity: FindingSeverity.warning,
        message: 'detail field "$key" selector "$selector" matched '
            '${matched.length} element(s) but extracted no value',
        suggestion: 'check the attribute chain / text for "$key"',
      ));
    }
  }

  // Cover content-type: probe what the adapter resolved, not the raw attribute.
  if (fieldsConfig['coverUrl'] is Map) {
    final cover = resolvedCoverUrl.trim();
    if (cover.isEmpty) {
      findings.add(ProbeFinding(
        probe: 'detail-cover-not-image',
        severity: FindingSeverity.blocking,
        message: 'detail coverUrl resolved to an empty URL',
        suggestion: 'cover selector does not match, or the attribute is a '
            'lazy-load placeholder the fallback chain misses',
      ));
    } else {
      final absolute = cover.startsWith('http') ? cover : '$baseUrl$cover';
      final type = await contentTypeOf(absolute);
      // null = CDN refused HEAD/GET (rate limit, hotlink guard) — advisory
      // only, a hard 4xx on every image would fail the reader probe anyway.
      if (type != null && !type.startsWith('image/')) {
        findings.add(ProbeFinding(
          probe: 'detail-cover-not-image',
          severity: FindingSeverity.blocking,
          message: 'detail cover resolves to "$type", not image/*: $absolute',
          suggestion: 'cover selector is probably grabbing a non-image node',
        ));
      }
    }
  }

  return findings;
}

/// Writes golden fixtures (raw HTML per screen + manifest.json) next to the
/// generated config.
class FixtureEmitter {
  FixtureEmitter({required this.outputDir, required this.sourceId});

  final String outputDir;
  final String sourceId;

  Directory get _fixtureDir => Directory('$outputDir/fixtures/$sourceId');

  void writeAll(Map<String, String> fixtures, Map<String, dynamic> config) {
    if (fixtures.isEmpty) return;
    _fixtureDir.createSync(recursive: true);
    for (final entry in fixtures.entries) {
      File('${_fixtureDir.path}/${entry.key}.html')
          .writeAsStringSync(entry.value);
    }
    File('${_fixtureDir.path}/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'source': sourceId,
        'baseUrl': config['baseUrl'],
        'probedAt': DateTime.now().toUtc().toIso8601String(),
        'screens': fixtures.keys.toList(),
      }),
    );
  }
}
