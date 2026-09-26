// nhentai v2 API shape helpers extracted from
// [GenericRestAdapter] (task 6.1). Pure functions over the v2 payload
// shape (`media_id` + thumbnails/covers/pages); the source identity
// the old code read from an instance field is now an explicit
// `sourceId` parameter. Orchestration stays in the adapter.
library;

String extractNhentaiV2ListTitle(dynamic data, {required String sourceId}) {
  if (!isNhentaiV2Shape(sourceId, data)) return 'Unknown';

  if (data is Map) {
    final english = data['english_title']?.toString().trim() ?? '';
    if (english.isNotEmpty) return english;

    final japanese = data['japanese_title']?.toString().trim() ?? '';
    if (japanese.isNotEmpty) return japanese;
  }

  return 'Unknown';
}

String extractNhentaiV2DetailTitle(dynamic data, {required String sourceId}) {
  if (!isNhentaiV2Shape(sourceId, data)) return 'Unknown';

  final pretty = extractNhentaiV2Field(data, 'pretty', sourceId: sourceId);
  if (pretty != null && pretty.trim().isNotEmpty) {
    return pretty;
  }

  final english = extractNhentaiV2Field(data, 'english', sourceId: sourceId);
  if (english != null && english.trim().isNotEmpty) {
    return english;
  }

  final japanese = extractNhentaiV2Field(data, 'japanese', sourceId: sourceId);
  if (japanese != null && japanese.trim().isNotEmpty) {
    return japanese;
  }

  return 'Unknown';
}

String? extractNhentaiV2Field(dynamic data, String field, {required String sourceId}) {
  if (!isNhentaiV2Shape(sourceId, data) || data is! Map) return null;
  final title = data['title'];
  if (title is Map) {
    final value = title[field]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String? resolveNhentaiV2CoverUrl(dynamic data, {required String sourceId}) {
  if (!isNhentaiV2Shape(sourceId, data) || data is! Map) return null;

  final thumbnail = data['thumbnail'];
  final cover = data['cover'];

  if (thumbnail is String && thumbnail.trim().isNotEmpty) {
    return resolveNhentaiV2AssetUrl(thumbnail, thumbnail: true);
  }

  if (cover is Map) {
    final path = cover['path']?.toString().trim() ?? '';
    if (path.isNotEmpty) {
      return resolveNhentaiV2AssetUrl(path, thumbnail: true);
    }
  }

  if (thumbnail is Map) {
    final path = thumbnail['path']?.toString().trim() ?? '';
    if (path.isNotEmpty) {
      return resolveNhentaiV2AssetUrl(path, thumbnail: true);
    }
  }

  return null;
}

List<String> resolveNhentaiV2ImageUrls(dynamic data, {required String sourceId}) {
  if (!isNhentaiV2Shape(sourceId, data) || data is! Map) return const [];

  final pages = data['pages'];
  if (pages is! List) return const [];

  return pages
      .whereType<Map>()
      .map((page) => page['path']?.toString().trim() ?? '')
      .where((path) => path.isNotEmpty)
      .map((path) => resolveNhentaiV2AssetUrl(path, thumbnail: false))
      .toList();
}

String resolveNhentaiV2AssetUrl(
  String rawPath, {
  required bool thumbnail,
}) {
  if (rawPath.startsWith('https://') || rawPath.startsWith('http://')) {
    return rawPath;
  }

  final normalized = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
  final host = thumbnail ? 'https://t.nhentai.net' : 'https://i.nhentai.net';
  return '$host/$normalized';
}

bool isNhentaiV2Shape(String sourceId, dynamic data) {
  if (sourceId != 'nhentai' || data is! Map) return false;

  return data.containsKey('media_id') &&
      (data.containsKey('thumbnail') ||
          data.containsKey('cover') ||
          data.containsKey('pages') ||
          data.containsKey('english_title'));
}
