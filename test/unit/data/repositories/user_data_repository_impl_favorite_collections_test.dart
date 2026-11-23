import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/datasources/local/local_data_source.dart';
import 'package:nhasixapp/data/repositories/user_data_repository_impl.dart';
import 'package:nhasixapp/domain/entities/favorite_collection.dart';

class MockLocalDataSource extends Mock implements LocalDataSource {}

void main() {
  late UserDataRepositoryImpl repository;
  late MockLocalDataSource mockLocalDataSource;

  setUp(() {
    mockLocalDataSource = MockLocalDataSource();
    repository = UserDataRepositoryImpl(localDataSource: mockLocalDataSource);
  });

  group('UserDataRepositoryImpl favorite collections', () {
    final tCollection = FavoriteCollection(
      id: 'collection_1',
      name: 'Favorites 1',
      createdAt: DateTime(2026, 4, 12),
      updatedAt: DateTime(2026, 4, 12),
      itemCount: 3,
    );

    test('getFavorites passes collectionId to localDataSource', () async {
      when(() => mockLocalDataSource.getFavorites(
            page: 1,
            limit: 20,
            collectionId: 'collection_1',
            uncategorizedOnly: false,
          )).thenAnswer((_) async => [
            {
              'id': '123',
              'source_id': 'nhentai',
              'title': 'Test',
              'cover_url': 'https://example.com/cover.jpg',
            }
          ]);

      final result =
          await repository.getFavorites(collectionId: 'collection_1');

      verify(() => mockLocalDataSource.getFavorites(
            page: 1,
            limit: 20,
            collectionId: 'collection_1',
            uncategorizedOnly: false,
          )).called(1);
      expect(result, hasLength(1));
    });

    test('createFavoriteCollection delegates to localDataSource', () async {
      when(() => mockLocalDataSource.createFavoriteCollection(
            name: 'Favorites 1',
            collectionId: any(named: 'collectionId'),
          )).thenAnswer((_) async => tCollection);

      final result =
          await repository.createFavoriteCollection(name: 'Favorites 1');

      verify(() => mockLocalDataSource.createFavoriteCollection(
            name: 'Favorites 1',
            collectionId: any(named: 'collectionId'),
          )).called(1);
      expect(result, tCollection);
    });

    test('setFavoriteCollectionIds delegates to localDataSource', () async {
      when(() => mockLocalDataSource.setFavoriteCollectionIds(
            favoriteId: '123',
            sourceId: 'nhentai',
            collectionIds: ['collection_1', 'collection_2'],
          )).thenAnswer((_) async {});

      await repository.setFavoriteCollectionIds(
        favoriteId: '123',
        sourceId: 'nhentai',
        collectionIds: const ['collection_1', 'collection_2'],
      );

      verify(() => mockLocalDataSource.setFavoriteCollectionIds(
            favoriteId: '123',
            sourceId: 'nhentai',
            collectionIds: ['collection_1', 'collection_2'],
          )).called(1);
    });

    test('removeFromFavorites passes sourceId to localDataSource', () async {
      when(() => mockLocalDataSource.removeFromFavorites(
            '123',
            sourceId: 'nhentai',
          )).thenAnswer((_) async {});

      await repository.removeFromFavorites('123', sourceId: 'nhentai');

      verify(() => mockLocalDataSource.removeFromFavorites(
            '123',
            sourceId: 'nhentai',
          )).called(1);
    });
  });
}
