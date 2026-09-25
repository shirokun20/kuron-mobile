// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nclient_backup.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NclientGallery _$NclientGalleryFromJson(Map<String, dynamic> json) =>
    _NclientGallery(
      idGallery: (json['idGallery'] as num).toInt(),
      titlePretty: json['title_pretty'] as String?,
      titleEng: json['title_eng'] as String?,
      favoriteCount: (json['favorite_count'] as num?)?.toInt(),
      mediaId: json['mediaId'],
      pages: json['pages'] as String?,
      upload: json['upload'],
    );

Map<String, dynamic> _$NclientGalleryToJson(_NclientGallery instance) =>
    <String, dynamic>{
      'idGallery': instance.idGallery,
      'title_pretty': instance.titlePretty,
      'title_eng': instance.titleEng,
      'favorite_count': instance.favoriteCount,
      'mediaId': instance.mediaId,
      'pages': instance.pages,
      'upload': instance.upload,
    };

_NclientFavorite _$NclientFavoriteFromJson(Map<String, dynamic> json) =>
    _NclientFavorite(
      galleryId: (json['id_gallery'] as num).toInt(),
    );

Map<String, dynamic> _$NclientFavoriteToJson(_NclientFavorite instance) =>
    <String, dynamic>{
      'id_gallery': instance.galleryId,
    };

_NclientStatus _$NclientStatusFromJson(Map<String, dynamic> json) =>
    _NclientStatus(
      name: json['name'] as String,
    );

Map<String, dynamic> _$NclientStatusToJson(_NclientStatus instance) =>
    <String, dynamic>{
      'name': instance.name,
    };

_NclientStatusLink _$NclientStatusLinkFromJson(Map<String, dynamic> json) =>
    _NclientStatusLink(
      galleryId: (json['gallery'] as num).toInt(),
      name: json['name'] as String,
    );

Map<String, dynamic> _$NclientStatusLinkToJson(_NclientStatusLink instance) =>
    <String, dynamic>{
      'gallery': instance.galleryId,
      'name': instance.name,
    };

_NclientHistory _$NclientHistoryFromJson(Map<String, dynamic> json) =>
    _NclientHistory(
      id: (json['id'] as num).toInt(),
      mediaId: json['mediaId'],
      title: json['title'] as String?,
      thumbType: _thumbFromJson(json['thumbType']),
      time: json['time'],
    );

Map<String, dynamic> _$NclientHistoryToJson(_NclientHistory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'mediaId': instance.mediaId,
      'title': instance.title,
      'thumbType': instance.thumbType,
      'time': instance.time,
    };
