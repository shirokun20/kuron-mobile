import 'dart:convert';

import 'package:crypto/crypto.dart';

// Contract shared with kuron-extensions: every config declares a top-level
// `idType` of `'real'` (UUID / numeric API ids) or `'slug'` (URL-slug ids).
// `idType` wins when present; older configs fall back to other config evidence
// (a `transform: 'slug'` id field, a non-numeric `contentIdPattern`, a
// `$.slug` selector, …) and only then to the id's own format.
final RegExp _uuidRegExp = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _numericRegExp = RegExp(r'^\d+$');
final RegExp _shortSafeIdRegExp = RegExp(r'^[A-Za-z0-9._~-]{1,20}$');
final RegExp _slugSelectorRegExp = RegExp(
  r'^\$?\.?(?:[\w-]+\.)*slug$',
  caseSensitive: false,
);

/// Whether [rawId] is already a concise identifier that must be shown as-is.
///
/// This is a DISPLAY-ONLY decision: callers keep using the untouched
/// `content.id` for routing, API/scraper calls, bookmarks and storage.
bool isRealContentId(String rawId, {Map<String, dynamic>? rawConfig}) {
  final declared = rawConfig?['idType']?.toString().toLowerCase();
  if (declared == 'real') return true;
  if (declared == 'slug') return false;

  // Config evidence beats the id's own format: a bare short slug coming from
  // non-link extraction on a stale cached config (no `idType`) must not be
  // mistaken for a real id just because it is short and filesystem-safe.
  if (_configUsesSlugId(rawConfig)) return false;
  if (_configHasSlugIdEvidence(rawConfig)) return false;

  if (rawId.isEmpty) return false;
  if (_uuidRegExp.hasMatch(rawId) || _numericRegExp.hasMatch(rawId)) {
    return true;
  }
  // Unknown config + short, filesystem-safe id: last-resort fallback.
  return rawId.length <= 20 && _shortSafeIdRegExp.hasMatch(rawId);
}

/// The string shown in the Detail "ID" metadata row.
String displayContentId(String rawId, {Map<String, dynamic>? rawConfig}) {
  return isRealContentId(rawId, rawConfig: rawConfig)
      ? rawId
      : _shortDisplayHash(rawId);
}

/// Mirrors `DownloadStorageUtils.getElegantId`'s algorithm, but applies it
/// unconditionally: a slug-classified id is hashed for DISPLAY even when it is
/// short and filesystem-safe (`mahiru-no-tsuki` -> `qbpwf9zkg`). The download
/// storage implementation itself is left untouched, so folder names and the
/// download item widget keep their existing behaviour.
String _shortDisplayHash(String rawId) {
  final digest = sha1.convert(utf8.encode(rawId));
  final bigInt = BigInt.parse(
    digest.bytes
        .sublist(0, 6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    radix: 16,
  );
  return bigInt.toRadixString(36);
}

// Older slug configs (komikindo, komikcast, crotpedia, …) declare
// `transform: 'slug'` on an `id` field even without the newer `idType` key.
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

// Further config-only evidence for stale configs that predate `idType`:
//   * a non-numeric `contentIdPattern` capture (`/manga/([^/]+)`),
//   * an API `id` selector targeting `$.slug` / `*.slug`,
//   * an `id` regex capture that yields a path/slug, or an id typed `slug`.
// Purely numeric / hex / UUID captures are deliberately ignored so real-id
// configs keep their ids raw even on stale cached copies.
bool _configHasSlugIdEvidence(Object? node, [int depth = 0]) {
  if (depth > 10 || node == null) return false;
  if (node is List) {
    for (final value in node) {
      if (_configHasSlugIdEvidence(value, depth + 1)) return true;
    }
    return false;
  }
  if (node is! Map) return false;
  for (final entry in node.entries) {
    final key = entry.key.toString();
    final value = entry.value;

    if (key == 'contentIdPattern' && value is String) {
      if (_patternCapturesSlug(value)) return true;
    }
    if (key == 'id') {
      if (value is String && _slugSelectorRegExp.hasMatch(value)) return true;
      if (value is Map) {
        final selector = value['selector']?.toString();
        if (selector != null && _slugSelectorRegExp.hasMatch(selector)) {
          return true;
        }
        if (value['type']?.toString().toLowerCase() == 'slug') return true;
        final regex = value['regex']?.toString();
        if (regex != null && _patternCapturesSlug(regex)) return true;
      }
    }
    if (_configHasSlugIdEvidence(value, depth + 1)) return true;
  }
  return false;
}

// True when a regex/URL pattern captures arbitrary text instead of a clean
// numeric / hex / UUID token. Negated classes (`[^/]+`), letter classes
// (`[a-z]`), `\w` and literal path suffixes (`.html`) all count as slugs.
bool _patternCapturesSlug(String pattern) {
  if (RegExp(r'\{(?:slug|id)\}', caseSensitive: false).hasMatch(pattern)) {
    return true; // path-template style: `/manga/{slug}`, `/{id}`, …
  }
  for (final group in _captureGroups(pattern)) {
    if (_captureBodyIsSlug(group)) return true;
  }
  return false;
}

// Sufficient parenthesis scan for config regexes: escaped parens are ignored
// and only top-level groups are collected.
List<String> _captureGroups(String pattern) {
  final groups = <String>[];
  var depth = 0;
  var start = 0;
  var escaped = false;
  for (var i = 0; i < pattern.length; i++) {
    final c = pattern[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (c == r'\') {
      escaped = true;
      continue;
    }
    if (c == '(') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (c == ')') {
      if (depth == 1) groups.add(pattern.substring(start, i));
      if (depth > 0) depth--;
    }
  }
  return groups;
}

bool _captureBodyIsSlug(String body) {
  final b = body.toLowerCase();
  // These constructs deliberately capture arbitrary text.
  if (b.contains('[^')) return true;
  if (b.contains(r'\w') || b.contains(r'\s')) return true;
  if (b.contains('[a-z')) return true;

  // Strip numeric / hex / UUID-only syntax, then regex punctuation. Whatever
  // letters survive outside the hex alphabet are slug text (e.g. `html`).
  final stripped = b
      .replaceAll(
        RegExp(r'\\d|\[0-9(?:-[0-9])?\]|\[a-f0-9\]|\[0-9a-f\]|\{[0-9,]+\}'),
        '',
      )
      .replaceAll(RegExp(r'[\[\](){}+\*?|^$\\/\-_:#&=%,~@!\s\.]'), '');
  return RegExp(r'[g-z]').hasMatch(stripped);
}
