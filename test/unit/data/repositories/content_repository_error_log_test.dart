import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' as core;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart' show getIt;
import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart';
import 'package:nhasixapp/core/services/cache/cache_manager.dart'
    as multi_cache;
import 'package:nhasixapp/core/services/detail_cache_service.dart';
import 'package:nhasixapp/core/services/error_log/error_log.dart';
import 'package:nhasixapp/core/services/request_deduplication_service.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:nhasixapp/data/datasources/remote/exceptions.dart';
import 'package:nhasixapp/data/datasources/remote/remote_data_source.dart';
import 'package:nhasixapp/data/repositories/content_repository_impl.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/value_objects/value_objects.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockRemoteDataSource extends Mock implements RemoteDataSource {}

class _MockDetailCacheService extends Mock implements DetailCacheService {}

class _MockContentCacheManager extends Mock
    implements multi_cache.CacheManager<Map<String, dynamic>> {}

class _MockTagCacheManager extends Mock
    implements multi_cache.CacheManager<List<Tag>> {}

class _MockContentSource extends Mock implements core.ContentSource {}

class _MockAnomalyStore extends Mock implements AnomalyStore {}

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

void main() {
  const sourceId = 'komiktap';

  late core.ContentSourceRegistry registry;
  late _MockContentSource source;
  late _MockDatabaseHelper helper;
  late _MockDatabase db;
  late ContentRepositoryImpl repository;

  setUpAll(() {
    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(level: Level.off));
    }
    registerFallbackValue(core.SortOption.newest);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErrorLog.debugReset();

    registry = core.ContentSourceRegistry();
    source = _MockContentSource();
    when(() => source.id).thenReturn(sourceId);
    when(() => source.displayName).thenReturn('KomikTap');
    registry.register(source);

    helper = _MockDatabaseHelper();
    db = _MockDatabase();
    when(() => helper.database).thenAnswer((_) async => db);
    when(() => db.insert(any(), any())).thenAnswer((_) async => 1);
    when(
      () => db.query(
        any(),
        columns: any(named: 'columns'),
        orderBy: any(named: 'orderBy'),
      ),
    ).thenAnswer((_) async => <Map<String, Object?>>[]);

    ErrorLog.debugConfigure(dbHelper: helper, appVersion: '1.2.3+7');

    final remoteConfigService = _MockRemoteConfigService();
    when(() => remoteConfigService.isFeatureEnabled(any(), any()))
        .thenReturn(false);
    when(() => remoteConfigService.getInstalledVersion(any()))
        .thenReturn('1.0.0');

    final contentCacheManager = _MockContentCacheManager();
    when(() => contentCacheManager.get(any())).thenAnswer((_) async => null);
    when(() => contentCacheManager.set(any(), any(), ttl: any(named: 'ttl')))
        .thenAnswer((_) async {});

    final anomalyStore = _MockAnomalyStore();
    when(
      () => anomalyStore.recordEvent(
        sourceId: any(named: 'sourceId'),
        feature: any(named: 'feature'),
        kind: any(named: 'kind'),
        contextJson: any(named: 'contextJson'),
        configVersion: any(named: 'configVersion'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
    when(() => anomalyStore.resetFeature(any(), any()))
        .thenAnswer((_) async {});

    repository = ContentRepositoryImpl(
      contentSourceRegistry: registry,
      remoteConfigService: remoteConfigService,
      remoteDataSource: _MockRemoteDataSource(),
      detailCacheService: _MockDetailCacheService(),
      requestDeduplicationService: RequestDeduplicationService(),
      contentCacheManager: contentCacheManager,
      tagCacheManager: _MockTagCacheManager(),
      anomalyStore: anomalyStore,
      healthTracker: SourceHealthTracker(),
    );
  });

  tearDown(ErrorLog.debugReset);

  Map<String, Object?> onlyInserted() =>
      verify(() => db.insert('error_log', captureAny())).captured.single
          as Map<String, Object?>;

  group('error recording', () {
    test('repository exception is recorded with feature + sourceId', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any()))
          .thenAnswer((_) async => throw Exception('socket closed'));

      final result = await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      // Return behaviour untouched.
      expect(result.images, isEmpty);

      final inserted = onlyInserted();
      expect(inserted['sourceId'], sourceId);
      expect(inserted['feature'], 'getChapterImages');
      expect(inserted['message'], contains('socket closed'));
      expect(inserted['appVersion'], '1.2.3+7');
    });

    test('HTTP 5xx keeps its status code', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any())).thenAnswer(
        (_) async => throw const ServerException('Bad Gateway', '502'),
      );

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      expect(onlyInserted()['statusCode'], 502);
    });

    test('timeout is recorded without a status code', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any())).thenAnswer(
        (_) async => throw const TimeoutException('Connection timed out'),
      );

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      final inserted = onlyInserted();
      expect(inserted['statusCode'], isNull);
      expect(inserted['message'], contains('Connection timed out'));
    });
  });

  group('error exclusions', () {
    test('cloudflare challenge is never recorded', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any())).thenAnswer(
        (_) async => throw const CloudflareException('challenge detected'),
      );

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      verifyNever(() => db.insert(any(), any()));
    });

    test('403 WAF response is never recorded', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any())).thenAnswer(
        (_) async => throw const ServerException('Forbidden', '403'),
      );

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      verifyNever(() => db.insert(any(), any()));
    });

    test('login-wall is never recorded', () async {
      await ErrorLog.setEnabled(true);
      when(() => source.getChapterImages(any())).thenAnswer(
        (_) async => throw core.LoginRequiredException('login required'),
      );

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      verifyNever(() => db.insert(any(), any()));
    });

    test('toggle off writes nothing even for a real error', () async {
      when(() => source.getChapterImages(any()))
          .thenAnswer((_) async => throw Exception('socket closed'));

      await repository.getChapterImages(
        ContentId.fromString('ch-1'),
        sourceId: sourceId,
      );
      await pumpEventQueue();

      verifyNever(() => db.insert(any(), any()));
    });
  });
}
