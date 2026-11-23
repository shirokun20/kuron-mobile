import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/download_manager.dart';
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
import 'package:connectivity_plus/connectivity_plus.dart';

// No permanent 5s ticker: the DB-flush timer must only exist while saves
// are queued, so an idle app has zero perpetual timers from this bloc.
class _MockDownloadContentUseCase extends Mock
    implements DownloadContentUseCase {}

class _MockGetContentDetailUseCase extends Mock
    implements GetContentDetailUseCase {}

class _MockGetChapterImagesUseCase extends Mock
    implements GetChapterImagesUseCase {}

class _MockUserDataRepository extends Mock implements UserDataRepository {}

class _MockOfflineContentManager extends Mock
    implements OfflineContentManager {}

class _MockLogger extends Mock implements Logger {}

class _MockConnectivity extends Mock implements Connectivity {}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockDownloadManager extends Mock implements DownloadManager {}

class _MockPdfConversionQueueManager extends Mock
    implements PdfConversionQueueManager {}

class _MockPdfConversionService extends Mock implements PdfConversionService {}

class _MockNotificationServiceWithStubs extends _MockNotificationService {
  void stub() {
    when(() => initialize()).thenAnswer((_) async {});
    when(() => cancelDownloadGroup()).thenAnswer((_) async {});
    when(() => updateDownloadProgress(
          contentId: any(named: 'contentId'),
          progress: any(named: 'progress'),
          title: any(named: 'title'),
          isPaused: any(named: 'isPaused'),
          pagesPacked: any(named: 'pagesPacked'),
          totalPages: any(named: 'totalPages'),
          speedText: any(named: 'speedText'),
        )).thenAnswer((_) async => {});
  }
}

const _contentId = 'idle-timer-content';

DownloadStatus _status({int downloaded = 10}) => DownloadStatus(
      contentId: _contentId,
      state: DownloadState.downloading,
      downloadedPages: downloaded,
      totalPages: 20,
      title: 'Idle Timer Manga',
      sourceId: 'src',
    );

void main() {
  late DownloadBloc bloc;
  late _MockUserDataRepository repo;
  late StreamController<DownloadProgressUpdate> progressController;

  DownloadBloc buildBloc(_MockDownloadManager downloadManager) {
    final notificationService = _MockNotificationServiceWithStubs();
    notificationService.stub();
    return DownloadBloc(
      downloadContentUseCase: _MockDownloadContentUseCase(),
      getContentDetailUseCase: _MockGetContentDetailUseCase(),
      getChapterImagesUseCase: _MockGetChapterImagesUseCase(),
      userDataRepository: repo,
      offlineContentManager: _MockOfflineContentManager(),
      logger: _MockLogger(),
      connectivity: _MockConnectivity(),
      notificationService: notificationService,
      pdfConversionService: _MockPdfConversionService(),
      remoteConfigService: _MockRemoteConfigService(),
      downloadManager: downloadManager,
      pdfConversionQueueManager: _MockPdfConversionQueueManager(),
    );
  }

  setUpAll(() {
    registerFallbackValue(_status());
  });

  setUp(() {
    repo = _MockUserDataRepository();
    when(() => repo.saveDownloadStatus(any())).thenAnswer((_) async => {});
    progressController = StreamController<DownloadProgressUpdate>.broadcast();
  });

  tearDown(() async {
    await progressController.close();
    await bloc.close();
  });

  DownloadBloc newBloc() {
    final downloadManager = _MockDownloadManager();
    when(() => downloadManager.progressStream)
        .thenAnswer((_) => progressController.stream);
    when(() => downloadManager.unregisterTask(any())).thenReturn(null);
    return buildBloc(downloadManager);
  }

  void seedLoaded() {
    bloc.emit(DownloadLoaded(
      downloads: [_status()],
      settings: const DownloadSettings(),
      lastUpdated: DateTime.now(),
    ));
  }

  test('no flush timer runs on a fresh idle bloc', () {
    bloc = newBloc();
    expect(bloc.isFlushTimerActive, isFalse);
  });

  test('resumeBackgroundWork stays timer-free with empty queue', () {
    bloc = newBloc();
    bloc.resumeBackgroundWork();
    expect(bloc.isFlushTimerActive, isFalse);
  });

  test('timer starts when saves queue, stops after pauseBackgroundWork',
      () async {
    bloc = newBloc();
    seedLoaded();

    bloc.add(const DownloadProgressUpdateEvent(
      contentId: _contentId,
      downloadedPages: 11,
      totalPages: 20,
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(bloc.isFlushTimerActive, isTrue);

    bloc.pauseBackgroundWork();
    expect(bloc.isFlushTimerActive, isFalse);
    verify(() => repo.saveDownloadStatus(any())).called(greaterThanOrEqualTo(1));
  });

  test('timer stops by itself once the queue drains (FakeAsync)', () {
    FakeAsync().run((async) {
      bloc = newBloc();
      seedLoaded();

      bloc.add(const DownloadProgressUpdateEvent(
        contentId: _contentId,
        downloadedPages: 11,
        totalPages: 20,
      ));
      async.flushMicrotasks();
      expect(bloc.isFlushTimerActive, isTrue);

      // The 5s tick flushes the queued save, then finds an empty queue and
      // cancels itself: idle again with zero tickers.
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(bloc.isFlushTimerActive, isFalse);
    });
    verify(() => repo.saveDownloadStatus(any())).called(1);
  });
}
