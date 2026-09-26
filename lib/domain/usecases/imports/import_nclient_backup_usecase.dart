import 'dart:isolate';
import 'dart:typed_data';

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
  ///
  /// Parsing runs on a background isolate: a real backup carries 6-8 MB of
  /// JSON (85k tag rows) and `jsonDecode` + row mapping would otherwise freeze
  /// the UI for the whole pick-and-preview step, before any dialog is shown.
  Future<NclientBackup?> pickAndParse() async {
    _logger.i('NClient import: pick started');
    final Uint8List? bytes;
    try {
      bytes = await _kuronNative.pickBinaryFile();
    } catch (e, s) {
      _logger.e('NClient import: pick failed', error: e, stackTrace: s);
      rethrow;
    }
    if (bytes == null) {
      _logger.i('NClient import: pick cancelled');
      return null;
    }
    // Copy to a non-nullable local: Dart drops promotion for variables
    // assigned inside a try block, and the isolate closure needs Uint8List.
    final data = bytes;
    _logger.i('NClient import: picked ${data.lengthInBytes} bytes, parsing');
    try {
      // Hoist: the isolate closure must not capture `this` — the usecase
      // holds repositories whose loggers are unsendable across isolates.
      final parser = _parser;
      final backup = await Isolate.run(() => parser.parseBytes(data));
      _logger.i('NClient import: parsed ${backup.galleries.length} galleries, '
          '${backup.favorites.length} favorites, '
          '${backup.statusLinks.length} status links, '
          '${backup.history.length} history, '
          '${backup.resumes.length} resumes, '
          '${backup.malformedRows} malformed rows');
      return backup;
    } catch (e, s) {
      _logger.e('NClient import: parse failed (${data.lengthInBytes} bytes)',
          error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Counts per category for the preview dialog. No writes.
  ///
  /// Mirrors what [import] can actually write so the preview never promises
  /// more than the summary reports: favorites are the union of `Favorite` rows
  /// and `StatusManga` galleries (both paths ensure a favorite), and positions
  /// are only counted when the row carries a gallery id and a page.
  Map<String, int> preview(NclientBackup backup) {
    final galleries = {for (final g in backup.galleries) g.idGallery: g};
    final favoriteIds = <int>{
      for (final f in backup.favorites) f.galleryId,
      for (final l in backup.statusLinks) l.galleryId,
    };
    final memberNames = {
      for (final l in backup.statusLinks)
        if (galleries.containsKey(l.galleryId)) l.name,
    };
    return {
      'favorites': favoriteIds.length,
      'collections': memberNames.length,
      'history': backup.history.length,
      'positions': backup.resumes
          .where((r) => r.galleryId != null && r.page != null)
          .length,
    };
  }

  Future<NclientImportSummary> import(
    NclientBackup backup, {
    NclientImportProgress? onProgress,
  }) async {
    _logger.i('NClient import: started (${backup.favorites.length} favorites, '
        '${backup.statusLinks.length} status links, '
        '${backup.history.length} history, '
        '${backup.resumes.length} resumes)');
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
    _logger.i('NClient import: favorites done '
        '($favOk ok, $favSkip skipped, $favFail failed)');

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
    _logger.i('NClient import: collections done '
        '($colOk ok, $colSkip skipped, $colFail failed)');

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
    _logger.i('NClient import: history done '
        '($hisOk ok, $hisSkip skipped, $hisFail failed)');

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

    _logger.i('NClient import: positions done '
        '($posOk ok, $posSkip skipped, $posFail failed)');
    final summary = {
      'favorites': (success: favOk, skipped: favSkip, failed: favFail),
      'collections': (success: colOk, skipped: colSkip, failed: colFail),
      'history': (success: hisOk, skipped: hisSkip, failed: hisFail),
      'positions': (success: posOk, skipped: posSkip, failed: posFail),
      // Rows the parser could not read are real failures the user should see;
      // without this they only ever appear as silently missing items.
      'malformed': (success: 0, skipped: 0, failed: backup.malformedRows),
    };
    _logger.i('NClient import: finished $summary');
    return summary;
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
