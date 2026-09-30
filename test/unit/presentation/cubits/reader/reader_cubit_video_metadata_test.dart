// A gallery whose detail page IS the chapter: does the reader ever learn
// there is a video?
//
// cosplaytele has `features.chapters=false`, no `detail.chapters`, and
// `urlPatterns.chapter = /{id}` — one page serves as both. `getDetail`
// hydrates `content.imageUrls` from it (110 photos), so the reader used to ask
// the chapter endpoint ONLY when `imageUrls` was empty. That endpoint is the
// one place `reader.video` becomes `videoUrls`/`videoIndex`, so the config
// block parsed correctly and the reader still showed photos with no video card.
//
// The gate must therefore also open for a source that declares `reader.video`
// and has no chapter data yet — and must stay shut for every other source, so
// the other 103 pay no extra fetch.
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/domain/entities/reader_position.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/domain/repositories/reader_repository.dart';
import 'package:nhasixapp/domain/repositories/reader_settings_repository.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_detail_usecase.dart';
import 'package:nhasixapp/domain/usecases/history/add_to_history_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/clear_all_reader_positions_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/get_reader_position_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/get_reader_settings_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/save_reader_position_usecase.dart';
import 'package:nhasixapp/domain/usecases/reader/save_reader_settings_usecase.dart';
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

  Content galleryContent({
    required String id,
    required String sourceId,
    required List<String> imageUrls,
  }) =>
      Content(
        id: id,
        sourceId: sourceId,
        title: 'Hiyuki',
        coverUrl: 'https://cosplaytele.example/cover.webp',
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

  /// cosplaytele's real config shape, trimmed to what the gate reads.
  Map<String, dynamic> configDeclaringVideo() => <String, dynamic>{
        'source': 'cosplaytele',
        'version': '1.0.1',
        'scraper': {
          'selectors': {
            'reader': {
              'container': '.entry-content.single-page',
              'images': {
                'selector': '.entry-content.single-page .gallery-item img',
                'attribute': 'src',
              },
              'video': {
                'container': '.entry-content.single-page',
                'selector': 'iframe[src*="cossora.stream"]',
                'attribute': 'src',
              },
            },
          },
        },
      };

  Map<String, dynamic> configWithoutVideo() => <String, dynamic>{
        'source': 'plain',
        'version': '1.0.0',
        'scraper': {
          'selectors': {
            'reader': {
              'container': '.entry-content.single-page',
              'images': {'selector': 'img', 'attribute': 'src'},
            },
          },
        },
      };

  ReaderCubit buildCubit({
    required _MockGetChapterImagesUseCase getChapterImagesUseCase,
    required _MockNetworkCubit networkCubit,
    required _MockRemoteConfigService remoteConfigService,
    required _MockReaderSettingsEntityRepository readerSettingsEntityRepository,
    required _MockReaderRepository readerRepository,
    required _MockOfflineContentManager offlineContentManager,
    required _MockAddToHistoryUseCase addToHistoryUseCase,
  }) =>
      ReaderCubit(
        getContentDetailUseCase: _MockGetContentDetailUseCase(),
        getChapterImagesUseCase: getChapterImagesUseCase,
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
        logger: Logger(level: Level.off),
      );

  void stubShared(
    _MockNetworkCubit networkCubit,
    _MockOfflineContentManager offlineContentManager,
    _MockReaderSettingsEntityRepository readerSettingsEntityRepository,
    _MockReaderRepository readerRepository,
    _MockAddToHistoryUseCase addToHistoryUseCase,
  ) {
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
  }

  test(
      'hydrated gallery pages still resolve the video block into chapterData',
      () async {
    final getChapterImagesUseCase = _MockGetChapterImagesUseCase();
    final networkCubit = _MockNetworkCubit();
    final remoteConfigService = _MockRemoteConfigService();
    final readerSettingsEntityRepository =
        _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final offlineContentManager = _MockOfflineContentManager();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();

    stubShared(
      networkCubit,
      offlineContentManager,
      readerSettingsEntityRepository,
      readerRepository,
      addToHistoryUseCase,
    );

    when(() => remoteConfigService.getRawConfig('cosplaytele'))
        .thenReturn(configDeclaringVideo());
    when(() => getChapterImagesUseCase(any())).thenAnswer(
      (_) async => const ChapterData(
        images: [
          'https://cosplaytele.example/01.webp',
          'https://cosplaytele.example/02.webp',
        ],
        videoUrls: ['https://cossora.stream/embed/c74c438d'],
        videoIndex: 0,
      ),
    );

    final cubit = buildCubit(
      getChapterImagesUseCase: getChapterImagesUseCase,
      networkCubit: networkCubit,
      remoteConfigService: remoteConfigService,
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      addToHistoryUseCase: addToHistoryUseCase,
    );

    // The detail page already hydrated three pages — the old gate never fired.
    final preloaded = galleryContent(
      id: 'hiyuki-2',
      sourceId: 'cosplaytele',
      imageUrls: const [
        'https://cosplaytele.example/01.webp',
        'https://cosplaytele.example/02.webp',
        'https://cosplaytele.example/03.webp',
      ],
    );

    await cubit.loadContent(preloaded.id, preloadedContent: preloaded);

    verify(() => getChapterImagesUseCase(any())).called(1);
    expect(
      cubit.state.chapterData?.videoUrls,
      ['https://cossora.stream/embed/c74c438d'],
    );
    expect(
      cubit.state.chapterData?.videoIndex,
      0,
      reason: 'the embed sits above every photo, so no page precedes it',
    );
    expect(
      cubit.state.content?.imageUrls,
      hasLength(3),
      reason: 'hydrated pages must survive a metadata-only refetch',
    );
  });

  test('a source without a video block pays no extra chapter fetch', () async {
    final getChapterImagesUseCase = _MockGetChapterImagesUseCase();
    final networkCubit = _MockNetworkCubit();
    final remoteConfigService = _MockRemoteConfigService();
    final readerSettingsEntityRepository = _MockReaderSettingsEntityRepository();
    final readerRepository = _MockReaderRepository();
    final offlineContentManager = _MockOfflineContentManager();
    final addToHistoryUseCase = _MockAddToHistoryUseCase();

    stubShared(
      networkCubit,
      offlineContentManager,
      readerSettingsEntityRepository,
      readerRepository,
      addToHistoryUseCase,
    );

    when(() => remoteConfigService.getRawConfig('plain'))
        .thenReturn(configWithoutVideo());
    when(() => remoteConfigService.getRawConfig(any()))
        .thenReturn(configWithoutVideo());

    final cubit = buildCubit(
      getChapterImagesUseCase: getChapterImagesUseCase,
      networkCubit: networkCubit,
      remoteConfigService: remoteConfigService,
      readerSettingsEntityRepository: readerSettingsEntityRepository,
      readerRepository: readerRepository,
      offlineContentManager: offlineContentManager,
      addToHistoryUseCase: addToHistoryUseCase,
    );

    final preloaded = galleryContent(
      id: 'plain-gallery',
      sourceId: 'plain',
      imageUrls: const ['https://plain.example/01.jpg'],
    );

    await cubit.loadContent(preloaded.id, preloadedContent: preloaded);

    verifyNever(() => getChapterImagesUseCase(any()));
    expect(cubit.state.chapterData, isNull);
  });
}