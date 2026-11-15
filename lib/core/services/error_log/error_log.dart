import 'dart:async';

import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nhasixapp/data/datasources/local/database_helper.dart';

/// Error-response log entry.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.id,
    required this.createdAt,
    required this.sourceId,
    required this.feature,
    this.statusCode,
    required this.message,
    required this.urlPath,
  });

  final int id;
  final DateTime createdAt;
  final String sourceId;
  final String feature;
  final int? statusCode;
  final String message;
  final String urlPath;
}

/// Local error-response logging store (opt-in).
///
/// Public API is static as specified by source-anomaly-report (Grup 5.1-5.3).
class ErrorLog {
  ErrorLog._();

  static const String tableName = 'error_log';
  static const String _enabledKey = 'error_log_enabled';
  static const int defaultLimit = 100;
  static const int _capEntries = 200;
  static const int _capBytes = 1024 * 1024; // 1 MB

  static final Logger _logger = Logger();
  static DatabaseHelper? _dbHelperOverride;
  static String? _appVersionOverride;
  static Future<SharedPreferences>? _prefsFutureOverride;

  /// Test-only overrides.
  static void debugSetOverrides({
    DatabaseHelper? dbHelper,
    String? appVersion,
    Future<SharedPreferences>? prefsFuture,
  }) {
    _dbHelperOverride = dbHelper;
    _appVersionOverride = appVersion;
    _prefsFutureOverride = prefsFuture;
  }

  /// Alias for [debugSetOverrides].
  static void debugConfigure({
    DatabaseHelper? dbHelper,
    String? appVersion,
    Future<SharedPreferences>? prefsFuture,
  }) =>
      debugSetOverrides(
        dbHelper: dbHelper,
        appVersion: appVersion,
        prefsFuture: prefsFuture,
      );

  static void debugResetOverrides() {
    _dbHelperOverride = null;
    _appVersionOverride = null;
    _prefsFutureOverride = null;
  }

  /// Alias for [debugResetOverrides].
  static void debugReset() => debugResetOverrides();

  static Future<Database?> _db() async {
    try {
      final helper = _dbHelperOverride ?? DatabaseHelper.instance;
      return await helper.database;
    } catch (e) {
      _logger.w('ErrorLog unavailable: $e');
      return null;
    }
  }

  static Future<SharedPreferences> _prefs() {
    final override = _prefsFutureOverride;
    if (override != null) return override;
    return SharedPreferences.getInstance();
  }

  static Future<String> _appVersion() async {
    final override = _appVersionOverride;
    if (override != null) return override;
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Records a real error response. No-op when logging is disabled or excluded.
  static Future<void> record({
    required String sourceId,
    required String feature,
    int? statusCode,
    required String message,
    String? urlPath,
  }) async {
    try {
      if (!await isEnabled()) return;
      if (shouldExclude(statusCode: statusCode, message: message)) return;
      final db = await _db();
      if (db == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final appVersion = await _appVersion();
      final path = _sanitizeUrlPath(urlPath);

      await db.insert(tableName, {
        'createdAt': now,
        'sourceId': sourceId,
        'feature': feature,
        'statusCode': statusCode,
        'message': message,
        'urlPath': path,
        'appVersion': appVersion,
      });
      await _prune(db);
    } catch (e) {
      _logger.w('ErrorLog.record failed: $e');
    }
  }

  /// Exclusions per spec: CF/challenge (any status), 403 WAF, login-wall,
  /// kosong-valid, kegagalan diskriminator-anomaly.
  /// Repo hooks only call record for exception/error paths (not valid-empty
  /// success) and discriminator failures are never routed here.
  static bool shouldExclude({
    required int? statusCode,
    required String message,
  }) {
    final lower = message.toLowerCase();

    // CF/challenge/Turnstile/captcha (any status).
    const challengeHints = <String>[
      'cloudflare',
      'cf-chl',
      'cf_chl',
      'challenge',
      'turnstile',
      'captcha',
      'just a moment',
      'attention required',
      'checking your browser',
      'ddos-guard',
      'sucuri',
    ];
    if (challengeHints.any(lower.contains)) return true;

    // 403 WAF / access denied by protection.
    if (statusCode == 403) {
      const wafHints = <String>[
        'waf',
        'forbidden',
        'access denied',
        'blocked',
        'cloudfront',
        'akamai',
        'imperva',
        'incapsula',
        'firewall',
        'bot',
      ];
      // Treat 403 from protective layers as excluded; generic 403 also excluded
      // as WAF/login-wall ambiguous in this context.
      if (wafHints.any(lower.contains) ||
          lower.contains('403') ||
          true) {
        return true;
      }
    }

    // Login-wall indicators.
    const loginHints = <String>[
      'login required',
      'login wall',
      'sign in',
      'signin',
      'please log in',
      'please login',
      'authentication required',
      'unauthorized access',
      'not logged in',
    ];
    if (loginHints.any(lower.contains)) return true;

    return false;
  }

  static String _sanitizeUrlPath(String? urlPath) {
    if (urlPath == null || urlPath.isEmpty) return '';
    try {
      final uri = Uri.parse(urlPath);
      if (uri.hasScheme || uri.hasAuthority) {
        return uri.path;
      }
      // relative/path?query -> path without query
      final q = urlPath.indexOf('?');
      final h = urlPath.indexOf('#');
      var end = urlPath.length;
      if (q >= 0) end = q < end ? q : end;
      if (h >= 0) end = h < end ? h : end;
      return urlPath.substring(0, end);
    } catch (_) {
      final q = urlPath.indexOf('?');
      return q >= 0 ? urlPath.substring(0, q) : urlPath;
    }
  }

  static Future<void> _prune(Database db) async {
    try {
      // Entry cap: FIFO by oldest createdAt/id.
      final countResult =
          await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
      var count = (countResult.first['c'] as num?)?.toInt() ?? 0;
      while (count > _capEntries) {
        final overflow = count - _capEntries;
        await db.rawDelete(
          'DELETE FROM $tableName WHERE id IN (SELECT id FROM $tableName ORDER BY createdAt ASC, id ASC LIMIT ?)',
          [overflow],
        );
        final again =
            await db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
        count = (again.first['c'] as num?)?.toInt() ?? 0;
      }

      // Size cap: approximate by serialized payload length.
      while (await _approxSize(db) > _capBytes) {
        final deleted = await db.rawDelete(
          'DELETE FROM $tableName WHERE id IN (SELECT id FROM $tableName ORDER BY createdAt ASC, id ASC LIMIT 1)',
        );
        if (deleted == 0) break;
      }
    } catch (e) {
      _logger.w('ErrorLog.prune failed: $e');
    }
  }

  static Future<int> _approxSize(Database db) async {
    final rows = await db.query(tableName,
        columns: ['message', 'urlPath', 'sourceId', 'feature', 'appVersion']);
    var total = 0;
    for (final row in rows) {
      for (final value in row.values) {
        if (value is String) total += value.length;
      }
      total += 32; // overhead for ints/timestamps/row
    }
    return total;
  }

  static Future<bool> isEnabled() async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool v) async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(_enabledKey, v);
    } catch (e) {
      _logger.w('ErrorLog.setEnabled failed: $e');
    }
  }

  static Future<List<ErrorLogEntry>> entries({int limit = defaultLimit}) async {
    try {
      final db = await _db();
      if (db == null) return const [];
      final rows = await db.query(
        tableName,
        orderBy: 'createdAt DESC, id DESC',
        limit: limit,
      );
      return rows.map(_fromMap).toList();
    } catch (e) {
      _logger.w('ErrorLog.entries failed: $e');
      return const [];
    }
  }

  static ErrorLogEntry _fromMap(Map<String, Object?> map) {
    final createdAtMs = (map['createdAt'] as num?)?.toInt() ?? 0;
    return ErrorLogEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      sourceId: map['sourceId'] as String? ?? '',
      feature: map['feature'] as String? ?? '',
      statusCode: (map['statusCode'] as num?)?.toInt(),
      message: map['message'] as String? ?? '',
      urlPath: map['urlPath'] as String? ?? '',
    );
  }

  static Future<void> deleteEntry(int id) async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      _logger.w('ErrorLog.deleteEntry failed: $e');
    }
  }

  static Future<void> clearAll() async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(tableName);
    } catch (e) {
      _logger.w('ErrorLog.clearAll failed: $e');
    }
  }

  static Future<String> exportText() async {
    try {
      final list = await entries(limit: _capEntries);
      if (list.isEmpty) return '';
      final buffer = StringBuffer();
      for (final e in list) {
        final ts = e.createdAt.toIso8601String();
        final status = e.statusCode != null ? 'HTTP ${e.statusCode}' : 'ERR';
        buffer.writeln(
            '[$ts] [$status] ${e.sourceId}/${e.feature} ${e.urlPath}');
        buffer.writeln(e.message);
        buffer.writeln('---');
      }
      return buffer.toString().trimRight();
    } catch (e) {
      _logger.w('ErrorLog.exportText failed: $e');
      return '';
    }
  }
}
