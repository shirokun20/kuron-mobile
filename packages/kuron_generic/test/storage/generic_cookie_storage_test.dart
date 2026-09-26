import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/src/storage/generic_cookie_storage.dart';
import 'package:test/test.dart';

void main() {
  group('GenericCookieStorage (port-backed)', () {
    test('read/write/delete delegate to SecureValueStore', () async {
      final storage = GenericCookieStorage(
        'crotpedia',
        secureStore: InMemorySecureValueStore(),
      );

      expect(await storage.read('alpha'), isNull);

      await storage.write('alpha', 'session=abc123');
      expect(await storage.read('alpha'), 'session=abc123');

      await storage.delete('alpha');
      expect(await storage.read('alpha'), isNull);
    });

    test('keys are namespaced per source id', () async {
      final a = GenericCookieStorage(
        'source_a',
        secureStore: InMemorySecureValueStore(),
      );
      final b = GenericCookieStorage(
        'source_b',
        secureStore: InMemorySecureValueStore(),
      );

      await a.write('cookie', 'value-a');
      await b.write('cookie', 'value-b');

      expect(await a.read('cookie'), 'value-a');
      expect(await b.read('cookie'), 'value-b');
    });

    test('deleteAll removes every key', () async {
      final storage = GenericCookieStorage(
        'x',
        secureStore: InMemorySecureValueStore(),
      );
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.deleteAll(['a', 'b']);
      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), isNull);
    });
  });
}
