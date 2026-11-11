import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';

class _FakeKuronNative extends KuronNative {
  Map<String, dynamic>? result;
  int invocations = 0;
  Duration hang = Duration.zero;
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
    invocations++;
    if (hang > Duration.zero) await Future.delayed(hang);
    return result;
  }
}

// Regression test for ravenscans: the shared Dio carries exactly one
// CookieManager (first adapter wins), so a freshly-minted cf_clearance in
// this adapter's own jar was never attached to verify requests → 403 loop.
void main() {
  group('WebViewSessionAdapter shared-Dio verify jar', () {
    test('verify attaches clearance from own jar, not shared jar', () async {
      final dio = Dio();
      final dioAdapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = dioAdapter;

      const url = 'https://ravenscans.test/';
      var calls = 0;
      final seenCookies = <String?>[];
      dioAdapter.onGet(
        url,
        (server) => server.replyCallback(200, (RequestOptions options) {
          calls++;
          if (calls == 1) {
            throw DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                data: 'challenge',
                headers: Headers.fromMap({
                  'cf-mitigated': ['challenge'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          }
          seenCookies.add(options.headers['cookie'] as String?);
          return '{"ok":true}';
        }),
      );

      // Isolated on-disk storage per jar: default FileStorage() shares
      // `.cookies/4/` across instances, which would mask the bug.
      final dirB = Directory.systemTemp.createTempSync('jarB');
      final dirA = Directory.systemTemp.createTempSync('jarA');
      addTearDown(() {
        try {
          dirB.deleteSync(recursive: true);
        } catch (_) {}
        try {
          dirA.deleteSync(recursive: true);
        } catch (_) {}
      });
      // Adapter B binds the shared Dio's CookieManager first (empty jar).
      WebViewSessionAdapter(
        dio: dio,
        cookieJar: PersistCookieJar(storage: FileStorage(dirB.path)),
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://other.test',
      );
      final fakeNative = _FakeKuronNative();
      final adapterA = WebViewSessionAdapter(
        dio: dio,
        cookieJar: PersistCookieJar(storage: FileStorage(dirA.path)),
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://ravenscans.test',
        native: fakeNative,
        logger: Logger(),
      );
      // Cookie capture happens inside the mock above (replyCallback sees the
      // exact headers the scoped verify client sends).
      fakeNative.result = {
        'success': true,
        'cookies': ['cf_clearance=fresh123'],
        'userAgent': 'TestUA/1.0',
      };

      final response = await adapterA.requestWithBypass<String>(url);

      expect(response.statusCode, 200);
      expect(calls, greaterThanOrEqualTo(2));
      expect(seenCookies.last, contains('cf_clearance=fresh123'));
    });

    test('concurrent caller waits for in-flight bypass instead of WebView',
        () async {
      final dio = Dio();
      final dioAdapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = dioAdapter;

      const url = 'https://ravenscans.test/';
      var calls = 0;
      final seenCookies = <String?>[];
      dioAdapter.onGet(
        url,
        (server) => server.replyCallback(200, (RequestOptions options) {
          calls++;
          if (calls == 1) {
            throw DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                data: 'challenge',
                headers: Headers.fromMap({
                  'cf-mitigated': ['challenge'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          }
          seenCookies.add(options.headers['cookie'] as String?);
          return '{"ok":true}';
        }),
      );

      final dirB = Directory.systemTemp.createTempSync('waitB');
      final dirA = Directory.systemTemp.createTempSync('waitA');
      addTearDown(() {
        for (final d in [dirB, dirA]) {
          try {
            d.deleteSync(recursive: true);
          } catch (_) {}
        }
      });
      WebViewSessionAdapter(
        dio: dio,
        cookieJar: PersistCookieJar(storage: FileStorage(dirB.path)),
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://other.test',
      );
      final fakeNative = _FakeKuronNative()
        ..hang = const Duration(seconds: 3)
        ..result = {
          'success': true,
          'cookies': ['cf_clearance=fresh123'],
          'userAgent': 'TestUA/1.0',
        };
      final adapterA = WebViewSessionAdapter(
        dio: dio,
        cookieJar: PersistCookieJar(storage: FileStorage(dirA.path)),
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://ravenscans.test',
        native: fakeNative,
        logger: Logger(),
      );

      // First request triggers the bypass (slow WebView).
      final first = adapterA.requestWithBypass<String>(url);
      // Wait until the WebView is actually solving.
      for (var i = 0; i < 100 && fakeNative.invocations == 0; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(fakeNative.invocations, 1);
      // Second concurrent request must wait, not open another WebView.
      final second = adapterA.requestWithBypass<String>(url);

      final responses = await Future.wait([first, second]);

      expect(responses[0].statusCode, 200);
      expect(responses[1].statusCode, 200);
      expect(fakeNative.invocations, 1);
      expect(seenCookies, isNotEmpty);
      expect(seenCookies.last, contains('cf_clearance=fresh123'));
    });
  });
}
