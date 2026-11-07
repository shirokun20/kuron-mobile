import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/datasources/local/database_helper.dart';
import 'package:nhasixapp/data/datasources/local/local_data_source.dart';
import 'package:sqflite/sqflite.dart';

class _MockDatabaseHelper extends Mock implements DatabaseHelper {}

class _MockDatabase extends Mock implements Database {}

void main() {
  late _MockDatabaseHelper mockHelper;
  late _MockDatabase mockDb;
  late LocalDataSource dataSource;

  setUpAll(() {
    if (!GetIt.instance.isRegistered<Logger>()) {
      GetIt.instance.registerSingleton<Logger>(Logger());
    }
  });

  setUp(() {
    mockHelper = _MockDatabaseHelper();
    mockDb = _MockDatabase();
    when(() => mockHelper.database).thenAnswer((_) async => mockDb);
    dataSource = LocalDataSource(mockHelper);
  });

  group('getReadCountsBySource', () {
    test('returns per-source counts for 2 sources, skipping null/empty ids',
        () async {
      // Arrange: grouped rows as the query would return them.
      final rows = <Map<String, Object?>>[
        {'source_id': 'sourceA', 'count': 10},
        {'source_id': 'sourceB', 'count': 1},
        {'source_id': null, 'count': 5},
        {'source_id': '   ', 'count': 3},
      ];
      when(() => mockDb.rawQuery(any())).thenAnswer((_) async => rows);

      // Act
      final result = await dataSource.getReadCountsBySource();

      // Assert
      expect(result, {'sourceA': 10, 'sourceB': 1});

      final sql =
          verify(() => mockDb.rawQuery(captureAny())).captured.single as String;
      expect(sql, contains('history'));
      expect(sql, contains('GROUP BY source_id'));
      expect(sql, contains('COUNT(DISTINCT id)'));
      expect(sql, contains('last_page'));
      expect(sql, contains('total_pages'));
      expect(sql, contains('source_id IS NOT NULL'));
    });

    test('returns empty map when database is unavailable', () async {
      // Arrange
      when(() => mockHelper.database).thenThrow(Exception('no db'));

      // Act
      final result = await dataSource.getReadCountsBySource();

      // Assert
      expect(result, isEmpty);
    });

    test('returns empty map when query throws', () async {
      // Arrange
      when(() => mockDb.rawQuery(any())).thenThrow(Exception('query fail'));

      // Act
      final result = await dataSource.getReadCountsBySource();

      // Assert
      expect(result, isEmpty);
    });
  });
}
