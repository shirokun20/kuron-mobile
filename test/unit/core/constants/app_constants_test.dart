import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/constants/app_constants.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/config_models.dart' as cfg;
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

final testSourceRegistry = ContentSourceRegistry();

// Mock RemoteConfigService for testing
class MockRemoteConfigService extends RemoteConfigService {
  MockRemoteConfigService() : super(dio: Dio(), logger: Logger());

  @override
  cfg.AppConfig? get appConfig => cfg.AppConfig(
        limits: cfg.AppLimits(
          defaultPageSize: 20,
          maxBatchSize: 1000,
          maxConcurrentDownloads: 3,
          searchHistoryLimit: 50,
          imagePreloadBuffer: 5,
        ),
        durations: cfg.AppDurations(
          splashDelayMs: 1000,
          snackbarShortMs: 2000,
          snackbarLongMs: 4000,
          pageTransitionMs: 300,
          searchDebounceMs: 300,
          networkTimeoutMs: 30000,
          cacheExpirationHours: 24,
          readerAutoHideDelaySeconds: 3,
          progressUpdateIntervalMs: 100,
        ),
        storage: cfg.AppStorage(
          folders: cfg.StorageFolders(
            backup: 'nhasix',
            images: 'images',
            pdf: 'pdf',
          ),
          files: cfg.StorageFiles(
            metadata: 'metadata.json',
            config: 'config.json',
          ),
          limits: cfg.StorageLimits(
            maxImageSizeKb: 200,
            pdfPartsSizePages: 100,
          ),
        ),
        ui: cfg.AppUiConfig(
          gridColumnsPortrait: 2,
          gridColumnsLandscape: 3,
          minCardWidth: 150.0,
          cardAspectRatio: 0.65,
          cardBorderRadius: 12.0,
          defaultPadding: 16.0,
          titleMaxLength: 40,
        ),
      );
}

void main() {
  setUpAll(() {
    // Initialize GetIt with mock RemoteConfigService
    final mockService = MockRemoteConfigService();
    GetIt.I.registerSingleton<RemoteConfigService>(mockService);
    GetIt.I.registerSingleton<ContentSourceRegistry>(testSourceRegistry);
  });

  tearDownAll(() {
    // Clear GetIt after all tests
    GetIt.I.reset();
  });

  group('AppLimits', () {
    test('defaultPageSize is reasonable', () {
      expect(AppLimits.defaultPageSize, greaterThan(0));
      expect(AppLimits.defaultPageSize, lessThanOrEqualTo(50));
    });

    test('maxBatchSize is larger than defaultPageSize', () {
      expect(AppLimits.maxBatchSize, greaterThan(AppLimits.defaultPageSize));
    });

    test('defaultPage is 1', () {
      expect(AppLimits.defaultPage, 1);
    });

    test('maxConcurrentDownloads is reasonable', () {
      expect(AppLimits.maxConcurrentDownloads, greaterThan(0));
      expect(AppLimits.maxConcurrentDownloads, lessThanOrEqualTo(10));
    });

    test('searchHistoryLimit is positive', () {
      expect(AppLimits.searchHistoryLimit, greaterThan(0));
    });

    test('imagePreloadBuffer is positive', () {
      expect(AppLimits.imagePreloadBuffer, greaterThan(0));
    });
  });

  group('AppDurations', () {
    test('splashDelay is not too long', () {
      expect(AppDurations.splashDelay.inSeconds, lessThanOrEqualTo(5));
    });

    test('snackbar durations are reasonable', () {
      expect(AppDurations.snackbarShort.inSeconds,
          lessThan(AppDurations.snackbarLong.inSeconds));
    });

    test('searchDebounce is reasonable', () {
      expect(AppDurations.searchDebounce.inMilliseconds,
          greaterThanOrEqualTo(100));
      expect(
          AppDurations.searchDebounce.inMilliseconds, lessThanOrEqualTo(1000));
    });

    test('networkTimeout is reasonable', () {
      expect(AppDurations.networkTimeout.inSeconds, greaterThanOrEqualTo(10));
      expect(AppDurations.networkTimeout.inSeconds, lessThanOrEqualTo(120));
    });

    test('cacheExpiration is at least 1 hour', () {
      expect(AppDurations.cacheExpiration.inHours, greaterThanOrEqualTo(1));
    });
  });

  group('AppStorage', () {
    test('knownSources always includes local when registry is populated', () {
      testSourceRegistry.register(_FakeContentSource('custom-source'));

      final knownSources = AppStorage.knownSources;

      expect(knownSources, contains('custom-source'));
      expect(knownSources, contains('local'));
    });

    test('backupFolderName is not empty', () {
      expect(AppStorage.backupFolderName, isNotEmpty);
    });

    test('metadataFileName ends with .json', () {
      expect(AppStorage.metadataFileName.endsWith('.json'), true);
    });

    test('imagesSubfolder is not empty', () {
      expect(AppStorage.imagesSubfolder, isNotEmpty);
    });

    test('maxImageSizeKb is reasonable', () {
      expect(AppStorage.maxImageSizeKb, greaterThan(0));
      expect(AppStorage.maxImageSizeKb, lessThanOrEqualTo(1000));
    });
  });

  group('AppUI', () {
    test('gridColumnsPortrait is greater than 0', () {
      expect(AppUI.gridColumnsPortrait, greaterThan(0));
    });

    test('gridColumnsLandscape is greater than portrait', () {
      expect(AppUI.gridColumnsLandscape,
          greaterThanOrEqualTo(AppUI.gridColumnsPortrait));
    });

    test('minCardWidth is positive', () {
      expect(AppUI.minCardWidth, greaterThan(0));
    });

    test('cardAspectRatio is reasonable', () {
      expect(AppUI.cardAspectRatio, greaterThan(0));
      expect(AppUI.cardAspectRatio, lessThan(2));
    });

    test('cardBorderRadius is positive', () {
      expect(AppUI.cardBorderRadius, greaterThan(0));
    });

    test('defaultPadding is positive', () {
      expect(AppUI.defaultPadding, greaterThan(0));
    });

    test('titleMaxLength is positive', () {
      expect(AppUI.titleMaxLength, greaterThan(0));
    });
  });

  group('AppConfig', () {
    test('minAndroidSdk is at least API 21', () {
      expect(AppConfig.minAndroidSdk, greaterThanOrEqualTo(21));
    });

    test('feature flags are boolean', () {
      expect(AppConfig.enablePerformanceMonitoring, isA<bool>());
      expect(AppConfig.enableAnalytics, isA<bool>());
    });
  });
}

class _FakeContentSource extends ContentSource {
  _FakeContentSource(this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  String get displayName => _id;

  @override
  String get iconPath => '';

  @override
  String get baseUrl => '';

  @override
  bool get requiresBypass => false;

  @override
  SearchCapabilities get searchCapabilities =>
      SearchCapabilities.defaultCapabilities;

  @override
  Future<ContentListResult> search(
    SearchFilter filter, {
    OnCancelRegister? onCancel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Content> getDetail(
    String contentId, {
    OnCancelRegister? onCancel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ContentListResult> getList({
    int page = 1,
    SortOption sort = SortOption.newest,
    OnCancelRegister? onCancel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ContentListResult> getPopular({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
    OnCancelRegister? onCancel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Content>> getRandom({int count = 1}) {
    throw UnimplementedError();
  }

  @override
  Future<List<Content>> getRelated(
    String contentId, {
    OnCancelRegister? onCancel,
  }) {
    throw UnimplementedError();
  }

  @override
  String buildImageUrl({
    required String contentId,
    required String mediaId,
    required int page,
    required String extension,
    bool thumbnail = false,
  }) {
    throw UnimplementedError();
  }

  @override
  String buildThumbnailUrl({
    required String contentId,
    required String mediaId,
  }) {
    throw UnimplementedError();
  }

  @override
  String? parseContentIdFromUrl(String url) => null;

  @override
  bool isValidContentId(String contentId) => true;

  @override
  String get refererHeader => '';

  @override
  Map<String, String> getImageDownloadHeaders({
    required String imageUrl,
    Map<String, String>? cookies,
  }) {
    return const {};
  }
}
