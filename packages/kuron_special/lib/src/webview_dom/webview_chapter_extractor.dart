import 'dart:convert';

import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

/// Thrown when the headless page is a protection wall (CF challenge,
/// Turnstile, login-wall) instead of chapter content.
///
/// The message intentionally contains the word "challenge" so the app's
/// error-log exclusions recognise it: a wall is not a bug and must neither
/// be logged as an error nor reported as a config anomaly.
class ReaderChallengeException implements Exception {
  ReaderChallengeException(this.pageUrl);

  final String pageUrl;

  @override
  String toString() =>
      'ReaderChallengeException: reader challenge wall detected at $pageUrl (protection active, retry after bypass)';
}

/// Result of parsing one headless collect run.
class CollectedChapter {
  const CollectedChapter({required this.images, required this.challenge});

  /// Absolute image URLs in document order, deduplicated.
  final List<String> images;

  /// True when the page is a protection wall instead of content.
  final bool challenge;
}

/// Headless evaluate callback (injectable for tests; defaults to the
/// native WebView).
typedef HeadlessEval = Future<String?> Function({
  required String url,
  required String script,
  required int timeoutMs,
});

/// Extracts chapter images from JS-rendered pages (e.g. voratoon
/// Next.js Server Action chapters) via a headless WebView.
class WebViewChapterExtractor {
  WebViewChapterExtractor({this._native, Logger? logger, this._headlessEval})
    : _logger = logger ?? Logger();

  final KuronNative? _native;
  final Logger _logger;
  final HeadlessEval? _headlessEval;

  /// Builds the polling collector script. Returns `""` while the page is
  /// still loading, otherwise a JSON string
  /// `{"images":[...],"challenge":bool}`.
  ///
  /// Set [detectChallenge] to `false` when running inside an interactive
  /// WebView so the view stays open until images render instead of closing on
  /// a Turnstile/CF challenge wall.
  static String buildCollectorScript({
    required List<String> selectors,
    required List<String> attributes,
    bool detectChallenge = true,
  }) {
    final selJson = jsonEncode(selectors);
    final attrJson = jsonEncode(attributes);
    final challengeExpr = detectChallenge
        ? '''
  var hay = ((document.title || '') + ' ' +
    (document.body ? document.body.innerText.slice(0, 2000) : '')).toLowerCase();
  var challenge = hay.indexOf('just a moment') !== -1 ||
      hay.indexOf('verifying you are human') !== -1 ||
      hay.indexOf('attention required') !== -1 ||
      hay.indexOf('verifikasi keamanan gagal') !== -1 ||
      !!document.querySelector('.cf-turnstile,#challenge-running,#cf-challenge-running');'''
        : '  var challenge = false;';
    return '''
(() => {
  var sels = $selJson;
  var attrs = $attrJson;
  var out = [];
  var seen = {};
  function push(v) {
    if (!v || v.indexOf('data:') === 0) return;
    try {
      var u = new URL(v, document.baseURI).toString();
      if (!seen[u]) { seen[u] = 1; out.push(u); }
    } catch (e) {}
  }
  for (var si = 0; si < sels.length; si++) {
    try {
      var nodes = document.querySelectorAll(sels[si]);
      for (var ni = 0; ni < nodes.length; ni++) {
        var el = nodes[ni];
        for (var ai = 0; ai < attrs.length; ai++) {
          var v = (el.getAttribute(attrs[ai]) || '').trim();
          if (v) { push(v); break; }
        }
        var src = (el.getAttribute('src') || '').trim();
        if (src) push(src);
      }
    } catch (e) {}
  }
$challengeExpr
  if (out.length === 0 && !challenge) return '';
  return JSON.stringify({images: out, challenge: !!challenge});
})()
''';
  }

  /// Parses one collect run. Tolerates the extra JSON quoting that
  /// Android `evaluateJavascript` adds around string results.
  static CollectedChapter parseCollected(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') {
      return const CollectedChapter(images: [], challenge: false);
    }
    try {
      final decoded = _looseJsonDecode(raw);
      if (decoded is Map) {
        final images = decoded['images'];
        final challenge = decoded['challenge'] == true;
        if (images is List) {
          return CollectedChapter(
            images: images
                .whereType<String>()
                .where((u) => u.startsWith('http'))
                .toList(),
            challenge: challenge,
          );
        }
      }
    } catch (_) {}
    return const CollectedChapter(images: [], challenge: false);
  }

  static Object? _looseJsonDecode(String raw) {
    try {
      final first = jsonDecode(raw);
      if (first is String) {
        return jsonDecode(first);
      }
      return first;
    } catch (_) {}
    // Android wraps string results in quotes and escapes the content.
    try {
      return jsonDecode(
        raw.replaceAll(r'\"', '"').replaceAll(RegExp(r'^"|"$'), ''),
      );
    } catch (_) {}
    return null;
  }

  /// Loads [pageUrl] headlessly and returns its chapter images.
  ///
  /// Throws [ReaderChallengeException] when the page is a protection
  /// wall (caller turns it into a retry/bypass, never an anomaly).
  /// Returns empty [ChapterData.images] on timeout/empty (drift
  /// candidate — the repository's home/reader detectors decide).
  Future<ChapterData> fetchChapterImages({
    required String pageUrl,
    required List<String> imageSelectors,
    List<String> imageAttributes = const ['src'],
    Duration timeout = const Duration(seconds: 20),
    HeadlessEval? headlessEval,
    Future<bool?> Function({required String url, required String cookies})?
    cookieSync,
    String? cookies,
  }) async {
    final eval =
        headlessEval ??
        _headlessEval ??
        ({
          required String url,
          required String script,
          required int timeoutMs,
        }) => (_native ?? KuronNative.instance).headlessGetClearance(
          url: url,
          script: script,
          timeoutMs: timeoutMs,
        );
    if (cookies != null && cookies.isNotEmpty) {
      try {
        final sync =
            cookieSync ??
            ({required String url, required String cookies}) =>
                KuronNative.instance.setCookies(url: url, cookies: cookies);
        await sync(url: pageUrl, cookies: cookies);
      } catch (_) {
        // Best effort: the headless load may still pass with cookies the
        // native store already holds from an earlier bypass.
      }
    }
    final script = buildCollectorScript(
      selectors: imageSelectors,
      attributes: imageAttributes,
    );
    final raw = await eval(
      url: pageUrl,
      script: script,
      timeoutMs: timeout.inMilliseconds,
    );
    final collected = parseCollected(raw);
    if (collected.challenge) {
      throw ReaderChallengeException(pageUrl);
    }
    if (collected.images.isEmpty) {
      _logger.w('WebViewDomReader: no images collected from $pageUrl');
    }
    return ChapterData(images: collected.images);
  }
}
