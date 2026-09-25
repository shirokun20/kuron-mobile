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

// NClient V2 stores History.thumbType as an ImageExt ordinal (int), V3 as the
// full thumbnail URL (string) — verified in both upstreams (NClientV2
// Queries.java `getThumb().ordinal()`, NClientV3 `getThumbnail().toString()`).
// Accept both so a V2 history row is not dropped; a non-URL value simply falls
// back to the Gallery cover at import time.
String? _thumbFromJson(dynamic value) => value?.toString();

@freezed
abstract class NclientHistory with _$NclientHistory {
  const factory NclientHistory({
    required int id,
    dynamic mediaId,
    String? title,
    @JsonKey(name: 'thumbType', fromJson: _thumbFromJson) String? thumbType,
    dynamic time,
  }) = _NclientHistory;

  factory NclientHistory.fromJson(Map<String, dynamic> json) =>
      _$NclientHistoryFromJson(json);
}

// Verified shape from a real backup (issue #50, NClientV3 4.2.7):
//   {"id_gallery": 589597, "page": 6} — `page` is 1-based (upstream stores
// actualPage + 1), so it maps straight onto ReaderPosition.currentPage.
// Key fallbacks keep other exporter variants parseable; a row without a
// gallery id or page counts as malformed instead of aborting the import.
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
