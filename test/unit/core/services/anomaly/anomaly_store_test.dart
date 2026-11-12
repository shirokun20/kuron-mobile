import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

Map<String, Object?> _row({
  required String fingerprint,
  int count = 1,
  int firstSeen = 1000,
  int lastSeen = 1000,
  String lastSessionId = 'session-1',
  String configVersion = '1.0.0',
  String state = 'local',
}) =>
    {
      'fingerprint': fingerprint,
      'sourceId': 'komiktap',
      'feature': 'reader-empty',
      'kind': 'empty',
      'contextJson': '{}',
      'count': count,
      'firstSeen': firstSeen,
      'lastSeen': lastSeen,
      'lastSessionId': lastSessionId,
      'configVersion': configVersion,
      'state': state,
    };

void main() {
  late _MockDatabaseHelper mockHelper;
  late _MockDatabase mockDb;

  setUp(() {
    mockHelper = _MockDatabaseHelper();
    mockDb = _MockDatabase();
    when(() => mockHelper.database).thenAnswer((_) async => mockDb);
  });

  group('recordEvent insert', () {
    test('first event inserts a new record with count 1', () async {
      when(
        () => mockDb.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => <Map<String, Object?>>[]);
      when(() => mockDb.insert(any(), any())).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      await store.recordEvent(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        configVersion: '1.0.0',
      );

      final inserted =
          verify(() => mockDb.insert('anomaly_records', captureAny()))
              .captured
              .single as Map<String, Object?>;
      expect(inserted['sourceId'], 'komiktap');
      expect(inserted['feature'], 'reader-empty');
      expect(inserted['count'], 1);
      expect(inserted['firstSeen'], inserted['lastSeen']);
      expect(inserted['lastSessionId'], 'session-1');
      expect(inserted['configVersion'], '1.0.0');
      expect(inserted['state'], 'local');
      expect(inserted['fingerprint'], isNotEmpty);
    });
  });

  group('recordEvent upsert', () {
    test('repeat in the same session keeps count at 1 and updates lastSeen',
        () async {
      final fp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: '',
      );
      when(
        () => mockDb.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => [_row(fingerprint: fp)]);
      when(
        () => mockDb.update(
          any(),
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      await store.recordEvent(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        configVersion: '1.0.0',
      );

      final updated =
          verify(() => mockDb.update('anomaly_records', captureAny(),
                  where: any(named: 'where'),
                  whereArgs: any(named: 'whereArgs')))
              .captured
              .single as Map<String, Object?>;
      expect(updated['count'], 1);
      expect(updated['lastSessionId'], 'session-1');
      verifyNever(() => mockDb.insert(any(), any()));
    });

    test('repeat in a different session increments count', () async {
      final fp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: '',
      );
      when(
        () => mockDb.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => [_row(fingerprint: fp)]);
      when(
        () => mockDb.update(
          any(),
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-2');
      await store.recordEvent(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        configVersion: '1.0.0',
        sessionId: 'session-2',
      );

      final updated =
          verify(() => mockDb.update('anomaly_records', captureAny(),
                  where: any(named: 'where'),
                  whereArgs: any(named: 'whereArgs')))
              .captured
              .single as Map<String, Object?>;
      expect(updated['count'], 2);
      expect(updated['lastSessionId'], 'session-2');
    });

    test('config version change resets count for re-verification', () async {
      final fp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: '',
      );
      when(
        () => mockDb.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer(
          (_) async => [_row(fingerprint: fp, count: 2, configVersion: '1.0.0')]);
      when(
        () => mockDb.update(
          any(),
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-3');
      await store.recordEvent(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        configVersion: '2.0.0',
        sessionId: 'session-3',
      );

      final updated =
          verify(() => mockDb.update('anomaly_records', captureAny(),
                  where: any(named: 'where'),
                  whereArgs: any(named: 'whereArgs')))
              .captured
              .single as Map<String, Object?>;
      expect(updated['count'], 1);
      expect(updated['configVersion'], '2.0.0');
    });

    test('database failure never throws', () async {
      when(() => mockHelper.database).thenThrow(Exception('no db'));
      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      await store.recordEvent(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
      );
    });
  });

  group('records and delete', () {
    test('records maps rows with threshold eligibility', () async {
      final eligibleFp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: '',
      );
      final freshFp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'detail-parse',
        kind: 'parse-failed',
        template: '',
      );
      when(
        () => mockDb.query(any(), orderBy: any(named: 'orderBy')),
      ).thenAnswer((_) async => [
            _row(fingerprint: eligibleFp, count: 2, lastSeen: 2000),
            _row(fingerprint: freshFp, count: 1, lastSeen: 1000),
          ]);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      final records = await store.records();

      expect(records, hasLength(2));
      expect(records.first.fingerprint, eligibleFp);
      expect(records.first.count, 2);
      expect(records.first.lastSeen, 2000);
      expect(records.first.eligible, isTrue);
      expect(records.last.eligible, isFalse);
      expect(records.last.sourceId, 'komiktap');
    });

    test('deleteRecord removes the row by fingerprint', () async {
      when(
        () => mockDb.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      await store.deleteRecord('fp-abc');

      verify(() => mockDb.delete('anomaly_records',
          where: 'fingerprint = ?', whereArgs: ['fp-abc'])).called(1);
    });

    test('resetFeature clears counters for the source feature', () async {
      when(
        () => mockDb.delete(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      final store =
          AnomalyStore(dbHelper: mockHelper, sessionId: 'session-1');
      await store.resetFeature('komiktap', 'reader-empty');

      verify(() => mockDb.delete('anomaly_records',
          where: 'sourceId = ? AND feature = ?',
          whereArgs: ['komiktap', 'reader-empty'])).called(1);
    });
  });
}
