import 'package:test/test.dart';
import 'package:kuron_config_generator/src/wizard/wizard_builder.dart';
import 'package:kuron_config_generator/src/generator/config_generator.dart';

void main() {
  group('Wizard', () {
    test('WizardBuilder creates flow with expected sections', () {
      final flow = WizardBuilder.buildFlow();

      expect(flow.sections, contains('identity'));
      expect(flow.sections, contains('features'));
      expect(flow.sections, contains('api'));
    });

    test('Identity section has required questions', () {
      final flow = WizardBuilder.buildFlow();
      final identityQuestions = flow.sections['identity']!;

      expect(identityQuestions.any((q) => q.id == 'sourceId'), isTrue);
      expect(identityQuestions.any((q) => q.id == 'homeUrl'), isTrue);
    });
    test('Scraper section asks taxonomy overrides (optional)', () {
      final flow = WizardBuilder.buildFlow();
      final questions = {
        for (final q in flow.sections['scraper']!) q.id: q
      };

      for (final id in [
        'genreSearchUrl',
        'tagSearchUrl',
        'authorSearchUrl',
        'artistSearchUrl'
      ]) {
        expect(questions, contains(id));
        expect(questions[id]!.isRequired, isFalse);
      }
    });

    test('ConfigGenerator produces valid config structure', () {
      final answers = {
        'sourceId': 'test_source',
        'displayName': 'Test Source',
        'version': '1.0.0',
        'homeUrl': 'https://test.com',
        'mode': 'rest_json',
        'supportsSearch': 'y',
        'supportsChapters': 'n',
        'supportsComments': 'n',
        'needsHeaders': 'n',
      };

      final config = ConfigGenerator.generateConfig(answers);

      expect(config['source'], 'test_source');
      expect(config['schemaVersion'], '2.0');
      expect(config['features'], isA<Map>());
      expect(config['requiredPrimitives'], isA<List>());
    });
  });
}
