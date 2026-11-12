import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nhasixapp/core/services/report/report_builder.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';

/// One recorded error-response row (`error_log` table, DDL owned by Grup 1).
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.id,
    required this.createdAt,
    required this.sourceId,
    required this.feature,
    this.statusCode,
    required this.message,
    this.urlPath = '',
    this.appVersion = '',
  });

  final int id;
  final DateTime createdAt;
  final String sourceId;
  final String feature;
  final int? statusCode;
  final String message;
  final String urlPath;
  final String appVersion;

  factory ErrorLogEntry.fromMap(Map<String, Object?> map) => ErrorLogEntry(
    id: (map['id'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ?? 0,
    ),
    sourceId: map['sourceId'] as String? ?? '',
    feature: map['feature'] as String? ?? '',
    statusCode: (map['statusCode'] as num?)?.toInt(),
    message: map['message'] as String? ?? '',
    urlPath: map['urlPath'] as String? ?? '',
    appVersion: map['appVersion'] as String? ?? '',
  );
}

/// Opt-in ring buffer of real error responses (Keputusan 6).
///
/// Recorded: repository exceptions, HTTP 5xx, timeout/DNS failures and
/// non-challenge parse failures. Never recorded: CF/Turnstile challenges
/// (any status), 403 WAF, login-walls, valid-empty responses, and
/// failures already owned by the anomaly discriminators.
///
/// Toggle off (the default) means *zero writes* — [record] returns before
/// touching the database. Cap: [maxEntries] rows or [maxBytes], whichever
/// is reached first; the oldest rows are pruned FIFO.
class ErrorLog {
  ErrorLog._();

  static const String tableName = 'error_log';

  /// SharedPreferences key for the Settings toggle (default off).
  static const String prefKeyEnabled = 'error_log_enabled';

  /// Row cap of the ring buffer.
  static const int maxEntries = 200;

  /// Byte budget of the ring buffer (1 MB).
  static const int maxBytes = 1024 * 1024;

  /// Anything longer is truncated before storage — one stack trace must
  /// not be able to eat the whole budget.
  static const int maxMessageLength = 2000;

  static final Logger _logger = Logger();

  static const List<String> _pruneColumns = [
    'id',
    'sourceId',
    'feature',
    'message',
    'urlPath',
    'appVersion',
  ];

  /// Statuses that are never real errors: 401 login-wall, 403 WAF.
  static const List<int> _excludedStatusCodes = [401, 403];

  /// Substrings (lower-cased) marking a challenge / login-wall page. These
  /// are protections working as designed, not app bugs.
  static const List<String> _excludedMarkers = [
    'challenge',
    'cloudflare',
    'cf-clearance',
    'cf_clearance',
    'turnstile',
    'captcha',
    'just a moment',
    'checking your browser',
    'attention required',
    'loginrequired',
    'login required',
    'login_required',
    'unauthorized',
  ];

  static DatabaseHelper? _dbHelperOverride;
  static bool? _enabledCache;
  static String? _appVersionOverride;
  static String _cachedAppVersion = '';
  static Future<SharedPreferences>? _prefsFuture;

  /// Test seam: point the store at a mocked helper and/or force the toggle.
  @visibleForTesting
  static void debugConfigure({
    DatabaseHelper? dbHelper,
    bool? enabled,
    String? appVersion,
  }) {
    _dbHelperOverride = dbHelper ?? _dbHelperOverride;
    _enabledCache = enabled ?? _enabledCache;
    _appVersionOverride = appVersion ?? _appVersionOverride;
  }

  /// Test seam: forget every override and cached value.
  @visibleForTesting
  static void debugReset() {
    _dbHelperOverride = null;
    _enabledCache = null;
    _appVersionOverride = null;
    _cachedAppVersion = '';
    _prefsFuture = null;
  }

  /// Whether error logging is on (default off). Never throws.
  static Future<bool> isEnabled() async {
    final cached = _enabledCache;
    if (cached != null) return cached;
    try {
      final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
      final value = prefs.getBool(prefKeyEnabled) ?? false;
      _enabledCache = value;
      return value;
    } catch (e) {
      _logger.w('ErrorLog.isEnabled failed: $e');
      return false;
    }
  }

  /// Persists the Settings toggle. Off stops every write immediately.
  static Future<void> setEnabled(bool v) async {
    _enabledCache = v;
    try {
      final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
      await prefs.setBool(prefKeyEnabled, v);
    } catch (e) {
      _logger.w('ErrorLog.setEnabled failed: $e');
    }
  }

  /// Records one real error response. No-op when disabled or excluded.
  ///
  /// Fire-and-forget by design: callers sit inside repository `catch`
  /// blocks, so this never throws and never changes their return value.
  static Future<void> record({
    required String sourceId,
    required String feature,
    int? statusCode,
    required String message,
    String? urlPath,
  }) async {
    try {
      if (!await isEnabled()) return;

      final text = message.length > maxMessageLength
          ? message.substring(0, maxMessageLength)
          : message;
      if (isExcluded(statusCode: statusCode, message: text)) return;

      final db = await _db();
      if (db == null) return;

      await db.insert(tableName, {
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'sourceId': sourceId,
        'feature': feature,
        'statusCode': statusCode,
        'message': text,
        'urlPath': ReportBuilder.pathOnly(urlPath),
        'appVersion': await _appVersion(),
      });

      await _prune(db);
    } catch (e) {
      _logger.w('ErrorLog.record failed: $e');
    }
  }

  /// Pure exclusion rule (spec "Error-response logging opt-in dengan
  /// pengecualian jelas"): protections and valid-empty answers are not
  /// app errors.
  static bool isExcluded({int? statusCode, required String message}) {
    if (statusCode != null && _excludedStatusCodes.contains(statusCode)) {
      return true;
    }
    final lowered = message.toLowerCase();
    for (final marker in _excludedMarkers) {
      if (lowered.contains(marker)) return true;
    }
    return false;
  }

  /// Stored entries, newest first.
  static Future<List<ErrorLogEntry>> entries({int limit = 100}) async {
    try {
      final db = await _db();
      if (db == null) return const [];
      final rows = await db.query(
        tableName,
        orderBy: 'createdAt DESC, id DESC',
        limit: limit,
      );
      return rows.map(ErrorLogEntry.fromMap).toList();
    } catch (e) {
      _logger.w('ErrorLog.entries failed: $e');
      return const [];
    }
  }

  /// Removes one entry (user action in Settings).
  static Future<void> deleteEntry(int id) async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      _logger.w('ErrorLog.deleteEntry failed: $e');
    }
  }

  /// Empties the ring buffer (user action in Settings).
  static Future<void> clearAll() async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(tableName);
    } catch (e) {
      _logger.w('ErrorLog.clearAll failed: $e');
    }
  }

  /// Plain-text dump for the user's own export action. Never uploaded.
  static Future<String> exportText() async {
    try {
      final rows = await entries(limit: maxEntries);
      if (rows.isEmpty) return '';
      final buffer = StringBuffer()
        ..writeln('# Kuron error log (${rows.length} entries)')
        ..writeln();
      for (final entry in rows) {
        final status = entry.statusCode == null
            ? ''
            : ' | HTTP ${entry.statusCode}';
        buffer.writeln(
          '[${entry.id}] ${entry.createdAt.toIso8601String()} | '
          '${entry.sourceId} | ${entry.feature}$status | '
          'app ${entry.appVersion}',
        );
        if (entry.urlPath.isNotEmpty) {
          buffer.writeln('    url: ${entry.urlPath}');
        }
        buffer.writeln('    msg: ${entry.message}');
      }
      return buffer.toString().trimRight();
    } catch (e) {
      _logger.w('ErrorLog.exportText failed: $e');
      return '';
    }
  }

  static Future<Database?> _db() async {
    try {
      final helper = _dbHelperOverride ?? DatabaseHelper.instance;
      return await helper.database;
    } catch (e) {
      _logger.w('ErrorLog store unavailable: $e');
      return null;
    }
  }

  static Future<String> _appVersion() async {
    final override = _appVersionOverride;
    if (override != null && override.isNotEmpty) return override;
    if (_cachedAppVersion.isNotEmpty) return _cachedAppVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      _cachedAppVersion = build.isEmpty
          ? info.version
          : '${info.version}+$build';
      if (_cachedAppVersion.isEmpty) _cachedAppVersion = 'unknown';
    } catch (_) {
      _cachedAppVersion = 'unknown';
    }
    return _cachedAppVersion;
  }

  /// FIFO prune: oldest rows go first until both caps are satisfied.
  static Future<void> _prune(Database db) async {
    final rows = await db.query(
      tableName,
      columns: _pruneColumns,
      orderBy: 'id ASC',
    );
    if (rows.isEmpty) return;

    var remaining = rows.length;
    var bytes = rows.fold<int>(0, (sum, row) => sum + _rowBytes(row));
    final expired = <Object?>[];

    for (final row in rows) {
      if (remaining <= maxEntries && bytes <= maxBytes) break;
      expired.add(row['id']);
      remaining--;
      bytes -= _rowBytes(row);
    }
    if (expired.isEmpty) return;

    final placeholders = List.filled(expired.length, '?').join(',');
    await db.delete(
      tableName,
      where: 'id IN ($placeholders)',
      whereArgs: expired,
    );
  }

  static int _rowBytes(Map<String, Object?> row) {
    final payload = [
      row['sourceId'],
      row['feature'],
      row['message'],
      row['urlPath'],
      row['appVersion'],
    ].map((value) => value?.toString() ?? '').join();
    // 64 bytes covers ids, timestamps and SQLite row overhead.
    return utf8.encode(payload).length + 64;
  }
}
