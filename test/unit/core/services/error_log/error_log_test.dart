import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/error_log/error_log.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

Map<String, Object?> _row({
  required int id,
  int createdAt = 1000,
  String sourceId = 'komiktap',
  String feature = 'getChapterImages',
  int? statusCode,
  String message = 'boom',
  String urlPath = '',
  String appVersion = '1.0.0',
}) => {
  'id': id,
  'createdAt': createdAt,
  'sourceId': sourceId,
  'feature': feature,
  'statusCode': statusCode,
  'message': message,
  'urlPath': urlPath,
  'appVersion': appVersion,
};

void main() {
  late _MockDatabaseHelper helper;
  late _MockDatabase db;

  /// Rows returned by the prune query (`columns` + `orderBy`, no limit).
  late List<Map<String, Object?>> pruneRows;

  /// Rows returned by `entries()` (`orderBy` + `limit`).
  late List<Map<String, Object?>> entryRows;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErrorLog.debugReset();

    helper = _MockDatabaseHelper();
    db = _MockDatabase();
    pruneRows = <Map<String, Object?>>[];
    entryRows = <Map<String, Object?>>[];

    when(() => helper.database).thenAnswer((_) async => db);
    when(() => db.insert(any(), any())).thenAnswer((_) async => 1);
    when(
      () => db.query(
        any(),
        columns: any(named: 'columns'),
        orderBy: any(named: 'orderBy'),
      ),
    ).thenAnswer((_) async => pruneRows);
    when(
      () => db.query(
        any(),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => entryRows);
    when(
      () => db.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => db.delete(any())).thenAnswer((_) async => 1);

    ErrorLog.debugConfigure(dbHelper: helper, appVersion: '9.9.9+99');
  });

  tearDown(ErrorLog.debugReset);

  group('toggle', () {
    test('defaults to off', () async {
      expect(await ErrorLog.isEnabled(), isFalse);
    });

    test('setEnabled persists and isEnabled reads it back', () async {
      await ErrorLog.setEnabled(true);
      expect(await ErrorLog.isEnabled(), isTrue);
      expect(
        SharedPreferences.getInstance().then(
          (p) => p.getBool('error_log_enabled'),
        ),
        completion(isTrue),
      );

      await ErrorLog.setEnabled(false);
      expect(await ErrorLog.isEnabled(), isFalse);
    });
  });

  group('record', () {
    test('is a total no-op while the toggle is off', () async {
      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        statusCode: 502,
        message: 'Bad Gateway',
      );

      verifyNever(() => db.insert(any(), any()));
      verifyNever(() => db.query(any(), orderBy: any(named: 'orderBy')));
    });

    test('writes one entry when enabled', () async {
      await ErrorLog.setEnabled(true);

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        statusCode: 502,
        message: 'Bad Gateway',
        urlPath: 'https://komiktap.test/api/ch/1/images?token=secret',
      );

      final inserted =
          verify(() => db.insert('error_log', captureAny())).captured.single
              as Map<String, Object?>;

      expect(inserted['sourceId'], 'komiktap');
      expect(inserted['feature'], 'getChapterImages');
      expect(inserted['statusCode'], 502);
      expect(inserted['message'], 'Bad Gateway');
      expect(inserted['urlPath'], '/api/ch/1/images');
      expect(inserted['appVersion'], '9.9.9+99');
      expect(inserted['createdAt'], isA<int>());
    });

    test('keeps urlPath query-free even for bare paths', () async {
      await ErrorLog.setEnabled(true);

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'search',
        message: 'oops',
        urlPath: '/api/search?q=secret#frag',
      );

      final inserted =
          verify(() => db.insert('error_log', captureAny())).captured.single
              as Map<String, Object?>;

      expect(inserted['urlPath'], '/api/search');
    });

    test(
      'truncates oversized messages instead of storing them whole',
      () async {
        await ErrorLog.setEnabled(true);

        await ErrorLog.record(
          sourceId: 'komiktap',
          feature: 'search',
          message: 'x' * (ErrorLog.maxMessageLength + 500),
        );

        final inserted =
            verify(() => db.insert('error_log', captureAny())).captured.single
                as Map<String, Object?>;

        expect(
          (inserted['message'] as String).length,
          ErrorLog.maxMessageLength,
        );
      },
    );
  });

  group('exclusions', () {
    test('403 WAF responses are never recorded', () async {
      await ErrorLog.setEnabled(true);

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        statusCode: 403,
        message: 'Forbidden',
      );

      verifyNever(() => db.insert(any(), any()));
    });

    test('cloudflare / turnstile challenges are never recorded', () async {
      await ErrorLog.setEnabled(true);

      for (final message in [
        'Cloudflare challenge detected, attempting bypass',
        'Turnstile verification failed (110200)',
        'Just a moment... checking your browser',
        'cf-challenge-form present',
      ]) {
        await ErrorLog.record(
          sourceId: 'komiktap',
          feature: 'getContentDetail',
          statusCode: 503,
          message: message,
        );
      }

      verifyNever(() => db.insert(any(), any()));
    });

    test('login-wall failures are never recorded', () async {
      await ErrorLog.setEnabled(true);

      for (final message in [
        'LoginRequiredException: please sign in',
        'HTTP 401 Unauthorized',
      ]) {
        await ErrorLog.record(
          sourceId: 'komiktap',
          feature: 'getContentDetail',
          message: message,
        );
      }

      verifyNever(() => db.insert(any(), any()));
    });

    test('real failures still pass the exclusion filter', () async {
      await ErrorLog.setEnabled(true);

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        statusCode: 502,
        message: 'ServerException: Bad Gateway',
      );

      verify(() => db.insert('error_log', any())).called(1);
    });
  });

  group('ring buffer cap', () {
    test('prunes oldest entries beyond 200 (FIFO)', () async {
      await ErrorLog.setEnabled(true);
      pruneRows = [
        for (var i = 1; i <= ErrorLog.maxEntries + 1; i++) _row(id: i),
      ];

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        message: 'boom',
      );

      final where = verify(
        () => db.delete(
          'error_log',
          where: captureAny(named: 'where'),
          whereArgs: captureAny(named: 'whereArgs'),
        ),
      ).captured;

      expect(where[0], 'id IN (?)');
      expect(where[1], [1]);
    });

    test('prunes oldest entries until the 1 MB budget is met', () async {
      await ErrorLog.setEnabled(true);

      // Each row ~ 300 KB of payload → only 3 fit in 1 MB.
      final big = 'y' * (300 * 1024);
      pruneRows = [for (var i = 1; i <= 5; i++) _row(id: i, message: big)];

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        message: 'boom',
      );

      final captured = verify(
        () => db.delete(
          'error_log',
          where: captureAny(named: 'where'),
          whereArgs: captureAny(named: 'whereArgs'),
        ),
      ).captured;

      final ids = captured[1] as List<Object?>;
      expect(ids, [1, 2]);
      // 3 rows fit, the 4th would blow the budget.
      expect(utf8.encode(big).length * 4, greaterThan(ErrorLog.maxBytes));
    });

    test('does not prune while under both caps', () async {
      await ErrorLog.setEnabled(true);
      pruneRows = [for (var i = 1; i <= 5; i++) _row(id: i)];

      await ErrorLog.record(
        sourceId: 'komiktap',
        feature: 'getChapterImages',
        message: 'boom',
      );

      verifyNever(
        () => db.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      );
    });
  });

  group('entries', () {
    test('maps rows newest-first with the default limit', () async {
      entryRows = [
        _row(id: 2, createdAt: 2000, statusCode: 502),
        _row(id: 1, createdAt: 1000),
      ];

      final entries = await ErrorLog.entries();

      expect(entries, hasLength(2));
      expect(entries.first.id, 2);
      expect(entries.first.statusCode, 502);
      expect(entries.first.createdAt.millisecondsSinceEpoch, 2000);
      expect(entries.last.statusCode, isNull);
      expect(entries.last.urlPath, '');

      verify(
        () => db.query(
          'error_log',
          orderBy: 'createdAt DESC, id DESC',
          limit: 100,
        ),
      ).called(1);
    });

    test('returns an empty list when the database is unavailable', () async {
      when(() => helper.database).thenThrow(Exception('no db'));

      expect(await ErrorLog.entries(), isEmpty);
    });
  });

  group('delete / clear', () {
    test('deleteEntry removes exactly one row', () async {
      await ErrorLog.deleteEntry(7);

      verify(() => db.delete('error_log', where: 'id = ?', whereArgs: [7]))
          .called(1);
    });

    test('clearAll empties the table', () async {
      await ErrorLog.clearAll();

      verify(() => db.delete('error_log')).called(1);
    });
  });

  group('exportText', () {
    test('renders a text report of every stored entry', () async {
      entryRows = [
        _row(
          id: 2,
          createdAt: 2000,
          sourceId: 'nhentai',
          feature: 'getChapterImages',
          statusCode: 502,
          message: 'Bad Gateway',
          urlPath: '/api/gallery/1/images',
        ),
      ];

      final text = await ErrorLog.exportText();

      expect(text, contains('nhentai'));
      expect(text, contains('getChapterImages'));
      expect(text, contains('502'));
      expect(text, contains('/api/gallery/1/images'));
      expect(text, contains('Bad Gateway'));
    });

    test('returns an empty string when nothing is stored', () async {
      expect(await ErrorLog.exportText(), '');
    });
  });
}
