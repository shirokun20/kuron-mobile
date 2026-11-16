import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';

import 'package:nhasixapp/domain/entities/download_status.dart';
import 'package:nhasixapp/domain/entities/user_preferences.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kuron_core/kuron_core.dart';

// Corrected Imports based on error logs and file structure
import 'package:nhasixapp/domain/usecases/downloads/download_content_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_content_detail_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/get_chapter_images_usecase.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart'; // Was network/
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/services/pdf_conversion_service.dart';
import 'package:logger/logger.dart';

import '../../../presentation/blocs/download/download_bloc_test.dart';
// For ContentModel if needed, but imported above too.

// Manual Mocks
class MockUserDataRepository extends Fake implements UserDataRepository {
  @override
  Future<UserPreferences> getUserPreferences() async {
    return const UserPreferences(
      autoRetry: true,
      retryAttempts: 3,
      retryDelaySeconds: 2,
    );
  }

  @override
  Future<List<DownloadStatus>> getAllDownloads({
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    return [
      DownloadStatus(
        contentId: 'test-id',
        title: 'Test Content',
        state: DownloadState.downloading,
        retryCount: 0,
        downloadPath: '',
        startTime: DateTime.now(),
      )
    ];
  }

  @override
  Future<void> saveDownloadStatus(DownloadStatus status) async {}
}

class MockDownloadContentUseCase extends Fake
    implements DownloadContentUseCase {
  @override
  Future<DownloadStatus> call(DownloadContentParams params) async {
    throw Exception('Simulated Network Error');
  }
}

class MockConnectivity extends Fake implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
}

class MockNotificationService extends Fake implements NotificationService {
  @override
  Future<void> showDownloadError(
      {required String contentId,
      required String title,
      required String error}) async {}

  @override
  Future<void> initialize() async {
    return;
  }

  @override
  void setCallbacks({
    void Function(String contentId)? onDownloadPause,
    void Function(String contentId)? onDownloadResume,
    void Function(String contentId)? onDownloadCancel,
    void Function(String contentId)? onDownloadRetry,
    void Function(String contentId)? onPdfRetry,
    void Function(String contentId)? onOpenDownload,
    void Function(String? contentId)? onNavigateToDownloads,
    VoidCallback? onPauseAll,
    VoidCallback? onCancelAll,
  }) {
    // No-op for test
  }
}

class MockRemoteConfigService extends Fake implements RemoteConfigService {
  @override
  Null get appConfig => null;
}

class MockGetContentDetailUseCase extends Fake
    implements GetContentDetailUseCase {}

class MockGetChapterImagesUseCase extends Fake
    implements GetChapterImagesUseCase {}

class MockPdfConversionService extends Fake implements PdfConversionService {}

class MockOfflineContentManager extends Fake implements OfflineContentManager {}

class MockLogger extends Fake implements Logger {
  @override
  void i(dynamic message,
      {DateTime? time, Object? error, StackTrace? stackTrace}) {}
  @override
  void e(dynamic message,
      {DateTime? time, Object? error, StackTrace? stackTrace}) {}
  @override
  void w(dynamic message,
      {DateTime? time, Object? error, StackTrace? stackTrace}) {}
  @override
  void d(dynamic message,
      {DateTime? time, Object? error, StackTrace? stackTrace}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(MockLogger());
    }
    if (!GetIt.I.isRegistered<RemoteConfigService>()) {
      GetIt.I.registerSingleton<RemoteConfigService>(MockRemoteConfigService());
    }
    if (!GetIt.I.isRegistered<ContentSourceRegistry>()) {
      GetIt.I.registerSingleton<ContentSourceRegistry>(ContentSourceRegistry());
    }
  });

  tearDown(() {
    GetIt.I.reset();
  });

  test('DownloadBloc emits Retrying status immediately on failure', () async {
    final bloc = DownloadBloc(
      userDataRepository: MockUserDataRepository(),
      downloadContentUseCase: MockDownloadContentUseCase(),
      getContentDetailUseCase: MockGetContentDetailUseCase(),
      getChapterImagesUseCase: MockGetChapterImagesUseCase(),
      offlineContentManager: MockOfflineContentManager(),
      connectivity: MockConnectivity(),
      notificationService: MockNotificationService(),
      remoteConfigService: MockRemoteConfigService(),
      pdfConversionService: MockPdfConversionService(),
      logger: MockLogger(),
      pdfConversionQueueManager: MockPdfConversionQueueManager(),
    );

    // Listen to changes immediately
    final states = <DownloadState>[];
    final subscription = bloc.stream.listen((state) {
      debugPrint('Stream Emitted: $state');
      if (state is DownloadError) {
        debugPrint('DOWNLOAD ERROR MESSAGE: ${state.message}');
        debugPrint('DOWNLOAD ERROR TYPE: ${state.errorType}');
        debugPrint('DOWNLOAD ERROR STACKTRACE: ${state.stackTrace}');
      }
      if (state is DownloadLoaded) {
        try {
          final download =
              state.downloads.firstWhere((d) => d.contentId == 'test-id');
          debugPrint(
              'Download Item State: ${download.state} - Error: ${download.error}');
          states.add(download.state);
        } catch (e) {
          debugPrint('Download item test-id not found in state');
        }
      }
    });

    debugPrint('Initializing Bloc...');
    bloc.add(const DownloadInitializeEvent());

    // Wait for initial load
    await Future.delayed(const Duration(milliseconds: 200));

    debugPrint('Starting Download...');
    // Trigger start (will fail and should retry)
    bloc.add(const DownloadStartEvent('test-id'));

    // Wait for retry logic
    await Future.delayed(const Duration(milliseconds: 1000));

    await subscription.cancel();
    await bloc.close();

    // We expect the state to have gone: Downloading -> Queued (Retrying) -> ...
    expect(states, contains(DownloadState.queued));
  });
}
