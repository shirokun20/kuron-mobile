library;

import 'package:kuron_core/kuron_core.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  // Parser emits `compatible` when the feature is declared in
  // `features` (search: true here) and `inferred` when only the config
  // block (urlPatterns/selectors) backs it (home/detail/reader).
  // Upstream (kuron-extensions) dropped the `features.search` declaration
  // for ngomik/sektedoujin/mihentai/mangaread (verified live 2026-09-26),
  // so those resolve to `inferred` while the rest stay `compatible`.
  const Map<FeatureKind, FeatureStatus> mangaFeatures =
      <FeatureKind, FeatureStatus>{
    FeatureKind.home: FeatureStatus.inferred,
    FeatureKind.search: FeatureStatus.compatible,
    FeatureKind.detail: FeatureStatus.inferred,
    FeatureKind.reader: FeatureStatus.inferred,
  };
  const Map<FeatureKind, FeatureStatus> mangaFeaturesNoSearch =
      <FeatureKind, FeatureStatus>{
    FeatureKind.home: FeatureStatus.inferred,
    FeatureKind.search: FeatureStatus.inferred,
    FeatureKind.detail: FeatureStatus.inferred,
    FeatureKind.reader: FeatureStatus.inferred,
  };

  // Gallery sources omit `features.search: true`, so search is only
  // inferred from the urlPatterns block.
  final Map<FeatureKind, FeatureStatus> galleryFeatures =
      Map<FeatureKind, FeatureStatus>.of(mangaFeatures)
        ..[FeatureKind.search] = FeatureStatus.inferred;

  runConfigContractTests(<ConfigContractCase>[
    for (final String name in <String>[
      'komikindo',
      'komikdewasa',
      'manhwareads',
    ])
      ConfigContractCase(
        configName: '$name-config.json',
        expectedFeatures: mangaFeatures,
        forbiddenDiagCodes: <String>{'featureUnsupported'},
      ),
    for (final String name in <String>[
      'ngomik',
      'sektedoujin',
      'mihentai',
      'mangaread',
    ])
      ConfigContractCase(
        configName: '$name-config.json',
        expectedFeatures: mangaFeaturesNoSearch,
        forbiddenDiagCodes: <String>{'featureUnsupported'},
      ),
    for (final String name in <String>[
      'hentaiera',
      'hentaizap',
      'hentaienvy',
      'asmhentai',
    ])
      ConfigContractCase(
        configName: '$name-config.json',
        expectedFeatures: galleryFeatures,
        forbiddenDiagCodes: <String>{'featureUnsupported'},
      ),
  ]);

  group('phase1 structural checks', () {
    test('komikindo home list + ts_reader regex', () async {
      final Map<String, Object?> config = await loadConfigRemote('komikindo-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final Map<String, Object?> home =
          (urlPatterns['home'] as Map).cast<String, Object?>();
      final Map<String, Object?> list =
          (home['list'] as Map).cast<String, Object?>();

      // Home/homePage MUST scope to the "Latest Update" bixbox: the page
      // renders 7 bixbox sections and unscoped containers pull in Popular
      // Today / Project Update / Recommendation items.
      expect(list['container'],
          'div.bixbox:contains(Latest Update) .listupd .bs .bsx');

      // Genre/archive pages render plain .bs cards (no "Latest Update"
      // bixbox heading), so search/genreSearch must NOT pin the bixbox
      // wrapper. Regression: genre page 2 returned zero items (2026-08-23).
      final Map<String, Object?> search =
          (urlPatterns['search'] as Map).cast<String, Object?>();
      final Map<String, Object?> searchList =
          (search['list'] as Map).cast<String, Object?>();
      expect(searchList['container'], '.listupd .bsx');

      final Map<String, Object?> selectors =
          (scraper['selectors'] as Map).cast<String, Object?>();
      final Map<String, Object?> reader =
          (selectors['reader'] as Map).cast<String, Object?>();
      expect(reader['tsReaderRegex'], contains('ts_reader'));
    });

    test('komikdewasa imageHeaders referer + detail pattern', () async {
      final Map<String, Object?> config =
          await loadConfigRemote('komikdewasa-config.json');
      final Map<String, Object?> network =
          (config['network'] as Map).cast<String, Object?>();
      final Map<String, Object?> imageHeaders =
          (network['imageHeaders'] as Map).cast<String, Object?>();

      expect(imageHeaders['Referer'], 'https://komikdewasa.mom/');

      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      expect(urlPatterns['detail'], '/komik/{id}/');
    });

    test('mangaread baseUrl', () async {
      final mangareadConfig =
          await loadConfigRemote('mangaread-config.json');
      expect(mangareadConfig['baseUrl'], 'https://www.mangaread.org');
    });

    test('manhwareads home url', () async {
      final Map<String, Object?> config =
          await loadConfigRemote('manhwareads-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final Map<String, Object?> home =
          (urlPatterns['home'] as Map).cast<String, Object?>();
      expect(home['url'], '/new-2/');
    });

    test('hentaiera reader page url + image selector', () async {
      final Map<String, Object?> config = await loadConfigRemote('hentaiera-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> reader =
          ((scraper['selectors'] as Map)['reader'] as Map)
              .cast<String, Object?>();

      expect(reader['readerPageUrlPattern'], '/view/{id}/1/');
      expect(reader['readerImageSelector'], '#gimg');
    });

    test('hentaizap reader image selector + page count attr', () async {
      final Map<String, Object?> config = await loadConfigRemote('hentaizap-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> reader =
          ((scraper['selectors'] as Map)['reader'] as Map)
              .cast<String, Object?>();

      expect(reader['readerImageSelector'], '#readerImg');
      expect(reader['readerPageCountAttr'], 'data-reader-total');
    });

    test('hentaienvy reader page url + tags selector', () async {
      final Map<String, Object?> config =
          await loadConfigRemote('hentaienvy-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> selectors =
          (scraper['selectors'] as Map).cast<String, Object?>();
      final Map<String, Object?> reader =
          (selectors['reader'] as Map).cast<String, Object?>();
      final Map<String, Object?> detail =
          (selectors['detail'] as Map).cast<String, Object?>();
      final Map<String, Object?> fields =
          (detail['fields'] as Map).cast<String, Object?>();
      final Map<String, Object?> tags =
          (fields['tags'] as Map).cast<String, Object?>();

      expect(reader['readerPageUrlPattern'], '/g/{id}/1/');
      expect(tags['selector'] as String, contains('gp_tag'));
    });

    test('asmhentai detail + reader page urls', () async {
      final Map<String, Object?> config =
          await loadConfigRemote('asmhentai-config.json');
      final Map<String, Object?> scraper =
          (config['scraper'] as Map).cast<String, Object?>();
      final Map<String, Object?> urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final Map<String, Object?> reader =
          ((scraper['selectors'] as Map)['reader'] as Map)
              .cast<String, Object?>();

      expect(urlPatterns['detail'], '/g/{id}/');
      expect(reader['readerPageUrlPattern'], '/gallery/{id}/1/');
    });
  });
}
