import 'package:nhasixapp/core/services/error_log/error_log.dart'
    as impl;

import 'error_log_contract.dart' as ui;

/// Group 6 integration: binds W3's static store to W2's UI contract.
///
/// Static methods are taken as tear-off defaults so tests can inject
/// fakes without touching sqflite.
class ErrorLogAdapter implements ui.ErrorLogContract {
  ErrorLogAdapter({
    Future<bool> Function()? isEnabledFn,
    Future<void> Function(bool)? setEnabledFn,
    Future<List<impl.ErrorLogEntry>> Function({int limit})? entriesFn,
    Future<void> Function(int id)? deleteEntryFn,
    Future<void> Function()? clearAllFn,
    Future<String> Function()? exportTextFn,
  })  : _isEnabledFn = isEnabledFn ?? impl.ErrorLog.isEnabled,
        _setEnabledFn = setEnabledFn ?? impl.ErrorLog.setEnabled,
        _entriesFn = entriesFn ?? impl.ErrorLog.entries,
        _deleteEntryFn = deleteEntryFn ?? impl.ErrorLog.deleteEntry,
        _clearAllFn = clearAllFn ?? impl.ErrorLog.clearAll,
        _exportTextFn = exportTextFn ?? impl.ErrorLog.exportText;

  final Future<bool> Function() _isEnabledFn;
  final Future<void> Function(bool) _setEnabledFn;
  final Future<List<impl.ErrorLogEntry>> Function({int limit}) _entriesFn;
  final Future<void> Function(int id) _deleteEntryFn;
  final Future<void> Function() _clearAllFn;
  final Future<String> Function() _exportTextFn;

  @override
  Future<bool> isEnabled() => _isEnabledFn();

  @override
  Future<void> setEnabled(bool enabled) => _setEnabledFn(enabled);

  @override
  Future<List<ui.ErrorLogEntry>> entries({int limit = 100}) async {
    final rows = await _entriesFn(limit: limit);
    return [
      for (final r in rows)
        ui.ErrorLogEntry(
          id: r.id,
          createdAt: r.createdAt,
          sourceId: r.sourceId,
          feature: r.feature,
          statusCode: r.statusCode,
          message: r.message,
          urlPath: r.urlPath,
        ),
    ];
  }

  @override
  Future<void> deleteEntry(int id) => _deleteEntryFn(id);

  @override
  Future<void> clearAll() => _clearAllFn();

  @override
  Future<String> exportText() => _exportTextFn();
}
