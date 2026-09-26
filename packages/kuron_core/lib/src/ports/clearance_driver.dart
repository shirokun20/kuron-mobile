// Platform port for challenge clearance solving.
//
// Lives in kuron_core so pure-Dart packages can orchestrate clearance
// (caching, persistence, retry) without importing Flutter-only plugins.
// The production implementation drives a native WebView and lives in
// kuron_special; tests use fakes.
library;

/// Solved clearance data (plain DTOs — no platform handles).
class ClearanceSolution {
  const ClearanceSolution({
    required this.token,
    this.userAgent,
    this.cookies,
  });

  final String token;
  final String? userAgent;
  final String? cookies;
}

/// Solves a site challenge (e.g. Cloudflare) in exchange for clearance data.
abstract class ClearanceDriver {
  Future<ClearanceSolution?> solve(String domainUrl);
}
