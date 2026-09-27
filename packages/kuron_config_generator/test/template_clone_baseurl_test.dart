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
}
