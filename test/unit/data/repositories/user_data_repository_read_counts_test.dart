import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/datasources/local/local_data_source.dart';
import 'package:nhasixapp/data/repositories/user_data_repository_impl.dart';

class MockLocalDataSource extends Mock implements LocalDataSource {}

void main() {
  late UserDataRepositoryImpl repository;
  late MockLocalDataSource mockLocalDataSource;

  setUp(() {
    mockLocalDataSource = MockLocalDataSource();
    repository = UserDataRepositoryImpl(localDataSource: mockLocalDataSource);
  });

  group('getReadCountsBySource', () {
    test('returns per-source read counts from localDataSource', () async {
      // Arrange
      const counts = {'sourceA': 10, 'sourceB': 1};
      when(() => mockLocalDataSource.getReadCountsBySource())
          .thenAnswer((_) async => counts);

      // Act
      final result = await repository.getReadCountsBySource();

      // Assert
      verify(() => mockLocalDataSource.getReadCountsBySource()).called(1);
      expect(result, counts);
    });

    test('returns empty map when localDataSource throws', () async {
      // Arrange
      when(() => mockLocalDataSource.getReadCountsBySource())
          .thenThrow(Exception('db fail'));

      // Act
      final result = await repository.getReadCountsBySource();

      // Assert
      expect(result, isEmpty);
    });
  });
}
