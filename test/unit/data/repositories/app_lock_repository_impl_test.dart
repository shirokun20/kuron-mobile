import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nhasixapp/data/repositories/app_lock_repository_impl.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late AppLockRepositoryImpl repository;
  late MockFlutterSecureStorage storage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    storage = MockFlutterSecureStorage();
    repository = AppLockRepositoryImpl(storage: storage);
  });

  group('AppLockRepositoryImpl', () {
    test('savePinHash and getPinHash round-trip', () async {
      when(() =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'abc123hash');

      await repository.savePinHash('abc123hash');
      final result = await repository.getPinHash();
      expect(result, 'abc123hash');
    });

    test('getPinHash returns null when nothing saved', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      final result = await repository.getPinHash();
      expect(result, isNull);
    });

    test('setPinEnabled and getPinEnabled round-trip', () async {
      when(() =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'true');

      await repository.setPinEnabled(true);
      expect(await repository.getPinEnabled(), isTrue);
    });

    test('getPinEnabled defaults to false', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      expect(await repository.getPinEnabled(), isFalse);
    });

    test('setBiometricEnabled and getBiometricEnabled round-trip', () async {
      when(() =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'true');

      await repository.setBiometricEnabled(true);
      expect(await repository.getBiometricEnabled(), isTrue);
    });

    test('clear removes all stored values', () async {
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      await repository.clear();
      verify(() => storage.delete(key: any(named: 'key'))).called(5);
    });

    test('isBiometricAvailable returns false when not set', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);

      expect(await repository.isBiometricAvailable(), isFalse);
    });
  });
}
