import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/favorite_collection.dart';
import 'package:nhasixapp/domain/entities/history.dart';
import 'package:nhasixapp/domain/entities/reader_position.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/imports/import_nclient_backup_usecase.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup.dart';

class MockKuronNative extends Mock implements KuronNative {}

class MockUserData extends Mock implements UserDataRepository {}

class MockReader extends Mock implements ReaderRepository {}

NclientBackup sample() => const NclientBackup(
      galleries: [
        NclientGallery(
            idGallery: 1,
            titlePretty: 'G1',
            mediaId: 11,
            pages: '5;/cover.jpg.webp;/thumb.jpg.webp;'),
        NclientGallery(
            idGallery: 2,
            titlePretty: 'G2',
            mediaId: 22,
            pages: '3;/cover.webp;/thumb.webp;'),
      ],
      favorites: [NclientFavorite(galleryId: 1)],
      statuses: [NclientStatus(name: 'Reading'), NclientStatus(name: 'None')],
      statusLinks: [NclientStatusLink(galleryId: 2, name: 'Reading')],
      history: [
        NclientHistory(
            id: 1,
            title: 'G1',
            thumbType: 'https://t/book/thumb.webp',
            time: 1700000000000)
      ],
      resumes: [NclientResume(galleryId: 2, page: 2)],
    );

FavoriteCollection col(String id, String name) => FavoriteCollection(
      id: id,
      name: name,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(History(contentId: 'x', lastViewed: DateTime(2024)));
    registerFallbackValue(
        ReaderPosition.create(contentId: 'x', currentPage: 1, totalPages: 1));
  });
  late MockUserData userData;
  late MockReader reader;
  late ImportNclientBackupUseCase useCase;

  setUp(() {
    userData = MockUserData();
    reader = MockReader();
    useCase = ImportNclientBackupUseCase(
      kuronNative: MockKuronNative(),
      userDataRepository: userData,
      readerRepository: reader,
    );
  });

  void stubFresh() {
    when(() => userData.isFavorite(any(), sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async => false);
    when(() => userData.getFavoriteCollections()).thenAnswer((_) async => []);
    when(() => userData.createFavoriteCollection(name: any(named: 'name')))
        .thenAnswer((i) async => col('c1', i.namedArguments[#name] as String));
    when(() => userData.getFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'))).thenAnswer((_) async => []);
    when(() => userData.setFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'),
        collectionIds: any(named: 'collectionIds'))).thenAnswer((_) async {});
    when(() => userData.addToFavorites(
        id: any(named: 'id'),
        sourceId: any(named: 'sourceId'),
        coverUrl: any(named: 'coverUrl'),
        title: any(named: 'title'))).thenAnswer((_) async {});
    when(() => userData.getHistoryEntry(any())).thenAnswer((_) async => null);
    when(() => userData.saveHistory(any())).thenAnswer((_) async {});
    when(() => reader.getReaderPosition(any())).thenAnswer((_) async => null);
    when(() => reader.saveReaderPosition(any())).thenAnswer((_) async {});
  }

  test('preview counts without writes', () {
    final counts = useCase.preview(sample());
    expect(counts, {
      'favorites': 1,
      'collections': 1, // "None" has no members -> excluded
      'memberships': 1,
      'history': 1,
      'positions': 1,
    });
    verifyZeroInteractions(userData);
    verifyZeroInteractions(reader);
  });

  test('fresh import succeeds all', () async {
    stubFresh();
    final summary = await useCase.import(sample());
    expect(summary['favorites'], (success: 2, skipped: 0, failed: 0));
    expect(summary['collections'], (success: 1, skipped: 0, failed: 0));
    expect(summary['history'], (success: 1, skipped: 0, failed: 0));
    expect(summary['positions'], (success: 1, skipped: 0, failed: 0));
    // cover rebuilt from mediaId + last-dot ext (double-ext -> webp)
    verify(() => userData.addToFavorites(
        id: '1',
        sourceId: 'nhentai',
        coverUrl: 'https://t.nhentai.net/galleries/11/cover.webp',
        title: 'G1')).called(1);
    // history keeps thumbType URL + time
    final saved = verify(() => userData.saveHistory(captureAny()))
        .captured
        .single as History;
    expect(saved.coverUrl, 'https://t/book/thumb.webp');
    expect(
        saved.lastViewed, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    final pos = verify(() => reader.saveReaderPosition(captureAny()))
        .captured
        .single as ReaderPosition;
    expect((pos.currentPage, pos.totalPages), (2, 3));
  });

  test('full duplicates all skipped', () async {
    stubFresh();
    when(() => userData.isFavorite(any(), sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async => true);
    when(() => userData.getFavoriteCollections())
        .thenAnswer((_) async => [col('c9', 'Reading')]);
    when(() => userData.getFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'))).thenAnswer((_) async => ['c9']);
    when(() => userData.getHistoryEntry(any())).thenAnswer(
        (_) async => History(contentId: '1', lastViewed: DateTime(2024)));
    when(() => reader.getReaderPosition(any())).thenAnswer((_) async =>
        ReaderPosition.create(contentId: '2', currentPage: 2, totalPages: 3));
    final summary = await useCase.import(sample());
    expect(summary['favorites']!.success, 0);
    expect(summary['favorites']!.skipped, 2); // fav + membership ensure
    expect(summary['collections']!.skipped, 1);
    expect(summary['history']!.skipped, 1);
    expect(summary['positions']!.skipped, 1);
    verifyNever(
        () => userData.createFavoriteCollection(name: any(named: 'name')));
  });

  test('empty backup imports nothing', () async {
    stubFresh();
    final summary = await useCase.import(const NclientBackup());
    expect(
        summary.values
            .every((r) => r.success == 0 && r.skipped == 0 && r.failed == 0),
        isTrue);
  });
}
