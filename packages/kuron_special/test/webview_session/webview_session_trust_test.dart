import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_special/kuron_special.dart';

class _FakeKuronNative extends KuronNative {
  Map<String, dynamic>? result;

  @override
  Future<Map<String, dynamic>?> showLoginWebView({
    required String url,
    List<String>? successUrlFilters,
    String? initialCookie,
    String? userAgent,
    String? autoCloseOnCookie,
    String? ssoRedirectUrl,
    List<String>? domImageSelectors,
    List<String>? domImageAttributes,
    List<String>? domLinkSelectors,
    List<String>? captureRequestPatterns,
    List<String>? allowRequestPatterns,
    String? pageFinishedScript,
    bool blockNetworkImages = false,
    bool enableAdBlock = false,
    bool clearCookies = false,
    String? backgroundColor,
    String? textColor,
  }) async {
    return result;
  }
}

void main() {
  group('isTrustedWebViewSessionUrl (F1)', () {
    const target = 'https://komiktap.info/manga';

    test('allows the session domain itself', () {
      expect(
        isTrustedWebViewSessionUrl('https://komiktap.info/login', target),
        isTrue,
      );
    });

    test('allows subdomains (Cloudflare challenge pages)', () {
      expect(
        isTrustedWebViewSessionUrl(
          'https://challenge.komiktap.info/cdn-cgi/challenge-platform',
          target,
        ),
        isTrue,
      );
    });

    test('allows http scheme on the session domain', () {
      expect(
        isTrustedWebViewSessionUrl('http://komiktap.info/', target),
        isTrue,
      );
    });

    test('rejects foreign hosts', () {
      expect(
        isTrustedWebViewSessionUrl('https://evil.com/login', target),
        isFalse,
      );
    });

    test('rejects lookalike suffix hosts', () {
      expect(
        isTrustedWebViewSessionUrl('https://komiktap.info.evil.com/', target),
        isFalse,
      );
    });

    test('rejects non-http schemes', () {
      expect(
        isTrustedWebViewSessionUrl('javascript:alert(1)', target),
        isFalse,
      );
      expect(
        isTrustedWebViewSessionUrl('intent://evil.com#Intent;end', target),
        isFalse,
      );
      expect(
        isTrustedWebViewSessionUrl('data:text/html,<h1>x</h1>', target),
        isFalse,
      );
    });

    test('rejects blank or unparsable urls', () {
      expect(isTrustedWebViewSessionUrl(null, target), isFalse);
      expect(isTrustedWebViewSessionUrl('', target), isFalse);
      expect(isTrustedWebViewSessionUrl('not a url', target), isFalse);
    });
  });

  group('runInteractivePageScript cookie rebind guard (F1)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('webview_trust_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    WebViewSessionAdapter buildAdapter(
      _FakeKuronNative native,
      PersistCookieJar jar,
    ) {
      return WebViewSessionAdapter(
        dio: Dio(),
        cookieJar: jar,
        native: native,
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://komiktap.info',
      );
    }

    PersistCookieJar isolatedJar(String name) =>
        PersistCookieJar(storage: FileStorage('${tempDir.path}/$name'));

    test('persists cookies when the finish URL matches the session domain',
        () async {
      final native = _FakeKuronNative();
      native.result = {
        'success': true,
        'cookies': <String>['cf_clearance=trusted-value'],
        'userAgent': 'ua',
        'currentUrl': 'https://komiktap.info/cdn-cgi/challenge-platform',
        'pageFinishedScriptResult': 'token',
      };
      final jar = isolatedJar('trusted');
      final adapter = buildAdapter(native, jar);

      final token = await adapter.runInteractivePageScript(
        url: 'https://komiktap.info/',
        pageFinishedScript: 'script',
      );

      expect(token, 'token');
      final saved =
          await jar.loadForRequest(Uri.parse('https://komiktap.info/'));
      expect(
        saved.map((c) => '${c.name}=${c.value}'),
        contains('cf_clearance=trusted-value'),
      );
    });

    test('drops cookies harvested from an untrusted redirect', () async {
      final native = _FakeKuronNative();
      native.result = {
        'success': true,
        'cookies': <String>['cf_clearance=evil-value'],
        'userAgent': 'ua',
        'currentUrl': 'https://evil.com/login',
        'pageFinishedScriptResult': 'token',
      };
      final jar = isolatedJar('untrusted');
      final adapter = buildAdapter(native, jar);

      final token = await adapter.runInteractivePageScript(
        url: 'https://komiktap.info/',
        pageFinishedScript: 'script',
      );

      expect(token, 'token');
      final saved =
          await jar.loadForRequest(Uri.parse('https://komiktap.info/'));
      expect(saved, isEmpty);
    });
  });
}
