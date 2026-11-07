import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesValueStore', () {
    test('round-trips values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = PreferencesValueStore(prefs: prefs);

      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    });

    test('serves as fallback when secure primary throws (-34018)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FallbackSecureValueStore(
        primary: _ThrowingStore(),
        fallback: PreferencesValueStore(prefs: prefs),
      );

      await store.write('crt', 'token-1');
      expect(await store.read('crt'), 'token-1');
      await store.delete('crt');
      expect(await store.read('crt'), isNull);
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
