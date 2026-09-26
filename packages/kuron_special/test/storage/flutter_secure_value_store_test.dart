import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/storage/flutter_secure_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterSecureValueStore', () {
    test('read/write/delete delegate to FlutterSecureStorage', () async {
      FlutterSecureStorage.setMockInitialValues({});

      const store = FlutterSecureValueStore();

      expect(await store.read('alpha'), isNull);

      await store.write('alpha', 'session=abc123');
      expect(await store.read('alpha'), 'session=abc123');

      await store.delete('alpha');
      expect(await store.read('alpha'), isNull);
    });
  });
}
