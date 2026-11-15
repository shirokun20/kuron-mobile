import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const DownloadStatus(
      contentId: 'fallback',
      state: DownloadState.downloading,
      downloadedPages: 0,
      totalPages: 1,
    ));
    registerFallbackValue(const UserPreferences());
  });

  group('DownloadBloc Offline vs Online Reader Coexistence', () {
    late DownloadBloc bloc;
    late _MockDownloadManager mockManager;
    late StreamController<DownloadProgressUpdate> progressController;
    late Map<String, DownloadStatus> db;
    late ValueNotifier<bool> anyReaderNotifier;
    late ValueNotifier<bool> onlineReaderNotifier;
    late _MockUserDataRepository mockRepo;

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
      mockRepo = _MockUserDataRepository();
      final mockConnectivity = _MockConnectivity();
      final mockNotifications = _MockNotificationService();
      final mockPdfQueue = _MockPdfConversionQueueManager();
      final mockRemote = _MockRemoteConfigService();
      final mockOffline = _MockOfflineContentManager();
      mockManager = _MockDownloadManager();
      progressController =
          StreamController<DownloadProgressUpdate>.broadcast();

      db = {
        'dl-1': status('dl-1', DownloadState.downloading),
        'dl-2': status('dl-2', DownloadState.downloading),
        'dl-paused': status('dl-paused', DownloadState.paused),
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
      when(() => mockRepo.getUserPreferences()).thenAnswer(
        (_) async => const UserPreferences(pauseOnOnlineReaderOnly: true),
      );
      when(() => mockRepo.saveUserPreferences(any())).thenAnswer((_) async => {});
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
      when(() => mockNotifications.cancelDownloadGroup())
          .thenAnswer((_) async => {});
      when(() => mockNotifications.updateDownloadGroupProgress(
            activeCount: any(named: 'activeCount'),
            totalProgress: any(named: 'totalProgress'),
            speedText: any(named: 'speedText'),
          )).thenAnswer((_) async => {});
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);

      anyReaderNotifier = ValueNotifier<bool>(false);
      onlineReaderNotifier = ValueNotifier<bool>(false);

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
        readerActiveNotifier: anyReaderNotifier,
        onlineReaderActiveNotifier: onlineReaderNotifier,
      );

      addTearDown(() async {
        await bloc.close();
        await progressController.close();
      });

      bloc.emit(DownloadLoaded(
        downloads: db.values.toList(),
        settings: const DownloadSettings(
          wifiOnly: true,
          enableNotifications: false,
          pauseOnOnlineReaderOnly: true,
        ),
      ));
    });

    test('offline reader does NOT pause running downloads when pauseOnOnlineReaderOnly is true', () async {
      // Offline reader active: anyReader is true, onlineReader is false
      anyReaderNotifier.value = true;
      onlineReaderNotifier.value = false;

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.isReaderDownloadBlocked, isFalse);
      expect(bloc.readerAutoPaused, isEmpty);
      verifyNever(() => mockManager.pauseDownload(any()));
    });

    test('online reader DOES auto-pause running downloads', () async {
      // Online reader active: both are true
      anyReaderNotifier.value = true;
      onlineReaderNotifier.value = true;

      for (var i = 0;
          i < 200 &&
              db.values.where((d) => d.state == DownloadState.paused).length < 3;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(bloc.isReaderDownloadBlocked, isTrue);
      expect(bloc.readerAutoPaused, {'dl-1', 'dl-2'});
      verify(() => mockManager.pauseDownload('dl-1')).called(1);
      verify(() => mockManager.pauseDownload('dl-2')).called(1);
    });

    test('transition from offline to online pauses, transition back resumes', () async {
      // 1. Enter offline
      anyReaderNotifier.value = true;
      onlineReaderNotifier.value = false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.readerAutoPaused, isEmpty);

      // 2. Transition to online chapter
      onlineReaderNotifier.value = true;
      for (var i = 0;
          i < 200 &&
              ((bloc.state is! DownloadLoaded) ||
                  (bloc.state as DownloadLoaded)
                          .downloads
                          .where((d) => d.state == DownloadState.paused)
                          .length <
                      3);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(bloc.readerAutoPaused, {'dl-1', 'dl-2'});

      // 3. Transition back to offline chapter
      onlineReaderNotifier.value = false;
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (bloc.readerAutoPaused.isEmpty) break;
      }
      expect(bloc.isReaderDownloadBlocked, isFalse);
      expect(bloc.readerAutoPaused, isEmpty);

      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        try {
          verify(() => mockManager.resumeDownload('dl-1')).called(1);
          verify(() => mockManager.resumeDownload('dl-2')).called(1);
          break;
        } catch (_) {}
      }
      verifyNever(() => mockManager.resumeDownload('dl-paused'));
    });

    test('when pauseOnOnlineReaderOnly is false, offline reader DOES pause downloads', () async {
      // Update setting to false
      bloc.add(const DownloadSettingsUpdateEvent(pauseOnOnlineReaderOnly: false));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Offline reader active
      anyReaderNotifier.value = true;
      onlineReaderNotifier.value = false;

      for (var i = 0;
          i < 200 &&
              db.values.where((d) => d.state == DownloadState.paused).length < 3;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(bloc.isReaderDownloadBlocked, isTrue);
      expect(bloc.readerAutoPaused, {'dl-1', 'dl-2'});
    });
  });
}
