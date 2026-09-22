import 'package:freezed_annotation/freezed_annotation.dart';

part 'nclient_backup.freezed.dart';
part 'nclient_backup.g.dart';

// Parsed NClient V2/V3 backup tables. Every field nullable except row keys:
// a row missing its key is counted malformed, never fatal.
@freezed
abstract class NclientGallery with _$NclientGallery {
  const factory NclientGallery({
    @JsonKey(name: 'idGallery') required int idGallery,
    @JsonKey(name: 'title_pretty') String? titlePretty,
    @JsonKey(name: 'title_eng') String? titleEng,
    @JsonKey(name: 'favorite_count') int? favoriteCount,
    @JsonKey(name: 'mediaId') dynamic mediaId,
    String? pages,
    dynamic upload,
  }) = _NclientGallery;

  factory NclientGallery.fromJson(Map<String, dynamic> json) =>
      _$NclientGalleryFromJson(json);
}

@freezed
abstract class NclientFavorite with _$NclientFavorite {
  const factory NclientFavorite({
    @JsonKey(name: 'id_gallery') required int galleryId,
  }) = _NclientFavorite;

  factory NclientFavorite.fromJson(Map<String, dynamic> json) =>
      _$NclientFavoriteFromJson(json);
}

@freezed
abstract class NclientStatus with _$NclientStatus {
  const factory NclientStatus({required String name}) = _NclientStatus;

  factory NclientStatus.fromJson(Map<String, dynamic> json) =>
      _$NclientStatusFromJson(json);
}

@freezed
abstract class NclientStatusLink with _$NclientStatusLink {
  const factory NclientStatusLink({
    @JsonKey(name: 'gallery') required int galleryId,
    required String name,
  }) = _NclientStatusLink;

  factory NclientStatusLink.fromJson(Map<String, dynamic> json) =>
      _$NclientStatusLinkFromJson(json);
}

@freezed
abstract class NclientHistory with _$NclientHistory {
  const factory NclientHistory({
    required int id,
    dynamic mediaId,
    String? title,
    String? thumbType,
    dynamic time,
  }) = _NclientHistory;

  factory NclientHistory.fromJson(Map<String, dynamic> json) =>
      _$NclientHistoryFromJson(json);
}

// ponytail: Resume shape unverified (0 rows in real sample) — best-effort
// keys only; unparseable rows count malformed via null galleryId/page.
@freezed
abstract class NclientResume with _$NclientResume {
  const factory NclientResume({int? galleryId, int? page}) = _NclientResume;

  static int? _asInt(dynamic v) => v is int
      ? v
      : v is String
          ? int.tryParse(v)
          : null;

  static NclientResume tryParse(Map<String, dynamic> json) => NclientResume(
        galleryId: _asInt(json['gallery'] ??
            json['id_gallery'] ??
            json['idGallery'] ??
            json['id']),
        page:
            _asInt(json['page'] ?? json['currentPage'] ?? json['current_page']),
      );
}

@freezed
abstract class NclientBackup with _$NclientBackup {
  const factory NclientBackup({
    @Default([]) List<NclientGallery> galleries,
    @Default([]) List<NclientFavorite> favorites,
    @Default([]) List<NclientStatus> statuses,
    @Default([]) List<NclientStatusLink> statusLinks,
    @Default([]) List<NclientHistory> history,
    @Default([]) List<NclientResume> resumes,
    @Default(0) int malformedRows,
  }) = _NclientBackup;
}
