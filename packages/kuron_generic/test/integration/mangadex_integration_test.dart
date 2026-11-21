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

const _baseUrl = 'https://api.mangadex.org';
const _mangaId = '32d76d19-8a05-4db0-9fc2-e0b0648fe9d0';
const _chapterId = '0f3ea8af-cdbf-4dd9-a5a7-0f7c9f4e0a01';

const _config = {
  'source': 'mangadex',
  'baseUrl': _baseUrl,
  'defaultLanguage': 'english',
  'api': {
    'queryRules': {
      'search': {
        'enforceMultiValueParams': {
          'availableTranslatedLanguage[]': ['id', 'en', 'ja', 'zh'],
        },
        'ensureParams': {'hasAvailableChapters': 'true'},
      },
      'chapters': {
        'enforceMultiValueParams': {
          'translatedLanguage[]': ['id', 'en', 'ja', 'zh'],
        },
        'ensureMultiValueParamsIfMissing': {
          'contentRating[]': ['safe', 'suggestive', 'erotica', 'pornographic'],
        },
      },
    },
    'endpoints': {
      'allGalleries': '/manga?limit=30&offset={offset}&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh&order[followedCount]=desc&hasAvailableChapters=true',
      'search': '/manga?title={query}&limit=30&offset={offset}&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh&hasAvailableChapters=true',
      'detail': '/manga/{id}?includes[]=cover_art&includes[]=author&includes[]=artist',
    },
    'list': {
      'items': r'$.data[*]',
      'pagination': {
        'offsetMode': true,
        'total': {'path': r'$.total'},
        'limit': {'path': r'$.limit'},
        'offset': {'path': r'$.offset'},
        'pageSize': 30,
      },
      'fields': {
        'id': {'selector': r'$.id'},
        'title': {'selector': r'$.attributes.title'},
        'altTitles': {'selector': r'$.attributes.altTitles'},
        'description': {'selector': r'$.attributes.description'},
        'coverUrl': {
          'type': 'coverBuilder',
          'template':
              'https://mangadex.org/covers/{mangaId}/{fileName}.512.jpg',
          'mangaIdPath': r'$.id',
          'filenamePath':
              r"$.relationships[?(@.type=='cover_art')].attributes.fileName",
        },
        'tags': {
          'selector': r'$.attributes.tags[*].attributes.name.en',
          'multi': true,
        },
        'artists': {
          'selector': r"$.relationships[?(@.type=='artist')].attributes.name",
          'multi': true,
        },
        'status': {'selector': r'$.attributes.status'},
        'language': {'selector': r'$.attributes.originalLanguage'},
        'originalLanguage': {'selector': r'$.attributes.originalLanguage'},
        'availableTranslatedLanguages': {
          'selector': r'$.attributes.availableTranslatedLanguages[*]',
          'multi': true,
        },
        'pageCount': {'selector': r'$.attributes.lastChapter'},
      },
    },
    'detail': {
      'chapters': {
        'endpoint': '/chapter?manga={id}&limit=100&order[chapter]=desc&translatedLanguage[]=all&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic',
        'items': r'$.data[*]',
        'fallbackFields': {'language': r'$.attributes.translatedLanguage'},
        'fields': {
          'id': {'selector': r'$.id'},
          'chapterNum': {'selector': r'$.attributes.chapter'},
          'volume': {'selector': r'$.attributes.volume'},
          'language': {'selector': r'$.attributes.translatedLanguage'},
          'url': {'selector': r'$.id'},
          'date': {'selector': r'$.attributes.readableAt'},
        },
      },
      'fields': {
        'id': {'selector': r'$.data.id'},
        'title': {'selector': r'$.data.attributes.title'},
        'altTitles': {'selector': r'$.data.attributes.altTitles'},
        'description': {'selector': r'$.data.attributes.description'},
        'coverUrl': {
          'type': 'coverBuilder',
          'template':
              'https://mangadex.org/covers/{mangaId}/{fileName}.512.jpg',
          'mangaIdPath': r'$.data.id',
          'filenamePath': r"$.data.relationships[?(@.type=='cover_art')].attributes.fileName",
        },
        'status': {'selector': r'$.data.attributes.status'},
        'language': {'selector': r'$.data.attributes.originalLanguage'},
        'originalLanguage': {'selector': r'$.data.attributes.originalLanguage'},
        'availableTranslatedLanguages': {
          'selector': r'$.data.attributes.availableTranslatedLanguages[*]',
          'multi': true,
        },
        'pageCount': {'selector': r'$.data.attributes.lastChapter'},
        'uploadDate': {'selector': r'$.data.attributes.createdAt'},
      },
    },
    'statistics': {
      'followsEndpoint': '/statistics/manga/{id}',
      'followsPath': r'$.statistics.{id}.follows',
      'ratingPath': r'$.statistics.{id}.rating.average',
    },
    'images': {
      'mode': 'atHome',
      'atHomeEndpoint': '/at-home/server/{chapterId}',
    },
  },
};

const _listResponse = {
  'result': 'ok',
  'total': 1,
  'limit': 30,
  'offset': 0,
  'data': [
    {
      'id': _mangaId,
      'attributes': {
        'title': {'ko-ro': 'Na Honjaman Level-Up'},
        'altTitles': [
          {'ko': '나 혼자만 레벨업'},
          {'en': 'Solo Leveling'},
        ],
        'description': {'en': '10 years ago...'},
        'status': 'completed',
        'originalLanguage': 'ko',
        'lastChapter': '200',
      },
      'relationships': [
        {
          'type': 'cover_art',
          'attributes': {'fileName': 'e90bdc47-cover.jpg'},
        },
      ],
    },
  ],
};

const _detailResponse = {
  'result': 'ok',
  'data': {
    'id': _mangaId,
    'attributes': {
      'title': {'ko-ro': 'Na Honjaman Level-Up'},
      'altTitles': [
        {'en': 'Solo Leveling'},
      ],
      'description': {'en': '10 years ago...'},
      'status': 'completed',
      'originalLanguage': 'ko',
      'lastChapter': '200',
      'createdAt': '2024-05-01T00:00:00Z',
    },
    'relationships': [
      {
        'type': 'cover_art',
        'attributes': {'fileName': 'e90bdc47-cover.jpg'},
      },
    ],
  },
};

const _chaptersResponse = {
  'result': 'ok',
  'data': [
    {
      'id': _chapterId,
      'attributes': {
        'chapter': '200',
        'volume': '10',
        'translatedLanguage': 'en',
        'readableAt': '2025-01-01T00:00:00Z',
      },
    },
  ],
};

const _chaptersPage1Response = {
  'result': 'ok',
  'total': 150,
  'limit': 100,
  'offset': 0,
  'data': [
    {
      'id': 'page-1-chapter-id',
      'attributes': {
        'chapter': '120',
        'volume': '7',
        'translatedLanguage': 'en',
        'readableAt': '2025-01-01T00:00:00Z',
      },
    },
  ],
};

const _chaptersPage2Response = {
  'result': 'ok',
  'total': 150,
  'limit': 100,
  'offset': 100,
  'data': [
    {
      'id': 'page-2-chapter-id',
      'attributes': {
        'chapter': '20',
        'volume': '2',
        'translatedLanguage': 'id',
        'readableAt': '2024-06-01T00:00:00Z',
      },
    },
  ],
};

const _statsResponse = {
  'result': 'ok',
  'statistics': {
    _mangaId: {
      'follows': 3,
      'rating': {'average': 7.5},
    },
  },
};

const _atHomeResponse = {
  'result': 'ok',
  'baseUrl': 'https://uploads.mangadex.org',
  'chapter': {
    'hash': 'abc123hash',
    'data': ['1.jpg', '2.jpg'],
  },
};

const _searchPage2Response = {
  'result': 'ok',
  'total': 31,
  'limit': 30,
  'offset': 30,
  'data': [
    {
      'id': 'next-page-id',
      'attributes': {
        'title': {'en': 'Solo Leveling Side Story'},
        'altTitles': [
          {'en': 'Solo Leveling Side Story'},
        ],
        'description': {'en': 'Page 2 result'},
        'status': 'ongoing',
        'originalLanguage': 'ko',
        'lastChapter': '201',
      },
      'relationships': [
        {
          'type': 'cover_art',
          'attributes': {'fileName': 'cover-page-2.jpg'},
        },
      ],
    },
  ],
};

const _listNoCoverResponse = {
  'result': 'ok',
  'total': 1,
  'limit': 30,
  'offset': 0,
  'data': [
    {
      'id': 'no-cover-id',
      'attributes': {
        'title': {'en': 'No Cover Manga'},
        'altTitles': [
          {'en': 'No Cover Manga'},
        ],
        'description': {'en': 'No cover available'},
        'status': 'ongoing',
        'originalLanguage': 'en',
        'lastChapter': '12',
      },
      'relationships': [],
    },
  ],
};

const _listOriginalLanguageJaResponse = {
  'result': 'ok',
  'total': 1,
  'limit': 30,
  'offset': 0,
  'data': [
    {
      'id': 'ja-language-id',
      'attributes': {
        'title': {'en': 'Japanese Original'},
        'altTitles': [
          {'en': 'Japanese Original'},
        ],
        'originalLanguage': 'ja',
        'availableTranslatedLanguages': ['en', 'id'],
        'status': 'ongoing',
        'lastChapter': '20',
      },
      'relationships': [
        {
          'type': 'cover_art',
          'attributes': {'fileName': 'ja-cover.jpg'},
        },
      ],
    },
  ],
};

const _detailNoEnDescriptionResponse = {
  'result': 'ok',
  'data': {
    'id': _mangaId,
    'attributes': {
      'title': {'ko-ro': 'Na Honjaman Level-Up'},
      'altTitles': [
        {'en': 'Solo Leveling'},
      ],
      'description': {'de': 'Nur deutsche Beschreibung'},
      'status': 'completed',
      'originalLanguage': 'ko',
      'lastChapter': '200',
      'createdAt': '2024-05-01T00:00:00Z',
    },
    'relationships': [
      {
        'type': 'cover_art',
        'attributes': {'fileName': 'e90bdc47-cover.jpg'},
      },
    ],
  },
};

const _chaptersNoVolumeResponse = {
  'result': 'ok',
  'data': [
    {
      'id': _chapterId,
      'attributes': {
        'chapter': '15',
        'volume': '',
        'translatedLanguage': 'id',
        'readableAt': '2025-01-01T00:00:00Z',
      },
    },
  ],
};

const _emptyChaptersResponse = {'result': 'ok', 'data': []};

const _atHomeMissingHashResponse = {
  'result': 'ok',
  'baseUrl': 'https://uploads.mangadex.org',
  'chapter': {
    'data': ['1.jpg', '2.jpg'],
  },
};

const _atHomeDataSaverOnlyResponse = {
  'result': 'ok',
  'baseUrl': 'https://uploads.mangadex.org',
  'chapter': {
    'hash': 'abc123hash',
    'dataSaver': ['1.webp', '2.webp'],
  },
};

Map<String, dynamic> _cloneConfig() {
  return (jsonDecode(jsonEncode(_config)) as Map).cast<String, dynamic>();
}

Dio _buildDio() {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  return dio;
}

GenericRestAdapter _buildAdapter(Dio dio) {
  return GenericRestAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericJsonParser(logger: Logger(level: Level.off)),
    logger: Logger(level: Level.off),
    sourceId: 'mangadex',
  );
}

void main() {
  group('MangaDex integration', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late GenericRestAdapter adapter;

    setUp(() {
      dio = _buildDio();
      dioAdapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter = _buildAdapter(dio);
    });

    test('search maps altTitles.en title and cover URL from relationships', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&order[followedCount]=desc&hasAvailableChapters=true&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh',
        (server) => server.reply(200, _listResponse),
      );

      final result = await adapter.search(const SearchFilter(page: 1), _config);

      expect(result.items, hasLength(1));
      expect(result.items.first.title, 'Solo Leveling');
      expect(
        result.items.first.coverUrl,
        'https://mangadex.org/covers/$_mangaId/e90bdc47-cover.jpg.512.jpg',
      );
      expect(result.items.first.status, ContentStatus.completed);
      expect(result.items.first.totalChapters, 200);
      expect(result.totalPages, 1);
      expect(result.hasNextPage, isFalse);
    });

    test('search with query uses search endpoint and offset pagination', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga?title=solo+leveling&limit=30&offset=30&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&hasAvailableChapters=true&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh',
        (server) => server.reply(200, _searchPage2Response),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'solo leveling', page: 2),
        _config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'next-page-id');
      expect(result.items.first.title, 'Solo Leveling Side Story');
      expect(result.items.first.status, ContentStatus.ongoing);
      expect(result.items.first.totalChapters, 201);
      expect(result.hasNextPage, isFalse);
      expect(result.totalPages, 2);
    });

    test('raw search preserves included/excluded tag UUIDs and modes', () async {
      const expectedUrl =
          '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&hasAvailableChapters=true&includedTags[]=391b0423-d847-456f-aff0-8b0cfc03066b&excludedTags[]=5920b825-4181-4a17-beeb-9918b0ff7a30&excludedTags[]=a3c67850-4684-404e-9b7f-c69850ee5da6&includedTagsMode=AND&excludedTagsMode=OR&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh';

      dioAdapter.onGet(
        expectedUrl,
        (server) => server.reply(200, _listResponse),
      );

      final result = await adapter.search(
        const SearchFilter(
          query: 'raw:includedTags[]=391b0423-d847-456f-aff0-8b0cfc03066b&excludedTags[]=5920b825-4181-4a17-beeb-9918b0ff7a30&excludedTags[]=a3c67850-4684-404e-9b7f-c69850ee5da6&includedTagsMode=AND&excludedTagsMode=OR',
          page: 1,
        ),
        _config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, _mangaId);
      expect(result.items.first.title, 'Solo Leveling');
    });

    test('raw search preserves authorOrArtist UUID params', () async {
      const expectedAuthorUrl =
          '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&hasAvailableChapters=true&authorOrArtist=11111111-2222-3333-4444-555555555555&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh';
      const expectedArtistUrl =
          '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&hasAvailableChapters=true&authorOrArtist=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh';

      dioAdapter.onGet(
        expectedAuthorUrl,
        (server) => server.reply(200, _listResponse),
      );
      dioAdapter.onGet(
        expectedArtistUrl,
        (server) => server.reply(200, _listResponse),
      );

      final authorResult = await adapter.search(
        const SearchFilter(
          query: 'raw:authorOrArtist=11111111-2222-3333-4444-555555555555',
          page: 1,
        ),
        _config,
      );
      final artistResult = await adapter.search(
        const SearchFilter(
          query: 'raw:authorOrArtist=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          page: 1,
        ),
        _config,
      );

      expect(authorResult.items, hasLength(1));
      expect(authorResult.items.first.id, _mangaId);
      expect(artistResult.items, hasLength(1));
      expect(artistResult.items.first.id, _mangaId);
    });

    test('search handles missing cover relationship without crashing', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&order[followedCount]=desc&hasAvailableChapters=true&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh',
        (server) => server.reply(200, _listNoCoverResponse),
      );

      final result = await adapter.search(const SearchFilter(page: 1), _config);

      expect(result.items, hasLength(1));
      expect(result.items.first.coverUrl, isEmpty);
      expect(result.items.first.title, 'No Cover Manga');
    });

    test('search maps ja from originalLanguage without unknown fallback', () async {
      final configWithoutLanguage = _cloneConfig();
      final api =
          ((configWithoutLanguage['api'] as Map)['list'] as Map)['fields']
              as Map;
      api.remove('language');

      dioAdapter.onGet(
        '$_baseUrl/manga?limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&order[followedCount]=desc&hasAvailableChapters=true&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh',
        (server) => server.reply(200, _listOriginalLanguageJaResponse),
      );

      final result = await adapter.search(
        const SearchFilter(page: 1),
        configWithoutLanguage,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'ja-language-id');
      expect(result.items.first.language, 'ja');
      expect(result.items.first.language, isNot('unknown'));
    });

    test('detail maps favorites from statistics and chapter label', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.title, 'Solo Leveling');
      expect(result.content.favorites, 3);
      expect(result.content.status, ContentStatus.completed);
      expect(result.content.totalChapters, 200);
      expect(result.content.chapters, isNotNull);
      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.first.url, _chapterId);
      expect(result.content.chapters!.first.title, 'Vol.10 Ch.200');
      expect(result.content.chapters!.first.language, 'en');
      expect(result.content.subTitle, '10 years ago...');
      expect(
        result.content.coverUrl,
        'https://mangadex.org/covers/$_mangaId/e90bdc47-cover.jpg.512.jpg',
      );
    });

    test('detail still succeeds when statistics endpoint fails', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(500, {'result': 'error'}),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.id, _mangaId);
      expect(result.content.favorites, 0);
      expect(result.content.chapters, hasLength(1));
      expect(result.content.coverUrl, isNotEmpty);
    });

    test('detail description falls back to first available language key', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailNoEnDescriptionResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.subTitle, 'Nur deutsche Beschreibung');
    });

    test('detail chapter label falls back to Ch.X when volume missing', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersNoVolumeResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.first.title, 'Ch.15');
    });

    test(
      'reader at-home mode builds full image URLs from chapter hash',
      () async {
        dioAdapter.onGet(
          '$_baseUrl/at-home/server/$_chapterId',
          (server) => server.reply(200, _atHomeResponse),
        );

        final chapterData = await adapter.fetchChapterImages(
          _chapterId,
          _config,
        );

        expect(chapterData, isNotNull);
        expect(chapterData!.images, [
          'https://uploads.mangadex.org/data/abc123hash/1.jpg',
          'https://uploads.mangadex.org/data/abc123hash/2.jpg',
        ]);
      },
    );

    test('reader returns null when at-home response missing hash', () async {
      dioAdapter.onGet(
        '$_baseUrl/at-home/server/$_chapterId',
        (server) => server.reply(200, _atHomeMissingHashResponse),
      );

      final chapterData = await adapter.fetchChapterImages(_chapterId, _config);

      expect(chapterData, isNull);
    });

    test('reader falls back to dataSaver files when data is absent', () async {
      dioAdapter.onGet(
        '$_baseUrl/at-home/server/$_chapterId',
        (server) => server.reply(200, _atHomeDataSaverOnlyResponse),
      );

      final chapterData = await adapter.fetchChapterImages(_chapterId, _config);

      expect(chapterData, isNotNull);
      expect(chapterData!.images, [
        'https://uploads.mangadex.org/data-saver/abc123hash/1.webp',
        'https://uploads.mangadex.org/data-saver/abc123hash/2.webp',
      ]);
    });

    test('reader returns null when images config is absent', () async {
      final configNoImages = _cloneConfig();
      final api = (configNoImages['api'] as Map).cast<String, dynamic>();
      api.remove('images');

      final chapterData = await adapter.fetchChapterImages(
        _chapterId,
        configNoImages,
      );

      expect(chapterData, isNull);
    });

    test('language from SearchFilter is used for search endpoint', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga?title=solo&limit=30&offset=0&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=erotica&contentRating[]=pornographic&contentRating[]=suggestive&contentRating[]=safe&hasAvailableChapters=true&availableTranslatedLanguage[]=id&availableTranslatedLanguage[]=en&availableTranslatedLanguage[]=ja&availableTranslatedLanguage[]=zh',
        (server) => server.reply(200, _listResponse),
      );

      final result = await adapter.search(
        const SearchFilter(query: 'solo', page: 1, language: 'indonesian'),
        _config,
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.id, _mangaId);
    });

    test('chapter endpoint is language-agnostic for grouped display', () async {
      final idConfig = _cloneConfig();
      idConfig['defaultLanguage'] = 'indonesian';
      // With an explicit default language the adapter injects that single
      // code instead of the language-agnostic `all` sentinel.

      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=id',
        (server) => server.reply(200, _chaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, idConfig);

      expect(result.content.id, _mangaId);
      expect(result.content.chapters, hasLength(1));
    });

    test('detail chapters paginate with offset when total exceeds limit', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersPage1Response),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all&offset=100',
        (server) => server.reply(200, _chaptersPage2Response),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.chapters, hasLength(2));
      expect(result.content.chapters![0].id, 'page-1-chapter-id');
      expect(result.content.chapters![1].id, 'page-2-chapter-id');
      expect(result.content.chapters![1].title, 'Vol.2 Ch.20');
      expect(result.content.chapters![1].language, 'id');
    });

    test('detail chapters stop at first page when autoPaginate is false', () async {
      final firstPageOnlyConfig = _cloneConfig();
      final chaptersCfg =
          (((firstPageOnlyConfig['api'] as Map)['detail'] as Map)['chapters']
              as Map);
      chaptersCfg['autoPaginate'] = false;

      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersPage1Response),
      );

      final result = await adapter.fetchDetail(_mangaId, firstPageOnlyConfig);

      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.single.id, 'page-1-chapter-id');
    });

    test('detail returns empty chapter list when API has no chapters', () async {
      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _emptyChaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, _config);

      expect(result.content.chapters, isEmpty);
    });

    test('legacy translatedLanguage endpoint is normalized for grouping', () async {
      final legacyConfig = _cloneConfig();
      final detail = ((legacyConfig['api'] as Map)['detail'] as Map);
      final chapters = (detail['chapters'] as Map);
      chapters['endpoint'] = '/chapter?manga={id}&translatedLanguage[]={language}&limit=100&order[chapter]=desc';
      final chapterFields = (chapters['fields'] as Map);
      chapterFields.remove('language');

      dioAdapter.onGet(
        '$_baseUrl/manga/$_mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
        (server) => server.reply(200, _detailResponse),
      );
      dioAdapter.onGet(
        '$_baseUrl/statistics/manga/$_mangaId',
        (server) => server.reply(200, _statsResponse),
      );
      // `{language}` resolves to the `all` sentinel; query rules first add
      // contentRating, then the single-language injection appends the
      // translatedLanguage param at the end.
      dioAdapter.onGet(
        '$_baseUrl/chapter?manga=$_mangaId&limit=100&order[chapter]=desc&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic&translatedLanguage[]=all',
        (server) => server.reply(200, _chaptersResponse),
      );

      final result = await adapter.fetchDetail(_mangaId, legacyConfig);

      expect(result.content.chapters, hasLength(1));
      expect(result.content.chapters!.first.language, 'en');
    });
  });
}
