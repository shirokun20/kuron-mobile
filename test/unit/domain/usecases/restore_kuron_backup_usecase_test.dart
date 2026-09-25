import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/favorite_collection.dart';
import 'package:nhasixapp/domain/entities/history.dart';
import 'package:nhasixapp/domain/entities/reader_position.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/settings_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_serializer.dart';
import 'package:nhasixapp/domain/usecases/exports/restore_kuron_backup_usecase.dart';

class _MockUserData extends Mock implements UserDataRepository {}

class _MockReader extends Mock implements ReaderRepository {}

class _MockSettings extends Mock implements SettingsRepository {}

FavoriteCollection _col(String id, String name) => FavoriteCollection(
      id: id,
      name: name,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

KuronBackup _backup({int favorites = 2, int malformed = 0}) => KuronBackup(
      favorites: List.generate(
        favorites,
        (i) => KuronBackupFavorite(
          id: '$i',
          sourceId: 'nhentai',
          title: 'T$i',
          coverUrl: 'c$i',
        ),
      ),
      collections: const [KuronBackupCollection(id: 'b1', name: 'Reading')],
      collectionMembers: [
        if (favorites > 0)
          const KuronBackupCollectionMember(
            collectionId: 'b1',
            favoriteId: '0',
            sourceId: 'nhentai',
          ),
      ],
      history: const [
        KuronBackupHistory(contentId: '0', sourceId: 'nhentai'),
      ],
      positions: const [
        KuronBackupPosition(contentId: '0', currentPage: 6, totalPages: 270),
        KuronBackupPosition(contentId: '1', currentPage: 0, totalPages: 0),
      ],
      settings: const {'theme_settings': '{"mode":"dark"}'},
      malformedRows: malformed,
    );

void main() {
  late _MockUserData userData;
  late _MockReader reader;
  late _MockSettings settings;
  late RestoreKuronBackupUseCase useCase;

  /// Stateful fake: a real DB reports `isFavorite == true` after the write, so
  /// the membership path must not add the same favorite twice.
  final storedFavorites = <String>{};
  final storedCollections = <String, String>{}; // name -> id
  final storedMembers = <String, Set<String>>{}; // collectionId -> favoriteIds
  final storedHistory = <String>{};
  final storedPositions = <String>{};

  setUpAll(() {
    registerFallbackValue(History(contentId: 'x', lastViewed: DateTime(2024)));
    registerFallbackValue(
        ReaderPosition.create(contentId: 'x', currentPage: 1, totalPages: 1));
  });

  setUp(() {
    storedFavorites.clear();
    storedCollections.clear();
    storedMembers.clear();
    storedHistory.clear();
    storedPositions.clear();
    // RestoreKuronBackupUseCase logs through GetIt on every catch path.
    GetIt.I.registerSingleton<Logger>(Logger());
    addTearDown(() => GetIt.I.reset());
    userData = _MockUserData();
    reader = _MockReader();
    settings = _MockSettings();
    useCase = RestoreKuronBackupUseCase(
      userDataRepository: userData,
      readerRepository: reader,
      settingsRepository: settings,
    );
  });

  void stubFresh() {
    when(() => userData.isFavorite(any(), sourceId: any(named: 'sourceId')))
        .thenAnswer(
            (i) async => storedFavorites.contains(i.positionalArguments[0]));
    when(() => userData.addToFavorites(
        id: any(named: 'id'),
        sourceId: any(named: 'sourceId'),
        coverUrl: any(named: 'coverUrl'),
        title: any(named: 'title'))).thenAnswer((i) async {
      storedFavorites.add(i.namedArguments[#id] as String);
    });
    when(() => userData.getFavoriteCollections()).thenAnswer((_) async => []);
    when(() => userData.createFavoriteCollection(name: any(named: 'name')))
        .thenAnswer((i) async => _col('c1', i.namedArguments[#name] as String));
    when(() => userData.getFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'))).thenAnswer((_) async => []);
    when(() => userData.setFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'),
        collectionIds: any(named: 'collectionIds'))).thenAnswer((_) async {});
    when(() => userData.getHistoryEntry(any())).thenAnswer((_) async => null);
    when(() => userData.saveHistory(any())).thenAnswer((_) async {});
    when(() => reader.getReaderPosition(any())).thenAnswer((_) async => null);
    when(() => reader.saveReaderPosition(any())).thenAnswer((_) async {});
    when(() => settings.importSettingsKeys(any(),
            onlyIfAbsent: any(named: 'onlyIfAbsent')))
        .thenAnswer((_) async => (applied: 1, skipped: 0));
  }

  test('preview counts every category and writes nothing', () {
    final counts = useCase.preview(_backup());
    expect(counts, {
      'favorites': 2,
      'collections': 1,
      'memberships': 1,
      'history': 1,
      'positions': 2,
      'settings': 1,
    });
    verifyZeroInteractions(userData);
    verifyZeroInteractions(reader);
    verifyZeroInteractions(settings);
  });

  test('fresh restore adds everything and reports unreadable rows', () async {
    stubFresh();
    final summary = await useCase.restore(_backup(malformed: 2));

    expect(summary['favorites'], (success: 2, skipped: 0, failed: 0));
    expect(summary['collections'], (success: 1, skipped: 0, failed: 0));
    expect(summary['history'], (success: 1, skipped: 0, failed: 0));
    expect(summary['positions'], (success: 2, skipped: 0, failed: 0));
    expect(summary['settings'], (success: 1, skipped: 0, failed: 0));
    expect(summary['malformed'], (success: 0, skipped: 0, failed: 2));

    // Membership had a foreign key on favorites, so the favorite is ensured.
    verify(() => userData.addToFavorites(
        id: '0', sourceId: 'nhentai', coverUrl: 'c0', title: 'T0')).called(1);
    final positions = verify(() => reader.saveReaderPosition(captureAny()))
        .captured
        .cast<ReaderPosition>();
    expect(positions.map((p) => p.currentPage), [6, 1]); // 0 floored to 1
  });

  test('existing data is never overwritten', () async {
    stubFresh();
    when(() => userData.isFavorite(any(), sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async => true);
    when(() => userData.getFavoriteCollections())
        .thenAnswer((_) async => [_col('c9', 'Reading')]);
    when(() => userData.getFavoriteCollectionIds(
        favoriteId: any(named: 'favoriteId'),
        sourceId: any(named: 'sourceId'))).thenAnswer((_) async => ['c9']);
    when(() => userData.getHistoryEntry(any())).thenAnswer(
        (_) async => History(contentId: '0', lastViewed: DateTime(2024)));
    when(() => reader.getReaderPosition(any())).thenAnswer((_) async =>
        ReaderPosition.create(contentId: '0', currentPage: 2, totalPages: 10));
    when(() => settings.importSettingsKeys(any(),
            onlyIfAbsent: any(named: 'onlyIfAbsent')))
        .thenAnswer((_) async => (applied: 0, skipped: 1));

    final summary = await useCase.restore(_backup());

    expect(summary['favorites']!.skipped, 2);
    expect(summary['collections']!.skipped, 1);
    expect(summary['history']!.skipped, 1);
    expect(summary['positions']!.skipped, 2);
    expect(summary['settings'], (success: 0, skipped: 1, failed: 0));
    verifyNever(() => userData.addToFavorites(
        id: any(named: 'id'),
        sourceId: any(named: 'sourceId'),
        coverUrl: any(named: 'coverUrl'),
        title: any(named: 'title')));
    verifyNever(
        () => userData.createFavoriteCollection(name: any(named: 'name')));
  });

  test('settings are applied with onlyIfAbsent so the device wins', () async {
    stubFresh();
    await useCase.restore(_backup());
    verify(() => settings.importSettingsKeys(
          {'theme_settings': '{"mode":"dark"}'},
          onlyIfAbsent: true,
        )).called(1);
  });

  test('a membership whose collection row is missing counts as failed',
      () async {
    stubFresh();
    final summary = await useCase.restore(const KuronBackup(
      collectionMembers: [
        KuronBackupCollectionMember(
            collectionId: 'ghost', favoriteId: '1', sourceId: 'nhentai'),
      ],
    ));
    expect(summary['collections'], (success: 0, skipped: 0, failed: 1));
  });

  test('empty backup restores nothing and reports zeros', () async {
    stubFresh();
    final summary = await useCase.restore(const KuronBackup());
    expect(
      summary.values
          .every((r) => r.success == 0 && r.skipped == 0 && r.failed == 0),
      isTrue,
    );
    verifyNever(() => userData.addToFavorites(
        id: any(named: 'id'),
        sourceId: any(named: 'sourceId'),
        coverUrl: any(named: 'coverUrl'),
        title: any(named: 'title')));
  });

  test('a settings failure fails the category without aborting the rest',
      () async {
    stubFresh();
    when(() => settings.importSettingsKeys(any(),
            onlyIfAbsent: any(named: 'onlyIfAbsent')))
        .thenThrow(StateError('nope'));
    final summary = await useCase.restore(_backup());
    expect(summary['settings'], (success: 0, skipped: 0, failed: 1));
    expect(summary['history']!.success, 1);
  });

  test('parseBytesAsync reads a zip payload off the UI isolate', () async {
    final zip = KuronBackupSerializer.toZipBytesFromBackup(_backup());
    final parsed = await useCase.parseBytesAsync(zip);
    expect(parsed.favorites.length, 2);
    expect(parsed.positions.first.currentPage, 6);
  });
}
