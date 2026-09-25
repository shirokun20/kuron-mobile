part of 'download_bloc.dart';

// ============================================================
// EHentai Constants
// ============================================================

const String _ehentaiSourceId = 'ehentai';
const String _ehentaiPartPrefix = '__ehpart__';
const String _ehentaiChunkPrefix = '__ehchunk__';

// ============================================================
// EHentai Helpers
// ============================================================

bool _isEhentaiSource(String? sourceId) {
  if (sourceId == null || sourceId.isEmpty) return false;
  return sourceId.toLowerCase() == _ehentaiSourceId;
}

bool _hasPaginationConfig(String? sourceId) {
  if (sourceId == null || sourceId.isEmpty) return false;
  final rawConfig = getIt<RemoteConfigService>().getRawConfig(sourceId);
  if (rawConfig == null) return false;
  final scraper = rawConfig['scraper'];
  if (scraper is! Map<String, dynamic>) return false;
  final selectors = scraper['selectors'];
  if (selectors is! Map<String, dynamic>) return false;
  final reader = selectors['reader'];
  if (reader is! Map<String, dynamic>) return false;
  return reader.containsKey('pagination') && reader['pagination'] != null;
}

bool _isEhentaiChunkId(String chapterId) {
  return chapterId.startsWith(_ehentaiChunkPrefix);
}

bool _isEhentaiPartId(String chapterId) {
  return chapterId.startsWith(_ehentaiPartPrefix);
}

bool _isEhentaiVirtualChapterId(String chapterId) {
  return _isEhentaiPartId(chapterId) || _isEhentaiChunkId(chapterId);
}

// ============================================================
// Config Helpers
// ============================================================

String? _extractEndpointPath(dynamic endpoint) {
  if (endpoint is String && endpoint.isNotEmpty) return endpoint;
  if (endpoint is Map) {
    final pathValue = endpoint['path'];
    if (pathValue is String && pathValue.isNotEmpty) return pathValue;
    final urlValue = endpoint['url'];
    if (urlValue is String && urlValue.isNotEmpty) return urlValue;
  }
  return null;
}

// ============================================================
// Error Type Helper
// ============================================================

DownloadErrorType _determineErrorType(dynamic error) {
  final errorString = error.toString().toLowerCase();

  if (errorString.contains('network') ||
      errorString.contains('connection') ||
      errorString.contains('timeout')) {
    return DownloadErrorType.network;
  } else if (errorString.contains('storage') ||
      errorString.contains('space') ||
      errorString.contains('disk')) {
    return DownloadErrorType.storage;
  } else if (errorString.contains('permission') ||
      errorString.contains('denied')) {
    return DownloadErrorType.permission;
  } else if (errorString.contains('server') || errorString.contains('5')) {
    return DownloadErrorType.server;
  } else if (errorString.contains('parse') || errorString.contains('format')) {
    return DownloadErrorType.parsing;
  } else if (errorString.contains('timeout')) {
    return DownloadErrorType.timeout;
  } else if (errorString.contains('cancel')) {
    return DownloadErrorType.cancelled;
  } else {
    return DownloadErrorType.unknown;
  }
}

// ============================================================
// Image Counting Helper
// ============================================================

Future<int> _countDownloadedImages({
  required String contentId,
  required String? sourceId,
  String? downloadPath,
}) async {
  bool isImageFile(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.avif') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  Future<int> countFromBasePath(String basePath) async {
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) return 0;

    final imagesDir =
        Directory(path.join(baseDir.path, AppStorage.imagesSubfolder));
    final targetDir = await imagesDir.exists() ? imagesDir : baseDir;

    final entities = await targetDir.list().toList();
    return entities.whereType<File>().where((f) => isImageFile(f.path)).length;
  }

  if (downloadPath != null && downloadPath.isNotEmpty) {
    final directCount = await countFromBasePath(downloadPath);
    if (directCount > 0) return directCount;
  }

  try {
    final resolvedPaths = await DownloadStorageUtils.getDownloadedImagePaths(
      contentId,
      sourceId: sourceId,
    );
    return resolvedPaths.length;
  } catch (e) {
    return 0;
  }
}
