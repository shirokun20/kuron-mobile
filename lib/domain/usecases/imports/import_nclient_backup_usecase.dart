import 'package:get_it/get_it.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

import '../../../data/datasources/remote/api/nhentai_image_url_builder.dart';
import '../../entities/history.dart';
import '../../entities/reader_position.dart';
import '../../repositories/reader_repository.dart';
import '../../repositories/user_data_repository.dart';
import 'nclient_backup.dart';
import 'nclient_backup_parser.dart';

/// Progress callback: (category, done, total).
typedef NclientImportProgress = void Function(
    String category, int done, int total);

// ponytail: plain records, no model class — the summary is consumed once
// by the result dialog and never serialized.
typedef CategoryResult = ({int success, int skipped, int failed});
typedef NclientImportSummary = Map<String, CategoryResult>;

/// Imports NClient V2/V3 backups. Merge is non-destructive (Kuron wins):
/// existing favorites/history/positions are never overwritten, collections
/// merge by exact name. Only statuses WITH members create collections.
class ImportNclientBackupUseCase {
  ImportNclientBackupUseCase({
    required KuronNative kuronNative,
    required UserDataRepository userDataRepository,
    required ReaderRepository readerRepository,
    NclientBackupParser? parser,
  })  : _kuronNative = kuronNative,
        _userData = userDataRepository,
        _reader = readerRepository,
        _parser = parser ?? NclientBackupParser();

  final KuronNative _kuronNative;
  final UserDataRepository _userData;
  final ReaderRepository _reader;
  final NclientBackupParser _parser;

  static const String sourceId = 'nhentai';
  static const int _batch = 100;

  Logger get _logger => GetIt.I<Logger>();

  /// Picks a file (ZIP or raw JSON) and parses it. Null when cancelled.
  Future<NclientBackup?> pickAndParse() async {
    final bytes = await _kuronNative.pickBinaryFile();
    if (bytes == null) return null;
    return _parser.parseBytes(bytes);
  }

  /// Counts per category for the preview dialog. No writes.
  Map<String, int> preview(NclientBackup backup) {
    final galleries = {for (final g in backup.galleries) g.idGallery: g};
    final memberNames = {
      for (final l in backup.statusLinks)
        if (galleries.containsKey(l.galleryId)) l.name,
    };
    return {
      'favorites': backup.favorites.length,
      'collections': memberNames.length,
      'memberships': backup.statusLinks.length,
      'history': backup.history.length,
      'positions': backup.resumes.length,
    };
  }

  Future<NclientImportSummary> import(
    NclientBackup backup, {
    NclientImportProgress? onProgress,
  }) async {
    final galleries = {for (final g in backup.galleries) g.idGallery: g};
    var favOk = 0, favSkip = 0, favFail = 0;

    // ponytail: ensure-favorite shared by Favorite + StatusManga paths.
    Future<bool> ensureFavorite(int galleryId) async {
      final id = '$galleryId';
      try {
        if (await _userData.isFavorite(id, sourceId: sourceId)) {
          favSkip++;
          return true;
        }
        final gallery = galleries[galleryId];
        if (gallery == null) {
          favFail++;
          return false;
        }
        await _userData.addToFavorites(
          id: id,
          sourceId: sourceId,
          coverUrl: _coverFor(gallery) ?? '',
          title: gallery.titlePretty ?? gallery.titleEng,
        );
        favOk++;
        return true;
      } catch (e) {
        _logger.w('NClient favorite $id failed: $e');
        favFail++;
        return false;
      }
    }

    for (var i = 0; i < backup.favorites.length; i += _batch) {
      final chunk = backup.favorites.skip(i).take(_batch);
      for (final fav in chunk) {
        await ensureFavorite(fav.galleryId);
      }
      onProgress?.call(
          'favorites',
          (i + chunk.length).clamp(0, backup.favorites.length),
          backup.favorites.length);
    }

    var colOk = 0, colSkip = 0, colFail = 0;
    final existing = {
      for (final c in await _userData.getFavoriteCollections()) c.name: c,
    };
    final linksByStatus = <String, List<NclientStatusLink>>{};
    for (final link in backup.statusLinks) {
      if (!galleries.containsKey(link.galleryId)) {
        colFail++; // ponytail: dangling link, same rule as favorite w/o gallery
        continue;
      }
      (linksByStatus[link.name] ??= []).add(link);
    }
    // ponytail: statuses with zero members create nothing (e.g. "None").
    var done = 0;
    for (final entry in linksByStatus.entries) {
      try {
        var collection = existing[entry.key];
        collection ??= await _userData.createFavoriteCollection(
          name: entry.key,
        );
        existing[entry.key] = collection;
        for (final link in entry.value) {
          final id = '${link.galleryId}';
          if (!await ensureFavorite(link.galleryId)) {
            colFail++;
            continue;
          }
          final ids = await _userData.getFavoriteCollectionIds(
            favoriteId: id,
            sourceId: sourceId,
          );
          if (ids.contains(collection.id)) {
            colSkip++;
          } else {
            await _userData.setFavoriteCollectionIds(
              favoriteId: id,
              sourceId: sourceId,
              collectionIds: [...ids, collection.id],
            );
            colOk++;
          }
        }
      } catch (e) {
        _logger.w('NClient status ${entry.key} failed: $e');
        colFail += entry.value.length;
      }
      onProgress?.call('collections', ++done, linksByStatus.length);
    }

    var hisOk = 0, hisSkip = 0, hisFail = 0;
    for (var i = 0; i < backup.history.length; i++) {
      final h = backup.history[i];
      try {
        if (await _userData.getHistoryEntry('${h.id}') != null) {
          hisSkip++;
        } else {
          final gallery = galleries[h.id];
          final thumb = h.thumbType ?? '';
          await _userData.saveHistory(History(
            contentId: '${h.id}',
            sourceId: sourceId,
            lastViewed: dateFromMillis(h.time) ?? DateTime.now(),
            title: h.title ?? gallery?.titlePretty ?? gallery?.titleEng,
            coverUrl: thumb.startsWith('http') ? thumb : _coverFor(gallery),
            totalPages: gallery == null ? 0 : pageCountFromPages(gallery.pages),
          ));
          hisOk++;
        }
      } catch (e) {
        _logger.w('NClient history ${h.id} failed: $e');
        hisFail++;
      }
      onProgress?.call('history', i + 1, backup.history.length);
    }

    // NClient purges Gallery rows on every DB open (keep-list = Downloads ∪
    // Favorite ∪ StatusManga only), so a Resume gallery is regularly missing
    // from Gallery. Positions are still worth importing: History carries the
    // title + thumbnail URL for those galleries.
    final historyById = {for (final h in backup.history) h.id: h};
    var posOk = 0, posSkip = 0, posFail = 0;
    for (var i = 0; i < backup.resumes.length; i++) {
      final r = backup.resumes[i];
      try {
        final gallery = r.galleryId == null ? null : galleries[r.galleryId];
        if (r.galleryId == null || r.page == null) {
          posFail++;
        } else if (await _reader.getReaderPosition('${r.galleryId}') != null) {
          posSkip++;
        } else {
          final total = gallery == null ? 0 : pageCountFromPages(gallery.pages);
          final history = historyById[r.galleryId];
          final thumb = history?.thumbType ?? '';
          await _reader.saveReaderPosition(ReaderPosition.create(
            contentId: '${r.galleryId}',
            currentPage: _safePage(r.page!, total),
            totalPages: total,
            title: gallery?.titlePretty ?? gallery?.titleEng ?? history?.title,
            coverUrl:
                _coverFor(gallery) ?? (thumb.startsWith('http') ? thumb : null),
          ));
          posOk++;
        }
      } catch (e) {
        _logger.w('NClient resume failed: $e');
        posFail++;
      }
      onProgress?.call('positions', i + 1, backup.resumes.length);
    }

    return {
      'favorites': (success: favOk, skipped: favSkip, failed: favFail),
      'collections': (success: colOk, skipped: colSkip, failed: colFail),
      'history': (success: hisOk, skipped: hisSkip, failed: hisFail),
      'positions': (success: posOk, skipped: posSkip, failed: posFail),
    };
  }

  String? _coverFor(NclientGallery? gallery) {
    final mediaId = gallery?.mediaId;
    if (gallery == null || mediaId == null) return null;
    return NhentaiImageUrlBuilder.buildCoverUrl(
      '$mediaId',
      coverExtFromPages(gallery.pages),
    );
  }

  // NClient pages are 1-based (ZoomActivity stores actualPage + 1), same as
  // ReaderPosition.currentPage. Clamp into range when a total is known;
  // floor at 1 so a 0 page cannot throw inside clamp().
  int _safePage(int page, int total) {
    if (page < 1) return 1;
    if (total > 0) return page > total ? total : page;
    return page;
  }
}
