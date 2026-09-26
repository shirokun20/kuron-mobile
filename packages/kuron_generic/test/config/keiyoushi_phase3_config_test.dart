library;

import 'package:kuron_core/kuron_core.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  // Parser emits `compatible` when the feature is declared in `features`
  // and `inferred` when only the config block (urlPatterns/selectors)
  // backs it. Upstream (kuron-extensions) dropped the `features.search`
  // declaration for all four phase-3 sources (verified live 2026-09-26),
  // so search resolves to `inferred` here.
  const Map<FeatureKind, FeatureStatus> mangaFeatures =
      <FeatureKind, FeatureStatus>{
    FeatureKind.home: FeatureStatus.inferred,
    FeatureKind.search: FeatureStatus.inferred,
    FeatureKind.detail: FeatureStatus.inferred,
    FeatureKind.reader: FeatureStatus.inferred,
  };

  runConfigContractTests(<ConfigContractCase>[
    ConfigContractCase(
      configName: 'rawbaka-config.json',
      expectedFeatures: mangaFeatures,
      forbiddenDiagCodes: <String>{'featureUnsupported'},
    ),
    ConfigContractCase(
      configName: 'manhwa18cc-config.json',
      expectedFeatures: mangaFeatures,
      forbiddenDiagCodes: <String>{'featureUnsupported'},
    ),
    ConfigContractCase(
      configName: 'manhwaclubnet-config.json',
      expectedFeatures: mangaFeatures,
      forbiddenDiagCodes: <String>{'featureUnsupported'},
    ),
    ConfigContractCase(
      configName: 'mangaforfree-config.json',
      expectedFeatures: mangaFeatures,
      forbiddenDiagCodes: <String>{'featureUnsupported'},
    ),
  ]);

  group('phase3 structural checks', () {
    test('rawbaka home list + reader images', () async {
      final config = await loadConfigRemote('rawbaka-config.json');
      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final home = (urlPatterns['home'] as Map).cast<String, Object?>();
      final list = (home['list'] as Map).cast<String, Object?>();

      expect(list['container'], 'article.manga-card');

      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final reader = (selectors['reader'] as Map).cast<String, Object?>();
      final images = (reader['images'] as Map).cast<String, Object?>();
      expect(images['selector'], '.reader-images img');
      expect(images['attribute'], 'src');
    });

    test('rawbaka detail chapter regex', () async {
      final config = await loadConfigRemote('rawbaka-config.json');
      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final detail = (selectors['detail'] as Map).cast<String, Object?>();
      final chapters = (detail['chapters'] as Map).cast<String, Object?>();
      final fields = (chapters['fields'] as Map).cast<String, Object?>();
      final id = (fields['id'] as Map).cast<String, Object?>();

      expect(id['regex'], contains('/manga/'));
    });

    test('manhwa18cc home list + reader images', () async {
      final config = await loadConfigRemote('manhwa18cc-config.json');
      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final home = (urlPatterns['home'] as Map).cast<String, Object?>();
      final list = (home['list'] as Map).cast<String, Object?>();

      expect(list['container'], '.bsx');

      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final reader = (selectors['reader'] as Map).cast<String, Object?>();
      final images = (reader['images'] as Map).cast<String, Object?>();
      expect(images['selector'], '.read-content img.loading');
      expect(images['attribute'], 'data-src');
    });

    test('manhwa18cc detail + reader nav', () async {
      final config = await loadConfigRemote('manhwa18cc-config.json');
      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final urlPatterns =
          (scraper['urlPatterns'] as Map).cast<String, Object?>();
      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final reader = (selectors['reader'] as Map).cast<String, Object?>();
      final nav = (reader['nav'] as Map).cast<String, Object?>();

      expect(urlPatterns['detail'], '/webtoon/{id}/');
      expect(nav['prev'], '.navi-change-chapter-btn-prev');
      expect(nav['next'], '.navi-change-chapter-btn-next');
    });

    test('manhwaclubnet baseUrl + madara signature', () async {
      final config = await loadConfigRemote('manhwaclubnet-config.json');
      expect(config['baseUrl'], 'https://manhwaclub.net');

      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final detail = (selectors['detail'] as Map).cast<String, Object?>();
      final chapters = (detail['chapters'] as Map).cast<String, Object?>();

      // Phase-4 fix: chapters load via madara admin-ajax (theme's
      // `ajax/chapters/` returns a full page, not a fragment), so config
      // declares ajaxHtml mode with the fragment's wp-manga-chapter markup.
      expect(chapters['mode'], 'ajaxHtml');
      expect(chapters['container'], 'li.wp-manga-chapter');
    });

    test('mangaforfree baseUrl + reader mode', () async {
      final config = await loadConfigRemote('mangaforfree-config.json');
      // Live 2026-09-26: domain moved .com → .net and the reader left the
      // madara chapterDataScript for plain html images.
      expect(config['baseUrl'], 'https://mangaforfree.net');

      final scraper = (config['scraper'] as Map).cast<String, Object?>();
      final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
      final reader = (selectors['reader'] as Map).cast<String, Object?>();

      expect(reader['mode'], 'html');
    });
  });
}
