// Hunt for hidden JSON API endpoints behind an HTML site.
//
// The generator prefers a working JSON API over scraper selectors: an API
// response is stable ("tidak ribet") while CSS selectors rot on every theme
// change. This hunter runs on sites that already passed the clean-probe gate
// (HTTP 200, no Cloudflare/WAF) and reports the first usable endpoint — the
// caller then builds a `rest_json` config from it as the patokan.
library;

import 'api_detector.dart';
import 'http_probe.dart';

// Where a hunted endpoint came from.
enum ApiEndpointKind {
  // WordPress REST index (`/wp-json/` exposes the `wp/v2` namespace).
  wpRest,
  // Well-known generic path (`/api/`, `/api/v1/`).
  genericJson,
  // Next.js data endpoint derived from `__NEXT_DATA__` buildId.
  nextData,
  // `/api/...` URL literal found inside the page's own scripts.
  scriptApi,
}

// A usable JSON endpoint found by [huntApiEndpoints].
class ApiHuntHit {
  ApiHuntHit({
    required this.endpointUrl,
    required this.kind,
    required this.inference,
    required this.tried,
  });

  final String endpointUrl;
  final ApiEndpointKind kind;
  final ApiInference inference;

  // Every candidate URL probed (for transparent logging).
  final List<String> tried;
}

// Minimum [ApiInference.confidence] for a generic JSON hit to be usable.
const double kApiHuntConfidenceThreshold = 0.5;

// Max `/api/...` literals lifted from page scripts (page scripts can contain
// dozens of irrelevant API paths; only the first few are worth probing).
const int kMaxScriptApiCandidates = 3;

// Well-known index endpoints, probed only when the page gives no better hint.
const List<String> kGenericApiCandidates = <String>[
  '/api/',
  '/api/v1/',
];

// WordPress REST index endpoints, probed when the HTML smells like WP.
const List<String> kWpApiCandidates = <String>[
  '/wp-json/',
  '/wp-json/wp/v2/types',
];

bool _isUsableJson(ProbeResult r) =>
    r.statusCode == 200 && !r.isBlocked && r.jsonBody != null;

// A `/wp-json/` index is a Map of namespaces, which [inferApi] scores low —
// but the `wp/v2` namespace itself is proof of a usable REST API.
ApiInference? _asWpRest(String endpointUrl, dynamic json) {
  if (json is! Map) return null;
  final namespaces = json['namespaces'];
  if (namespaces is List &&
      namespaces.any((n) => n.toString().contains('wp/v2'))) {
    final uri = Uri.tryParse(endpointUrl);
    final origin =
        '${uri?.scheme}://${uri?.host}${uri?.port == 80 || uri?.port == 443 ? '' : ':${uri?.port}'}';
    return ApiInference(
      baseUrl: '$origin/wp-json/wp/v2',
      hasList: true,
      listEndpoint: '/wp-json/wp/v2/search',
      queryParam: 'search',
      listItemsPath: '',
      confidence: 0.65,
    );
  }
  return null;
}

// Lift `/api/...` URL literals out of inline page scripts, e.g.
// `fetch("/api/parse-chapter")`. Returns site-absolute paths.
List<String> scriptApiCandidates(String htmlBody) {
  final found = <String>[];
  final re = RegExp(
    r'''(?:fetch\s*\(\s*|axios\.[a-z]+\s*\(\s*|url\s*"\s*:\s*")["'](/api/[^"'\s?#]+)''',
  );
  for (final m in re.allMatches(htmlBody)) {
    final path = m.group(1)!;
    if (!found.contains(path)) found.add(path);
    if (found.length >= kMaxScriptApiCandidates) break;
  }
  return found;
}

String? _nextBuildId(String htmlBody) {
  if (!htmlBody.contains('__NEXT_DATA__')) return null;
  final m =
      RegExp(r'"buildId"\s*:\s*"([^"]+)"').firstMatch(htmlBody);
  return m?.group(1);
}

bool _looksLikeWordPress(String htmlBody) {
  final lower = htmlBody.toLowerCase();
  return lower.contains('wp-content/') ||
      lower.contains('wp-json') ||
      lower.contains('wp-includes/') ||
      RegExp(r'<meta[^>]+name="generator"[^>]+wordpress')
          .hasMatch(lower);
}

String _originOf(Uri base) =>
    '${base.scheme}://${base.host}${base.port == 80 || base.port == 443 ? '' : ':${base.port}'}';

// Probe [url] and return the inference when the response is usable JSON.
Future<({ApiInference inference, bool wpRest})?> _tryCandidate(
  String url,
  Future<ProbeResult> Function(String url) fetch,
) async {
  late final ProbeResult res;
  try {
    res = await fetch(url);
  } catch (_) {
    return null;
  }
  if (!_isUsableJson(res)) return null;
  final json = res.jsonBody;
  final wp = _asWpRest(url, json);
  if (wp != null) return (inference: wp, wpRest: true);
  final inference = inferApi(url, json);
  if (inference.confidence >= kApiHuntConfidenceThreshold) {
    return (inference: inference, wpRest: false);
  }
  return null;
}

// Hunt for a usable JSON API behind [base]'s HTML shell.
//
// Order: page-script `/api/...` hints → Next.js `/_next/data` → WordPress
// REST (only when the HTML smells like WP) → generic `/api/` fallbacks.
// Returns the first hit, or null when the site is scraper-only.
Future<ApiHuntHit?> huntApiEndpoints({
  required Uri base,
  required String htmlBody,
  Future<ProbeResult> Function(String url)? fetch,
}) async {
  final doFetch = fetch ?? probeUrl;
  final origin = _originOf(base);
  final tried = <String>[];

  Future<ApiHuntHit?> attempt(String path, ApiEndpointKind kind) async {
    final url = '$origin$path';
    tried.add(url);
    final got = await _tryCandidate(url, doFetch);
    if (got == null) return null;
    return ApiHuntHit(
      endpointUrl: url,
      kind: kind,
      inference: got.inference,
      tried: List.of(tried),
    );
  }

  for (final path in scriptApiCandidates(htmlBody)) {
    final hit = await attempt(path, ApiEndpointKind.scriptApi);
    if (hit != null) return hit;
  }

  final buildId = _nextBuildId(htmlBody);
  if (buildId != null) {
    final hit = await attempt(
      '/_next/data/$buildId/index.json',
      ApiEndpointKind.nextData,
    );
    if (hit != null) return hit;
  }

  if (_looksLikeWordPress(htmlBody)) {
    for (final path in kWpApiCandidates) {
      final hit = await attempt(path, ApiEndpointKind.wpRest);
      if (hit != null) return hit;
    }
  }

  for (final path in kGenericApiCandidates) {
    final hit = await attempt(path, ApiEndpointKind.genericJson);
    if (hit != null) return hit;
  }

  return null;
}
