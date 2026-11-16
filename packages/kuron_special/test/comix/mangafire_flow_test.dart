import 'dart:convert';
import 'dart:io';

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
    expect(url.queryParameters['sort'], 'relevance:desc');
    expect(url.queryParameters.containsKey('rawParam'), isFalse);
    expect(url.queryParameters.keys.any((k) => k.startsWith('order[')), isFalse);
    expect(result.totalPages, 3);
    expect(arguments['bootstrapScript'], contains(arguments['captureScript']));
  });

  test('home page 2 pins page/sort lane and defaults language to en',
      () async {
    payload = {
      'items': [
        {'hid': '5x8p9', 'title': 'No Flag Title', 'type': 'manga'}
      ],
      'meta': {'page': 2, 'lastPage': 332, 'total': 9960, 'hasNext': true},
    };
    final result = await adapter.search(
      const SearchFilter(query: '', page: 2),
      config,
    );
    final url = Uri.parse(arguments['pageUrl'] as String);
    expect(url.path, '/browse');
    expect(url.queryParameters['page'], '2');
    expect(
      url.queryParameters['sort'],
      contains('chapter_updated_at'),
    );
    final capture = arguments['captureScript'] as String;
    expect(capture, contains('const targetPageNum = 2;'));
    expect(capture, contains('chapter_updated_at'));
    // No language flag on the item → default English (shows EN badge).
    expect(result.items.single.language, 'en');
    expect(result.hasNextPage, isTrue);
    expect(result.totalPages, 332);
  });

  test('detail uses title route, exposes chapter languages and real genre ids', () async {
    payload = {
      'data': {
        'hid': '81o3q',
        'title': 'Example',
        'languages': ['en', 'id'],
        'genres': [
          {'id': 26, 'title': 'Romance'},
          {'id': 1, 'title': 'Action'},
        ],
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
    final romanceTag =
        result.content.tags.firstWhere((tag) => tag.name == 'Romance');
    expect(romanceTag.id, 26);
    final actionTag =
        result.content.tags.firstWhere((tag) => tag.name == 'Action');
    expect(actionTag.id, 1);
    expect(
      result.content.tags
          .where((tag) => tag.type == '__mangafire_chapter_group')
          .map((tag) => tag.name),
      ['Chapter'],
    );
  });

  test('detail exposes volume group when hasVolumes is true', () async {
    payload = {
      'data': {
        'hid': '81o3q',
        'title': 'Example',
        'languages': ['en'],
        'hasVolumes': true,
        'genres': [],
      },
    };
    final result = await adapter.fetchDetail('title/81o3q', config);
    expect(
      result.content.tags
          .where((tag) => tag.type == '__mangafire_chapter_group')
          .map((tag) => tag.name),
      ['Chapter', 'Volume'],
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
    expect(chapters.first.language, 'id');
  });

  test(
      'chapters default to english when language is null and preserve language on Chapter',
      () async {
    payload = {
      'items': [
        {'id': 10, 'number': 1, 'language': 'en'},
        {'id': 11, 'number': 2, 'language': 'en'},
        {'id': 20, 'number': 1, 'language': 'es-la'},
      ],
    };
    final chapters = await adapter.fetchChapters('81o3q', config);
    expect(chapters.length, 2);
    expect(chapters.map((c) => c.title), ['Chapter 2', 'Chapter 1']);
    expect(chapters.every((c) => c.language == 'en'), isTrue);
  });

  test('chapters supports volume scanGroup and maps Volume entities', () async {
    payload = {
      'items': [
        {'id': 59147, 'number': 1, 'chapterCount': 6, 'language': 'en'},
        {'id': 59148, 'number': 2, 'chapterCount': 6, 'language': 'en'},
      ],
    };
    final volumes = await adapter.fetchChapters(
      '81o3q',
      config,
      scanGroup: 'Volume',
    );
    expect(volumes.length, 2);
    expect(volumes.first.id, 'vol-59148:81o3q');
    expect(volumes.first.title, 'Volume 2');
    expect(volumes.first.url, 'title/81o3q/volume/59148');
    expect(volumes.first.scanGroup, 'Volume');
    expect(arguments['captureScript'], contains('/volumes'));
  });

  test('chapters load more targets targetPage in capture script', () async {
    payload = {
      'items': [
        {'id': 30, 'number': 21, 'language': 'en'},
      ],
    };
    final chapters = await adapter.fetchChapters(
      '81o3q',
      config,
      page: 2,
    );
    expect(chapters.length, 1);
    expect(
      arguments['captureScript'],
      allOf(
        contains('const targetPage = 2;'),
        contains('onPageChange(targetPage)'),
        contains('parsed.meta.page === targetPage'),
      ),
    );
  });

  test('reader supports volume URLs and api markers', () async {
    payload = {
      'data': {
        'id': 59147,
        'pages': [
          {'url': 'https://cdn.example/vol1_p1.jpg'},
        ],
      },
    };
    final result = await adapter.fetchChapterImages('vol-59147:81o3q', config);
    expect(
      arguments['pageUrl'],
      'https://mangafire.to/title/81o3q/volume/59147',
    );
    expect(arguments['captureScript'], contains('/api/volumes/'));
    expect(result!.images, ['https://cdn.example/vol1_p1.jpg']);
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
