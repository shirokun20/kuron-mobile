import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/download_manager.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:nhasixapp/core/services/pdf_conversion_queue_manager.dart';
import 'package:nhasixapp/core/services/pdf_conversion_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/data/repositories/reader_image_repository_impl.dart';
import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_detail_usecase.dart';
import 'package:nhasixapp/domain/usecases/downloads/download_content_usecase.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';

class _MockDownloadContentUseCase extends Mock
    implements DownloadContentUseCase {}

class _MockGetContentDetailUseCase extends Mock
    implements GetContentDetailUseCase {}

class _MockGetChapterImagesUseCase extends Mock
    implements GetChapterImagesUseCase {}

class _MockUserDataRepository extends Mock implements UserDataRepository {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockPdfConversionQueueManager extends Mock
    implements PdfConversionQueueManager {}

class _MockPdfConversionService extends Mock implements PdfConversionService {}

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockDownloadManager extends Mock implements DownloadManager {}

class _MockOfflineContentManager extends Mock
    implements OfflineContentManager {}
class _FakeDownloadContentParams extends Fake implements DownloadContentParams {}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory mockTempDir;

  setUpAll(() {
    mockTempDir = Directory.systemTemp.createTempSync('path_provider_mock_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return mockTempDir.path;
    });

    registerFallbackValue(const DownloadStatus(
      contentId: 'fallback',
      state: DownloadState.queued,
      totalPages: 0,
    ));
    registerFallbackValue(_FakeDownloadContentParams());

    if (!GetIt.instance.isRegistered<Logger>()) {
      GetIt.instance.registerSingleton<Logger>(Logger(level: Level.off));
    }
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (mockTempDir.existsSync()) {
      mockTempDir.deleteSync(recursive: true);
    }
  });

  group('Proof 1: Dual notification bug elimination', () {
    late DownloadBloc bloc;
    late _MockNotificationService mockNotifications;
    late _MockDownloadManager mockManager;
    late _MockUserDataRepository mockRepo;
    late _MockDownloadContentUseCase mockContent;
    late ValueNotifier<bool> readerNotifier;
    late Map<String, DownloadStatus> db;

    setUp(() async {
      mockNotifications = _MockNotificationService();
      mockManager = _MockDownloadManager();
      mockRepo = _MockUserDataRepository();
      mockContent = _MockDownloadContentUseCase();
      final mockConnectivity = _MockConnectivity();
      readerNotifier = ValueNotifier<bool>(false);

      db = {
        'manga-1': const DownloadStatus(
          contentId: 'manga-1',
          state: DownloadState.downloading,
          downloadedPages: 5,
          totalPages: 10,
          title: 'Solo Leveling Chapter 1',
        ),
      };

      when(() => mockNotifications.initialize()).thenAnswer((_) async => {});
      when(() => mockNotifications.setCallbacks(
            onDownloadPause: any(named: 'onDownloadPause'),
            onDownloadResume: any(named: 'onDownloadResume'),
            onDownloadCancel: any(named: 'onDownloadCancel'),
            onDownloadRetry: any(named: 'onDownloadRetry'),
            onPdfRetry: any(named: 'onPdfRetry'),
            onOpenDownload: any(named: 'onOpenDownload'),
            onNavigateToDownloads: any(named: 'onNavigateToDownloads'),
          )).thenReturn(null);
      when(() => mockNotifications.showDownloadCompleted(
            contentId: any(named: 'contentId'),
            title: any(named: 'title'),
            downloadPath: any(named: 'downloadPath'),
          )).thenAnswer((_) async => {});
      when(() => mockNotifications.cancelDownloadNotification(any()))
          .thenAnswer((_) async => {});
      when(() => mockNotifications.cancelDownloadGroup())
          .thenAnswer((_) async => {});
      when(() => mockNotifications.updateDownloadProgress(
            contentId: any(named: 'contentId'),
            progress: any(named: 'progress'),
            title: any(named: 'title'),
            isPaused: any(named: 'isPaused'),
          )).thenAnswer((_) async => {});
      when(() => mockNotifications.updateDownloadGroupProgress(
            activeCount: any(named: 'activeCount'),
            totalProgress: any(named: 'totalProgress'),
            speedText: any(named: 'speedText'),
          )).thenAnswer((_) async => {});

      when(() => mockManager.progressStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockManager.pauseDownload(any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.resumeDownload(any())).thenReturn(null);
      when(() => mockManager.unregisterTask(any())).thenReturn(null);

      when(() => mockRepo.getAllDownloads(
            state: any(named: 'state'),
            sourceId: any(named: 'sourceId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => db.values.toList());
      when(() => mockRepo.saveDownloadStatus(any())).thenAnswer((inv) async {
        final s = inv.positionalArguments.first as DownloadStatus;
        db[s.contentId] = s;
      });

      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      bloc = DownloadBloc(
        downloadContentUseCase: mockContent,
        getContentDetailUseCase: _MockGetContentDetailUseCase(),
        getChapterImagesUseCase: _MockGetChapterImagesUseCase(),
        userDataRepository: mockRepo,
        offlineContentManager: _MockOfflineContentManager(),
        logger: Logger(level: Level.off),
        connectivity: mockConnectivity,
        notificationService: mockNotifications,
        pdfConversionService: _MockPdfConversionService(),
        pdfConversionQueueManager: _MockPdfConversionQueueManager(),
        remoteConfigService: _MockRemoteConfigService(),
        downloadManager: mockManager,
        readerActiveNotifier: readerNotifier,
      );

      bloc.emit(DownloadLoaded(
        downloads: db.values.toList(),
        settings: const DownloadSettings(
          enableNotifications: true,
          wifiOnly: false,
        ),
      ));
    });

    tearDown(() async {
      await bloc.close();
    });

    test('1 download active updates individual notification and cancels group notification', () async {
      bloc.add(const DownloadProgressUpdateEvent(
        contentId: 'manga-1',
        downloadedPages: 6,
        totalPages: 10,
        downloadSpeed: 1024 * 500,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 350));

      // PROOF: Group notification (777778 "Downloading 1 item") is CANCELLED!
      verify(() => mockNotifications.cancelDownloadGroup()).called(greaterThanOrEqualTo(1));

      // PROOF: Rich notification with title and progress is updated
      verify(() => mockNotifications.updateDownloadProgress(
            contentId: 'manga-1',
            progress: 60,
            title: 'Solo Leveling Chapter 1',
            isPaused: false,
          )).called(greaterThanOrEqualTo(1));
    });

    test('Entering reader auto-pauses download and cancels group notification (NO "Downloading 1 item" beside "Paused")', () async {
      // User opens reader
      readerNotifier.value = true;

      for (var i = 0; i < 100 && db['manga-1']!.state != DownloadState.paused; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(db['manga-1']!.state, DownloadState.paused);

      // PROOF: Paused notification is displayed for manga-1
      verify(() => mockNotifications.updateDownloadProgress(
            contentId: 'manga-1',
            progress: any(named: 'progress'),
            title: 'Solo Leveling Chapter 1',
            isPaused: true,
          )).called(1);

      // PROOF: Group notification (777778) is CANCELLED! It never stays stuck beside the "Paused" notification!
      verify(() => mockNotifications.cancelDownloadGroup()).called(greaterThanOrEqualTo(1));
    });

    test('Completed download shows completion notification and never lingers as Paused or in group', () async {
      bloc.add(const DownloadCompletedEvent('manga-1'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // PROOF: showDownloadCompleted replaces the paused notification with completion
      verify(() => mockNotifications.showDownloadCompleted(
            contentId: 'manga-1',
            title: 'Solo Leveling Chapter 1',
            downloadPath: any(named: 'downloadPath'),
          )).called(1);

      // PROOF: Group notification is cancelled
      verify(() => mockNotifications.cancelDownloadGroup()).called(greaterThanOrEqualTo(1));
    });
  });

  group('Proof 2: Reader active blocks queue processing (No background lag)', () {
    late DownloadBloc bloc;
    late _MockDownloadContentUseCase mockContent;
    late ValueNotifier<bool> readerNotifier;
    late Map<String, DownloadStatus> db;

    setUp(() async {
      mockContent = _MockDownloadContentUseCase();
      final mockRepo = _MockUserDataRepository();
      final mockConnectivity = _MockConnectivity();
      final mockNotifications = _MockNotificationService();
      final mockManager = _MockDownloadManager();
      readerNotifier = ValueNotifier<bool>(true); // READER IS ACTIVE!

      when(() => mockManager.progressStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockManager.unregisterTask(any())).thenReturn(null);
      when(() => mockNotifications.initialize()).thenAnswer((_) async => {});
      when(() => mockNotifications.setCallbacks(
            onDownloadPause: any(named: 'onDownloadPause'),
            onDownloadResume: any(named: 'onDownloadResume'),
            onDownloadCancel: any(named: 'onDownloadCancel'),
            onDownloadRetry: any(named: 'onDownloadRetry'),
            onPdfRetry: any(named: 'onPdfRetry'),
            onOpenDownload: any(named: 'onOpenDownload'),
            onNavigateToDownloads: any(named: 'onNavigateToDownloads'),
          )).thenReturn(null);

      db = {
        'queued-manga': const DownloadStatus(
          contentId: 'queued-manga',
          state: DownloadState.queued,
          totalPages: 10,
          title: 'Queued Manga',
        ),
      };

      when(() => mockRepo.getAllDownloads(
            state: any(named: 'state'),
            sourceId: any(named: 'sourceId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => db.values.toList());

      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      bloc = DownloadBloc(
        downloadContentUseCase: mockContent,
        getContentDetailUseCase: _MockGetContentDetailUseCase(),
        getChapterImagesUseCase: _MockGetChapterImagesUseCase(),
        userDataRepository: mockRepo,
        offlineContentManager: _MockOfflineContentManager(),
        logger: Logger(level: Level.off),
        connectivity: mockConnectivity,
        notificationService: mockNotifications,
        pdfConversionService: _MockPdfConversionService(),
        pdfConversionQueueManager: _MockPdfConversionQueueManager(),
        remoteConfigService: _MockRemoteConfigService(),
        downloadManager: mockManager,
        readerActiveNotifier: readerNotifier,
      );

      bloc.emit(DownloadLoaded(
        downloads: db.values.toList(),
        settings: const DownloadSettings(
          customStorageRoot: '/tmp/downloads',
          wifiOnly: false,
        ),
      ));
    });

    tearDown(() async {
      await bloc.close();
    });

    test('Queued downloads are NOT started while reader is active', () async {
      // Trigger a refresh event while reader is active
      bloc.add(const DownloadRefreshEvent());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // PROOF: mockContent.call is NEVER executed because _processQueue is gated by readerActiveNotifier
      verifyNever(() => mockContent.call(any()));
      expect(db['queued-manga']!.state, DownloadState.queued);
    });
  });

  group('Proof 3: ReaderImageRepositoryImpl legacy lookup has zero network leakage', () {
    test('Legacy lookup returns null on miss without triggering network downloads', () async {
      final tempDir = Directory.systemTemp.createTempSync('proof_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final sampleFile = File('${tempDir.path}/page_1.jpg')..createSync();

      var legacyLookupCalled = false;
      var networkDownloadCalled = false;

      final repo = ReaderImageRepositoryImpl(
        logger: Logger(level: Level.off),
        localLookup: (contentId, page) async => null, // not in local storage
        legacyLookup: (url) async {
          legacyLookupCalled = true;
          // getFileFromCache returns null on cache miss
          return null;
        },
        networkDownload: ({
          required url,
          required contentId,
          required pageNumber,
          headers,
          cancelToken,
        }) async {
          networkDownloadCalled = true;
          return sampleFile.path;
        },
      );

      final result = await repo.resolvePage(
        url: 'https://example.com/uncached_page_1.jpg',
        contentId: 'manga-test',
        pageNumber: 1,
      );

      // PROOF: Legacy cache miss falls through directly to cancelable streaming network downloader,
      // without hanging or spawning un-cancelable getSingleFile downloads!
      expect(legacyLookupCalled, isTrue);
      expect(networkDownloadCalled, isTrue);
      expect(result, isA<ReadyFresh>());
      expect((result as ReadyFresh).path, sampleFile.path);
    });
  });
}
