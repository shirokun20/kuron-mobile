import 'package:kuron_core/kuron_core.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySecureValueStore', () {
    test('round-trips values', () async {
      final store = InMemorySecureValueStore();
      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    });

    test('instances are isolated', () async {
      final a = InMemorySecureValueStore();
      final b = InMemorySecureValueStore();
      await a.write('k', 'a');
      expect(await b.read('k'), isNull);
    });
  });

  group('ClearanceSolution', () {
    test('holds optional fields', () {
      const s = ClearanceSolution(
        token: 'crt',
        userAgent: 'ua',
        cookies: 'a=b',
      );
      expect(s.token, 'crt');
      expect(s.userAgent, 'ua');
      expect(s.cookies, 'a=b');
      const minimal = ClearanceSolution(token: 'crt');
      expect(minimal.userAgent, isNull);
      expect(minimal.cookies, isNull);
    });
  });
}
