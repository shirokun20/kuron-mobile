typedef DetailTagQueryResult = ({String query, bool explicitMappingFailed});

typedef LoadedTagIdResolver = String? Function(
  String tagName,
  List<String> candidateTypes,
);

class DetailTagQueryResolver {
  const DetailTagQueryResolver();

  DetailTagQueryResult resolve({
    required String sourceId,
    required String tagName,
    String? tagId,
    String? tagType,
    Map<String, dynamic>? rawConfig,
    LoadedTagIdResolver? resolveTagIdFromLoadedContent,
  }) {
    final actualSourceId = sourceId.trim().toLowerCase();
    final normalizedTagName = tagName.trim();
    var query = normalizedTagName;

    final navigation = _asMap(rawConfig?['navigation']);
    final tagQueryMapping = _asMap(navigation['tagQueryMapping']);

    var hasExplicitTagMapping = false;

    final mappedQuery = _resolveByTagMapping(
      sourceId: actualSourceId,
      tagName: normalizedTagName,
      tagId: tagId,
      tagType: tagType,
      tagQueryMapping: tagQueryMapping,
      resolveTagIdFromLoadedContent: resolveTagIdFromLoadedContent,
      onExplicitMappingDetected: () {
        hasExplicitTagMapping = true;
      },
    );

    if (hasExplicitTagMapping && (mappedQuery == null || mappedQuery.isEmpty)) {
      return (query: '', explicitMappingFailed: true);
    }

    if (mappedQuery != null && mappedQuery.isNotEmpty) {
      query = mappedQuery;
    } else if (actualSourceId == 'ehentai') {
      final ehentaiQuery = _buildEhentaiTagQuery(
        tagName: normalizedTagName,
        tagId: tagId,
        tagType: tagType,
      );
      if (ehentaiQuery != null && ehentaiQuery.isNotEmpty) {
        query = ehentaiQuery;
      }
    } else if (actualSourceId == 'nhentai') {
      query = _buildNhentaiTagQuery(
        tagName: normalizedTagName,
        tagId: tagId,
        tagType: tagType,
      );
    } else {
      final genreQuery = _buildGenreQuery(
        navigation: navigation,
        rawConfig: rawConfig,
        tagName: normalizedTagName,
        tagId: tagId,
        tagType: tagType,
      );
      if (genreQuery != null && genreQuery.isNotEmpty) {
        query = genreQuery;
      }
    }

    return (query: query, explicitMappingFailed: false);
  }

  String? _resolveByTagMapping({
    required String sourceId,
    required String tagName,
    required String? tagId,
    required String? tagType,
    required Map<String, dynamic> tagQueryMapping,
    required LoadedTagIdResolver? resolveTagIdFromLoadedContent,
    required void Function() onExplicitMappingDetected,
  }) {
    if (tagQueryMapping.isEmpty) {
      return null;
    }

    final normalizedType = (tagType ?? '').toLowerCase().trim();

    var mapping = _asMap(tagQueryMapping[normalizedType]);
    if (mapping.isEmpty) {
      mapping = _asMap(tagQueryMapping['default']);
    }
    if (mapping.isEmpty) {
      return null;
    }

    onExplicitMappingDetected();

    final mode = (mapping['mode'] as String? ?? 'rawParam').trim();
    if (mode == 'name') {
      // Return type-prefixed query for adapter routing
      return '$normalizedType:$tagName';
    }

    final valueSource =
        (mapping['valueSource'] as String? ?? 'tagIdOrName').trim();
    final sameAsTypes =
        (mapping['sameAsTypes'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString().toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final candidateTypes = <String>[normalizedType, ...sameAsTypes]
        .where((e) => e.isNotEmpty)
        .toList();

    var resolvedTagId = tagId?.trim();
    if ((resolvedTagId == null ||
            resolvedTagId.isEmpty ||
            resolvedTagId == '0') &&
        resolveTagIdFromLoadedContent != null) {
      resolvedTagId = resolveTagIdFromLoadedContent(tagName, candidateTypes);
    }

    String value;
    if (valueSource == 'tagName') {
      value = tagName.trim();
    } else if (valueSource == 'tagId') {
      value = (resolvedTagId ?? '').trim();
      // FALLBACK for old corrupted tags (like "Beauty Mark\n4K") that have no ID saved
      if (value.isEmpty && tagName.isNotEmpty) {
        final cleanName = tagName.split('\n').first.trim().toLowerCase();
        value = cleanName
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
      }
    } else {
      value = (resolvedTagId != null && resolvedTagId.isNotEmpty)
          ? resolvedTagId
          : tagName.trim();
    }

    if (value.isEmpty) {
      return '';
    }

    final param = (mapping['param'] as String? ?? '').trim();
    final requiredPattern =
        (mapping['requiredPattern'] as String? ?? '').trim();

    if (requiredPattern.isNotEmpty) {
      final regex = RegExp(requiredPattern);
      if (!regex.hasMatch(value)) {
        return '';
      }
    }

    final transform = (mapping['transform'] as String? ?? '').trim();
    if (transform == 'lowercase') {
      value = value.toLowerCase();
    } else if (transform == 'spaceToPlus') {
      value = value.replaceAll(' ', '+');
    }

    final valuePrefix = (mapping['valuePrefix'] as String? ?? '').trim();
    if (valuePrefix.isNotEmpty) {
      value = '$valuePrefix$value';
    }

    final valueSuffix = (mapping['valueSuffix'] as String? ?? '').trim();
    if (valueSuffix.isNotEmpty) {
      value = '$value$valueSuffix';
    }

    if (sourceId == 'hentainexus' && param == 'q') {
      try {
        value = Uri.decodeComponent(value).replaceAll('+', ' ');
      } catch (_) {
        value = value.replaceAll('+', ' ');
      }
    }

    if (param.isEmpty) {
      return null;
    }

    return 'raw:$param=$value';
  }

  String _buildNhentaiTagQuery({
    required String tagName,
    String? tagId,
    String? tagType,
  }) {
    final numericTagId = (tagId ?? '').trim();
    if (numericTagId.isNotEmpty && int.tryParse(numericTagId) != null) {
      return 'raw:tag_id=$numericTagId';
    }

    var value = tagName.toLowerCase().replaceAll(' ', '-');
    if (tagId != null && int.tryParse(tagId) == null) {
      value = tagId;
    }

    final normalizedType = tagType?.toLowerCase();
    if (normalizedType != null &&
        !const {'tag', 'category'}.contains(normalizedType)) {
      return '$normalizedType:$value';
    }

    return value;
  }

  String? _buildGenreQuery({
    required Map<String, dynamic> navigation,
    required Map<String, dynamic>? rawConfig,
    required String tagName,
    required String? tagId,
    required String? tagType,
  }) {
    final scraper = _asMap(rawConfig?['scraper']);
    final urlPatterns = _asMap(scraper['urlPatterns']);

    final normalizedTagType = (tagType ?? '').toLowerCase().trim();

    // Typed taxonomy taps go straight to their own archive route —
    // never through genreSearch. Without this, hentai4free `tag`,
    // `author`, `artist` taps all landed on /hentai-genre/ because the
    // config has no `navigation` block and the genre fallback claimed
    // every genre-like type.
    const directRoutes = {
      'tag': 'tagSearch',
      'author': 'authorSearch',
      'artist': 'artistSearch',
    };
    final directPattern = directRoutes[normalizedTagType];
    if (directPattern != null && urlPatterns.containsKey(directPattern)) {
      var slug = tagName.toLowerCase().trim();
      if (tagId != null && int.tryParse(tagId) == null) {
        slug = tagId.toLowerCase().trim();
      }
      slug = slug
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      return '$normalizedTagType:$slug';
    }

    final hasGenreSearch = urlPatterns.containsKey('genreSearch');

    final genrePrefix =
        (navigation['genreQueryPrefix'] as String? ?? 'genre:').trim();
    final tagPrefix = (navigation['tagQueryPrefix'] as String? ?? '').trim();
    final genreTagType =
        (navigation['genreTagType'] as String? ?? 'genre').trim().toLowerCase();

    final isGenreLikeTag = normalizedTagType.isEmpty ||
        normalizedTagType == 'tag' ||
        normalizedTagType == genreTagType;

    if (!hasGenreSearch || !isGenreLikeTag) {
      return null;
    }

    var slug = tagName.toLowerCase().trim();
    if (tagId != null && int.tryParse(tagId) == null) {
      slug = tagId.toLowerCase().trim();
    }

    slug = slug
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    final actualPrefix = (tagPrefix.isNotEmpty &&
            normalizedTagType.isNotEmpty &&
            normalizedTagType != genreTagType)
        ? tagPrefix
        : genrePrefix;

    return '$actualPrefix$slug';
  }

  String _quoteEhentaiSearchValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (!trimmed.contains(' ') && !trimmed.contains('"')) {
      return trimmed;
    }

    final escaped = trimmed.replaceAll('"', r'\"');
    return '"$escaped"';
  }

  String? _buildEhentaiTagQuery({
    required String tagName,
    String? tagId,
    String? tagType,
  }) {
    final normalizedType = (tagType ?? '').toLowerCase().trim();
    final slug = (tagId ?? '').trim();
    final name = tagName.trim();

    if (normalizedType == 'uploader' && name.isNotEmpty) {
      return 'raw:f_search=uploader:${_quoteEhentaiSearchValue(name)}';
    }

    if (slug.contains(':')) {
      final separatorIndex = slug.indexOf(':');
      final namespace = slug.substring(0, separatorIndex).trim();
      final value = slug.substring(separatorIndex + 1).trim();
      if (namespace.isNotEmpty && value.isNotEmpty) {
        return 'raw:f_search=$namespace:${_quoteEhentaiSearchValue(value)}';
      }
    }

    if (normalizedType.isNotEmpty &&
        !const {'tag', 'category'}.contains(normalizedType) &&
        name.isNotEmpty) {
      return 'raw:f_search=$normalizedType:${_quoteEhentaiSearchValue(name)}';
    }

    return null;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), entry));
    }
    return <String, dynamic>{};
  }
}
