import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/datasources/local/local_data_source.dart';
import 'package:nhasixapp/data/repositories/user_data_repository_impl.dart';
import 'package:nhasixapp/domain/value_objects/favorite_key.dart';

class MockLocalDataSource extends Mock implements LocalDataSource {}

void main() {
  setUpAll(() {
    registerFallbackValue((id: '', sourceId: ''));
    registerFallbackValue(<FavoriteKey>[]);
    registerFallbackValue(<String>[]);
  });

  late UserDataRepositoryImpl repository;
  late MockLocalDataSource mockLocalDataSource;

  const keyA = (id: '1', sourceId: 'nhentai');
  const keyB = (id: '2', sourceId: 'crotpedia');
  const keys = [keyA, keyB];

  setUp(() {
    mockLocalDataSource = MockLocalDataSource();
    repository = UserDataRepositoryImpl(localDataSource: mockLocalDataSource);
  });

  group('UserDataRepositoryImpl batch collections', () {
    test('getUncategorizedFavorites delegates page and limit', () async {
      when(
        () => mockLocalDataSource.getUncategorizedFavorites(page: 2, limit: 20),
      ).thenAnswer(
        (_) async => [
          {'id': '9', 'source_id': 'nhentai'},
        ],
      );

      final result = await repository.getUncategorizedFavorites(
        page: 2,
        limit: 20,
      );

      verify(
        () => mockLocalDataSource.getUncategorizedFavorites(page: 2, limit: 20),
      ).called(1);
      expect(result, hasLength(1));
    });

    test('getUncategorizedFavorites returns empty on DAO error', () async {
      when(
        () => mockLocalDataSource.getUncategorizedFavorites(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => []);

      expect(await repository.getUncategorizedFavorites(), isEmpty);
    });

    test('getUncategorizedCount delegates to localDataSource', () async {
      when(() => mockLocalDataSource.getUncategorizedCount())
          .thenAnswer((_) async => 7);

      expect(await repository.getUncategorizedCount(), 7);
      verify(() => mockLocalDataSource.getUncategorizedCount()).called(1);
    });

    test(
      'addFavoritesToCollections delegates keys, ids and move target',
      () async {
        when(
          () => mockLocalDataSource.addFavoritesToCollections(
            favorites: any(named: 'favorites'),
            collectionIds: any(named: 'collectionIds'),
            removeFromCollectionId: any(named: 'removeFromCollectionId'),
          ),
        ).thenAnswer((_) async {});

        await repository.addFavoritesToCollections(
          favorites: keys,
          collectionIds: const ['collection_1', 'collection_2'],
          removeFromCollectionId: 'collection_0',
        );

        verify(
          () => mockLocalDataSource.addFavoritesToCollections(
            favorites: keys,
            collectionIds: ['collection_1', 'collection_2'],
            removeFromCollectionId: 'collection_0',
          ),
        ).called(1);
      },
    );

    test(
      'addFavoritesToCollections passes null move target for plain add',
      () async {
        when(
          () => mockLocalDataSource.addFavoritesToCollections(
            favorites: any(named: 'favorites'),
            collectionIds: any(named: 'collectionIds'),
            removeFromCollectionId: any(named: 'removeFromCollectionId'),
          ),
        ).thenAnswer((_) async {});

        await repository.addFavoritesToCollections(
          favorites: keys,
          collectionIds: const ['collection_1'],
        );

        verify(
          () => mockLocalDataSource.addFavoritesToCollections(
            favorites: keys,
            collectionIds: ['collection_1'],
            removeFromCollectionId: null,
          ),
        ).called(1);
      },
    );

    test('addFavoritesToCollections rethrows DAO failures', () async {
      when(
        () => mockLocalDataSource.addFavoritesToCollections(
          favorites: any(named: 'favorites'),
          collectionIds: any(named: 'collectionIds'),
          removeFromCollectionId: any(named: 'removeFromCollectionId'),
        ),
      ).thenThrow(StateError('db gone'));

      expect(
        () => repository.addFavoritesToCollections(
          favorites: keys,
          collectionIds: const ['collection_1'],
        ),
        throwsStateError,
      );
    });

    test(
      'removeFavoritesFromCollection delegates keys and collection',
      () async {
        when(
          () => mockLocalDataSource.removeFavoritesFromCollection(
            favorites: any(named: 'favorites'),
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async {});

        await repository.removeFavoritesFromCollection(
          favorites: keys,
          collectionId: 'collection_1',
        );

        verify(
          () => mockLocalDataSource.removeFavoritesFromCollection(
            favorites: keys,
            collectionId: 'collection_1',
          ),
        ).called(1);
      },
    );

    test('removeFavoritesFromCollection rethrows DAO failures', () async {
      when(
        () => mockLocalDataSource.removeFavoritesFromCollection(
          favorites: any(named: 'favorites'),
          collectionId: any(named: 'collectionId'),
        ),
      ).thenThrow(StateError('db gone'));

      expect(
        () => repository.removeFavoritesFromCollection(
          favorites: keys,
          collectionId: 'collection_1',
        ),
        throwsStateError,
      );
    });
  });
}
