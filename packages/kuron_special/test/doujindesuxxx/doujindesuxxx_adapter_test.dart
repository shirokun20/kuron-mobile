import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/src/doujindesuxxx/doujindesuxxx_source_factory.dart';

const _base = 'https://doujin.desu.xxx';

Map<String, dynamic> _manga({
  String slug = 'some-slug',
  String title = 'Some Title',
  String? terms,
  String? termList,
}) =>
    {
      'id': 'uuid-1',
      'slug': slug,
      'title': title,
      'cover_url': 'https://pic.desu.xxx/cover.webp',
      'status': 'completed',
      'type': 'doujinshi',
      'created_at': '2026-09-25T11:54:49.729Z',
      'chapter_count': 1,
      'manga_genres': [
        {
          'manga_id': 'uuid-1',
          'genre_id': 69,
          'genres': {'id': 69, 'name': 'Paizuri', 'slug': 'paizuri'},
        }
      ],
      if (terms != null) 'terms': terms,
      if (termList != null) 'term_list': termList,
    };

void main() {
  late Dio dio;
  late DioAdapter http;
  late DoujinDesuXxxAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _base, responseType: ResponseType.json));
    http = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    adapter = DoujinDesuXxxAdapter(dio: dio, sourceId: 'doujindesuxxx');
  });

  void onGetPath(String path, Object body) {
    http.onGet(_base + path, (server) => server.reply(200, body));
  }

  group('taxonomy browsing (content by tag)', () {
    test('genre tag routes to /api/taxonomy/genres and reads mangaList',
        () async {
      onGetPath(
        '/api/taxonomy/genres/sole-male?page=1&sort=latest&limit=30',
        {
          'term': {'id': 452, 'name': 'Sole Male', 'slug': 'sole-male'},
          'mangaList': [_manga(slug: 'a'), _manga(slug: 'b')],
          'pagination': {
            'total': 6769,
            'page': 1,
            'limit': 30,
            'totalPages': 226,
          },
        },
      );

      final res = await adapter.search(
        const SearchFilter(query: 'raw:taxonomy_genre=sole-male'),
        const {},
      );

      expect(res.items.map((c) => c.id), ['a', 'b']);
      expect(res.totalItems, 6769);
      expect(res.totalPages, 226);
      expect(res.hasNextPage, isTrue);
    });

    test('page and popular sort are forwarded (page-based, not offset)',
        () async {
      onGetPath(
        '/api/taxonomy/genres/sole-male?page=3&sort=popular&limit=30',
        {
          'mangaList': [_manga()],
          'pagination': {
            'total': 100,
            'page': 3,
            'limit': 30,
            'totalPages': 4,
          },
        },
      );

      final res = await adapter.search(
        const SearchFilter(
          query: 'raw:taxonomy_genre=sole-male&sort=popular',
          page: 3,
        ),
        const {},
      );

      expect(res.items.length, 1);
      expect(res.hasNextPage, isTrue);
    });

    test('last taxonomy page reports hasNextPage false', () async {
      onGetPath(
        '/api/taxonomy/genres/sole-male?page=4&sort=latest&limit=30',
        {
          'mangaList': [_manga()],
          'pagination': {
            'total': 100,
            'page': 4,
            'limit': 30,
            'totalPages': 4,
          },
        },
      );

      final res = await adapter.search(
        const SearchFilter(query: 'raw:taxonomy_genre=sole-male', page: 4),
        const {},
      );

      expect(res.hasNextPage, isFalse);
    });

    test('author name is slugified into the authors namespace', () async {
      onGetPath(
        '/api/taxonomy/authors/negita-shio?page=1&sort=latest&limit=30',
        {
          'term': {'id': 6017, 'name': 'Negita Shio', 'slug': 'negita-shio'},
          'mangaList': [_manga(slug: 'author-hit')],
          'pagination': {
            'total': 2,
            'page': 1,
            'limit': 30,
            'totalPages': 1,
          },
        },
      );

      final res = await adapter.search(
        const SearchFilter(query: 'raw:taxonomy_author=Negita Shio'),
        const {},
      );

      expect(res.items.single.id, 'author-hit');
      expect(res.hasNextPage, isFalse);
    });

    test('group name is slugified into the groups namespace', () async {
      onGetPath(
        '/api/taxonomy/groups/deppatsu-shinkoo?page=1&sort=latest&limit=30',
        {
          'mangaList': [_manga(slug: 'group-hit')],
          'pagination': {'total': 2, 'page': 1, 'limit': 30, 'totalPages': 1},
        },
      );

      final res = await adapter.search(
        const SearchFilter(query: 'raw:taxonomy_group=Deppatsu Shinkoo'),
        const {},
      );

      expect(res.items.single.id, 'group-hit');
    });

    test('junk term value (the site ships a "[]" genre) yields no request',
        () async {
      final res = await adapter.search(
        const SearchFilter(query: 'raw:taxonomy_genre=%5B%5D'),
        const {},
      );
      expect(res.items, isEmpty);
      expect(res.hasNextPage, isFalse);
    });

    test('SortOption.popular maps to the site sort, others to latest',
        () async {
      expect(DoujinDesuXxxAdapter.taxonomySort(SortOption.popular), 'popular');
      expect(DoujinDesuXxxAdapter.taxonomySort(SortOption.newest), 'latest');
      expect(DoujinDesuXxxAdapter.taxonomySort(SortOption.rating), 'latest');
      expect(DoujinDesuXxxAdapter.taxonomySort(null), 'latest');
    });
  });

  group('plain search paths are untouched', () {
    test('free text still uses offset pagination on /api/manga', () async {
      onGetPath('/api/manga?limit=30&offset=30&search=big+breast', [
        _manga(slug: 'text-hit'),
      ]);

      final res = await adapter.search(
        const SearchFilter(query: 'big breast', page: 2),
        const {},
      );

      expect(res.items.single.id, 'text-hit');
    });

    test('genre= slug filter still works from the search form', () async {
      onGetPath('/api/manga?limit=30&offset=0&genre=sole-male', [
        _manga(slug: 'form-hit'),
      ]);

      final res = await adapter.search(
        const SearchFilter(query: 'raw:genre=sole-male'),
        const {},
      );

      expect(res.items.single.id, 'form-hit');
    });

    test('mode:name artist prefix falls back to free text', () async {
      onGetPath('/api/manga?limit=30&offset=0&search=Some+Character', [
        _manga(slug: 'character-text'),
      ]);

      final res = await adapter.search(
        const SearchFilter(query: 'character:Some Character'),
        const {},
      );

      expect(res.items.single.id, 'character-text');
    });
  });

  group('term parsing', () {
    test('detail term_list fills artist/character/group/parody', () async {
      onGetPath('/api/manga/detail-slug', {
        ..._manga(
          slug: 'detail-slug',
          termList: 'Paizuri:genre:paizuri|N/A:character:n-a|'
              'Yomogi Mametaro:author:yomogi-mametaro|'
              'Original:series:original|diletta:group:diletta',
        ),
      });

      final detail = await adapter.fetchDetail('detail-slug', const {});
      final content = detail.content;

      expect(content.artists, ['Yomogi Mametaro']);
      expect(content.characters, isEmpty); // "N/A" is skipped
      expect(content.groups, ['diletta']);
      expect(content.parodies, ['Original']);
      // Genre tags come from manga_genres (id + slug) and must not duplicate.
      expect(content.tags.map((t) => t.name), contains('Paizuri'));
      expect(content.tags.map((t) => t.slug), contains('paizuri'));
    });

    test('list/search terms (genre only, comma separated) still parse',
        () async {
      onGetPath('/api/manga?limit=30&offset=0', [
        _manga(slug: 'list-hit', terms: 'Paizuri:genre,Anal:genre'),
      ]);

      final res = await adapter.search(const SearchFilter(), const {});
      final content = res.items.single;

      expect(content.tags.map((t) => t.name), containsAll(['Paizuri', 'Anal']));
      expect(content.artists, isEmpty);
    });
  });

  group('helpers', () {
    test('slugifyTerm normalizes names and strips junk', () {
      expect(DoujinDesuXxxAdapter.slugifyTerm('Negita Shio'), 'negita-shio');
      expect(DoujinDesuXxxAdapter.slugifyTerm('  Sole   Male  '), 'sole-male');
      expect(DoujinDesuXxxAdapter.slugifyTerm('X-Ray'), 'x-ray');
      expect(DoujinDesuXxxAdapter.slugifyTerm('[]'), isEmpty);
      expect(DoujinDesuXxxAdapter.slugifyTerm('already-slug'), 'already-slug');
    });

    test('stripTermPrefix only drops known taxonomy type prefixes', () {
      expect(DoujinDesuXxxAdapter.stripTermPrefix('artist:Bob'), 'Bob');
      expect(DoujinDesuXxxAdapter.stripTermPrefix('group:AC'), 'AC');
      expect(DoujinDesuXxxAdapter.stripTermPrefix('genre:Sole Male'),
          'genre:Sole Male');
      expect(DoujinDesuXxxAdapter.stripTermPrefix('plain text'), 'plain text');
    });
  });

  group('genre id resolution still works', () {
    test('numeric genre id from the picker form resolves to a slug', () async {
      onGetPath('/api/genres?limit=1000', [
        {'id': 174, 'name': 'Age Progression', 'slug': 'age-progression'},
      ]);
      onGetPath('/api/manga?limit=30&offset=0&genre=age-progression', [
        _manga(slug: 'numeric-hit'),
      ]);

      final res = await adapter.search(
        const SearchFilter(query: 'raw:genre=174'),
        const {},
      );

      expect(res.items.single.id, 'numeric-hit');
    });
  });
}
