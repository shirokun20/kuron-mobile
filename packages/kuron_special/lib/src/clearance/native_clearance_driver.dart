import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

import 'turnstile_clearance.dart';

// Production [ClearanceDriver]: solves challenges through the native
// WebView (headless first, visible fallback). The orchestration
// (caching, persistence, retry) lives in kuron_generic's ClearanceService.
class NativeClearanceDriver implements ClearanceDriver {
  /// Optional step logging (turnstile attempt + outcome). Null = silent.
  final Logger? logger;

  /// HTTP client for the `auth.<domain>/clearance` exchange. Injected in
  /// tests; defaults to a plain client in production.
  final Dio? dio;

  const NativeClearanceDriver({this.logger, this.dio});

  /// Desktop Chrome identity, macOS only.
  ///
  /// The schale-family token minter gates its Turnstile on automation/UA
  /// signals, and the harvested UA is replayed on subsequent API calls, so
  /// WebView and Dio must present one coherent identity. Android keeps its
  /// default (genuine Chromium WebView UA — proven working); macOS
  /// WKWebView defaults to Safari, which the minter stalls on (endless
  /// loader, token never minted on the same network where Chromium passes).
  static const String _macOsChromeUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  static String? _clearanceUserAgent() =>
      Platform.isMacOS ? _macOsChromeUserAgent : null;

  /// Headless results vary by platform build (`String` vs `List` cookies);
  /// normalize defensively so a shape mismatch can never crash the solve
  /// (seen live on macOS: `List<Object?> is not String?` at this cast,
  /// which killed the solve before the visible fallback could run).
  static String? _cookiesToHeader(Object? cookies) {
    if (cookies is List) {
      final parts = cookies
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty);
      final joined = parts.join('; ');
      return joined.isEmpty ? null : joined;
    }
    if (cookies is String) return cookies.isEmpty ? null : cookies;
    return cookies?.toString();
  }

  /// Explicit-Turnstile step of the chain (schale family only).
  ///
  /// Mints a Turnstile token with the site's own explicit widget inside the
  /// app WebView, then exchanges it for the API `crt` at
  /// `auth.<domain>/clearance`. Returns null on any failure so the visible
  /// popup runs next. Never throws.
  ///
  /// The mint runs with the HONEST WebView UA (null = platform Safari
  /// default): presenting a desktop-Chrome UA over Safari TLS is a classic
  /// inconsistency signal, and schale's strict key answers the spoofed
  /// popup with a visible "Verification failed". The exchange and cached
  /// API identity keep the proven desktop-Chrome UA (the token itself is
  /// not UA-bound).
  Future<ClearanceSolution?> _solveViaTurnstile(String domainUrl) async {
    final config = TurnstileClearanceConfig.forDomainUrl(domainUrl);
    if (config == null) return null;
    logger?.i('[Turnstile] minting via explicit widget (${config.authHost})');
    String? raw;
    try {
      raw = await KuronNative.instance.headlessGetClearance(
        url: config.baseUrl,
        script: config.widgetScript(),
        timeoutMs: 60000,
      );
    } catch (e) {
      logger?.w('[Turnstile] mint failed: $e');
    }
    final token = raw?.replaceAll('"', '');
    if (token == null || token.isEmpty || token == 'null') {
      logger?.w('[Turnstile] no token minted headlessly');
      return null;
    }
    final crt = await TurnstileClearanceExchange.exchange(
      dio: dio ?? Dio(),
      config: config,
      turnstileToken: token,
      userAgent: _clearanceUserAgent(),
    );
    if (crt == null || crt.isEmpty) {
      logger?.w('[Turnstile] exchange failed');
      return null;
    }
    logger?.i('[Turnstile] solved, crt len=${crt.length}');
    // Replay the proven desktop-Chrome identity on macOS so the API calls
    // present the same identity the exchange accepted. Elsewhere (Android)
    // the native WebView UA keeps working, so leave it untouched (null).
    return ClearanceSolution(
      token: crt,
      userAgent: _clearanceUserAgent(),
      cookies: null,
    );
  }

  @override
  Future<ClearanceSolution?> solve(String domainUrl) async {
    final result = await KuronNative.instance.getHeadlessClearance(
      url: domainUrl,
      userAgent: _clearanceUserAgent(),
    );

    if (result != null) {
      final crt = result['token'] as String?;
      if (crt != null && crt.isNotEmpty) {
        return ClearanceSolution(
          token: crt,
          userAgent: result['userAgent'] as String?,
          cookies: _cookiesToHeader(result['cookies']),
        );
      }
    }

    // Explicit Turnstile widget (schale family): mints inside the app WebView
    // where the site's managed challenge never completes.
    final turnstile = await _solveViaTurnstile(domainUrl);
    if (turnstile != null) return turnstile;

    // Visible popup: for the schale family it carries the same widget script,
    // so the user can tick the checkbox when the headless mint needs
    // interaction; otherwise the legacy localStorage probe is used.
    // The widget popup uses the honest WebView UA (see above); the legacy
    // popup keeps the previous behavior.
    final config = TurnstileClearanceConfig.forDomainUrl(domainUrl);
    final fallbackResult = await KuronNative.instance.showLoginWebView(
      url: domainUrl,
      userAgent: config != null ? null : _clearanceUserAgent(),
      pageFinishedScript:
          config?.widgetScript() ?? "window.localStorage.getItem('clearance')",
    );

    if (fallbackResult != null) {
      final scriptResult =
          fallbackResult['pageFinishedScriptResult'] as String?;
      final userAgent = fallbackResult['userAgent'] as String?;

      String? cookies;
      final cookiesData = fallbackResult['cookies'];
      if (cookiesData is List) {
        cookies = cookiesData.join('; ');
      } else if (cookiesData is String) {
        cookies = cookiesData;
      }

      // the script result might be wrapped in quotes
      final raw = scriptResult?.replaceAll('"', '');
      if (raw == null || raw == 'null' || raw.isEmpty) return null;
      if (config == null) {
        return ClearanceSolution(
          token: raw,
          userAgent: userAgent,
          cookies: cookies,
        );
      }
      final crt = await TurnstileClearanceExchange.exchange(
        dio: dio ?? Dio(),
        config: config,
        turnstileToken: raw,
        userAgent: _clearanceUserAgent(),
      );
      if (crt == null || crt.isEmpty) return null;
      return ClearanceSolution(
        token: crt,
        userAgent: _clearanceUserAgent(),
        cookies: null,
      );
    }

    return null;
  }
}
