library;

import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  group('manga18.club config contract', () {
    late Map<String, dynamic> config;
    late Map<String, dynamic> scraper;
    late Map<String, dynamic> urlPatterns;
    late Map<String, dynamic> selectors;

    setUpAll(() async {
      config = (await loadConfigRemote('manga18.club-config.json'))
          .cast<String, dynamic>();
      scraper = (config['scraper'] as Map).cast<String, dynamic>();
      urlPatterns = (scraper['urlPatterns'] as Map).cast<String, dynamic>();
      selectors = (scraper['selectors'] as Map).cast<String, dynamic>();
    });

    test('chapter URL template only uses {id}', () {
      expect(urlPatterns['chapter'], '/manhwa/{id}');
      expect((urlPatterns['chapter'] as String).contains('{chapter}'), isFalse);
    });

    test('home list is scoped to recoment_box cards', () {
      final home = (urlPatterns['home'] as Map).cast<String, dynamic>();
      final list = (home['list'] as Map).cast<String, dynamic>();
      expect(list['container'], contains('.recoment_box'));

      final fields = (list['fields'] as Map).cast<String, dynamic>();
      expect((fields['title'] as Map)['selector'], '.mg_name a');
      expect((fields['coverUrl'] as Map)['selector'], '.story_images img');
    });

    test('detail chapter IDs are extracted with regex, not transform:slug', () {
      final detail = (selectors['detail'] as Map).cast<String, dynamic>();
      final chapters = (detail['chapters'] as Map).cast<String, dynamic>();
      final fields = (chapters['fields'] as Map).cast<String, dynamic>();
      final idDef = (fields['id'] as Map).cast<String, dynamic>();

      expect(idDef['attribute'], 'href');
      expect(
        idDef['regex'],
        r'/manhwa/([^/?#]+/[^/?#]+)',
      );
      expect(idDef.containsKey('transform'), isFalse);
    });

    test('reader is wired to chapter_boxImages and regex-based nav parsing',
        () {
      final reader = (selectors['reader'] as Map).cast<String, dynamic>();
      expect(reader['container'], contains('.chapter_boxImages'));
      expect(
        ((reader['images'] as Map)['selector'] as String),
        contains('.chapter_boxImages img'),
      );

      final nav = (reader['nav'] as Map).cast<String, dynamic>();
      final next = (nav['next'] as Map).cast<String, dynamic>();
      final prev = (nav['prev'] as Map).cast<String, dynamic>();

      expect(next['selector'], 'script');
      expect(prev['selector'], 'script');
      expect((next['regex'] as String), contains('next_chapter'));
      expect((prev['regex'] as String), contains('prev_chapter'));
    });

    test('search form uses live search query param names', () {
      final searchForm = (config['searchForm'] as Map).cast<String, dynamic>();
      final params = (searchForm['params'] as Map).cast<String, dynamic>();
      final query = (params['query'] as Map).cast<String, dynamic>();
      final page = (params['page'] as Map).cast<String, dynamic>();

      expect(urlPatterns['search'], isA<Map>());
      expect(urlPatterns['searchPage'], isA<Map>());
      expect((query['queryParam'] as String), 'search');
      expect((page['queryParam'] as String), 'page');
      expect(
        ((urlPatterns['search'] as Map)['url'] as String),
        '/list-manga/?search={query}',
      );
      expect(
        ((urlPatterns['searchPage'] as Map)['url'] as String),
        '/list-manga/?search={query}&page={page}',
      );
    });
  });
}
