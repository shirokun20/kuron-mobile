import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../repositories/reader_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/user_data_repository.dart';
import 'kuron_backup.dart';
import 'kuron_backup_parser.dart';

/// Progress callback while exporting: (category, done, total).
typedef KuronExportProgress = void Function(
    String category, int done, int total);

/// Builds a `KuronBackup_*.zip` from the repositories.
///
/// Reuses the existing export queries as-is: favorites and collection
/// memberships come from [UserDataRepository.getAllFavoritesForExport] and
/// friends, history/positions from the existing repositories, settings from
/// [SettingsRepository.exportSettingsKeys]. No image bytes are exported.
class KuronBackupSerializer {
  KuronBackupSerializer({
    required UserDataRepository userDataRepository,
    required ReaderRepository readerRepository,
    required SettingsRepository settingsRepository,
  })  : _userData = userDataRepository,
        _reader = readerRepository,
        _settings = settingsRepository;

  final UserDataRepository _userData;
  final ReaderRepository _reader;
  final SettingsRepository _settings;

  static const int _historyPageSize = 200;
  static const int _positionPageSize = 200;

  Future<Uint8List> toZipBytes({KuronExportProgress? onProgress}) async {
    final payload = await toBackup(onProgress: onProgress);
    return toZipBytesFromBackup(payload);
  }

  Future<KuronBackup> toBackup({KuronExportProgress? onProgress}) async {
    onProgress?.call('favorites', 0, 1);
    final favoriteRows = await _userData.getAllFavoritesForExport();
    final favorites = favoriteRows
        .map(_favoriteFromRow)
        .whereType<KuronBackupFavorite>()
        .toList();
    onProgress?.call('favorites', favorites.length, favoriteRows.length);

    onProgress?.call('collections', 0, 1);
    final collections = (await _userData.getFavoriteCollectionsForExport())
        .map((c) => KuronBackupCollection(
              id: c.id,
              name: c.name,
              createdAt: c.createdAt,
              updatedAt: c.updatedAt,
            ))
        .toList();
    final memberRows =
        await _userData.getFavoriteCollectionMembershipsForExport();
    final members = memberRows
        .map(_memberFromRow)
        .whereType<KuronBackupCollectionMember>()
        .toList();
    onProgress?.call('collections', collections.length, collections.length);

    onProgress?.call('history', 0, 1);
    final history = await _exportAllHistory();
    onProgress?.call('history', history.length, history.length);

    onProgress?.call('positions', 0, 1);
    final positions = await _exportAllPositions();
    onProgress?.call('positions', positions.length, positions.length);

    onProgress?.call('settings', 0, 1);
    final settings = await _settings.exportSettingsKeys();
    onProgress?.call('settings', settings.length, settings.length);

    return KuronBackup(
      favorites: favorites,
      collections: collections,
      collectionMembers: members,
      history: history,
      positions: positions,
      settings: settings,
    );
  }

  static Uint8List toZipBytesFromBackup(KuronBackup backup) {
    final jsonBytes = utf8.encode(jsonEncode(backup.toJson()));
    final archive = Archive()
      ..addFile(
          ArchiveFile(kuronBackupPayloadName, jsonBytes.length, jsonBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Default file name: `KuronBackup_<epoch>.zip`.
  static String fileName([DateTime? now]) =>
      'KuronBackup_${(now ?? DateTime.now()).millisecondsSinceEpoch}.zip';

  /// Pages through the existing history query instead of adding a new
  /// "get all history" repository method.
  Future<List<KuronBackupHistory>> _exportAllHistory() async {
    final total = await _userData.getHistoryCount();
    if (total <= 0) return [];
    final out = <KuronBackupHistory>[];
    var page = 1;
    while (out.length < total) {
      final batch = await _userData.getHistory(
        page: page,
        limit: _historyPageSize,
      );
      if (batch.isEmpty) break;
      for (final h in batch) {
        out.add(KuronBackupHistory(
          contentId: h.contentId,
          sourceId: h.sourceId,
          lastViewed: h.lastViewed,
          lastPage: h.lastPage,
          totalPages: h.totalPages,
          timeSpentSeconds: h.timeSpent.inSeconds,
          isCompleted: h.isCompleted,
          title: h.title,
          coverUrl: h.coverUrl,
          chapterId: h.chapterId,
          chapterIndex: h.chapterIndex,
          chapterTitle: h.chapterTitle,
        ));
      }
      page++;
    }
    return out;
  }

  /// `getAllReaderPositions` is paginated too (default page size 50), so keep
  /// pulling until a short page comes back.
  Future<List<KuronBackupPosition>> _exportAllPositions() async {
    final out = <KuronBackupPosition>[];
    var page = 1;
    while (true) {
      final batch = await _reader.getAllReaderPositions(
        page: page,
        limit: _positionPageSize,
      );
      if (batch.isEmpty) break;
      for (final p in batch) {
        out.add(KuronBackupPosition(
          contentId: p.contentId,
          currentPage: p.currentPage,
          totalPages: p.totalPages,
          lastAccessed: p.lastAccessed,
          readingProgress: p.readingProgress,
          readingTimeMinutes: p.readingTimeMinutes,
          title: p.title,
          coverUrl: p.coverUrl,
          chapterId: p.chapterId,
          chapterIndex: p.chapterIndex,
          chapterTitle: p.chapterTitle,
        ));
      }
      if (batch.length < _positionPageSize) break;
      page++;
    }
    return out;
  }

  KuronBackupFavorite? _favoriteFromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return KuronBackupFavorite(
      id: id,
      sourceId: row['source_id']?.toString() ?? 'nhentai',
      title: row['title']?.toString(),
      coverUrl: row['cover_url']?.toString(),
      addedAt: _dateOrNull(row['added_at']),
    );
  }

  KuronBackupCollectionMember? _memberFromRow(Map<String, dynamic> row) {
    final collectionId = row['collection_id']?.toString() ?? '';
    final favoriteId = row['favorite_id']?.toString() ?? '';
    if (collectionId.isEmpty || favoriteId.isEmpty) return null;
    return KuronBackupCollectionMember(
      collectionId: collectionId,
      favoriteId: favoriteId,
      sourceId: row['source_id']?.toString() ?? 'nhentai',
      addedAt: _dateOrNull(row['added_at']),
    );
  }

  static DateTime? _dateOrNull(dynamic value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final millis = int.tryParse(value);
      if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
      return DateTime.tryParse(value);
    }
    return null;
  }
}
