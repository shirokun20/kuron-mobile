import 'package:test/test.dart';
import 'package:kuron_config_generator/src/commands/generate_command.dart';

void main() {
  group('baseOrigin', () {
    test('keeps non-root path', () {
      expect(
        GenerateCommand.baseOrigin(Uri.parse('https://example.com/manga')),
        'https://example.com/manga',
      );
    });

    test('strips trailing slash; root path keeps origin only', () {
      expect(
        GenerateCommand.baseOrigin(Uri.parse('https://example.com/manga/')),
        'https://example.com/manga',
      );
      expect(
        GenerateCommand.baseOrigin(Uri.parse('https://example.com/')),
        'https://example.com',
      );
      expect(
        GenerateCommand.baseOrigin(Uri.parse('https://example.com')),
        'https://example.com',
      );
    });
  });

  // #56: clone kept the template's Referer, so hotlink-protected images
  // answered 403 / text/plain and the reader smoke screen failed.
  group('repointTemplateHeaders', () {
    test('rewrites headers + imageHeaders carrying the template host', () {
      final config = {
        'baseUrl': 'https://newhost.test',
        'network': {
          'headers': {
            'Referer': 'https://template.test/',
            'X-Other': 'untouched',
          },
          'imageHeaders': {'Referer': 'https://template.test/manga/x/'},
        },
      };
      GenerateCommand.repointTemplateHeaders(
        config,
        oldBase: 'https://template.test',
        newBase: 'https://newhost.test/manga',
      );
      final network = config['network'] as Map;
      final headers = network['headers'] as Map;
      final imageHeaders = network['imageHeaders'] as Map;
      expect(headers['Referer'], 'https://newhost.test/manga/');
      expect(headers['X-Other'], 'untouched');
      expect(imageHeaders['Referer'], 'https://newhost.test/manga/manga/x/');
      expect(
        (headers['Referer'] as String).contains('template.test'),
        isFalse,
      );
    });

    test('no-op without oldBase or network block', () {
      final config = {
        'network': {
          'headers': {'Referer': 'https://template.test/'},
        },
      };
      GenerateCommand.repointTemplateHeaders(config,
          oldBase: null, newBase: 'https://newhost.test');
      expect((config['network']! as Map)['headers'],
          {'Referer': 'https://template.test/'});

      final noNetwork = <String, dynamic>{'baseUrl': 'https://newhost.test'};
      GenerateCommand.repointTemplateHeaders(noNetwork,
          oldBase: 'https://template.test', newBase: 'https://newhost.test');
      expect(noNetwork['network'], isNull);
    });
  });
}
