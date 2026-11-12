import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nhasixapp/presentation/pages/settings/anomaly/anomaly_store_adapter.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

void main() {
  late _MockDatabaseHelper mockHelper;
  late _MockDatabase mockDb;

  setUp(() {
    mockHelper = _MockDatabaseHelper();
    mockDb = _MockDatabase();
    when(() => mockHelper.database).thenAnswer((_) async => mockDb);
  });

  Map<String, Object?> row(String fp, int count) => {
        'fingerprint': fp,
        'sourceId': 'komikcast',
        'feature': 'reader-empty',
        'kind': 'empty',
        'contextJson': '{"template": "/series/{slug}/"}',
        'count': count,
        'firstSeen': 1000,
        'lastSeen': 2000,
        'lastSessionId': 's-2',
        'configVersion': '3.0.0',
        'state': 'local',
      };

  test('records maps int-ms to DateTime and passes fields through', () async {
    when(
      () => mockDb.query(
        any(),
        orderBy: any(named: 'orderBy'),
      ),
    ).thenAnswer((_) async => [row('fp1', 1), row('fp2', 2)]);

    final adapter = AnomalyStoreAdapter(
      AnomalyStore(dbHelper: mockHelper, sessionId: 's-2'),
    );
    final records = await adapter.records();

    expect(records, hasLength(2));
    expect(records[0].fingerprint, 'fp1');
    expect(records[0].sourceId, 'komikcast');
    expect(records[0].lastSeen,
        DateTime.fromMillisecondsSinceEpoch(2000));
    expect(records[0].firstSeen,
        DateTime.fromMillisecondsSinceEpoch(1000));
    expect(records[0].eligible, isFalse);
    expect(records[1].eligible, isTrue);
    expect(records[1].configVersion, '3.0.0');
    expect(records[1].context, {'template': '/series/{slug}/'});
  });

  test('deleteRecord forwards fingerprint to the store', () async {
    when(
      () => mockDb.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);

    final adapter = AnomalyStoreAdapter(
      AnomalyStore(dbHelper: mockHelper, sessionId: 's-2'),
    );
    await adapter.deleteRecord('fp1');

    verify(
      () => mockDb.delete(
        'anomaly_records',
        where: 'fingerprint = ?',
        whereArgs: ['fp1'],
      ),
    ).called(1);
  });
}
