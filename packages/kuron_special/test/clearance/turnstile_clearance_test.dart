import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/clearance/native_clearance_driver.dart';
import 'package:kuron_special/src/clearance/turnstile_clearance.dart';

/// Explicit-Turnstile clearance chain for [NativeClearanceDriver.solve]:
/// headless localStorage -> widget mint + `auth.<domain>/clearance`
/// exchange -> visible popup (widget script, user can tick).
///
/// Proven live on macOS 2026-11-07 (same machine + network):
/// - hdoujin single sitekey mints ~709-char tokens in the app WKWebView.
/// - schale mints with the VISIBLE key; the invisible key mints a token
///   the backend rejects (403).
/// - Exchange needs browser-like headers (Bearer + UA + Origin + Referer
///   + X-Requested-With): Bearer-only gets 400. Success is 201 + plain crt.
class FakeClearanceAdapter implements HttpClientAdapter {
  final int status;
  final String body;
  Map<String, dynamic>? lastHeaders;
  String? lastUrl;

  FakeClearanceAdapter(this.status, this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastHeaders = Map<String, dynamic>.from(options.headers);
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.textPlainContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(int status, String body) =>
    Dio()..httpClientAdapter = FakeClearanceAdapter(status, body);

void main() {
  group('TurnstileClearanceExchange', () {
    test('returns trimmed crt on 201 and sends browser-like headers', () async {
      final adapter = FakeClearanceAdapter(201, '  crt-uuid-123  ');
      final crt = await TurnstileClearanceExchange.exchange(
        dio: Dio()..httpClientAdapter = adapter,
        config: TurnstileClearanceConfig.hdoujin,
        turnstileToken: 'tok',
        userAgent: 'TestUA',
      );

      expect(crt, 'crt-uuid-123');
      expect(adapter.lastUrl, 'https://auth.hdoujin.org/clearance');
      // Load-bearing headers: without Origin/Referer/XHR the backend
      // answers 400 even for a valid token (proven live).
      expect(adapter.lastHeaders?['Authorization'], 'Bearer tok');
      expect(adapter.lastHeaders?['User-Agent'], 'TestUA');
      expect(adapter.lastHeaders?['Origin'], 'https://hdoujin.org');
      expect(adapter.lastHeaders?['Referer'], 'https://hdoujin.org/');
      expect(adapter.lastHeaders?['X-Requested-With'], 'XMLHttpRequest');
      // A manual Host header breaks the exchange (proven live: 403).
      expect(adapter.lastHeaders?.containsKey('Host'), isFalse);
    });

    test('returns null on 400', () async {
      final crt = await TurnstileClearanceExchange.exchange(
        dio: fakeDio(400, ''),
        config: TurnstileClearanceConfig.schale,
        turnstileToken: 'tok',
      );
      expect(crt, isNull);
    });

    test('returns null on empty body', () async {
      final crt = await TurnstileClearanceExchange.exchange(
        dio: fakeDio(201, '   '),
        config: TurnstileClearanceConfig.schale,
        turnstileToken: 'tok',
      );
      expect(crt, isNull);
    });

    test('config lookup matches schale-family hosts only', () {
      expect(TurnstileClearanceConfig.forDomainUrl('https://niyaniya.moe/'),
          TurnstileClearanceConfig.schale);
      expect(TurnstileClearanceConfig.forDomainUrl('https://hdoujin.org/'),
          TurnstileClearanceConfig.hdoujin);
      expect(TurnstileClearanceConfig.forDomainUrl('https://example.com/'),
          isNull);
    });
  });

  group('NativeClearanceDriver turnstile chain', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('kuron_native');

    final calls = <String>[];
    final methodArgs = <String, dynamic>{};
    var headlessLocal = <String, dynamic>{'success': false};
    Object? headlessScriptResult;
    Object? popupResult;

    setUp(() {
      calls.clear();
      methodArgs.clear();
      headlessLocal = <String, dynamic>{'success': false};
      headlessScriptResult = null;
      popupResult = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call.method);
        if (call.method == 'showLoginWebView') {
          methodArgs['pageFinishedScript'] =
              (call.arguments as Map)['pageFinishedScript'];
        }
        switch (call.method) {
          case 'getHeadlessClearance':
            return headlessLocal;
          case 'headlessGetClearance':
            if (headlessScriptResult is Exception) {
              throw headlessScriptResult!;
            }
            methodArgs['mintUserAgent'] =
                (call.arguments as Map)['userAgent'];
            return headlessScriptResult;
          case 'showLoginWebView':
            methodArgs['popupUserAgent'] =
                (call.arguments as Map)['userAgent'];
            return popupResult;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('headless mint + exchange solves without popup', () async {
      headlessScriptResult = 'widget-token-abc';
      final driver =
          NativeClearanceDriver(dio: fakeDio(201, 'exchanged-crt-1'));

      final solution = await driver.solve('https://hdoujin.org/');

      expect(solution, isNotNull);
      expect(solution!.token, 'exchanged-crt-1');
      expect(calls, isNot(contains('showLoginWebView')));
    });

    test('direct headless token short-circuits the chain', () async {
      headlessLocal = <String, dynamic>{
        'token': 'local-clearance',
        'userAgent': 'UA',
        'cookies': <String>['a=b'],
      };
      final driver =
          NativeClearanceDriver(dio: fakeDio(201, 'should-not-be-used'));

      final solution = await driver.solve('https://hdoujin.org/');

      expect(solution!.token, 'local-clearance');
      expect(calls, isNot(contains('headlessGetClearance')));
    });

    test('popup widget token is exchanged before returning', () async {
      headlessScriptResult = '';
      popupResult = {
        'pageFinishedScriptResult': 'popup-token-xyz',
        'userAgent': 'UA',
        'cookies': <String>[],
      };
      final driver = NativeClearanceDriver(dio: fakeDio(201, 'popup-crt-2'));

      final solution = await driver.solve('https://niyaniya.moe/');

      expect(solution!.token, 'popup-crt-2');
      expect(methodArgs['pageFinishedScript'], contains('turnstile'));
      expect(methodArgs['pageFinishedScript'],
          contains(TurnstileClearanceConfig.schale.siteKey));
      // Auto-retry marker: the script re-renders the widget until a token
      // lands (schale answers WKWebView with "Verification failed").
      expect(methodArgs['pageFinishedScript'], contains('__kwstart'));
      // Honest UA on the widget popup: a spoofed desktop-Chrome UA over
      // Safari TLS is an inconsistency signal for the strict key.
      expect(methodArgs['popupUserAgent'], isNull);
    });

    test('unknown domain keeps the legacy localStorage popup', () async {
      popupResult = null;
      final driver = NativeClearanceDriver(dio: fakeDio(201, 'unused'));

      final solution = await driver.solve('https://example.com/');

      expect(solution, isNull);
      expect(calls, isNot(contains('headlessGetClearance')));
      expect(methodArgs['pageFinishedScript'], contains('localStorage'));
    });
  });
}
