library;

import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  late Map<String, Object?> config;

  setUpAll(() async {
    config = await loadConfigRemote('shirodoujin-config.json');
  });

  test('uses direct chapter URLs and genre archive routes', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final urlPatterns = (scraper['urlPatterns'] as Map).cast<String, Object?>();

    expect(urlPatterns['chapter'], '/{id}');
    expect(
      (urlPatterns['genreSearch'] as Map)['url'],
      '/genre/{tag}/',
    );
    expect(
      (urlPatterns['genreSearchPage'] as Map)['url'],
      '/genre/{tag}/page/{page}/',
    );
  });
}
