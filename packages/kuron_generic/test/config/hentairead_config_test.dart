library;

import 'package:dio/dio.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../support/config_test_harness.dart';

void main() {
  late Map<String, Object?> config;

  setUpAll(() async {
    config = await loadConfigRemote('hentairead-config.json');
  });

  test('uses the site root listing and plain detail/chapter routes', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final urlPatterns = (scraper['urlPatterns'] as Map).cast<String, Object?>();

    expect((urlPatterns['home'] as Map)['url'], '/');
    expect((urlPatterns['search'] as Map)['url'], '/search/{query}');
    expect(urlPatterns['detail'], '/{id}/');
    expect(urlPatterns['chapter'], '/{id}');
  });

  test('declares chapters and reads images from data-index img tags', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
    final reader = (selectors['reader'] as Map).cast<String, Object?>();
    final features = (config['features'] as Map).cast<String, Object?>();
    final chapters =
        ((selectors['detail'] as Map)['chapters'] as Map)
            .cast<String, Object?>();

    expect(features['chapters'], isTrue);
    expect(chapters['container'], '#nt_listchapter');
    expect((reader['images'] as Map)['selector'], 'img[data-index]');
  });

  test('image download headers match hentairead full-size reader contract', () {
    final source = GenericHttpSource(
      rawConfig: Map<String, dynamic>.from(config),
      dio: Dio(),
      logger: Logger(level: Level.off),
    );

    final headers = source.getImageDownloadHeaders(
      imageUrl: 'https://hentairead.io/upload/pages/2026/09/cover.jpg',
    );

    // refererHeader is derived from the config's baseUrl, so this asserts the
    // published config points at the live domain.
    expect(config['baseUrl'], 'https://hentairead.io');
    expect(headers['Referer'], 'https://hentairead.io/');
    expect(headers['User-Agent'], contains('Mozilla/5.0'));
  });
}
