// Guards issue #84 (STRICTLY NON-REDESIGN):
// - Reader overlay auto-hide follows the user preference / remote config
//   delay instead of the hardcoded 3s, and honours the Focus-mode gate
//   (`readerAutoHideUI`).
// - The reader brightness slider persists to [UserPreferences] and is
//   re-applied when the reader opens again.
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/domain/entities/reader_position.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/reader_settings_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/reader/get_reader_settings_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/save_reader_settings_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/save_reader_position_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/clear_all_reader_positions_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/get_reader_position_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_detail_usecase.dart';
import 'package:nhasixapp/domain/usecases/history/add_to_history_usecase.dart';
import 'package:nhasixapp/presentation/cubits/network/network_cubit.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_cubit.dart';
import 'package:nhasixapp/core/services/image_metadata_service.dart';

class _MockGetContentDetailUseCase extends Mock
    implements GetContentDetailUseCase {}

class _MockGetChapterImagesUseCase extends Mock
    implements GetChapterImagesUseCase {}

class _MockAddToHistoryUseCase extends Mock implements AddToHistoryUseCase {}

class _MockGetReaderSettingsUseCase extends Mock
    implements GetReaderSettingsUseCase {}

class _MockSaveReaderSettingsUseCase extends Mock
    implements SaveReaderSettingsUseCase {}

class _MockSaveReaderPositionUseCase extends Mock
    implements SaveReaderPositionUseCase {}

class _MockClearAllReaderPositionsUseCase extends Mock
    implements ClearAllReaderPositionsUseCase {}

class _MockGetReaderPositionUseCase extends Mock
    implements GetReaderPositionUseCase {}

class _MockReaderSettingsEntityRepository extends Mock
    implements ReaderSettingsEntityRepository {}

class _MockReaderRepository extends Mock implements ReaderRepository {}

class _MockOfflineContentManager extends Mock
    implements OfflineContentManager {}

class _MockNetworkCubit extends Mock implements NetworkCubit {}

class _MockImageMetadataService extends Mock implements ImageMetadataService {}

class _MockContentSourceRegistry extends Mock
    implements ContentSourceRegistry {}

class _MockPersistCookieJar extends Mock implements PersistCookieJar {}

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockUserDataRepository extends Mock implements UserDataRepository {}

class _FakeAddToHistoryParams extends Fake implements AddToHistoryParams {}

class _FakeReaderPosition extends Fake implements ReaderPosition {}

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<bool> get enabled async => true;

  @override
  Future<void> toggle({required bool enable}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    WakelockPlusPlatformInterface.instance = _FakeWakelockPlatform();
    registerFallbackValue(_FakeAddToHistoryParams());
    registerFallbackValue(_FakeReaderPosition());
    registerFallbackValue(const UserPreferences());
  });

  Content buildContent() {
    return Content(
      id: 'sample',
      sourceId: 'hentairead',
      title: 'Sample',
      coverUrl: 'https://cover.example/s.webp',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: 2,
      imageUrls: const [
        'https://img.example/1.jpg',
        'https://img.example/2.jpg',
      ],
      uploadDate: DateTime.parse('2026-06-28T00:00:00Z'),
    );
  }

  _MockUserDataRepository stubPrefs(UserPreferences prefs) {
    final repo = _MockUserDataRepository();
    when(() => repo.getUserPreferences()).thenAnswer((_) async => prefs);
    when(() => repo.saveUserPreferences(any()))
        .thenAnswer((_) async {});
    return repo;
  }

  ReaderCubit buildCubit({_MockUserDataRepository? userDataRepository}) {
    final networkCubit = _MockNetworkCubit();
    final offlineContentManager = _MockOfflineContentManager();
    final readerSettingsEntityRepository =
        _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();
    final remoteConfigService = _MockRemoteConfigService();

    when(() => networkCubit.isConnected).thenReturn(true);
    when(() => offlineContentManager.isContentAvailableOffline(any()))
        .thenAnswer((_) async => false);
    when(() => readerSettingsEntityRepository.getReaderSettingsEntity())
        .thenAnswer((_) async => const ReaderSettingsEntity());
    when(() => readerRepository.getReaderPosition(any()))
        .thenAnswer((_) async => null);
    when(() => readerRepository.saveReaderPosition(any()))
        .thenAnswer((_) async {});
    when(() => addToHistoryUseCase(any())).thenAnswer((_) async {});

    return ReaderCubit(
      getContentDetailUseCase: _MockGetContentDetailUseCase(),
      getChapterImagesUseCase: _MockGetChapterImagesUseCase(),
      addToHistoryUseCase: addToHistoryUseCase,
      getReaderSettingsUseCase: _MockGetReaderSettingsUseCase(),
      saveReaderSettingsUseCase: _MockSaveReaderSettingsUseCase(),
      saveReaderPositionUseCase: _MockSaveReaderPositionUseCase(),
      clearAllReaderPositionsUseCase: _MockClearAllReaderPositionsUseCase(),
      getReaderPositionUseCase: _MockGetReaderPositionUseCase(),
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      networkCubit: networkCubit,
      imageMetadataService: _MockImageMetadataService(),
      httpClient: Dio(),
      contentSourceRegistry: _MockContentSourceRegistry(),
      ehentaiCookieJar: _MockPersistCookieJar(),
      remoteConfigService: remoteConfigService,
      userDataRepository: userDataRepository,
      logger: Logger(level: Level.off),
    );
  }

  Future<void> openReader(ReaderCubit cubit, Content content) async {
    await cubit.loadContent(content.id, preloadedContent: content);
  }

  group('reader auto-hide delay (issue #84)', () {
    test('overlay hides after the preference delay, not hardcoded 3s', () {
      fakeAsync((async) {
        final cubit = buildCubit(
          userDataRepository: stubPrefs(
            const UserPreferences(
              readerAutoHideUI: true,
              readerAutoHideDelay: 1,
            ),
          ),
        );
        final content = buildContent();
        openReader(cubit, content);
        async.flushMicrotasks();
        expect(cubit.state.status, ReaderStatus.loaded);

        cubit.showUI();
        async.flushMicrotasks();
        expect(cubit.state.showUI, isTrue);

        // 0.9s < 1s preference: overlay must still be visible.
        async.elapse(const Duration(milliseconds: 900));
        expect(cubit.state.showUI, isTrue);

        // Past the 1s preference (but well before the old hardcoded 3s):
        // overlay hides.
        async.elapse(const Duration(milliseconds: 200));
        expect(cubit.state.showUI, isFalse);
      });
    });

    test('long preference delay keeps overlay visible past 3s', () {
      fakeAsync((async) {
        final cubit = buildCubit(
          userDataRepository: stubPrefs(
            const UserPreferences(
              readerAutoHideUI: true,
              readerAutoHideDelay: 30,
            ),
          ),
        );
        openReader(cubit, buildContent());
        async.flushMicrotasks();

        cubit.showUI();
        async.flushMicrotasks();

        // Old hardcoded 3s would have hidden the overlay by now.
        async.elapse(const Duration(seconds: 5));
        expect(cubit.state.showUI, isTrue);
      });
    });

    test('disabled auto-hide keeps overlay visible (Focus Mode gate)', () {
      fakeAsync((async) {
        final cubit = buildCubit(
          userDataRepository: stubPrefs(
            const UserPreferences(
              readerAutoHideUI: false,
              readerAutoHideDelay: 1,
            ),
          ),
        );
        openReader(cubit, buildContent());
        async.flushMicrotasks();

        cubit.showUI();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 60));
        expect(cubit.state.showUI, isTrue);
      });
    });

    test('defaults to 3s without a preferences repository', () {
      fakeAsync((async) {
        final cubit = buildCubit();
        openReader(cubit, buildContent());
        async.flushMicrotasks();

        cubit.showUI();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.showUI, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.showUI, isFalse);
      });
    });
  });

  group('reader brightness (issue #84)', () {
    test('slider persists to UserPreferences and applies live', () async {
      final userDataRepository = stubPrefs(const UserPreferences());
      final cubit = buildCubit(userDataRepository: userDataRepository);
      await openReader(cubit, buildContent());
      expect(cubit.state.readerBrightness, 1.0);

      await cubit.setReaderBrightness(0.6);

      expect(cubit.state.readerBrightness, 0.6);
      expect(cubit.readerBrightness, 0.6);
      final saved = verify(
        () => userDataRepository.saveUserPreferences(captureAny()),
      ).captured.single as UserPreferences;
      expect(saved.readerBrightness, 0.6);
    });

    test('saved brightness is restored on next open', () async {
      final userDataRepository = stubPrefs(
        const UserPreferences(readerBrightness: 0.6),
      );
      final cubit = buildCubit(userDataRepository: userDataRepository);
      await openReader(cubit, buildContent());

      expect(cubit.state.readerBrightness, 0.6);
      expect(cubit.readerBrightness, 0.6);
    });

    test('brightness clamps to the readable 0.2..1.0 range', () async {
      final userDataRepository = stubPrefs(const UserPreferences());
      final cubit = buildCubit(userDataRepository: userDataRepository);
      await openReader(cubit, buildContent());

      await cubit.setReaderBrightness(5.0);
      expect(cubit.state.readerBrightness, 1.0);

      await cubit.setReaderBrightness(0.0);
      expect(cubit.state.readerBrightness, 0.2);
    });
  });
}
