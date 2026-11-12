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
import 'package:nhasixapp/core/services/request_deduplication_service.dart';
import 'package:nhasixapp/data/datasources/remote/remote_data_source.dart';
import 'package:nhasixapp/data/repositories/content_repository_impl.dart';
import 'package:nhasixapp/domain/entities/entities.dart';

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockRemoteDataSource extends Mock implements RemoteDataSource {}

class _MockDetailCacheService extends Mock implements DetailCacheService {}

class _MockContentCacheManager extends Mock
    implements multi_cache.CacheManager<Map<String, dynamic>> {}

class _MockTagCacheManager extends Mock
    implements multi_cache.CacheManager<List<Tag>> {}

class _MockContentSource extends Mock implements core.ContentSource {}

class _MockAnomalyStore extends Mock implements AnomalyStore {}

Content _content({required String sourceId}) => Content(
      id: 'content-1',
      sourceId: sourceId,
      title: 'Some Title',
      coverUrl: 'https://cdn.example.com/cover.jpg',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'id',
      pageCount: 18,
      imageUrls: const [],
      uploadDate: DateTime(2026, 5, 19),
    );

core.ContentListResult _listResult(List<Content> contents) =>
    core.ContentListResult(
      contents: contents,
      currentPage: 1,
      totalPages: 1,
      totalCount: contents.length,
    );

void main() {
  setUpAll(() {
    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(level: Level.off));
    }
    registerFallbackValue(core.SortOption.newest);
  });

  const sourceId = 'anisascansin';

  late core.ContentSourceRegistry registry;
  late _MockRemoteConfigService remoteConfigService;
  late _MockRemoteDataSource remoteDataSource;
  late _MockDetailCacheService detailCacheService;
  late _MockContentCacheManager contentCacheManager;
  late _MockTagCacheManager tagCacheManager;
  late _MockContentSource source;
  late _MockAnomalyStore anomalyStore;
  late SourceHealthTracker healthTracker;
  late ContentRepositoryImpl repository;

  setUp(() {
    registry = core.ContentSourceRegistry();
    remoteConfigService = _MockRemoteConfigService();
    remoteDataSource = _MockRemoteDataSource();
    detailCacheService = _MockDetailCacheService();
    contentCacheManager = _MockContentCacheManager();
    tagCacheManager = _MockTagCacheManager();
    source = _MockContentSource();
    anomalyStore = _MockAnomalyStore();
    healthTracker = SourceHealthTracker();

    when(() => source.id).thenReturn(sourceId);
    when(() => source.displayName).thenReturn('AnisaScans');
    registry.register(source);

    when(() => remoteConfigService.isFeatureEnabled(any(), any()))
        .thenReturn(false);
    when(() => remoteConfigService.getInstalledVersion(any()))
        .thenReturn('1.0.0');
    when(() => contentCacheManager.get(any())).thenAnswer((_) async => null);
    when(() => contentCacheManager.set(any(), any(), ttl: any(named: 'ttl')))
        .thenAnswer((_) async {});
    when(() => anomalyStore.recordEvent(
          sourceId: any(named: 'sourceId'),
          feature: any(named: 'feature'),
          kind: any(named: 'kind'),
          contextJson: any(named: 'contextJson'),
          configVersion: any(named: 'configVersion'),
          sessionId: any(named: 'sessionId'),
        )).thenAnswer((_) async {});
    when(() => anomalyStore.resetFeature(any(), any()))
        .thenAnswer((_) async {});

    repository = ContentRepositoryImpl(
      contentSourceRegistry: registry,
      remoteConfigService: remoteConfigService,
      remoteDataSource: remoteDataSource,
      detailCacheService: detailCacheService,
      requestDeduplicationService: RequestDeduplicationService(),
      contentCacheManager: contentCacheManager,
      tagCacheManager: tagCacheManager,
      anomalyStore: anomalyStore,
      healthTracker: healthTracker,
    );
  });

  group('home-empty detector', () {
    test('page-1 empty with healthy source records home-empty', () async {
      when(() => source.getList(
          page: any(named: 'page'),
          sort: any(named: 'sort'))).thenAnswer((_) async => _listResult([]));
      healthTracker.markSuccess(sourceId, 'detail');

      final result = await repository.getContentList();

      expect(result.contents, isEmpty);
      verify(() => anomalyStore.recordEvent(
            sourceId: sourceId,
            feature: 'home-empty',
            kind: 'empty',
            contextJson: any(named: 'contextJson'),
            configVersion: '1.0.0',
            sessionId: any(named: 'sessionId'),
          )).called(1);
    });

    test('page-1 empty with all features failing records nothing',
        () async {
      when(() => source.getList(
          page: any(named: 'page'),
          sort: any(named: 'sort'))).thenAnswer((_) async => _listResult([]));

      await repository.getContentList();

      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
            contextJson: any(named: 'contextJson'),
            configVersion: any(named: 'configVersion'),
            sessionId: any(named: 'sessionId'),
          ));
    });

    test('page-2 empty is not recorded (catalog end is legitimate)',
        () async {
      when(() => source.getList(
          page: any(named: 'page'),
          sort: any(named: 'sort'))).thenAnswer((_) async => _listResult([]));
      healthTracker.markSuccess(sourceId, 'detail');

      await repository.getContentList(page: 2);

      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: 'home-empty',
            kind: any(named: 'kind'),
            contextJson: any(named: 'contextJson'),
            configVersion: any(named: 'configVersion'),
            sessionId: any(named: 'sessionId'),
          ));
    });

    test('non-empty home resets home-empty and marks list healthy', () async {
      when(() => source.getList(
          page: any(named: 'page'),
          sort: any(named: 'sort'))).thenAnswer(
          (_) async => _listResult([_content(sourceId: sourceId)]));

      final result = await repository.getContentList();

      expect(result.contents, isNotEmpty);
      verify(() => anomalyStore.resetFeature(sourceId, 'home-empty'))
          .called(1);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: 'home-empty',
            kind: any(named: 'kind'),
            contextJson: any(named: 'contextJson'),
            configVersion: any(named: 'configVersion'),
            sessionId: any(named: 'sessionId'),
          ));
    });
  });
}
