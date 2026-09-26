import 'package:test/test.dart';

import '../support/config_test_harness.dart';



void main() {
  group('MangaDex Config Schema Validation', () {
    late Map<String, dynamic> config;

    setUpAll(() async {
      config = (await loadConfigRemote('mangadex-config.json'))
          .cast<String, dynamic>();
    });

    test('has required top-level keys', () {
      expect(config['source'], 'mangadex');
      expect(config['api'], isA<Map>());
    });

    test('api block has required endpoints', () {
      final api = config['api'] as Map;
      final endpoints = api['endpoints'] as Map;
      expect(endpoints.containsKey('allGalleries'), isTrue);
      expect(endpoints.containsKey('search'), isTrue);
      expect(endpoints.containsKey('detail'), isTrue);
    });

    test('api.list configuration is valid', () {
      final list = config['api']['list'] as Map;
      expect(list['items'], r'$.data[*]');
      expect(list['fields'], isA<Map>());
      expect(list['pagination']['offsetMode'], isTrue);
    });

    test('api.detail configuration is valid', () {
      final detail = config['api']['detail'] as Map;
      expect(detail['fields'], isA<Map>());
      expect(detail['chapters']['endpoint'], isNotEmpty);
      expect(detail['chapters']['items'], isNotNull);
    });

    test('api.images configuration is valid', () {
      final images = config['api']['images'] as Map;
      expect(images['mode'], 'atHome');
      expect(images['atHomeEndpoint'], isNotEmpty);
    });
  });

  group('HentaiFox Config Schema Validation', () {
    late Map<String, dynamic> config;

    setUpAll(() async {
      config = (await loadConfigRemote('hentaifox-config.json'))
          .cast<String, dynamic>();
    });

    test('has required top-level keys', () {
      expect(config['source'], 'hentaifox');
      expect(config['scraper'], isA<Map>());
    });

    test('scraper URL patterns are present', () {
      final patterns = config['scraper']['urlPatterns'] as Map;
      expect(patterns.containsKey('detail'), isTrue);
      expect(patterns.containsKey('chapter'), isTrue);
    });

    test('scraper.selectors has detail and reader blocks', () {
      final selectors = config['scraper']['selectors'] as Map;
      expect(selectors['detail'], isNotNull);
      expect(selectors['reader'], isNotNull);
    });

    test('reader block is configured for hentaifoxCdn mode', () {
      final reader = config['scraper']['selectors']['reader'] as Map;
      expect(reader['mode'], 'hentaifoxCdn');
      expect(reader['thumbSelector'], isNotEmpty);
      expect(reader['thumbSrcAttr'], isNotEmpty);
      expect(reader['cdnPathRegex'], isNotEmpty);
      expect(reader['pageCountSelector'], isNotEmpty);
    });
  });
}
