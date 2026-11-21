library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/adapters/generic_rest_adapter.dart';
import 'package:kuron_generic/src/parsers/generic_json_parser.dart';
import 'package:kuron_generic/src/url_builder/generic_url_builder.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://api.voratoon.com';
const _slug = 'atm-ojisan-isekai-de-mote-ki-ga-tomaranai';

const _searchTemplate =
    '/series?takeChapter=2&includeMeta=true&sort={sort}&sortOrder=desc&take=12&page={page}&filter=title=ilike="{query}",nativeTitle=ilike="{query}"';

const _config = {
  'source': 'komikcast',
  'baseUrl': 'https://v2.komikcast.fit',
  'defaultLanguage': 'indonesian',
  'api': {
    'url': _baseUrl,
    'endpoints': {
      'allGalleries': {
        'path': '/series',
        'params': {
          'includeMeta': 'true',
          'sort': 'latest',
          'sortOrder': 'desc',
          'take': '12',
          'page': '{page}',
        },
      },
      'search': {
        'path': '/series',
        'params': {
          'takeChapter': '2',
          'includeMeta': 'true',
          'sort': '{sort}',
          'sortOrder': 'desc',
          'take': '12',
          'page': '{page}',
          'filter': 'title=ilike="{query}",nativeTitle=ilike="{query}"',
        },
      },
      'tagSearch': {
        'path': '/series',
        'params': {
          'genreIds': '{tagId}',
          'takeChapter': '2',
          'includeMeta': 'true',
          'sort': '{sort}',
          'sortOrder': 'desc',
          'take': '12',
          'page': '{page}',
        },
      },
      'detail': {'path': '/series/{id}'},
      'images': {'path': '/series/{id}/chapters/{chapter}'},
    },
    'list': {
      'items': r'$.data[*]',
      'pagination': {
        'currentPage': {'path': r'$.meta.page'},
        'totalPages': {'path': r'$.meta.lastPage'},
      },
      'fields': {
        'id': {'selector': r'$.data.slug'},
        'title': {'selector': r'$.data.title'},
        'coverUrl': {'selector': r'$.data.coverImage'},
      },
    },
    'detail': {
      'fields': {
        'id': {'selector': r'$.data.data.slug'},
        'title': {'selector': r'$.data.data.title'},
        'description': {'selector': r'$.data.data.synopsis'},
        'coverUrl': {'selector': r'$.data.data.coverImage'},
        'status': {'selector': r'$.data.data.status'},
        'tags': {'selector': r'$.data.data.genres[*].data.name', 'multi': true},
        'pageCount': {'selector': r'$.data.data.totalChapters'},
      },
      'chapters': {
        'endpoint': '/series/{id}/chapters',
        'items': r'$.data[*]',
        'fields': {
          'id': {'selector': r'$.data.index'},
          'chapterNum': {'selector': r'$.data.index'},
          'url': {'selector': r'$.data.index'},
          'date': {'selector': r'$.createdAt'},
        },
        'composeIdWithContentId': true,
      },
    },
    'images': {
      'mode': 'direct',
      'items': r'$.data.data.images[*]',
      'urlPath': r'$',
    },
  },
  'searchConfig': {
    'sortingConfig': {
      'options': [
        {'value': 'newest', 'apiValue': 'latest'},
        {'value': 'popular', 'apiValue': 'popularity'},
        {'value': 'rating', 'apiValue': 'rating'},
      ],
    },
  },
};

const _searchResponse = {
  'status': 200,
  'message': 'ok',
  'meta': {'total': 10043, 'page': 2, 'lastPage': 5022},
  'data': [
    {
      'data': {
        'slug': _slug,
        'title': 'ATM Ojisan: Isekai de Mote-ki ga Tomaranai!',
        'coverImage': 'https://example.com/cover.webp',
      },
    },
  ],
};

const _detailResponse = {
  'status': 200,
  'message': 'ok',
  'data': {
    'data': {
      'slug': _slug,
      'title': 'ATM Ojisan: Isekai de Mote-ki ga Tomaranai!',
      'synopsis': 'detail synopsis',
      'status': 'ongoing',
      'totalChapters': '17',
      'coverImage': 'https://example.com/cover.webp',
      'genres': [
        {
          'data': {'name': 'Action'},
        },
      ],
    },
  },
};

const _chaptersResponse = {
  'status': 200,
  'message': 'ok',
  'data': [
    {
      'createdAt': '2026-05-27T10:23:03.400+07:00',
      'data': {'index': 17},
    },
    {
      'createdAt': '2026-05-20T10:23:03.400+07:00',
      'data': {'index': 16},
    },
  ],
};

const _imagesResponse = {
  'status': 200,
  'message': 'ok',
  'data': {
    'data': {
      'images': [
        'https://sv1.imgkc1.my.id/wp-content/img/A/ATM/017/001.jpg',
        'https://sv1.imgkc1.my.id/wp-content/img/A/ATM/017/002.jpg',
      ],
    },
  },
};

Dio _buildDio() => Dio(BaseOptions(baseUrl: _baseUrl));

GenericRestAdapter _buildAdapter(Dio dio) {
  return GenericRestAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericJsonParser(logger: Logger(level: Level.off)),
    logger: Logger(level: Level.off),
    sourceId: 'komikcast',
  );
}

void main() {
  group('Komikcast REST integration', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericRestAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('search uses endpoint params and parses pagination', () async {
      final expectedUrl = const GenericUrlBuilder(baseUrl: _baseUrl)
          .buildSearchUrl(
            _searchTemplate,
            const SearchFilter(query: 'atm', page: 2, sort: SortOption.newest),
            sortValue: 'newest',
          );

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_searchResponse))),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'atm', page: 2, sort: SortOption.newest),
        _config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, _slug);
      expect(result.items.first.language, 'indonesian');
      expect(result.totalPages, 5022);
      expect(result.hasNextPage, isTrue);
    });

    test('raw genre tag query uses tagSearch endpoint instead of text filter', () async {
      const expectedUrl =
          '$_baseUrl/series?genreIds=Ecchi&takeChapter=2&includeMeta=true&sort=newest&sortOrder=desc&take=12&page=1';

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_searchResponse))),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:genreIds=Ecchi',
          page: 1,
          sort: SortOption.newest,
        ),
        _config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, _slug);
    });

    test('raw text query fills endpoint filter placeholder', () async {
      const expectedUrl =
          '$_baseUrl/series?takeChapter=2&includeMeta=true&sortOrder=desc&take=12&page=1&filter=title%3Dilike%3D%22neko%22%2CnativeTitle%3Dilike%3D%22neko%22&sort=popular';

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_searchResponse))),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:query=neko',
          page: 1,
          sort: SortOption.popular,
        ),
        _config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, _slug);
    });

    test('raw text sort follows filter sort value', () async {
      const expectedUrl =
          '$_baseUrl/series?takeChapter=2&includeMeta=true&sortOrder=desc&take=12&page=1&filter=title%3Dilike%3D%22neko%22%2CnativeTitle%3Dilike%3D%22neko%22&sort=rating';

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_searchResponse))),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:query=neko',
          page: 1,
          sort: SortOption.rating,
        ),
        _config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, _slug);
    });

    test('stale raw sort is overridden by filter sort', () async {
      const expectedUrl =
          '$_baseUrl/series?takeChapter=2&includeMeta=true&sortOrder=desc&take=12&page=1&filter=title%3Dilike%3D%22neko%22%2CnativeTitle%3Dilike%3D%22neko%22&sort=popular';

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_searchResponse))),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:query=neko&sort=latest',
          page: 1,
          sort: SortOption.popular,
        ),
        _config,
      );

      expect(result.items, isNotEmpty);
      expect(result.items.first.id, _slug);
    });

    test('detail parses chapters and composes chapter id for reader', () async {
      final detailUrl = const GenericUrlBuilder(baseUrl: _baseUrl)
          .buildDetailUrl('/series/{id}', _slug);
      final chaptersUrl = const GenericUrlBuilder(
        baseUrl: _baseUrl,
      ).buildDetailUrl('/series/{id}/chapters?translatedLanguage[]=id', _slug);

      dioAdapter.onGet(
        detailUrl,
        (server) => server.reply(200, jsonDecode(jsonEncode(_detailResponse))),
      );
      dioAdapter.onGet(
        chaptersUrl,
        (server) =>
            server.reply(200, jsonDecode(jsonEncode(_chaptersResponse))),
      );

      final result = await adapter.fetchDetail(_slug, _config);

      expect(
        result.content.title,
        'ATM Ojisan: Isekai de Mote-ki ga Tomaranai!',
      );
      expect(result.content.language, 'indonesian');
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, hasLength(2));
      expect(result.content.chapters!.first.id, '$_slug/17');
      expect(result.content.chapters!.first.title, 'Ch.17');
    });

    test(
      'chapter images resolve composite chapter id with endpoint placeholders',
      () async {
        const chapterId = '$_slug/17';
        const expectedUrl = '$_baseUrl/series/$_slug/chapters/17';

        dioAdapter.onGet(
          expectedUrl,
          (server) =>
              server.reply(200, jsonDecode(jsonEncode(_imagesResponse))),
        );

        final result = await adapter.fetchChapterImages(chapterId, _config);

        expect(result, isNotNull);
        expect(result!.images, hasLength(2));
        expect(
          result.images.first,
          'https://sv1.imgkc1.my.id/wp-content/img/A/ATM/017/001.jpg',
        );
      },
    );

    test(
      'chapter images supports selector object config (no map cast)',
      () async {
        const chapterId = '$_slug/17';
        const expectedUrl = '$_baseUrl/series/$_slug/chapters/17';

        dioAdapter.onGet(
          expectedUrl,
          (server) =>
              server.reply(200, jsonDecode(jsonEncode(_imagesResponse))),
        );

        final configWithObjectSelector =
            jsonDecode(jsonEncode(_config)) as Map<String, dynamic>;
        final api = configWithObjectSelector['api'] as Map<String, dynamic>;
        final images = api['images'] as Map<String, dynamic>;
        images['items'] = {'path': r'$.data.data.images[*]'};
        images['urlPath'] = {'path': r'$'};

        final result = await adapter.fetchChapterImages(
          chapterId,
          configWithObjectSelector,
        );

        expect(result, isNotNull);
        expect(result!.images, hasLength(2));
        expect(
          result.images[1],
          'https://sv1.imgkc1.my.id/wp-content/img/A/ATM/017/002.jpg',
        );
      },
    );
  });
}
