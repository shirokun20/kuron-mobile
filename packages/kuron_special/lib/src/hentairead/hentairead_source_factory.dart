import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import '../generic_bypass/generic_bypass_source_factory.dart';
import '../webview_session/webview_session_adapter.dart';

/// Bypass factory for sources whose reader pages lazy-load images from a
/// sibling CDN host through blob URLs (HentaiRead, ManhwaRead).
///
/// The WebView capture pass records the CDN image requests
/// (`captureRequestPatterns`) and serves them back without network I/O
/// (`preferCapturedImageUrls`), which is how the CDN's Cloudflare
/// protection is sidestepped for the reader.
class WebViewReaderSourceFactory implements SourceFactory {
  WebViewReaderSourceFactory({
    required String sourceId,
    required Dio dio,
    required WebViewSessionAdapter sessionAdapter,
    required Logger logger,
  }) : _delegate = GenericBypassSourceFactory(
          sourceId: sourceId,
          dio: dio,
          sessionAdapter: sessionAdapter,
          logger: logger,
        );

  final GenericBypassSourceFactory _delegate;

  static WebViewBypassOptions buildBypassOptions(
    String targetUrl,
    WebViewSessionConfig config, {
    required String readerPagePattern,
    required String captureHost,
    required String previewHost,
  }) {
    final isReaderPage = targetUrl.contains(readerPagePattern);
    final registrable = _registrableDomainOf(targetUrl);
    // NOTE: preferCapturedImageUrls deliberately NOT set — reader images are
    // blob lazy-load: CDN requests only fire as the user scrolls, so capture
    // returns only the first ~3 viewport images. The captured HTML contains
    // the chapterData script with ALL image URLs (base64), and
    // chapterDataScript mode extracts them — always prefer HTML.
    // captureRequestPatterns likewise unused for readers. Re-enable capture
    // only if a site's chapterData script ever goes away.
    // NOTE: skipInitialRequest deliberately NOT set — HTTP probe first.
    // Sites serve content without CF challenge when a valid cf_clearance
    // exists; WebView only launches on 403. Setting skipInitialRequest:true
    // would launch WebView on EVERY reader page load — slow + spammy.
    // Auto-close: CF challenge finishes when page title changes from
    // "Just a moment..." — poll via pageFinishedScript, close + harvest
    // cookies when title is real.
    //
    // Reader pages additionally wait for the chapterData script to exist in
    // the DOM before closing. Title flips as soon as <head> parses, but the
    // reader payload sits at the end of <body> — closing on title alone
    // captured a partial DOM and lost most images (2026-08-23 regression).
    // ponytail: 20-poll (~20s) give-up ceiling if the site renames
    // chapterData — upgrade path is a config-supplied ready selector.
    const challengeCheck = '''
          var t = document.title;
          var lower = t.toLowerCase();
          if (lower.indexOf('just a moment') >= 0 ||
              lower.indexOf('attention required') >= 0 ||
              lower.indexOf('checking your browser') >= 0 ||
              lower.indexOf('security check') >= 0 ||
              lower.indexOf('verifying you') >= 0) {
            return '';
          }
      ''';
    final pageFinishedScript = isReaderPage
        ? '''
        (function() {
          $challengeCheck
          if (location.href.indexOf('$readerPagePattern') < 0) return t;
          var hasPayload = false;
          var scripts = document.scripts;
          for (var i = 0; i < scripts.length; i++) {
            if ((scripts[i].textContent || '').indexOf('chapterData') >= 0) {
              hasPayload = true;
              break;
            }
          }
          if (!hasPayload && !document.querySelector('.chapter-image-item')) {
            window.__kuronPolls = (window.__kuronPolls || 0) + 1;
            if (window.__kuronPolls <= 20) return '';
          }
          return t;
        })()
      '''
        : '''
        (function() {
          $challengeCheck
          return t;
        })()
      ''';
    return WebViewBypassOptions(
      autoCloseOnCookie:
          config.autoCloseOnCookie.isEmpty ? null : config.autoCloseOnCookie,
      preferCapturedHtml: true,
      allowRequestPatterns: isReaderPage && registrable != null
          ? [
              registrable,
              captureHost,
              previewHost,
              'cloudflare.com',
              'challenge-platform',
              '.js',
              '.css',
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
              'fonts.gstatic',
              'googleapis',
              'gstatic',
            ]
          : null,
      pageFinishedScript: pageFinishedScript,
    );
  }

  static String? _registrableDomainOf(String url) =>
      registrableDomain(Uri.parse(url));

  @override
  String get sourceId => _delegate.sourceId;

  @override
  ContentSource create(Map<String, dynamic> config) => _delegate.create(config);
}
