import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';

class _FakeKuronNative extends KuronNative {
  bool launched = false;

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
    launched = true;
    return null;
  }
}

// Probe must attach this adapter's own jar cookies: with a previously minted
// clearance, the first attempt succeeds and no WebView is launched at all.
// (Regression for repeated WebView popups on every sequential fetch.)
void main() {
  group('WebViewSessionAdapter probe carries own jar', () {
    test('pre-seeded clearance succeeds without WebView', () async {
      final dio = Dio();
      final dioAdapter = DioAdapter(dio: dio);
      dio.httpClientAdapter = dioAdapter;

      const url = 'https://ravenscans.test/';
      dioAdapter.onGet(
        url,
        (server) => server.replyCallback(200, (RequestOptions options) {
          final cookie = options.headers['cookie'] as String?;
          if (cookie != null && cookie.contains('cf_clearance=pre123')) {
            return '{"ok":true}';
          }
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
        }),
      );

      final dirB = Directory.systemTemp.createTempSync('probeB');
      final dirA = Directory.systemTemp.createTempSync('probeA');
      addTearDown(() {
        for (final d in [dirB, dirA]) {
          try {
            d.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      // Another adapter wins the shared Dio's CookieManager (empty jar).
      WebViewSessionAdapter(
        dio: dio,
        cookieJar: PersistCookieJar(storage: FileStorage(dirB.path)),
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://other.test',
      );
      final jarA =
          PersistCookieJar(storage: FileStorage(dirA.path));
      await jarA.saveFromResponse(
        Uri.parse(url),
        [
          Cookie('cf_clearance', 'pre123')
            ..domain = 'ravenscans.test'
            ..path = '/',
        ],
      );
      final fakeNative = _FakeKuronNative();
      final adapterA = WebViewSessionAdapter(
        dio: dio,
        cookieJar: jarA,
        config: const WebViewSessionConfig(bypassEnabled: true),
        baseUrl: 'https://ravenscans.test',
        native: fakeNative,
        logger: Logger(),
      );

      final response = await adapterA.requestWithBypass<String>(url);

      expect(response.statusCode, 200);
      expect(fakeNative.launched, isFalse);
    });
  });
}
