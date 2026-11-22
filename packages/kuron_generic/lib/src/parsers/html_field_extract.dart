// Shared pure-Dart HTML field extraction for scraper-type sources.
//
// This module is the single source of truth for the DOM-walking half of
// `GenericScraperAdapter`: element/document field extraction, tag-object
// parsing, slug/regex transforms, image-URL sanitizing, and list-page
// pagination signals. Both the in-isolate sync path in the adapter AND the
// `Isolate.run()` jobs in `html_isolate_parse.dart` call these exact
// functions, so behavior (including `normalizeWhitespace` / `cleanText`
// handling) is identical wherever the parse runs.
//
// Rules for this file:
// - Pure Dart only (`dart:convert`, `package:html`, `kuron_core`).
// - No `Logger`, no `Dio`, no closures over non-sendable objects — every
//   function takes plain parameters so `Isolate.run()` entry points can call
//   them with values that cross isolate boundaries.
// - Tag objects cross isolates as `Map<String, dynamic>` rows
//   (`tagMapKeys` lists which result keys hold them); the adapter rebuilds
//   `Tag` entities on the calling isolate before handing fields to
//   `GenericContentMapper`.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:kuron_core/kuron_core.dart';

import '../models/source_config_runtime.dart';
import 'generic_html_parser.dart';

/// Result key holding tag-object rows is recorded here so the caller can
/// rebuild `Tag` entities before mapping.
const String tagMapKeysMarker = '__tagMapKeys';

/// `Map<String, dynamic>` view of a raw config field definition.
Map<String, dynamic>? toDefMap(dynamic def) {
  if (def is Map<String, dynamic>) return def;
  if (def is Map) return def.cast<String, dynamic>();
  if (def is String) return <String, dynamic>{'selector': def};
  return null;
}

/// Converts a field definition map to a [FieldSelector].
///
/// Mirrors `ReaderImageResolver.fieldDefToSelector` exactly: `attribute` may
/// be a single string (legacy) or a list (first-non-empty-wins chain).
FieldSelector? fieldDefToSelector(Map<String, dynamic> def) {
  final selector = def['selector'] as String?;
  if (selector == null || selector.isEmpty) return null;
  final rawAttribute = def['attribute'];
  final chain = rawAttribute is List
      ? rawAttribute.map((e) => e.toString().trim()).toList()
      : const <String>[];
  return FieldSelector(
    selector: selector,
    attribute: chain.isNotEmpty ? chain.first : rawAttribute as String?,
    attributes: chain,
    type: (def['type'] as String?) ?? 'css',
    regex: def['regex'] as String?,
    prefix: def['prefix'] as String?,
    suffix: def['suffix'] as String?,
    fallback: def['fallback'] as String?,
  );
}

/// Adapter-style regex extraction (no `dotAll`): first capture group wins,
/// else the whole match. Returns null on no-match or bad pattern.
///
/// NOTE: `GenericHtmlParser` uses `dotAll: true`; the adapter helpers ported
/// here intentionally do not — call sites below run the adapter variant.
String? applyAdapterRegex(String input, String pattern) {
  try {
    final match = RegExp(pattern).firstMatch(input);
    if (match == null) return null;
    return match.groupCount > 0 ? match.group(1) : match.group(0);
  } catch (_) {
    return null;
  }
}

/// Decodes percent-encoded segments without throwing on malformed input.
///
/// Ported from `SearchQueryRouting.decodePercentEncodedSegments` (pure
/// algorithm, no instance state): returns null when a `%` escape is
/// incomplete or undecodable so callers can keep the raw slug.
String? decodePercentEncodedSegments(String slug) {
  bool isHexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  final output = StringBuffer();
  var index = 0;
  while (index < slug.length) {
    final current = slug.codeUnitAt(index);
    if (current != 0x25) {
      output.writeCharCode(current);
      index++;
      continue;
    }

    if (index + 2 >= slug.length ||
        !isHexDigit(slug.codeUnitAt(index + 1)) ||
        !isHexDigit(slug.codeUnitAt(index + 2))) {
      return null;
    }

    final bytes = <int>[];
    while (index + 2 < slug.length && slug.codeUnitAt(index) == 0x25) {
      final first = slug.codeUnitAt(index + 1);
      final second = slug.codeUnitAt(index + 2);
      if (!isHexDigit(first) || !isHexDigit(second)) {
        return null;
      }
      bytes.add(int.parse(slug.substring(index + 1, index + 3), radix: 16));
      index += 3;
    }

    try {
      output.write(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  return output.toString();
}

/// Decode percent escapes in a slug, keeping the raw slug on failure.
String decodeSlugComponent(String slug) {
  if (!slug.contains('%')) return slug;
  try {
    return Uri.decodeComponent(slug);
  } catch (_) {
    return decodePercentEncodedSegments(slug) ?? slug;
  }
}

/// Extracts the last meaningful path slug from a URL.
///
/// Matches `/manga/<slug>` and `/<slug>-chapter-<n>` shapes before falling
/// back to `Uri.parse` segment logic. Regex matching tolerates raw Unicode
/// path characters which may throw inside `Uri.parse`.
String extractSlugFromUrl(String url) {
  if (url.isEmpty) return '';

  final patterns = <RegExp>[
    RegExp(r'/manga/([^/?#]+)'),
    RegExp(r'/manhwa/([^/?#]+(?:/[^/?#]+)?)'),
    RegExp(r'/([^/?#]+?-chapter-[\d.-]+)(?:/|[?#]|$)'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(url);
    final slug = match?.group(1);
    if (slug != null && slug.isNotEmpty) {
      return decodeSlugComponent(slug);
    }
  }

  try {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      final mangaIndex = segments.indexOf('manga');
      final slug = mangaIndex != -1 && mangaIndex + 1 < segments.length
          ? segments[mangaIndex + 1]
          : segments.last;
      return decodeSlugComponent(slug);
    }
  } catch (_) {}
  return '';
}

/// Base64-decodes a UTF-8 payload, tolerating missing padding.
String? decodeBase64Value(String value) {
  try {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return utf8.decode(base64.decode(padded));
  } catch (_) {
    return null;
  }
}

/// Applies a config field transform.
///
/// Config contract: `transform: 'cleanText'` trims and collapses internal
/// whitespace on title fields. The global normalization in
/// `GenericHtmlParser` / `GenericContentMapper` remains the defensive
/// fallback for configs that do not declare the transform.
String applyFieldTransform(String value, String? transform) {
  switch (transform) {
    case 'cleanText':
      return normalizeWhitespace(value);
    case 'slug':
      return extractSlugFromUrl(value);
    case 'base64':
      return decodeBase64Value(value) ?? value;
    default:
      return value;
  }
}

/// Sanitizes an extracted image URL: strips escaping/quotes, fixes broken
/// hostnames, and resolves relative paths against [baseUrl].
///
/// Ported from `ReaderImageResolver.sanitizeImageUrl`; [baseUrl] replaces the
/// resolver's `_urlBuilder.baseUrl` so the function stays isolate-safe.
String sanitizeImageUrl(String value, String baseUrl) {
  var cleaned = value.trim();
  if (cleaned.length >= 2 &&
      ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
          (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
    cleaned = cleaned.substring(1, cleaned.length - 1);
  }

  cleaned = cleaned
      .replaceAll(r'\/', '/')
      .replaceAll(r'\n', '')
      .replaceAll(r'\r', '')
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .trim();

  //  fix broken hostname in HTML (missing dot):
  // "images2/imgbox.com" -> "images2.imgbox.com"
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'//([^./]+)/((?:imgbox|imgbb|pixhost|ibucket|imagebam)\.com/)'),
    (m) => '//${m[1]}.${m[2]}',
  );

  if (cleaned.startsWith('//')) {
    cleaned = 'https:$cleaned';
  }

  // Relative paths resolve against the source baseUrl so list covers are
  // always fetchable.
  if (cleaned.startsWith('/') &&
      !cleaned.startsWith('//') &&
      !baseUrl.startsWith('/')) {
    cleaned = '$baseUrl$cleaned';
  }

  // Bare relative paths resolve against the source baseUrl the same way. An
  // empty value is NOT a relative path — resolving it would fabricate the
  // baseUrl as an image URL.
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(cleaned);
  if (cleaned.isNotEmpty &&
      !hasScheme &&
      !cleaned.startsWith('/') &&
      !baseUrl.startsWith('/')) {
    cleaned = '$baseUrl/$cleaned';
  }

  // Android network_security_config blocks cleartext http:// — native
  // image downloads fail with a transport error. Sites serving page markup
  // over https but embedding `http://` image srcs always also answer on
  // https (301 at worst), so upgrade when the host matches the source
  // baseUrl.
  if (cleaned.startsWith('http://')) {
    final baseHost = Uri.tryParse(baseUrl)?.host ?? '';
    final imgHost = Uri.tryParse(cleaned)?.host ?? '';
    if (baseHost.isNotEmpty && imgHost == baseHost) {
      cleaned = 'https:${cleaned.substring(5)}';
    }
  }

  return cleaned;
}

/// Rebuilds [Tag] entities from isolate-safe tag rows.
///
/// Rows carry `id` (num), `name`, `type`, `slug` (nullable String), `count`
/// (num) and `url` (String, may be absent).
Tag tagFromRow(Map<String, dynamic> row) {
  return Tag(
    id: (row['id'] as num?)?.toInt() ?? 0,
    name: row['name']?.toString() ?? '',
    type: row['type']?.toString() ?? 'tag',
    count: (row['count'] as num?)?.toInt() ?? 0,
    url: row['url'] is String ? row['url'] as String : '',
    slug: row['slug'] is String ? row['slug'] as String : null,
  );
}

// ── Element / document extraction ────────────────────────────────────────────
// Ports of `GenericScraperAdapter._extractElementFields` /
// `_extractDocumentFields` minus logging. [parser] performs selector queries;
// pass the adapter's live parser on the calling isolate or a silent one
// inside `Isolate.run()`. [baseUrl] feeds `sanitizeImageUrl`.

/// Extracts a fields map from a single list-item [el].
///
/// Values are `String` or `List<String>` only (isolate-safe). `coverUrl` is
/// sanitized against [baseUrl].
Map<String, dynamic> extractElementFields(
  GenericHtmlParser parser,
  dom.Element el,
  Map<String, dynamic> fieldsConfig,
  String baseUrl,
) {
  final result = <String, dynamic>{};
  for (final entry in fieldsConfig.entries) {
    final defMap = toDefMap(entry.value);
    if (defMap == null) continue;

    final multi = defMap['multi'] as bool? ?? false;
    final transform = defMap['transform'] as String?;
    final sel = fieldDefToSelector(defMap);
    if (sel == null) continue;

    if (multi) {
      var values = el
          .querySelectorAll(sel.selector)
          .map(
            (c) => sel.attribute != null
                ? (c.attributes[sel.attribute] ?? '')
                : c.text.trim(),
          )
          .where((s) => s.isNotEmpty)
          .toList();

      // Apply regex filter if present
      if (sel.regex != null) {
        values = values
            .map((v) => applyAdapterRegex(v, sel.regex!))
            .where((v) => v != null && v.isNotEmpty)
            .cast<String>()
            .toList();
      }

      if (transform == 'slug' || transform == 'cleanText') {
        values = values
            .map((v) => applyFieldTransform(v, transform))
            .where((v) => v.isNotEmpty)
            .toList();
      }
      result[entry.key] = values;
    } else if (sel.selector == 'self') {
      var value = sel.attribute != null
          ? (el.attributes[sel.attribute] ?? '')
          : normalizeWhitespace(el.text);
      if (value.isEmpty) continue;
      if (sel.regex != null) {
        final matched = applyAdapterRegex(value, sel.regex!);
        if (matched != null && matched.isNotEmpty) value = matched;
      }
      if (transform == 'slug' && value.isNotEmpty) {
        value = extractSlugFromUrl(value);
      } else if (transform == 'cleanText' && value.isNotEmpty) {
        value = normalizeWhitespace(value);
      }
      result[entry.key] = value;
    } else {
      var value = parser.extractFromElement(el, sel) ?? '';
      if (transform == 'slug' && value.isNotEmpty) {
        value = extractSlugFromUrl(value);
      } else if (transform == 'cleanText' && value.isNotEmpty) {
        value = normalizeWhitespace(value);
      }
      if (entry.key == 'coverUrl' && value.isNotEmpty) {
        value = sanitizeImageUrl(value, baseUrl);
      }
      result[entry.key] = value;
    }
  }
  return result;
}

int _parseTagCount(String countText) {
  double multiplier = 1.0;
  var numStr = countText;
  if (countText.endsWith('k')) {
    multiplier = 1000.0;
    numStr = countText.substring(0, countText.length - 1);
  } else if (countText.endsWith('m')) {
    multiplier = 1000000.0;
    numStr = countText.substring(0, countText.length - 1);
  }
  final parsedNum = double.tryParse(numStr);
  if (parsedNum == null) return 0;
  return (parsedNum * multiplier).toInt();
}

/// Extracts a fields map from a full detail [doc].
///
/// Tag-object entries (`extractTagObjects`, `parseTagNamespace`) are returned
/// as `List<Map<String, dynamic>>` rows; their keys are listed under
/// [tagMapKeysMarker] so the caller can rebuild `Tag` entities. Everything
/// else is `String` / `List<String>`.
Map<String, dynamic> extractDocumentFields(
  GenericHtmlParser parser,
  dom.Document doc,
  Map<String, dynamic> fieldsConfig,
  String baseUrl,
) {
  final result = <String, dynamic>{};
  // Tag objects from every `extractTagObjects` field (author/artist/genres/
  // tags) are merged into `tagObjects` so GenericContentMapper can build a
  // typed Tag list instead of losing the non-`tags` fields.
  final allTagObjectMaps = <Map<String, dynamic>>[];
  final tagMapKeys = <String>[];

  for (final entry in fieldsConfig.entries) {
    final defMap = toDefMap(entry.value);
    if (defMap == null) continue;

    final multi = defMap['multi'] as bool? ?? false;
    final transform = defMap['transform'] as String?;
    final sel = fieldDefToSelector(defMap);
    if (sel == null) continue;

    if (defMap['extractTagObjects'] == true) {
      final elements = parser.selectAll(doc, sel.selector);
      final tagRows = <Map<String, dynamic>>[];
      for (final el in elements) {
        // If the element contains multiple spans (like hentairead),
        // usually the first is the name and the second is the count.
        // Fallback to the element itself if no spans exist.
        final spans = el.querySelectorAll('span');
        final nameEl = spans.isNotEmpty ? spans.first : el;

        // Honor the field's `attribute` + `transform`, otherwise fall back
        // to the element's display text as the tag name.
        final rawAttribute = sel.attribute?.trim();
        String rawName = nameEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (rawAttribute != null &&
            rawAttribute.isNotEmpty &&
            rawAttribute != 'text') {
          rawName = nameEl.attributes[rawAttribute] ?? rawName;
        }
        String name = rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (transform == 'slug' && name.isNotEmpty) {
          name = extractSlugFromUrl(name);
        }
        if (name.isEmpty) continue;

        String segmentType = '';
        String slug = '';
        final href = el.attributes['href'] ?? '';
        if (href.isNotEmpty) {
          final uri = Uri.tryParse(href);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final segments = uri.pathSegments
                .where((s) => s.isNotEmpty)
                .toList();
            if (segments.length >= 2) {
              segmentType = segments[segments.length - 2].toLowerCase();
              slug = segments.last.toLowerCase();
            } else if (segments.isNotEmpty) {
              slug = segments.last.toLowerCase();
            }
          }
        }

        // Type precedence: explicit tagType > tagTypeMap > tagTypeRegex >
        // legacy segment normalization > raw URL segment > 'tag'.
        String type = 'tag';
        final explicitType = defMap['tagType']?.toString().trim();
        final typeMap = defMap['tagTypeMap'];
        final typeRegex = defMap['tagTypeRegex']?.toString();
        if (explicitType != null && explicitType.isNotEmpty) {
          type = explicitType;
        } else if (typeMap is Map && typeMap[segmentType] != null) {
          type = typeMap[segmentType].toString();
        } else if (typeRegex != null && typeRegex.isNotEmpty) {
          final m = RegExp(typeRegex).firstMatch(segmentType);
          final g = m == null
              ? null
              : (m.groupCount > 0 ? m.group(1) : m.group(0));
          if (g != null && g.trim().isNotEmpty) type = g.trim();
        } else if (segmentType == 'circle') {
          type = 'publisher';
        } else if (segmentType.isNotEmpty) {
          type = segmentType;
        }

        int count = 0;
        if (spans.length > 1) {
          final countText = spans[1].text.trim().toLowerCase();
          if (countText.isNotEmpty) {
            count = _parseTagCount(countText);
          }
        } else {
          // Fallback for elements without separate spans for count:
          // trailing number like "Shiro Marimo 1" -> name + count 1.
          final match = RegExp(r'^(.+?)\s+(\d+[.0-9]*[kKmM]?)$')
              .firstMatch(name);
          if (match != null) {
            name = match.group(1)!.trim();
            count = _parseTagCount(match.group(2)!.trim().toLowerCase());
          }
        }

        tagRows.add(<String, dynamic>{
          'id': 0,
          'name': name,
          'type': type,
          'slug': slug,
          'count': count,
          'url': href,
        });
      }

      final seenValues = <String>{};
      final uniqueRows = tagRows
          .where((t) => seenValues.add('${t['type']}:${t['name']}'))
          .toList();

      allTagObjectMaps.addAll(uniqueRows);
      result[entry.key] = uniqueRows;
      tagMapKeys.add(entry.key);
      continue;
    }

    if (multi) {
      var values = parser.extractList(doc, sel);
      if (transform == 'slug' || transform == 'cleanText') {
        values = values
            .map((v) => applyFieldTransform(v, transform))
            .where((v) => v.isNotEmpty)
            .toList();
      } else if (transform == 'base64') {
        values = values
            .map((v) => decodeBase64Value(v) ?? v)
            .where((v) => v.isNotEmpty)
            .toList();
      }

      final seenValues = <String>{};
      values = values.where((v) => seenValues.add(v)).toList();

      // parseTagNamespace: split "namespace:name" strings into typed Tags.
      // Used by sources like E-Hentai where tag title attributes carry the
      // full "namespace:tagname" string.
      final parseNamespace = defMap['parseTagNamespace'] as bool? ?? false;
      if (parseNamespace && entry.key == 'tags') {
        final tagRows = <Map<String, dynamic>>[];
        for (final raw in values) {
          final colonIdx = raw.indexOf(':');
          if (colonIdx > 0 && colonIdx < raw.length - 1) {
            final ns = raw.substring(0, colonIdx).trim().toLowerCase();
            final tagName = raw.substring(colonIdx + 1).trim();
            if (ns.isNotEmpty && tagName.isNotEmpty) {
              tagRows.add(<String, dynamic>{
                'id': 0,
                'name': tagName,
                'type': ns,
                'slug': '',
                'count': 0,
                'url': '',
              });
              continue;
            }
          }
          tagRows.add(<String, dynamic>{
            'id': 0,
            'name': raw,
            'type': 'tag',
            'slug': '',
            'count': 0,
            'url': '',
          });
        }
        result[entry.key] = tagRows;
        tagMapKeys.add(entry.key);
      } else {
        result[entry.key] = values;
      }
    } else {
      var value = parser.extractString(doc, sel) ?? '';
      if (transform == 'slug' && value.isNotEmpty) {
        value = extractSlugFromUrl(value);
      } else if (transform == 'cleanText' && value.isNotEmpty) {
        value = normalizeWhitespace(value);
      } else if (transform == 'base64' && value.isNotEmpty) {
        value = decodeBase64Value(value) ?? value;
      }
      if (entry.key == 'coverUrl' && value.isNotEmpty) {
        value = sanitizeImageUrl(value, baseUrl);
      }
      result[entry.key] = value;
    }
  }
  if (allTagObjectMaps.isNotEmpty) {
    result['tagObjects'] = allTagObjectMaps;
  }
  if (tagMapKeys.isNotEmpty) {
    result[tagMapKeysMarker] = tagMapKeys;
  }
  return result;
}

// ── List-page + pagination signals ───────────────────────────────────────────

/// True when [selector] matches a non-disabled link in [doc].
bool hasEnabledLink(dom.Document doc, String selector) {
  final link = doc.querySelector(selector);
  if (link == null) return false;

  final href = (link.attributes['href'] ?? '').trim();
  final hxGet = (link.attributes['hx-get'] ?? '').trim();
  if ((href.isEmpty || href == '#') && hxGet.isEmpty) return false;

  final parentClass = link.parent?.attributes['class'] ?? '';
  if (parentClass.contains('disabled')) return false;

  return true;
}

/// Resolves the enabled pagination link for [selector] against [baseUrl].
String? extractEnabledLinkUrl(
  dom.Document doc,
  String? selector, {
  required String baseUrl,
}) {
  if (selector == null || selector.trim().isEmpty) return null;

  final link = doc.querySelector(selector);
  if (link == null) return null;

  final href = (link.attributes['href'] ?? '').trim();
  final hxGet = (link.attributes['hx-get'] ?? '').trim();
  if ((href.isEmpty || href == '#') && hxGet.isEmpty) return null;

  final parentClass = link.parent?.attributes['class'] ?? '';
  if (parentClass.contains('disabled')) return null;

  final candidate = href.isNotEmpty && href != '#' ? href : hxGet;
  return Uri.parse(baseUrl).resolve(candidate).toString();
}

/// Input bundle for [extractListPage] — plain JSON-safe values only.
class ListPageJob {
  final String container;
  final Map<String, dynamic> fields;
  final bool sectionFilterEnabled;
  final List<String> allowedSectionTitles;
  final List<String> idFallbackSelectors;
  final String? nextSelector;
  final String? altSelector;
  final String? linksSelector;
  final String? lastSelector;
  final bool pagedMode;

  const ListPageJob({
    required this.container,
    required this.fields,
    this.sectionFilterEnabled = false,
    this.allowedSectionTitles = const [],
    this.idFallbackSelectors = const [],
    this.nextSelector,
    this.altSelector,
    this.linksSelector,
    this.lastSelector,
    this.pagedMode = false,
  });

  Map<String, dynamic> toMap() => {
    'container': container,
    'fields': fields,
    'sectionFilterEnabled': sectionFilterEnabled,
    'allowedSectionTitles': allowedSectionTitles,
    'idFallbackSelectors': idFallbackSelectors,
    'nextSelector': nextSelector,
    'altSelector': altSelector,
    'linksSelector': linksSelector,
    'lastSelector': lastSelector,
    'pagedMode': pagedMode,
  };

  factory ListPageJob.fromMap(Map<String, dynamic> map) => ListPageJob(
    container: map['container'] as String,
    fields: (map['fields'] as Map).cast<String, dynamic>(),
    sectionFilterEnabled: map['sectionFilterEnabled'] as bool? ?? false,
    allowedSectionTitles: ((map['allowedSectionTitles'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    idFallbackSelectors: ((map['idFallbackSelectors'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    nextSelector: map['nextSelector'] as String?,
    altSelector: map['altSelector'] as String?,
    linksSelector: map['linksSelector'] as String?,
    lastSelector: map['lastSelector'] as String?,
    pagedMode: map['pagedMode'] as bool? ?? false,
  );
}

/// Parses a list/search page: item field maps plus pagination signals.
///
/// Returns an isolate-safe map:
/// - `items`: `List<Map<String, dynamic>>` raw field maps (`String` /
///   `List<String>` values, fallback-id fixup already applied).
/// - `nextPageUrl`: resolved `String?`.
/// - `hasNextByLink`: `bool` — forced-paged with items, a next URL, or an
///   enabled next/alt link (the overlap guard still runs on the caller).
/// - `totalPages`: `int?`.
Map<String, dynamic> extractListPage(
  GenericHtmlParser parser,
  dom.Document doc,
  ListPageJob job,
  String pageUrl,
  String baseUrl,
) {
  final items = <Map<String, dynamic>>[];
  final elements = parser.selectAll(doc, job.container);

  for (final el in elements) {
    if (job.sectionFilterEnabled && job.allowedSectionTitles.isNotEmpty) {
      final sectionTitle =
          el.parent?.parent?.previousElementSibling?.text
              .trim()
              .toLowerCase() ??
          '';
      final isAllowed = job.allowedSectionTitles.any(
        (needle) => sectionTitle.contains(needle),
      );
      if (sectionTitle.isNotEmpty && !isAllowed) {
        continue;
      }
    }

    final fields = extractElementFields(parser, el, job.fields, baseUrl);
    var id = (fields['id'] as String?) ?? '';
    if (id.isEmpty && job.idFallbackSelectors.isNotEmpty) {
      String fallbackHref = '';
      for (final selector in job.idFallbackSelectors) {
        final href = (el.querySelector(selector)?.attributes['href'] ?? '')
            .trim();
        if (href.isNotEmpty) {
          fallbackHref = href;
          break;
        }
      }
      final fallbackId = extractSlugFromUrl(fallbackHref);
      if (fallbackId.isNotEmpty) {
        fields['id'] = fallbackId;
        id = fallbackId;
      }
    }
    if (id.isNotEmpty) {
      items.add(fields);
    }
  }

  final nextPageUrl =
      extractEnabledLinkUrl(doc, job.nextSelector, baseUrl: pageUrl) ??
      extractEnabledLinkUrl(doc, job.altSelector, baseUrl: pageUrl);
  final forcedPaged = job.pagedMode && items.isNotEmpty;
  final hasNextByLink =
      forcedPaged ||
      nextPageUrl != null ||
      (job.nextSelector != null && hasEnabledLink(doc, job.nextSelector!)) ||
      (job.altSelector != null && hasEnabledLink(doc, job.altSelector!));

  int? totalPages;
  if (job.linksSelector != null) {
    final pageLinks = parser.selectAll(doc, job.linksSelector!);
    for (final link in pageLinks) {
      final pageText = link.text.trim();
      final pageNum = int.tryParse(pageText);
      if (pageNum != null && (totalPages == null || pageNum > totalPages)) {
        totalPages = pageNum;
      }
    }
  }

  if (totalPages == null &&
      job.lastSelector != null &&
      job.lastSelector!.isNotEmpty) {
    final lastHref = parser.extractString(
      doc,
      FieldSelector(selector: job.lastSelector!, attribute: 'href'),
    );
    if (lastHref != null && lastHref.isNotEmpty) {
      final match = RegExp(r'/page/(\d+)/').firstMatch(lastHref);
      totalPages = int.tryParse(match?.group(1) ?? '');
    }
  }

  if (totalPages == null) {
    final pageLinks = parser.selectAll(doc, 'a[href]');
    for (final link in pageLinks) {
      final href = (link.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      final match = RegExp(r'/page/(\d+)/').firstMatch(href);
      final pageNum = int.tryParse(match?.group(1) ?? '');
      if (pageNum != null && (totalPages == null || pageNum > totalPages)) {
        totalPages = pageNum;
      }
    }
  }

  return {
    'items': items,
    'nextPageUrl': nextPageUrl,
    'hasNextByLink': hasNextByLink,
    'totalPages': totalPages,
  };
}
