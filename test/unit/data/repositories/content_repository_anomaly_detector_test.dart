import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' as core;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart' show getIt;
import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart';
import 'package:nhasixapp/core/services/anomaly/source_health_tracker.dart';
import 'package:nhasixapp/core/services/cache/cache_manager.dart'
    as multi_cache;
import 'package:nhasixapp/core/services/detail_cache_service.dart';
import 'package:nhasixapp/core/services/request_deduplication_service.dart';
import 'package:nhasixapp/data/datasources/remote/remote_data_source.dart';
import 'package:nhasixapp/data/repositories/content_repository_impl.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/value_objects/value_objects.dart';

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

class _MockRemoteDataSource extends Mock implements RemoteDataSource {}

class _MockDetailCacheService extends Mock implements DetailCacheService {}

class _MockContentCacheManager extends Mock
    implements multi_cache.CacheManager<Map<String, dynamic>> {}

class _MockTagCacheManager extends Mock
    implements multi_cache.CacheManager<List<Tag>> {}

class _MockContentSource extends Mock implements core.ContentSource {}

class _MockAnomalyStore extends Mock implements AnomalyStore {}

Content _content({
  required String sourceId,
  String title = 'Some Title',
  List<core.Chapter>? chapters,
}) =>
    Content(
      id: 'content-1',
      sourceId: sourceId,
      title: title,
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
      chapters: chapters,
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
    registerFallbackValue(const core.SearchFilter());
    registerFallbackValue(core.SortOption.newest);
    registerFallbackValue(Content(
      id: 'fallback',
      sourceId: 'fallback',
      title: 'fallback',
      coverUrl: '',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'id',
      pageCount: 0,
      imageUrls: const [],
      uploadDate: DateTime(2026, 5, 19),
    ));
  });

  const sourceId = 'komiktap';

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
    when(() => source.displayName).thenReturn('KomikTap');
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

  group('reader-empty detector', () {
    test('empty images with healthy source records anomaly', () async {
      when(() => source.getList(page: any(named: 'page'), sort: any(named: 'sort')))
          .thenAnswer((_) async => _listResult([_content(sourceId: sourceId)]));
      when(() => source.getChapterImages(any()))
          .thenAnswer((_) async => const core.ChapterData(images: []));

      await repository.getContentList();
      await repository.getChapterImages(ContentId.fromString('ch-1'),
          sourceId: sourceId);

      verify(() => anomalyStore.recordEvent(
            sourceId: sourceId,
            feature: 'reader-empty',
            kind: 'empty',
            contextJson: any(named: 'contextJson'),
            configVersion: '1.0.0',
            sessionId: any(named: 'sessionId'),
          )).called(1);
    });

    test('empty images with all features failing records nothing', () async {
      when(() => source.getChapterImages(any()))
          .thenAnswer((_) async => const core.ChapterData(images: []));

      final result = await repository.getChapterImages(
          ContentId.fromString('ch-1'),
          sourceId: sourceId);

      expect(result.images, isEmpty);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });

    test('null result means unsupported source, not an anomaly', () async {
      healthTracker.markSuccess(sourceId, 'list');
      when(() => source.getChapterImages(any()))
          .thenAnswer((_) async => null);

      final result = await repository.getChapterImages(
          ContentId.fromString('ch-1'),
          sourceId: sourceId);

      expect(result.images, isEmpty);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });

    test('non-empty images mark success and reset the counter', () async {
      when(() => source.getChapterImages(any())).thenAnswer(
          (_) async => const core.ChapterData(images: ['https://x/1.jpg']));

      final result = await repository.getChapterImages(
          ContentId.fromString('ch-1'),
          sourceId: sourceId);

      expect(result.images, hasLength(1));
      expect(healthTracker.isHealthy(sourceId), isTrue);
      verify(() => anomalyStore.resetFeature(sourceId, 'reader-empty'))
          .called(1);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });
  });

  group('tag-list-empty detector', () {
    const tag = Tag(id: 1, name: 'sparkle', type: 'tag', count: 10);

    test('empty tag result with healthy source records anomaly', () async {
      when(() => source.getList(page: any(named: 'page'), sort: any(named: 'sort')))
          .thenAnswer((_) async => _listResult([_content(sourceId: sourceId)]));
      when(() => source.search(any()))
          .thenAnswer((_) async => _listResult(const []));

      await repository.getContentList();
      await repository.getContentByTag(tag: tag);

      verify(() => anomalyStore.recordEvent(
            sourceId: sourceId,
            feature: 'tag-list-empty',
            kind: 'empty',
            contextJson: any(named: 'contextJson'),
            configVersion: '1.0.0',
            sessionId: any(named: 'sessionId'),
          )).called(1);
    });

    test('empty tag result with all features failing records nothing',
        () async {
      when(() => source.search(any()))
          .thenAnswer((_) async => _listResult(const []));

      await repository.getContentByTag(tag: tag);

      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });

    test('non-empty tag result marks success and resets the counter',
        () async {
      when(() => source.search(any())).thenAnswer(
          (_) async => _listResult([_content(sourceId: sourceId)]));

      final result = await repository.getContentByTag(tag: tag);

      expect(result.contents, hasLength(1));
      verify(() => anomalyStore.resetFeature(sourceId, 'tag-list-empty'))
          .called(1);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });
  });

  group('detail-parse detector', () {
    test('empty title with healthy source records anomaly', () async {
      healthTracker.markSuccess(sourceId, 'list');
      when(() => remoteConfigService.isFeatureEnabled(sourceId, any()))
          .thenReturn(true);
      when(() => detailCacheService.getCachedDetail(any()))
          .thenAnswer((_) async => null);
      when(() => detailCacheService.cacheDetail(any()))
          .thenAnswer((_) async {});
      when(() => source.getDetail(any())).thenAnswer(
          (_) async => _content(sourceId: sourceId, title: '  '));

      await repository.getContentDetail(ContentId.fromString('content-1'),
          sourceId: sourceId);

      verify(() => anomalyStore.recordEvent(
            sourceId: sourceId,
            feature: 'detail-parse',
            kind: 'parse-failed',
            contextJson: any(named: 'contextJson'),
            configVersion: '1.0.0',
            sessionId: any(named: 'sessionId'),
          )).called(1);
    });

    test('chapters that are all external do not count as parse failure',
        () async {
      healthTracker.markSuccess(sourceId, 'list');
      when(() => remoteConfigService.isFeatureEnabled(sourceId, any()))
          .thenReturn(true);
      when(() => detailCacheService.getCachedDetail(any()))
          .thenAnswer((_) async => null);
      when(() => detailCacheService.cacheDetail(any()))
          .thenAnswer((_) async {});
      when(() => source.getDetail(any())).thenAnswer(
        (_) async => _content(
          sourceId: sourceId,
          chapters: const [
            core.Chapter(
              id: 'ch-1',
              title: 'Chapter 1',
              url: 'https://x/1',
              externalUrl: 'https://comikey.com/x',
            ),
            core.Chapter(
              id: 'ch-2',
              title: 'Chapter 2',
              url: 'https://x/2',
              isUnavailable: true,
            ),
          ],
        ),
      );

      await repository.getContentDetail(ContentId.fromString('content-1'),
          sourceId: sourceId);

      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: 'detail-parse',
            kind: any(named: 'kind'),
          ));
    });

    test('valid detail marks success and resets the counter', () async {
      when(() => remoteConfigService.isFeatureEnabled(sourceId, any()))
          .thenReturn(true);
      when(() => detailCacheService.getCachedDetail(any()))
          .thenAnswer((_) async => null);
      when(() => detailCacheService.cacheDetail(any()))
          .thenAnswer((_) async {});
      when(() => source.getDetail(any())).thenAnswer((_) async => _content(
            sourceId: sourceId,
            chapters: const [
              core.Chapter(id: 'ch-1', title: 'Chapter 1', url: 'https://x/1'),
            ],
          ));

      await repository.getContentDetail(ContentId.fromString('content-1'),
          sourceId: sourceId);

      expect(healthTracker.isHealthy(sourceId), isTrue);
      verify(() => anomalyStore.resetFeature(sourceId, 'detail-parse'))
          .called(1);
      verifyNever(() => anomalyStore.recordEvent(
            sourceId: any(named: 'sourceId'),
            feature: any(named: 'feature'),
            kind: any(named: 'kind'),
          ));
    });
  });
}
