import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:kuron_native/kuron_native.dart';

// Configuration for the WebView session (parsed from JSON)
class WebViewSessionConfig {
  final bool bypassEnabled;
  final bool authEnabled;
  final String loginUrl;
  final String registerUrl;
  final String bookmarkVerifyUrl;
  final String cookieVerifyKey;
  final String nonceRegex;
  final String loginSuccessFilter;
  final String autoCloseOnCookie;

  const WebViewSessionConfig({
    this.bypassEnabled = false,
    this.authEnabled = false,
    this.loginUrl = '',
    this.registerUrl = '',
    this.bookmarkVerifyUrl = '',
    this.cookieVerifyKey = '',
    this.nonceRegex = '',
    this.loginSuccessFilter = '',
    this.autoCloseOnCookie = '',
  });

  factory WebViewSessionConfig.fromJson(Map<String, dynamic> json) {
    final network = json['network'] as Map<String, dynamic>? ?? {};
    final cf = network['cloudflare'] as Map<String, dynamic>? ?? {};
    final siteProtection =
        network['siteProtection'] as Map<String, dynamic>? ?? {};
    final auth = json['auth'] as Map<String, dynamic>? ?? {};
    final requiresBypass = network['requiresBypass'] == true;
    final cloudflareBypass = cf['bypassEnabled'] == true;
    final bypassEnabled = requiresBypass || cloudflareBypass;

    return WebViewSessionConfig(
      bypassEnabled: bypassEnabled,
      authEnabled: auth['enabled'] == true,
      loginUrl: (auth['loginUrl'] as String?) ?? '',
      registerUrl: (auth['registerUrl'] as String?) ?? '',
      bookmarkVerifyUrl: (auth['bookmarkUrl'] as String?) ?? '',
      cookieVerifyKey: (auth['cookieVerifyKey'] as String?) ?? '',
      nonceRegex: (auth['nonceRegex'] as String?) ?? '',
      loginSuccessFilter: (auth['loginSuccessFilter'] as String?) ?? '',
      autoCloseOnCookie:
          (siteProtection['autoCloseOnCookie'] as String?)?.trim() ??
          (cf['autoCloseOnCookie'] as String?)?.trim() ??
          (bypassEnabled ? 'cf_clearance' : ''),
    );
  }
}

typedef WebViewBypassOptionsBuilder = WebViewBypassOptions Function(
  String targetUrl,
  WebViewSessionConfig config,
);

class WebViewBypassOptions {
  const WebViewBypassOptions({
    this.autoCloseOnCookie,
    this.captureRequestPatterns,
    this.allowRequestPatterns,
    this.pageFinishedScript,
    this.blockNetworkImages = false,
    this.clearCookies = true,
    this.preferCapturedHtml = false,
    this.preferCapturedImageUrls = false,
    this.skipInitialRequest = false,
  });

  final String? autoCloseOnCookie;
  final List<String>? captureRequestPatterns;
  final List<String>? allowRequestPatterns;
  final String? pageFinishedScript;
  final bool blockNetworkImages;
  final bool clearCookies;
  final bool preferCapturedHtml;
  final bool preferCapturedImageUrls;
  final bool skipInitialRequest;
}

WebViewBypassOptions _defaultBypassOptionsBuilder(
  String targetUrl,
  WebViewSessionConfig config,
) {
  return WebViewBypassOptions(
    autoCloseOnCookie: config.autoCloseOnCookie.isEmpty
        ? null
        : config.autoCloseOnCookie,
  );
}

// Result of an authentication attempt
class WebViewAuthResult {
  final bool success;
  final String? errorMessage;
  final String? username;

  const WebViewAuthResult._({
    required this.success,
    this.errorMessage,
    this.username,
  });

  factory WebViewAuthResult.success(String username) =>
      WebViewAuthResult._(success: true, username: username);

  factory WebViewAuthResult.failure(String message) =>
      WebViewAuthResult._(success: false, errorMessage: message);
}

// State of authentication
enum WebViewAuthState { notLoggedIn, loggingIn, loggedIn, error }

// An adapter that orchestrates Cloudflare bypass and authentication
// through a shared Dio instance and CookieJar.
class WebViewSessionAdapter {
  final Dio _dio;
  final PersistCookieJar _cookieJar;
  final FlutterSecureStorage _secureStorage;
  final Logger _logger;
  final WebViewSessionConfig _config;
  final String _baseUrl;
  final KuronNative _native;
  final WebViewBypassOptionsBuilder _bypassOptionsBuilder;

  WebViewAuthState _authState = WebViewAuthState.notLoggedIn;
  String? _username;
  String? _email;
  // Per-URL bypass latch: concurrent requests to the same URL wait, other
  // URLs bypass independently (no cross-source blocking).
  final Set<String> _bypassingUrls = {};

  // Sync cache for bypass cookies per baseUrl host — used by GenericHttpSource
  // to add Cookie header to image requests without async.
  static final Map<String, String> _cachedCookieHeaders =
      _CappedMap<String, String>(50);
  static final Map<String, String> _cachedUserAgents =
      _CappedMap<String, String>(50);

  /// Matches [url] against a sync header cache keyed by base URL or host.
  ///
  /// Exact host wins; a subdomain request (e.g. `cdn5.ravenscans.org`)
  /// inherits the entry seeded for its parent (`ravenscans.org`) since the
  /// clearance cookie's domain covers subdomains. Suffix-anchored, so
  /// lookalikes (`notravenscans.org`, `ravenscans.org.evil.com`) never match.
  @visibleForTesting
  static String? matchCachedHost(Map<String, String> cache, String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return null;
    String? parentFallback;
    for (final entry in cache.entries) {
      final rawKey = entry.key;
      if (rawKey.isEmpty) continue;
      final keyHost = Uri.tryParse(rawKey)?.host ?? rawKey;
      if (keyHost.isEmpty) continue;
      if (keyHost == host) return entry.value;
      if (host.endsWith('.$keyHost')) return entry.value;
      parentFallback ??= keyHost.endsWith('.$host') ? entry.value : null;
    }
    return parentFallback;
  }

  static String? getCachedCookieHeaderForUrl(String url) {
    try {
      return matchCachedHost(_cachedCookieHeaders, url);
    } catch (_) {
      return null;
    }
  }

  static String? getCachedUserAgentForUrl(String url) {
    try {
      return matchCachedHost(_cachedUserAgents, url);
    } catch (_) {
      return null;
    }
  }

  // Secure storage keys
  static const _keyPrefix = 'kuron_special_auth_';
  String get _keyEmail => '$_keyPrefix${_baseUrl.hashCode}_email';

  /// cf_clearance is bound to the User-Agent that solved the challenge.
  /// Persisting the WebView UA lets post-restart probes reuse the clearance
  /// instead of re-triggering the challenge every cold session.
  String get _uaKey => '$_keyPrefix${_baseUrl.hashCode}_ua';

  WebViewSessionAdapter({
    required this._dio,
    required this._cookieJar,
    required this._config,
    required this._baseUrl,
    FlutterSecureStorage? secureStorage,
    KuronNative? native,
    Logger? logger,
    WebViewBypassOptionsBuilder? bypassOptionsBuilder,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _native = native ?? KuronNative.instance,
       _logger = logger ?? Logger(),
       _bypassOptionsBuilder =
           bypassOptionsBuilder ?? _defaultBypassOptionsBuilder {
    // Avoid stacking duplicate cookie interceptors when adapter is recreated.
    final hasCookieManager = _dio.interceptors
        .whereType<CookieManager>()
        .isNotEmpty;
    if (!hasCookieManager) {
      _dio.interceptors.add(CookieManager(_cookieJar));
    }
  }

  // ============ Getters ============

  WebViewAuthState get authState => _authState;
  bool get isLoggedIn => _authState == WebViewAuthState.loggedIn;
  String? get username => _username;
  String? get email => _email;
  String get registerUrl => _config.registerUrl;
  String get baseUrl => _baseUrl;

  Future<Map<String, String>> getCookiesForDomain(String url) async {
    try {
      final uri = Uri.parse(url.isEmpty ? _baseUrl : url);
      final cookies = await _cookieJar.loadForRequest(uri);

      if (cookies.isEmpty) return {};

      return Map.fromEntries(
        cookies.map((cookie) => MapEntry(cookie.name, cookie.value)),
      );
    } catch (e) {
      _logger.e('Failed to get cookies: $e');
      return {};
    }
  }

  // ============ Cloudflare Bypass ============

  // Returns true if the HTML response looks like a Cloudflare challenge.
  bool isCloudflareChallenge(String html) {
    final indicators = [
      'Checking your browser',
      'cf-challenge-form',
      'challenge-platform',
      '__cf_chl_',
      'cf-mitigated',
      'Ray ID:',
      '<title>Just a moment...</title>',
      '<title>Attention Required! | Cloudflare</title>',
      '<div id="cf-please-wait">',
    ];

    final lowerHtml = html.toLowerCase();
    return indicators.any(
      (indicator) => lowerHtml.contains(indicator.toLowerCase()),
    );
  }

  @visibleForTesting
  bool shouldTriggerBypass(Response<dynamic>? response) {
    if (response == null) return false;

    final statusCode = response.statusCode ?? 0;
    if (statusCode == 403) {
      return response.headers.value('cf-mitigated') != null ||
          (response.data is String &&
              isCloudflareChallenge(response.data as String));
    }

    if (statusCode < 300 || statusCode >= 400) {
      return false;
    }

    final location = response.headers.value('location')?.trim();
    if (location != null && location.isNotEmpty) {
      return false;
    }

    final server = response.headers.value('server')?.toLowerCase() ?? '';
    return server.contains('sucuri') ||
        server.contains('cloudproxy') ||
        (response.headers.value('x-sucuri-id')?.isNotEmpty ?? false);
  }

  // Execute a GET request, automatically handling Cloudflare bypass if encountered.
  Future<Response<T>> requestWithBypass<T>(
    String url, {
    Options? options,
  }) async {
    final bypassOptions = _bypassOptionsBuilder(url, _config);
    try {
      options ??= Options();
      options.headers ??= {};

      // Resolve the UA for this request. Priority: cached bypass UA >
      // persisted bypass UA > caller/config UA. cf_clearance is UA-bound
      // (live-proven: clearance + mismatched UA = 403), so once a WebView UA
      // exists it MUST win over any config UA for this host — otherwise every
      // request voids the clearance and re-triggers the challenge. Never fall
      // back to the shared Dio default (app identity UA).
      var requestUa = _cachedUserAgents[_baseUrl];
      try {
        requestUa ??= _cachedUserAgents[Uri.tryParse(url)?.host ?? ''];
      } catch (_) {}
      if (requestUa == null || requestUa.isEmpty) {
        final persistedUa = await _secureStorage
            .read(key: _uaKey)
            .catchError((_) => null);
        if (persistedUa != null && persistedUa.isNotEmpty) {
          requestUa = persistedUa;
        }
      }
      if (requestUa == null || requestUa.isEmpty) {
        requestUa =
            (options.headers?['User-Agent'] as String?)?.trim().isNotEmpty ==
                true
            ? options.headers!['User-Agent'] as String
            : null;
      }
      if (requestUa != null && requestUa.isNotEmpty) {
        options.headers?['User-Agent'] = requestUa;
        _cachedUserAgents[_baseUrl] = requestUa;
        try {
          _cachedUserAgents[Uri.parse(_baseUrl).host] = requestUa;
        } catch (_) {}
      }

      if (_config.bypassEnabled && bypassOptions.skipInitialRequest) {
        final bypassResponse = await _attemptNativeBypassAndVerify<T>(
          targetUrl: url,
          options: options,
          bypassOptions: bypassOptions,
        );
        if (bypassResponse != null) {
          _logger.i('✅ Site protection bypassed without initial probe.');
          return bypassResponse;
        }
      }

      // 1. First attempt — through this adapter's own jar, so a previously
      // minted clearance is attached (shared Dio would send another source's
      // jar and re-trigger the challenge on every call).
      final response = await _jarClient().get<T>(url, options: options);
      if (!shouldTriggerBypass(response) || !_config.bypassEnabled) {
        unawaited(_seedImageHeaderCache(url));
        return response;
      }

      _logger.w(
        '🔒 Site protection challenge detected for: $url (${response.statusCode})',
      );

      final bypassResponse = await _attemptNativeBypassAndVerify<T>(
        targetUrl: url,
        options: options,
        bypassOptions: bypassOptions,
      );
      if (bypassResponse == null) {
        _logger.e('❌ Site protection bypass failed completely.');
        throw DioException.badResponse(
          statusCode: response.statusCode ?? 0,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      _logger.i('✅ Site protection bypassed. Using verified response.');
      unawaited(_seedImageHeaderCache(url));
      return bypassResponse;
    } on DioException catch (e) {
      if (!shouldTriggerBypass(e.response) || !_config.bypassEnabled) {
        rethrow;
      }

      _logger.w(
        '🔒 Site protection challenge detected for: $url (${e.response?.statusCode})',
      );
      // An in-flight bypass for the same URL is already solving: wait for it
      // (Turnstile takes ~10-20s; a fixed 5s retry would 403 and spam a new
      // WebView per concurrent caller) then do a single jar-scoped attempt.
      if (_bypassingUrls.contains(url)) {
        _logger.w(
          'Already bypassing $url, waiting for the in-flight bypass...',
        );
        for (var i = 0; i < 15 && _bypassingUrls.contains(url); i++) {
          await Future.delayed(const Duration(seconds: 2));
        }
        return await _jarClient().get<T>(url, options: options);
      }

      // 3. Launch UI Bypass and use verified response directly.
      final bypassResponse = await _attemptNativeBypassAndVerify<T>(
        targetUrl: url,
        options: options,
        bypassOptions: bypassOptions,
      );
      if (bypassResponse == null) {
        _logger.e('❌ Cloudflare bypass failed completely.');
        rethrow;
      }

      _logger.i('✅ Cloudflare bypassed. Using verified response.');
      unawaited(_seedImageHeaderCache(url));
      return bypassResponse;
    }
  }

  Future<Response<T>?> _attemptNativeBypassAndVerify<T>({
    required String targetUrl,
    Options? options,
    WebViewBypassOptions? bypassOptions,
  }) async {
    _bypassingUrls.add(targetUrl);
    try {
      _logger.i('🚀 Launching Native WebView for CF Bypass...');

      // 1. Clear old cookies to ensure fresh start
      final uri = Uri.parse(targetUrl);
      await _cookieJar.delete(uri);

      bypassOptions ??= _bypassOptionsBuilder(targetUrl, _config);

      // 2. Launch Native WebView
      final result = await _native.showLoginWebView(
        url: targetUrl,
        successUrlFilters: [],
        initialCookie: null,
        userAgent: null,
        autoCloseOnCookie: bypassOptions.autoCloseOnCookie,
        captureRequestPatterns: bypassOptions.captureRequestPatterns,
        allowRequestPatterns: bypassOptions.allowRequestPatterns,
        pageFinishedScript: bypassOptions.pageFinishedScript,
        blockNetworkImages: bypassOptions.blockNetworkImages,
        clearCookies: bypassOptions.clearCookies,
      );

      if (result != null && result['success'] == true) {
        final pageHtml = result['pageHtml'] as String?;
        final usedSslFallback = result['usedSslFallback'] as bool? ?? false;

        if (usedSslFallback) {
          _logger.w(
            '⚠️ WebView SSL fallback used — server certificate was not trusted.',
          );
        }

        final untrustedHeader = await _persistBypassSession(
          result,
          targetUrl,
          usedSslFallback: usedSslFallback,
        );

        if (bypassOptions.preferCapturedImageUrls) {
          final capturedUrls = (result['capturedImageUrls'] as List<dynamic>?)
              ?.cast<String>()
              .where((u) => u.isNotEmpty)
              .toList();
          if (capturedUrls != null && capturedUrls.isNotEmpty) {
            _logger.i(
              '📸 Using WebView-captured image URLs (${capturedUrls.length}) — skipping Dio verify',
            );
            final chapterData = <String, dynamic>{'images': capturedUrls};
            return Response<String>(
              statusCode: 200,
              data: jsonEncode(chapterData),
              requestOptions: RequestOptions(path: targetUrl),
            ) as Response<T>;
          }
        }

        if (usedSslFallback && _hasCapturedHtml(pageHtml)) {
          // WebView proceeded past a bad cert (komiktap ERR_SSL_PROTOCOL_ERROR,
          // openspec komiktap-ssl-websocket-bypass). Dio's shared client has
          // no badCertificateCallback — it would 3× retry and die on the same
          // bad cert. The WebView just proved the page loads; trust its
          // captured HTML directly.
          final htmlContent = await _readCapturedHtml(pageHtml!);
          if (htmlContent != null) {
            _logger.w(
              '⚠️ SSL fallback — skipping Dio re-verify, serving captured '
              'HTML (${htmlContent.length} chars)',
            );
            return _htmlResponse<T>(htmlContent, targetUrl);
          }
        }

        // 4. If WebView saved HTML to file and this source asked for it,
        // use it directly instead of re-verifying with Dio.
        if (bypassOptions.preferCapturedHtml && _hasCapturedHtml(pageHtml)) {
          final htmlContent = await _readCapturedHtml(pageHtml!);
          if (htmlContent != null) {
            _logger.i(
              '📄 Using WebView-captured HTML (${htmlContent.length} chars) — skipping Dio verify',
            );
            return _htmlResponse<T>(htmlContent, targetUrl);
          }
        }

        // 5. Fallback: verify with a fresh Dio request using WebView cookies.
        return await _verifyBypass<T>(
          targetUrl,
          options: options,
          untrustedCookieHeader: untrustedHeader,
        );
      }
      return null;
    } catch (e) {
      _logger.e('Native Bypass Error: $e');
      return null;
    } finally {
      _bypassingUrls.remove(targetUrl);
    }
  }

  bool _hasCapturedHtml(String? pageHtml) =>
      pageHtml != null && pageHtml.isNotEmpty && pageHtml.startsWith('/');

  Future<String?> _persistBypassSession(
    Map<String, dynamic> result,
    String targetUrl, {
    bool usedSslFallback = false,
  }) async {
    final cookiesRaw =
        (result['cookies'] as List<dynamic>?)?.cast<String>() ?? [];
    final userAgent = result['userAgent'] as String?;

    if (userAgent != null && userAgent.isNotEmpty) {
      _dio.options.headers['User-Agent'] = userAgent;
      // Persist so cold-start probes reuse the UA that minted the
      // current cf_clearance (challenge is UA-bound).
      await _secureStorage
          .write(key: _uaKey, value: userAgent)
          .catchError((_) {});
      _cachedUserAgents[_baseUrl] = userAgent;
      try {
        _cachedUserAgents[Uri.parse(_baseUrl).host] = userAgent;
        _cachedUserAgents[Uri.parse(targetUrl).host] = userAgent;
      } catch (_) {}
      _logger.i('🔄 Synced User-Agent: $userAgent');
    }

    // Untrusted-session cookies ride only this verify chain, then drop
    // (no jar write, no secure storage). Local var, never instance state —
    // no cross-chain races on concurrent bypasses.
    String? untrustedHeader;
    if (cookiesRaw.isNotEmpty) {
      if (usedSslFallback) {
        untrustedHeader = cookiesRaw.join('; ');
        _logger.w(
          '⚠️ SSL fallback — using ${cookiesRaw.length} untrusted cookie(s) for this request chain only (not persisted)',
        );
      } else {
        await _saveRawCookies(cookiesRaw, targetUrl);
      }
    }
    return untrustedHeader;
  }

  /// Opens the visible in-app WebView for [url] and polls [pageFinishedScript]
  /// until it yields a non-empty result, then persists the minted cookies +
  /// User-Agent and returns `pageFinishedScriptResult`.
  ///
  /// Used when a JS-rendered reader (e.g. Cloudflare Turnstile gating a
  /// Next.js Server Action) fails inside the detached headless WebView.
  Future<String?> runInteractivePageScript({
    required String url,
    required String pageFinishedScript,
  }) async {
    if (!_config.bypassEnabled) return null;
    final bypassOptions = _bypassOptionsBuilder(url, _config);
    final result = await _native.showLoginWebView(
      url: url,
      successUrlFilters: const [],
      initialCookie: getCachedCookieHeaderForUrl(url),
      userAgent: null,
      autoCloseOnCookie: null,
      captureRequestPatterns: bypassOptions.captureRequestPatterns,
      allowRequestPatterns: bypassOptions.allowRequestPatterns,
      pageFinishedScript: pageFinishedScript,
      blockNetworkImages: false,
      clearCookies: false,
    );
    if (result == null || result['success'] != true) return null;
    final usedSslFallback = result['usedSslFallback'] as bool? ?? false;
    await _persistBypassSession(result, url, usedSslFallback: usedSslFallback);
    return result['pageFinishedScriptResult'] as String?;
  }

  /// Reads the HTML file captured by the WebView. evaluateJavascript returns
  /// a JSON-encoded string (quoted + escaped) — decode when present.
  /// Returns null on read failure so callers fall through to Dio re-verify.
  Future<String?> _readCapturedHtml(String pageHtml) async {
    try {
      final rawContent = await File(pageHtml).readAsString();
      return rawContent.startsWith('"')
          ? (jsonDecode(rawContent) as String)
          : rawContent;
    } catch (e) {
      _logger.w('Failed to read HTML file: $e');
      return null;
    }
  }

  Response<T> _htmlResponse<T>(String htmlContent, String targetUrl) =>
      Response<String>(
        statusCode: 200,
        data: htmlContent,
        requestOptions: RequestOptions(path: targetUrl),
      ) as Response<T>;

  /// Scoped HTTP client bound to this adapter's own jar.
  ///
  /// The shared [_dio] carries exactly one [CookieManager] (first adapter
  /// wins — see constructor), so requests that need this source's cookies
  /// (probe, waiter retry, bypass verify) must not go through it: another
  /// source's jar would be attached and a freshly-minted clearance would
  /// never be sent (ravenscans: clearance minted + saved, verify still 403).
  /// This client shares the transport stack and non-cookie interceptors,
  /// but resolves cookies exclusively from [_cookieJar].
  Dio _jarClient() {
    final options = _dio.options.copyWith(
      headers: Map<String, dynamic>.from(_dio.options.headers),
      extra: Map<String, Object?>.from(_dio.options.extra),
    );
    final dio = Dio(options)..httpClientAdapter = _dio.httpClientAdapter;
    for (final interceptor in _dio.interceptors) {
      if (interceptor is! CookieManager) dio.interceptors.add(interceptor);
    }
    dio.interceptors.add(CookieManager(_cookieJar));
    return dio;
  }

  Future<Response<T>?> _verifyBypass<T>(
    String url, {
    Options? options,
    String? untrustedCookieHeader,
  }) async {
    // Untrusted-session cookies ride only this verify chain, then drop.
    final untrustedHeader = untrustedCookieHeader;
    final verifyDio = _jarClient();
    try {
      for (int i = 0; i < 3; i++) {
        try {
          final response = await verifyDio.get<T>(
            url,
            options: Options(
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
              headers: {'Cookie': ?untrustedHeader},
            ),
          );

          if (response.statusCode != null && response.statusCode! >= 400) {
            _logger.w(
              'Bypass verify attempt ${i + 1} got status ${response.statusCode}',
            );
            continue;
          }

          // Status < 400 means bypass worked — return immediately.
          // Don't re-check isCloudflareChallenge here because normal pages
          // can contain CF-related strings (Ray ID in footer, challenge-platform
          // in Turnstile scripts) causing false positives.
          return response;
        } catch (e) {
          _logger.w('Verify attempt ${i + 1} failed: $e');
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      return null;
    } finally {
      if (untrustedHeader != null) {
        // CookieManager interceptor may have captured Set-Cookie from the
        // verify response — purge so untrusted cookies never persist.
        try {
          await _cookieJar.delete(Uri.parse(url));
        } catch (_) {
          // Best-effort purge; jar may not have written anything.
        }
      }
    }
  }

  // Cold-start bridge: after app restart the static image-header caches are
  // empty even though the cookie jar still holds a valid cf_clearance.
  // Seed them from the jar so reader image requests (raw HttpClient, no
  // CookieManager interceptor) carry the clearance without re-running bypass.
  Future<void> _seedImageHeaderCache(String url) async {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return;
      if (_cachedCookieHeaders[host] != null &&
          _cachedUserAgents[_baseUrl] != null) {
        return;
      }
      final cookies = await _cookieJar.loadForRequest(Uri.parse(url));
      if (!cookies.any((c) => c.name == 'cf_clearance')) return;
      final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      _cachedCookieHeaders[_baseUrl] = header;
      _cachedCookieHeaders[host] = header;
      await seedBypassHeaderCacheFromJar();
    } catch (_) {
      // Best-effort; next successful bypass repopulates caches anyway.
    }
  }

  /// Public cold-start bridge: re-seeds the static image-header caches from
  /// this adapter's persisted cookie jar + UA. Callers (e.g. download/reader
  /// entry points) invoke it before building image headers so a valid
  /// cf_clearance survives an app restart without opening a WebView first.
  Future<void> seedBypassHeaderCacheFromJar() async {
    try {
      if (_cachedUserAgents[_baseUrl] == null ||
          _cachedUserAgents[_baseUrl]!.isEmpty) {
        final persistedUa = await _secureStorage
            .read(key: _uaKey)
            .catchError((_) => null);
        if (persistedUa != null && persistedUa.isNotEmpty) {
          _cachedUserAgents[_baseUrl] = persistedUa;
          try {
            _cachedUserAgents[Uri.parse(_baseUrl).host] = persistedUa;
          } catch (_) {}
        }
      }
      if (_cachedCookieHeaders[_baseUrl] != null &&
          _cachedCookieHeaders[_baseUrl]!.isNotEmpty) {
        return;
      }
      final uri = Uri.parse(_baseUrl);
      final cookies = await _cookieJar.loadForRequest(uri);
      if (!cookies.any((c) => c.name == 'cf_clearance')) return;
      final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      _cachedCookieHeaders[_baseUrl] = header;
      _cachedCookieHeaders[uri.host] = header;
    } catch (_) {
      // Best-effort; next successful bypass repopulates caches anyway.
    }
  }

  Future<void> _saveRawCookies(List<String> rawCookies, String urlStr) async {
    final uri = Uri.parse(urlStr);

    // Create new cookies ensuring path=/ and domain matches
    final cookiesToSave = rawCookies.map((s) {
      final parts = s.split('=');
      final key = parts[0].trim();
      final value = parts.length > 1 ? parts.sublist(1).join('=') : '';
      return Cookie(key, value)
        ..domain = uri.host
        ..path = '/';
    }).toList();

    await _cookieJar.saveFromResponse(uri, cookiesToSave);
    final cookieHeader = cookiesToSave
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
    _cachedCookieHeaders[_baseUrl] = cookieHeader;
    _cachedCookieHeaders[uri.host] = cookieHeader;
    _logger.d('Saved ${cookiesToSave.length} cookies to jar for ${uri.host}');
  }

  // ============ Authentication Focus ============

  // Login programmatically by fetching nonce and POSTing credentials
  Future<WebViewAuthResult> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    if (!_config.authEnabled || _config.loginUrl.isEmpty) {
      return WebViewAuthResult.failure('Authentication is not configured.');
    }

    _authState = WebViewAuthState.loggingIn;

    try {
      // 1. Getting Nonce
      final loginPageRes = await requestWithBypass<String>(_config.loginUrl);
      final nonceMatch = RegExp(_config.nonceRegex)
          .firstMatch(loginPageRes.data ?? '');
      final nonce = nonceMatch?.group(1) ?? '';

      if (nonce.isEmpty) {
        _authState = WebViewAuthState.error;
        return WebViewAuthResult.failure('Failed to extract login nonce.');
      }

      // 2. Submit Logic
      final postRes = await _dio.post(
        _config.loginUrl,
        data: {
          'koi_user_login': email,
          'koi_user_pass': password,
          'koi_login_nonce': nonce,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      // Check failure signs from form HTML response
      final postHtml = postRes.data.toString();
      if (postHtml.contains('Incorrect password') ||
          postHtml.contains('password you entered is incorrect')) {
        _authState = WebViewAuthState.error;
        return WebViewAuthResult.failure('Invalid email or password.');
      }

      // 3. Verify
      final verified = await _verifyLoginSession();
      if (verified) {
        _authState = WebViewAuthState.loggedIn;
        _email = email;
        _username = email.split('@').first;

        if (rememberMe) {
          // Password intentionally NOT persisted (security: no replay of
          // koi_user_pass at rest). Session verified via cookies instead.
          await _secureStorage.write(key: _keyEmail, value: email);
        }
        return WebViewAuthResult.success(_username!);
      }

      _authState = WebViewAuthState.error;
      return WebViewAuthResult.failure('Login verification failed.');
    } catch (e) {
      _authState = WebViewAuthState.error;
      return WebViewAuthResult.failure('Login failed: $e');
    }
  }

  // Used to check if we have a valid login session (usually by accessing bookmark endpoint)
  Future<bool> _verifyLoginSession() async {
    if (_config.bookmarkVerifyUrl.isNotEmpty) {
      try {
        final res = await _dio.get(
          _config.bookmarkVerifyUrl,
          options: Options(followRedirects: false),
        );
        // Accessing bookmark should return 200. If we get 302, it redirects to login=unauthenticated
        if (res.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // Fallback to cookie verification below.
      }
    }

    if (_config.cookieVerifyKey.isNotEmpty) {
      final cookies = await getCookiesForDomain(_baseUrl);
      final cookieValue = cookies[_config.cookieVerifyKey];
      if (cookieValue != null && cookieValue.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  Future<bool> tryAutoLogin() async {
    if (!_config.authEnabled) return false;

    try {
      if (await _verifyLoginSession()) {
        _email = await _secureStorage.read(key: _keyEmail);
        _username = _email?.split('@').first;
        _authState = WebViewAuthState.loggedIn;
        return true;
      }
      // No password replay: expired session requires explicit re-login.
      return false;
    } catch (_) {
      return false;
    }
  }

  // Set session from external WebView login (e.g. native browser login flow).
  // [username] is the detected username from cookies.
  // [rawCookies] is a list of "key=value" strings from the WebView.
  Future<void> setExternalLogin({
    required String username,
    required List<String> rawCookies,
  }) async {
    if (rawCookies.isNotEmpty) {
      await _saveRawCookies(rawCookies, _baseUrl);
    }

    _authState = WebViewAuthState.loggedIn;
    _username = username;
    _email = '$username@external';

    // Save identity so tryAutoLogin can restore state
    await _secureStorage.write(key: _keyEmail, value: _email!);
    // No password for external sessions
  }

  Future<void> logout() async {
    await _cookieJar.deleteAll();
    await _secureStorage.delete(key: _keyEmail);

    _authState = WebViewAuthState.notLoggedIn;
    _email = null;
    _username = null;
  }
}

class _CappedMap<K, V> extends MapBase<K, V> {
  final int maxCapacity;
  final LinkedHashMap<K, V> _inner = LinkedHashMap<K, V>();

  _CappedMap(this.maxCapacity);

  @override
  V? operator [](Object? key) => _inner[key];

  @override
  void operator []=(K key, V value) {
    if (_inner.length >= maxCapacity && !_inner.containsKey(key)) {
      _inner.remove(_inner.keys.first);
    }
    _inner[key] = value;
  }

  @override
  void clear() => _inner.clear();

  @override
  Iterable<K> get keys => _inner.keys;

  @override
  V? remove(Object? key) => _inner.remove(key);
}
