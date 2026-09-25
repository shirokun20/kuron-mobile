import 'dart:isolate';
import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../../entities/history.dart';
import '../../entities/reader_position.dart';
import '../../repositories/reader_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/user_data_repository.dart';
import 'kuron_backup.dart';
import 'kuron_backup_parser.dart';

/// Progress callback while restoring: (category, done, total).
typedef KuronRestoreProgress = void Function(
  String category,
  int done,
  int total,
);

// ponytail: plain records — consumed once by the result dialog, never serialized.
typedef KuronCategoryResult = ({int success, int skipped, int failed});
typedef KuronRestoreSummary = Map<String, KuronCategoryResult>;

/// Restores a `KuronBackup_*.zip` with the same non-destructive merge policy the
/// NClient importer uses, so the whole app has one mental model for imports:
/// existing data always wins.
class RestoreKuronBackupUseCase {
  RestoreKuronBackupUseCase({
    required UserDataRepository userDataRepository,
    required ReaderRepository readerRepository,
    required SettingsRepository settingsRepository,
    KuronBackupParser? parser,
  })  : _userData = userDataRepository,
        _reader = readerRepository,
        _settings = settingsRepository,
        _parser = parser ?? KuronBackupParser();

  final UserDataRepository _userData;
  final ReaderRepository _reader;
  final SettingsRepository _settings;
  final KuronBackupParser _parser;

  static const int _batch = 100;

  Logger get _logger => GetIt.I<Logger>();

  /// Synchronous parse (tests / already-small payloads).
  KuronBackup parseBytes(List<int> bytes, {String? fileName}) =>
      _parser.parseBytes(_asBytes(bytes), fileName: fileName);

  /// Parsing a multi-MB payload on the UI isolate would freeze the picker step,
  /// so the restore path mirrors the NClient importer and parses off-thread.
  Future<KuronBackup> parseBytesAsync(
    List<int> bytes, {
    String? fileName,
  }) =>
      Isolate.run(
        () => KuronBackupParser().parseBytes(
          _asBytes(bytes),
          fileName: fileName,
        ),
      );

  /// Counts per category for the preview dialog. No writes.
  Map<String, int> preview(KuronBackup backup) => {
        'favorites': backup.favorites.length,
        'collections': backup.collections.length,
        'memberships': backup.collectionMembers.length,
        'history': backup.history.length,
        'positions': backup.positions.length,
        'settings': backup.settings.length,
      };

  Future<KuronRestoreSummary> restore(
    KuronBackup backup, {
    KuronRestoreProgress? onProgress,
  }) async {
    var favOk = 0, favSkip = 0, favFail = 0;
    for (var i = 0; i < backup.favorites.length; i += _batch) {
      final chunk = backup.favorites.skip(i).take(_batch);
      for (final fav in chunk) {
        try {
          if (await _userData.isFavorite(fav.id, sourceId: fav.sourceId)) {
            favSkip++;
            continue;
          }
          await _userData.addToFavorites(
            id: fav.id,
            sourceId: fav.sourceId,
            coverUrl: fav.coverUrl ?? '',
            title: fav.title,
          );
          favOk++;
        } catch (e) {
          _logger.w('Kuron backup favorite ${fav.id} failed: $e');
          favFail++;
        }
      }
      onProgress?.call(
        'favorites',
        (i + chunk.length).clamp(0, backup.favorites.length),
        backup.favorites.length,
      );
    }

    // Collections merge by exact name, so a rename on the destination device
    // still receives the backed-up members under a new collection.
    var colOk = 0, colSkip = 0, colFail = 0;
    final existing = {
      for (final c in await _userData.getFavoriteCollections()) c.name: c,
    };
    final byBackupId = <String, String>{
      for (final c in backup.collections) c.id: c.name,
    };
    final membersByName = <String, List<KuronBackupCollectionMember>>{};
    for (final member in backup.collectionMembers) {
      final name = byBackupId[member.collectionId];
      if (name == null || name.isEmpty) {
        colFail++; // membership without a collection row
        continue;
      }
      (membersByName[name] ??= []).add(member);
    }

    var done = 0;
    final totalNames = membersByName.length;
    for (final entry in membersByName.entries) {
      try {
        final collection = existing[entry.key] ??
            await _userData.createFavoriteCollection(name: entry.key);
        existing[entry.key] = collection;
        for (final member in entry.value) {
          // Membership has a foreign key on favorites: make sure the favorite
          // exists first (same order as the NClient importer).
          if (!await _userData.isFavorite(
            member.favoriteId,
            sourceId: member.sourceId,
          )) {
            final favorite = _favoriteById(backup, member.favoriteId);
            await _userData.addToFavorites(
              id: member.favoriteId,
              sourceId: member.sourceId,
              coverUrl: favorite?.coverUrl ?? '',
              title: favorite?.title,
            );
            favOk++;
          }
          final ids = await _userData.getFavoriteCollectionIds(
            favoriteId: member.favoriteId,
            sourceId: member.sourceId,
          );
          if (ids.contains(collection.id)) {
            colSkip++;
          } else {
            await _userData.setFavoriteCollectionIds(
              favoriteId: member.favoriteId,
              sourceId: member.sourceId,
              collectionIds: [...ids, collection.id],
            );
            colOk++;
          }
        }
      } catch (e) {
        _logger.w('Kuron backup collection "${entry.key}" failed: $e');
        colFail += entry.value.length;
      }
      onProgress?.call('collections', ++done, totalNames);
    }

    var hisOk = 0, hisSkip = 0, hisFail = 0;
    for (var i = 0; i < backup.history.length; i++) {
      final h = backup.history[i];
      try {
        if (await _userData.getHistoryEntry(h.contentId) != null) {
          hisSkip++;
        } else {
          await _userData.saveHistory(History(
            contentId: h.contentId,
            sourceId: h.sourceId,
            lastViewed: h.lastViewed ?? DateTime.now(),
            lastPage: h.lastPage ?? 1,
            totalPages: h.totalPages ?? 0,
            timeSpent: Duration(seconds: h.timeSpentSeconds ?? 0),
            isCompleted: h.isCompleted ?? false,
            title: h.title,
            coverUrl: h.coverUrl,
            chapterId: h.chapterId,
            chapterIndex: h.chapterIndex,
            chapterTitle: h.chapterTitle,
          ));
          hisOk++;
        }
      } catch (e) {
        _logger.w('Kuron backup history ${h.contentId} failed: $e');
        hisFail++;
      }
      onProgress?.call('history', i + 1, backup.history.length);
    }

    var posOk = 0, posSkip = 0, posFail = 0;
    for (var i = 0; i < backup.positions.length; i++) {
      final p = backup.positions[i];
      try {
        if (await _reader.getReaderPosition(p.contentId) != null) {
          posSkip++;
        } else {
          final total = p.totalPages ?? 0;
          final page = p.currentPage < 1
              ? 1
              : (total > 0 && p.currentPage > total ? total : p.currentPage);
          await _reader.saveReaderPosition(ReaderPosition.create(
            contentId: p.contentId,
            currentPage: page,
            totalPages: total,
            readingTimeMinutes: p.readingTimeMinutes ?? 0,
            title: p.title,
            coverUrl: p.coverUrl,
            chapterId: p.chapterId,
            chapterIndex: p.chapterIndex,
            chapterTitle: p.chapterTitle,
          ));
          posOk++;
        }
      } catch (e) {
        _logger.w('Kuron backup position ${p.contentId} failed: $e');
        posFail++;
      }
      onProgress?.call('positions', i + 1, backup.positions.length);
    }

    // Settings: device value wins per key; unknown keys are skipped inside the
    // repository and counted here as skipped, never failed.
    var setOk = 0, setSkip = 0, setFail = 0;
    if (backup.settings.isNotEmpty) {
      try {
        final result = await _settings.importSettingsKeys(
          backup.settings,
          onlyIfAbsent: true,
        );
        setOk = result.applied;
        setSkip = result.skipped;
      } catch (e) {
        _logger.w('Kuron backup settings failed: $e');
        setFail = backup.settings.length;
      }
    }
    onProgress?.call(
        'settings', backup.settings.length, backup.settings.length);

    return {
      'favorites': (success: favOk, skipped: favSkip, failed: favFail),
      'collections': (success: colOk, skipped: colSkip, failed: colFail),
      'history': (success: hisOk, skipped: hisSkip, failed: hisFail),
      'positions': (success: posOk, skipped: posSkip, failed: posFail),
      'settings': (success: setOk, skipped: setSkip, failed: setFail),
      'malformed': (success: 0, skipped: 0, failed: backup.malformedRows),
    };
  }

  static KuronBackupFavorite? _favoriteById(
    KuronBackup backup,
    String id,
  ) {
    for (final fav in backup.favorites) {
      if (fav.id == id) return fav;
    }
    return null;
  }
}

Uint8List _asBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
