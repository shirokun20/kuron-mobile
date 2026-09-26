library;

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_rest_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_json_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

const _baseUrl = 'https://mangafire.to';
const _mangaId = 'manga123';
const _chapterId = 'chap123';

const _listResponse = {
  'items': [
    {
      'hid': _mangaId,
      'title': 'Test Manga',
      'poster': {'large': 'https://img.mangafire.to/manga1.jpg'},
      'status': 'ongoing',
      'type': 'manga',
      'latestChapter': 50
    }
  ],
  'meta': {'currentPage': 1, 'hasNext': true}
};

const _detailResponse = {
  'data': {
    'hid': _mangaId,
    'title': 'Test Manga Detail',
    'synopsisHtml': 'This is a test synopsis.',
    'poster': {'large': 'https://img.mangafire.to/manga1.jpg'},
    'status': 'ongoing',
    'type': 'manga',
    'genres': [
      {'title': 'Action'},
      {'title': 'Adventure'}
    ],
    'authors': [
      {'title': 'Test Author'}
    ],
    'languages': ['en', 'id'],
    'createdAt': '2023-01-01T00:00:00Z'
  }
};

const _chaptersResponse = {
  'items': [
    {
      'id': _chapterId,
      'number': '1.0',
      'name': 'The Beginning',
      'createdAt': '2023-01-01T00:00:00Z'
    }
  ]
};

const _imagesResponse = {
  'data': {
    'pages': [
      {'url': 'https://img.mangafire.to/page1.jpg'},
      {'url': 'https://img.mangafire.to/page2.jpg'}
    ]
  }
};

String? lastRequestedUri;

class MockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri.toString();
    lastRequestedUri = uri;
    if (uri.contains('/api/titles/$_mangaId/chapters')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: _chaptersResponse,
      ));
    } else if (uri.contains('/api/titles/$_mangaId')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: _detailResponse,
      ));
    } else if (uri.contains('/api/titles')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: _listResponse,
      ));
    } else if (uri.contains('/api/chapters/$_chapterId')) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: _imagesResponse,
      ));
    } else {
      handler.reject(DioException(
        requestOptions: options,
        error: 'Unhandled mocked route: $uri',
      ));
    }
  }
}

void main() {
  group('MangaFire REST Adapter Integration', () {
    late Dio dio;
    late GenericRestAdapter adapter;
    late Map<String, dynamic> config;

    setUp(() async {
      config = (await loadConfigRemote('mangafire-config.json'))
          .cast<String, dynamic>();

      dio = Dio();
      dio.interceptors.add(MockInterceptor());

      final logger = Logger(printer: PrettyPrinter(methodCount: 0));

      adapter = GenericRestAdapter(
        sourceId: 'mangafire',
        dio: dio,
        logger: logger,
        urlBuilder: GenericUrlBuilder(baseUrl: _baseUrl),
        parser: GenericJsonParser(logger: logger),
      );
    });

    test('search returns parsed items and hasNextPage', () async {
      final result = await adapter.search(
        const SearchFilter(query: '', page: 1, sort: SortOption.popular),
        config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, _mangaId);
      expect(result.items.first.title, 'Test Manga');
      expect(result.hasNextPage, isTrue);
      
      expect(lastRequestedUri, isNotNull);
      // Native sort only works if '{sort}' or 'sort=' is in the URL template. 
      // If the user removed it from config, it won't be appended.
      if (config['api']['endpoints']['allGalleries'].contains('{sort}')) {
        expect(Uri.decodeComponent(lastRequestedUri!), contains('order[views_total]=desc'));
      }
    });

    test('search with keyword and native sort', () async {
      await adapter.search(
        const SearchFilter(query: 'naruto', page: 2, sort: SortOption.newest),
        config,
      );

      expect(lastRequestedUri, isNotNull);
      if (config['api']['endpoints']['search'].contains('{sort}')) {
        expect(Uri.decodeComponent(lastRequestedUri!), contains('order[created_at]=desc'));
      }
      expect(lastRequestedUri, contains('keyword=naruto'));
      expect(lastRequestedUri, contains('page=2'));
    });

    test('search with dynamic UI rawParam sorting', () async {
      await adapter.search(
        const SearchFilter(
          query: 'naruto', 
          page: 1, 
          radioGroupSelections: {
            'rawParam': 'order[views_total]=desc'
          }
        ),
        config,
      );

      expect(lastRequestedUri, isNotNull);
      // Validate that the rawParam is injected into the URL!
      // Uri.toString() encodes '[' and ']', so we decode it for assertion
      expect(Uri.decodeComponent(lastRequestedUri!), contains('order[views_total]=desc'));
      expect(lastRequestedUri, contains('keyword=naruto'));
      expect(lastRequestedUri, contains('page=1'));
    });

    test('fetchDetail returns parsed detail with tags and languages', () async {
      final result = await adapter.fetchDetail(_mangaId, config);

      expect(result.content.id, _mangaId);
      expect(result.content.title, 'Test Manga Detail');
      expect(result.content.hasTag('Action'), isTrue);
      expect(result.content.hasTag('Adventure'), isTrue);
      expect(result.content.hasArtist('Test Author'), isTrue);
    });

    test('fetchChapters returns parsed chapters for language', () async {
      final chapters =
          await adapter.fetchChapters(_mangaId, config, language: 'en');

      expect(chapters, hasLength(1));
      expect(
          chapters.first.id, 'https://mangafire.to/api/chapters/$_chapterId');
      expect(chapters.first.title, 'Ch.1.0');
    });

    test('fetchChapterImages returns direct image urls', () async {
      final images = await adapter.fetchChapterImages(
        'https://mangafire.to/api/chapters/$_chapterId',
        config,
      );
      expect(images, isNotNull);
      expect(images!.images, hasLength(2));
      expect(images.images.first, 'https://img.mangafire.to/page1.jpg');
    });
  });
}
