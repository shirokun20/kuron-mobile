import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/domain/entities/reader_position.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/reader_settings_repository.dart';
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

class _FakeGetContentDetailParams extends Fake
    implements GetContentDetailParams {}

class _FakeGetChapterImagesParams extends Fake
    implements GetChapterImagesParams {}

class _FakeAddToHistoryParams extends Fake implements AddToHistoryParams {}

class _FakeReaderPosition extends Fake implements ReaderPosition {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeGetContentDetailParams());
    registerFallbackValue(_FakeGetChapterImagesParams());
    registerFallbackValue(_FakeAddToHistoryParams());
    registerFallbackValue(_FakeReaderPosition());
  });

  Content buildContent({
    required String id,
    required String sourceId,
    required List<String> imageUrls,
  }) {
    return Content(
      id: id,
      sourceId: sourceId,
      title: 'Sample',
      coverUrl: 'https://cover.example/$id.webp',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: imageUrls.length,
      imageUrls: imageUrls,
      uploadDate: DateTime.parse('2026-06-28T00:00:00Z'),
    );
  }

  test(
      'uses preloaded no-chapters content shell and skips detail refetch for hentairead',
      () async {
    final getContentDetailUseCase = _MockGetContentDetailUseCase();
    final getChapterImagesUseCase = _MockGetChapterImagesUseCase();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();
    final getReaderSettingsUseCase = _MockGetReaderSettingsUseCase();
    final saveReaderSettingsUseCase = _MockSaveReaderSettingsUseCase();
    final saveReaderPositionUseCase = _MockSaveReaderPositionUseCase();
    final clearAllReaderPositionsUseCase =
        _MockClearAllReaderPositionsUseCase();
    final getReaderPositionUseCase = _MockGetReaderPositionUseCase();
    final readerSettingsEntityRepository =
        _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final offlineContentManager = _MockOfflineContentManager();
    final networkCubit = _MockNetworkCubit();
    final imageMetadataService = _MockImageMetadataService();
    final contentSourceRegistry = _MockContentSourceRegistry();
    final ehentaiCookieJar = _MockPersistCookieJar();
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
    when(() => getChapterImagesUseCase(any())).thenAnswer(
      (_) async => const ChapterData(
        images: ['https://henread.xyz/294075/87911/hr_0001.jpg'],
      ),
    );

    final cubit = ReaderCubit(
      getContentDetailUseCase: getContentDetailUseCase,
      getChapterImagesUseCase: getChapterImagesUseCase,
      addToHistoryUseCase: addToHistoryUseCase,
      getReaderSettingsUseCase: getReaderSettingsUseCase,
      saveReaderSettingsUseCase: saveReaderSettingsUseCase,
      saveReaderPositionUseCase: saveReaderPositionUseCase,
      clearAllReaderPositionsUseCase: clearAllReaderPositionsUseCase,
      getReaderPositionUseCase: getReaderPositionUseCase,
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      networkCubit: networkCubit,
      imageMetadataService: imageMetadataService,
      httpClient: Dio(),
      contentSourceRegistry: contentSourceRegistry,
      ehentaiCookieJar: ehentaiCookieJar,
      remoteConfigService: remoteConfigService,
      logger: Logger(level: Level.all),
    );

    final preloadedContent = buildContent(
      id: 'mama-no-saikon-aite-wa-papakatsu-no-papa',
      sourceId: 'hentairead',
      imageUrls: const [],
    );

    await cubit.loadContent(
      preloadedContent.id,
      preloadedContent: preloadedContent,
    );

    verifyNever(() => getContentDetailUseCase(any()));
    verify(() => getChapterImagesUseCase(any())).called(1);
    expect(cubit.state.content?.imageUrls, hasLength(1));
    expect(
      cubit.state.content?.imageUrls.first,
      'https://henread.xyz/294075/87911/hr_0001.jpg',
    );
  });

  test(
      'still fetches fallback images for no-chapters shell when network state is late',
      () async {
    final getContentDetailUseCase = _MockGetContentDetailUseCase();
    final getChapterImagesUseCase = _MockGetChapterImagesUseCase();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();
    final getReaderSettingsUseCase = _MockGetReaderSettingsUseCase();
    final saveReaderSettingsUseCase = _MockSaveReaderSettingsUseCase();
    final saveReaderPositionUseCase = _MockSaveReaderPositionUseCase();
    final clearAllReaderPositionsUseCase =
        _MockClearAllReaderPositionsUseCase();
    final getReaderPositionUseCase = _MockGetReaderPositionUseCase();
    final readerSettingsEntityRepository =
        _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final offlineContentManager = _MockOfflineContentManager();
    final networkCubit = _MockNetworkCubit();
    final imageMetadataService = _MockImageMetadataService();
    final contentSourceRegistry = _MockContentSourceRegistry();
    final ehentaiCookieJar = _MockPersistCookieJar();
    final remoteConfigService = _MockRemoteConfigService();

    when(() => networkCubit.isConnected).thenReturn(false);
    when(() => offlineContentManager.isContentAvailableOffline(any()))
        .thenAnswer((_) async => false);
    when(() => readerSettingsEntityRepository.getReaderSettingsEntity())
        .thenAnswer((_) async => const ReaderSettingsEntity());
    when(() => readerRepository.getReaderPosition(any()))
        .thenAnswer((_) async => null);
    when(() => readerRepository.saveReaderPosition(any()))
        .thenAnswer((_) async {});
    when(() => addToHistoryUseCase(any())).thenAnswer((_) async {});
    when(() => getChapterImagesUseCase(any())).thenAnswer(
      (_) async => const ChapterData(
        images: ['https://images.hentainexus.com/1.webp'],
      ),
    );

    final cubit = ReaderCubit(
      getContentDetailUseCase: getContentDetailUseCase,
      getChapterImagesUseCase: getChapterImagesUseCase,
      addToHistoryUseCase: addToHistoryUseCase,
      getReaderSettingsUseCase: getReaderSettingsUseCase,
      saveReaderSettingsUseCase: saveReaderSettingsUseCase,
      saveReaderPositionUseCase: saveReaderPositionUseCase,
      clearAllReaderPositionsUseCase: clearAllReaderPositionsUseCase,
      getReaderPositionUseCase: getReaderPositionUseCase,
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      networkCubit: networkCubit,
      imageMetadataService: imageMetadataService,
      httpClient: Dio(),
      contentSourceRegistry: contentSourceRegistry,
      ehentaiCookieJar: ehentaiCookieJar,
      remoteConfigService: remoteConfigService,
      logger: Logger(level: Level.all),
    );

    final preloadedContent = buildContent(
      id: '21724',
      sourceId: 'hentainexus',
      imageUrls: const [],
    );

    await cubit.loadContent(
      preloadedContent.id,
      preloadedContent: preloadedContent,
    );

    verifyNever(() => getContentDetailUseCase(any()));
    verify(() => getChapterImagesUseCase(any())).called(1);
    expect(cubit.state.content?.imageUrls,
        ['https://images.hentainexus.com/1.webp']);
  });

  // Issue #68 follow-up: a video chapter resolves to 0 images + 1 stream. Every
  // page clamp then ran against `clamp(1, 0)`, which throws ArgumentError — the
  // reader screen died instead of showing the play card.
  test('page-less video chapter never throws on page clamps', () async {
    final getContentDetailUseCase = _MockGetContentDetailUseCase();
    final getChapterImagesUseCase = _MockGetChapterImagesUseCase();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();
    final getReaderSettingsUseCase = _MockGetReaderSettingsUseCase();
    final saveReaderSettingsUseCase = _MockSaveReaderSettingsUseCase();
    final saveReaderPositionUseCase = _MockSaveReaderPositionUseCase();
    final clearAllReaderPositionsUseCase =
        _MockClearAllReaderPositionsUseCase();
    final getReaderPositionUseCase = _MockGetReaderPositionUseCase();
    final readerSettingsEntityRepository =
        _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final offlineContentManager = _MockOfflineContentManager();
    final networkCubit = _MockNetworkCubit();
    final imageMetadataService = _MockImageMetadataService();
    final contentSourceRegistry = _MockContentSourceRegistry();
    final ehentaiCookieJar = _MockPersistCookieJar();
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
    when(() => getChapterImagesUseCase(any())).thenAnswer(
      (_) async => const ChapterData(
        images: [],
        videoUrls: ['https://sv1.example.com/videos/ep1/master.m3u8'],
      ),
    );

    final cubit = ReaderCubit(
      getContentDetailUseCase: getContentDetailUseCase,
      getChapterImagesUseCase: getChapterImagesUseCase,
      addToHistoryUseCase: addToHistoryUseCase,
      getReaderSettingsUseCase: getReaderSettingsUseCase,
      saveReaderSettingsUseCase: saveReaderSettingsUseCase,
      saveReaderPositionUseCase: saveReaderPositionUseCase,
      clearAllReaderPositionsUseCase: clearAllReaderPositionsUseCase,
      getReaderPositionUseCase: getReaderPositionUseCase,
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      networkCubit: networkCubit,
      imageMetadataService: imageMetadataService,
      httpClient: Dio(),
      contentSourceRegistry: contentSourceRegistry,
      ehentaiCookieJar: ehentaiCookieJar,
      remoteConfigService: remoteConfigService,
      logger: Logger(level: Level.all),
    );

    final preloadedContent = buildContent(
      id: 'ai-animation-catastrophic/ep1/',
      sourceId: 'mangadistrict',
      imageUrls: const [],
    );

    await cubit.loadContent(
      preloadedContent.id,
      preloadedContent: preloadedContent,
    );

    expect(cubit.state.chapterData?.videoUrls, hasLength(1));
    expect(cubit.state.content?.imageUrls, isEmpty);

    // Every entry point a reader touches on open must survive 0 pages.
    expect(() => cubit.goToPage(3), returnsNormally);
    expect(() => cubit.updateCurrentPageSilent(2), returnsNormally);
    expect(() => cubit.updateCurrentPageFromSwipe(4), returnsNormally);
    expect(() => cubit.previousPage(), returnsNormally);
    expect(() => cubit.nextPage(), returnsNormally);
    expect(() => cubit.jumpToPage(1), returnsNormally);
  });
}
