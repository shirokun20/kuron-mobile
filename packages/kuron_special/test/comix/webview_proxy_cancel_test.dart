import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';
import 'package:logger/logger.dart';

// Cancellation wiring for per-request proxy WebViews:
// ComixAdapter -> WebViewProxyEngine.runInWebView -> KuronNative ->
// ProxyWebViewHandler.cancel, which aborts and destroys the native WebView
// so cancelled requests never leave orphaned background WebViews behind.

class _FakeNative extends KuronNative {
  _FakeNative({this.hang = false});

  final bool hang;
  int runCalls = 0;
  String? cancelledBridge;

  @override
  Future<String> runProxyWebView({
    required String pageUrl,
    required String html,
    required String userAgent,
    required List<String> allowedHosts,
    required String bridgeName,
    required String errorBridgeName,
    required String bootstrapScript,
    required String captureScript,
    int pollIntervalMs = 100,
    bool extendDeadlineOnApiTraffic = false,
  }) {
    runCalls++;
    if (hang) return Completer<String>().future;
    return Future.value(
      jsonEncode({'payload': jsonEncode('captured'), 'material': null}),
    );
  }

  @override
  Future<void> cancelProxyWebView({required String bridgeName}) async {
    cancelledBridge = bridgeName;
  }
}

WebViewProxyEngine _engine(_FakeNative native) => WebViewProxyEngine(
      sourceHost: 'comix.to',
      allowedHosts: const ['comix.to'],
      native: native,
      logger: Logger(level: Level.off),
    );

void main() {
  test('pre-cancelled token skips the WebView and throws cancel', () async {
    final native = _FakeNative();
    final token = CancelToken()..cancel('gone');
    await expectLater(
      _engine(native).runInWebView(
        pageUrl: 'https://comix.to/title/x',
        html: '<html></html>',
        userAgent: 'test',
        buildScript: (pass, reject) => 'null',
        cancelToken: token,
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(native.runCalls, 0);
    expect(native.cancelledBridge, isNull);
  });

  test('mid-flight cancel aborts the native WebView and throws cancel',
      () async {
    final native = _FakeNative(hang: true);
    final token = CancelToken();
    final future = _engine(native).runInWebView(
      pageUrl: 'https://comix.to/title/x',
      html: '<html></html>',
      userAgent: 'test',
      buildScript: (pass, reject) => 'null',
      cancelToken: token,
    );
    // Let the request reach the native side before cancelling.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(native.runCalls, 1);
    token.cancel('stop');
    await expectLater(
      future,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(native.cancelledBridge, isNotNull);
  });

  test('no token still captures the payload', () async {
    final native = _FakeNative();
    final payload = await _engine(native).runInWebView(
      pageUrl: 'https://comix.to/title/x',
      html: '<html></html>',
      userAgent: 'test',
      buildScript: (pass, reject) => 'null',
    );
    expect(payload, '"captured"');
    expect(native.runCalls, 1);
    expect(native.cancelledBridge, isNull);
  });
}
