import 'dart:async'; // Add async import for StreamController
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kuron_core/kuron_core.dart'
    show ChapterData, Content, ContentSourceRegistry;
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/usecases/content/content_usecases.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/domain/usecases/downloads/downloads_usecases.dart';
import 'package:nhasixapp/domain/repositories/repositories.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:nhasixapp/core/services/pdf_conversion_queue_manager.dart';
import 'package:nhasixapp/core/services/pdf_conversion_service.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/services/download_manager.dart'; // Import DownloadManager
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mocks
class MockDownloadContentUseCase extends Mock
    implements DownloadContentUseCase {}

class MockGetContentDetailUseCase extends Mock
    implements GetContentDetailUseCase {}

class MockGetChapterImagesUseCase extends Mock
    implements GetChapterImagesUseCase {}

class MockUserDataRepository extends Mock implements UserDataRepository {}

class MockLogger extends Mock implements Logger {}

class MockConnectivity extends Mock implements Connectivity {}

class MockNotificationService extends Mock implements NotificationService {}

class MockPdfConversionService extends Mock implements PdfConversionService {}

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

class MockDownloadManager extends Mock
    implements DownloadManager {} // Add MockDownloadManager

class MockOfflineContentManager extends Mock implements OfflineContentManager {}

class MockPdfConversionQueueManager extends Mock
    implements PdfConversionQueueManager {} // Add MockDownloadManager

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('DownloadBloc Completion Logic', () {
    late DownloadBloc downloadBloc;
    late MockDownloadContentUseCase mockDownloadContentUseCase;
    late MockGetContentDetailUseCase mockGetContentDetailUseCase;
    late MockGetChapterImagesUseCase mockGetChapterImagesUseCase;
    late MockUserDataRepository mockRepo;
    late MockConnectivity mockConnectivity;
    late MockNotificationService mockNotificationService;
    late MockPdfConversionService mockPdfConversionService;
    late MockRemoteConfigService mockRemoteConfigService;
    late MockDownloadManager mockDownloadManager; // Add MockDownloadManager
    late MockOfflineContentManager mockOfflineContentManager;
    late MockPdfConversionQueueManager mockPdfConversionQueueManager;
    late MockLogger mockLogger;
    late Directory completionGuardTempDir;

    // Stream controller for DownloadManager progress
    late StreamController<DownloadProgressUpdate> progressController;

    const testContentId = '123';
    const testDownloadStatus = DownloadStatus(
      contentId: testContentId,
      state: DownloadState.downloading,
      downloadedPages: 10,
      totalPages: 10,
      title: 'Test Manga',
      sourceId: 'src',
    );

    setUp(() async {
      mockDownloadContentUseCase = MockDownloadContentUseCase();
      mockGetContentDetailUseCase = MockGetContentDetailUseCase();
      mockGetChapterImagesUseCase = MockGetChapterImagesUseCase();
      mockRepo = MockUserDataRepository();
      mockConnectivity = MockConnectivity();
      mockNotificationService = MockNotificationService();
      mockPdfConversionService = MockPdfConversionService();
      mockRemoteConfigService = MockRemoteConfigService();
      mockDownloadManager = MockDownloadManager();
      mockOfflineContentManager = MockOfflineContentManager();
      mockPdfConversionQueueManager = MockPdfConversionQueueManager();
      mockLogger = MockLogger();
      progressController = StreamController<DownloadProgressUpdate>.broadcast();
      completionGuardTempDir =
          Directory.systemTemp.createTempSync('download-bloc-empty-');

      registerFallbackValue(
        GetContentDetailParams.fromString('fallback-content-id'),
      );
      registerFallbackValue(
        GetChapterImagesParams.fromString('fallback-chapter-id'),
      );
      registerFallbackValue(
        DownloadContentParams.immediate(
          Content(
            id: 'fallback-content-id',
            sourceId: 'fallback-source',
            title: 'Fallback Content',
            coverUrl: '',
            tags: const [],
            artists: const [],
            characters: const [],
            parodies: const [],
            groups: const [],
            language: 'en',
            pageCount: 1,
            imageUrls: const ['https://example.com/page-1.jpg'],
            uploadDate: DateTime(2026, 1, 1),
          ),
          savePath: '/tmp/fallback-content',
        ),
      );

      // Stub DownloadManager properties
      when(() => mockDownloadManager.progressStream)
          .thenAnswer((_) => progressController.stream);
      when(() => mockDownloadManager.unregisterTask(any())).thenReturn(null);

      // Register fallback values
      registerFallbackValue(testDownloadStatus);

      // Default mocks
      // Note: mocktail matches named arguments by matching the value passed to the name
      when(() => mockRepo.getAllDownloads(
            state: any(named: 'state'),
            sourceId: any(named: 'sourceId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => [testDownloadStatus]);
      when(() => mockRepo.getUserPreferences()).thenAnswer(
          (_) async => const UserPreferences()); // Use default constructor
      when(() => mockRepo.saveDownloadStatus(any()))
          .thenAnswer((_) async => {});
      when(() => mockRepo.getDownloadStatus(any()))
          .thenAnswer((_) async => testDownloadStatus);

      // Notification service mocks
      when(() => mockNotificationService.initialize())
          .thenAnswer((_) async => {});
      when(() => mockNotificationService.setCallbacks(
            onDownloadPause: any(named: 'onDownloadPause'),
            onDownloadResume: any(named: 'onDownloadResume'),
            onDownloadCancel: any(named: 'onDownloadCancel'),
            onDownloadRetry: any(named: 'onDownloadRetry'),
            onPdfRetry: any(named: 'onPdfRetry'),
            onOpenDownload: any(named: 'onOpenDownload'),
            onNavigateToDownloads: any(named: 'onNavigateToDownloads'),
          )).thenReturn(null);

      when(() => mockNotificationService.showDownloadCompleted(
            contentId: any(named: 'contentId'),
            title: any(named: 'title'),
            downloadPath: any(named: 'downloadPath'),
          )).thenAnswer((_) async => {});
      when(() => mockNotificationService.showDownloadStarted(
            contentId: any(named: 'contentId'),
            title: any(named: 'title'),
          )).thenAnswer((_) async => {});

      when(() => mockNotificationService.updateDownloadGroupProgress(
            activeCount: any(named: 'activeCount'),
            totalProgress: any(named: 'totalProgress'),
            speedText: any(named: 'speedText'),
          )).thenAnswer((_) async => {});

      when(() => mockNotificationService.showDownloadGroupCompleted(any()))
          .thenAnswer((_) async => {});

      when(() => mockNotificationService.cancelDownloadNotification(any()))
          .thenAnswer((_) async => {});

      when(() => mockNotificationService.showPdfConversionError(
            contentId: any(named: 'contentId'),
            title: any(named: 'title'),
            error: any(named: 'error'),
          )).thenAnswer((_) async => {});
      when(() => mockOfflineContentManager
              .reconcileChapterMetadataForCompletedDownload(
            contentId: any(named: 'contentId'),
            contentPath: any(named: 'contentPath'),
          )).thenAnswer((_) async => {});
      when(() => mockRemoteConfigService.getRawConfig(any())).thenReturn({
        'network': {
          'headers': {
            'User-Agent': 'UnitTest',
            'Referer': 'https://e-hentai.org/',
          },
        },
      });

      await getIt.reset();
      getIt.registerSingleton<RemoteConfigService>(mockRemoteConfigService);
      getIt.registerSingleton<ContentSourceRegistry>(ContentSourceRegistry());

      downloadBloc = DownloadBloc(
        downloadContentUseCase: mockDownloadContentUseCase,
        getContentDetailUseCase: mockGetContentDetailUseCase,
        getChapterImagesUseCase: mockGetChapterImagesUseCase,
        userDataRepository: mockRepo,
        offlineContentManager: mockOfflineContentManager,
        logger: mockLogger,
        connectivity: mockConnectivity,
        notificationService: mockNotificationService,
        pdfConversionService: mockPdfConversionService,
        remoteConfigService: mockRemoteConfigService,
        downloadManager: mockDownloadManager,
        pdfConversionQueueManager: mockPdfConversionQueueManager,
      );

      // Initialize to get into Loaded state
      // Instead of async setup, we will use seed in blocTest
    });

    tearDown(() async {
      await progressController.close();
      await downloadBloc.close();
      await getIt.reset();
      if (completionGuardTempDir.existsSync()) {
        completionGuardTempDir.deleteSync(recursive: true);
      }
    });

    blocTest<DownloadBloc, DownloadBlocState>(
      'marks download as failed when completion arrives but no image file exists',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: [
          DownloadStatus(
            contentId: testContentId,
            state: DownloadState.downloading,
            downloadedPages: 10,
            totalPages: 10,
            title: 'Test Manga',
            sourceId: 'src',
            downloadPath: completionGuardTempDir.path,
          ),
        ],
        settings: const DownloadSettings(
          autoRetry: false,
          enableNotifications: false,
        ),
        lastUpdated: DateTime.now(),
      ),
      act: (bloc) => bloc.add(const DownloadCompletedEvent(testContentId)),
      wait: const Duration(milliseconds: 30),
      verify: (_) {
        verify(
          () => mockRepo.saveDownloadStatus(
            any(
              that: predicate<DownloadStatus>(
                (d) =>
                    d.contentId == testContentId &&
                    d.state == DownloadState.failed &&
                    (d.error?.contains(
                          'Native download completed without saved image files',
                        ) ??
                        false),
              ),
            ),
          ),
        ).called(1);

        verifyNever(
          () => mockNotificationService.showDownloadCompleted(
            contentId: any(named: 'contentId'),
            title: any(named: 'title'),
            downloadPath: any(named: 'downloadPath'),
          ),
        );
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'emits completed state and saves to DB when DownloadCompletedEvent is added',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: [testDownloadStatus],
        settings: DownloadSettings.defaultSettings(),
        lastUpdated: DateTime.now(),
      ),
      act: (bloc) => bloc.add(const DownloadCompletedEvent(testContentId)),
      verify: (bloc) {
        verify(() => mockRepo.saveDownloadStatus(any(
            that: predicate<DownloadStatus>((d) =>
                d.contentId == testContentId &&
                d.state == DownloadState.completed &&
                d.endTime != null)))).called(1);

        verify(() => mockOfflineContentManager
                .reconcileChapterMetadataForCompletedDownload(
              contentId: testContentId,
              contentPath: any(named: 'contentPath'),
            )).called(1);
      },
      expect: () => [
        isA<DownloadLoaded>().having(
          (state) => state.downloads
              .firstWhere((d) => d.contentId == testContentId)
              .state,
          'download state',
          DownloadState.completed,
        ),
        isA<DownloadLoaded>(),
      ],
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'ignores regressive progress updates from retried workers',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: testContentId,
            state: DownloadState.downloading,
            downloadedPages: 4,
            totalPages: 8,
            title: 'Test Manga',
            sourceId: 'src',
          ),
        ],
        settings: DownloadSettings.defaultSettings(),
        lastUpdated: DateTime.now(),
      ),
      act: (bloc) => bloc.add(const DownloadProgressUpdateEvent(
        contentId: testContentId,
        downloadedPages: 2,
        totalPages: 8,
      )),
      expect: () => <DownloadBlocState>[],
      verify: (_) {
        verifyNever(() => mockRepo.saveDownloadStatus(any(
              that: predicate<DownloadStatus>(
                (d) => d.contentId == testContentId && d.downloadedPages == 2,
              ),
            )));
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'maps native FAILED terminal marker to failed status instead of completed',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: testContentId,
            state: DownloadState.downloading,
            downloadedPages: 3,
            totalPages: 8,
            title: 'Test Manga',
            sourceId: 'src',
          ),
        ],
        settings: const DownloadSettings(
          autoRetry: false,
          enableNotifications: false,
        ),
        lastUpdated: DateTime.now(),
      ),
      act: (_) => progressController.add(const DownloadProgressUpdate(
        contentId: testContentId,
        downloadedPages: -1,
        totalPages: -2,
      )),
      wait: const Duration(milliseconds: 30),
      verify: (_) {
        verify(() => mockRepo.saveDownloadStatus(any(
              that: predicate<DownloadStatus>(
                (d) =>
                    d.contentId == testContentId &&
                    d.state == DownloadState.failed &&
                    d.error != null,
              ),
            ))).called(1);
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'downloads full EHentai gallery by aggregating linked parts in order',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: '123456/tokenabc',
            state: DownloadState.queued,
            totalPages: 0,
            title: 'Gallery Title',
            sourceId: 'ehentai',
            downloadPath: '/tmp/ehentai-gallery',
          ),
        ],
        settings: const DownloadSettings(
          enableNotifications: false,
          customStorageRoot: '/tmp/downloads',
        ),
        lastUpdated: DateTime(2026, 6, 22),
      ),
      setUp: () {
        when(() => mockGetContentDetailUseCase.call(any())).thenAnswer(
          (_) async => Content(
            id: '123456/tokenabc',
            sourceId: 'ehentai',
            title: 'Gallery Title',
            coverUrl: 'https://example.com/cover.jpg',
            tags: const [],
            artists: const [],
            characters: const [],
            parodies: const [],
            groups: const [],
            language: 'en',
            pageCount: 0,
            imageUrls: const [],
            uploadDate: DateTime(2026, 6, 22),
            url: 'https://e-hentai.org/g/123456/tokenabc/',
          ),
        );
        when(() => mockGetChapterImagesUseCase.call(any()))
            .thenAnswer((inv) async {
          final params =
              inv.positionalArguments.single as GetChapterImagesParams;
          switch (params.chapterId.value) {
            case '123456/tokenabc':
              return const ChapterData(
                images: [
                  'https://img.e-hentai.org/gallery-page-1.jpg',
                  'https://img.e-hentai.org/gallery-page-2.jpg',
                ],
                nextChapterId: '__ehpart__:123456:tokenabc:1',
                nextChapterTitle: 'Part 2',
              );
            case '__ehpart__:123456:tokenabc:1':
              return const ChapterData(
                images: [
                  'https://img.e-hentai.org/gallery-page-3.jpg',
                  'https://img.e-hentai.org/gallery-page-4.jpg',
                ],
              );
          }
          throw StateError('Unexpected chapter id: ${params.chapterId.value}');
        });
        when(() => mockDownloadContentUseCase.call(any())).thenAnswer(
          (_) async => const DownloadStatus(
            contentId: '123456/tokenabc',
            state: DownloadState.downloading,
            totalPages: 4,
            title: 'Gallery Title',
            sourceId: 'ehentai',
          ),
        );
      },
      act: (bloc) => bloc.add(const DownloadStartEvent('123456/tokenabc')),
      verify: (_) {
        final captured = verify(
          () => mockDownloadContentUseCase.call(captureAny()),
        ).captured.single as DownloadContentParams;

        expect(captured.content.imageUrls, const [
          'https://img.e-hentai.org/gallery-page-1.jpg',
          'https://img.e-hentai.org/gallery-page-2.jpg',
          'https://img.e-hentai.org/gallery-page-3.jpg',
          'https://img.e-hentai.org/gallery-page-4.jpg',
        ]);
        expect(captured.content.pageCount, 4);
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'downloads only the selected EHentai part instead of traversing next parts',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: '__ehpart__:123456:tokenabc:0',
            state: DownloadState.queued,
            totalPages: 0,
            title: 'Part 1',
            sourceId: 'ehentai',
            downloadPath: '/tmp/ehentai-part-1',
          ),
        ],
        settings: const DownloadSettings(
          enableNotifications: false,
          customStorageRoot: '/tmp/downloads',
        ),
        lastUpdated: DateTime(2026, 5, 23),
      ),
      setUp: () {
        when(() => mockGetContentDetailUseCase.call(any())).thenAnswer(
          (_) async => Content(
            id: '__ehpart__:123456:tokenabc:0',
            sourceId: 'ehentai',
            title: 'Gallery Title',
            coverUrl: 'https://example.com/cover.jpg',
            tags: const [],
            artists: const [],
            characters: const [],
            parodies: const [],
            groups: const [],
            language: 'en',
            pageCount: 0,
            imageUrls: const [],
            uploadDate: DateTime(2026, 5, 23),
            url: 'https://e-hentai.org/g/123456/tokenabc/',
          ),
        );
        when(() => mockGetChapterImagesUseCase.call(any()))
            .thenAnswer((inv) async {
          final params =
              inv.positionalArguments.single as GetChapterImagesParams;
          final chapterId = params.chapterId.value;
          if (chapterId == '__ehpart__:123456:tokenabc:0') {
            return const ChapterData(
              images: [
                'https://img.e-hentai.org/part-1-page-1.jpg',
                'https://img.e-hentai.org/part-1-page-2.jpg',
              ],
              nextChapterId: '__ehpart__:123456:tokenabc:1',
              nextChapterTitle: 'Part 2',
            );
          }
          if (chapterId == '__ehpart__:123456:tokenabc:1') {
            return const ChapterData(
              images: ['https://img.e-hentai.org/part-2-page-1.jpg'],
            );
          }
          throw StateError('Unexpected chapter id: $chapterId');
        });
        when(() => mockDownloadContentUseCase.call(any())).thenAnswer(
          (_) async => const DownloadStatus(
            contentId: '__ehpart__:123456:tokenabc:0',
            state: DownloadState.downloading,
            totalPages: 2,
            title: 'Part 1',
            sourceId: 'ehentai',
          ),
        );
      },
      act: (bloc) =>
          bloc.add(const DownloadStartEvent('__ehpart__:123456:tokenabc:0')),
      verify: (_) {
        verify(
          () => mockGetChapterImagesUseCase.call(
            any(
              that: predicate<GetChapterImagesParams>(
                (params) =>
                    params.chapterId.value == '__ehpart__:123456:tokenabc:0' &&
                    params.sourceId == 'ehentai',
              ),
            ),
          ),
        ).called(1);
        verifyNever(
          () => mockGetChapterImagesUseCase.call(
            any(
              that: predicate<GetChapterImagesParams>(
                (params) =>
                    params.chapterId.value == '__ehpart__:123456:tokenabc:1',
              ),
            ),
          ),
        );

        final captured = verify(
          () => mockDownloadContentUseCase.call(captureAny()),
        ).captured.single as DownloadContentParams;

        expect(captured.content.imageUrls, const [
          'https://img.e-hentai.org/part-1-page-1.jpg',
          'https://img.e-hentai.org/part-1-page-2.jpg',
        ]);
        expect(captured.content.pageCount, 2);
        expect(captured.content.title, 'Part 1');

        verify(
          () => mockRepo.saveDownloadStatus(
            any(
              that: predicate<DownloadStatus>(
                (status) =>
                    status.contentId == '__ehpart__:123456:tokenabc:0' &&
                    status.totalPages == 2,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'queues EHentai part-local range download with selected bounds',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [],
        settings: const DownloadSettings(
          enableNotifications: false,
          customStorageRoot: '/tmp/downloads',
        ),
        lastUpdated: DateTime(2026, 6, 22),
      ),
      act: (bloc) => bloc.add(
        DownloadRangeEvent(
          content: Content(
            id: '__ehpart__:123456:tokenabc:1',
            sourceId: 'ehentai',
            title: 'Gallery Title - Part 2',
            coverUrl: 'https://example.com/cover.jpg',
            tags: const [],
            artists: const [],
            characters: const [],
            parodies: const [],
            groups: const [],
            language: 'en',
            pageCount: 12,
            imageUrls: const [],
            uploadDate: DateTime(2026, 6, 22),
          ),
          startPage: 3,
          endPage: 7,
        ),
      ),
      verify: (_) {
        verify(
          () => mockRepo.saveDownloadStatus(
            any(
              that: predicate<DownloadStatus>(
                (status) =>
                    status.contentId == '__ehpart__:123456:tokenabc:1' &&
                    status.startPage == 3 &&
                    status.endPage == 7 &&
                    status.sourceId == 'ehentai',
              ),
            ),
          ),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'normalizes composite chapter id for detail lookup and keeps chapter download running',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: 'komikcast-slug/17',
            state: DownloadState.queued,
            totalPages: 0,
            title: 'Komikcast Ch.17',
            sourceId: 'komikcast',
            downloadPath: '/tmp/komikcast-chapter',
          ),
        ],
        settings: const DownloadSettings(
          enableNotifications: false,
          customStorageRoot: '/tmp/downloads',
        ),
        lastUpdated: DateTime(2026, 5, 28),
      ),
      setUp: () {
        when(() => mockRemoteConfigService.getRawConfig('komikcast'))
            .thenReturn({
          'network': {
            'headers': {'User-Agent': 'UnitTest'},
          },
          'api': {
            'url': 'https://be.komikcast.cc',
            'endpoints': {
              'detail': {'path': '/series/{id}'},
              'images': {'path': '/series/{id}/chapters/{chapter}'},
            },
          },
        });
        when(() => mockGetContentDetailUseCase.call(any()))
            .thenThrow(Exception('detail can fail for chapter download'));
        when(() => mockGetChapterImagesUseCase.call(any())).thenAnswer(
          (_) async => const ChapterData(
            images: [
              'https://sv1.imgkc1.my.id/wp-content/img/A/ATM/017/001.jpg'
            ],
          ),
        );
        when(() => mockDownloadContentUseCase.call(any())).thenAnswer(
          (_) async => const DownloadStatus(
            contentId: 'komikcast-slug/17',
            state: DownloadState.downloading,
            totalPages: 1,
            title: 'Komikcast Ch.17',
            sourceId: 'komikcast',
          ),
        );
      },
      act: (bloc) => bloc.add(const DownloadStartEvent('komikcast-slug/17')),
      wait: const Duration(milliseconds: 30),
      verify: (_) {
        final capturedDetailCall = verify(
          () => mockGetContentDetailUseCase.call(captureAny()),
        ).captured.single as GetContentDetailParams;
        expect(capturedDetailCall.contentId.value, 'komikcast-slug');
        expect(capturedDetailCall.sourceId, 'komikcast');

        verify(
          () => mockDownloadContentUseCase.call(
            any(
              that: predicate<DownloadContentParams>(
                (params) =>
                    params.content.id == 'komikcast-slug/17' &&
                    params.content.imageUrls.length == 1 &&
                    params.content.imageUrls.first.endsWith('/001.jpg'),
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<DownloadBloc, DownloadBlocState>(
      'does not start native download when chapter images cannot be resolved',
      build: () => downloadBloc,
      seed: () => DownloadLoaded(
        downloads: const [
          DownloadStatus(
            contentId: 'komikcast-slug/17',
            state: DownloadState.queued,
            totalPages: 0,
            title: 'Komikcast Ch.17',
            sourceId: 'komikcast',
            downloadPath: '/tmp/komikcast-chapter',
          ),
        ],
        settings: const DownloadSettings(
          enableNotifications: false,
          customStorageRoot: '/tmp/downloads',
        ),
        lastUpdated: DateTime(2026, 5, 28),
      ),
      setUp: () {
        when(() => mockGetContentDetailUseCase.call(any()))
            .thenThrow(Exception('detail not available for chapter id'));
        when(() => mockGetChapterImagesUseCase.call(any())).thenAnswer(
          (_) async => const ChapterData(images: []),
        );
      },
      act: (bloc) => bloc.add(const DownloadStartEvent('komikcast-slug/17')),
      wait: const Duration(milliseconds: 30),
      verify: (_) {
        verifyNever(() => mockDownloadContentUseCase.call(any()));
      },
    );
  });
}
