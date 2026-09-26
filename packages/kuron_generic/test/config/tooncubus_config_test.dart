library;

import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  late Map<String, Object?> config;

  setUpAll(() async {
    config = await loadConfigRemote('tooncubus-config.json');
  });

  test('uses Blogger label pages, chapters, and reader-link handoff', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final urlPatterns = (scraper['urlPatterns'] as Map).cast<String, Object?>();
    final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
    final features = (config['features'] as Map).cast<String, Object?>();

    expect((urlPatterns['home'] as Map)['url'],
        '/search/label/Series?max-results=16');
    expect((urlPatterns['search'] as Map)['url'],
        '/search?q={query}&max-results=12');
    expect((urlPatterns['tagSearch'] as Map)['url'],
        '/search/label/{tag}?max-results=20');
    expect(features['chapters'], isTrue);
    expect(
      ((selectors['reader'] as Map)['readerPageLink'] as Map)['selector'],
      ".series-chapterlist .flexch-infoz a[href*='tooncubus-read.my.id']",
    );
  });
}
