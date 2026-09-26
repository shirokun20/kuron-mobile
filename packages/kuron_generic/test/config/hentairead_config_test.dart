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

  test('uses the /hentai/ listing and english reader route', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final urlPatterns = (scraper['urlPatterns'] as Map).cast<String, Object?>();

    expect((urlPatterns['home'] as Map)['url'], '/hentai/');
    expect(urlPatterns['detail'], '/hentai/{id}/');
    expect(urlPatterns['chapter'], '/hentai/{id}/english/p/1/');
  });

  test('keeps hentairead as a no-chapters source with reader fallback', () {
    final scraper = (config['scraper'] as Map).cast<String, Object?>();
    final selectors = (scraper['selectors'] as Map).cast<String, Object?>();
    final reader = (selectors['reader'] as Map).cast<String, Object?>();
    final features = (config['features'] as Map).cast<String, Object?>();

    expect(reader['mode'], 'chapterDataScript');
    expect(features['chapters'], isFalse);
  });

  test('image download headers match hentairead full-size reader contract', () {
    final source = GenericHttpSource(
      rawConfig: Map<String, dynamic>.from(config),
      dio: Dio(),
      logger: Logger(level: Level.off),
    );

    final headers = source.getImageDownloadHeaders(
      imageUrl: 'https://henread.xyz/294075/87911/hr_0001.jpg',
    );

    expect(headers['Referer'], 'https://hentairead.com/');
    expect(headers['Accept'], 'image/webp,image/*,*/*;q=0.8');
    expect(headers['Origin'], 'https://hentairead.com');
    expect(headers['Sec-Fetch-Dest'], 'image');
  });
}
