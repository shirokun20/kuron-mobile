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

  group('FallbackSecureValueStore', () {
    test('uses primary when it works, fallback untouched', () async {
      final primary = InMemorySecureValueStore();
      final fallback = _SpyStore(InMemorySecureValueStore());
      final store =
          FallbackSecureValueStore(primary: primary, fallback: fallback);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      expect(fallback.calls, isEmpty);
      await store.delete('k');
      expect(await store.read('k'), isNull);
      expect(fallback.calls, isEmpty);
    });

    test('falls back on primary failure (unsigned macOS -34018)', () async {
      final store = FallbackSecureValueStore(
        primary: _ThrowingStore(),
        fallback: InMemorySecureValueStore(),
      );
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    });

    test('read falls back when primary throws but keeps primary hits',
        () async {
      final primary = InMemorySecureValueStore();
      await primary.write('k', 'primary-v');
      final store = FallbackSecureValueStore(
        primary: primary,
        fallback: InMemorySecureValueStore(),
      );
      expect(await store.read('k'), 'primary-v');
    });
  });
}

class _ThrowingStore implements SecureValueStore {
  @override
  Future<String?> read(String key) async => throw Exception('-34018');

  @override
  Future<void> write(String key, String value) async =>
      throw Exception('-34018');

  @override
  Future<void> delete(String key) async => throw Exception('-34018');
}

class _SpyStore implements SecureValueStore {
  _SpyStore(this.inner);
  final SecureValueStore inner;
  final List<String> calls = [];

  @override
  Future<String?> read(String key) async {
    calls.add('read:$key');
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    calls.add('write:$key');
    return inner.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    calls.add('delete:$key');
    return inner.delete(key);
  }
}
