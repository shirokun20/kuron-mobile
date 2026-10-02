// Tag identity for artist/author split (nhentai-artist-author-split 1.1/1.2).
//
// The nhentai v2 payload carries `id`/`slug`/`url` per tag object
// (e.g. artist `koari` -> `/artist/koari/`). Both parse paths must keep them
// so creator taps can resolve `tag_id` without re-guessing.
//
// Dio is mocked ([DioAdapter]); no real HTTP calls are made.
library;

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:kuron_generic/src/mappers/generic_content_mapper.dart';
import 'package:test/test.dart';

const _baseUrl = 'https://nhentai.net';

GenericRestAdapter _buildAdapter(Dio dio) {
  return GenericRestAdapter(
    dio: dio,
    urlBuilder: const GenericUrlBuilder(baseUrl: _baseUrl),
    parser: GenericJsonParser(logger: Logger(level: Level.off)),
    logger: Logger(level: Level.off),
    sourceId: 'nhentai',
  );
}

final Map<String, dynamic> _config = {
  'source': 'nhentai',
  'baseUrl': _baseUrl,
  'api': {
    'endpoints': {
      'galleryDetail': '/api/v2/galleries/{id}',
    },
  },
  'selectors': {
    'id': {'selector': r'$.id'},
    'tagObjects': {'selector': r'$.tags[*]'},
    'pageCount': {'selector': r'$.num_pages'},
    'uploadDate': {'selector': r'$.upload_date'},
  },
};

Map<String, dynamic> _galleryJson() => {
      'id': 1,
      'media_id': '9',
      'title': {'english': 'Eat The Rich!', 'pretty': 'Eat The Rich!'},
      'num_pages': 20,
      'num_favorites': 5,
      'upload_date': 1403964737,
      'tags': [
        {
          'id': 9063,
          'type': 'artist',
          'name': 'koari',
          'slug': 'koari',
          'url': '/artist/koari/',
          'count': 53,
        },
        {
          'id': 6346,
          'type': 'language',
          'name': 'japanese',
          'slug': 'japanese',
          'url': '/language/japanese/',
          'count': 341399,
        },
      ],
    };

void main() {
  group('nhentai tag identity (artist split)', () {
    test('1.1 _parseTagObjects keeps id/slug/url via fetchDetail', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final dioAdapter =
          DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      dioAdapter.onGet(
        '$_baseUrl/api/v2/galleries/1',
        (s) => s.reply(200, _galleryJson()),
      );
      final adapter = _buildAdapter(dio);

      final detail = await adapter.fetchDetail('1', _config);
      final artist =
          detail.content.tags.firstWhere((t) => t.type == 'artist');

      expect(artist.name, 'koari');
      expect(artist.id, 9063);
      expect(artist.slug, 'koari');
      expect(artist.url, '/artist/koari/');
      expect(detail.content.artists, contains('koari'));
    });

    test('1.2 splitTagObjects keeps url on artist tags', () {
      final split = GenericContentMapper.splitTagObjects([
        {
          'id': 9063,
          'name': 'koari',
          'type': 'artist',
          'slug': 'koari',
          'url': '/artist/koari/',
          'count': 53,
        },
      ]);

      expect(split.tags.single.url, '/artist/koari/');
      expect(split.tags.single.slug, 'koari');
      expect(split.artists, ['koari']);
    });

    test('1.2 missing url degrades to empty string', () {
      final split = GenericContentMapper.splitTagObjects([
        {'id': 1, 'name': 'x', 'type': 'artist', 'count': 0},
      ]);

      expect(split.tags.single.url, '');
    });
  });
}
