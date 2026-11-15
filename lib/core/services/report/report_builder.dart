class ReportBuilder {
  const ReportBuilder._();

  static const String mobileRepo = 'kuron-mobile';
  static const String extensionsRepo = 'kuron-extensions';
  static const String _owner = 'shirokun20';

  /// Suggests destination repo: source-layer issues -> kuron-extensions,
  /// app/feature issues -> kuron-mobile.
  static String suggestRepo({required bool isSourceLayer}) {
    return isSourceLayer ? extensionsRepo : mobileRepo;
  }

  /// Builds issue title following `[bug][sourceId] feature: kind`.
  static String buildIssueTitle({
    required String sourceId,
    required String feature,
    required String kind,
  }) {
    return '[bug][$sourceId] $feature: $kind';
  }

  /// Builds report body with technical fields only, query-free URLs/paths,
  /// and fingerprint token.
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
    final buffer = StringBuffer();
    buffer.writeln('## Summary');
    buffer.writeln('- Source: `$sourceId`');
    buffer.writeln('- Feature: `$feature`');
    buffer.writeln('- Kind: `$kind`');
    if (statusCode != null) {
      buffer.writeln('- Status: `HTTP $statusCode`');
    }
    buffer.writeln('- Config version: `${_safeValue(configVersion)}`');
    buffer.writeln('- App version: `${_safeValue(appVersion)}`');
    buffer.writeln('- Fingerprint: `$fingerprint`');

    final cleanTemplate = _cleanPathOrUrl(templatePath);
    final cleanUrlPath = _cleanPathOrUrl(urlPath);
    final cleanMessage = _cleanMessage(message);

    if (cleanTemplate.isNotEmpty ||
        cleanUrlPath.isNotEmpty ||
        cleanMessage.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Technical context');
      if (cleanTemplate.isNotEmpty) {
        buffer.writeln('- Template/path: `$cleanTemplate`');
      }
      if (cleanUrlPath.isNotEmpty) {
        buffer.writeln('- URL path: `$cleanUrlPath`');
      }
      if (cleanMessage.isNotEmpty) {
        buffer.writeln('- Message: $cleanMessage');
      }
    }

    buffer.writeln();
    buffer.writeln('<!-- kuron-anomaly: $fingerprint -->');
    return buffer.toString().trim();
  }

  /// Builds a prefilled GitHub new-issue URL.
  ///
  /// [repo] must be the repository name (e.g. kuron-mobile) or owner/repo.
  /// Body is sanitized (query params stripped) and fingerprint token is
  /// ensured when [fingerprint] is provided.
  static Uri buildPrefilledUrl({
    required String repo,
    required String title,
    required String body,
    String? fingerprint,
  }) {
    final ownerRepo = repo.contains('/') ? repo : '$_owner/$repo';
    var sanitizedBody = stripQueryParamsFromUrls(body);
    if (fingerprint != null && fingerprint.isNotEmpty) {
      final token = '<!-- kuron-anomaly: $fingerprint -->';
      if (!sanitizedBody.contains(token)) {
        sanitizedBody = sanitizedBody.trimRight();
        sanitizedBody =
            sanitizedBody.isEmpty ? token : '$sanitizedBody\n\n$token';
      }
    }
    return Uri.https(
      'github.com',
      '/$ownerRepo/issues/new',
      <String, String>{
        'title': title,
        'body': sanitizedBody,
      },
    );
  }

  /// Strips query params and fragments from all URLs found in [text].
  /// Keeps scheme/host/path only for absolute URLs; relative paths unchanged.
  static String stripQueryParamsFromUrls(String text) {
    final urlPattern = RegExp(r'https?://[^\s)>\]"''`]+');
    return text.replaceAllMapped(urlPattern, (match) {
      final raw = match.group(0)!;
      final trimmed = _trimTrailingPunctuation(raw);
      final urlPart = trimmed.value;
      try {
        final uri = Uri.parse(urlPart);
        final clean = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
        ).toString();
        return '$clean${trimmed.trailing}';
      } catch (_) {
        return raw;
      }
    });
  }

  static String _cleanPathOrUrl(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final trimmed = value.trim();
    final stripped = stripQueryParamsFromUrls(trimmed);
    try {
      final uri = Uri.parse(stripped);
      if (uri.hasScheme || uri.hasAuthority) {
        return uri.path.isEmpty ? '/' : uri.path;
      }
    } catch (_) {
      // fall through
    }
    final q = stripped.indexOf('?');
    final h = stripped.indexOf('#');
    var end = stripped.length;
    if (q >= 0 && q < end) end = q;
    if (h >= 0 && h < end) end = h;
    return stripped.substring(0, end);
  }

  static String _cleanMessage(String? message) {
    if (message == null || message.trim().isEmpty) return '';
    return stripQueryParamsFromUrls(message.trim());
  }

  static String _safeValue(String? value) {
    if (value == null || value.trim().isEmpty) return 'unknown';
    return value.trim();
  }

  static _Trimmed _trimTrailingPunctuation(String value) {
    var end = value.length;
    const trailing = {'.', ',', ';', ':', '!', '?'};
    while (end > 0 && trailing.contains(value[end - 1])) {
      end--;
    }
    return _Trimmed(value.substring(0, end), value.substring(end));
  }
}

class _Trimmed {
  const _Trimmed(this.value, this.trailing);
  final String value;
  final String trailing;
}
