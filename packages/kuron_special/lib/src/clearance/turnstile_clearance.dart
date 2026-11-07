import 'package:dio/dio.dart';

/// Explicit-Turnstile clearance for the schale family (schale-network,
/// hdoujin).
///
/// Proven live 2026-11-07 on macOS (same machine + network where WKWebView
/// never mints and a spawned real Chrome dies in the sandbox):
/// - hdoujin single sitekey `0x4AAAAAAA4d8pRpLY09lDOq` mints a ~709-char
///   token inside the app's own WKWebView via `turnstile.render`.
/// - schale mints with the VISIBLE key `0x4AAAAAAA1gtfQl-5lpZVcM`; the
///   invisible key `0x4AAAAAABCg6jAP5NgVpyoZ` mints a token the backend
///   rejects (403), so it must NOT be used here.
/// - Exchange `POST {authHost}/clearance` with `Authorization: Bearer`
///   REQUIRES browser-like headers (UA + Origin + Referer +
///   X-Requested-With): Bearer-only gets 400, and a manual `Host` header
///   gets 403. Success is 201 with the plain-text `crt` body.
/// Sitekeys + auth hosts were read from the sites' own shipped JS bundles,
/// not guessed.
class TurnstileClearanceConfig {
  /// Page whose origin hosts the widget (hostname must match the sitekey).
  final String baseUrl;

  /// Explicit Turnstile sitekey used for the clearance widget.
  final String siteKey;

  /// Clearance minter, e.g. `https://auth.hdoujin.org`.
  final String authHost;

  const TurnstileClearanceConfig({
    required this.baseUrl,
    required this.siteKey,
    required this.authHost,
  });

  static const schale = TurnstileClearanceConfig(
    baseUrl: 'https://niyaniya.moe/',
    siteKey: '0x4AAAAAAA1gtfQl-5lpZVcM',
    authHost: 'https://auth.schale.network',
  );

  static const hdoujin = TurnstileClearanceConfig(
    baseUrl: 'https://hdoujin.org/',
    siteKey: '0x4AAAAAAA4d8pRpLY09lDOq',
    authHost: 'https://auth.hdoujin.org',
  );

  static TurnstileClearanceConfig? forDomainUrl(String domainUrl) {
    final host = Uri.tryParse(domainUrl)?.host ?? '';
    if (host.contains('niyaniya.moe') || host.contains('schale.network')) {
      return schale;
    }
    if (host.contains('hdoujin.org')) return hdoujin;
    return null;
  }

  /// Compound page script: injects the explicit Turnstile widget, stores the
  /// token at `window.__kwcrt`, and returns it when present (`''` until
  /// then, so headless/visible pollers keep waiting).
  ///
  /// Render errors are swallowed AND the widget is re-rendered every 45s
  /// without a token: schale's key answers WKWebView with a terminal
  /// "Verification failed" (while hdoujin's key passes in the same
  /// environment), and a fresh challenge can draw a different verdict —
  /// or surface the interactive checkbox for the user to tick in the
  /// visible popup. Blind time-based retry: the failure UI lives in a
  /// cross-origin iframe we cannot inspect.
  String widgetScript() => '''
(function(){
  if (window.__kwcrt) return window.__kwcrt;
  function render(){
    try {
      var old = document.getElementById('kwbox');
      if (old) old.remove();
      var d = document.createElement('div');
      d.id = 'kwbox'; document.body.appendChild(d);
      window.turnstile.render(d, {sitekey: '$siteKey', callback: function(t){ window.__kwcrt = t; }});
      window.__kwstart = Date.now();
    } catch(e){}
  }
  if (!window.__kwstarted) {
    window.__kwstarted = true;
    window.__kwload = render;
    var s = document.createElement('script');
    s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=__kwload';
    s.async = true; s.defer = true;
    document.head.appendChild(s);
    window.__kwstart = Date.now();
    return '';
  }
  if (window.turnstile && (Date.now() - window.__kwstart > 45000)) render();
  return '';
})()''';
}

/// Exchanges a Turnstile token for the API `crt`.
///
/// Returns the trimmed `crt` body on HTTP 200/201, `null` otherwise
/// (never throws: every failure means "fall through to the next step").
class TurnstileClearanceExchange {
  static Future<String?> exchange({
    required Dio dio,
    required TurnstileClearanceConfig config,
    required String turnstileToken,
    String? userAgent,
  }) async {
    try {
      final origin = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      final res = await dio.post<String>(
        '${config.authHost}/clearance',
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $turnstileToken',
            if (userAgent != null && userAgent.isNotEmpty)
              'User-Agent': userAgent,
            'Origin': origin,
            'Referer': config.baseUrl,
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.plain,
        ),
      );
      final crt = (res.data ?? '').trim();
      if ((res.statusCode == 200 || res.statusCode == 201) && crt.isNotEmpty) {
        return crt;
      }
    } catch (_) {
      // Fall through: caller tries the next step (visible popup).
    }
    return null;
  }
}
