import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

import '../comix/comix_cipher.dart';

// Dart side of the per-request WebView proxy (keiyoushi Comix.kt
// `runInWebView` exact behavior).
//
// One engine instance per origin (comix.to, mangafire) keeps cipher caches
// isolated. The WebView itself is per-request and destroyed by the native
// side when the call completes.

const int webviewTimeoutSeconds = 120;
const int scriptRetryIntervalMs = 100;
const int maxChapterPages = 200;

const List<String> comixAllowedHosts = [
  'comix.to',
  '.comix.to',
  'comix.ws',
  '.comix.ws',
  'challenges.cloudflare.com',
];

const List<String> mangafireAllowedHosts = [
  'mangafire.to',
  '.mangafire.to',
  // React SPA shell + route chunks are served from the mfcdn static host.
  // Without these the SPA never boots and no API traffic is captured.
  's.mfcdn.nl',
  '.s.mfcdn.nl',
  'challenges.cloudflare.com',
];

final _random = Random.secure();
const _bridgeAlphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

String _randomBridgeName() {
  final len = 10 + _random.nextInt(11);
  return List.generate(
    len,
    (_) => _bridgeAlphabet[_random.nextInt(_bridgeAlphabet.length)],
  ).join();
}

/// Builds the bootstrap script injected BEFORE page load: hijacks
/// `window.atob` to capture sboxes (256B) / keys (24/32B), and defines the
/// payload + error bridges. [initializationScript] runs after the hijack
/// (e.g. browse contentFilter localStorage seed).
String buildBootstrapScript({
  required String bridgeName,
  required String errorBridgeName,
  required String passPayloadName,
  required String rejectName,
  String? initializationScript,
}) =>
    '''
(function () {
    const captures = window.__comixCipherCaptures = [];
    const originalAtob = window.atob.bind(window);
    window.atob = function (value) {
        const decoded = originalAtob(value);
        try {
            const bytes = Array.from(decoded, char => char.charCodeAt(0) & 255);
            if (bytes.length === 256 || bytes.length === 24 || bytes.length === 32) {
                captures.push(bytes);
            }
        } catch (e) {}
        return decoded;
    };
    window.$passPayloadName = function (payload) {
        const sboxes = captures.filter(item => item.length === 256).slice(0, 3);
        const keys = captures.filter(item => item.length === 24 || item.length === 32).slice(0, 3);
        const material = sboxes.length === 3 && keys.length === 3
            ? { sboxes, keys }
            : null;
        window.$bridgeName.post(JSON.stringify({ payload, material }));
    };
    window.$rejectName = function (error) {
        window.$errorBridgeName.post(String(error && error.message || error));
    };
})();
${initializationScript ?? ''}
''';

/// Browse/search capture script (fetch + XHR + JSON.parse hooks).
///
/// [apiPathMarker] selects the list API per origin (`/api/v1/manga` for
/// comix, `/api/titles` for mangafire). The keyword gate matches when no
/// keyword is expected or the raw URL contains it (covers both
/// `?keyword=` and `/search/{kw}` styles).
String buildBrowseScript({
  required String passPayloadName,
  required String expectedKeywordJson,
  String apiPathMarker = '/api/v1/manga',
}) =>
    '''
(function () {
    const payloadKey = '__comixBrowsePayload';
    const expectedKeyword = $expectedKeywordJson;
    const apiPathMarker = '$apiPathMarker';
    const capture = (parsed, allowEmpty = false) => {
        try {
            if (parsed && Array.isArray(parsed.items)) {
                parsed = { result: parsed };
            }
            if (
                parsed &&
                parsed.result &&
                Array.isArray(parsed.result.items) &&
                (allowEmpty || parsed.result.items.length > 0)
            ) {
                window[payloadKey] = JSON.stringify(parsed);
                window.$passPayloadName(window[payloadKey]);
                return true;
            }
        } catch (e) {}
        return false;
    };

    if (window[payloadKey]) return window[payloadKey];

    try {
        const raw = document.querySelector('script#initial-data')?.textContent;
        const queries = raw && JSON.parse(raw).queries;
        if (queries) Object.values(queries).some(capture);
    } catch (e) {}

    if (window[payloadKey]) return window[payloadKey];
    if (window.__comixBrowseCaptureInstalled) return null;
    window.__comixBrowseCaptureInstalled = true;

    const captureText = text => {
        try {
            if (text) capture(JSON.parse(text), true);
        } catch (e) {}
    };

    const shouldCaptureUrl = rawUrl => {
        try {
            const url = new URL(rawUrl || '', window.location.origin);
            if (!url.pathname.includes(apiPathMarker)) return false;
            if (!expectedKeyword) return true;
            return (rawUrl || '').includes(expectedKeyword);
        } catch (e) {
            return false;
        }
    };

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
        window.fetch = function () {
            return originalFetch.apply(this, arguments).then(response => {
                try {
                    const url = response && response.url || '';
                    if (shouldCaptureUrl(url)) {
                        response.clone().text().then(captureText).catch(() => {});
                    }
                } catch (e) {}
                return response;
            });
        };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
        this.__comixBrowseUrl = String(url || '');
        return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
            try {
                if (shouldCaptureUrl(this.__comixBrowseUrl)) {
                    captureText(this.responseText);
                }
            } catch (e) {}
        });
        return originalSend.apply(this, arguments);
    };

    const originalParse = JSON.parse;
    const proxiedParse = new Proxy(originalParse, {
        apply(target, thisArg, args) {
            const parsed = Reflect.apply(target, thisArg, args);
            if (!expectedKeyword) capture(parsed);
            return parsed;
        }
    });
    JSON.parse = proxiedParse;
    return window[payloadKey] || null;
})();
''';

/// Generic single-payload capture (fetch + XHR hooks).
///
/// Used for origins without an `initial-data` SSR blob (e.g. mangafire
/// React SPA): the page JS issues its own signed/VRF requests and this
/// posts the first JSON satisfying [captureTestJs] (a JS expression over
/// `parsed`), optionally restricted to URLs containing [apiPathMarker].
/// The SPA generates its own auth params, so Dart captures only.
String buildApiCaptureScript({
  required String payloadKey,
  required String passPayloadName,
  required String captureTestJs,
  String apiPathMarker = '',
}) =>
    '''
(function () {
    const payloadKey = '$payloadKey';
    const apiPathMarker = '$apiPathMarker';
    const capture = parsed => {
        try {
            if (window[payloadKey]) return true;
            let ok = false;
            try { ok = ($captureTestJs); } catch (e) { ok = false; }
            if (ok) {
                window[payloadKey] = JSON.stringify(parsed);
                window.$passPayloadName(window[payloadKey]);
                return true;
            }
        } catch (e) {}
        return false;
    };

    if (window[payloadKey]) return window[payloadKey];
    if (window.__comixApiCaptureInstalled) return null;
    window.__comixApiCaptureInstalled = true;

    const shouldCaptureUrl = rawUrl => {
        if (!apiPathMarker) return true;
        try {
            const url = new URL(rawUrl || '', window.location.origin);
            return url.pathname.includes(apiPathMarker);
        } catch (e) {
            return false;
        }
    };
    const captureText = text => {
        try {
            if (text) capture(JSON.parse(text));
        } catch (e) {}
    };

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
        window.fetch = function () {
            return originalFetch.apply(this, arguments).then(response => {
                try {
                    const url = response && response.url || '';
                    if (shouldCaptureUrl(url)) {
                        response.clone().text().then(captureText).catch(() => {});
                    }
                } catch (e) {}
                return response;
            });
        };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
        this.__comixApiUrl = String(url || '');
        return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
            try {
                if (shouldCaptureUrl(this.__comixApiUrl)) {
                    captureText(this.responseText);
                }
            } catch (e) {}
        });
        return originalSend.apply(this, arguments);
    };
    return window[payloadKey] || null;
})();
''';

/// Chapter-list capture script (env bundle import + mangaApi.chapters loop).
String buildChapterListScript({
  required String passPayloadName,
  required String rejectName,
  required String mangaIdJson,
  required String mainScriptUrlJson,
  required int? latestChapterId,
}) =>
    '''
(function () {
    const payloadKey = '__comixChapterPayload';
    const mangaId = $mangaIdJson;
    const mainScriptUrl = $mainScriptUrlJson;
    const latestChapterId = ${latestChapterId?.toString() ?? 'null'};
    if (window[payloadKey]) return null;
    window[payloadKey] = true;

    (async () => {
        try {
            if (!mainScriptUrl) throw new Error('Could not find main bundle');
            const mainResponse = await fetch(mainScriptUrl);
            if (!mainResponse.ok) throw new Error('Could not load main bundle');
            const mainJavaScript = await mainResponse.text();
            const environmentFile = mainJavaScript.match(
                /from\\s*["']\\.\\/(env-[^"']+\\.js)["']/
            )?.[1];
            if (!environmentFile) throw new Error('Could not find environment bundle');

            const importBundle = new Function('url', 'return import(url)');
            const environment = await importBundle(
                new URL(environmentFile, mainScriptUrl).href
            );
            const mangaApi = Object.values(environment).find(value =>
                value &&
                typeof value === 'object' &&
                typeof value.chapters === 'function'
            );
            if (!mangaApi) throw new Error('Could not find manga API');

            const items = [];
            let page = 1;
            while (page <= $maxChapterPages) {
                const response = await mangaApi.chapters(mangaId, {
                    page,
                    limit: 100,
                    order: { number: 'desc' }
                });
                const pageItems = response?.items;
                if (!Array.isArray(pageItems) || pageItems.length === 0) break;

                items.push(...pageItems);
                if (pageItems.some(item => item.id === latestChapterId)) break;

                const meta = response.meta || response.pagination || {};
                const lastPage = meta.lastPage || meta.last_page || page;
                if (!(meta.hasNext || page < lastPage)) break;
                page++;
            }
            window.$passPayloadName(JSON.stringify(items));
        } catch (error) {
            window.$rejectName(error);
        }
    })();
    return null;
})();
''';

/// Reader pages capture script (initial-data + JSON.parse proxy).
String buildPageListScript({required String passPayloadName}) => '''
(function () {
    const payloadKey = '__comixPagePayload';
    const capture = parsed => {
        try {
            if (parsed && parsed.result && parsed.result.pages) {
                window[payloadKey] = JSON.stringify(parsed);
                window.$passPayloadName(window[payloadKey]);
                return true;
            }
        } catch (e) {}
        return false;
    };

    if (window[payloadKey]) return window[payloadKey];

    try {
        const raw = document.querySelector('script#initial-data')?.textContent;
        const queries = raw && JSON.parse(raw).queries;
        if (queries) Object.values(queries).some(capture);
    } catch (e) {}

    if (window[payloadKey]) return window[payloadKey];
    if (JSON.parse.__comixPageCaptureInstalled) return null;
    const originalParse = JSON.parse;
    const proxiedParse = new Proxy(originalParse, {
        apply(target, thisArg, args) {
            const parsed = Reflect.apply(target, thisArg, args);
            capture(parsed);
            return parsed;
        }
    });
    proxiedParse.__comixPageCaptureInstalled = true;
    JSON.parse = proxiedParse;
    return window[payloadKey] || null;
})();
''';

/// Per-request WebView proxy engine. One instance per origin.
class WebViewProxyEngine {
  WebViewProxyEngine({
    required this.sourceHost,
    required this.allowedHosts,
    KuronNative? native,
    Logger? logger,
  })  : _native = native ?? KuronNative.instance,
        _logger = logger ?? Logger();

  final String sourceHost;
  final List<String> allowedHosts;
  final KuronNative _native;
  final Logger _logger;

  ComixCipher? _cipher;

  ComixCipher? get cipher => _cipher;
  bool get hasCipher => _cipher != null;

  void resetCipher() => _cipher = null;

  /// Runs [buildScript] in a per-request WebView loading [pageUrl]+[html].
  /// Returns the captured payload; caches cipher material when valid.
  Future<String> runInWebView({
    required String pageUrl,
    required String html,
    required String userAgent,
    String? initializationScript,
    required String Function(String passPayloadName, String rejectName)
        buildScript,
    bool extendDeadlineOnApiTraffic = false,
  }) async {
    final bridgeName = _randomBridgeName();
    final errorBridgeName = _randomBridgeName();
    final passPayloadName = _randomBridgeName();
    final rejectName = _randomBridgeName();

    final bootstrap = buildBootstrapScript(
      bridgeName: bridgeName,
      errorBridgeName: errorBridgeName,
      passPayloadName: passPayloadName,
      rejectName: rejectName,
      initializationScript: initializationScript,
    );
    final captureScript = buildScript(passPayloadName, rejectName);

    late final String raw;
    try {
      raw = await _native
          .runProxyWebView(
            pageUrl: pageUrl,
            html: html,
            userAgent: userAgent,
            allowedHosts: allowedHosts,
            bridgeName: bridgeName,
            errorBridgeName: errorBridgeName,
            bootstrapScript: bootstrap,
            captureScript: captureScript,
            pollIntervalMs: scriptRetryIntervalMs,
            extendDeadlineOnApiTraffic: extendDeadlineOnApiTraffic,
          )
          .timeout(
            Duration(seconds: webviewTimeoutSeconds + 30),
            onTimeout: () =>
                throw TimeoutException('Timed out waiting for WebView'),
          );
    } on TimeoutException {
      _logger.w('comix: WebView proxy timed out for $pageUrl');
      rethrow;
    }

    final capture =
        WebViewCapture.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final material = capture.material;
    if (material != null && material.isValid) {
      _cipher = ComixCipher(material);
      _logger.i('comix: cipher material captured, Tier-1 unlocked');
    }
    return capture.payload;
  }
}
