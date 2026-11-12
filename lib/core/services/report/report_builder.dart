/// Builds zero-secret GitHub issue links for anomaly / error reports.
///
/// Keputusan 4: every build uses one channel — a prefilled `issues/new`
/// URL the user opens and submits themselves. No PAT, no auto-create,
/// no GitHub search. Keputusan 7: titles follow the existing
/// `[bug][<sourceId>] <feature>: <kind>` convention of `kuron-extensions`.
///
/// Payload hygiene (spec "Payload laporan tanpa data pribadi dan URL
/// bersih"): only technical fields leave the device, every URL is reduced
/// to its path (query params + fragment dropped), and the anomaly
/// fingerprint token is always present so duplicates can be spotted.
class ReportBuilder {
  ReportBuilder._();

  /// Owner of both report targets.
  static const String defaultOwner = 'shirokun20';

  /// Source-layer bugs (config/selector/parsing) live here.
  static const String extensionsRepo = 'kuron-extensions';

  /// App-layer bugs (feature code, UI, storage) live here.
  static const String mobileRepo = 'kuron-mobile';

  /// Prefix of the hidden dedup token appended to every report body.
  static const String fingerprintTokenPrefix = '<!-- kuron-anomaly:';

  /// Suggested target repo: source-layer failures belong to the config
  /// repo, app-layer failures to the app repo. The user may override it.
  static String suggestRepo({required bool isSourceLayer}) =>
      isSourceLayer ? extensionsRepo : mobileRepo;

  /// `[bug][<sourceId>] <feature>: <kind>` — same shape as the 58 issues
  /// the generator-validation machine already files.
  static String buildIssueTitle({
    required String sourceId,
    required String feature,
    required String kind,
  }) => '[bug][$sourceId] $feature: $kind';

  /// Technical-only report body. Optional fields are omitted when absent
  /// so an anomaly report and an error-log report share one shape.
  static String buildReportBody({
    required String sourceId,
    required String feature,
    required String kind,
    required String fingerprint,
    String? templatePath,
    String? configVersion,
    String? appVersion,
    int? statusCode,
    String? urlPath,
    String? message,
  }) {
    final lines = <String>[
      '### Kuron report',
      '',
      '- sourceId: `${_clean(sourceId)}`',
      '- feature: `${_clean(feature)}`',
      '- kind: `${_clean(kind)}`',
    ];

    void addField(String label, String? value) {
      if (value == null) return;
      final cleaned = _clean(value);
      if (cleaned.isEmpty) return;
      lines.add('- $label: `$cleaned`');
    }

    addField('template', templatePath == null ? null : pathOnly(templatePath));
    addField('configVersion', configVersion);
    addField('appVersion', appVersion);
    if (statusCode != null) lines.add('- statusCode: `$statusCode`');
    addField('urlPath', urlPath == null ? null : pathOnly(urlPath));
    addField('message', message);

    final token = fingerprint.trim();
    lines
      ..add('')
      ..add(
        token.isEmpty
            ? '$fingerprintTokenPrefix -->'
            : '$fingerprintTokenPrefix $token -->',
      );

    return stripQueryParamsFromUrls(lines.join('\n'));
  }

  /// Prefilled `https://github.com/<owner>/<repo>/issues/new` link.
  ///
  /// [repo] accepts either a bare name (`kuron-mobile`) or `owner/repo`.
  /// The body is query-stripped and, when [fingerprint] is given, carries
  /// exactly one dedup token line.
  static Uri buildPrefilledUrl({
    required String repo,
    required String title,
    required String body,
    String? fingerprint,
  }) {
    final trimmedRepo = repo.trim();
    final fullRepo = trimmedRepo.contains('/')
        ? trimmedRepo
        : '$defaultOwner/$trimmedRepo';

    var cleanBody = stripQueryParamsFromUrls(body);
    final token = fingerprint?.trim() ?? '';
    if (token.isNotEmpty) {
      final tokenLine = '$fingerprintTokenPrefix $token -->';
      if (!cleanBody.contains(tokenLine)) {
        cleanBody = cleanBody.trim().isEmpty
            ? tokenLine
            : '$cleanBody\n\n$tokenLine';
      }
    }

    return Uri.https('github.com', '/$fullRepo/issues/new', {
      'title': title,
      'body': cleanBody,
    });
  }

  /// Reduces [value] to its path: absolute URLs keep only `uri.path`,
  /// anything already path-like is only query-stripped.
  static String pathOnly(String? value) {
    if (value == null) return '';
    final cleaned = stripQueryParamsFromUrls(value.trim());
    if (cleaned.isEmpty) return '';
    final uri = Uri.tryParse(cleaned);
    if (uri != null && uri.hasScheme && uri.path.isNotEmpty) {
      return uri.path;
    }
    final cut = cleaned.indexOf(RegExp(r'[?#]'));
    return cut < 0 ? cleaned : cleaned.substring(0, cut);
  }

  /// Removes `?query` and `#fragment` from every URL found in [text].
  ///
  /// Trailing sentence punctuation is preserved so plain prose survives
  /// the rewrite (`https://b.test/y?k=v.` → `https://b.test/y.`).
  static String stripQueryParamsFromUrls(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(_urlPattern, (match) {
      final raw = match.group(0)!;
      final punctuation = _trailingPunctuation.firstMatch(raw)?.group(0) ?? '';
      final base = punctuation.isEmpty
          ? raw
          : raw.substring(0, raw.length - punctuation.length);
      final cut = base.indexOf(RegExp(r'[?#]'));
      final stripped = cut < 0 ? base : base.substring(0, cut);
      return '$stripped$punctuation';
    });
  }

  static final RegExp _urlPattern = RegExp(r'https?://[^\s<>"]+');

  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?]+$');

  /// Collapses whitespace and backticks so a field can never break out of
  /// its markdown line.
  static String _clean(String value) =>
      value.replaceAll('`', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
}
