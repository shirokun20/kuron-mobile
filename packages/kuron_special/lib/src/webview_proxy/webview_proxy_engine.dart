import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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

/// Default DOM selectors for the comix WebView collectors. Mirrors
/// `webviewSelectors` in comix-config.json; used when the config omits
/// them (e.g. older cached configs), so overrides stay optional.
const Map<String, String> defaultChapterSelectors = {
  'item': '.mchap-list .mchap-item',
  'link': 'a.mchap-row__primary',
  'number': '.mchap-row__ch',
  'title': '.mchap-row__title',
  'group': '.mchap-row__group',
  'date': '.mchap-row__time',
  'votes': '.mchap-row__likes',
  'pagerButton': 'nav.npager .npager__num',
  'pagerActive': 'nav.npager .npager__num.is-active',
};

/// Default DOM selectors for the comix reader WebView collector.
const Map<String, String> defaultReaderSelectors = {
  'pageContainer': '.rpage-page',
  'pageImage': 'img.rpage-page__img',
  'pageAttr': 'data-page',
};

/// Safely injects one selector into generated JS: config override when
/// present, otherwise the default. `jsonEncode` keeps injection safe.
String _selectorJson(
  Map<String, String>? selectors,
  String key,
  String fallback,
) =>
    jsonEncode(selectors?[key] ?? fallback);

/// Thrown by [WebViewProxyEngine.runInWebView] when the site answers with a
/// WAF/bot challenge (`CAPTCHA_REQUIRED:<challengePath>` from the capture
/// script) instead of content. Callers surface a user-visible verification
/// action; never attempt to bypass the challenge automatically.
class WebViewChallengeException implements Exception {
  const WebViewChallengeException(this.challengePath, {this.pageUrl, this.userAgent});

  /// Challenge path as reported by the site (`/@waf/challenge`, relative
  /// or absolute). Resolve against the site origin before opening.
  final String challengePath;

  /// Page that triggered the challenge, if known.
  final String? pageUrl;

  /// Request User-Agent that triggered the challenge. WAF cookies can be
  /// User-Agent bound, so interactive verification must reuse it.
  final String? userAgent;

  @override
  String toString() =>
      'WebViewChallengeException($challengePath, pageUrl: $pageUrl)';
}

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
  int? targetPage,
  String urlFragment = '',
}) =>
    '''
(function () {
    const payloadKey = '__comixBrowsePayload';
    const expectedKeyword = $expectedKeywordJson;
    const apiPathMarker = '$apiPathMarker';
    const targetPageNum = ${targetPage ?? 'null'};
    const urlFragment = ${jsonEncode(urlFragment)};
    // When the caller pins a page/sort lane (mangafire home & page 2),
    // blind JSON.parse capture is disabled: only URL-verified fetch/XHR
    // responses may capture, so shell/trending lanes can't win the race.
    const allowBlindCapture = targetPageNum == null && !urlFragment;
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

    const captureText = (text, url) => {
        try {
            if (text && (!url || shouldCaptureUrl(url))) capture(JSON.parse(text), true);
        } catch (e) {}
    };

    const pageMatches = rawUrl => {
        if (targetPageNum == null) return true;
        try {
            const u = new URL(rawUrl || '', window.location.origin);
            const p = u.searchParams.get('page');
            if (targetPageNum === 1) return p === null || p === '1';
            return p === String(targetPageNum);
        } catch (e) {
            return false;
        }
    };

    const shouldCaptureUrl = rawUrl => {
        try {
            const url = new URL(rawUrl || '', window.location.origin);
            if (!url.pathname.includes(apiPathMarker)) return false;
            if (!pageMatches(rawUrl)) return false;
            if (urlFragment && !String(rawUrl || '').includes(urlFragment)) return false;
            if (!expectedKeyword) return true;
            const raw = String(rawUrl || '');
            const decoded = decodeURIComponent(raw.replace(/\\+/g, ' '));
            const kw = expectedKeyword.toLowerCase();
            const rawLower = raw.toLowerCase();
            const decodedLower = decoded.toLowerCase();
            return decodedLower.includes(kw) ||
                   rawLower.includes(kw.replace(/ /g, '+')) ||
                   rawLower.includes(encodeURIComponent(kw).toLowerCase());
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
                    const data = (this.response != null && typeof this.response === 'object') ? this.response : this.responseText;
                    if (typeof data === 'string') {
                        captureText(data);
                    } else if (data && typeof data === 'object') {
                        capture(data, true);
                    }
                }
            } catch (e) {}
        });
        return originalSend.apply(this, arguments);
    };

    const originalParse = JSON.parse;
    const proxiedParse = new Proxy(originalParse, {
        apply(target, thisArg, args) {
            const parsed = Reflect.apply(target, thisArg, args);
            if (!expectedKeyword && allowBlindCapture) {
                capture(parsed);
            }
            // When expectedKeyword is set — or the caller pinned a
            // page/sort lane — rely on fetch/XHR hooks that can
            // verify the request URL. Blindly capturing any items-shaped JSON
            // here races with unrelated SPA payloads (home/trending shell data)
            // and can return wrong results before the actual search API responds.
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
  int? targetPage,
}) {
  final targetPageNum = targetPage ?? 1;
  final paginationTriggerJs = (targetPageNum > 1)
      ? '''
    let pageAttempts = 0;
    const pageTimer = setInterval(() => {
        pageAttempts++;
        if (window[payloadKey] || pageAttempts > 200) {
            clearInterval(pageTimer);
            return;
        }
        try {
            // 1. Try React Fiber onPageChange on pager container
            const pagerEl = document.querySelector('.title-detail__chapters-pager, .npager');
            if (pagerEl) {
                const fiberKey = Object.keys(pagerEl).find(k => k.startsWith('__reactFiber\$'));
                let fiber = pagerEl[fiberKey];
                let fired = false;
                while (fiber) {
                    if (fiber.memoizedProps && typeof fiber.memoizedProps.onPageChange === 'function') {
                        fiber.memoizedProps.onPageChange(targetPage);
                        fired = true;
                        break;
                    }
                    fiber = fiber.return;
                }
                if (fired) return;
            }

            // 2. Try clicking exact numeric button
            const pageButtons = Array.from(document.querySelectorAll('.npager button.npager__num, .title-detail__chapters-pager button'));
            for (const btn of pageButtons) {
                if (btn.textContent.trim() === String(targetPage)) {
                    btn.click();
                    return;
                }
            }

            // 3. Fallback: click next page button
            const nextBtn = document.querySelector('button[aria-label="Next page"]');
            if (nextBtn) {
                nextBtn.click();
            }
        } catch (e) {}
    }, 150);
'''
      : '';

  return '''
(function () {
    const payloadKey = '$payloadKey';
    const apiPathMarker = '$apiPathMarker';
    const targetPage = $targetPageNum;

    const isPageMatch = parsed => {
        if (!targetPage || targetPage <= 1) return true;
        if (parsed && parsed.meta && typeof parsed.meta.page === 'number') {
            return parsed.meta.page === targetPage;
        }
        return true;
    };

    const capture = parsed => {
        try {
            if (window[payloadKey]) return true;
            let ok = false;
            try { ok = ($captureTestJs); } catch (e) { ok = false; }
            if (ok && isPageMatch(parsed)) {
                window[payloadKey] = JSON.stringify(parsed);
                window.$passPayloadName(window[payloadKey]);
                return true;
            }
        } catch (e) {}
        return false;
    };

    if (window[payloadKey]) return window[payloadKey];
    const installedKey = '__comixApiCaptureInstalled_' + payloadKey;
    if (window[installedKey]) return null;
    window[installedKey] = true;

    const shouldCaptureUrl = rawUrl => {
        if (!apiPathMarker) return true;
        try {
            const url = new URL(rawUrl || '', window.location.origin);
            return url.pathname.includes(apiPathMarker);
        } catch (e) {
            return false;
        }
    };

    $paginationTriggerJs

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
        return originalOpen.call(this, method, url);
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
}

/// Chapter-list capture script — rotation-proof hybrid.
///
/// The SPA boots normally (callers keep `<script src="/dist/main-*.js">`
/// in the HTML) and this captures its own signed chapters requests:
/// fetch/XHR hooks accumulate every JSON response whose request URL pairs
/// `/manga/` (or `/api/`) with `chapters`. Signed responses are often
/// encrypted (`{"e":"..."}`) and only become chapters-shaped after apicore
/// decrypts them, so an encrypted chapters response opens a short window
/// in which chapters-shaped `JSON.parse` results are also captured. Manga /
/// recommendation objects are explicitly rejected (manga-only keys and
/// 1-segment `/title/<slug>` URLs), as are comment/thread objects
/// (comment-only keys; `/threads/` and `/comments` URLs never match),
/// so related-title and discussion payloads can never win as chapters.
/// In parallel, the `apicore-*.js` bundle referenced by
/// `main-*.js` is imported and its exports are probed *behaviorally* —
/// functions are tried arity-first in small concurrent batches with short
/// timeouts while outgoing requests are watched; only a candidate that
/// actually fired a `/chapters` request (sequentially re-verified per
/// candidate, never trusted from shared batch state) and returned chapter
/// items pages the full list. Identity comes from observed network
/// behavior, never from export/property names or stringified function
/// source, and items/envelopes are matched structurally, so key rotation
/// in `comix.to` obfuscated bundles doesn't break chapter loading.
String buildChapterListScript({
  required String passPayloadName,
  required String rejectName,
  required String mangaIdJson,
  required String mainScriptUrlJson,
  required int? latestChapterId,
  Map<String, String>? selectors,
}) =>
    '''
(function () {
    const payloadGuard = '__comixChapterPayload';
    const mangaId = $mangaIdJson;
    const mainScriptUrl = $mainScriptUrlJson;
    const latestChapterId = ${latestChapterId?.toString() ?? 'null'};
    const maxPages = $maxChapterPages;
    const selItem = ${_selectorJson(selectors, 'item', defaultChapterSelectors['item']!)};
    const selLink = ${_selectorJson(selectors, 'link', defaultChapterSelectors['link']!)};
    const selNumber = ${_selectorJson(selectors, 'number', defaultChapterSelectors['number']!)};
    const selTitle = ${_selectorJson(selectors, 'title', defaultChapterSelectors['title']!)};
    const selGroup = ${_selectorJson(selectors, 'group', defaultChapterSelectors['group']!)};
    const selDate = ${_selectorJson(selectors, 'date', defaultChapterSelectors['date']!)};
    const selVotes = ${_selectorJson(selectors, 'votes', defaultChapterSelectors['votes']!)};
    const selPagerButton = ${_selectorJson(selectors, 'pagerButton', defaultChapterSelectors['pagerButton']!)};
    const selPagerActive = ${_selectorJson(selectors, 'pagerActive', defaultChapterSelectors['pagerActive']!)};
    if (window[payloadGuard]) return null;
    window[payloadGuard] = true;
    if (window.__comixChaptersInstalled) return null;
    window.__comixChaptersInstalled = true;

    const byId = new Map();
    const requestLog = [];
    let settled = false;
    let probeDone = false;
    let quietTimer = 0;

    const finish = (items) => {
        if (settled) return;
        settled = true;
        if (quietTimer) clearTimeout(quietTimer);
        window.$passPayloadName(JSON.stringify(items));
    };
    const fail = (message) => {
        if (settled) return;
        settled = true;
        if (quietTimer) clearTimeout(quietTimer);
        window.$rejectName(new Error(message));
    };
    const allItems = () => Array.from(byId.values());

    const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
    // Manga/recommendation objects also carry numbers + strings, so reject
    // them explicitly: manga-only keys, and 1-segment `/title/<slug>` URLs
    // (chapter URLs carry the chapter path as a second segment).
    const mangaOnlyKeys = ['poster', 'synopsis', 'synopsisHtml',
        'contentRating', 'altTitles', 'followsTotal', 'latestChapter',
        'ratedAvg', 'recPivot', 'genres', 'authors'];
    // Comment/thread/collection objects (e.g. `/api/v1/threads/{id}/comments`
    // items) also look chapter-shaped; reject them via comment-only keys.
    const commentOnlyKeys = ['body', 'content', 'text', 'threadId',
        'thread_id', 'userId', 'user_id', 'user', 'author', 'replies',
        'replyCount', 'reply_count', 'parentId', 'parent_id', 'isEdited',
        'is_deleted', 'objectType', 'pageIdentifier', 'itemCount', 'owner',
        'preview'];
    const isMangaUrl = (u) => {
        if (typeof u !== 'string') return false;
        const idx = u.indexOf('/title/');
        if (idx === -1) return false;
        const rest = u.substring(idx + 7).split('?')[0].split('#')[0]
            .split('/').filter((s) => s.length > 0);
        return rest.length === 1;
    };
    const isChapterItem = (o) => {
        if (!isObject(o)) return false;
        for (const k of mangaOnlyKeys) {
            if (k in o) return false;
        }
        for (const k of commentOnlyKeys) {
            if (k in o) return false;
        }
        for (const k of ['url', 'href', 'Az', 'ek']) {
            if (isMangaUrl(o[k])) return false;
        }
        let numbers = 0;
        let strings = 0;
        for (const v of Object.values(o)) {
            if (typeof v === 'number' && isFinite(v)) numbers++;
            else if (typeof v === 'string' && v.length > 0) strings++;
        }
        return numbers >= 1 && strings >= 1;
    };
    // Chapters envelope: a bare array, `{items:[...]}`,
    // `{result|data:{items,...}}`, or any object whose array-valued
    // property holds chapter-shaped entries (covers rotated keys).
    const itemsOf = (node, depth) => {
        if (node === null || node === undefined) return null;
        if (Array.isArray(node)) return node;
        if (!isObject(node) || (depth || 0) > 2) return null;
        if (Array.isArray(node.items)) return node.items;
        for (const key of ['result', 'data']) {
            const inner = itemsOf(node[key], (depth || 0) + 1);
            if (inner) return inner;
        }
        for (const v of Object.values(node)) {
            if (Array.isArray(v) && (v.length === 0 || isChapterItem(v[0]))) return v;
        }
        return null;
    };
    // Pagination meta: known wrappers plus any nested object holding a
    // boolean flag or several numbers (covers rotated meta keys).
    const metaOf = (node) => {
        if (Array.isArray(node) || !isObject(node)) return {};
        for (const key of ['meta', 'pagination']) {
            if (isObject(node[key])) return node[key];
        }
        for (const key of ['result', 'data']) {
            if (isObject(node[key])) {
                const inner = metaOf(node[key]);
                if (Object.keys(inner).length > 0) return inner;
            }
        }
        for (const v of Object.values(node)) {
            if (!isObject(v)) continue;
            const vals = Object.values(v);
            const bools = vals.filter((x) => typeof x === 'boolean').length;
            const nums = vals.filter((x) => typeof x === 'number').length;
            if (bools >= 1 || nums >= 2) return v;
        }
        return {};
    };
    const lastPageOf = (m, page) => {
        for (const k of Object.keys(m)) {
            if (/last/i.test(k) && typeof m[k] === 'number' && m[k] >= page) {
                return Math.floor(m[k]);
            }
        }
        let best = 0;
        for (const v of Object.values(m)) {
            if (typeof v === 'number' && isFinite(v) && v > page && v <= maxPages && v > best) {
                best = Math.floor(v);
            }
        }
        return best;
    };
    const shouldFetchMore = (meta, page, count) => {
        if (meta.hasNext === true) return true;
        if (meta.hasNext === false) return false;
        const last = lastPageOf(meta, page);
        if (last > page) return true;
        if (last > 0) return false;
        // Uninformative envelope (rotated keys): a full page suggests more.
        return count >= 100;
    };
    const containsId = (items, id) => items.some((it) =>
        isObject(it) && Object.values(it).some((v) => v === id || (typeof v === 'string' && Number(v) === id)));

    const absorb = (parsed) => {
        const items = itemsOf(parsed, 0);
        if (!items || items.length === 0) return 'empty';
        let added = 0;
        for (const it of items) {
            if (!isChapterItem(it)) continue;
            const key = JSON.stringify(it);
            if (!byId.has(key)) {
                byId.set(key, it);
                added++;
            }
        }
        return added > 0 ? 'added' : 'dup';
    };
    const armSettle = () => {
        if (settled || byId.size === 0) return;
        if (quietTimer) clearTimeout(quietTimer);
        quietTimer = setTimeout(() => finish(allItems()), 8000);
    };

    // Relaxed on purpose: the path prefix varies between deploys, but the
    // resource pair (`/manga/` + `chapters`, or any `/api/` chapters call)
    // is stable server-side. Threads/comments endpoints are explicitly
    // excluded so discussion payloads can never match.
    const isChaptersUrl = (url) => {
        const u = String(url || '');
        if (u.indexOf('chapters') === -1) return false;
        if (u.indexOf('/comments') !== -1) return false;
        if (u.indexOf('/threads/') !== -1) return false;
        return u.indexOf('/manga/') !== -1 || u.indexOf('/api/') !== -1;
    };
    const noteRequest = (url) => {
        requestLog.push(String(url || ''));
        if (requestLog.length > 400) requestLog.splice(0, requestLog.length - 400);
    };
    const absorbText = (text) => {
        try {
            if (checkChallenge(0, text)) return;
            const parsed = JSON.parse(text);
            noteEncrypted(parsed);
            if (absorb(parsed) === 'added' && probeDone) armSettle();
        } catch (e) {}
    };
    // WAF challenge fast-reject: a 403/503 (or any body mentioning the
    // marker) carrying `{"error":"captcha_required","challenge":"..."}` is
    // rejected immediately instead of waiting out the 30s grace timer.
    const checkChallenge = (status, text) => {
        try {
            const statusBlocked = status === 403 || status === 503;
            const bodySaysCaptcha = typeof text === 'string' &&
                text.indexOf('captcha_required') !== -1;
            if (!statusBlocked && !bodySaysCaptcha) return false;
            const parsed = typeof text === 'string' ? JSON.parse(text) : text;
            if (parsed && (parsed.error === 'captcha_required' ||
                typeof parsed.challenge === 'string')) {
                fail('CAPTCHA_REQUIRED:' + (parsed.challenge || '/@waf/challenge'));
                return true;
            }
        } catch (e) {}
        return false;
    };

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
        window.fetch = function () {
            let url = '';
            try {
                url = (arguments[0] && arguments[0].url) || String(arguments[0] || '');
            } catch (e) {}
            noteRequest(url);
            return originalFetch.apply(this, arguments).then((response) => {
                try {
                    const status = response ? response.status : 0;
                    const rurl = (response && response.url) || url;
                    if (status === 403 || status === 503) {
                        response.clone().text().then((t) => checkChallenge(status, t)).catch(() => {});
                    }
                    if (isChaptersUrl(rurl)) {
                        response.clone().text().then(absorbText).catch(() => {});
                    }
                } catch (e) {}
                return response;
            });
        };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
        try {
            this.__comixChaptersUrl = String(url || '');
        } catch (e) {}
        return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
        try {
            noteRequest(this.__comixChaptersUrl || '');
        } catch (e) {}
        this.addEventListener('load', function () {
            try {
                const status = this.status || 0;
                const data = this.response;
                if (status === 403 || status === 503) {
                    checkChallenge(status, data);
                }
                if (isChaptersUrl(this.__comixChaptersUrl || '')) {
                    if (typeof data === 'string') {
                        absorbText(data);
                    } else if (data !== null && typeof data === 'object') {
                        noteEncrypted(data);
                        if (absorb(data) === 'added' && probeDone) armSettle();
                    }
                }
            } catch (e) {}
        });
        return originalSend.apply(this, arguments);
    };

    // Encrypted signed responses (`{"e":"..."}`) carry no items at the
    // fetch/XHR layer — apicore decrypts them and parses the plaintext via
    // JSON.parse. So a chapters-URL encrypted response opens a short window
    // during which chapters-shaped JSON.parse results are captured. The
    // window (not blind capture) keeps unrelated SPA JSON from winning.
    let decryptWindowUntil = 0;
    const noteEncrypted = (parsed) => {
        try {
            if (!isObject(parsed)) return;
            const keys = Object.keys(parsed);
            if (keys.length === 1 && typeof parsed[keys[0]] === 'string' &&
                parsed[keys[0]].length > 64) {
                decryptWindowUntil = Date.now() + 15000;
            }
        } catch (e) {}
    };
    const absorbParsedLoose = (parsed) => {
        try {
            const items = itemsOf(parsed, 0);
            if (items && items.length > 0 && items.some(isChapterItem)) {
                if (absorb(parsed) === 'added' && probeDone) armSettle();
            }
        } catch (e) {}
    };

    if (!JSON.parse.__comixChaptersParseInstalled) {
        const originalParse = JSON.parse;
        const proxiedParse = new Proxy(originalParse, {
            apply(target, thisArg, args) {
                const parsed = Reflect.apply(target, thisArg, args);
                try {
                    if (!settled && Date.now() < decryptWindowUntil) {
                        absorbParsedLoose(parsed);
                    }
                } catch (e) {}
                return parsed;
            }
        });
        proxiedParse.__comixChaptersParseInstalled = true;
        JSON.parse = proxiedParse;
    }

    const timeoutAfter = (ms) => new Promise((_, reject) =>
        setTimeout(() => reject(new Error('probe timeout')), ms));
    const firedChapters = (mark) => {
        for (let i = mark; i < requestLog.length; i++) {
            if (requestLog[i].indexOf('chapters') !== -1) return true;
        }
        return false;
    };
    const looksChapters = (r) => {
        const items = itemsOf(r, 0);
        return !!items && items.length > 0 && items.some(isChapterItem);
    };
    // Behavioral probe: call every exported function with chapters-list
    // arguments and watch outgoing requests. Prioritizes functions whose
    // arity fits a `(id, params)` list call, probes in small concurrent
    // batches with a short per-call timeout (hanging exports must not stall
    // the scan — the live chapters export sits behind dozens of them), and
    // confirms batch hits sequentially since concurrent attribution is
    // ambiguous. Never inspects names or function source.
    const probeNamespaces = async (mod) => {
        const namespaces = [];
        try {
            for (const v of Object.values(mod)) {
                if ((v !== null && typeof v === 'object') || typeof v === 'function') namespaces.push(v);
            }
        } catch (e) {}
        if (namespaces.length === 0 && mod !== null &&
            (typeof mod === 'object' || typeof mod === 'function')) {
            namespaces.push(mod);
        }
        const seenFns = new Set();
        const prioritized = [];
        const deferred = [];
        for (const ns of namespaces) {
            let fns = [];
            try {
                fns = (typeof ns === 'function') ? [ns] : Object.values(ns).filter((v) => typeof v === 'function');
            } catch (e) {}
            const target = (typeof ns === 'object' && ns !== null) ? ns : null;
            for (const fn of fns) {
                if (seenFns.has(fn)) continue;
                seenFns.add(fn);
                const arity = (typeof fn.length === 'number') ? fn.length : 99;
                if (arity >= 1 && arity <= 3) prioritized.push({target, fn});
                else deferred.push({target, fn});
            }
        }
        const ordered = prioritized.concat(deferred).slice(0, 240);
        const argSets = [
            [mangaId, {page: 1, limit: 5, order: {number: 'desc'}}],
            [mangaId, {page: 1, limit: 5}],
            [mangaId, {page: '1', limit: '5'}],
        ];
        const deadline = Date.now() + 45000;
        const batchSize = 10;
        const isEncryptedEnvelope = (r) => {
            if (!isObject(r)) return false;
            const keys = Object.keys(r);
            return keys.length === 1 && typeof r[keys[0]] === 'string' &&
                r[keys[0]].length > 64;
        };
        const tryOne = async (cand, args, timeoutMs) => {
            const mark = requestLog.length;
            try {
                const result = await Promise.race([
                    Reflect.apply(cand.fn, cand.target, args),
                    timeoutAfter(timeoutMs),
                ]);
                // NEVER accept shape alone: the recommendations API also
                // returns item arrays. Only a candidate that actually fired
                // a `/chapters` request — and whose result is chapters (or
                // still-encrypted) — is the chapters API.
                if (!firedChapters(mark)) return null;
                if (looksChapters(result) || isEncryptedEnvelope(result)) {
                    return cand;
                }
            } catch (e) {}
            return null;
        };
        for (const args of argSets) {
            for (let i = 0; i < ordered.length; i += batchSize) {
                if (settled || Date.now() > deadline) return null;
                const batch = ordered.slice(i, i + batchSize);
                const hits = await Promise.all(batch.map((c) => tryOne(c, args, 1500)));
                for (let j = 0; j < batch.length; j++) {
                    if (settled || Date.now() > deadline) return null;
                    if (!hits[j]) continue;
                    // Sequential confirm: a batch hit may credit a sibling
                    // sharing requestLog, so re-verify THIS candidate fired.
                    // Never fall back to the batch hit itself.
                    const confirm = await tryOne(batch[j], args, 4000);
                    if (confirm) return confirm;
                }
            }
        }
        return null;
    };

    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const textOf = (root, sel) => {
        try {
            const el = root.querySelector(sel);
            return ((el && el.textContent) || '').trim();
        } catch (e) {
            return '';
        }
    };
    const attrOf = (root, sel, attr) => {
        try {
            const el = root.querySelector(sel);
            return ((el && el.getAttribute(attr)) || '');
        } catch (e) {
            return '';
        }
    };
    // Primary collector: page-1 chapters are SSR-rendered in
    // `.mchap-list .mchap-item`, so the SPA often never fetches the
    // chapters API on initial load. Scrape the DOM and drive `.npager`
    // pagination by clicking the next-page button.
    const scrapeDomChapters = () => {
        const out = [];
        let items = [];
        try {
            items = Array.from(document.querySelectorAll(selItem));
        } catch (e) {
            return out;
        }
        for (const li of items) {
            try {
                const href = attrOf(li, selLink, 'href');
                if (!href) continue;
                const segs = href.split('?')[0].split('#')[0].split('/').filter((s) => s.length > 0);
                const lastSeg = segs.length > 0 ? segs[segs.length - 1] : '';
                const id = parseInt(lastSeg.split('-')[0], 10);
                if (!isFinite(id)) continue;
                const chText = textOf(li, selNumber).replace('Ch.', '').replace('Ch', '').trim();
                const number = parseFloat(chText);
                const name = textOf(li, selTitle);
                const createdAtFormatted = textOf(li, selDate);
                const groupName = textOf(li, selGroup);
                const groupHref = attrOf(li, selGroup, 'href');
                let groupId = 0;
                if (groupHref) {
                    const gsegs = groupHref.split('?')[0].split('#')[0].split('/').filter((s) => s.length > 0);
                    const gparsed = parseInt(gsegs.length > 0 ? gsegs[gsegs.length - 1] : '', 10);
                    if (isFinite(gparsed)) groupId = gparsed;
                }
                const votes = parseInt(textOf(li, selVotes).replace(/,/g, ''), 10);
                const item = {
                    id, url: href,
                    number: isFinite(number) ? number : 0, name,
                    votes: isFinite(votes) ? votes : 0, createdAtFormatted,
                };
                if (groupName) {
                    item.group = {name: groupName};
                    if (groupId) item.group.id = groupId;
                }
                out.push(item);
            } catch (e) {}
        }
        return out;
    };
    const firstDomHref = () => {
        try {
            const a = document.querySelector(selItem + ' ' + selLink);
            return (a && a.getAttribute('href')) || '';
        } catch (e) {
            return '';
        }
    };
    const collectDomChapters = async () => {
        // SSR renders page 1 immediately; allow briefly for SPA boot.
        let items = [];
        for (let i = 0; i < 100 && items.length === 0; i++) {
            items = scrapeDomChapters();
            if (items.length === 0) await sleep(50);
        }
        if (items.length === 0) return [];
        const seen = new Set();
        const all = [];
        const pushAll = (list) => {
            for (const it of list) {
                const key = String(it.id);
                if (seen.has(key)) continue;
                seen.add(key);
                all.push(it);
                if (latestChapterId !== null && latestChapterId !== undefined && it.id === latestChapterId) {
                    return false;
                }
            }
            return true;
        };
        if (!pushAll(items)) return all;
        let page = 1;
        while (page < maxPages) {
            let nextBtn = null;
            try {
                const btns = Array.from(document.querySelectorAll(selPagerButton));
                for (const b of btns) {
                    if (((b.textContent) || '').trim() === String(page + 1)) {
                        nextBtn = b;
                        break;
                    }
                }
            } catch (e) {}
            if (!nextBtn) break;
            const prevFirst = firstDomHref();
            try {
                nextBtn.click();
            } catch (e) {
                break;
            }
            let changed = false;
            for (let i = 0; i < 100; i++) {
                await sleep(50);
                try {
                    const active = document.querySelector(selPagerActive);
                    if (active && ((active.textContent) || '').trim() === String(page + 1)) {
                        changed = true;
                        break;
                    }
                } catch (e) {}
                if (firstDomHref() !== prevFirst) {
                    changed = true;
                    break;
                }
            }
            if (!changed) break;
            page++;
            const list = scrapeDomChapters();
            if (list.length === 0) break;
            if (!pushAll(list)) break;
        }
        return all;
    };

    (async () => {
        try {
            // DOM first: SSR + npager clicks need no API access at all.
            // Only fall back to behavioral probing when the DOM has
            // no chapters (avoids the probe scan entirely).
            const domItems = await collectDomChapters();
            if (domItems.length > 0) {
                absorb(domItems);
                const items = allItems();
                if (items.length > 0) {
                    finish(items);
                    return;
                }
            }
            let found = null;
            try {
                let mainUrl = mainScriptUrl;
                if (!mainUrl) {
                    const el = document.querySelector('script[type=module][src*="/dist/main-"]');
                    mainUrl = el ? el.src : '';
                }
                if (mainUrl) {
                    const mainResponse = await Promise.race([fetch(mainUrl), timeoutAfter(20000)]);
                    if (mainResponse && mainResponse.ok) {
                        const mainJavaScript = await mainResponse.text();
                        const match = mainJavaScript.match(
                            /from\\s*["']\\.\\/((?:env|apicore)-[^"']+\\.js)["']/
                        );
                        const environmentFile = match ? match[1] : null;
                        if (environmentFile) {
                            const importer = new Function('url', 'return import(url)');
                            const envModule = await Promise.race([
                                importer(new URL(environmentFile, mainUrl).href),
                                timeoutAfter(20000),
                            ]);
                            found = await probeNamespaces(envModule);
                        }
                    }
                }
            } catch (e) {
                found = null;
            }
            if (found) {
                let page = 1;
                let consecutiveEmpty = 0;
                while (page <= maxPages) {
                    let response = null;
                    try {
                        response = await Promise.race([
                            Reflect.apply(found.fn, found.target, [
                                mangaId,
                                {page, limit: 100, order: {number: 'desc'}},
                            ]),
                            timeoutAfter(20000),
                        ]);
                    } catch (e) {
                        break;
                    }
                    const items = itemsOf(response, 0);
                    if (!items || items.length === 0) {
                        consecutiveEmpty++;
                        if (consecutiveEmpty >= 2) break;
                        page++;
                        continue;
                    }
                    consecutiveEmpty = 0;
                    absorb(response);
                    if (latestChapterId !== null && latestChapterId !== undefined &&
                        containsId(items, latestChapterId)) break;
                    if (!shouldFetchMore(metaOf(response), page, items.length)) break;
                    page++;
                }
                const items = allItems();
                if (items.length > 0) {
                    finish(items);
                    return;
                }
            }
        } catch (e) {
            // Fall through to passive capture below.
        } finally {
            probeDone = true;
        }
        if (byId.size > 0) {
            armSettle();
        } else if (!settled) {
            if (quietTimer) clearTimeout(quietTimer);
            quietTimer = setTimeout(() => {
                if (byId.size > 0) finish(allItems());
                else fail('Could not capture chapters list for this title');
            }, 30000);
        }
    })();
    return null;
})();
''';

/// Reader pages capture script — rotation-proof hybrid.
///
/// Primary: URL-verified fetch/XHR hooks for the chapter pages API plus a
/// structural pages-shape check (image-URL items, optional base URL), so
/// obfuscated `apicore-*.js` renames can't break it. Fallback: the
/// `apicore-*.js` bundle is imported and its exports probed behaviorally —
/// each function is tried with the chapter id while outgoing requests are
/// watched; whatever hits the chapter pages endpoint (or returns a
/// pages-shaped envelope) supplies the payload. Posted as canonical
/// `{result:{pages:{baseUrl,items}}}` for `ChapterPagesResponse`.
/// A strict blind `JSON.parse` hook (base URL required) covers SSR shells
/// whose pages payload never crosses fetch/XHR.
String buildPageListScript({
  required String passPayloadName,
  String rejectName = r'$reject',
  String chapterIdJson = 'null',
  String mainScriptUrlJson = 'null',
  Map<String, String>? selectors,
}) =>
    '''
(function () {
    const payloadGuard = '__comixPagePayload';
    if (window[payloadGuard]) return null;
    window[payloadGuard] = true;
    if (window.__comixPagesInstalled) return null;
    window.__comixPagesInstalled = true;

    let chapterId = $chapterIdJson;
    const mainScriptUrl = $mainScriptUrlJson;
    const selPageContainer = ${_selectorJson(selectors, 'pageContainer', defaultReaderSelectors['pageContainer']!)};
    const selPageImage = ${_selectorJson(selectors, 'pageImage', defaultReaderSelectors['pageImage']!)};
    const selPageAttr = ${_selectorJson(selectors, 'pageAttr', defaultReaderSelectors['pageAttr']!)};
    const requestLog = [];
    let settled = false;
    const finish = (baseUrl, items) => {
        if (settled) return;
        settled = true;
        window.$passPayloadName(JSON.stringify({result: {pages: {baseUrl: baseUrl || '', items}}}));
    };
    const fail = (message) => {
        if (settled) return;
        settled = true;
        window.$rejectName(new Error(message));
    };
    // WAF challenge fast-reject: a 403/503 (or any body mentioning the
    // marker) carrying `{"error":"captcha_required","challenge":"..."}` is
    // rejected immediately instead of waiting out the probe scan.
    const checkChallenge = (status, text) => {
        try {
            const statusBlocked = status === 403 || status === 503;
            const bodySaysCaptcha = typeof text === 'string' &&
                text.indexOf('captcha_required') !== -1;
            if (!statusBlocked && !bodySaysCaptcha) return false;
            const parsed = typeof text === 'string' ? JSON.parse(text) : text;
            if (parsed && (parsed.error === 'captcha_required' ||
                typeof parsed.challenge === 'string')) {
                fail('CAPTCHA_REQUIRED:' + (parsed.challenge || '/@waf/challenge'));
                return true;
            }
        } catch (e) {}
        return false;
    };

    const isHttp = (v) => typeof v === 'string' && /^https?:\\/\\//.test(v);
    const isPageItem = (o) => o !== null && typeof o === 'object' && !Array.isArray(o) &&
        Object.values(o).some(isHttp);
    // Structural pages envelope: an object graph containing an array of
    // image-URL items plus the sibling base URL. `strict` (blind JSON.parse
    // path) additionally requires the base URL, which chapters/browse
    // payloads don't carry — that discriminator avoids wrong wins.
    const pagesOf = (node, depth, strict) => {
        if (node === null || node === undefined) return null;
        if (typeof node !== 'object' || (depth || 0) > 3) return null;
        if (Array.isArray(node)) {
            if (node.length === 0) return null;
            const pages = node.filter(isPageItem);
            if (pages.length === 0) return null;
            if (strict && !pages.every(isPageItem)) return null;
            return {baseUrl: '', items: strict ? node : pages};
        }
        const itemArrays = [];
        if (Array.isArray(node.items)) itemArrays.push(node.items);
        for (const v of Object.values(node)) {
            if (Array.isArray(v) && v.length > 0 && v.some(isPageItem) && itemArrays.indexOf(v) === -1) {
                itemArrays.push(v);
            }
        }
        for (const k of ['result', 'data', 'pages']) {
            if (node[k] !== null && typeof node[k] === 'object') {
                const inner = pagesOf(node[k], (depth || 0) + 1, strict);
                if (inner) return inner;
            }
        }
        if (itemArrays.length === 0) return null;
        let baseUrl = '';
        for (const k of Object.keys(node)) {
            if (/base/i.test(k) && isHttp(node[k])) {
                baseUrl = node[k];
                break;
            }
        }
        if (!baseUrl) {
            for (const v of Object.values(node)) {
                if (isHttp(v) && v.endsWith('/')) {
                    baseUrl = v;
                    break;
                }
            }
        }
        if (strict && !baseUrl) return null;
        const items = itemArrays[0];
        if (strict && !items.every(isPageItem)) return null;
        return {baseUrl, items: strict ? items : items.filter(isPageItem)};
    };
    const absorbStrict = (parsed) => {
        const found = pagesOf(parsed, 0, true);
        if (found && found.items.length > 0) finish(found.baseUrl, found.items);
    };
    const absorbLoose = (parsed) => {
        const found = pagesOf(parsed, 0, false);
        if (found && found.items.length > 0) finish(found.baseUrl, found.items);
    };

    try {
        const raw = document.querySelector('script#initial-data')?.textContent;
        const queries = raw && JSON.parse(raw).queries;
        if (queries) {
            for (const q of Object.values(queries)) absorbStrict(q);
            if (!chapterId) {
                try {
                    const parsed = JSON.parse(raw);
                    chapterId = chapterId || parsed?.read?.chapterId;
                } catch (e) {}
            }
        }
    } catch (e) {}
    if (settled) return null;

    const isPagesUrl = (url) => String(url || '').indexOf('/api/v1/chapters') !== -1;
    const noteRequest = (url) => {
        requestLog.push(String(url || ''));
        if (requestLog.length > 400) requestLog.splice(0, requestLog.length - 400);
    };
    const absorbText = (text, loose) => {
        try {
            if (checkChallenge(0, text)) return;
            if (loose) absorbLoose(JSON.parse(text));
            else absorbStrict(JSON.parse(text));
        } catch (e) {}
    };

    const originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
        window.fetch = function () {
            let url = '';
            try {
                url = (arguments[0] && arguments[0].url) || String(arguments[0] || '');
            } catch (e) {}
            noteRequest(url);
            return originalFetch.apply(this, arguments).then((response) => {
                try {
                    const status = response ? response.status : 0;
                    if (status === 403 || status === 503) {
                        response.clone().text().then((t) => checkChallenge(status, t)).catch(() => {});
                    }
                    if (isPagesUrl(response ? response.url : url)) {
                        response.clone().text().then((t) => absorbText(t, true)).catch(() => {});
                    }
                } catch (e) {}
                return response;
            });
        };
    }

    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
        try {
            this.__comixPagesUrl = String(url || '');
        } catch (e) {}
        return originalOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
        try {
            noteRequest(this.__comixPagesUrl || '');
        } catch (e) {}
        this.addEventListener('load', function () {
            try {
                const status = this.status || 0;
                const data = this.response;
                if (status === 403 || status === 503) {
                    checkChallenge(status, data);
                }
                if (isPagesUrl(this.__comixPagesUrl || '')) {
                    if (typeof data === 'string') absorbText(data, true);
                    else if (data !== null && typeof data === 'object') absorbLoose(data);
                }
            } catch (e) {}
        });
        return originalSend.apply(this, arguments);
    };

    if (!JSON.parse.__comixPageCaptureInstalled) {
        const originalParse = JSON.parse;
        const proxiedParse = new Proxy(originalParse, {
            apply(target, thisArg, args) {
                const parsed = Reflect.apply(target, thisArg, args);
                try {
                    if (!settled) absorbStrict(parsed);
                } catch (e) {}
                return parsed;
            }
        });
        proxiedParse.__comixPageCaptureInstalled = true;
        JSON.parse = proxiedParse;
    }

    const timeoutAfter = (ms) => new Promise((_, reject) =>
        setTimeout(() => reject(new Error('probe timeout')), ms));
    const firedPages = (mark) => {
        for (let i = mark; i < requestLog.length; i++) {
            if (requestLog[i].indexOf('/api/v1/chapters') !== -1) return true;
        }
        return false;
    };

    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    // Primary collector: reader pages render as `.rpage-page` divs with
    // lazy `img.rpage-page__img`. Scrolling each into view materializes
    // every `src` in milliseconds with no API access at all.
    const collectDomPages = async () => {
        let pages = [];
        for (let i = 0; i < 150 && pages.length === 0; i++) {
            try {
                pages = Array.from(document.querySelectorAll(selPageContainer));
            } catch (e) {
                pages = [];
            }
            if (pages.length === 0) await sleep(100);
        }
        if (pages.length === 0) return false;
        const byPage = new Map();
        const readVisible = () => {
            for (const p of pages) {
                try {
                    const key = (p.getAttribute(selPageAttr) || '').trim();
                    if (!key || byPage.has(key)) continue;
                    const img = p.querySelector(selPageImage);
                    const src = (img && img.getAttribute('src')) || '';
                    if (src) byPage.set(key, src);
                } catch (e) {}
            }
        };
        readVisible();
        // Bounded to two passes (forward + one retry): with a real
        // viewport each scroll materializes its image in ~ms, so a missing
        // page only needs a short settle wait, never a 30s loop.
        const scanPass = async () => {
            for (const p of pages) {
                if (settled) return;
                let key = '';
                try {
                    key = (p.getAttribute(selPageAttr) || '').trim();
                } catch (e) {}
                if (!key || byPage.has(key)) continue;
                try {
                    p.scrollIntoView({behavior: 'instant', block: 'center'});
                } catch (e) {}
                for (let i = 0; i < 8; i++) {
                    await sleep(20);
                    try {
                        const img = p.querySelector(selPageImage);
                        const src = (img && img.getAttribute('src')) || '';
                        if (src) {
                            byPage.set(key, src);
                            break;
                        }
                    } catch (e) {}
                }
            }
            readVisible();
        };
        await scanPass();
        if (byPage.size < pages.length && !settled) {
            try {
                pages = Array.from(document.querySelectorAll(selPageContainer));
            } catch (e) {}
            await scanPass();
        }
        if (byPage.size === 0) return false;
        const orderedKeys = Array.from(byPage.keys())
            .sort((a, b) => Number(a) - Number(b));
        finish('', orderedKeys.map((k) => ({url: byPage.get(k)})));
        return true;
    };

    (async () => {
        try {
            // DOM first: scrolling `.rpage-page` into view needs no API
            // access. Only probe apicore when the DOM has no pages.
            try {
                if (await collectDomPages()) return;
            } catch (e) {}
            if (settled) return;
            if (!chapterId) return;
            let mainUrl = mainScriptUrl;
            if (!mainUrl) {
                const scriptEl = document.querySelector('script[type=module][src*="/dist/main-"]');
                mainUrl = scriptEl ? scriptEl.src : '';
            }
            if (!mainUrl) return;
            const mainResponse = await Promise.race([fetch(mainUrl), timeoutAfter(20000)]);
            if (!mainResponse || !mainResponse.ok) return;
            const mainJavaScript = await mainResponse.text();
            const match = mainJavaScript.match(
                /from\\s*["']\\.\\/((?:env|apicore)-[^"']+\\.js)["']/
            );
            const environmentFile = match ? match[1] : null;
            if (!environmentFile) return;
            const importer = new Function('url', 'return import(url)');
            const envModule = await Promise.race([
                importer(new URL(environmentFile, mainUrl).href),
                timeoutAfter(20000),
            ]);
            const seenFns = new Set();
            const prioritized = [];
            const deferred = [];
            for (const ns of namespaces) {
                let fns = [];
                try {
                    fns = (typeof ns === 'function') ? [ns] : Object.values(ns).filter((v) => typeof v === 'function');
                } catch (e) {}
                const target = (typeof ns === 'object' && ns !== null) ? ns : null;
                for (const fn of fns) {
                    if (seenFns.has(fn)) continue;
                    seenFns.add(fn);
                    const arity = (typeof fn.length === 'number') ? fn.length : 99;
                    if (arity >= 1 && arity <= 2) prioritized.push({target, fn});
                    else deferred.push({target, fn});
                }
            }
            const ordered = prioritized.concat(deferred).slice(0, 240);
            const variants = [chapterId];
            try {
                const n = Number(chapterId);
                if (isFinite(n)) variants.push(n, String(n));
            } catch (e) {}
            const deadline = Date.now() + 45000;
            const batchSize = 10;
            const tryPageFn = async (cand, variant, timeoutMs) => {
                const mark = requestLog.length;
                try {
                    const result = await Promise.race([
                        Reflect.apply(cand.fn, cand.target, [variant]),
                        timeoutAfter(timeoutMs),
                    ]);
                    // Require `/chapters/` URL proof: shape alone also matches
                    // unrelated item arrays, and a blind win here would post
                    // manga payloads as reader pages.
                    if (!firedPages(mark)) return null;
                    const found = pagesOf(result, 0, false);
                    if (found && found.items.length > 0) {
                        return {cand, found, result};
                    }
                    return {cand, found: null, result};
                } catch (e) {}
                return null;
            };
            for (const variant of variants) {
                for (let i = 0; i < ordered.length; i += batchSize) {
                    if (settled || Date.now() > deadline) return;
                    const batch = ordered.slice(i, i + batchSize);
                    const hits = await Promise.all(batch.map((c) => tryPageFn(c, variant, 1500)));
                    for (let j = 0; j < batch.length; j++) {
                        if (!hits[j] || settled || Date.now() > deadline) continue;
                        const confirm = await tryPageFn(batch[j], variant, 4000);
                        const win = confirm || hits[j];
                        if (win.found && win.found.items.length > 0) {
                            finish(win.found.baseUrl, win.found.items);
                        } else if (win.result !== null && typeof win.result === 'object') {
                            absorbLoose(win.result);
                        }
                        if (settled) return;
                    }
                }
                if (settled) return;
            }
        } catch (e) {
            // Passive hooks remain active if active fetch fails.
        } finally {
            // Nothing captured and nothing still running: fail fast after a
            // brief grace period for late fetch/XHR captures instead of
            // hanging until the 120s native WebView timeout.
            if (!settled) {
                setTimeout(() => {
                    if (!settled) {
                        fail('Could not capture reader pages for this chapter');
                    }
                }, 5000);
            }
        }
    })();

    return null;
})();
''';

/// Per-request WebView proxy engine. One instance per origin.
class WebViewProxyEngine {
  WebViewProxyEngine({
    required this.sourceHost,
    required this.allowedHosts,
    KuronNative? native,
    Logger? logger,
  }) : _native = native ?? KuronNative.instance,
       _logger = logger ?? Logger();

  final String sourceHost;
  final List<String> allowedHosts;
  final KuronNative _native;
  final Logger _logger;

  ComixCipher? _cipher;

  ComixCipher? get cipher => _cipher;
  bool get hasCipher => _cipher != null;

  void resetCipher() => _cipher = null;

  /// Reads the native WebView cookie jar for [url] (same store the
  /// proxied pages run in). Lets direct Dio calls ride the captured
  /// session instead of hitting `missing_token` 403s. Returns '' when
  /// unavailable (desktop, no WebView ran yet) — callers must fall back.
  Future<String> readCookies(String url) async {
    try {
      final cookies = await _native.getCookies(url: url);
      return cookies ?? '';
    } catch (_) {
      return '';
    }
  }
  /// Runs [buildScript] in a per-request WebView loading [pageUrl]+[html].
  /// Returns the captured payload; caches cipher material when valid.
  Future<String> runInWebView({
    required String pageUrl,
    required String html,
    required String userAgent,
    String? initializationScript,
    List<String>? extraAllowedHosts,
    required String Function(String passPayloadName, String rejectName)
    buildScript,
    bool extendDeadlineOnApiTraffic = false,
    CancelToken? cancelToken,
  }) async {
    final bridgeName = _randomBridgeName();
    final errorBridgeName = _randomBridgeName();
    final passPayloadName = _randomBridgeName();
    final rejectName = _randomBridgeName();

    final captureScript = buildScript(passPayloadName, rejectName);
    final effectiveInit = [
      if (initializationScript != null &&
          initializationScript.trim().isNotEmpty)
        initializationScript,
      captureScript,
    ].join('\n');
    final bootstrap = buildBootstrapScript(
      bridgeName: bridgeName,
      errorBridgeName: errorBridgeName,
      passPayloadName: passPayloadName,
      rejectName: rejectName,
      initializationScript: effectiveInit,
    );

    final mergedAllowedHosts =
        extraAllowedHosts != null && extraAllowedHosts.isNotEmpty
        ? {...allowedHosts, ...extraAllowedHosts}.toList()
        : allowedHosts;

    if (cancelToken?.isCancelled == true) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: pageUrl),
        reason: cancelToken?.cancelError,
      );
    }

    late final String raw;
    try {
      final pending = _native
          .runProxyWebView(
            pageUrl: pageUrl,
            html: html,
            userAgent: userAgent,
            allowedHosts: mergedAllowedHosts,
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
      if (cancelToken == null) {
        raw = await pending;
      } else {
        // Fire-and-forget: abort + destroy the native WebView immediately
        // on cancel. Unknown/already-settled bridge names are ignored.
        unawaited(
          cancelToken.whenCancel.then<void>((_) {
            return _native.cancelProxyWebView(bridgeName: bridgeName);
          }).catchError((_) {}),
        );
        raw = await Future.any([
          pending,
          cancelToken.whenCancel.then<String>((_) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: pageUrl),
              reason: cancelToken.cancelError,
            );
          }),
        ]);
      }
    } on TimeoutException {
      _logger.w('comix: WebView proxy timed out for $pageUrl');
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'WEBVIEW_PROXY' &&
          (e.message ?? '').startsWith('CAPTCHA_REQUIRED:')) {
        throw WebViewChallengeException(
          (e.message ?? '').substring('CAPTCHA_REQUIRED:'.length),
          pageUrl: pageUrl,
          userAgent: userAgent,
        );
      }
      rethrow;
    }

    final capture = WebViewCapture.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final material = capture.material;
    if (material != null && material.isValid) {
      _cipher = ComixCipher(material);
      _logger.i('comix: cipher material captured, Tier-1 unlocked');
    }
    return capture.payload;
  }
}
