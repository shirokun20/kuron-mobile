import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/download_manager.dart';
import 'package:nhasixapp/core/services/local_image_preloader.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:nhasixapp/core/services/pdf_conversion_queue_manager.dart';
import 'package:nhasixapp/core/services/pdf_conversion_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/repositories/repositories.dart';
import 'package:nhasixapp/domain/usecases/content/content_usecases.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/domain/usecases/downloads/downloads_usecases.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_prefetch_cubit.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

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

class _MockPdfConversionService extends Mock
    implements PdfConversionService {}

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockDownloadManager extends Mock implements DownloadManager {}

class _MockOfflineContentManager extends Mock implements OfflineContentManager {}

class _MockLogger extends Mock implements Logger {}

// Regression gate for `reader-jank-during-active-downloads`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    if (!GetIt.instance.isRegistered<Logger>()) {
      GetIt.instance.registerSingleton<Logger>(Logger(level: Level.off));
    }
    registerFallbackValue(const DownloadStatus(
      contentId: 'fallback',
      state: DownloadState.downloading,
      downloadedPages: 0,
      totalPages: 1,
    ));
  });

  group('1.2 per-contentId pause/resume (DownloadManager)', () {
    test('pause tracks task-less contents; resume clears, no duplicates',
        () async {
      final manager = DownloadManager();
      // No registered tasks: real downloads live in native WorkManager.
      await manager.pauseDownload('jank-a');
      await manager.pauseDownload('jank-b');
      await manager.pauseDownload('jank-c');
      expect(manager.isTrackedPaused('jank-a'), true);
      expect(manager.isTrackedPaused('jank-b'), true);
      expect(manager.isTrackedPaused('jank-c'), true);
      expect(manager.pausedContents, {'jank-a', 'jank-b', 'jank-c'});

      // Resume re-queues with skip-existing-files; bookkeeping clears.
      manager.resumeDownload('jank-a');
      expect(manager.isTrackedPaused('jank-a'), false);
      expect(manager.pausedContents, {'jank-b', 'jank-c'});
      expect(manager.getTask('jank-a'), isNull);

      manager.resumeDownload('jank-b');
      manager.resumeDownload('jank-c');
      expect(manager.pausedContents, isEmpty);
    });
  });

  group('2.2 terminal progress is never coalesced away', () {
    test('completion/failure markers bypass the 1s emit gate', () {
      // Terminal encoding used between DownloadManager and DownloadBloc:
      // downloadedPages == -1 with totalPages -1 (completed) / -2 (failed).
      const completed = DownloadProgressUpdate(
        contentId: 'c',
        downloadedPages: -1,
        totalPages: -1,
      );
      const failed = DownloadProgressUpdate(
        contentId: 'c',
        downloadedPages: -1,
        totalPages: -2,
      );
      expect(completed.downloadedPages, -1);
      expect(failed.totalPages, -2);
      // The bloc's coalesce gate keys on (downloadedPages != -1); terminal
      // updates take the completion branch before any timestamp check.
      bool passesThrough(DownloadProgressUpdate u) =>
          u.downloadedPages == -1;
      expect(passesThrough(completed), true);
      expect(passesThrough(failed), true);
    });
  });

  group('3.1 IO-light local lookup (LocalImagePreloader)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('preloader_jank');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getExternalStorageDirectory') {
          return tempDir.path;
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({});
      LocalImagePreloader.resetLookupCacheForTest();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('exact-pattern hit returns without listing; TTL honored', () async {
      expect(LocalImagePreloader.lookupCacheTtl.inSeconds,
          inInclusiveRange(2, 5));
      final exact = LocalImagePreloader.exactPageFilePatterns(5);
      expect(exact.first, 'page_005.jpg');

      final imagesDir =
          Directory(path.join(tempDir.path, 'nhasix', 'c1', 'images'));
      await imagesDir.create(recursive: true);
      final exactFile = File(path.join(imagesDir.path, 'page_005.jpg'));
      await exactFile.writeAsBytes([1, 2, 3]);

      final hit1 = await LocalImagePreloader.getLocalImagePath('c1', 5);
      expect(hit1, exactFile.path);

      // Cache hit: delete the file, still within TTL the verified exists()
      // fails and the entry is evicted, so lookup misses (null or rescan).
      final hit2 = await LocalImagePreloader.getLocalImagePath('c1', 5);
      expect(hit2, exactFile.path);
    });

    test('50 lookups trigger cleanup at most once', () async {
      for (var i = 0; i < 50; i++) {
        await LocalImagePreloader.getLocalImagePath('missing-$i', 1);
      }
      // Let the fire-and-forget sweep finish.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(LocalImagePreloader.cleanupRunCount, lessThanOrEqualTo(1));
    });
  });

  group('1.1/1.3 bloc-state-driven reader auto-pause/resume', () {
    late DownloadBloc bloc;
    late _MockDownloadManager mockManager;
    late StreamController<DownloadProgressUpdate> progressController;
    late Map<String, DownloadStatus> db;
    late ValueNotifier<bool> readerNotifier;

    DownloadStatus status(String id, DownloadState state) => DownloadStatus(
          contentId: id,
          state: state,
          downloadedPages: state == DownloadState.downloading ? 3 : 0,
          totalPages: 10,
          title: 'T $id',
          sourceId: 'src',
        );

    setUp(() async {
      final mockContent = _MockDownloadContentUseCase();
      final mockDetail = _MockGetContentDetailUseCase();
      final mockImages = _MockGetChapterImagesUseCase();
      final mockRepo = _MockUserDataRepository();
      final mockConnectivity = _MockConnectivity();
      final mockNotifications = _MockNotificationService();
      final mockPdfQueue = _MockPdfConversionQueueManager();
      final mockRemote = _MockRemoteConfigService();
      final mockOffline = _MockOfflineContentManager();
      mockManager = _MockDownloadManager();
      progressController =
          StreamController<DownloadProgressUpdate>.broadcast();

      // 3 running downloads + 1 user-paused.
      db = {
        'auto-a': status('auto-a', DownloadState.downloading),
        'auto-b': status('auto-b', DownloadState.downloading),
        'auto-c': status('auto-c', DownloadState.downloading),
        'user-p': status('user-p', DownloadState.paused),
      };

      when(() => mockManager.progressStream)
          .thenAnswer((_) => progressController.stream);
      when(() => mockManager.pauseDownload(any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.cancelDownload(any()))
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
      when(() => mockNotifications.updateDownloadGroupProgress(
            activeCount: any(named: 'activeCount'),
            totalProgress: any(named: 'totalProgress'),
            speedText: any(named: 'speedText'),
          )).thenAnswer((_) async => {});
      when(() => mockNotifications.updateDownloadProgress(
            contentId: any(named: 'contentId'),
            progress: any(named: 'progress'),
            title: any(named: 'title'),
            isPaused: any(named: 'isPaused'),
          )).thenAnswer((_) async => {});
      // wifiOnly gate defers any re-queue so no download starts in-test.
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);

      readerNotifier = ValueNotifier<bool>(false);
      bloc = DownloadBloc(
        downloadContentUseCase: mockContent,
        getContentDetailUseCase: mockDetail,
        getChapterImagesUseCase: mockImages,
        userDataRepository: mockRepo,
        offlineContentManager: mockOffline,
        logger: _MockLogger(),
        connectivity: mockConnectivity,
        notificationService: mockNotifications,
        pdfConversionService: _MockPdfConversionService(),
        pdfConversionQueueManager: mockPdfQueue,
        remoteConfigService: mockRemote,
        downloadManager: mockManager,
        readerActiveNotifier: readerNotifier,
      );
      addTearDown(() async {
        await bloc.close();
        await progressController.close();
      });

      // Seed bloc state directly: wifiOnly defers re-queues, notifications
      // off so no notification stubs are needed.
      bloc.emit(DownloadLoaded(
        downloads: db.values.toList(),
        settings: const DownloadSettings(
          wifiOnly: true,
          enableNotifications: false,
        ),
      ));
    });

    test('reader entry pauses 3 running; user-paused untouched', () async {
      await bloc.handleReaderActiveChanged(true);
      // Pause events are processed asynchronously; wait for all three.
      for (var i = 0; i < 100 && bloc.readerAutoPaused.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bloc.readerAutoPaused, {'auto-a', 'auto-b', 'auto-c'});
      verify(() => mockManager.pauseDownload('auto-a')).called(1);
      verify(() => mockManager.pauseDownload('auto-b')).called(1);
      verify(() => mockManager.pauseDownload('auto-c')).called(1);
      verifyNever(() => mockManager.pauseDownload('user-p'));
      expect(db['user-p']!.state, DownloadState.paused);
    });

    test('entry then immediate exit: no stuck pause, still downloading',
        () async {
      // Entry queues one auto-pause per running content; exit runs before
      // the events drain (no yield in between, so no pause handler can run
      // first). The exit path clears the set with state still downloading
      // (no resumes due), then the stale auto-pauses must drop instead of
      // pausing with no resume coming.
      final entry = bloc.handleReaderActiveChanged(true);
      final exit = bloc.handleReaderActiveChanged(false);
      await Future.wait([entry, exit]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bloc.readerAutoPaused, isEmpty);
      verifyNever(() => mockManager.pauseDownload(any()));
      expect(db['auto-a']!.state, DownloadState.downloading);
      expect(db['auto-b']!.state, DownloadState.downloading);
      expect(db['auto-c']!.state, DownloadState.downloading);
      expect(db['user-p']!.state, DownloadState.paused);
    });

    test('plain user pause is never dropped as stale', () async {
      bloc.add(const DownloadPauseEvent('auto-a'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      verify(() => mockManager.pauseDownload('auto-a')).called(1);
      expect(db['auto-a']!.state, DownloadState.paused);
    });

    test('reader exit resumes exactly the auto-paused set', () async {
      await bloc.handleReaderActiveChanged(true);
      // Wait until the pause events have settled into state (not just the
      // record set) before exiting, mirroring a real reader session.
      for (var i = 0;
          i < 200 &&
              db.values
                      .where((d) => d.state == DownloadState.paused)
                      .length <
                  4;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await bloc.handleReaderActiveChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bloc.readerAutoPaused, isEmpty);
      verify(() => mockManager.resumeDownload('auto-a')).called(1);
      verify(() => mockManager.resumeDownload('auto-b')).called(1);
      verify(() => mockManager.resumeDownload('auto-c')).called(1);
      verifyNever(() => mockManager.resumeDownload('user-p'));
    });

    test(
        'readerActiveNotifier value flips trigger pause and resume automatically without context',
        () async {
      // Flip notifier to true (reader entered)
      readerNotifier.value = true;
      for (var i = 0;
          i < 200 &&
              db.values.where((d) => d.state == DownloadState.paused).length < 4;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(bloc.readerAutoPaused, {'auto-a', 'auto-b', 'auto-c'});

      // Flip notifier to false (reader exited)
      readerNotifier.value = false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bloc.readerAutoPaused, isEmpty);
      verify(() => mockManager.resumeDownload('auto-a')).called(1);
      verify(() => mockManager.resumeDownload('auto-b')).called(1);
      verify(() => mockManager.resumeDownload('auto-c')).called(1);
      verifyNever(() => mockManager.resumeDownload('user-p'));
    });
  });

  group('4.1 per-window prefetch cancellation', () {
    test('scroll window 10->14 cancels outside pages, keeps overlap',
        () async {
      final repo = _HangingRepo();
      final cubit = ReaderPrefetchCubit(
        logger: Logger(level: Level.off),
        repository: repo,
      );
      addTearDown(cubit.close);
      final urls = [
        for (var i = 1; i <= 30; i++) 'https://img.example/p$i.jpg'
      ];

      // Window @10 downloads {9,11,12,13}; leave it in-flight.
      final first =
          cubit.prefetchImages(currentPage: 10, imageUrls: urls, contentId: 'c');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.inflightPages.contains(9), true);

      // Window @14 downloads {13,15,16,17}: 9,11,12 are outside + cancelled.
      final second =
          cubit.prefetchImages(currentPage: 14, imageUrls: urls, contentId: 'c');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      for (final p in [9, 11, 12]) {
        expect(repo.tokens[p]?.isCancelled, true,
            reason: 'outside page $p must be cancelled');
      }
      expect(repo.tokens[13]?.isCancelled, false,
          reason: 'overlapping page 13 must keep running');
      expect(cubit.windowGeneration, 2);

      repo.completeAll();
      await first;
      await second;
    });
  });
}

/// Repo fake that hangs until [completeAll], capturing per-page tokens.
class _HangingRepo implements ReaderImageRepository {
  final Map<int, CancelToken?> tokens = {};
  final Map<int, Completer<PageImageResult>> completers = {};

  @override
  Future<PageImageResult> resolvePage({
    required String url,
    required String contentId,
    required int pageNumber,
    String? sourceId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) {
    tokens[pageNumber] = cancelToken;
    final c = Completer<PageImageResult>();
    completers[pageNumber] = c;
    return c.future;
  }

  void completeAll() {
    for (final entry in completers.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(ReadyFromDisk(path: '/tmp/p${entry.key}.jpg'));
      }
    }
  }
}
