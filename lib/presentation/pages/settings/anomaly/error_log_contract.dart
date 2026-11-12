/// Model representing an error-response log entry.
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

/// Abstract contract for ErrorLog store.
/// Implemented by ErrorLog (W3) during integration, or fake in widget tests.
abstract class ErrorLogContract {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
  Future<List<ErrorLogEntry>> entries({int limit});
  Future<void> deleteEntry(int id);
  Future<void> clearAll();
  Future<String> exportText();
}
