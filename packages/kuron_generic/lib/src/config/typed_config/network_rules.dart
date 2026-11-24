// Typed network/header/referer rules for a Source Config.
///
// Parsed from the `network` block of a raw config JSON by
// `SourceConfigParser`. Handles both the canonical `requiresBypass` field
// and the legacy `cloudflare.bypassEnabled` field, emitting diagnostics
// when both are present or when the fields are inconsistent.
library;

import 'package:equatable/equatable.dart';
import 'package:kuron_core/kuron_core.dart';

// Rate-limiting declaration inside a Source Config `network.rateLimit` block.
class RateLimitRules extends Equatable {
  const RateLimitRules({
    this.requestsPerSecond,
    this.maxConcurrentRequests,
  });

  final double? requestsPerSecond;
  final int? maxConcurrentRequests;

  factory RateLimitRules.fromMap(Map<String, Object?> map) {
    return RateLimitRules(
      requestsPerSecond: switch (map['requestsPerSecond']) {
        final num n => n.toDouble(),
        _ => null,
      },
      maxConcurrentRequests: switch (map['maxConcurrentRequests']) {
        final int i => i,
        final num n => n.toInt(),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (requestsPerSecond != null) 'requestsPerSecond': requestsPerSecond,
        if (maxConcurrentRequests != null)
          'maxConcurrentRequests': maxConcurrentRequests,
      };

  @override
  List<Object?> get props =>
      <Object?>[requestsPerSecond, maxConcurrentRequests];
}

// Typed representation of the `network` block in a Source Config.
class NetworkRules extends Equatable {
  NetworkRules({
    required this.requiresBypass,
    required this.cloudflareBypass,
    this.antiDetection = false,
    Map<String, String>? staticHeaders,
    this.rateLimit,
    this.exBaseUrl,
    this.diagnostics = const <ValidationDiagnostic>[],
  }) : staticHeaders = Map<String, String>.unmodifiable(
            staticHeaders ?? const <String, String>{});

  // Merged bypass flag — true when either `network.requiresBypass` or
  // `network.cloudflare.bypassEnabled` is true in the config.
  final bool requiresBypass;

  // Whether the config explicitly declared a `cloudflare` bypass block.
  final bool cloudflareBypass;

  // Whether the config declares `network.cloudflare.antiDetection`.
  // Parsed for contract consistency; engine wiring stays with the
  // per-source bypass/clearance drivers.
  final bool antiDetection;

  // Static headers declared under `network.headers`.
  final Map<String, String> staticHeaders;

  // Rate-limit rules if `network.rateLimit` is declared.
  final RateLimitRules? rateLimit;

  // Secondary base URL (e.g. `auth.preferExhentai` exBaseUrl). Optional.
  final String? exBaseUrl;

  // Diagnostics produced while parsing the `network` block.
  final List<ValidationDiagnostic> diagnostics;

  // Required engine primitives implied by these network rules.
  Set<String> get impliedPrimitives => <String>{
        if (requiresBypass) EnginePrimitive.networkRequiresBypass,
        if (rateLimit != null) EnginePrimitive.networkRateLimit,
        if (staticHeaders.isNotEmpty) EnginePrimitive.headersStatic,
      };

  // Parses a raw `network` block and the optional top-level `auth` block
  // (for `exBaseUrl`), returning a [NetworkRules] with any diagnostics.
  factory NetworkRules.fromConfig(Map<String, Object?> rawConfig) {
    final Object? networkRaw = rawConfig['network'];
    final Map<String, Object?> network = networkRaw is Map
        ? networkRaw.cast<String, Object?>()
        : const <String, Object?>{};

    final List<ValidationDiagnostic> diags = <ValidationDiagnostic>[];

    final bool requiresBypassField =
        network['requiresBypass'] as bool? ?? false;
    final Object? cfRaw = network['cloudflare'];
    final Map<String, Object?> cf = cfRaw is Map
        ? cfRaw.cast<String, Object?>()
        : const <String, Object?>{};
    final bool cloudflareBypassField = cf['bypassEnabled'] as bool? ?? false;
    final bool antiDetectionField = cf['antiDetection'] as bool? ?? false;

    // Emit a diagnostic when the plural bypass fields are both present and
    // consistent — this is a v1 schema issue where they should be unified.
    if (requiresBypassField && cloudflareBypassField) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'bypassFieldPlural',
        message:
            'Both network.requiresBypass and network.cloudflare.bypassEnabled '
            'are true. Prefer network.requiresBypass only in v2 configs.',
        path: 'network',
      ));
    }

    // Parse static headers.
    final Object? headersRaw = network['headers'];
    final Map<String, String> headers = headersRaw is Map
        ? headersRaw.cast<Object, Object?>().map<String, String>(
            (Object k, Object? v) =>
                MapEntry<String, String>(k.toString(), v?.toString() ?? ''))
        : const <String, String>{};

    // Parse rate-limit.
    final Object? rlRaw = network['rateLimit'];
    final RateLimitRules? rateLimit = rlRaw is Map
        ? RateLimitRules.fromMap(rlRaw.cast<String, Object?>())
        : null;

    // Extract exBaseUrl from `network` or from `auth` block (e-hentai pattern).
    final Object? networkExBase = network['exBaseUrl'];
    final Object? authRaw = rawConfig['auth'];
    final Object? authExBase =
        authRaw is Map ? (authRaw.cast<String, Object?>())['exBaseUrl'] : null;
    final String? exBaseUrl = (networkExBase ?? authExBase)?.toString();

    return NetworkRules(
      requiresBypass: requiresBypassField || cloudflareBypassField,
      cloudflareBypass: cloudflareBypassField,
      antiDetection: antiDetectionField,
      staticHeaders: headers,
      rateLimit: rateLimit,
      exBaseUrl: exBaseUrl,
      diagnostics: diags,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'requiresBypass': requiresBypass,
        'cloudflareBypass': cloudflareBypass,
        if (antiDetection) 'antiDetection': antiDetection,
        if (staticHeaders.isNotEmpty) 'staticHeaders': staticHeaders,
        if (rateLimit != null) 'rateLimit': rateLimit!.toJson(),
        if (exBaseUrl != null) 'exBaseUrl': exBaseUrl,
      };

  @override
  List<Object?> get props => <Object?>[
        requiresBypass,
        cloudflareBypass,
        antiDetection,
        staticHeaders,
        rateLimit,
        exBaseUrl,
        diagnostics,
      ];
}
