import 'package:test/test.dart';
import 'package:args/command_runner.dart';
import 'package:kuron_config_generator/src/commands/generate_command.dart';
import 'package:kuron_config_generator/src/commands/validate_command.dart';
import 'package:kuron_config_generator/src/discovery/http_probe.dart';

void main() {
  group('CLI commands', () {
    test('GenerateCommand has expected name and description', () {
      final cmd = GenerateCommand();
      expect(cmd.name, 'generate');
      expect(cmd.description, contains('Generate'));
    });

    test('runner registers generate + validate only (discover stub gone)',
        () {
      final runner = CommandRunner<void>('kuron_config_generator', 'test')
        ..addCommand(GenerateCommand())
        ..addCommand(ValidateCommand());
      expect(runner.commands.keys, containsAll(['generate', 'validate-generated']));
      expect(runner.commands.keys, isNot(contains('discover')));
    });

    test('ValidateCommand has expected name and description', () {
      final cmd = ValidateCommand();
      expect(cmd.name, 'validate-generated');
      expect(cmd.description, contains('Validate'));
    });

    test('GenerateCommand requires url or interactive flag', () {
      final cmd = GenerateCommand();
      expect(cmd.argParser.options, contains('url'));
      expect(cmd.argParser.options, contains('interactive'));
    });

    test('GenerateCommand exposes taxonomy overrides + report contract', () {
      final cmd = GenerateCommand();
      for (final flag in [
        'genre-search-url',
        'tag-search-url',
        'author-search-url',
        'artist-search-url',
        'fix',
        'report-output',
      ]) {
        expect(cmd.argParser.options, contains(flag));
      }
    });
  });

  group('resolveClonedHomeUrl (#52)', () {
    const base = 'https://newhost.test';
    const container = '.item';

    test('keeps home.url when probe 200s with container match', () async {
      final got = await GenerateCommand.resolveClonedHomeUrl(
        baseUrl: base,
        homeUrl: '/new-2/',
        container: container,
        fetch: (_) async => ProbeResult(
          url: '$base/new-2/',
          statusCode: 200,
          body: '<html><body><div class="item">x</div></body></html>',
        ),
      );
      expect(got, '/new-2/');
    });

    test('resets to / when guessed page 404s', () async {
      final got = await GenerateCommand.resolveClonedHomeUrl(
        baseUrl: base,
        homeUrl: '/new-2/',
        container: container,
        fetch: (_) async => ProbeResult(
          url: '$base/new-2/',
          statusCode: 404,
          body: '',
        ),
      );
      expect(got, '/');
    });

    test('resets to / when 200 but no container match', () async {
      final got = await GenerateCommand.resolveClonedHomeUrl(
        baseUrl: base,
        homeUrl: '/new-2/',
        container: container,
        fetch: (_) async => ProbeResult(
          url: '$base/new-2/',
          statusCode: 200,
          body: '<html><body><p>parked</p></body></html>',
        ),
      );
      expect(got, '/');
    });

    test('skips probe when already /', () async {
      var called = false;
      final got = await GenerateCommand.resolveClonedHomeUrl(
        baseUrl: base,
        homeUrl: '/',
        container: container,
        fetch: (_) async {
          called = true;
          throw StateError('must not fetch');
        },
      );
      expect(got, '/');
      expect(called, isFalse);
    });
  });
}
