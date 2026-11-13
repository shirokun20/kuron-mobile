import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:kuron_special/src/generic_bypass/generic_bypass_source_factory.dart';
import 'package:kuron_special/src/webview_dom/webview_dom_reader_source.dart';
import 'package:kuron_special/src/webview_session/webview_session_adapter.dart';
import 'package:logger/logger.dart';

GenericBypassSourceFactory _factory() {
  final dir = Directory.systemTemp.createTempSync('webview_dom_factory');
  return GenericBypassSourceFactory(
    sourceId: 'komikcast',
    dio: Dio(),
    sessionAdapter: WebViewSessionAdapter(
      dio: Dio(),
      cookieJar: PersistCookieJar(storage: FileStorage(dir.path)),
      config: const WebViewSessionConfig(bypassEnabled: true),
      baseUrl: 'https://13.voratoon.com',
    ),
    logger: Logger(level: Level.off),
  );
}

Map<String, dynamic> _config({bool webviewDom = false}) => {
  'source': 'komikcast',
  'version': '1.2.5',
  'baseUrl': 'https://13.voratoon.com',
  'scraper': {
    'urlPatterns': {'chapter': '/{id}'},
    'selectors': {
      'reader': {
        if (webviewDom) 'mode': 'webviewDom',
        'images': {
          'selector': 'img[data-chapter-page]',
          'attribute': 'data-chapter-page',
        },
      },
    },
  },
};

void main() {
  test('reader without webviewDom stays GenericHttpSource', () {
    final source = _factory().create(_config());
    expect(source, isA<GenericHttpSource>());
    expect(source, isNot(isA<WebViewDomReaderSource>()));
  });

  test('reader with mode webviewDom wraps in decorator', () {
    final source = _factory().create(_config(webviewDom: true));
    expect(source, isA<WebViewDomReaderSource>());
    expect(source.id, 'komikcast');
  });
}
