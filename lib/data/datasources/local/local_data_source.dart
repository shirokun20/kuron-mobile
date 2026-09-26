import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';

import 'package:nhasixapp/core/constants/app_constants.dart';
import '../../models/download_status_model.dart';
import '../../models/history_model.dart';
import '../../models/reader_position_model.dart';
import '../../../domain/entities/content_tag.dart';
import '../../../domain/entities/favorite_collection.dart';
import '../../../domain/entities/user_preferences.dart';
import '../../../domain/entities/download_status.dart';
import 'database_helper.dart';

// Local data source for database operations (simplified)
class LocalDataSource {
  final DatabaseHelper _databaseHelper;
  final Logger _logger = getIt<Logger>();

  LocalDataSource(this._databaseHelper);

  // Handle database errors and attempt recovery
  Future<Database?> _getSafeDatabase() async {
    try {
      return await _databaseHelper.database;
    } catch (e) {
      _logger.e('Database access failed: $e');

      // Attempt to reset database if it's corrupted
      try {
        _logger.w('Attempting to reset corrupted database...');
        await _databaseHelper.resetDatabase();
        return await _databaseHelper.database;
      } catch (resetError) {
        _logger.e('Database reset failed: $resetError');
        return null;
      }
    }
  }

  // ==================== FAVORITES OPERATIONS ====================

  // Add content to favorites with full metadata
  Future<void> addToFavorites({
    required String id,
    required String sourceId,
    required String coverUrl,
    String? title,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot add to favorites');
        return;
      }

      await db.insert(
        'favorites',
        {
          'id': id,
          'source_id': sourceId,
          'title': title, // Added title
          'cover_url': coverUrl,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.d('Added content $id from $sourceId to favorites');
    } catch (e) {
      _logger.e('Error adding to favorites: $e');
      rethrow;
    }
  }

  // Remove content from favorites
  Future<void> removeFromFavorites(String id, {String? sourceId}) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot remove from favorites');
        return;
      }

      if (sourceId == null) {
        await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
      } else {
        await db.delete(
          'favorites',
          where: 'id = ? AND source_id = ?',
          whereArgs: [id, sourceId],
        );
      }
      _logger.d('Removed content $id from favorites');
    } catch (e) {
      _logger.e('Error removing from favorites: $e');
      rethrow;
    }
  }

  // Remove all favorites for a specific source
  Future<void> deleteFavoritesBySourceId(String sourceId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete favorites by source');
        return;
      }

      await db
          .delete('favorites', where: 'source_id = ?', whereArgs: [sourceId]);
      _logger.d('Deleted all favorites for source: $sourceId');
    } catch (e) {
      _logger.e('Error deleting favorites by source: $e');
      rethrow;
    }
  }

  // ==================== CONTENT TAGS (recommendation seeds) ====================

  // Replace all tag rows for one content (delete + batch reinsert).
  // Best-effort derived data: callers treat failures as non-fatal.
  Future<void> saveContentTags(List<ContentTag> tags) async {
    if (tags.isEmpty) return;
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save content tags');
        return;
      }

      final first = tags.first;
      final batch = db.batch();
      batch.delete(
        'content_tags',
        where: 'content_id = ? AND source_id = ?',
        whereArgs: [first.contentId, first.sourceId],
      );
      for (final tag in tags) {
        batch.insert(
          'content_tags',
          {
            'content_id': tag.contentId,
            'source_id': tag.sourceId,
            'name': tag.name,
            'type': tag.type,
            'origin': tag.origin,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      _logger.d(
          'Saved ${tags.length} tags for ${first.contentId} (${first.origin})');
    } catch (e) {
      _logger.e('Error saving content tags: $e');
      rethrow;
    }
  }

  // ==================== RECOMMENDATION HISTORY ====================

  static const _recTable = 'recommendation_history';

  // Single-column upsert that preserves the other columns (a blind
  // replace would wipe shown_at when a tap is recorded, and vice versa).
  Future<void> _upsertRecState(
    String contentId,
    String? sourceId,
    String column,
    Object value, {
    Map<String, Object>? extraSet,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return;
      final sid = sourceId ?? 'nhentai';
      final setClause = [
        '$column = excluded.$column',
        if (extraSet != null)
          for (final e in extraSet.entries) '${e.key} = ${e.value}',
      ].join(', ');
      await db.rawInsert(
        'INSERT INTO $_recTable (content_id, source_id, $column) '
        'VALUES (?, ?, ?) '
        'ON CONFLICT (content_id, source_id) DO UPDATE SET $setClause',
        [contentId, sid, value],
      );
      // Keep the table bounded: drop rows fully older than 30 days.
      final cutoff =
          DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      await db.delete(
        _recTable,
        where:
            '(shown_at IS NULL OR shown_at < ?) AND (dismissed_at IS NULL OR dismissed_at < ?)',
        whereArgs: [cutoff, cutoff],
      );
    } catch (e) {
      _logger.e('Error recording recommendation state: $e');
    }
  }

  Future<void> recordRecommendationShown(
    String contentId,
    String? sourceId,
  ) =>
      _upsertRecState(contentId, sourceId, 'shown_at',
          DateTime.now().millisecondsSinceEpoch);

  Future<void> recordRecommendationTapped(
    String contentId,
    String? sourceId,
  ) =>
      _upsertRecState(contentId, sourceId, 'tapped_at',
          DateTime.now().millisecondsSinceEpoch);

  Future<void> recordRecommendationDismissed(
    String contentId,
    String? sourceId,
  ) =>
      _upsertRecState(
        contentId,
        sourceId,
        'dismissed_at',
        DateTime.now().millisecondsSinceEpoch,
        extraSet: const {'dismissed': 1},
      );

  Future<List<Map<String, dynamic>>> getRecommendationHistoryRows() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return [];
      return await db.query(_recTable);
    } catch (e) {
      _logger.e('Error reading recommendation history: $e');
      return [];
    }
  }

  // Tag names for one content — the seed set used by the scoring engine.
  Future<Set<String>> getTagNamesForContent(
    String contentId, {
    String? sourceId,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return {};
      final rows = await db.query(
        'content_tags',
        columns: ['name'],
        where: sourceId == null
            ? 'content_id = ?'
            : 'content_id = ? AND source_id = ?',
        whereArgs:
            sourceId == null ? [contentId] : [contentId, sourceId],
      );
      return {for (final r in rows) r['name'] as String};
    } catch (e) {
      _logger.e('Error reading content tags: $e');
      return {};
    }
  }

  // Get favorite content with title from favorites table (fallback to history/downloads)
  Future<List<Map<String, dynamic>>> getFavorites({
    int page = 1,
    int limit = 20,
    String? collectionId,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty favorites');
        return [];
      }

      final offset = (page - 1) * limit;

      // Prefer f.title, fallback to history/downloads for old data
      final collectionJoin = collectionId == null
          ? ''
          : 'INNER JOIN favorite_collection_items fci ON f.id = fci.favorite_id AND f.source_id = fci.source_id';
      final collectionWhere =
          collectionId == null ? '' : 'WHERE fci.collection_id = ?';
      final args = <Object?>[
        if (collectionId != null) collectionId,
        limit,
        offset,
      ];

      final result = await db.rawQuery('''
        SELECT 
          f.id,
          f.source_id,
          f.cover_url,
          f.added_at,
          COALESCE(
            f.title,
            (
              SELECT h.title
              FROM history h
              WHERE h.id = f.id AND h.source_id = f.source_id
              ORDER BY h.last_viewed DESC
              LIMIT 1
            ),
            d.title
          ) as title
        FROM favorites f
        $collectionJoin
        LEFT JOIN downloads d ON f.id = d.id AND f.source_id = d.source_id
        $collectionWhere
        ORDER BY f.added_at DESC
        LIMIT ? OFFSET ?
      ''', args);

      return result;
    } catch (e) {
      _logger.e('Error getting favorites: $e');
      return [];
    }
  }

  // Check if content is favorited
  Future<bool> isFavorited(String id, {String? sourceId}) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot check if favorited');
        return false;
      }

      final result = await db.query('favorites',
          where: sourceId == null ? 'id = ?' : 'id = ? AND source_id = ?',
          whereArgs: sourceId == null ? [id] : [id, sourceId],
          limit: 1);

      return result.isNotEmpty;
    } catch (e) {
      _logger.e('Error checking if favorited: $e');
      return false;
    }
  }

  // Get favorites count
  Future<int> getFavoritesCount({String? collectionId}) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      final result = await db.rawQuery(
        collectionId == null
            ? 'SELECT COUNT(*) as count FROM favorites'
            : '''
              SELECT COUNT(*) as count
              FROM favorite_collection_items
              WHERE collection_id = ?
            ''',
        collectionId == null ? null : [collectionId],
      );
      return result.first['count'] as int;
    } catch (e) {
      _logger.e('Error getting favorites count: $e');
      return 0;
    }
  }

  // Get all favorites at once (for export - no pagination)
  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot get all favorites');
        return [];
      }

      final result = await db.rawQuery('''
        SELECT 
          f.id,
          f.source_id,
          f.cover_url,
          f.added_at,
          COALESCE(
            f.title,
            (
              SELECT h.title
              FROM history h
              WHERE h.id = f.id AND h.source_id = f.source_id
              ORDER BY h.last_viewed DESC
              LIMIT 1
            ),
            d.title
          ) as title
        FROM favorites f
        LEFT JOIN downloads d ON f.id = d.id AND f.source_id = d.source_id
        ORDER BY f.added_at DESC
      ''');

      return result;
    } catch (e) {
      _logger.e('Error getting all favorites: $e');
      return [];
    }
  }

  Future<FavoriteCollection> createFavoriteCollection({
    required String name,
    String? collectionId,
  }) async {
    final db = await _getSafeDatabase();
    if (db == null) {
      throw StateError('Database not available, cannot create collection');
    }

    final now = DateTime.now();
    final normalizedName = name.trim();
    final resolvedId =
        collectionId ?? 'collection_${now.microsecondsSinceEpoch}';

    await db.insert(
      'favorite_collections',
      {
        'id': resolvedId,
        'name': normalizedName,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return FavoriteCollection(
      id: resolvedId,
      name: normalizedName,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> renameFavoriteCollection({
    required String collectionId,
    required String name,
  }) async {
    final db = await _getSafeDatabase();
    if (db == null) {
      throw StateError('Database not available, cannot rename collection');
    }

    await db.update(
      'favorite_collections',
      {
        'name': name.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<void> deleteFavoriteCollection(String collectionId) async {
    final db = await _getSafeDatabase();
    if (db == null) {
      throw StateError('Database not available, cannot delete collection');
    }

    await db.delete(
      'favorite_collections',
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<List<FavoriteCollection>> getFavoriteCollections() async {
    final db = await _getSafeDatabase();
    if (db == null) {
      _logger.e('Database not available, returning empty favorite collections');
      return [];
    }

    final result = await db.rawQuery('''
      SELECT
        fc.id,
        fc.name,
        fc.created_at,
        fc.updated_at,
        COUNT(fci.favorite_id) as item_count
      FROM favorite_collections fc
      LEFT JOIN favorite_collection_items fci
        ON fc.id = fci.collection_id
      GROUP BY fc.id, fc.name, fc.created_at, fc.updated_at
      ORDER BY fc.updated_at DESC, fc.name COLLATE NOCASE ASC
    ''');

    return result.map(_mapFavoriteCollection).toList(growable: false);
  }

  Future<List<String>> getFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
  }) async {
    final db = await _getSafeDatabase();
    if (db == null) {
      _logger
          .e('Database not available, returning empty favorite collection ids');
      return [];
    }

    final result = await db.query(
      'favorite_collection_items',
      columns: ['collection_id'],
      where: 'favorite_id = ? AND source_id = ?',
      whereArgs: [favoriteId, sourceId],
    );

    return result
        .map((row) => row['collection_id']?.toString())
        .whereType<String>()
        .toList(growable: false);
  }

  Future<void> setFavoriteCollectionIds({
    required String favoriteId,
    required String sourceId,
    required List<String> collectionIds,
  }) async {
    final db = await _getSafeDatabase();
    if (db == null) {
      throw StateError('Database not available, cannot update memberships');
    }

    final uniqueCollectionIds = collectionIds.toSet().toList(growable: false);

    await db.transaction((txn) async {
      await txn.delete(
        'favorite_collection_items',
        where: 'favorite_id = ? AND source_id = ?',
        whereArgs: [favoriteId, sourceId],
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final collectionId in uniqueCollectionIds) {
        await txn.insert(
          'favorite_collection_items',
          {
            'collection_id': collectionId,
            'favorite_id': favoriteId,
            'source_id': sourceId,
            'added_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (uniqueCollectionIds.isNotEmpty) {
        final placeholders =
            List.filled(uniqueCollectionIds.length, '?').join(',');
        await txn.rawUpdate(
          '''
            UPDATE favorite_collections
            SET updated_at = ?
            WHERE id IN ($placeholders)
          ''',
          [now, ...uniqueCollectionIds],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>>
      getFavoriteCollectionMembershipsForExport() async {
    final db = await _getSafeDatabase();
    if (db == null) {
      _logger.e('Database not available, cannot export memberships');
      return [];
    }

    final result = await db.query(
      'favorite_collection_items',
      orderBy: 'added_at DESC',
    );

    return result;
  }

  // ==================== DOWNLOAD OPERATIONS ====================

  // Save download status (with title and cover_url)
  Future<void> saveDownloadStatus(DownloadStatusModel status) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save download status');
        return;
      }

      await db.insert(
        'downloads',
        status.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.d('Saved download status for ${status.contentId}');
    } catch (e) {
      _logger.e('Error saving download status: $e');
      rethrow;
    }
  }

  // Get download status
  Future<DownloadStatusModel?> getDownloadStatus(String id) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot get download status');
        return null;
      }

      final result = await db.query(
        'downloads',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return DownloadStatusModel.fromMap(result.first);
    } catch (e) {
      _logger.e('Error getting download status: $e');
      return null;
    }
  }

  // Get all downloads with optional state and source filtering
  Future<List<DownloadStatusModel>> getAllDownloads({
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty downloads');
        return [];
      }

      // Build WHERE clause
      String whereClause = '1=1';
      final List<dynamic> whereArgs = [];

      if (state != null) {
        whereClause += ' AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause += ' AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      // Map orderBy field names to actual column names
      final columnName = _mapOrderByField(orderBy);
      final orderDirection = descending ? 'DESC' : 'ASC';
      final String orderClause = columnName == 'title'
          ? 'COALESCE(title, id) $orderDirection'
          : '$columnName $orderDirection';

      // Use raw query with GROUP BY to prevent duplicates
      // Group by id to ensure only one entry per content (in case of duplicate source_id entries)
      final sql = '''
        SELECT
          id,
          source_id,
          title,
          cover_url,
          download_path,
          state,
          downloaded_pages,
          total_pages,
          start_time,
          end_time,
          file_size,
          error_message,
          retry_count,
          start_page,
          end_page
        FROM downloads
        WHERE $whereClause
        GROUP BY id
        ORDER BY $orderClause
        LIMIT ? OFFSET ?
      ''';

      final result = await db.rawQuery(
        sql,
        [...whereArgs, limit, offset],
      );

      return result.map((row) => DownloadStatusModel.fromMap(row)).toList();
    } catch (e) {
      _logger.e('Error getting all downloads: $e');
      return [];
    }
  }

  // Map orderBy field to actual database column
  String _mapOrderByField(String orderBy) {
    switch (orderBy) {
      case 'created_at':
        return 'start_time'; // downloads table uses start_time
      case 'updated_at':
        return 'end_time';
      case 'content_id':
        return 'id';
      case 'title':
        return 'title'; // COALESCE(title, id) will be used in the query directly if needed
      case 'total_pages':
        return 'total_pages';
      default:
        return 'start_time'; // Default to start_time
    }
  }

  // Delete download status
  Future<void> deleteDownloadStatus(String id) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete download status');
        return;
      }

      await db.delete(
        'downloads',
        where: 'id = ?',
        whereArgs: [id],
      );

      _logger.d('Deleted download status for $id');
    } catch (e) {
      _logger.e('Error deleting download status: $e');
    }
  }

  // Get downloads count by state and source
  Future<int> getDownloadsCount(
      {DownloadState? state, String? sourceId}) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      String whereClause = '1=1';
      final List<dynamic> whereArgs = [];

      if (state != null) {
        whereClause += ' AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause += ' AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      // Count DISTINCT ids to avoid counting duplicates
      final result = await db.rawQuery(
        'SELECT COUNT(DISTINCT id) as count FROM downloads WHERE $whereClause',
        whereArgs.isNotEmpty ? whereArgs : null,
      );
      return result.first['count'] as int;
    } catch (e) {
      _logger.e('Error getting downloads count: $e');
      return 0;
    }
  }

  // Get total download size
  Future<int> getTotalDownloadSize(
      {DownloadState? state, String? sourceId}) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      String whereClause = '1=1';
      final List<dynamic> whereArgs = [];

      if (state != null) {
        whereClause += ' AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause += ' AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      final result = await db.rawQuery(
        'SELECT SUM(file_size) as total_size FROM downloads WHERE $whereClause',
        whereArgs.isNotEmpty ? whereArgs : null,
      );

      final totalKey = result.first['total_size'];
      if (totalKey != null) {
        return totalKey as int;
      }
      return 0;
    } catch (e) {
      _logger.e('Error getting total download size: $e');
      return 0;
    }
  }

  // Search downloads by query (id, title, or source_id) with pagination
  Future<List<Map<String, dynamic>>> searchDownloads({
    required String query,
    DownloadState? state,
    String? sourceId,
    int limit = 20,
    int offset = 0,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty search results');
        return [];
      }

      final queryPattern = '%${query.toLowerCase()}%';

      String whereClause =
          '(LOWER(id) LIKE ? OR LOWER(title) LIKE ? OR LOWER(source_id) LIKE ?)';
      final List<dynamic> whereArgs = [
        queryPattern,
        queryPattern,
        queryPattern
      ];

      if (state != null) {
        whereClause = '$whereClause AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause = '$whereClause AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      final String columnName = _mapOrderByField(orderBy);
      final String orderDirection = descending ? 'DESC' : 'ASC';
      final String orderClause = columnName == 'title'
          ? 'COALESCE(title, id) $orderDirection'
          : '$columnName $orderDirection';

      // Use raw query with GROUP BY to prevent duplicates
      final sql = '''
        SELECT
          id,
          source_id,
          title,
          cover_url,
          download_path,
          state,
          downloaded_pages,
          total_pages,
          start_time,
          end_time,
          file_size,
          error_message,
          retry_count,
          start_page,
          end_page
        FROM downloads
        WHERE $whereClause
        GROUP BY id
        ORDER BY $orderClause
        LIMIT ? OFFSET ?
      ''';

      final result = await db.rawQuery(
        sql,
        [...whereArgs, limit, offset],
      );

      _logger.d(
          'Search downloads found ${result.length} results for: $query (offset: $offset)');
      return result;
    } catch (e) {
      _logger.e('Error searching downloads: $e');
      return [];
    }
  }

  // Get total size of search results
  Future<int> getSearchDownloadSize({
    required String query,
    DownloadState? state,
    String? sourceId,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      final queryPattern = '%${query.toLowerCase()}%';

      String whereClause =
          '(LOWER(id) LIKE ? OR LOWER(title) LIKE ? OR LOWER(source_id) LIKE ?)';
      final List<dynamic> whereArgs = [
        queryPattern,
        queryPattern,
        queryPattern
      ];

      if (state != null) {
        whereClause = '$whereClause AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause = '$whereClause AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      final result = await db.rawQuery(
        'SELECT SUM(file_size) as total_size FROM downloads WHERE $whereClause',
        whereArgs,
      );

      final totalKey = result.first['total_size'];
      if (totalKey != null) {
        return totalKey as int;
      }
      return 0;
    } catch (e) {
      _logger.e('Error getting search download size: $e');
      return 0;
    }
  }

  // Get search results count
  Future<int> getSearchCount({
    required String query,
    DownloadState? state,
    String? sourceId,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      final queryPattern = '%${query.toLowerCase()}%';

      String whereClause =
          '(LOWER(id) LIKE ? OR LOWER(title) LIKE ? OR LOWER(source_id) LIKE ?)';
      final List<dynamic> whereArgs = [
        queryPattern,
        queryPattern,
        queryPattern
      ];

      if (state != null) {
        whereClause = '$whereClause AND state = ?';
        whereArgs.add(state.name);
      }

      if (sourceId != null) {
        whereClause = '$whereClause AND LOWER(source_id) = ?';
        whereArgs.add(sourceId.toLowerCase());
      }

      final result = await db.rawQuery(
        'SELECT COUNT(DISTINCT id) as count FROM downloads WHERE $whereClause',
        whereArgs,
      );
      return result.first['count'] as int;
    } catch (e) {
      _logger.e('Error getting search count: $e');
      return 0;
    }
  }

  // ==================== HISTORY OPERATIONS ====================

  // Save history entry (with title and cover_url)
  // For chapter mode content, chapterId is included in the primary key
  Future<void> saveHistory(HistoryModel history) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save history');
        return;
      }

      // Save entry with chapter_id (empty string for non-chapter mode)
      // With composite PK (id, source_id, chapter_id), this supports:
      // - Single entry for non-chapter content (chapter_id = '')
      // - Multiple entries for chapter content (different chapter_ids)
      await db.insert(
        'history',
        history.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // _logger.d(
      //     'Saved history for ${history.contentId} (Chapter: ${history.chapterId})');
    } catch (e) {
      _logger.e('Error saving history: $e');
      rethrow;
    }
  }

  // Get history entry by content ID
  // For chapter mode, returns the most recent chapter entry for this content
  Future<HistoryModel?> getHistory(String id) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return null;

      // First try to get the most recent entry for this content
      // This works for both chapter and non-chapter mode
      final result = await db.query(
        'history',
        where: 'id = ?',
        whereArgs: [id],
        orderBy: 'last_viewed DESC',
        limit: 1,
      );

      if (result.isEmpty) return null;
      return HistoryModel.fromMap(result.first);
    } catch (e) {
      _logger.e('Error getting history: $e');
      return null;
    }
  }

  // Get specific chapter history
  Future<HistoryModel?> getChapterHistory(String id, String chapterId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return null;

      final result = await db.query(
        'history',
        where: 'id = ? AND chapter_id = ?',
        whereArgs: [id, chapterId],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return HistoryModel.fromMap(result.first);
    } catch (e) {
      _logger.e('Error getting chapter history: $e');
      return null;
    }
  }

  // Get all chapter history for a content (series)
  // Now queries by parent_id since chapter entries use chapter.id as primary key
  Future<List<HistoryModel>> getContentChaptersHistory(String seriesId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return [];

      // Query by parent_id (series ID) to get all chapters
      // parent_id is set for chapter mode entries
      final result = await db.query(
        'history',
        where: 'parent_id = ? AND chapter_id != ?',
        whereArgs: [seriesId, ''],
        orderBy: 'chapter_index ASC',
      );

      _logger.d(
          'Found ${result.length} chapter history entries for series: $seriesId');
      return result.map((row) => HistoryModel.fromMap(row)).toList();
    } catch (e) {
      _logger.e('Error getting content chapters history: $e');
      return [];
    }
  }

  // Get all history entries
  // Returns all entries (both chapter and non-chapter) ordered by last viewed
  Future<List<HistoryModel>> getAllHistory({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty history');
        return [];
      }

      final offset = (page - 1) * limit;

      // Get all entries, including chapter entries
      // Each entry has composite PK (id, source_id, chapter_id)
      final result = await db.query(
        'history',
        orderBy: 'last_viewed DESC',
        limit: limit,
        offset: offset,
      );

      return result.map((row) => HistoryModel.fromMap(row)).toList();
    } catch (e) {
      _logger.e('Error getting all history: $e');
      return [];
    }
  }

  // Clear all history
  Future<void> clearHistory() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot clear history');
        return;
      }

      await db.delete('history');
      _logger.d('Cleared all history');
    } catch (e) {
      _logger.e('Error clearing history: $e');
    }
  }

  // Delete history entry
  // Deletes all entries (both main and chapters) for this content
  Future<void> deleteHistory(String id) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete history');
        return;
      }

      await db.delete(
        'history',
        where: 'id = ?',
        whereArgs: [id],
      );

      _logger.d('Deleted history for $id');
    } catch (e) {
      _logger.e('Error deleting history: $e');
    }
  }

  // Delete all history entries for a specific source
  Future<void> deleteHistoryBySourceId(String sourceId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete history by source');
        return;
      }

      await db.delete(
        'history',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );

      _logger.d('Deleted all history for source: $sourceId');
    } catch (e) {
      _logger.e('Error deleting history by source: $e');
    }
  }

  // Get history count
  Future<int> getHistoryCount() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) return 0;

      final result = await db.rawQuery('SELECT COUNT(*) as count FROM history');
      return result.first['count'] as int;
    } catch (e) {
      _logger.e('Error getting history count: $e');
      return 0;
    }
  }

  // ==================== PREFERENCES OPERATIONS ====================

  // Save user preferences
  Future<void> saveUserPreferences(UserPreferences preferences) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save preferences');
        return;
      }

      final batch = db.batch();

      final prefsMap = preferences.toJson();
      for (final entry in prefsMap.entries) {
        batch.insert(
          'preferences',
          {
            'key': entry.key,
            'value': entry.value.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Handle list preferences separately
      batch.insert(
        'preferences',
        {
          'key': 'blacklistedTags',
          'value': jsonEncode(preferences.blacklistedTags),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await batch.commit();
      _logger.d('Saved user preferences');
    } catch (e) {
      _logger.e('Error saving user preferences: $e');
      rethrow;
    }
  }

  // Get user preferences
  Future<UserPreferences> getUserPreferences() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning default preferences');
        return const UserPreferences();
      }

      final result = await db.query('preferences');

      final prefsMap = <String, dynamic>{};
      for (final row in result) {
        final key = row['key'] as String;
        final value = row['value'] as String;

        // Handle special cases for different data types
        if (key == 'blacklistedTags' || key == 'favoriteCategories') {
          try {
            prefsMap[key] = jsonDecode(value);
          } catch (e) {
            prefsMap[key] = <String>[];
          }
        } else if (_isBooleanField(key)) {
          prefsMap[key] = value.toLowerCase() == 'true';
        } else if (_isIntField(key)) {
          prefsMap[key] = int.tryParse(value) ?? _getDefaultIntValue(key);
        } else if (_isDoubleField(key)) {
          prefsMap[key] = double.tryParse(value) ?? _getDefaultDoubleValue(key);
        } else {
          prefsMap[key] = value;
        }
      }

      return UserPreferences.fromJson(prefsMap);
    } catch (e, stackTrace) {
      _logger.e('Error getting user preferences: $e');
      _logger.e('Stack trace: $stackTrace');
      return const UserPreferences(); // Return default preferences
    }
  }

  // Check if field should be boolean
  bool _isBooleanField(String key) {
    const boolFields = {
      'autoDownload',
      'showTitles',
      'blurThumbnails',
      'usePagination',
      'useVolumeKeys',
      'keepScreenOn',
      'showSystemUI',
      'autoBackup',
      'showNsfwContent',
      'readerInvertColors',
      'readerShowPageNumbers',
      'readerShowProgressBar',
      'readerAutoHideUI',
      'readerHideOnTap',
      'readerHideOnSwipe',
    };
    return boolFields.contains(key);
  }

  // Check if field should be integer
  bool _isIntField(String key) {
    const intFields = {
      'columnsPortrait',
      'columnsLandscape',
      'maxConcurrentDownloads',
      'readerAutoHideDelay',
    };
    return intFields.contains(key);
  }

  // Check if field should be double
  bool _isDoubleField(String key) {
    const doubleFields = {
      'readerBrightness',
    };
    return doubleFields.contains(key);
  }

  // Get default integer value for field
  int _getDefaultIntValue(String key) {
    switch (key) {
      case 'columnsPortrait':
        return 2;
      case 'columnsLandscape':
        return 3;
      case 'maxConcurrentDownloads':
        return 3;
      case 'readerAutoHideDelay':
        return 3;
      default:
        return 0;
    }
  }

  // Get default double value for field
  double _getDefaultDoubleValue(String key) {
    switch (key) {
      case 'readerBrightness':
        return 1.0;
      default:
        return 0.0;
    }
  }

  // Save single preference
  Future<void> savePreference(String key, String value) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save preference');
        return;
      }

      await db.insert(
        'preferences',
        {
          'key': key,
          'value': value,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.d('Saved preference: $key = $value');
    } catch (e) {
      _logger.e('Error saving preference: $e');
      rethrow;
    }
  }

  // Get single preference
  Future<String?> getPreference(String key) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot get preference');
        return null;
      }

      final result = await db.query(
        'preferences',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return result.first['value'] as String;
    } catch (e) {
      _logger.e('Error getting preference: $e');
      return null;
    }
  }

  // ==================== SEARCH HISTORY OPERATIONS ====================

  // Add search query to history
  Future<void> addSearchHistory(String query) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot add search history');
        return;
      }

      // Remove existing entry if it exists
      await db.delete(
        'search_history',
        where: 'query = ?',
        whereArgs: [query],
      );

      // Add new entry
      await db.insert('search_history', {
        'query': query,
        'searched_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Keep only last 50 searches
      await db.rawDelete('''
        DELETE FROM search_history 
        WHERE id NOT IN (
          SELECT id FROM search_history 
          ORDER BY searched_at DESC 
          LIMIT ${AppLimits.searchHistoryLimit}
        )
      ''');

      _logger.d('Added search history: $query');
    } catch (e) {
      _logger.e('Error adding search history: $e');
    }
  }

  // Get search history
  Future<List<String>> getSearchHistory({int? limit}) async {
    final effectiveLimit = limit ?? AppLimits.searchHistoryLimit;
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty search history');
        return [];
      }

      final result = await db.query(
        'search_history',
        columns: ['query'],
        orderBy: 'searched_at DESC',
        limit: effectiveLimit,
      );

      return result.map((row) => row['query'] as String).toList();
    } catch (e) {
      _logger.e('Error getting search history: $e');
      return [];
    }
  }

  // Clear search history
  Future<void> clearSearchHistory() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot clear search history');
        return;
      }

      await db.delete('search_history');
      _logger.d('Cleared search history');
    } catch (e) {
      _logger.e('Error clearing search history: $e');
    }
  }

  // Delete specific search history entry
  Future<void> deleteSearchHistory(String query) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete search history');
        return;
      }

      await db.delete(
        'search_history',
        where: 'query = ?',
        whereArgs: [query],
      );

      _logger.d('Deleted search history: $query');
    } catch (e) {
      _logger.e('Error deleting search history: $e');
    }
  }

  // ==================== SEARCH FILTER STATE PERSISTENCE ====================

  // Save search filter state for persistence with sourceId
  Future<void> saveSearchFilter(
      String sourceId, Map<String, dynamic> filterData) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save search filter');
        return;
      }

      await db.insert(
        'search_filter_state',
        {
          'source_id': sourceId,
          'filter_data': jsonEncode(filterData),
          'saved_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.d('Saved search filter state for $sourceId');
    } catch (e) {
      _logger.e('Error saving search filter: $e');
      rethrow;
    }
  }

  // Get last search filter state for a specific source
  Future<Map<String, dynamic>?> getLastSearchFilter(String sourceId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot get search filter');
        return null;
      }

      final result = await db.query(
        'search_filter_state',
        where: 'source_id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );

      if (result.isEmpty) return null;

      final filterDataString = result.first['filter_data'] as String? ?? '{}';
      final decoded = jsonDecode(filterDataString);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      _logger.e('Error getting search filter: $e');
      return null;
    }
  }

  // Clear search filter state for a specific source
  Future<void> removeLastSearchFilter(String sourceId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot clear search filter');
        return;
      }

      await db.delete(
        'search_filter_state',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      _logger.d('Cleared search filter state for $sourceId');
    } catch (e) {
      _logger.e('Error clearing search filter: $e');
    }
  }

  // ==================== UTILITY OPERATIONS ====================

  // Get database statistics
  Future<Map<String, int>> getDatabaseStats() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty stats');
        return {};
      }

      final stats = <String, int>{};

      // Count records in each table
      final tables = [
        'favorites',
        'downloads',
        'history',
        'search_history',
        'preferences',
      ];

      for (final table in tables) {
        final result =
            await db.rawQuery('SELECT COUNT(*) as count FROM $table');
        stats[table] = result.first['count'] as int;
      }

      return stats;
    } catch (e) {
      _logger.e('Error getting database stats: $e');
      return {};
    }
  }

  // Cleanup old data
  Future<void> cleanupOldData() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot cleanup old data');
        return;
      }

      final batch = db.batch();

      // Delete old search history (older than 30 days)
      final searchThreshold = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      batch.delete('search_history',
          where: 'searched_at < ?', whereArgs: [searchThreshold]);

      // Delete completed downloads older than 30 days
      final downloadThreshold = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      batch.delete('downloads',
          where: 'state = ? AND end_time < ?',
          whereArgs: ['completed', downloadThreshold]);

      await batch.commit();
      _logger.d('Cleaned up old data');
    } catch (e) {
      _logger.e('Error cleaning up old data: $e');
    }
  }

  // Clear all data except preferences
  Future<void> clearAllData() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot clear all data');
        return;
      }

      final batch = db.batch();

      // Clear all tables except preferences
      batch.delete('search_history');
      batch.delete('history');
      batch.delete('downloads');
      batch.delete('favorite_collection_items');
      batch.delete('favorite_collections');
      batch.delete('favorites');
      batch.delete('reader_positions');

      await batch.commit();
      _logger.i('All data cleared from database');
    } catch (e) {
      _logger.e('Error clearing all data: $e');
    }
  }

  // ==================== READER POSITION OPERATIONS ====================

  // Save reader position
  Future<void> saveReaderPosition(ReaderPositionModel position) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot save reader position');
        return;
      }

      await db.insert(
        'reader_positions',
        position.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.d('Saved reader position for ${position.contentId}');
    } catch (e) {
      _logger.e('Error saving reader position: $e');
      rethrow;
    }
  }

  // Get reader position by content ID
  Future<ReaderPositionModel?> getReaderPosition(String contentId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot get reader position');
        return null;
      }

      final result = await db.query(
        'reader_positions',
        where: 'content_id = ?',
        whereArgs: [contentId],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return ReaderPositionModel.fromMap(result.first);
    } catch (e) {
      _logger.e('Error getting reader position: $e');
      return null;
    }
  }

  // Get all reader positions
  Future<List<ReaderPositionModel>> getAllReaderPositions({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, returning empty reader positions');
        return [];
      }

      final offset = (page - 1) * limit;

      final result = await db.query(
        'reader_positions',
        orderBy: 'last_accessed DESC',
        limit: limit,
        offset: offset,
      );

      return result.map((row) => ReaderPositionModel.fromMap(row)).toList();
    } catch (e) {
      _logger.e('Error getting all reader positions: $e');
      return [];
    }
  }

  // Delete reader position
  Future<void> deleteReaderPosition(String contentId) async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot delete reader position');
        return;
      }

      await db.delete(
        'reader_positions',
        where: 'content_id = ?',
        whereArgs: [contentId],
      );

      _logger.d('Deleted reader position for $contentId');
    } catch (e) {
      _logger.e('Error deleting reader position: $e');
    }
  }

  // Clear all reader positions
  Future<void> clearAllReaderPositions() async {
    try {
      final db = await _getSafeDatabase();
      if (db == null) {
        _logger.e('Database not available, cannot clear reader positions');
        return;
      }

      await db.delete('reader_positions');
      _logger.d('Cleared all reader positions');
    } catch (e) {
      _logger.e('Error clearing reader positions: $e');
    }
  }

  FavoriteCollection _mapFavoriteCollection(Map<String, Object?> row) {
    final createdAtMs = int.tryParse(row['created_at']?.toString() ?? '') ?? 0;
    final updatedAtMs =
        int.tryParse(row['updated_at']?.toString() ?? '') ?? createdAtMs;
    final itemCount = int.tryParse(row['item_count']?.toString() ?? '') ?? 0;

    return FavoriteCollection(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      itemCount: itemCount,
    );
  }
}
