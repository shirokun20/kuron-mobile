import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' as core;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart' show getIt;
import 'package:nhasixapp/data/datasources/remote/remote_data_source.dart';
import 'package:nhasixapp/data/models/content_model.dart';
import 'package:nhasixapp/data/repositories/content_repository_impl.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/value_objects/value_objects.dart';
import 'package:nhasixapp/core/services/cache/cache_manager.dart'
    as multi_cache;
import 'package:nhasixapp/core/services/detail_cache_service.dart';
import 'package:nhasixapp/core/services/request_deduplication_service.dart';

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

class MockRemoteDataSource extends Mock implements RemoteDataSource {}

class MockDetailCacheService extends Mock implements DetailCacheService {}

class MockContentCacheManager extends Mock
    implements multi_cache.CacheManager<Map<String, dynamic>> {}

class MockTagCacheManager extends Mock
    implements multi_cache.CacheManager<List<Tag>> {}

class MockContentSource extends Mock implements core.ContentSource {}

void main() {
  setUpAll(() {
    // RequestDeduplicationService resolves Logger via GetIt
    // (commit 5f34d29a moved Logger to DI without updating tests).
    getIt.registerSingleton<Logger>(Logger(level: Level.off));
  });

  tearDownAll(() {
    getIt.reset();
  });

  late core.ContentSourceRegistry registry;
  late MockRemoteConfigService remoteConfigService;
  late MockRemoteDataSource remoteDataSource;
  late MockDetailCacheService detailCacheService;
  late MockContentCacheManager contentCacheManager;
  late MockTagCacheManager tagCacheManager;
  late MockContentSource source;
  late ContentRepositoryImpl repository;

  const sourceId = 'komiktap';
  const contentId = 'you-wont-break-me';

  final staleCachedContent = Content(
    id: contentId,
    sourceId: sourceId,
    title: "You Won't Break Me",
    coverUrl: 'https://cdn.example.com/cover.jpg',
    tags: const [],
    artists: const [],
    characters: const [],
    parodies: const [],
    groups: const [],
    language: 'id',
    pageCount: 18,
    imageUrls: const ['https://cdn.example.com/cover.jpg'],
    uploadDate: DateTime(2026, 5, 19),
    chapters: null,
  );

  final freshContent = Content(
    id: contentId,
    sourceId: sourceId,
    title: "You Won't Break Me",
    coverUrl: 'https://cdn.example.com/cover.jpg',
    tags: const [],
    artists: const [],
    characters: const [],
    parodies: const [],
    groups: const [],
    language: 'id',
    pageCount: 2,
    imageUrls: const [],
    uploadDate: DateTime(2026, 5, 19),
    chapters: [
      const core.Chapter(
        id: 'you-wont-break-me-chapter-37',
        title: 'Chapter 37',
        url: 'https://komiktap.info/you-wont-break-me-chapter-37/',
      ),
      const core.Chapter(
        id: 'you-wont-break-me-chapter-36',
        title: 'Chapter 36',
        url: 'https://komiktap.info/you-wont-break-me-chapter-36/',
      ),
    ],
  );

  final staleEmptyChapterContent = staleCachedContent.copyWith(
    chapters: const <core.Chapter>[],
  );

  setUp(() {
    registry = core.ContentSourceRegistry();
    remoteConfigService = MockRemoteConfigService();
    remoteDataSource = MockRemoteDataSource();
    detailCacheService = MockDetailCacheService();
    contentCacheManager = MockContentCacheManager();
    tagCacheManager = MockTagCacheManager();
    source = MockContentSource();

    when(() => source.id).thenReturn(sourceId);
    when(() => source.displayName).thenReturn('KomikTap');
    registry.register(source);

    when(() => remoteConfigService.isFeatureEnabled(any(), any()))
        .thenReturn(false);

    when(() => contentCacheManager.get(any())).thenAnswer((_) async => null);
    when(() => contentCacheManager.set(any(), any(), ttl: any(named: 'ttl')))
        .thenAnswer((_) async {});
    when(() => detailCacheService.cacheDetail(freshContent))
        .thenAnswer((_) async {});

    repository = ContentRepositoryImpl(
      contentSourceRegistry: registry,
      remoteConfigService: remoteConfigService,
      remoteDataSource: remoteDataSource,
      detailCacheService: detailCacheService,
      requestDeduplicationService: RequestDeduplicationService(),
      contentCacheManager: contentCacheManager,
      tagCacheManager: tagCacheManager,
    );
  });

  test(
      'getContentDetail bypasses stale chapter cache when chapter feature is enabled',
      () async {
    when(() => remoteConfigService.isFeatureEnabled(sourceId, any()))
        .thenReturn(true);

    when(() => detailCacheService.getCachedDetail(contentId))
        .thenAnswer((_) async => staleCachedContent);
    when(() => source.getDetail(contentId))
        .thenAnswer((_) async => freshContent);

    final result =
        await repository.getContentDetail(ContentId.fromString(contentId));

    expect(result.chapters, isNotNull);
    expect(result.chapters, hasLength(2));
    expect(result.chapters!.first.id, 'you-wont-break-me-chapter-37');
    verify(() => source.getDetail(contentId)).called(1);
    verify(() => detailCacheService.getCachedDetail(contentId)).called(1);
  });

  test('getContentDetail bypasses empty chapter cache for chapter sources',
      () async {
    const shiroSourceId = 'shirodoujin';
    final shiroSource = MockContentSource();
    final freshShiroContent = freshContent.copyWith(sourceId: shiroSourceId);
    final staleShiroContent = staleEmptyChapterContent.copyWith(
      sourceId: shiroSourceId,
    );

    when(() => shiroSource.id).thenReturn(shiroSourceId);
    when(() => shiroSource.displayName).thenReturn('ShiroDoujin');
    when(() => remoteConfigService.isFeatureEnabled(shiroSourceId, any()))
        .thenReturn(true);
    when(() => shiroSource.getDetail(contentId))
        .thenAnswer((_) async => freshShiroContent);
    when(() => detailCacheService.cacheDetail(freshShiroContent))
        .thenAnswer((_) async {});
    when(() => detailCacheService.getCachedDetail(contentId))
        .thenAnswer((_) async => staleShiroContent);
    registry.register(shiroSource);

    final result = await repository.getContentDetail(
      ContentId.fromString(contentId),
      sourceId: shiroSourceId,
    );

    expect(result.chapters, isNotEmpty);
    verify(() => shiroSource.getDetail(contentId)).called(1);
  });

  test('getContentDetail bypasses invalid memory-cache title and refreshes',
      () async {
    const shiroSourceId = 'shirodoujin';
    final shiroSource = MockContentSource();
    final staleMemoryMap = {
      ...ContentModel.fromEntity(
        staleEmptyChapterContent.copyWith(
          sourceId: shiroSourceId,
          title: 'Unknown',
        ),
      ).toJson(),
    };
    final freshShiroContent = freshContent.copyWith(
      sourceId: shiroSourceId,
      title: 'My Body is Atop Her Tongue Bahasa Indonesia',
    );

    when(() => shiroSource.id).thenReturn(shiroSourceId);
    when(() => shiroSource.displayName).thenReturn('ShiroDoujin');
    when(() => remoteConfigService.isFeatureEnabled(shiroSourceId, any()))
        .thenReturn(true);
    when(() => contentCacheManager.get('content_$contentId'))
        .thenAnswer((_) async => staleMemoryMap);
    when(() => detailCacheService.getCachedDetail(contentId))
        .thenAnswer((_) async => null);
    when(() => shiroSource.getDetail(contentId))
        .thenAnswer((_) async => freshShiroContent);
    when(() => detailCacheService.cacheDetail(freshShiroContent))
        .thenAnswer((_) async {});
    registry.register(shiroSource);

    final result = await repository.getContentDetail(
      ContentId.fromString(contentId),
      sourceId: shiroSourceId,
    );

    expect(result.title, 'My Body is Atop Her Tongue Bahasa Indonesia');
    verify(() => shiroSource.getDetail(contentId)).called(1);
  });

  test(
      'getContentDetail bypasses stale nicomanga cache when tags only mirror language',
      () async {
    const nicomangaSourceId = 'nicomanga';
    final nicomangaSource = MockContentSource();
    final staleNicomangaContent = Content(
      id: contentId,
      sourceId: nicomangaSourceId,
      title: 'Nicomanga Cached Detail',
      coverUrl: 'https://cdn.example.com/cover.jpg',
      tags: const [Tag(id: 0, name: 'japanese', type: 'tag', count: 0)],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'japanese',
      pageCount: 10,
      imageUrls: const ['https://cdn.example.com/cover.jpg'],
      uploadDate: DateTime(2026, 5, 27),
      chapters: const [
        core.Chapter(
          id: 'nicomanga-chapter-1',
          title: 'Chapter 1',
          url: 'https://nicomanga.com/read-1.html',
        ),
      ],
    );
    final refreshedNicomangaContent = staleNicomangaContent.copyWith(
      tags: const [
        Tag(id: 0, name: 'Comedy', type: 'tag', count: 0),
        Tag(id: 0, name: 'Fantasy', type: 'tag', count: 0),
      ],
    );

    when(() => nicomangaSource.id).thenReturn(nicomangaSourceId);
    when(() => nicomangaSource.displayName).thenReturn('Nicomanga');
    when(() => nicomangaSource.getDetail(contentId))
        .thenAnswer((_) async => refreshedNicomangaContent);
    when(() => detailCacheService.cacheDetail(refreshedNicomangaContent))
        .thenAnswer((_) async {});
    registry.register(nicomangaSource);

    when(() => detailCacheService.getCachedDetail(contentId))
        .thenAnswer((_) async => staleNicomangaContent);

    final result = await repository.getContentDetail(
      ContentId.fromString(contentId),
      sourceId: nicomangaSourceId,
    );

    expect(
        result.tags.map((tag) => tag.name), containsAll(['Comedy', 'Fantasy']));
    verify(() => nicomangaSource.getDetail(contentId)).called(1);
    verify(() => detailCacheService.getCachedDetail(contentId)).called(1);
  });
}
