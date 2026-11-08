import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/data/datasources/remote/tags/tags_remote_data_source.dart';
import 'package:nhasixapp/domain/entities/tags/tag_autocomplete_result.dart';
import 'package:nhasixapp/domain/entities/tags/tag_detail_entity.dart';
import 'package:nhasixapp/domain/entities/tags/tag_entity.dart';
import 'package:nhasixapp/domain/repositories/tag_repository.dart';

// Implementation of TagRepository
class TagRepositoryImpl implements TagRepository {
  final TagsRemoteDataSource _remoteDataSource;
  final TagDataManager _tagDataManager;
  final RemoteConfigService _configService;
  final Logger _logger;

  TagRepositoryImpl({
    required this._remoteDataSource,
    required this._tagDataManager,
    required this._configService,
    required this._logger,
  });

  @override
  Future<List<TagEntity>> getTagsByType({
    required String tagType,
    required String sourceId,
    int page = 1,
    int perPage = 30,
  }) async {
    try {
      final models = await _remoteDataSource.getTagsByType(
        tagType: tagType,
        sourceId: sourceId,
        page: page,
        perPage: perPage,
      );
      return models.map((model) => model.toEntity()).toList();
    } catch (e, stackTrace) {
      _logger.e('Error in getTagsByType', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  Future<TagAutocompleteResult> getAutocomplete({
    required String query,
    required String sourceId,
    String? tagType,
    int limit = 10,
  }) async {
    // Use local tag data when available (spyfakku etc.),
    // fall back to remote API (nhentai).
    if (_tagDataManager.hasTags(sourceId)) {
      return _searchLocalTags(query, tagType, sourceId, limit);
    }

    // try loading tags from source config's tagSource block
    final rawConfig = _configService.getRawConfig(sourceId);
    final tagSource = rawConfig?['tagSource'] as Map<String, dynamic>?;
    if (tagSource != null) {
      await _loadTagsFromConfig(sourceId, tagSource);
      if (_tagDataManager.hasTags(sourceId)) {
        return _searchLocalTags(query, tagType, sourceId, limit);
      }
    }

    try {
      final model = await _remoteDataSource.getAutocomplete(
        query: query,
        sourceId: sourceId,
        tagType: tagType,
        limit: limit,
      );
      return model.toEntity();
    } catch (e, stackTrace) {
      _logger.e('Error in getAutocomplete', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<TagAutocompleteResult> _searchLocalTags(
    String query,
    String? tagType,
    String sourceId,
    int limit,
  ) async {
    final tags = await _tagDataManager.searchTags(
      query,
      type: tagType,
      source: sourceId,
      limit: limit,
    );
    return TagAutocompleteResult(
      suggestions: tags
          .map((t) => TagEntity(
                id: t.id,
                name: t.name,
                slug: t.slug ?? '',
                type: t.type,
                count: t.count,
                url: t.url,
              ))
          .toList(),
      query: query,
      totalResults: tags.length,
    );
  }

  Future<void> _loadTagsFromConfig(
    String sourceId,
    Map<String, dynamic> tagSource,
  ) async {
    final url = tagSource['url'] as String?;
    if (url == null || url.isEmpty) return;
    try {
      await _tagDataManager.loadAndCacheTagsFromUrl(url, sourceId);
    } catch (e) {
      _logger.e('Failed to load tags from tagSource config for $sourceId',
          error: e);
    }
  }

  @override
  Future<TagDetailEntity> getTagDetail({
    required String tagType,
    required String slug,
    required String sourceId,
  }) async {
    try {
      final model = await _remoteDataSource.getTagDetail(
        tagType: tagType,
        slug: slug,
        sourceId: sourceId,
      );
      return model.toEntity();
    } catch (e, stackTrace) {
      _logger.e('Error in getTagDetail', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
