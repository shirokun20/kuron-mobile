import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/error_log/error_log.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

void main() {
  late _MockDatabaseHelper mockHelper;
  late _MockDatabase mockDb;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockHelper = _MockDatabaseHelper();
    mockDb = _MockDatabase();
    when(() => mockHelper.database).thenAnswer((_) async => mockDb);
    ErrorLog.debugSetOverrides(
      dbHelper: mockHelper,
      appVersion: '1.2.3',
    );
  });

  tearDown(() {
    ErrorLog.debugResetOverrides();
  });

  group('toggle', () {
    test('isEnabled defaults to false', () async {
      expect(await ErrorLog.isEnabled(), isFalse);
    });

    test('setEnabled persists value', () async {
      await ErrorLog.setEnabled(true);
      expect(await ErrorLog.isEnabled(), isTrue);
      await ErrorLog.setEnabled(false);
      expect(await ErrorLog.isEnabled(), isFalse);
    });
  });

  group('record', () {
    test('does not write when disabled (zero-write)', () async {
      await ErrorLog.setEnabled(false);
      await ErrorLog.record(
        sourceId: 'nhentai',
        feature: 'getChapterImages',
        statusCode: 500,
        message: 'boom',
        urlPath: '/g/1?token=x',
      );
      verifyNever(() => mockDb.insert(any(), any()));
    });

    test('writes entry and strips query params from urlPath when enabled',
        () async {
      await ErrorLog.setEnabled(true);
      when(() => mockDb.insert(any(), any())).thenAnswer((_) async => 1);
      when(() => mockDb.rawQuery('SELECT COUNT(*) AS c FROM error_log'))
          .thenAnswer((_) async => [
                {'c': 1}
              ]);
      when(() => mockDb.query('error_log',
              columns: any(named: 'columns')))
          .thenAnswer((_) async => <Map<String, Object?>>[]);

      await ErrorLog.record(
        sourceId: 'nhentai',
        feature: 'getChapterImages',
        statusCode: 502,
        message: 'Bad Gateway',
        urlPath: 'https://site.test/api/img?id=1&secret=x',
      );

      final inserted = verify(() => mockDb.insert('error_log', captureAny()))
          .captured
          .single as Map<String, Object?>;
      expect(inserted['sourceId'], 'nhentai');
      expect(inserted['feature'], 'getChapterImages');
      expect(inserted['statusCode'], 502);
      expect(inserted['message'], 'Bad Gateway');
      expect(inserted['urlPath'], '/api/img');
      expect(inserted['appVersion'], '1.2.3');
      expect(inserted['createdAt'], isA<int>());
    });
  });

  group('entries', () {
    test('returns mapped entries ordered by createdAt desc', () async {
      when(() => mockDb.query(
            'error_log',
            orderBy: any(named: 'orderBy'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            {
              'id': 2,
              'createdAt': 2000,
              'sourceId': 'b',
              'feature': 'f2',
              'statusCode': null,
              'message': 'm2',
              'urlPath': '/2',
              'appVersion': '1.0.0',
            },
            {
              'id': 1,
              'createdAt': 1000,
              'sourceId': 'a',
              'feature': 'f1',
              'statusCode': 500,
              'message': 'm1',
              'urlPath': '/1',
              'appVersion': '1.0.0',
            },
          ]);

      final list = await ErrorLog.entries(limit: 50);
      expect(list.length, 2);
      expect(list.first.id, 2);
      expect(list.first.sourceId, 'b');
      expect(list.first.statusCode, isNull);
      expect(list.last.statusCode, 500);
      expect(list.last.createdAt.millisecondsSinceEpoch, 1000);
    });
  });

  group('prune', () {
    test('prunes FIFO when over entry cap', () async {
      await ErrorLog.setEnabled(true);
      when(() => mockDb.insert(any(), any())).thenAnswer((_) async => 1);
      var count = 201;
      when(() => mockDb.rawQuery('SELECT COUNT(*) AS c FROM error_log'))
          .thenAnswer((_) async => [
                {'c': count}
              ]);
      when(() => mockDb.rawDelete(any(), any())).thenAnswer((inv) async {
        count = 200;
        return 1;
      });
      when(() => mockDb.query('error_log',
              columns: any(named: 'columns')))
          .thenAnswer((_) async => <Map<String, Object?>>[]);

      await ErrorLog.record(
        sourceId: 's',
        feature: 'f',
        statusCode: 500,
        message: 'e',
        urlPath: '/p',
      );

      final deletes = verify(() => mockDb.rawDelete(captureAny(), captureAny()))
          .captured;
      expect(deletes, isNotEmpty);
      // first delete call is the FIFO overflow delete
      expect(deletes[0] as String, contains('DELETE FROM error_log'));
    });
  });

  group('delete/clear/export', () {
    test('deleteEntry deletes by id', () async {
      when(() => mockDb.delete(any(),
              where: any(named: 'where'), whereArgs: any(named: 'whereArgs')))
          .thenAnswer((_) async => 1);
      await ErrorLog.deleteEntry(7);
      verify(() => mockDb.delete('error_log',
          where: 'id = ?', whereArgs: [7])).called(1);
    });

    test('clearAll deletes all rows', () async {
      when(() => mockDb.delete(any())).thenAnswer((_) async => 3);
      await ErrorLog.clearAll();
      verify(() => mockDb.delete('error_log')).called(1);
    });

    test('exportText formats entries', () async {
      when(() => mockDb.query(
            'error_log',
            orderBy: any(named: 'orderBy'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            {
              'id': 1,
              'createdAt': 1700000000000,
              'sourceId': 'nhentai',
              'feature': 'fetchDetail',
              'statusCode': 503,
              'message': 'timeout',
              'urlPath': '/g/1',
              'appVersion': '1.0.0',
            },
          ]);
      final text = await ErrorLog.exportText();
      expect(text, contains('HTTP 503'));
      expect(text, contains('nhentai/fetchDetail'));
      expect(text, contains('/g/1'));
      expect(text, contains('timeout'));
    });
  });

  group('exclusions (5.3)', () {
    Future<void> expectExcluded({
      int? statusCode,
      required String message,
    }) async {
      await ErrorLog.setEnabled(true);
      reset(mockDb);
      when(() => mockHelper.database).thenAnswer((_) async => mockDb);
      await ErrorLog.record(
        sourceId: 's',
        feature: 'f',
        statusCode: statusCode,
        message: message,
        urlPath: '/p',
      );
      verifyNever(() => mockDb.insert(any(), any()));
    }

    test('CF/challenge messages excluded regardless of status', () async {
      await expectExcluded(statusCode: 200, message: 'Cloudflare challenge page');
      await expectExcluded(statusCode: 503, message: 'cf-chl-bypass failed');
      await expectExcluded(
          statusCode: 403, message: 'Just a moment... checking your browser');
      await expectExcluded(statusCode: 401, message: 'Turnstile captcha required');
    });

    test('403 WAF excluded', () async {
      await expectExcluded(statusCode: 403, message: 'Forbidden by WAF');
      await expectExcluded(statusCode: 403, message: 'HTTP 403 access denied');
    });

    test('login-wall excluded', () async {
      await expectExcluded(statusCode: 401, message: 'Login required to view');
      await expectExcluded(statusCode: 302, message: 'Please log in first');
    });

    test('real errors are recorded (5xx, timeout/DNS, parse non-challenge)',
        () async {
      Future<void> expectRecorded({
        int? statusCode,
        required String message,
      }) async {
        await ErrorLog.setEnabled(true);
        reset(mockDb);
        when(() => mockHelper.database).thenAnswer((_) async => mockDb);
        when(() => mockDb.insert(any(), any())).thenAnswer((_) async => 1);
        when(() => mockDb.rawQuery('SELECT COUNT(*) AS c FROM error_log'))
            .thenAnswer((_) async => [
                  {'c': 1}
                ]);
        when(() => mockDb.query('error_log', columns: any(named: 'columns')))
            .thenAnswer((_) async => <Map<String, Object?>>[]);
        await ErrorLog.record(
          sourceId: 's',
          feature: 'f',
          statusCode: statusCode,
          message: message,
          urlPath: '/p',
        );
        verify(() => mockDb.insert('error_log', any())).called(1);
      }

      await expectRecorded(statusCode: 500, message: 'Internal Server Error');
      await expectRecorded(statusCode: 503, message: 'Service Unavailable');
      await expectRecorded(
          statusCode: null, message: 'TimeoutException: request timeout');
      await expectRecorded(
          statusCode: null, message: 'SocketException: DNS lookup failed');
      await expectRecorded(
          statusCode: 200, message: 'ParseException: invalid json body');
    });
  });
}
