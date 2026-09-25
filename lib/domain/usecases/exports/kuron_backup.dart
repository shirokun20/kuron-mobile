import 'package:freezed_annotation/freezed_annotation.dart';

part 'kuron_backup.freezed.dart';
part 'kuron_backup.g.dart';

/// Highest backup payload version this app can restore.
const int kuronBackupSupportedVersion = 1;

/// A Kuron backup payload: everything needed to rebuild a library on another
/// device except image files (metadata only, same call as NClient import).
///
/// Every row field is nullable-tolerant so a payload written by a different app
/// version still imports what it can: the parser counts a row it cannot read as
/// malformed instead of aborting the restore.
@freezed
abstract class KuronBackup with _$KuronBackup {
  const factory KuronBackup({
    @Default(kuronBackupSupportedVersion) int formatVersion,
    @Default(<KuronBackupFavorite>[]) List<KuronBackupFavorite> favorites,
    @Default(<KuronBackupCollection>[]) List<KuronBackupCollection> collections,
    @Default(<KuronBackupCollectionMember>[])
    List<KuronBackupCollectionMember> collectionMembers,
    @Default(<KuronBackupHistory>[]) List<KuronBackupHistory> history,
    @Default(<KuronBackupPosition>[]) List<KuronBackupPosition> positions,
    @Default(<String, String>{}) Map<String, String> settings,
    @Default(0) int malformedRows,
  }) = _KuronBackup;

  factory KuronBackup.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupFromJson(json);
}

/// `favorites` row. Key is `(id, sourceId)`, the same key the app uses.
@freezed
abstract class KuronBackupFavorite with _$KuronBackupFavorite {
  const factory KuronBackupFavorite({
    required String id,
    @Default('nhentai') String sourceId,
    String? title,
    String? coverUrl,
    DateTime? addedAt,
  }) = _KuronBackupFavorite;

  factory KuronBackupFavorite.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupFavoriteFromJson(json);
}

/// `favorite_collections` row.
@freezed
abstract class KuronBackupCollection with _$KuronBackupCollection {
  const factory KuronBackupCollection({
    required String id,
    required String name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _KuronBackupCollection;

  factory KuronBackupCollection.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupCollectionFromJson(json);
}

/// `favorite_collection_items` row. Restore matches collections by exact name,
/// so the stored id is a hint only.
@freezed
abstract class KuronBackupCollectionMember with _$KuronBackupCollectionMember {
  const factory KuronBackupCollectionMember({
    required String collectionId,
    required String favoriteId,
    @Default('nhentai') String sourceId,
    DateTime? addedAt,
  }) = _KuronBackupCollectionMember;

  factory KuronBackupCollectionMember.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupCollectionMemberFromJson(json);
}

/// `history` row.
@freezed
abstract class KuronBackupHistory with _$KuronBackupHistory {
  const factory KuronBackupHistory({
    required String contentId,
    @Default('nhentai') String sourceId,
    DateTime? lastViewed,
    int? lastPage,
    int? totalPages,
    int? timeSpentSeconds,
    bool? isCompleted,
    String? title,
    String? coverUrl,
    String? chapterId,
    int? chapterIndex,
    String? chapterTitle,
  }) = _KuronBackupHistory;

  factory KuronBackupHistory.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupHistoryFromJson(json);
}

/// `reader_positions` row. `currentPage` is 1-based, like the entity.
@freezed
abstract class KuronBackupPosition with _$KuronBackupPosition {
  const factory KuronBackupPosition({
    required String contentId,
    required int currentPage,
    int? totalPages,
    DateTime? lastAccessed,
    double? readingProgress,
    int? readingTimeMinutes,
    String? title,
    String? coverUrl,
    String? chapterId,
    int? chapterIndex,
    String? chapterTitle,
  }) = _KuronBackupPosition;

  factory KuronBackupPosition.fromJson(Map<String, dynamic> json) =>
      _$KuronBackupPositionFromJson(json);
}
