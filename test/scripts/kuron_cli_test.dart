// KURON CLI runner tests: direct mode never hangs, help/version exit 0,
// no-arg non-TTY exits 1 without prompting.
import 'dart:io';

import 'package:test/test.dart';

const _cli = 'scripts/kuron.dart';

Future<ProcessResult> _run(List<String> args, {Map<String, String>? env}) {
  final extra = <String, String>{};
  if (env != null) extra.addAll(env);
  return Process.run(
    'fvm',
    ['dart', _cli, ...args],
    environment: {...Platform.environment, ...extra},
  );
}

void main() {
  test('help exits 0 and shows KURON brand', () async {
    final r = await _run(['help']);
    expect(r.exitCode, 0);
    expect(r.stdout as String, contains('Kuron Utility Runner & Optimizer'));
    expect(r.stdout as String, contains('build'));
  });

  test('version exits 0 with KURON name', () async {
    final r = await _run(['version']);
    expect(r.exitCode, 0);
    expect(r.stdout as String, contains('KURON v1.1.0'));
  });

  test('unknown command exits 1', () async {
    final r = await _run(['ngawur']);
    expect(r.exitCode, 1);
  });

  test('no-arg in CI exits 1 without hanging (direct mode)', () async {
    final r = await _run([], env: {'CI': 'true'}).timeout(
      const Duration(seconds: 60),
    );
    expect(r.exitCode, 1);
    expect(r.stdout as String, contains('Usage:'));
  });

  test('search usage exits 1 with mode list', () async {
    final r = await _run(['search']);
    expect(r.exitCode, 1);
    expect(r.stdout as String, contains('text | ast | audit'));
  });
}
