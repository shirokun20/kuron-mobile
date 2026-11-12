import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/error_log/error_log.dart' as impl;
import 'package:nhasixapp/presentation/pages/settings/anomaly/error_log_adapter.dart';

void main() {
  impl.ErrorLogEntry row({
    int id = 7,
    String message = 'HTTP 500',
    String urlPath = '/manga/x?page=2',
  }) =>
      impl.ErrorLogEntry(
        id: id,
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        sourceId: 'komikcast',
        feature: 'getChapterImages',
        statusCode: 500,
        message: message,
        urlPath: urlPath,
      );

  test('entries maps impl rows to contract rows', () async {
    final adapter = ErrorLogAdapter(
      entriesFn: ({int limit = 100}) async => [row(), row(id: 8)],
    );
    final entries = await adapter.entries();

    expect(entries, hasLength(2));
    expect(entries[0].id, 7);
    expect(entries[0].createdAt,
        DateTime.fromMillisecondsSinceEpoch(2000));
    expect(entries[0].statusCode, 500);
    expect(entries[0].urlPath, '/manga/x?page=2');
    expect(entries[1].id, 8);
  });

  test('isEnabled/setEnabled/deleteEntry/clearAll/exportText delegate',
      () async {
    var enabled = false;
    var deleted = -1;
    var cleared = false;
    final adapter = ErrorLogAdapter(
      isEnabledFn: () async => enabled,
      setEnabledFn: (v) async => enabled = v,
      deleteEntryFn: (id) async => deleted = id,
      clearAllFn: () async => cleared = true,
      exportTextFn: () async => 'EXPORT',
    );

    expect(await adapter.isEnabled(), isFalse);
    await adapter.setEnabled(true);
    expect(await adapter.isEnabled(), isTrue);
    await adapter.deleteEntry(7);
    expect(deleted, 7);
    await adapter.clearAll();
    expect(cleared, isTrue);
    expect(await adapter.exportText(), 'EXPORT');
  });
}
