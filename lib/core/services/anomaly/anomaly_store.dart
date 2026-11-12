import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nhasixapp/data/datasources/local/database_helper.dart';

export 'source_health_tracker.dart';

/// Threshold: an anomaly becomes report-eligible after being seen in
/// 2 different app sessions (Keputusan 8 — locked at 2).
const int kAnomalyReportThreshold = 2;

/// Local state of an anomaly record (v1: only `local`; report queue
/// and remote sync belong to later groups).
const String kAnomalyStateLocal = 'local';

/// Pure rule (Keputusan 10): a chapter whose emptiness is officially
/// declared — hosted externally or flagged unavailable — is legitimate
/// content, never an anomaly candidate.
bool isExcludedAnomalyChapter({
  String? externalUrl,
  bool isUnavailable = false,
}) {
  if (isUnavailable) return true;
  return externalUrl != null && externalUrl.trim().isNotEmpty;
}

/// Local anomaly record read from sqflite.
class AnomalyRecord {
  const AnomalyRecord({
    required this.fingerprint,
    required this.sourceId,
    required this.feature,
    required this.kind,
    required this.count,
    required this.lastSeen,
    required this.eligible,
    this.contextJson = '{}',
    this.firstSeen = 0,
    this.lastSessionId = '',
    this.configVersion = '',
    this.state = kAnomalyStateLocal,
  });

  final String fingerprint;
  final String sourceId;
  final String feature;
  final String kind;
  final int count;
  final int lastSeen;
  final bool eligible;
  final String contextJson;
  final int firstSeen;
  final String lastSessionId;
  final String configVersion;
  final String state;

  factory AnomalyRecord.fromMap(Map<String, Object?> map) {
    final count = (map['count'] as num?)?.toInt() ?? 0;
    return AnomalyRecord(
      fingerprint: map['fingerprint'] as String? ?? '',
      sourceId: map['sourceId'] as String? ?? '',
      feature: map['feature'] as String? ?? '',
      kind: map['kind'] as String? ?? '',
      count: count,
      lastSeen: (map['lastSeen'] as num?)?.toInt() ?? 0,
      eligible: count >= kAnomalyReportThreshold,
      contextJson: map['contextJson'] as String? ?? '{}',
      firstSeen: (map['firstSeen'] as num?)?.toInt() ?? 0,
      lastSessionId: map['lastSessionId'] as String? ?? '',
      configVersion: map['configVersion'] as String? ?? '',
      state: map['state'] as String? ?? kAnomalyStateLocal,
    );
  }
}

/// Sqflite-backed anomaly store with fingerprint dedup.
///
/// Fingerprint = sha256(sourceId + feature + kind + template): stable
/// across sessions so repeats land on one row. Counting rule (Keputusan 9):
/// one app run owns one session UUID — a repeat in the same session only
/// refreshes `lastSeen`, a repeat under a different UUID bumps `count`.
/// A `configVersion` change resets the counter (re-verification required).
/// A recorded feature success ([resetFeature]) clears that feature's rows.
class AnomalyStore {
  AnomalyStore({DatabaseHelper? dbHelper, String? sessionId, Logger? logger})
      : _databaseHelper = dbHelper,
        _sessionId = sessionId ??
            '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
        _logger = logger ?? Logger();

  /// Global singleton used by detectors and the (later) Settings UI.
  static final AnomalyStore instance = AnomalyStore();

  static const String tableName = 'anomaly_records';

  final DatabaseHelper? _databaseHelper;
  final String _sessionId;
  final Logger _logger;

  /// UUID of this app run (Keputusan 9): created once per store.
  String get sessionId => _sessionId;

  /// Stable fingerprint for (sourceId, feature, kind, template).
  static String fingerprintFor({
    required String sourceId,
    required String feature,
    required String kind,
    required String template,
  }) {
    final input = '$sourceId|$feature|$kind|$template';
    return sha256.convert(utf8.encode(input)).toString();
  }

  Future<Database?> _db() async {
    try {
      final helper = _databaseHelper ?? DatabaseHelper.instance;
      return await helper.database;
    } catch (e) {
      _logger.w('AnomalyStore unavailable: $e');
      return null;
    }
  }

  /// Records one anomaly sighting. Never throws — detectors must not
  /// break the reader when storage is unavailable.
  Future<void> recordEvent({
    required String sourceId,
    required String feature,
    required String kind,
    Map<String, Object?>? contextJson,
    String? configVersion,
    String? sessionId,
  }) async {
    try {
      final db = await _db();
      if (db == null) return;

      final template = contextJson?['template']?.toString() ?? '';
      final fingerprint = fingerprintFor(
        sourceId: sourceId,
        feature: feature,
        kind: kind,
        template: template,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final sid = sessionId ?? _sessionId;
      final version = (configVersion == null || configVersion.isEmpty)
          ? 'unknown'
          : configVersion;
      final context = contextJson == null ? '{}' : jsonEncode(contextJson);

      final existing = await db.query(
        tableName,
        where: 'fingerprint = ?',
        whereArgs: [fingerprint],
      );
      if (existing.isEmpty) {
        await db.insert(tableName, {
          'fingerprint': fingerprint,
          'sourceId': sourceId,
          'feature': feature,
          'kind': kind,
          'contextJson': context,
          'count': 1,
          'firstSeen': now,
          'lastSeen': now,
          'lastSessionId': sid,
          'configVersion': version,
          'state': kAnomalyStateLocal,
        });
        return;
      }

      final row = existing.first;
      final storedVersion = row['configVersion'] as String? ?? '';
      final storedSession = row['lastSessionId'] as String? ?? '';
      final storedCount = (row['count'] as num?)?.toInt() ?? 0;

      if (storedVersion != version) {
        // Config changed → stale record, re-verify from zero.
        await db.update(
          tableName,
          {
            'contextJson': context,
            'count': 1,
            'lastSeen': now,
            'lastSessionId': sid,
            'configVersion': version,
            'state': kAnomalyStateLocal,
          },
          where: 'fingerprint = ?',
          whereArgs: [fingerprint],
        );
        return;
      }

      await db.update(
        tableName,
        {
          'contextJson': context,
          // Keputusan 9: only a *different* session UUID bumps the counter.
          'count': storedSession == sid ? storedCount : storedCount + 1,
          'lastSeen': now,
          'lastSessionId': sid,
        },
        where: 'fingerprint = ?',
        whereArgs: [fingerprint],
      );
    } catch (e) {
      _logger.w('AnomalyStore.recordEvent failed: $e');
    }
  }

  /// All records, newest first. `eligible` = seen in ≥2 sessions.
  Future<List<AnomalyRecord>> records() async {
    try {
      final db = await _db();
      if (db == null) return const [];
      final rows = await db.query(tableName, orderBy: 'lastSeen DESC');
      return rows.map(AnomalyRecord.fromMap).toList();
    } catch (e) {
      _logger.w('AnomalyStore.records failed: $e');
      return const [];
    }
  }

  /// Deletes one record by fingerprint (user dismissal).
  Future<void> deleteRecord(String fingerprint) async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(
        tableName,
        where: 'fingerprint = ?',
        whereArgs: [fingerprint],
      );
    } catch (e) {
      _logger.w('AnomalyStore.deleteRecord failed: $e');
    }
  }

  /// Success path (one indexed UPDATE target): the feature works again,
  /// so its stale counters must never reach the report threshold.
  Future<void> resetFeature(String sourceId, String feature) async {
    try {
      final db = await _db();
      if (db == null) return;
      await db.delete(
        tableName,
        where: 'sourceId = ? AND feature = ?',
        whereArgs: [sourceId, feature],
      );
    } catch (e) {
      _logger.w('AnomalyStore.resetFeature failed: $e');
    }
  }
}
