import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/favorite_collection.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/favorites/add_to_favorites_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/get_favorites_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/remove_from_favorites_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/get_favorite_collections_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/create_favorite_collection_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/rename_favorite_collection_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/delete_favorite_collection_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/add_to_favorite_collection_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/add_batch_to_favorite_collections_usecase.dart';
import 'package:nhasixapp/domain/usecases/favorites/remove_batch_from_favorite_collection_usecase.dart';
import 'package:nhasixapp/presentation/cubits/favorite/favorite_cubit.dart';

class MockAddToFavoritesUseCase extends Mock implements AddToFavoritesUseCase {}

class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}

class MockRemoveFromFavoritesUseCase extends Mock
    implements RemoveFromFavoritesUseCase {}

class MockGetFavoriteCollectionsUseCase extends Mock
    implements GetFavoriteCollectionsUseCase {}

class MockCreateFavoriteCollectionUseCase extends Mock
    implements CreateFavoriteCollectionUseCase {}

class MockRenameFavoriteCollectionUseCase extends Mock
    implements RenameFavoriteCollectionUseCase {}

class MockDeleteFavoriteCollectionUseCase extends Mock
    implements DeleteFavoriteCollectionUseCase {}

class MockAddToFavoriteCollectionUseCase extends Mock
    implements AddToFavoriteCollectionUseCase {}

class MockAddBatchToFavoriteCollectionsUseCase extends Mock
    implements AddBatchToFavoriteCollectionsUseCase {}

class MockRemoveBatchFromFavoriteCollectionUseCase extends Mock
    implements RemoveBatchFromFavoriteCollectionUseCase {}

class MockUserDataRepository extends Mock implements UserDataRepository {}

class MockLogger extends Mock implements Logger {}

void main() {
  late FavoriteCubit cubit;
  late MockAddToFavoritesUseCase mockAddToFavoritesUseCase;
  late MockGetFavoritesUseCase mockGetFavoritesUseCase;
  late MockRemoveFromFavoritesUseCase mockRemoveFromFavoritesUseCase;
  late MockGetFavoriteCollectionsUseCase mockGetFavoriteCollectionsUseCase;
  late MockCreateFavoriteCollectionUseCase mockCreateFavoriteCollectionUseCase;
  late MockRenameFavoriteCollectionUseCase mockRenameFavoriteCollectionUseCase;
  late MockDeleteFavoriteCollectionUseCase mockDeleteFavoriteCollectionUseCase;
  late MockAddToFavoriteCollectionUseCase mockAddToFavoriteCollectionUseCase;
  late MockAddBatchToFavoriteCollectionsUseCase
  mockAddBatchToFavoriteCollectionsUseCase;
  late MockRemoveBatchFromFavoriteCollectionUseCase
  mockRemoveBatchFromFavoriteCollectionUseCase;
  late MockUserDataRepository mockUserDataRepository;
  late MockLogger mockLogger;

  final tCollection = FavoriteCollection(
    id: 'collection_1',
    name: 'Manga',
    createdAt: DateTime(2026, 4, 12),
    updatedAt: DateTime(2026, 4, 12),
    itemCount: 1,
  );

  const tKeys = [
    (id: '1', sourceId: 'nhentai'),
    (id: '2', sourceId: 'crotpedia'),
  ];

  List<Map<String, dynamic>> row(String id, String sourceId) => [
    {
      'id': id,
      'source_id': sourceId,
      'title': 'Title $id',
      'cover_url': 'https://example.com/$id.jpg',
    },
  ];

  setUpAll(() {
    registerFallbackValue(const GetFavoritesParams(page: 1, limit: 20));
    registerFallbackValue(RemoveFromFavoritesParams.fromString('123'));
    registerFallbackValue(<String>[]);
    registerFallbackValue((id: '', sourceId: ''));
    registerFallbackValue([(id: '', sourceId: '')]);
  });

  setUp(() {
    mockAddToFavoritesUseCase = MockAddToFavoritesUseCase();
    mockGetFavoritesUseCase = MockGetFavoritesUseCase();
    mockRemoveFromFavoritesUseCase = MockRemoveFromFavoritesUseCase();
    mockGetFavoriteCollectionsUseCase = MockGetFavoriteCollectionsUseCase();
    mockCreateFavoriteCollectionUseCase = MockCreateFavoriteCollectionUseCase();
    mockRenameFavoriteCollectionUseCase = MockRenameFavoriteCollectionUseCase();
    mockDeleteFavoriteCollectionUseCase = MockDeleteFavoriteCollectionUseCase();
    mockAddToFavoriteCollectionUseCase = MockAddToFavoriteCollectionUseCase();
    mockAddBatchToFavoriteCollectionsUseCase =
        MockAddBatchToFavoriteCollectionsUseCase();
    mockRemoveBatchFromFavoriteCollectionUseCase =
        MockRemoveBatchFromFavoriteCollectionUseCase();
    mockUserDataRepository = MockUserDataRepository();
    mockLogger = MockLogger();

    when(() => mockUserDataRepository.getFavoritesCount())
        .thenAnswer((_) async => 0);
    when(() => mockUserDataRepository.getUncategorizedCount())
        .thenAnswer((_) async => 0);

    cubit = FavoriteCubit(
      addToFavoritesUseCase: mockAddToFavoritesUseCase,
      getFavoritesUseCase: mockGetFavoritesUseCase,
      removeFromFavoritesUseCase: mockRemoveFromFavoritesUseCase,
      getFavoriteCollectionsUseCase: mockGetFavoriteCollectionsUseCase,
      createFavoriteCollectionUseCase: mockCreateFavoriteCollectionUseCase,
      renameFavoriteCollectionUseCase: mockRenameFavoriteCollectionUseCase,
      deleteFavoriteCollectionUseCase: mockDeleteFavoriteCollectionUseCase,
      addToFavoriteCollectionUseCase: mockAddToFavoriteCollectionUseCase,
      addBatchToFavoriteCollectionsUseCase:
          mockAddBatchToFavoriteCollectionsUseCase,
      removeBatchFromFavoriteCollectionUseCase:
          mockRemoveBatchFromFavoriteCollectionUseCase,
      userDataRepository: mockUserDataRepository,
      logger: mockLogger,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('FavoriteCubit batch folder actions', () {
    blocTest<FavoriteCubit, FavoriteState>(
      'addBatchToCollections calls usecase then refreshes the list',
      build: () {
        when(
          () => mockAddBatchToFavoriteCollectionsUseCase(
            favorites: any(named: 'favorites'),
            collectionIds: any(named: 'collectionIds'),
            removeFromCollectionId: any(named: 'removeFromCollectionId'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockGetFavoriteCollectionsUseCase())
            .thenAnswer((_) async => [tCollection]);
        when(() => mockGetFavoritesUseCase(any()))
            .thenAnswer((_) async => row('1', 'nhentai'));
        when(
          () => mockUserDataRepository.getFavoritesCount(
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async => 1);

        return cubit;
      },
      act: (cubit) => cubit.addBatchToCollections(
        favorites: tKeys,
        collectionIds: const ['collection_1'],
      ),
      expect: () => [
        // Initial state is FavoriteInitial, so no batch-operating
        // emission happens before the refresh reloads the list.
        isA<FavoriteLoading>(),
        isA<FavoriteLoaded>().having(
          (s) => s.isBatchOperating,
          'batch operating done',
          false,
        ),
      ],
      verify: (_) {
        verify(
          () => mockAddBatchToFavoriteCollectionsUseCase(
            favorites: tKeys,
            collectionIds: ['collection_1'],
            removeFromCollectionId: null,
          ),
        ).called(1);
      },
    );

    blocTest<FavoriteCubit, FavoriteState>(
      'addBatchToCollections with move target forwards it atomically',
      build: () {
        when(
          () => mockAddBatchToFavoriteCollectionsUseCase(
            favorites: any(named: 'favorites'),
            collectionIds: any(named: 'collectionIds'),
            removeFromCollectionId: any(named: 'removeFromCollectionId'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockGetFavoriteCollectionsUseCase())
            .thenAnswer((_) async => [tCollection]);
        when(() => mockGetFavoritesUseCase(any())).thenAnswer((_) async => []);
        when(
          () => mockUserDataRepository.getFavoritesCount(
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async => 0);

        return cubit;
      },
      act: (cubit) => cubit.addBatchToCollections(
        favorites: tKeys,
        collectionIds: const ['collection_2'],
        removeFromCollectionId: 'collection_1',
      ),
      verify: (_) {
        verify(
          () => mockAddBatchToFavoriteCollectionsUseCase(
            favorites: tKeys,
            collectionIds: ['collection_2'],
            removeFromCollectionId: 'collection_1',
          ),
        ).called(1);
      },
    );

    blocTest<FavoriteCubit, FavoriteState>(
      'addBatchToCollections ignores empty input without touching state',
      build: () => cubit,
      act: (cubit) => cubit.addBatchToCollections(
        favorites: const [],
        collectionIds: const ['collection_1'],
      ),
      expect: () => [],
      verify: (_) {
        verifyNever(
          () => mockAddBatchToFavoriteCollectionsUseCase(
            favorites: any(named: 'favorites'),
            collectionIds: any(named: 'collectionIds'),
            removeFromCollectionId: any(named: 'removeFromCollectionId'),
          ),
        );
      },
    );

    blocTest<FavoriteCubit, FavoriteState>(
      'removeBatchFromCollection calls usecase then refreshes the list',
      build: () {
        when(
          () => mockRemoveBatchFromFavoriteCollectionUseCase(
            favorites: any(named: 'favorites'),
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockGetFavoriteCollectionsUseCase())
            .thenAnswer((_) async => [tCollection]);
        when(() => mockGetFavoritesUseCase(any())).thenAnswer((_) async => []);
        when(
          () => mockUserDataRepository.getFavoritesCount(
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async => 0);

        return cubit;
      },
      act: (cubit) => cubit.removeBatchFromCollection(
        favorites: tKeys,
        collectionId: 'collection_1',
      ),
      expect: () => [
        isA<FavoriteLoading>(),
        isA<FavoriteLoaded>().having(
          (s) => s.isBatchOperating,
          'batch operating done',
          false,
        ),
      ],
      verify: (_) {
        verify(
          () => mockRemoveBatchFromFavoriteCollectionUseCase(
            favorites: tKeys,
            collectionId: 'collection_1',
          ),
        ).called(1);
      },
    );

    blocTest<FavoriteCubit, FavoriteState>(
      'removeBatchFavorites deletes exact (id, sourceId) pairs only',
      build: () {
        when(() => mockGetFavoriteCollectionsUseCase())
            .thenAnswer((_) async => [tCollection]);
        when(() => mockGetFavoritesUseCase(any())).thenAnswer(
          (_) async => [
            ...row('1', 'nhentai'),
            ...row('1', 'crotpedia'),
            ...row('2', 'nhentai'),
          ],
        );
        when(
          () => mockUserDataRepository.getFavoritesCount(
            collectionId: any(named: 'collectionId'),
          ),
        ).thenAnswer((_) async => 3);
        when(() => mockRemoveFromFavoritesUseCase(any()))
            .thenAnswer((_) async {});

        return cubit;
      },
      act: (cubit) async {
        await cubit.loadFavorites(refresh: true);
        await cubit.removeBatchFavorites(const [
          (id: '1', sourceId: 'nhentai'),
        ]);
      },
      expect: () => [
        isA<FavoriteLoading>(),
        isA<FavoriteLoaded>().having(
          (s) => s.favorites.length,
          'loaded count',
          3,
        ),
        isA<FavoriteLoaded>().having(
          (s) => s.isBatchOperating,
          'batch operating',
          true,
        ),
        isA<FavoriteLoaded>()
            .having((s) => s.favorites.length, 'remaining count', 2)
            .having((s) => s.totalCount, 'total count', 2),
      ],
      verify: (_) {
        verify(
          () => mockRemoveFromFavoritesUseCase(
            any(
              that: isA<RemoveFromFavoritesParams>()
                  .having((p) => p.contentId.value, 'contentId', '1')
                  .having((p) => p.sourceId, 'sourceId', 'nhentai'),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<FavoriteCubit, FavoriteState>(
      'selectCollection with uncategorized sentinel queries uncategorized only',
      build: () {
        when(() => mockGetFavoriteCollectionsUseCase())
            .thenAnswer((_) async => [tCollection]);
        when(() => mockGetFavoritesUseCase(any()))
            .thenAnswer((_) async => row('9', 'nhentai'));
        when(() => mockUserDataRepository.getUncategorizedCount())
            .thenAnswer((_) async => 1);

        return cubit;
      },
      act: (cubit) =>
          cubit.selectCollection(FavoriteCubit.uncategorizedCollectionId),
      expect: () => [
        isA<FavoriteLoading>(),
        isA<FavoriteLoaded>()
            .having(
              (s) => s.activeCollectionId,
              'active collection',
              FavoriteCubit.uncategorizedCollectionId,
            )
            .having((s) => s.favorites.length, 'favorites length', 1)
            .having((s) => s.totalCount, 'total count', 1),
      ],
      verify: (_) {
        verify(
          () => mockGetFavoritesUseCase(
            any(
              that: isA<GetFavoritesParams>().having(
                (p) => p.uncategorizedOnly,
                'uncategorizedOnly',
                true,
              ),
            ),
          ),
        ).called(1);
      },
    );
  });
}
