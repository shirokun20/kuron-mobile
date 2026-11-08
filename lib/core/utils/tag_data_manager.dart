import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Comprehensive tag data manager for assets integration
// Provides advanced tag management with caching, validation, and Matrix Filter Support
// Comprehensive tag data manager for remote-first architecture
class TagDataManager {
  TagDataManager({required this._dio, required this._logger});

  final Dio _dio;
  final Logger _logger;

  static const String _tagsVersionKey = 'tags_version';

  // In-memory cache
  List<Tag>? _cachedTags;
  Map<TagType, List<Tag>>? _tagsByType;
  final Map<String, List<Tag>> _cachedTagsBySource = {};
  final Map<String, DateTime> _lastCacheUpdateBySource = {};

  // Matrix Filter Support validation rules
  static const Map<TagType, bool> _multipleSelectSupport = {
    TagType.tag: true,
    TagType.artist: true,
    TagType.character: true,
    TagType.parody: true,
    TagType.group: true,
    TagType.language: false,
    TagType.category: false,
    TagType.genre: true,
  };

  // Initialize tag data from local storage or assets
  Future<void> initialize({required String source}) async {
    try {
      _logger.i('TagDataManager: Initializing tags for $source');
      bool loaded = false;

      // 1. Try loading from downloaded file in Documents
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/tags_$source.json');
        if (await file.exists()) {
          final jsonString = await file.readAsString();
          loaded = await _parseAndCacheTags(
            jsonString,
            source: 'local storage',
            tagSource: source,
          );
        }
      } catch (e) {
        _logger.w(
          'TagDataManager: Failed to load tags from storage for $source',
          error: e,
        );
      }

      // 2. Fallback to assets if storage failed or not found (Only if assets exist)
      if (!loaded) {
        // Note: For remote-first, assets might be deleted. This handles graceful fail.
        await _loadFromAssets(source);
      }

      // 3. Fallback to tagSource block in source config (e.g. spyfakku)
      if (!loaded) {
        final rawConfig = getIt<RemoteConfigService>().getRawConfig(source);
        final tagSource = rawConfig?['tagSource'] as Map<String, dynamic>?;
        final url = tagSource?['url'] as String?;
        if (url != null && url.isNotEmpty) {
          try {
            await loadAndCacheTagsFromUrl(url, source);
            loaded = hasTags(source);
          } catch (e) {
            _logger.w(
                'TagDataManager: Failed to load tags from config for $source',
                error: e);
          }
        }
      }
    } catch (e) {
      _logger.e('TagDataManager: Initialization failed for $source', error: e);
    }
  }

  // Check for updates and download if necessary
  Future<void> checkForUpdates({required String source}) async {
    try {
      final manifest = getIt<RemoteConfigService>().tagsManifest;
      final sourceConfig = manifest?.sources[source];
      if (sourceConfig == null) return;

      final migration = sourceConfig.migration;
      if (migration == null || !migration.enabled) return;

      final remoteVersion = manifest?.version ?? '0';
      final prefs = await SharedPreferences.getInstance();
      final versionKey = '${_tagsVersionKey}_$source';
      final localVersion = prefs.getString(versionKey) ?? '0';

      final hasData = hasTags(source);

      if ((remoteVersion != localVersion || !hasData) &&
          migration.remoteUrl != null) {
        _logger.i(
          'TagDataManager: Tag update required for $source (v$remoteVersion != v$localVersion, hasData: $hasData). Downloading...',
        );
        await downloadTags(
          '${migration.remoteUrl}',
          remoteVersion,
          source,
          fallbackUrl: migration.fallbackUrl,
        );
      } else {
        _logger.d(
            'TagDataManager: Tags for $source are up to date (v$localVersion)');
      }
    } catch (e) {
      _logger.e('TagDataManager: Failed to check updates for $source',
          error: e);
    }
  }

  // Download and cache tags
  Future<bool> downloadTags(
    String url,
    String version,
    String source, {
    String? fallbackUrl,
  }) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final filePath = '${docDir.path}/tags_$source.json';
      final candidateUrls = <String>[url];
      if (fallbackUrl != null && fallbackUrl.isNotEmpty && fallbackUrl != url) {
        candidateUrls.add(fallbackUrl);
      }

      DioException? lastDioError;
      bool downloaded = false;

      for (final candidateUrl in candidateUrls) {
        try {
          _logger.i(
            'TagDataManager: Downloading tags from $candidateUrl for $source...',
          );
          await _dio.download(candidateUrl, filePath);
          downloaded = true;
          break;
        } on DioException catch (e) {
          lastDioError = e;
          _logger.w(
            'TagDataManager: Failed downloading tags from $candidateUrl for $source',
            error: e,
          );
        }
      }

      if (!downloaded) {
        throw lastDioError ??
            Exception('Failed to download tags from all candidate URLs');
      }

      // Verify the downloaded file is valid JSON before updating prefs
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // Try parsing to verify integrity
      final isValid = await _parseAndCacheTags(
        jsonString,
        source: 'downloaded file',
        tagSource: source,
      );

      if (isValid) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${_tagsVersionKey}_$source', version);
        _logger.i(
          'TagDataManager: Successfully updated tags to version $version for $source',
        );
        return true;
      } else {
        _logger.w(
          'TagDataManager: Downloaded tags file is invalid. Reverting...',
        );
        if (file.existsSync()) await file.delete();
        // Try invalidating cache or reloading assets?
        // _loadFromAssets(source);
        return false;
      }
    } catch (e) {
      _logger.e(
        'TagDataManager: Failed to download tags for $source',
        error: e,
      );
      return false;
    }
  }

  // Load tags directly from a remote JSON URL without caching or version sync.
  ///
  // This is used by source configs that declare their tag list inline and do
  // not rely on the legacy tags manifest.
  Future<List<Tag>> loadTagsFromUrl(String url) async {
    final response = await _dio.get<dynamic>(url);
    dynamic payload = response.data;
    if (payload is String) {
      payload = jsonDecode(payload);
    }

    return _parseTagsPayload(payload);
  }

  // Load tags from a remote URL and cache them per [source].
  ///
  // Unlike [loadTagsFromUrl] this persists the result so that [hasTags] and
  // [searchTags] with a source argument work afterwards.
  Future<List<Tag>> loadAndCacheTagsFromUrl(String url, String source) async {
    final tags = await loadTagsFromUrl(url);
    if (tags.isNotEmpty) {
      _cachedTagsBySource[source] = tags;
      _lastCacheUpdateBySource[source] = DateTime.now();
    }
    return tags;
  }

  // Check if tags are loaded for a source
  bool hasTags(String source) =>
      _cachedTagsBySource.containsKey(source) &&
      (_cachedTagsBySource[source]?.isNotEmpty ?? false);

  Future<void> _loadFromAssets(String source) async {
    try {
      // Get asset path from remote config manifest
      final manifest = getIt<RemoteConfigService>().tagsManifest;
      final sourceConfig = manifest?.sources[source];

      if (sourceConfig == null) {
        _logger.d('TagDataManager: No config found for source $source');
        return;
      }

      // Only try to load from assets if type is "bundled" and assetPath is provided
      if (sourceConfig.type != 'bundled' || sourceConfig.assetPath == null) {
        _logger.d(
            'TagDataManager: Source $source is not bundled, skipping asset load');
        return;
      }

      final assetPath = sourceConfig.assetPath!;
      _logger.d('TagDataManager: Loading tags from asset: $assetPath');

      // Try to load from asset
      try {
        final String jsonString = await rootBundle.loadString(assetPath);
        await _parseAndCacheTags(
          jsonString,
          source: 'assets',
          tagSource: source,
        );
        _logger.i(
            'TagDataManager: Successfully loaded tags from asset for $source');
      } catch (e) {
        // Asset doesn't exist - this is OK for remote-first sources
        _logger
            .d('TagDataManager: Asset not found for $source, will use remote');
      }
    } catch (e) {
      _logger.w('TagDataManager: Failed to load asset for $source', error: e);
    }
  }

  Future<bool> _parseAndCacheTags(
    String jsonString, {
    required String source,
    required String tagSource,
  }) async {
    try {
      final dynamic jsonData = jsonDecode(jsonString);
      final List<Tag> tags = _parseTagsPayload(jsonData);

      if (tags.isNotEmpty) {
        _cachedTagsBySource[tagSource] = tags;
        _lastCacheUpdateBySource[tagSource] = DateTime.now();

        // Update the global default tag cache for root sources (no parentSource).
        // Root sources back the `searchTags` / `getTagsByType` calls that don't
        // pass a source parameter. Alias sources rely on their parent's cache.
        final manifest = getIt<RemoteConfigService>().tagsManifest;
        final isRootSource = manifest?.sources[tagSource]?.parentSource == null;
        if (isRootSource) {
          _cachedTags = tags;
          _buildTypeCache();
        }

        _logger.i(
          'TagDataManager: Loaded ${tags.length} tags from $source for $tagSource',
        );
        return true;
      }
    } catch (e) {
      _logger.e('TagDataManager: Parsing failed for $tagSource', error: e);
    }
    return false;
  }

  List<Tag> _parseTagsPayload(dynamic jsonData) {
    final tags = <Tag>[];

    // Unified parsing logic: Expect List of Arrays [id, name, slug, typeCode, count]
    if (jsonData is List) {
      for (final item in jsonData) {
        if (item is List && item.length >= 4) {
          try {
            final id = (item[0] as num?)?.toInt() ?? 0;
            final name = item[1]?.toString() ?? '';
            final slug = item[2]?.toString() ?? '';
            final typeCode = (item[3] as num?)?.toInt() ?? 0;
            // Count might be missing in old formats or some datasets
            final count =
                (item.length > 4) ? ((item[4] as num?)?.toInt() ?? 0) : 0;

            final type = TagType.fromCode(typeCode);

            tags.add(
              Tag(
                id: id,
                name: name,
                type: type
                    .name, // Keeping entity.type as String for compatibility
                count: count,
                url: _generateTagUrl(slug, type),
                slug: slug,
              ),
            );
          } catch (e) {
            // Skip invalid items.
          }
        }
      }
    }

    return tags;
  }

  // Search tags by query with type filtering
  Future<List<Tag>> searchTags(
    String query, {
    String? type,
    String? source,
    int limit = 20,
    bool caseSensitive = false,
  }) async {
    if (query.isEmpty) return [];

    // Use specific source cache if requested, else default
    final List<Tag> sourceTags = (source != null)
        ? (_cachedTagsBySource[source] ?? [])
        : (_cachedTags ?? []);

    if (sourceTags.isEmpty && source != null) {
      // Try initialize if empty?
      // await initialize(source: source);
    }

    final queryToMatch = caseSensitive ? query : query.toLowerCase();
    final results = <Tag>[];

    // Filter by type if provided
    TagType? filterType;
    if (type != null) {
      filterType = _normalizeTagType(type);
    }

    /* Optimization: If filterType provided and we are using default cache, use _tagsByType.
       But if using sourceTags (List), we must iterate. */

    for (final tag in sourceTags) {
      if (filterType != null && tag.type != filterType.name) continue;

      final nameToMatch = caseSensitive ? tag.name : tag.name.toLowerCase();
      if (nameToMatch.contains(queryToMatch)) {
        results.add(tag);
        if (results.length >= limit) break;
      }
    }

    // Sort results... (reuse existing sort logic)
    results.sort((a, b) {
      final aName = caseSensitive ? a.name : a.name.toLowerCase();
      final bName = caseSensitive ? b.name : b.name.toLowerCase();
      if (aName == queryToMatch && bName != queryToMatch) return -1;
      if (bName == queryToMatch && aName != queryToMatch) return 1;
      if (aName.startsWith(queryToMatch) && !bName.startsWith(queryToMatch)) {
        return -1;
      }
      if (bName.startsWith(queryToMatch) && !aName.startsWith(queryToMatch)) {
        return 1;
      }
      return b.count.compareTo(a.count);
    });

    return results;
  }

  // Get tags by type with pagination and search
  // Resolve the effective tag source.
  ///
  // If [source] has no cached tags, checks the tags-config manifest for a
  // `parentSource` declaration. Sources with `parentSource` set (e.g. alias
  // or test variants) inherit tag data from their parent without loading
  // their own dataset.
  String _resolveTagSource(String source) {
    if (_cachedTagsBySource[source]?.isNotEmpty == true) return source;
    final manifest = getIt<RemoteConfigService>().tagsManifest;
    final parentSource = manifest?.sources[source]?.parentSource;
    if (parentSource != null &&
        _cachedTagsBySource[parentSource]?.isNotEmpty == true) {
      _logger.d(
          'TagDataManager: "$source" is alias for "$parentSource" (via config), using parent tags');
      return parentSource;
    }
    return source;
  }

  Future<List<Tag>> getTagsByType(
    String type, {
    int offset = 0,
    int limit = 100,
    String? searchQuery,
    String? source,
  }) async {
    // Determine list to search
    List<Tag> tags;
    if (source != null) {
      // Resolve to base source if this source has no cached tags
      final effectiveSource = _resolveTagSource(source);
      tags = _cachedTagsBySource[effectiveSource] ?? [];
    } else {
      // use mapped cache for default
      final normalizedType = _normalizeTagType(type);
      tags = _tagsByType?[normalizedType] ?? [];
    }

    // Iterate and filter (if using raw list from source)
    if (source != null) {
      final normalizedType = _normalizeTagType(type);
      tags = tags.where((t) => t.type == normalizedType.name).toList();
    }

    // Apply search filter
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final queryLower = searchQuery.toLowerCase();
      tags = tags
          .where((tag) => tag.name.toLowerCase().contains(queryLower))
          .toList();
    }

    return tags.skip(offset).take(limit).toList();
  }

  // Get popular tags with type filtering
  Future<List<Tag>> getPopularTags({
    String? type,
    int limit = 20,
    int minCount = 0,
    String? source,
  }) async {
    List<Tag> tags;

    if (source != null) {
      tags = _cachedTagsBySource[source] ?? [];
      if (type != null) {
        final normalizedType = _normalizeTagType(type);
        tags = tags.where((t) => t.type == normalizedType.name).toList();
      }
    } else {
      tags = type != null
          ? (_tagsByType?[_normalizeTagType(type)] ?? [])
          : (_cachedTags ?? []);
    }

    final popularTags = tags.where((tag) => tag.count >= minCount).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return popularTags.take(limit).toList();
  }

  // Validate Matrix Filter Support rules
  bool validateMatrixFilterSupport(String type, List<String> selectedValues) {
    final normalizedType = _normalizeTagType(type);
    final supportsMultiple = _multipleSelectSupport[normalizedType] ?? true;
    return supportsMultiple || selectedValues.length <= 1;
  }

  // Check if type supports multiple selection
  bool supportsMultipleSelection(String type) {
    final normalizedType = _normalizeTagType(type);
    return _multipleSelectSupport[normalizedType] ?? true;
  }

  // Get all available tag types
  List<String> getAvailableTypes() {
    return _multipleSelectSupport.keys.map((e) => e.name).toList();
  }

  void _buildTypeCache() {
    if (_cachedTags == null) return;
    _tagsByType = <TagType, List<Tag>>{};
    for (final tag in _cachedTags!) {
      final type = _normalizeTagType(tag.type);
      _tagsByType![type] = (_tagsByType![type] ?? [])..add(tag);
    }
    for (final entry in _tagsByType!.entries) {
      entry.value.sort((a, b) => b.count.compareTo(a.count));
    }
  }

  TagType _normalizeTagType(String type) {
    final typeStr = type.toLowerCase().trim();
    switch (typeStr) {
      case 'artist':
      case 'artists':
        return TagType.artist;
      case 'character':
      case 'characters':
        return TagType.character;
      case 'parody':
      case 'parodies':
        return TagType.parody;
      case 'group':
      case 'groups':
        return TagType.group;
      case 'language':
      case 'languages':
        return TagType.language;
      case 'category':
      case 'categories':
        return TagType.category;
      case 'tag':
      case 'tags':
        return TagType.tag;
      case 'genre':
      case 'genres':
        return TagType.genre;
      default:
        // Try matching enum name
        try {
          return TagType.values.firstWhere((e) => e.name == typeStr);
        } catch (_) {
          return TagType.tag;
        }
    }
  }

  String _generateTagUrl(String slug, TagType type) {
    if (slug.isEmpty) return '/';
    switch (type) {
      case TagType.artist:
        return '/artist/$slug/';
      case TagType.character:
        return '/character/$slug/';
      case TagType.parody:
        return '/parody/$slug/';
      case TagType.group:
        return '/group/$slug/';
      case TagType.language:
        return '/language/$slug/';
      case TagType.category:
        return '/category/$slug/';
      case TagType.genre:
        return '/genre/$slug/';
      case TagType.tag:
        return '/tag/$slug/';
    }
  }

  // Statistics & Cache management methods (kept simple)
  Future<Map<String, dynamic>> getTagStatistics() async {
    // Implementation ...
    return {};
  }
}

enum TagType {
  category(0),
  artist(1),
  parody(2),
  tag(3),
  character(4),
  group(5),
  language(6),
  genre(8);

  final int code;
  const TagType(this.code);

  static TagType fromCode(int code) {
    return TagType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => TagType.tag,
    );
  }
}
