import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';

// Database helper class for managing SQLite database
class DatabaseHelper {
  static const String _databaseName = 'nhasix_app.db';
  static const int _databaseVersion =
      15; // v15: content_tags + recommendation_history for local recommendations

  static Database? _database;
  static final Logger _logger = getIt<Logger>();

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // Get database instance
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  // Get database path
  Future<String> getDatabasePath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return '${documentsDirectory.path}/$_databaseName';
  }

  // Initialize database
  Future<Database> _initDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = '${documentsDirectory.path}/$_databaseName';

      _logger.i('Initializing database at: $path');

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
        onOpen: (db) async {
          _logger.i('Database opened successfully');
        },
      );
    } catch (e) {
      _logger.e('Error initializing database: $e');

      // If database initialization fails, try to delete the corrupted database file
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final path = '${documentsDirectory.path}/$_databaseName';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          _logger
              .w('Deleted corrupted database file, attempting to recreate...');

          // Try to initialize again
          return await openDatabase(
            path,
            version: _databaseVersion,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
            onConfigure: _onConfigure,
            onOpen: (db) async {
              _logger.i('Database recreated and opened successfully');
            },
          );
        }
      } catch (deleteError) {
        _logger.e('Error deleting corrupted database: $deleteError');
      }

      rethrow;
    }
  }

  // Configure database settings
  Future<void> _onConfigure(Database db) async {
    try {
      // Enable foreign key constraints
      await db.rawQuery('PRAGMA foreign_keys = ON');

      // Set journal mode to WAL for better performance
      await db.rawQuery('PRAGMA journal_mode = WAL');

      // Set synchronous mode to NORMAL for better performance
      await db.rawQuery('PRAGMA synchronous = NORMAL');

      // Set cache size to 10MB
      await db.rawQuery('PRAGMA cache_size = -10000');

      _logger.d('Database configuration completed successfully');
    } catch (e) {
      _logger.e('Error configuring database: $e');
      // Don't rethrow here as it might prevent database initialization
    }
  }

  // Create database tables
  Future<void> _onCreate(Database db, int version) async {
    _logger.i('Creating database tables...');

    final batch = db.batch();

    // Create essential tables only
    _createFavoritesTable(batch);
    _createFavoriteCollectionsTable(batch);
    _createFavoriteCollectionItemsTable(batch);
    _createDownloadsTable(batch);
    _createHistoryTable(batch);
    _createPreferencesTable(batch);
    _createSearchHistoryTable(batch);
    _createSearchFilterStateTable(batch);
    _createReaderPositionsTable(batch);
    _createDoujinListTable(batch);
    _createTranslationCacheTable(batch);
    _createContentTagsTable(batch);
    _createRecommendationHistoryTable(batch);

    // Create indexes
    _createIndexes(batch);

    // Insert default data
    _insertDefaultData(batch);

    await batch.commit();
    _logger.i('Database tables created successfully');
  }

  // Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i('Upgrading database from version $oldVersion to $newVersion');

    // Handle specific version upgrades
    if (oldVersion < 3 && newVersion >= 3) {
      // Add search_filter_state table in version 3
      await db.execute('''
        CREATE TABLE search_filter_state (
          id INTEGER PRIMARY KEY DEFAULT 1,
          filter_data TEXT, -- JSON serialized SearchFilter
          saved_at INTEGER
        )
      ''');
      _logger.i('Added search_filter_state table in database upgrade');
    }

    if (oldVersion < 5 && newVersion >= 5) {
      // Add range download columns to downloads table in version 5
      try {
        await db.execute(
            'ALTER TABLE downloads ADD COLUMN retry_count INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE downloads ADD COLUMN start_page INTEGER');
        await db.execute('ALTER TABLE downloads ADD COLUMN end_page INTEGER');
        _logger.i(
            'Added range download columns to downloads table in database upgrade');
      } catch (e) {
        _logger
            .w('Error adding range download columns (may already exist): $e');
      }
    }

    if (oldVersion < 6 && newVersion >= 6) {
      // Add reader_positions table in version 6
      try {
        await db.execute('''
          CREATE TABLE reader_positions (
            content_id TEXT PRIMARY KEY,
            current_page INTEGER NOT NULL,
            total_pages INTEGER NOT NULL,
            last_accessed INTEGER NOT NULL,
            reading_progress REAL DEFAULT 0.0,
            reading_time_minutes INTEGER DEFAULT 0,
            title TEXT,
            cover_url TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        // Create index for reader positions
        await db.execute(
            'CREATE INDEX idx_reader_positions_last_accessed ON reader_positions (last_accessed DESC)');

        _logger.i('Added reader_positions table in database upgrade');
      } catch (e) {
        _logger
            .w('Error adding reader_positions table (may already exist): $e');
      }
    }

    // Version 7: Add source_id column for multi-source support
    if (oldVersion < 7 && newVersion >= 7) {
      _logger.i(
          'Upgrading to version 7: Adding source_id columns for multi-source support');

      try {
        // Add source_id to favorites table
        await db.execute(
            "ALTER TABLE favorites ADD COLUMN source_id TEXT DEFAULT 'nhentai'");
        _logger.d('Added source_id column to favorites table');
      } catch (e) {
        _logger
            .w('Error adding source_id to favorites (may already exist): $e');
      }

      try {
        // Add source_id to history table
        await db.execute(
            "ALTER TABLE history ADD COLUMN source_id TEXT DEFAULT 'nhentai'");
        _logger.d('Added source_id column to history table');
      } catch (e) {
        _logger.w('Error adding source_id to history (may already exist): $e');
      }

      try {
        // Add source_id to downloads table
        await db.execute(
            "ALTER TABLE downloads ADD COLUMN source_id TEXT DEFAULT 'nhentai'");
        _logger.d('Added source_id column to downloads table');
      } catch (e) {
        _logger
            .w('Error adding source_id to downloads (may already exist): $e');
      }

      try {
        // Add source_id to reader_positions table
        await db.execute(
            "ALTER TABLE reader_positions ADD COLUMN source_id TEXT DEFAULT 'nhentai'");
        _logger.d('Added source_id column to reader_positions table');
      } catch (e) {
        _logger.w(
            'Error adding source_id to reader_positions (may already exist): $e');
      }

      try {
        // Create composite indexes for source_id queries
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_favorites_source ON favorites (source_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_history_source ON history (source_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_downloads_source ON downloads (source_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_reader_source ON reader_positions (source_id)');
        _logger.d('Created source_id indexes');
      } catch (e) {
        _logger.w('Error creating source_id indexes: $e');
      }

      _logger.i('Database upgrade to version 7 completed successfully');
    }

    // Fix history table schema if needed (for any version upgrade)
    try {
      // Check if history table has the correct schema
      final historyColumns = await db.rawQuery('PRAGMA table_info(history)');
      final hasIdColumn = historyColumns.any((col) => col['name'] == 'id');

      if (!hasIdColumn) {
        _logger.w('History table missing id column, recreating table...');

        // Backup existing data
        final existingData = await db.query('history');

        // Drop and recreate history table
        await db.execute('DROP TABLE IF EXISTS history');
        await db.execute('''
          CREATE TABLE history (
            id TEXT PRIMARY KEY,
            title TEXT,
            cover_url TEXT,
            last_viewed INTEGER,
            last_page INTEGER DEFAULT 1,
            total_pages INTEGER,
            time_spent INTEGER DEFAULT 0,
            is_completed INTEGER DEFAULT 0
          )
        ''');

        // Restore data with proper column mapping
        for (final row in existingData) {
          await db.insert('history', {
            'id': row['content_id'] ??
                row['id'], // Handle both old and new column names
            'title': row['title'],
            'cover_url': row['cover_url'],
            'last_viewed': row['last_viewed'],
            'last_page': row['last_page'] ?? 1,
            'total_pages': row['total_pages'] ?? 0,
            'time_spent': row['time_spent'] ?? 0,
            'is_completed': row['is_completed'] ?? 0,
          });
        }

        // Recreate index
        await db.execute(
            'CREATE INDEX idx_history_last_viewed ON history (last_viewed DESC)');
        await db.execute(
            'CREATE INDEX idx_history_is_completed ON history (is_completed)');

        _logger.i('History table schema fixed successfully');
      }
    } catch (e) {
      _logger.e('Error fixing history table schema: $e');
      // If fixing fails, recreate the entire database
      await _dropAllTables(db);
      await _onCreate(db, newVersion);
    }

    // For major version changes, recreate database
    if (oldVersion < newVersion && (newVersion - oldVersion) > 2) {
      await _dropAllTables(db);
      await _onCreate(db, newVersion);
    }

    // Version 8: Update search_filter_state to support per-source storage
    if (oldVersion < 8 && newVersion >= 8) {
      _logger.i(
          'Upgrading to version 8: Updating search_filter_state for multi-source support');

      try {
        // Drop existing table and recreate with source_id
        await db.execute('DROP TABLE IF EXISTS search_filter_state');

        await db.execute('''
          CREATE TABLE search_filter_state (
            source_id TEXT PRIMARY KEY,
            filter_data TEXT, -- JSON serialized SearchFilter
            saved_at INTEGER
          )
        ''');

        _logger.i('Updated search_filter_state table schema successfully');
      } catch (e) {
        _logger.e('Error upgrading search_filter_state table: $e');
      }
    }

    if (oldVersion < 9 && newVersion >= 9) {
      _logger.i('Upgrading to version 9: Adding doujin_list table');
      try {
        await db.execute('''
          CREATE TABLE doujin_list (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            updated_at INTEGER
          )
        ''');
        _logger.i('Added doujin_list table');
      } catch (e) {
        _logger.w('Error adding doujin_list table: $e');
      }
    }

    if (oldVersion < 10 && newVersion >= 10) {
      _logger
          .i('Upgrading to version 10: Adding title column to favorites table');
      try {
        // Add title column
        await db.execute('ALTER TABLE favorites ADD COLUMN title TEXT');
        _logger.i('Added title column to favorites table');

        // Attempt to backfill titles from history and downloads
        await db.execute('''
          UPDATE favorites 
          SET title = (
            SELECT COALESCE(h.title, d.title)
            FROM favorites f2
            LEFT JOIN history h ON f2.id = h.id AND f2.source_id = h.source_id
            LEFT JOIN downloads d ON f2.id = d.id AND f2.source_id = d.source_id
            WHERE f2.id = favorites.id AND f2.source_id = favorites.source_id
          )
          WHERE title IS NULL
        ''');
        _logger.i('Backfilled titles for existing favorites');
      } catch (e) {
        _logger.e('Error upgrading favorites table: $e');
      }
    }
    if (oldVersion < 11 && newVersion >= 11) {
      _logger.i('Upgrading to version 11: Adding chapter support to history');
      try {
        await db.transaction((txn) async {
          // 1. Rename existing table
          await txn.execute('ALTER TABLE history RENAME TO history_old');

          // 2. Create new table with new Schema and PK
          await txn.execute('''
            CREATE TABLE history (
              id TEXT NOT NULL,
              source_id TEXT NOT NULL DEFAULT 'nhentai',
              title TEXT,
              cover_url TEXT,
              last_viewed INTEGER,
              last_page INTEGER DEFAULT 1,
              total_pages INTEGER,
              time_spent INTEGER DEFAULT 0,
              is_completed INTEGER DEFAULT 0,
              chapter_id TEXT NOT NULL DEFAULT '',
              chapter_index INTEGER DEFAULT 0,
              chapter_title TEXT,
              PRIMARY KEY (id, source_id, chapter_id)
            )
          ''');

          // 3. Copy data
          // Set chapter_id to empty string for existing records (content-level history)
          await txn.execute('''
            INSERT INTO history (
              id, source_id, title, cover_url, last_viewed, last_page, 
              total_pages, time_spent, is_completed, chapter_id
            )
            SELECT 
              id, source_id, title, cover_url, last_viewed, last_page, 
              total_pages, time_spent, is_completed, '' 
            FROM history_old
          ''');

          // 4. Drop old table
          await txn.execute('DROP TABLE history_old');

          // 5. Recreate Indexes
          await txn.execute(
              'CREATE INDEX idx_history_last_viewed ON history (last_viewed DESC)');
          await txn.execute(
              'CREATE INDEX idx_history_is_completed ON history (is_completed)');
          await txn.execute(
              'CREATE INDEX idx_history_source ON history (source_id)');
          await txn.execute(
              'CREATE INDEX idx_history_chapter_lookup ON history (id, chapter_id)');
        });

        _logger.i('Successfully migrated history table to version 11');
      } catch (e) {
        _logger.e('Error upgrading history table: $e');
        rethrow;
      }
    }

    if (oldVersion < 12 && newVersion >= 12) {
      _logger.i('Upgrading to version 12: Adding parent_id to history');
      try {
        // Add parent_id column to track series/parent content for chapters
        await db.execute('ALTER TABLE history ADD COLUMN parent_id TEXT');
        _logger.i('Added parent_id column to history table');

        // Create index for parent_id lookups
        await db
            .execute('CREATE INDEX idx_history_parent ON history (parent_id)');
        _logger.i('Created index on parent_id');
      } catch (e) {
        _logger.w('Error adding parent_id column: $e');
      }
    }

    if (oldVersion < 14 && newVersion >= 14) {
      _logger.i('Upgrading to version 14: Adding translation_cache table');
      try {
        await db.execute('''
          CREATE TABLE translation_cache (
            cache_key   TEXT PRIMARY KEY,
            content_id  TEXT NOT NULL,
            page_index  INTEGER NOT NULL,
            result_json TEXT NOT NULL,
            created_at  INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_tc_content ON translation_cache(content_id)');
        _logger.i('translation_cache table created successfully');
      } catch (e) {
        _logger.e('Error creating translation_cache table: $e');
        rethrow;
      }
    }

    if (oldVersion < 15 && newVersion >= 15) {
      _logger.i(
          'Upgrading to version 15: Adding content_tags + recommendation_history');
      try {
        await db.execute('''
          CREATE TABLE content_tags (
            content_id TEXT NOT NULL,
            source_id TEXT NOT NULL DEFAULT 'nhentai',
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'tag',
            origin TEXT NOT NULL DEFAULT 'history',
            PRIMARY KEY (content_id, source_id, name)
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_content_tags_name ON content_tags (name)');
        await db.execute(
            'CREATE INDEX idx_content_tags_content ON content_tags (content_id, source_id)');
        await db.execute('''
          CREATE TABLE recommendation_history (
            content_id TEXT NOT NULL,
            source_id TEXT NOT NULL DEFAULT 'nhentai',
            shown_at INTEGER,
            tapped_at INTEGER,
            dismissed INTEGER NOT NULL DEFAULT 0,
            dismissed_at INTEGER,
            PRIMARY KEY (content_id, source_id)
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_rec_hist_shown ON recommendation_history (shown_at DESC)');
        _logger.i('content_tags + recommendation_history created successfully');
      } catch (e) {
        _logger.e('Error creating recommendation tables: $e');
        rethrow;
      }
    }

    if (oldVersion < 13 && newVersion >= 13) {
      _logger.i('Upgrading to version 13: Adding favorite collections tables');
      try {
        await db.execute('''
          CREATE TABLE favorite_collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE favorite_collection_items (
            collection_id TEXT NOT NULL,
            favorite_id TEXT NOT NULL,
            source_id TEXT NOT NULL DEFAULT 'nhentai',
            added_at INTEGER NOT NULL,
            PRIMARY KEY (collection_id, favorite_id, source_id),
            FOREIGN KEY (collection_id) REFERENCES favorite_collections(id) ON DELETE CASCADE,
            FOREIGN KEY (favorite_id, source_id) REFERENCES favorites(id, source_id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
            'CREATE INDEX idx_favorite_collections_name ON favorite_collections (name)');
        await db.execute(
            'CREATE INDEX idx_collection_items_collection ON favorite_collection_items (collection_id)');
        await db.execute(
            'CREATE INDEX idx_collection_items_favorite ON favorite_collection_items (favorite_id, source_id)');

        _logger.i('Favorite collections tables created successfully');
      } catch (e) {
        _logger.e('Error upgrading favorite collections tables: $e');
        rethrow;
      }
    }
  }

  // Create favorites table with source_id for multi-source support
  void _createFavoritesTable(Batch batch) {
    batch.execute('''
      CREATE TABLE favorites (
        id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        title TEXT,
        cover_url TEXT,
        added_at INTEGER,
        PRIMARY KEY (id, source_id)
      )
    ''');
  }

  void _createFavoriteCollectionsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE favorite_collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  void _createFavoriteCollectionItemsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE favorite_collection_items (
        collection_id TEXT NOT NULL,
        favorite_id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        added_at INTEGER NOT NULL,
        PRIMARY KEY (collection_id, favorite_id, source_id),
        FOREIGN KEY (collection_id) REFERENCES favorite_collections(id) ON DELETE CASCADE,
        FOREIGN KEY (favorite_id, source_id) REFERENCES favorites(id, source_id) ON DELETE CASCADE
      )
    ''');
  }

  // Create downloads table with source_id for multi-source support
  void _createDownloadsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE downloads (
        id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        title TEXT,
        cover_url TEXT,
        download_path TEXT,
        state TEXT NOT NULL, -- queued, downloading, paused, completed, failed, cancelled
        downloaded_pages INTEGER DEFAULT 0,
        total_pages INTEGER,
        start_time INTEGER,
        end_time INTEGER,
        file_size INTEGER,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        start_page INTEGER,
        end_page INTEGER,
        PRIMARY KEY (id, source_id)
      )
    ''');
  }

  // Create history table with source_id for multi-source support
  void _createHistoryTable(Batch batch) {
    batch.execute('''
      CREATE TABLE history (
        id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        title TEXT,
        cover_url TEXT,
        last_viewed INTEGER,
        last_page INTEGER DEFAULT 1,
        total_pages INTEGER,
        time_spent INTEGER DEFAULT 0,
        is_completed INTEGER DEFAULT 0,
        chapter_id TEXT NOT NULL DEFAULT '',
        chapter_index INTEGER DEFAULT 0,
        chapter_title TEXT,
        parent_id TEXT,
        PRIMARY KEY (id, source_id, chapter_id)
      )
    ''');
  }

  // Create preferences table
  void _createPreferencesTable(Batch batch) {
    batch.execute('''
      CREATE TABLE preferences (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // Create search history table
  void _createSearchHistoryTable(Batch batch) {
    batch.execute('''
      CREATE TABLE search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        searched_at INTEGER
      )
    ''');
  }

  // Create search filter state table
  void _createSearchFilterStateTable(Batch batch) {
    batch.execute('''
      CREATE TABLE search_filter_state (
        source_id TEXT PRIMARY KEY,
        filter_data TEXT, -- JSON serialized SearchFilter
        saved_at INTEGER
      )
    ''');
  }

  // Create reader positions table with source_id for multi-source support
  void _createReaderPositionsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE reader_positions (
        content_id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        current_page INTEGER NOT NULL,
        total_pages INTEGER NOT NULL,
        last_accessed INTEGER NOT NULL,
        reading_progress REAL DEFAULT 0.0,
        reading_time_minutes INTEGER DEFAULT 0,
        title TEXT,
        cover_url TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (content_id, source_id)
      )
    ''');
  }

  // Create doujin list table for Crotpedia
  void _createDoujinListTable(Batch batch) {
    batch.execute('''
      CREATE TABLE doujin_list (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        updated_at INTEGER
      )
    ''');
  }

  // Create translation cache table for AI page translation
  void _createTranslationCacheTable(Batch batch) {
    batch.execute('''
      CREATE TABLE translation_cache (
        cache_key   TEXT PRIMARY KEY,
        content_id  TEXT NOT NULL,
        page_index  INTEGER NOT NULL,
        result_json TEXT NOT NULL,
        created_at  INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_tc_content ON translation_cache(content_id)');
  }

  // Create content_tags table for the local recommendation engine.
  // One row per (content, tag). Deliberately NO foreign keys: tags are also
  // written for downloads/metadata that may have no history/favorite row.
  // Tag names are normalized (lowercase, trimmed) by the writer, not here.
  void _createContentTagsTable(Batch batch) {
    batch.execute('''
      CREATE TABLE content_tags (
        content_id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'tag',
        origin TEXT NOT NULL DEFAULT 'history',
        PRIMARY KEY (content_id, source_id, name)
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_content_tags_name ON content_tags (name)');
    batch.execute(
        'CREATE INDEX idx_content_tags_content ON content_tags (content_id, source_id)');
  }

  // Tracks shown/tapped/dismissed recommendations for dedup windows
  // (shown 24h, dismissed 30 days). One row per content, updated in place.
  void _createRecommendationHistoryTable(Batch batch) {
    batch.execute('''
      CREATE TABLE recommendation_history (
        content_id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT 'nhentai',
        shown_at INTEGER,
        tapped_at INTEGER,
        dismissed INTEGER NOT NULL DEFAULT 0,
        dismissed_at INTEGER,
        PRIMARY KEY (content_id, source_id)
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_rec_hist_shown ON recommendation_history (shown_at DESC)');
  }

  // Create database indexes for performance
  void _createIndexes(Batch batch) {
    // Favorites indexes
    batch.execute(
        'CREATE INDEX idx_favorites_added_at ON favorites (added_at DESC)');
    batch.execute('CREATE INDEX idx_favorites_source ON favorites (source_id)');
    batch.execute(
        'CREATE INDEX idx_favorite_collections_name ON favorite_collections (name)');
    batch.execute(
        'CREATE INDEX idx_collection_items_collection ON favorite_collection_items (collection_id)');
    batch.execute(
        'CREATE INDEX idx_collection_items_favorite ON favorite_collection_items (favorite_id, source_id)');

    // Downloads indexes
    batch.execute('CREATE INDEX idx_downloads_state ON downloads (state)');
    batch.execute(
        'CREATE INDEX idx_downloads_start_time ON downloads (start_time DESC)');
    batch.execute(
        'CREATE INDEX idx_downloads_state_start_time ON downloads (state, start_time DESC)'); // NEW: For pagination
    batch.execute('CREATE INDEX idx_downloads_source ON downloads (source_id)');

    // History indexes
    batch.execute(
        'CREATE INDEX idx_history_last_viewed ON history (last_viewed DESC)');
    batch.execute(
        'CREATE INDEX idx_history_is_completed ON history (is_completed)');
    batch.execute('CREATE INDEX idx_history_source ON history (source_id)');

    // Search history indexes
    batch.execute(
        'CREATE INDEX idx_search_history_searched_at ON search_history (searched_at DESC)');

    // Reader positions indexes
    batch.execute(
        'CREATE INDEX idx_reader_positions_last_accessed ON reader_positions (last_accessed DESC)');
    batch.execute(
        'CREATE INDEX idx_reader_source ON reader_positions (source_id)');
  }

  // Insert default data
  void _insertDefaultData(Batch batch) {
    // Insert default preferences
    final defaultPreferences = {
      'theme': 'dark',
      'defaultLanguage': 'english',
      'imageQuality': 'high',
      'autoDownload': 'false',
      'showTitles': 'true',
      'blurThumbnails': 'false',
      'infiniteScroll': 'true',
      'columnsPortrait': '2',
      'columnsLandscape': '3',
      'useVolumeKeys': 'false',
      'readingDirection': 'leftToRight',
      'keepScreenOn': 'false',
      'showSystemUI': 'true',
      'maxConcurrentDownloads': '3',
      'autoBackup': 'false',
      'showNsfwContent': 'true',
    };

    for (final entry in defaultPreferences.entries) {
      batch.insert('preferences', {
        'key': entry.key,
        'value': entry.value,
      });
    }
  }

  // Drop all tables (for database recreation)
  Future<void> _dropAllTables(Database db) async {
    final tables = [
      'search_filter_state',
      'search_history',
      'preferences',
      'history',
      'downloads',
      'favorite_collection_items',
      'favorite_collections',
      'favorites',
      'translation_cache',
      'content_tags',
      'recommendation_history',
    ];

    for (final table in tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  // Close database connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _logger.i('Database connection closed');
    }
  }

  // Clear all data (for testing or reset)
  Future<void> clearAllData() async {
    final db = await database;
    final batch = db.batch();

    // Clear all tables except preferences
    batch.delete('search_filter_state');
    batch.delete('search_history');
    batch.delete('history');
    batch.delete('downloads');
    batch.delete('favorite_collection_items');
    batch.delete('favorite_collections');
    batch.delete('favorites');
    batch.delete('doujin_list');
    batch.delete('content_tags');
    batch.delete('recommendation_history');

    await batch.commit();
    _logger.i('All data cleared from database');
  }

  // Get database file size
  Future<int> getDatabaseSize() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = '${documentsDirectory.path}/$_databaseName';
      final file = File(path);

      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      _logger.e('Error getting database size: $e');
      return 0;
    }
  }

  // Vacuum database to reclaim space
  Future<void> vacuum() async {
    try {
      final db = await database;
      await db.rawQuery('VACUUM');
      _logger.i('Database vacuumed successfully');
    } catch (e) {
      _logger.e('Error vacuuming database: $e');
    }
  }

  // Check database integrity
  Future<bool> checkIntegrity() async {
    try {
      final db = await database;
      final result = await db.rawQuery('PRAGMA integrity_check');
      final isOk = result.isNotEmpty && result.first.values.first == 'ok';

      if (isOk) {
        _logger.i('Database integrity check passed');
      } else {
        _logger.w('Database integrity check failed: $result');
      }

      return isOk;
    } catch (e) {
      _logger.e('Error checking database integrity: $e');
      return false;
    }
  }

  // Reset database by deleting and recreating it
  Future<void> resetDatabase() async {
    try {
      // Close existing connection
      await close();

      // Delete database file
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = '${documentsDirectory.path}/$_databaseName';
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
        _logger.i('Database file deleted');
      }

      // Reinitialize database
      _database = await _initDatabase();
      _logger.i('Database reset completed');
    } catch (e) {
      _logger.e('Error resetting database: $e');
      rethrow;
    }
  }
}
