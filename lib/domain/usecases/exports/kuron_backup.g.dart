// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kuron_backup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_KuronBackup _$KuronBackupFromJson(Map<String, dynamic> json) => _KuronBackup(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ??
          kuronBackupSupportedVersion,
      favorites: (json['favorites'] as List<dynamic>?)
              ?.map((e) =>
                  KuronBackupFavorite.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KuronBackupFavorite>[],
      collections: (json['collections'] as List<dynamic>?)
              ?.map((e) =>
                  KuronBackupCollection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KuronBackupCollection>[],
      collectionMembers: (json['collectionMembers'] as List<dynamic>?)
              ?.map((e) => KuronBackupCollectionMember.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          const <KuronBackupCollectionMember>[],
      history: (json['history'] as List<dynamic>?)
              ?.map(
                  (e) => KuronBackupHistory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KuronBackupHistory>[],
      positions: (json['positions'] as List<dynamic>?)
              ?.map((e) =>
                  KuronBackupPosition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KuronBackupPosition>[],
      settings: (json['settings'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
      malformedRows: (json['malformedRows'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$KuronBackupToJson(_KuronBackup instance) =>
    <String, dynamic>{
      'formatVersion': instance.formatVersion,
      'favorites': instance.favorites,
      'collections': instance.collections,
      'collectionMembers': instance.collectionMembers,
      'history': instance.history,
      'positions': instance.positions,
      'settings': instance.settings,
      'malformedRows': instance.malformedRows,
    };

_KuronBackupFavorite _$KuronBackupFavoriteFromJson(Map<String, dynamic> json) =>
    _KuronBackupFavorite(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String? ?? 'nhentai',
      title: json['title'] as String?,
      coverUrl: json['coverUrl'] as String?,
      addedAt: json['addedAt'] == null
          ? null
          : DateTime.parse(json['addedAt'] as String),
    );

Map<String, dynamic> _$KuronBackupFavoriteToJson(
        _KuronBackupFavorite instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sourceId': instance.sourceId,
      'title': instance.title,
      'coverUrl': instance.coverUrl,
      'addedAt': instance.addedAt?.toIso8601String(),
    };

_KuronBackupCollection _$KuronBackupCollectionFromJson(
        Map<String, dynamic> json) =>
    _KuronBackupCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$KuronBackupCollectionToJson(
        _KuronBackupCollection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

_KuronBackupCollectionMember _$KuronBackupCollectionMemberFromJson(
        Map<String, dynamic> json) =>
    _KuronBackupCollectionMember(
      collectionId: json['collectionId'] as String,
      favoriteId: json['favoriteId'] as String,
      sourceId: json['sourceId'] as String? ?? 'nhentai',
      addedAt: json['addedAt'] == null
          ? null
          : DateTime.parse(json['addedAt'] as String),
    );

Map<String, dynamic> _$KuronBackupCollectionMemberToJson(
        _KuronBackupCollectionMember instance) =>
    <String, dynamic>{
      'collectionId': instance.collectionId,
      'favoriteId': instance.favoriteId,
      'sourceId': instance.sourceId,
      'addedAt': instance.addedAt?.toIso8601String(),
    };

_KuronBackupHistory _$KuronBackupHistoryFromJson(Map<String, dynamic> json) =>
    _KuronBackupHistory(
      contentId: json['contentId'] as String,
      sourceId: json['sourceId'] as String? ?? 'nhentai',
      lastViewed: json['lastViewed'] == null
          ? null
          : DateTime.parse(json['lastViewed'] as String),
      lastPage: (json['lastPage'] as num?)?.toInt(),
      totalPages: (json['totalPages'] as num?)?.toInt(),
      timeSpentSeconds: (json['timeSpentSeconds'] as num?)?.toInt(),
      isCompleted: json['isCompleted'] as bool?,
      title: json['title'] as String?,
      coverUrl: json['coverUrl'] as String?,
      chapterId: json['chapterId'] as String?,
      chapterIndex: (json['chapterIndex'] as num?)?.toInt(),
      chapterTitle: json['chapterTitle'] as String?,
    );

Map<String, dynamic> _$KuronBackupHistoryToJson(_KuronBackupHistory instance) =>
    <String, dynamic>{
      'contentId': instance.contentId,
      'sourceId': instance.sourceId,
      'lastViewed': instance.lastViewed?.toIso8601String(),
      'lastPage': instance.lastPage,
      'totalPages': instance.totalPages,
      'timeSpentSeconds': instance.timeSpentSeconds,
      'isCompleted': instance.isCompleted,
      'title': instance.title,
      'coverUrl': instance.coverUrl,
      'chapterId': instance.chapterId,
      'chapterIndex': instance.chapterIndex,
      'chapterTitle': instance.chapterTitle,
    };

_KuronBackupPosition _$KuronBackupPositionFromJson(Map<String, dynamic> json) =>
    _KuronBackupPosition(
      contentId: json['contentId'] as String,
      currentPage: (json['currentPage'] as num).toInt(),
      totalPages: (json['totalPages'] as num?)?.toInt(),
      lastAccessed: json['lastAccessed'] == null
          ? null
          : DateTime.parse(json['lastAccessed'] as String),
      readingProgress: (json['readingProgress'] as num?)?.toDouble(),
      readingTimeMinutes: (json['readingTimeMinutes'] as num?)?.toInt(),
      title: json['title'] as String?,
      coverUrl: json['coverUrl'] as String?,
      chapterId: json['chapterId'] as String?,
      chapterIndex: (json['chapterIndex'] as num?)?.toInt(),
      chapterTitle: json['chapterTitle'] as String?,
    );

Map<String, dynamic> _$KuronBackupPositionToJson(
        _KuronBackupPosition instance) =>
    <String, dynamic>{
      'contentId': instance.contentId,
      'currentPage': instance.currentPage,
      'totalPages': instance.totalPages,
      'lastAccessed': instance.lastAccessed?.toIso8601String(),
      'readingProgress': instance.readingProgress,
      'readingTimeMinutes': instance.readingTimeMinutes,
      'title': instance.title,
      'coverUrl': instance.coverUrl,
      'chapterId': instance.chapterId,
      'chapterIndex': instance.chapterIndex,
      'chapterTitle': instance.chapterTitle,
    };
