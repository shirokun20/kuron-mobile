library;

import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  late Map<String, Object?> config;

  setUpAll(() async {
    config = await loadConfigRemote('manhwaread-config.json');
  });

  test('uses /manhwa/ latest listing for the home feed', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final urlPatterns = (scraper['urlPatterns'] as Map).cast<String, Object?>();
    final home = (urlPatterns['home'] as Map).cast<String, Object?>();
    final homePage = (urlPatterns['homePage'] as Map).cast<String, Object?>();

    expect(home['url'], '/manhwa/');
    expect(homePage['url'], '/manhwa/page/{page}/');
  });

  test('scopes detail chapters to groupChapterList only', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
    final detail = (selectors['detail'] as Map).cast<String, Object?>();
    final chapters = (detail['chapters'] as Map).cast<String, Object?>();

    expect(
      chapters['container'],
      '#groupChapterList #chaptersList a.chapter-item',
    );
  });

  test('enables random gallery via scraper randomUrl', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final features = (config['features'] as Map).cast<String, Object?>();

    expect(scraper['randomUrl'], '/?random_manga=1');
    expect(features['randomGallery'], isTrue);
  });
}
