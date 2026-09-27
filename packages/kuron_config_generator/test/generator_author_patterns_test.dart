// Regression test for shirokun20/kuron-mobile#69 — the generator emitted
// `authorSearch`/`artistSearch` only for blogger/mangathemesia themes, so a
// madara config had none and author chips silently fell back to genreSearch
// (wrong archive, empty results).
library;

import 'package:kuron_config_generator/src/generator/config_generator.dart';
import 'package:test/test.dart';

Map<String, String?> _madaraAnswers() => {
      'sourceId': 'madaratest',
      'displayName': 'Madara Test',
      'mode': 'scraper',
      'cmsThemeType': 'madara-classic',
      'homeUrl': 'https://example.com',
      'supportsSearch': 'y',
      'supportsChapters': 'y',
    };

Map<String, Object?> _patterns(Map<String, String?> answers) {
  final config = ConfigGenerator.generateConfig(answers);
  final scraper = config['scraper']! as Map<String, Object?>;
  return (scraper['urlPatterns']! as Map<String, Object?>);
}

void main() {
  group('madara author/artist archive patterns (#69)', () {
    test('emits authorSearch + artistSearch for madara-classic', () {
      final urls = _patterns(_madaraAnswers());

      expect((urls['authorSearch']! as Map)['url'], '/manga-author/{tag}/');
      expect((urls['artistSearch']! as Map)['url'], '/manga-artist/{tag}/');
    });

    test('emits the same for madara-tailwind', () {
      final urls =
          _patterns({..._madaraAnswers(), 'cmsThemeType': 'madara-tailwind'});

      expect((urls['authorSearch']! as Map)['url'], '/manga-author/{tag}/');
      expect((urls['artistSearch']! as Map)['url'], '/manga-artist/{tag}/');
    });

    test('paged variants keep the {tag} segment', () {
      // Live: manhwaden serves /manga-genre/action/page/2/ (200).
      final urls = _patterns(_madaraAnswers());

      expect((urls['authorSearchPage']! as Map)['url'],
          '/manga-author/{tag}/page/{page}/');
      expect((urls['artistSearchPage']! as Map)['url'],
          '/manga-artist/{tag}/page/{page}/');
    });

    test('patterns inherit the home list block so extraction still works', () {
      final urls = _patterns(_madaraAnswers());

      expect((urls['authorSearch']! as Map)['inherits'], 'home');
      expect((urls['artistSearch']! as Map)['inherits'], 'home');
    });

    test('per-config overrides win over the madara defaults', () {
      // Verified live: manhwacomics serves /manhwa-author/, gedecomix
      // /comics-artist/, lilymanga /gl-author/ — the taxonomy root is
      // per-site, not derivable from the genre prefix.
      final urls = _patterns({
        ..._madaraAnswers(),
        'authorSearchUrl': '/manhwa-author/{tag}/',
        'artistSearchUrl': '/manhwa-artist/{tag}/',
      });

      expect((urls['authorSearch']! as Map)['url'], '/manhwa-author/{tag}/');
      expect((urls['artistSearch']! as Map)['url'], '/manhwa-artist/{tag}/');
      expect((urls['authorSearchPage']! as Map)['url'],
          '/manhwa-author/{tag}/page/{page}/');
    });

    test('mangathemesia keeps its own author/artist roots', () {
      final urls = _patterns({
        ..._madaraAnswers(),
        'cmsThemeType': 'mangathemesia',
      });

      expect((urls['authorSearch']! as Map)['url'], '/author/{tag}/');
      expect((urls['artistSearch']! as Map)['url'], '/artist/{tag}/');
    });
  });
}
