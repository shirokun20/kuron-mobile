import 'package:logger/logger.dart';
import 'package:nhasixapp/data/models/content_model.dart';

import '../../core/config/remote_config_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_repository.dart';
import '../../domain/value_objects/value_objects.dart';
import '../datasources/remote/remote_data_source.dart';
import '../../core/services/cache/cache_manager.dart' as multi_cache;
import '../models/tag_model.dart';
import '../../core/services/detail_cache_service.dart';
import '../datasources/remote/exceptions.dart';
import '../../core/services/request_deduplication_service.dart';
import 'package:kuron_core/kuron_core.dart' as core;

// Implementation of ContentRepository with caching strategy and offline-first architecture
class ContentRepositoryImpl implements ContentRepository {
  ContentRepositoryImpl({
    required this.contentSourceRegistry,
    required this.remoteConfigService,
    required this.remoteDataSource, // Keep for legacy tag ops for now
    required this.detailCacheService,
    required this.requestDeduplicationService,
    required this.contentCacheManager,
    required this.tagCacheManager,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final core.ContentSourceRegistry contentSourceRegistry;
  final RemoteConfigService remoteConfigService;
  final RemoteDataSource remoteDataSource;
  final DetailCacheService detailCacheService;
  final RequestDeduplicationService requestDeduplicationService;
  final multi_cache.CacheManager<Map<String, dynamic>> contentCacheManager;
  final multi_cache.CacheManager<List<Tag>> tagCacheManager;
  final Logger _logger;

  static const Duration cacheExpiration = Duration(hours: 6);
  static const int defaultPageSize = 20;

  core.ContentSource get _activeSource {
    final source = contentSourceRegistry.currentSource;
    if (source == null) {
      throw Exception('No active content source found');
    }
    return source;
  }

  @override
  Future<ContentListResult> getContentList({
    int page = 1,
    SortOption sortBy = SortOption.newest,
  }) async {
    try {
      _logger.i('Getting content list - page: $page, sort: $sortBy');

      try {
        // Map SortOption
        core.SortOption coreSort = core.SortOption.newest;
        if (sortBy == SortOption.popular) coreSort = core.SortOption.popular;
        if (sortBy == SortOption.popularWeek) {
          coreSort = core.SortOption.popularWeek;
        }
        if (sortBy == SortOption.popularToday) {
          coreSort = core.SortOption.popularToday;
        }
        if (sortBy == SortOption.rating) coreSort = core.SortOption.rating;

        final coreResult =
            await _activeSource.getList(page: page, sort: coreSort);

        // Cache individual content items
        final entities = coreResult.contents.map(_mapToAppContent).toList();

        for (final content in entities) {
          final cacheKey = 'content_${content.id}';
          // Convert to ContentModel and then to JSON Map (including tags)
          final model = ContentModel.fromEntity(content);
          await contentCacheManager.set(cacheKey, model.toJson());
        }

        _logger.i(
            'Fetched and cached ${entities.length} contents from ${_activeSource.id}');

        return _mapToAppContentListResult(coreResult);
      } catch (e) {
        _logger.w('Failed to fetch from source: $e');
        rethrow;
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to get content list', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<Content> getContentDetail(ContentId contentId,
      {String? sourceId}) async {
    final requestKey = 'content_detail_${contentId.value}';

    return requestDeduplicationService.deduplicate(
      requestKey,
      () async {
        try {
          _logger.i('Getting content detail for ID: ${contentId.value}');

          final cacheKey = 'content_${contentId.value}';
          final multiLayerCached = await contentCacheManager.get(cacheKey);

          if (multiLayerCached != null) {
            try {
              final cachedModel = ContentModel.fromJson(multiLayerCached);
              if (cachedModel.imageUrls.isNotEmpty &&
                  !_shouldBypassDetailCache(
                    cachedModel.toEntity(),
                    requestedSourceId: sourceId,
                  )) {
                return cachedModel.toEntity();
              }
              _logger.i(
                'Bypassing multi-layer detail cache for ${contentId.value} '
                '(source=${cachedModel.sourceId}) to refresh expiring image URLs',
              );
            } catch (e) {
              _logger.w('Failed to parse cached content for $contentId: $e');
              // Proceed to fallback
            }
          }

          final legacyCached =
              await detailCacheService.getCachedDetail(contentId.value);
          if (legacyCached != null) {
            if (legacyCached.imageUrls.isNotEmpty &&
                !_shouldBypassDetailCache(
                  legacyCached,
                  requestedSourceId: sourceId,
                )) {
              await contentCacheManager.set(
                  cacheKey, ContentModel.fromEntity(legacyCached).toJson());
              return legacyCached;
            }
            _logger.i(
              'Bypassing legacy detail cache for ${contentId.value} '
              '(source=${legacyCached.sourceId}) to refresh expiring image URLs',
            );
          }

          _logger.d('Cache MISS for content detail: ${contentId.value}');
          try {
            final source = sourceId != null
                ? contentSourceRegistry.getSource(sourceId)
                : _activeSource;

            if (source == null) {
              throw Exception('Source not found for ID: $sourceId');
            }

            final coreContent = await source.getDetail(contentId.value);
            final entity = _mapToAppContent(coreContent);

            await Future.wait([
              contentCacheManager.set(
                  cacheKey, ContentModel.fromEntity(entity).toJson()),
              detailCacheService.cacheDetail(entity),
            ]);

            return entity;
          } catch (e) {
            if (e is core.LoginRequiredException) {
              rethrow;
            }
            _logger.w('Failed to fetch detail from source: $e');
            throw NetworkException('Failed to fetch content detail: $e');
          }
        } catch (e, stackTrace) {
          _logger.e('Failed to get content detail',
              error: e, stackTrace: stackTrace);
          rethrow;
        }
      },
    );
  }

  @override
  Future<ContentListResult> searchContent(SearchFilter filter) async {
    try {
      _logger.i('Searching content with filter: ${filter.query}');
      try {
        final coreFilter = _mapToCoreSearchFilter(filter);
        final coreResult = await _activeSource.search(coreFilter);

        return _mapToAppContentListResult(coreResult);
      } catch (e) {
        _logger.w('Search failed: $e');
        rethrow;
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to search content', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<ContentListResult> getPopularContent({
    PopularTimeframe timeframe = PopularTimeframe.allTime,
    int page = 1,
  }) async {
    try {
      core.PopularTimeframe coreTimeframe = core.PopularTimeframe.allTime;
      if (timeframe == PopularTimeframe.today) {
        coreTimeframe = core.PopularTimeframe.today;
      }
      if (timeframe == PopularTimeframe.week) {
        coreTimeframe = core.PopularTimeframe.week;
      }

      final coreResult = await _activeSource.getPopular(
        timeframe: coreTimeframe,
        page: page,
      );

      return _mapToAppContentListResult(coreResult);
    } catch (e) {
      _logger.w('Failed to fetch popular content from source: $e');
      rethrow;
    }
  }

  @override
  Future<ContentListResult> getContentByTag({
    required Tag tag,
    int page = 1,
    SortOption sortBy = SortOption.newest,
  }) async {
    try {
      _logger.i('Getting content by tag: ${tag.name}, page: $page');

      // Map tag type to the appropriate filter category
      final List<FilterItem> tags = [];
      final List<FilterItem> artists = [];
      final List<FilterItem> characters = [];
      final List<FilterItem> parodies = [];
      final List<FilterItem> groups = [];

      final filterItem = FilterItem.include(tag.name);

      // We pass the raw slug as well using a special prefix so the scraper knows the exact type if it needs it.
      // E.g. 'artist:', 'magazine:'
      final mappedItem =
          FilterItem.include('${tag.type}:${tag.slug ?? tag.name}');

      switch (tag.type) {
        case TagType.artist:
        case 'author':
          artists.add(mappedItem);
          break;
        case TagType.character:
          characters.add(mappedItem);
          break;
        case TagType.parody:
          parodies.add(mappedItem);
          break;
        case TagType.group:
          groups.add(mappedItem);
          break;
        case 'magazine':
          // Put magazine in tags but with a prefix
          tags.add(mappedItem);
          break;
        default:
          tags.add(filterItem);
      }

      final filter = SearchFilter(
        tags: tags,
        artists: artists,
        characters: characters,
        parodies: parodies,
        groups: groups,
        page: page,
        sortBy: sortBy,
      );

      return await searchContent(filter);
    } catch (e, stackTrace) {
      _logger.e('Failed to get content by tag',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<Content>> getRelatedContent({
    required ContentId contentId,
    int limit = 10,
    String? sourceId,
  }) async {
    try {
      _logger.i(
          'Getting related content for: ${contentId.value} (source: $sourceId)');
      // Route to the owning source when known — ids are meaningless on any
      // other source. Falls back to the active source for legacy callers.
      final source = sourceId != null
          ? contentSourceRegistry.getSource(sourceId)
          : null;
      final target = source ?? _activeSource;
      try {
        final coreRelated = await target.getRelated(contentId.value);
        if (coreRelated.isNotEmpty) {
          return coreRelated.take(limit).map(_mapToAppContent).toList();
        }
      } catch (e) {
        _logger.w('Related content failed: $e');
      }
      return [];
    } catch (e, stackTrace) {
      _logger.e('Failed to get related content',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<List<Content>> getRandomGalleries({
    String? sourceId,
    int count = 1,
  }) async {
    try {
      _logger
          .i('Getting random galleries (sourceId: $sourceId, count: $count)');
      final source = sourceId != null
          ? contentSourceRegistry.getSource(sourceId)
          : _activeSource;

      if (source == null) {
        _logger.w('Source not found: $sourceId');
        return [];
      }

      final coreRandom = await source.getRandom(count: count);
      return coreRandom.map(_mapToAppContent).toList();
    } catch (e, stackTrace) {
      _logger.e('Failed to get random galleries',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<List<Tag>> getAllTags({
    String? type,
    TagSortOption sortBy = TagSortOption.count,
  }) async {
    try {
      // Generate cache key based on type and sort
      final cacheKey = 'tags_${type ?? 'all'}_${sortBy.name}';

      // Try cache first
      final cached = await tagCacheManager.get(cacheKey);
      if (cached != null) {
        _logger.i('Cache HIT for tags: $cacheKey (${cached.length} tags)');
        return cached;
      }

      // Cache MISS - fetch from remote
      _logger.d('Cache MISS for tags: $cacheKey');
      List<TagModel> remoteTags;
      if (type != null) {
        remoteTags = await remoteDataSource.getTagsByType(type);
      } else {
        remoteTags = await remoteDataSource.getAllTags();
      }

      final entities = remoteTags.map((model) => model.toEntity()).toList();
      _sortTags(entities, sortBy);

      // Cache the sorted result
      await tagCacheManager.set(cacheKey, entities);

      _logger.i('Fetched and cached ${entities.length} tags from remote');
      return entities;
    } catch (e) {
      _logger.w('Failed to fetch tags from remote: $e');
      rethrow;
    }
  }

  @override
  Future<bool> verifyContentExists(ContentId contentId) async {
    try {
      await remoteDataSource.getContentDetailViaApi(contentId.value);
      return true;
    } catch (e) {
      _logger.d('Content verification failed: $e');
      return false;
    }
  }

  @override
  Future<ChapterData> getChapterImages(ContentId chapterId,
      {String? sourceId}) async {
    try {
      _logger.d(
          'Getting chapter images for: ${chapterId.value}, source: $sourceId');
      final source = sourceId != null
          ? contentSourceRegistry.getSource(sourceId)
          : _activeSource;

      if (source == null) {
        throw Exception('Source not found for ID: $sourceId');
      }

      // Call getChapterImages on whatever source implements it (works for
      // GenericHttpSource, KomiktapSource, CrotpediaSource, or any future source).
      final result = await source.getChapterImages(chapterId.value);
      if (result != null) return result;

      _logger.w('Source ${source.displayName} does not support chapter images');
      return const ChapterData(images: []);
    } catch (e) {
      _logger.e('Failed to get chapter images: $e');
      return const ChapterData(images: []);
    }
  }

  @override
  Future<List<Chapter>> getContentChapters(
    ContentId contentId, {
    String? sourceId,
    String? language,
    String? scanGroup,
    int? page,
    int? offset,
    int? limit,
  }) async {
    final source = sourceId != null
        ? contentSourceRegistry.getSource(sourceId)
        : _activeSource;
    if (source == null) {
      return const [];
    }

    return source.getChapters(
      contentId.value,
      language: language,
      scanGroup: scanGroup,
      page: page,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<Comment>> getComments(String contentId) async {
    try {
      _logger.i('Getting comments for: $contentId');
      return await _activeSource.getComments(contentId);
    } catch (e, stackTrace) {
      _logger.e('Failed to get comments', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Sort tags based on sort option
  void _sortTags(List<Tag> tags, TagSortOption sortBy) {
    switch (sortBy) {
      case TagSortOption.count:
        tags.sort((a, b) => b.count.compareTo(a.count));
        break;
      case TagSortOption.name:
        tags.sort((a, b) => a.name.compareTo(b.name));
        break;
      case TagSortOption.recent:
        tags.sort((a, b) => b.count.compareTo(a.count));
        break;
    }
  }

  // --- Mappers ---

  ContentListResult _mapToAppContentListResult(
      core.ContentListResult coreResult) {
    return ContentListResult(
      contents: coreResult.contents,
      currentPage: coreResult.currentPage,
      totalPages: coreResult.totalPages,
      totalCount: coreResult.totalCount,
      hasNext: coreResult.hasNext,
      hasPrevious: coreResult.hasPrevious,
    );
  }

  // Return core Content directly (no mapping needed since types are unified)
  Content _mapToAppContent(core.Content coreContent) => coreContent;

  bool _shouldBypassDetailCache(
    Content content, {
    String? requestedSourceId,
  }) {
    final source = (requestedSourceId ?? content.sourceId).toLowerCase();
    if (_isInvalidCachedTitle(content.title)) {
      return true;
    }

    if (_isChapterCacheIncomplete(source, content)) {
      return true;
    }

    // Backward-compat cache healing: older nhentai detail cache entries were
    // saved before favorites mapping was fixed, so force refresh when zero.
    if (source == 'nhentai' && content.favorites == 0) {
      return true;
    }

    if (source == 'hentainexus' ||
        source == 'schale-network' ||
        source == 'hdoujin' ||
        source == 'nicomanga') {
      return true;
    }

    if (source == 'hitomi') {
      return true;
    }

    if (content.coverUrl.contains('gold-usergeneratedcontent.net')) {
      return true;
    }

    return content.imageUrls
        .any((url) => url.contains('gold-usergeneratedcontent.net'));
  }

  bool _isInvalidCachedTitle(String title) {
    final normalized = title.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized == 'unknown title';
  }

  bool _isChapterCacheIncomplete(String source, Content content) {
    final hasChapterFeature =
        remoteConfigService.isFeatureEnabled(source, (f) => f.chapters);
    if (!hasChapterFeature) {
      return false;
    }

    if (content.chapters == null) {
      return true;
    }

    // Empty chapter lists for chapter-enabled sources are usually stale/bad cache.
    if (content.chapters!.isEmpty) {
      return true;
    }

    return false;
  }

  core.SearchFilter _mapToCoreSearchFilter(SearchFilter appFilter) {
    // Map SortOption
    core.SortOption coreSort = core.SortOption.newest;
    if (appFilter.sortBy == SortOption.popular) {
      coreSort = core.SortOption.popular;
    }
    if (appFilter.sortBy == SortOption.popularWeek) {
      coreSort = core.SortOption.popularWeek;
    }
    if (appFilter.sortBy == SortOption.popularToday) {
      coreSort = core.SortOption.popularToday;
    }
    if (appFilter.sortBy == SortOption.rating) {
      coreSort = core.SortOption.rating;
    }

    // Convert FilterItems to core.FilterItem
    final includeTags = <core.FilterItem>[];
    final excludeTags = <core.FilterItem>[];

    void process(List<FilterItem> items, String type) {
      for (final item in items) {
        final coreItem = core.FilterItem(
          id: 0, // App doesn't store ID for filter items
          name: item.value,
          type: type,
          isExcluded: item.isExcluded,
        );
        if (item.isExcluded) {
          excludeTags.add(coreItem);
        } else {
          includeTags.add(coreItem);
        }
      }
    }

    process(appFilter.tags, 'tag');
    process(appFilter.artists, 'artist');
    process(appFilter.characters, 'character');
    process(appFilter.parodies, 'parody');
    process(appFilter.groups, 'group');

    // Config-driven genre-route support:
    // Convert `<genrePrefix><slug>` query into includeTags so generic scraper
    // can use `genreSearch` URL pattern from source config.
    var mappedQuery = appFilter.query ?? '';
    final activeSourceId = contentSourceRegistry.currentSource?.id;
    final rawConfig = activeSourceId == null
        ? null
        : remoteConfigService.getRawConfig(activeSourceId);
    final navigation = rawConfig?['navigation'];
    final genrePrefix = navigation is Map<String, dynamic>
        ? (navigation['genreQueryPrefix'] as String? ?? 'genre:')
        : 'genre:';
    final genreTagType = navigation is Map<String, dynamic>
        ? (navigation['genreTagType'] as String? ?? 'genre')
        : 'genre';

    if (mappedQuery.startsWith(genrePrefix)) {
      final rawSlug = mappedQuery.substring(genrePrefix.length).trim();
      final normalizedSlug = rawSlug
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');

      if (normalizedSlug.isNotEmpty) {
        includeTags.add(core.FilterItem(
          id: 0,
          name: normalizedSlug,
          type: genreTagType,
          isExcluded: false,
        ));
        mappedQuery = '';
      }
    } else {
      // `<tagPrefix><slug>` queries (e.g. "tag:sparkle") map to a plain-tag
      // includeTags entry; the scraper routes these via the tagSearch URL
      // pattern when the source has a separate /tag/ taxonomy.
      final tagPrefix = navigation is Map<String, dynamic>
          ? (navigation['tagQueryPrefix'] as String? ?? 'tag:')
          : 'tag:';
      if (tagPrefix.isNotEmpty && mappedQuery.startsWith(tagPrefix)) {
        final rawSlug = mappedQuery.substring(tagPrefix.length).trim();
        final normalizedSlug = rawSlug
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '');

        if (normalizedSlug.isNotEmpty) {
          includeTags.add(core.FilterItem(
            id: 0,
            name: normalizedSlug,
            type: 'tag',
            isExcluded: false,
          ));
          mappedQuery = '';
        }
      }
    }

    return core.SearchFilter(
      query: mappedQuery,
      page: appFilter.page,
      sort: coreSort,
      includeTags: includeTags,
      excludeTags: excludeTags,
      language: appFilter.language,
      category: appFilter.category,
      radioGroupSelections: appFilter.radioGroupSelections,
    );
  }
}
