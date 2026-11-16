import 'dart:convert';
import 'dart:io';

import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:test/test.dart';

void main() {
  group('SourceConfig with SearchConfig', () {
    test('parses comix-config.json successfully through compatibility normalizer', () {
      final file = File('/Users/asix/Documents/ektensi/kuron-extensions/config/en/comix-config.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final normalized = RemoteConfigService.normalizeSourceConfigForCompatibility(json);
      final config = SourceConfig.fromJson(normalized);

      expect(config.source, 'comix');
      expect(config.searchForm, isNotNull);
      expect(config.searchForm?.params['query']?.queryParam, 'keyword');
      expect(config.searchForm?.params['sort']?.type, 'select');
      expect(config.searchForm?.params['sort']?.options, hasLength(4));
      expect(config.searchForm?.params['sort']?.options?.map((o) => o.value).toSet(), hasLength(4));
      expect(json['adapterConfig'], isNotNull);
      expect((json['adapterConfig'] as Map)['endpoint'], '/browse');
    });

    test('parses mangafire-config.json successfully through compatibility normalizer', () {
      final file = File('/Users/asix/Documents/ektensi/kuron-extensions/config/en/mangafire-config.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final normalized = RemoteConfigService.normalizeSourceConfigForCompatibility(json);
      final config = SourceConfig.fromJson(normalized);

      expect(config.source, 'mangafire');
      expect(config.searchForm, isNotNull);
      expect(config.searchForm?.params['query']?.queryParam, 'keyword');
      expect(config.searchForm?.params['sort']?.type, 'select');
      expect(config.searchForm?.params['sort']?.options, hasLength(4));
      expect(config.searchForm?.params['sort']?.options?.map((o) => o.value).toSet(), hasLength(4));
      expect(json['adapterConfig'], isNotNull);
      expect((json['adapterConfig'] as Map)['endpoint'], '/browse');
    });

    test('parses searchConfig without endpoint without throwing type cast error', () {
      final json = {
        'source': 'test_source',
        'version': '1.0.0',
        'searchConfig': {
          'queryParam': 'q',
        },
      };

      final config = SourceConfig.fromJson(json);
      expect(config.searchConfig?.endpoint, '');
      expect(config.searchConfig?.queryParam, 'q');
    });
  });
}
