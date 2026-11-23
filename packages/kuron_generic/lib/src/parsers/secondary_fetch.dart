// Generic, config-driven **two-step fetch** primitive.
///
// Some sites (Next.js App Router "ad-frame" family, and similar
// shell + deferred-payload apps) do not put their content in the first
// HTML response. The page embeds a short-lived one-time token and the
// real payload is served by a second endpoint:
//
//   GET /manga-list.html?p=1        ->  ... "payloadKey":"l_3dc0…" ...
//   GET /ad-frame/data?k=l_3dc0…    ->  {items: "<obfuscated>", …}
//
// This file implements the generic half of that flow: extract the token
// with a configurable regex, build the secondary URL from a template,
// decode the payload (CJK-XOR obfuscation *or* plain JSON), and map list
// items / pagination / images out of it.
//
// ### Config contract
//
// ```jsonc
// "secondaryFetch": {
//   "enabled": true,
//   "tokenPattern": "payloadKey\\D{0,8}([lmc]_[a-f0-9]+)", // or alias "tokenRegex"
//   "url": "{origin}/ad-frame/data?k={key}", // or alias "secondaryUrlTemplate"
//   "referer": "page",                 // "page" | "origin" | literal URL
//   "payloadPath": "chaotic_payload",  // "" = whole response body
//   "decodeKey": "NicoManga",          // omit => plain JSON
//   "itemsPath": "items",              // list surfaces only
//   "imagesPath": "images",            // reader surfaces only
//   "itemFields": {
//     "id":       { "path": "ur", "regex": "^/?(.*)$" },
//     "title":    { "path": "n", "transform": "cleanText" },
//     "coverUrl": { "path": "c" }
//   },
//   "pagination": {
//     "page":     "pagination.page",
//     "total":    "pagination.total",
//     "lastPage": "pagination.last_page"
//   }
// }
// ```
//
// The primitive is deliberately source-agnostic: nothing here knows about
// nicomanga, `NicoManga`, or `/ad-frame/data`. Every site-specific value
// arrives through the config block, so a new site of the same family only
// needs a config (or a Pattern Bank preset) — never a Dart change.
library;

import 'dart:convert';

import 'html_field_extract.dart' as shared;

/// Immutable, validated view over a `secondaryFetch` config block.
class SecondaryFetchSpec {
  /// Default token regex. Handles the ad-frame family emission in both its
  /// plain (`"payloadKey":"l_…"`) and JSON-escaped (`\"payloadKey\":\"l_…\"`)
  /// forms. Used when the block sets no explicit `tokenPattern`/`tokenRegex`.
  static const defaultTokenPattern = r'payloadKey\D{0,8}([lmc]_[a-f0-9]+)';

  /// Whether the block exists and is switched on.
  final bool enabled;

  /// Regex (with one capture group, or a `(?<key>…)` named group) locating
  /// the token in the first response. Config keys: `tokenPattern` (preferred)
  /// or its alias `tokenRegex`.
  final String tokenPattern;

  /// Secondary URL template. Placeholders: `{origin}`, `{key}`, `{page}`,
  /// `{query}`, `{tag}`, `{contentId}`, `{pageUrl}`. Config keys: `url`
  /// (preferred) or its alias `secondaryUrlTemplate`.
  final String url;

  /// `page` (default) reuses the first request URL as `Referer`,
  /// `origin` sends the bare origin, anything else is sent verbatim.
  final String referer;

  /// Dot path into the decoded response JSON. Empty means "the body itself".
  final String payloadPath;

  /// CJK-XOR obfuscation key. Null/empty means the payload is plain JSON.
  final String? decodeKey;

  /// Dot path to the item array (list surfaces).
  final String itemsPath;

  /// Dot path to the image array (reader surfaces).
  final String imagesPath;

  /// Canonical field name -> `{path|selector, transform?, regex?}`.
  final Map<String, dynamic> itemFields;

  /// `page` / `total` / `lastPage` -> dot paths inside the decoded payload.
  final Map<String, String> pagination;

  /// How long to wait for the secondary request before falling back.
  final Duration timeout;

  const SecondaryFetchSpec({
    required this.enabled,
    required this.tokenPattern,
    required this.url,
    required this.referer,
    required this.payloadPath,
    required this.decodeKey,
    required this.itemsPath,
    required this.imagesPath,
    required this.itemFields,
    required this.pagination,
    required this.timeout,
  });

  /// Parse a config block. Returns `null` when the block is absent, disabled,
  /// or missing the secondary URL (`url` / `secondaryUrlTemplate`) — callers
  /// then keep their existing single-step behaviour. The token regex
  /// (`tokenPattern` / `tokenRegex`) is optional: when absent, [defaultTokenPattern]
  /// handles the ad-frame family `"payloadKey":"([lmc]_[a-f0-9]+)"` emission.
  static SecondaryFetchSpec? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['enabled'] == false) return null;

    var tokenPattern = (map['tokenPattern'] as String?)?.trim() ?? '';
    if (tokenPattern.isEmpty) {
      tokenPattern = (map['tokenRegex'] as String?)?.trim() ?? '';
    }
    if (tokenPattern.isEmpty) tokenPattern = defaultTokenPattern;
    var url = (map['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      url = (map['secondaryUrlTemplate'] as String?)?.trim() ?? '';
    }
    if (url.isEmpty) return null;

    final decodeKey = (map['decodeKey'] as String?)?.trim();
    final timeoutMs = (map['timeoutMs'] as num?)?.toInt() ?? 15000;

    return SecondaryFetchSpec(
      enabled: true,
      tokenPattern: tokenPattern,
      url: url,
      referer: (map['referer'] as String?)?.trim() ?? 'page',
      payloadPath: (map['payloadPath'] as String?)?.trim() ?? '',
      decodeKey: (decodeKey == null || decodeKey.isEmpty) ? null : decodeKey,
      itemsPath: (map['itemsPath'] as String?)?.trim() ?? 'items',
      imagesPath: (map['imagesPath'] as String?)?.trim() ?? 'images',
      itemFields:
          (map['itemFields'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      pagination:
          (map['pagination'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const <String, String>{},
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  // ── step 1: token extraction ───────────────────────────────────────────────

  /// Token from the first response body, or `null` when the page does not
  /// carry one (e.g. the site served the static/SEO variant instead).
  ///
  /// Group config: a `(?<key>…)` named group wins when present, else the
  /// first numbered capture group, else the whole match.
  String? resolveToken(String body) {
    if (body.isEmpty) return null;
    final RegExp regex;
    try {
      regex = RegExp(tokenPattern);
    } catch (_) {
      return null;
    }
    final match = regex.firstMatch(body);
    if (match == null) return null;
    String? value;
    try {
      value = match.namedGroup('key');
    } catch (_) {
      value = null;
    }
    value ??= (match.groupCount >= 1 ? match.group(1) : match.group(0));
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  // ── step 2: secondary URL + referer ────────────────────────────────────────

  /// Absolute URL for the secondary request.
  String resolveUrl({
    required String pageUrl,
    required String key,
    Map<String, String> extra = const <String, String>{},
  }) {
    var out = url;
    for (final entry in extra.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    out = out
        .replaceAll('{key}', Uri.encodeQueryComponent(key))
        .replaceAll('{origin}', originOf(pageUrl))
        .replaceAll('{pageUrl}', pageUrl);
    if (!out.startsWith('http')) {
      out = '${originOf(pageUrl)}$out';
    }
    return out;
  }

  /// `Referer` value for the secondary request.
  String resolveReferer(String pageUrl) {
    switch (referer.toLowerCase()) {
      case '':
      case 'page':
        return pageUrl;
      case 'origin':
        return originOf(pageUrl);
      default:
        return referer;
    }
  }

  /// Scheme + host (+ port) of [url], or `''` when unparseable.
  static String originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    return uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
  }

  // ── step 3: payload decoding ───────────────────────────────────────────────

  /// Decode a secondary response body into the **root** JSON object.
  ///
  /// When `payloadPath` points at an encoded string field, that field is
  /// decoded (CJK-XOR when `decodeKey` is set) and replaced in place, so
  /// `itemsPath`, `imagesPath` and `pagination.*` all resolve against one
  /// object. Use [payloadOf] to read the decoded payload itself.
  ///
  /// Returns `null` when the body is not the expected payload (expired key,
  /// `{"error": …}`, HTML error page, …) so callers fall back cleanly.
  dynamic decodeBody(String body) {
    final decoded = tryDecodeJson(body);
    if (decoded == null) return null;
    if (payloadPath.isEmpty) return decoded;

    final target = resolvePath(decoded, payloadPath);
    if (target == null) return null;
    if (target is Map || target is List) return decoded;
    if (target is! String) return null;

    var payload = target.trim();
    if (payload.isEmpty) return null;
    if (decodeKey != null) {
      payload = decodeObfuscated(payload, decodeKey!);
    }
    final inner = tryDecodeJson(payload);
    if (inner == null) return null;
    _assignPath(decoded, payloadPath, inner);
    return decoded;
  }

  /// The decoded payload object (the value at `payloadPath`), or [root]
  /// itself when the block declares no `payloadPath`.
  dynamic payloadOf(dynamic root) {
    if (payloadPath.isEmpty) return root;
    return resolvePath(root, payloadPath) ?? root;
  }

  /// CJK-XOR de-obfuscation used by the Next.js ad-frame family.
  ///
  /// Every character is `(codeUnit - 0x4E00) ^ key[i % key.length]`; the
  /// payload is the JSON text that comes back out. Exposed as a static so
  /// tests and the reader resolver share one implementation.
  static String decodeObfuscated(String body, String key) {
    final out = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      final code = body.codeUnitAt(i) - 0x4E00;
      if (code < 0) continue;
      out.writeCharCode(code ^ key.codeUnitAt(i % key.length));
    }
    return out.toString();
  }

  // ── step 4: shape extraction ───────────────────────────────────────────────

  /// Item maps from the decoded payload, mapped to canonical field names.
  List<Map<String, dynamic>> extractItems(dynamic root) {
    final base = _baseFor(root, itemsPath);
    final dynamic raw;
    if (base is List) {
      // A payload that *is* the array needs no path (plain JSON APIs).
      raw = base;
    } else {
      raw = itemsPath.isEmpty ? base : resolvePath(base, itemsPath);
    }
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final mapped = _mapItem(entry.cast<String, dynamic>());
      if (mapped.isNotEmpty) out.add(mapped);
    }
    return out;
  }

  /// Pagination signals from the decoded payload. Absent keys are omitted.
  Map<String, int> extractPagination(dynamic root) {
    final out = <String, int>{};
    for (final entry in pagination.entries) {
      final base = _baseFor(root, entry.value);
      final value = resolvePath(base, entry.value);
      final asInt = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
      if (asInt != null) out[entry.key] = asInt;
    }
    return out;
  }

  /// Image URLs from the decoded payload (reader surfaces).
  List<String> extractImages(dynamic root) {
    final base = _baseFor(root, imagesPath);
    final dynamic raw;
    if (base is List) {
      raw = base;
    } else {
      raw = imagesPath.isEmpty ? base : resolvePath(base, imagesPath);
    }
    if (raw is! List) return const <String>[];
    return raw
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
  }

  /// Pick the object a shape path resolves against: the root when the path
  /// lives there (list surfaces keep `items` + `pagination` side by side),
  /// else the decoded payload object (detail/reader surfaces wrap it).
  dynamic _baseFor(dynamic root, String path) {
    if (path.isEmpty) return root;
    if (resolvePath(root, path) != null) return root;
    final inner = payloadOf(root);
    if (!identical(inner, root) && resolvePath(inner, path) != null) {
      return inner;
    }
    return root;
  }

  Map<String, dynamic> _mapItem(Map<String, dynamic> item) {
    if (itemFields.isEmpty) return item;
    final out = <String, dynamic>{};
    for (final entry in itemFields.entries) {
      final def = entry.value;
      final path = def is Map
          ? (def['path'] ?? def['selector'])?.toString()
          : def?.toString();
      if (path == null || path.isEmpty) continue;
      final value = resolvePath(item, path);
      if (value == null) continue;
      var text = value is String ? value : value.toString();

      if (def is Map) {
        final regexSrc = def['regex']?.toString();
        if (regexSrc != null && regexSrc.isNotEmpty) {
          try {
            final match = RegExp(regexSrc).firstMatch(text);
            if (match != null) {
              text =
                  (match.groupCount >= 1 ? match.group(1) : match.group(0)) ??
                  '';
            }
          } catch (_) {
            // Malformed regex in config: keep the raw value.
          }
        }
        final transform = def['transform']?.toString();
        if (transform != null && transform.isNotEmpty) {
          text = shared.applyFieldTransform(text, transform);
        }
      }

      if (text.isNotEmpty) out[entry.key] = text;
    }
    return out;
  }
}

/// Dot-path lookup (`pagination.last_page`, `items.0.ur`).
///
/// Returns `null` for a missing path; numeric segments index into lists.
dynamic resolvePath(dynamic root, String path) {
  if (path.isEmpty) return root;
  dynamic current = root;
  for (final segment in path.split('.')) {
    if (segment.isEmpty) continue;
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
    if (current == null) return null;
  }
  return current;
}

/// Tolerant JSON decode: `null` instead of throwing on malformed input.
dynamic tryDecodeJson(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  try {
    return json.decode(trimmed);
  } catch (_) {
    return null;
  }
}

/// Write [value] at a dot path inside an already-parsed JSON tree.
///
/// Used to put a decoded payload back where the encoded string lived so all
/// sibling shape paths (`items`, `pagination`, …) keep resolving.
void _assignPath(dynamic root, String path, dynamic value) {
  final segments = path.split('.').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return;
  dynamic current = root;
  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return;
      current = current[index];
    } else {
      return;
    }
    if (current == null) return;
  }
  final last = segments.last;
  if (current is Map) {
    current[last] = value;
  } else if (current is List) {
    final index = int.tryParse(last);
    if (index != null && index >= 0 && index < current.length) {
      current[index] = value;
    }
  }
}
