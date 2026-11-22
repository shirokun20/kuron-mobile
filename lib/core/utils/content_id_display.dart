import 'download_storage_utils.dart';

// Contract shared with kuron-extensions: every config declares a top-level
// `idType` of `'real'` (UUID / numeric API ids) or `'slug'` (URL-slug ids).
// `idType` wins when present; older configs fall back to a `transform: 'slug'`
// id field or to the id's own format.
final RegExp _uuidRegExp = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _numericRegExp = RegExp(r'^\d+$');
final RegExp _shortSafeIdRegExp = RegExp(r'^[A-Za-z0-9._~-]{1,20}$');

/// Whether [rawId] is already a concise identifier that must be shown as-is.
///
/// This is a DISPLAY-ONLY decision: callers keep using the untouched
/// `content.id` for routing, API/scraper calls, bookmarks and storage.
bool isRealContentId(String rawId, {Map<String, dynamic>? rawConfig}) {
  final declared = rawConfig?['idType']?.toString().toLowerCase();
  if (declared == 'real') return true;
  if (declared == 'slug') return false;

  if (_configUsesSlugId(rawConfig)) return false;
  if (rawId.isEmpty) return false;
  if (_uuidRegExp.hasMatch(rawId) || _numericRegExp.hasMatch(rawId)) {
    return true;
  }
  // Short, filesystem-safe ids (including brief slugs) are already concise;
  // getElegantId would return them unchanged anyway.
  return rawId.length <= 20 && _shortSafeIdRegExp.hasMatch(rawId);
}

/// The string shown in the Detail "ID" metadata row.
String displayContentId(String rawId, {Map<String, dynamic>? rawConfig}) {
  return isRealContentId(rawId, rawConfig: rawConfig)
      ? rawId
      : DownloadStorageUtils.getElegantId(rawId);
}

// Older slug configs (komikindo, komikcast, …) declare `transform: 'slug'`
// on their `id` field selector even without the newer `idType` key.
bool _configUsesSlugId(Object? node, [int depth = 0]) {
  if (depth > 8 || node == null) return false;
  if (node is List) {
    for (final value in node) {
      if (_configUsesSlugId(value, depth + 1)) return true;
    }
    return false;
  }
  if (node is! Map) return false;
  for (final entry in node.entries) {
    if (entry.key == 'id' &&
        entry.value is Map &&
        entry.value['transform']?.toString() == 'slug') {
      return true;
    }
    if (_configUsesSlugId(entry.value, depth + 1)) return true;
  }
  return false;
}
