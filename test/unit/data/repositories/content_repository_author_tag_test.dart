// End-to-end proof for shirokun20/kuron-mobile#69 — an author/artist tag
// click must reach the source as its own typed, slug-carrying includeTag.
//
// Chain asserted here: Tag.slug → app FilterItem (type prefix + raw slug)
// → core.FilterItem (type `author`/`artist`, not collapsed to `artist`) →
// the URL the scraper builds. The scraper side (prefix → authorSearch,
// prefix stripping) is covered in
// packages/kuron_generic/test/adapters/author_tag_routing_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' as core;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart' show getIt;
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

void main() {
  setUpAll(() {
    getIt.registerSingleton<Logger>(Logger(level: Level.off));
    // mocktail needs a valid SearchFilter to match `any()` against.
    registerFallbackValue(const core.SearchFilter());
  });

  tearDownAll(() {
    getIt.reset();
  });

  late _MockRemoteConfigService remoteConfigService;
  late _MockContentSource source;
  late ContentRepositoryImpl repository;

  const sourceId = 'manhwaden';

  setUp(() {
    final registry = core.ContentSourceRegistry();
    remoteConfigService = _MockRemoteConfigService();
    source = _MockContentSource();
    when(() => source.id).thenReturn(sourceId);
    when(() => source.displayName).thenReturn('Manhwaden');
    registry.register(source);

    when(() => remoteConfigService.getRawConfig(sourceId)).thenReturn({
      'scraper': {
        'urlPatterns': {
          'genreSearch': {'url': '/manga-genre/{tag}/'},
          'authorSearch': {'url': '/manga-author/{tag}/'},
          'artistSearch': {'url': '/manga-artist/{tag}/'},
        },
      },
      'navigation': {'genreQueryPrefix': 'genre:', 'genreTagType': 'genre'},
    });
    when(() => source.search(any())).thenAnswer(
      (_) async => const core.ContentListResult(
        contents: [],
        currentPage: 1,
        totalPages: 1,
        totalCount: 0,
      ),
    );

    repository = ContentRepositoryImpl(
      contentSourceRegistry: registry,
      remoteConfigService: remoteConfigService,
      remoteDataSource: _MockRemoteDataSource(),
      detailCacheService: _MockDetailCacheService(),
      requestDeduplicationService: RequestDeduplicationService(),
      contentCacheManager: _MockContentCacheManager(),
      tagCacheManager: _MockTagCacheManager(),
      logger: Logger(level: Level.off),
    );
  });

  core.SearchFilter captured() {
    final c = verify(() => source.search(captureAny())).captured.single
        as core.SearchFilter;
    return c;
  }

  test('author tag keeps type `author` and the href slug (no prefix leak)',
      () async {
    await repository.getContentByTag(
      tag: const Tag(
        id: 0,
        name: 'Total Genius',
        type: 'author',
        count: 0,
        slug: 'total-genius',
      ),
    );

    final filter = captured();
    expect(filter.query, isEmpty);
    expect(filter.includeTags, hasLength(1));
    final item = filter.includeTags.single;
    expect(item.type, 'author');
    expect(item.name, 'author:total-genius');
  });

  test('artist tag routes with type `artist` and the href slug', () async {
    await repository.getContentByTag(
      tag: const Tag(
        id: 0,
        name: 'Jungeon',
        type: 'artist',
        count: 0,
        slug: 'jungeon',
      ),
    );

    final item = captured().includeTags.single;
    expect(item.type, 'artist');
    expect(item.name, 'artist:jungeon');
  });

  test('slugified-away names keep the site slug verbatim (CJK case)', () async {
    await repository.getContentByTag(
      tag: const Tag(
        id: 0,
        name: 'Pig On a Journey (',
        type: 'artist',
        count: 0,
        slug: 'pig-on-a-journey-%e6%85%a2%e9%80%94%e7%9a%84%e7%8c%aa',
      ),
    );

    expect(captured().includeTags.single.name,
        'artist:pig-on-a-journey-%e6%85%a2%e9%80%94%e7%9a%84%e7%8c%aa');
  });

  test('falls back to the display name when no slug is present', () async {
    await repository.getContentByTag(
      tag: const Tag(id: 0, name: 'Han Se', type: 'artist', count: 0),
    );

    final item = captured().includeTags.single;
    expect(item.type, 'artist');
    expect(item.name, 'artist:Han Se');
  });

  test('plain tag is unaffected and carries no type prefix', () async {
    await repository.getContentByTag(
      tag: const Tag(id: 0, name: 'Action', type: 'tag', count: 0),
    );

    final item = captured().includeTags.single;
    expect(item.type, 'tag');
    expect(item.name, 'Action');
  });
}
