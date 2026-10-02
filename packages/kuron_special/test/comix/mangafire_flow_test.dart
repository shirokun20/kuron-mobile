import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/src/comix/comix_adapter.dart';
import 'package:kuron_special/src/webview_proxy/webview_proxy_engine.dart';
import 'package:logger/logger.dart';

class _ShellClient implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('<html><head></head><body></body></html>', 200);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = {'source': 'mangafire', 'baseUrl': 'https://mangafire.to'};
  const channel = MethodChannel('kuron_native');
  late ComixAdapter adapter;
  late Map<String, dynamic> arguments;
  late Object payload;

  setUp(() {
    arguments = {};
    payload = {};
    adapter = ComixAdapter(
      dio: Dio()..httpClientAdapter = _ShellClient(),
      engine: WebViewProxyEngine(
        sourceHost: 'mangafire.to',
        allowedHosts: mangafireAllowedHosts,
        logger: Logger(level: Level.off),
      ),
      logger: Logger(level: Level.off),
      defaultBaseUrl: 'https://mangafire.to',
      defaultSourceId: 'mangafire',
      originKind: 'mangafire',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'runProxyWebView');
      arguments = Map<String, dynamic>.from(call.arguments as Map);
      return jsonEncode({'payload': jsonEncode(payload), 'material': null});
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('browse preserves keyword and page, captures before SPA modules',
      () async {
    payload = {
      'items': [
        {'hid': '81o3q', 'title': 'Example'}
      ],
      'meta': {'page': 2, 'lastPage': 3, 'total': 61, 'hasNext': true},
    };
    final result = await adapter.search(
      const SearchFilter(query: 'one piece', page: 2),
      config,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['keyword'], 'one piece');
    expect(url.queryParameters['page'], '2');
    expect(result.totalPages, 3);
    expect(arguments['bootstrapScript'], contains(arguments['captureScript']));
  });

  test('detail uses title route and exposes chapter languages', () async {
    payload = {
      'data': {
        'hid': '81o3q',
        'title': 'Example',
        'languages': ['en', 'id'],
      },
    };
    final result = await adapter.fetchDetail('title/81o3q', config);
    expect(arguments['pageUrl'], 'https://mangafire.to/title/81o3q');
    expect(
      result.content.tags
          .where((tag) => tag.type == '__mangafire_chapter_language')
          .map((tag) => tag.name),
      ['en', 'id'],
    );
  });

  test('chapters sort numerically and persist reader context', () async {
    payload = {
      'items': [
        {'id': 90, 'number': 9, 'language': 'id'},
        {'id': 100, 'number': 10, 'language': 'id'},
        {'id': 20, 'number': 2, 'language': 'en'},
      ],
    };
    final chapters =
        await adapter.fetchChapters('81o3q', config, language: 'id');
    expect(arguments['pageUrl'], 'https://mangafire.to/title/81o3q');
    expect(chapters.map((c) => c.title), ['Chapter 10', 'Chapter 9']);
    expect(chapters.first.id, '100:81o3q');
    expect(chapters.first.url, 'title/81o3q/chapter/100');
    expect(chapters.first.scanGroup, 'Chapter');
  });

  test('reader works without chapter cache and preserves plain CDN URLs',
      () async {
    payload = {
      'data': {
        'id': 100,
        'pages': List.generate(
          4,
          (i) => {
            'url': 'https://cdn.example/$i.jpg',
            'width': 800,
            'height': 1200
          },
        ),
      },
    };
    final result = await adapter.fetchChapterImages('100:81o3q', config);
    expect(
        arguments['pageUrl'], 'https://mangafire.to/title/81o3q/chapter/100');
    expect(result!.images, [
      'https://cdn.example/0.jpg',
      'https://cdn.example/1.jpg',
      'https://cdn.example/2.jpg',
      'https://cdn.example/3.jpg',
    ]);
  });

  test('invalid or empty reader payload is not successful empty data',
      () async {
    payload = {
      'data': {'id': 100, 'pages': []},
    };
    await expectLater(
      adapter.fetchChapterImages('100:81o3q', config),
      throwsFormatException,
    );
  });

  test('legacy numeric reader id fails explicitly without title context',
      () async {
    await expectLater(
      adapter.fetchChapterImages('100', config),
      throwsFormatException,
    );
    expect(arguments, isEmpty);
  });

  // Optional local probe exports the exact production scripts, not a JS rewrite.
  test('export production scripts for browser verification', () async {
    final directory = Platform.environment['MANGAFIRE_PROBE_DIR'];
    if (directory == null) return;
    payload = {'items': []};
    await adapter.search(const SearchFilter(), config);
    await File('$directory/browse.json').writeAsString(jsonEncode(arguments));
    payload = {
      'data': {
        'hid': '81o3q',
        'title': 'Example',
        'languages': ['en']
      },
    };
    await adapter.fetchDetail('81o3q', config);
    await File('$directory/detail.json').writeAsString(jsonEncode(arguments));
    payload = {'items': []};
    await adapter.fetchChapters('81o3q', config);
    await File('$directory/chapters.json').writeAsString(jsonEncode(arguments));
    payload = {
      'data': {
        'id': 9463350,
        'pages': [
          {'url': 'https://cdn.example/1.jpg'}
        ],
      },
    };
    await adapter.fetchChapterImages('9463350:81o3q', config);
    await File('$directory/reader.json').writeAsString(jsonEncode(arguments));
  });
}
