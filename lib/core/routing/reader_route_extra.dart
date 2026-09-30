import 'package:kuron_core/kuron_core.dart' show Chapter, ChapterData, Content;
import 'package:nhasixapp/core/models/image_metadata.dart';
import 'package:nhasixapp/core/utils/uri_component_utils.dart';

Map<String, dynamic> buildReaderRouteExtra({
  Content? content,
  List<ImageMetadata>? imageMetadata,
  ChapterData? chapterData,
  Content? parentContent,
  List<Chapter>? allChapters,
  Chapter? currentChapter,
  String? activeChapterLanguage,
}) {
  return <String, dynamic>{
    'content': content,
    'imageMetadata': imageMetadata?.map((item) => item.toJson()).toList(),
    'chapterData': _serializeChapterData(chapterData),
    'parentContent': parentContent,
    'allChapters': allChapters?.map(_serializeChapter).toList(),
    'currentChapter': _serializeChapter(currentChapter),
    'activeChapterLanguage': activeChapterLanguage,
  };
}

Map<String, dynamic>? asReaderRouteExtra(Object? extra) {
  return _asStringKeyedMap(extra);
}

Content? readReaderContent(Object? value) {
  return value is Content ? value : null;
}

List<ImageMetadata>? readReaderImageMetadata(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is List<ImageMetadata>) {
    return value;
  }

  if (value is! List) {
    return null;
  }

  final items = <ImageMetadata>[];
  for (final item in value) {
    if (item is ImageMetadata) {
      items.add(item);
      continue;
    }

    final map = _asStringKeyedMap(item);
    if (map == null) {
      continue;
    }

    try {
      items.add(ImageMetadata.fromJson(map));
    } catch (_) {
      // Ignore malformed payload items and keep parsing the rest.
    }
  }

  return items;
}

ChapterData? readReaderChapterData(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is ChapterData) {
    return value;
  }

  final map = _asStringKeyedMap(value);
  if (map == null) {
    return null;
  }

  final images = _readStringList(map['images']);
  if (images == null) {
    return null;
  }

  return ChapterData(
    images: images,
    videoUrls: _readStringList(map['videoUrls']) ?? const [],
    videoIndex: _readInt(map['videoIndex']),
    videoReferer: _readString(map['videoReferer']),
    prevChapterId: _readIdentifier(map['prevChapterId']),
    nextChapterId: _readIdentifier(map['nextChapterId']),
    prevChapterTitle: _readString(map['prevChapterTitle']),
    nextChapterTitle: _readString(map['nextChapterTitle']),
  );
}

List<Chapter>? readReaderChapters(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is List<Chapter>) {
    return value;
  }

  if (value is! List) {
    return null;
  }

  final chapters = <Chapter>[];
  for (final item in value) {
    final chapter = readReaderChapter(item);
    if (chapter != null) {
      chapters.add(chapter);
    }
  }

  return chapters;
}

Chapter? readReaderChapter(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is Chapter) {
    return value;
  }

  final map = _asStringKeyedMap(value);
  if (map == null) {
    return null;
  }

  final id = _readIdentifier(map['id']);
  final title = _readString(map['title']);
  final url = _readIdentifier(map['url']);

  if (id == null || title == null || url == null) {
    return null;
  }

  return Chapter(
    id: id,
    title: title,
    url: url,
    uploadDate: _readDateTime(map['uploadDate']),
    scanGroup: _readString(map['scanGroup']),
    language: _readString(map['language']),
    externalUrl: _readString(map['externalUrl']),
    pages: _readInt(map['pages']),
    isUnavailable: map['isUnavailable'] == true,
  );
}

String? readReaderActiveChapterLanguage(Object? value) => _readString(value);

Map<String, dynamic>? _serializeChapterData(ChapterData? chapterData) {
  if (chapterData == null) {
    return null;
  }

  return <String, dynamic>{
    'images': chapterData.images,
    'videoUrls': chapterData.videoUrls,
    'videoIndex': chapterData.videoIndex,
    'videoReferer': chapterData.videoReferer,
    'prevChapterId': chapterData.prevChapterId,
    'nextChapterId': chapterData.nextChapterId,
    'prevChapterTitle': chapterData.prevChapterTitle,
    'nextChapterTitle': chapterData.nextChapterTitle,
  };
}

Map<String, dynamic>? _serializeChapter(Chapter? chapter) {
  if (chapter == null) {
    return null;
  }

  return <String, dynamic>{
    'id': chapter.id,
    'title': chapter.title,
    'url': chapter.url,
    'uploadDate': chapter.uploadDate?.toIso8601String(),
    'scanGroup': chapter.scanGroup,
    'language': chapter.language,
    'externalUrl': chapter.externalUrl,
    'pages': chapter.pages,
    'isUnavailable': chapter.isUnavailable,
  };
}

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }

  final mapped = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      mapped[key] = entry.value;
    }
  }

  return mapped;
}

List<String>? _readStringList(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is List<String>) {
    return value;
  }

  if (value is! List) {
    return null;
  }

  return value.whereType<String>().toList();
}

String? _readString(Object? value) {
  return value is String ? value : null;
}

String? _readIdentifier(Object? value) {
  final raw = _readString(value);
  if (raw == null || raw.isEmpty) {
    return raw;
  }
  return UriComponentUtils.safeDecode(raw);
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }

  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }

  return null;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
