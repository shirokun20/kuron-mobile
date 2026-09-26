// Chapter-image resolution modes extracted from
// [GenericScraperAdapter] (task 4.1). Pure extraction logic lives
// here; network orchestration stays in the adapter. The adapter
// owns one instance and delegates — behavior is unchanged.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:logger/logger.dart';

import '../models/source_config_runtime.dart';
import '../parsers/generic_html_parser.dart';
import '../url_builder/generic_url_builder.dart';

class ReaderImageResolver {
  final GenericUrlBuilder _urlBuilder;
  final GenericHtmlParser _parser;
  final Logger _logger;
  final String _sourceId;

  ReaderImageResolver({
    required GenericUrlBuilder urlBuilder,
    required GenericHtmlParser parser,
    required Logger logger,
    required String sourceId,
  })  : _urlBuilder = urlBuilder,
        _parser = parser,
        _logger = logger,
        _sourceId = sourceId;

  // Returns the decoded JSON string, or null when not present / garbled.

  // The page references the payload as `"chaotic_payload":"$17"` (a Next.js
  // flight ref), but the string itself is pushed separately:
  // `self.__next_f.push([1,"<obfuscated>"])`. The obfuscated chunk is the
  // only push whose body starts with CJK glyphs (0x4E00+).
  static final chaoticPushRegex = RegExp(
    r'''self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)</script>''',
    dotAll: true,
  );

  String? decodeChaoticPayload(
    String htmlContent, {
    required String? key,
  }) {
    if (key == null || key.isEmpty) return null;
    String? body;
    for (final match in chaoticPushRegex.allMatches(htmlContent)) {
      final candidate = match.group(1)!;
      if (candidate.isNotEmpty && candidate.codeUnitAt(0) >= 0x4E00) {
        body = candidate;
        break;
      }
    }
    if (body == null) return null;

    // Unescape the JSON string body (\uXXXX, \", \\, \n, ...).
    String unescaped;
    try {
      unescaped = json.decode('"$body"') as String;
    } catch (e) {
      _logger.w('$_sourceId chaotic_payload unescape failed: $e');
      return null;
    }

    final out = StringBuffer();
    for (var i = 0; i < unescaped.length; i++) {
      final code = unescaped.codeUnitAt(i) - 0x4E00;
      if (code < 0) continue;
      out.writeCharCode(code ^ key.codeUnitAt(i % key.length));
    }
    return out.toString();
  }

  // Convert a field definition map to a [FieldSelector].
  FieldSelector? fieldDefToSelector(Map<String, dynamic> def) {
    final selector = def['selector'] as String?;
    if (selector == null || selector.isEmpty) return null;
    return FieldSelector(
      selector: selector,
      attribute: def['attribute'] as String?,
      type: (def['type'] as String?) ?? 'css',
      regex: def['regex'] as String?,
      fallback: def['fallback'] as String?,
    );
  }

  Map<String, dynamic>? extractAjaxRequestFields({
    required dom.Document readerDocument,
    required Map<String, dynamic> requestConfig,
    required String fieldGroup,
  }) {
    final defs =
        (requestConfig[fieldGroup] as Map?)?.cast<String, dynamic>() ?? {};
    final values = <String, dynamic>{};

    for (final entry in defs.entries) {
      final name = entry.key;
      final rawDef = entry.value;
      final required = rawDef is Map
          ? (rawDef.cast<String, dynamic>()['required'] as bool? ?? true)
          : true;

      final value = extractAjaxRequestFieldValue(
        readerDocument: readerDocument,
        definition: rawDef,
      );
      if ((value == null || value.isEmpty) && required) {
        _logger.w(
          '$_sourceId ajaxHtmlImages: missing required $fieldGroup field "$name"',
        );
        return null;
      }
      if (value != null && value.isNotEmpty) {
        values[name] = value;
      }
    }

    return values;
  }

  String? extractAjaxRequestFieldValue({
    required dom.Document readerDocument,
    required dynamic definition,
  }) {
    if (definition is String) return definition.trim();
    if (definition is num || definition is bool) return definition.toString();
    if (definition is! Map) return null;

    final map = definition.cast<String, dynamic>();
    final constant = map['value'];
    if (constant != null) {
      return constant.toString().trim();
    }

    final selector = fieldDefToSelector(map);
    if (selector == null) return null;
    final value = _parser.extractString(readerDocument, selector)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  List<String> extractScriptSlidesImageUrls(String htmlContent) {
    final slidesMatch = RegExp(
      r'slides_p_path\s*=\s*\[(.*?)\]\s*;',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(htmlContent);
    if (slidesMatch == null) {
      return const [];
    }

    final rawArray = slidesMatch.group(1);
    if (rawArray == null || rawArray.isEmpty) {
      return const [];
    }

    final encodedItems = RegExp(r"""["']([^"']+)["']""")
        .allMatches(rawArray)
        .map((match) => match.group(1))
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (encodedItems.isEmpty) {
      return const [];
    }

    final decodedUrls = <String>[];
    for (final item in encodedItems) {
      final decoded = decodeMaybeBase64Url(item);
      if (decoded != null) {
        decodedUrls.add(decoded);
      }
    }

    return decodedUrls;
  }

  String? decodeMaybeBase64Url(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    try {
      final decoded = utf8.decode(base64.decode(value)).trim();
      if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
        return decoded;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String? decodeBase64(String value) {
    try {
      final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      return null;
    }
  }

  // Extract image URLs from a `chapterData` JS variable pattern.
  ///
  // Matches `<script>chapterData = {"data":"<base64>","base":"<cdn>"}</script>`
  // where `data` is a base64-encoded JSON array of `{src, w, h}` entries.
  // Full CDN URL = `$base/$src`.
  List<String> extractChapterDataScriptImageUrls(
    String htmlContent, {
    required Map<String, dynamic> readerConfig,
  }) {
    final inlineChapterDataMatch = RegExp(
      r'''chapterData\s*=\s*\{[^}]*?"data"\s*:\s*"([^"]+)"\s*,\s*"base"\s*:\s*"([^"]+)"\s*\}''',
      dotAll: true,
    ).firstMatch(htmlContent);

    String? base64Str;
    String? baseUrl;

    if (inlineChapterDataMatch != null) {
      base64Str = inlineChapterDataMatch.group(1);
      baseUrl = inlineChapterDataMatch.group(2);
    } else {
      // Variant used by ManhwaRead/HentaiRead:
      // `var chapterData = {"data":"<base64>"}` (no `base`) — relative srcs
      // like `94297/mr_001.jpg` resolve against the CDN host:
      // `https://{cdnHost}/{currentId}/{chapterId}/{src}`, where
      // `currentId` (manga id) and `chapterId` come from `localStaticData`.
      final chapterDataNoBaseMatch = RegExp(
        r'''chapterData\s*=\s*\{[^}]*?"data"\s*:\s*"([^"]+)"\s*\}''',
        dotAll: true,
      ).firstMatch(htmlContent);
      if (chapterDataNoBaseMatch != null) {
        final cdnHost = readerConfig['cdnHost'] as String?;
        final localStatic = RegExp(
          r'''localStaticData\s*=\s*\{.*?"currentId"\s*:\s*(\d+).*?"chapterId"\s*:\s*(\d+)''',
          dotAll: true,
        ).firstMatch(htmlContent);
        if (cdnHost != null && cdnHost.isNotEmpty && localStatic != null) {
          base64Str = chapterDataNoBaseMatch.group(1);
          baseUrl = 'https://$cdnHost/${localStatic.group(1)}/'
              '${localStatic.group(2)}';
          _logger.d('$_sourceId chapterDataScript: manhwaread-style '
              'script, cdnHost=$cdnHost, '
              'mangaId=${localStatic.group(1)}, '
              'chapterId=${localStatic.group(2)}');
        } else {
          _logger.d('$_sourceId chapterDataScript: chapterData found but '
              'missing cdnHost/localStaticData; skipping');
        }
      }
    }

    if (base64Str == null) {
      final scriptBaseUrlMatch = RegExp(
        r'''single-chapter-js-extra[^>]*>[\s\S]*?"baseUrl"\s*:\s*"([^"]+)"''',
        dotAll: true,
      ).firstMatch(htmlContent);
      final scriptDataMatch = RegExp(
        r'''single-chapter-js-before[^>]*>[\s\S]*?([A-Za-z0-9+/=]*ey[A-Za-z0-9+/=]+)''',
        dotAll: true,
      ).firstMatch(htmlContent);

      baseUrl = scriptBaseUrlMatch?.group(1);
      base64Str = scriptDataMatch?.group(1);
    }

    if (base64Str == null || baseUrl == null) {
      _logger.d(
          '$_sourceId chapterDataScript: regex no match in ${htmlContent.length} bytes');
      return const [];
    }

    _logger.d(
        '$_sourceId chapterDataScript: regex matched, base=$baseUrl, base64Len=${base64Str.length}');

    String? decodedJson;
    try {
      final padded = base64Str.padRight((base64Str.length + 3) ~/ 4 * 4, '=');
      decodedJson = utf8.decode(base64.decode(padded));
      _logger.d(
          '$_sourceId chapterDataScript: base64 decoded OK, len=${decodedJson.length}');
    } catch (e) {
      _logger.w('$_sourceId chapterDataScript: base64 decode FAILED', error: e);
      return const [];
    }

    try {
      final decoded = json.decode(decodedJson);
      final items = switch (decoded) {
        final List<dynamic> list => list,
        final Map<String, dynamic> object =>
          (((object['data'] as Map<String, dynamic>?)?['chapter']
                  as Map<String, dynamic>?)?['images'] as List<dynamic>?) ??
              const <dynamic>[],
        _ => const <dynamic>[],
      };
      _logger.d(
          '$_sourceId chapterDataScript: JSON parsed OK, ${items.length} images');
      final resolvedBaseUrl = baseUrl;
      return items
          .map((item) {
            final src = (item as Map<String, dynamic>)['src'] as String?;
            if (src == null || src.isEmpty) return null;
            final base = resolvedBaseUrl.endsWith('/')
                ? resolvedBaseUrl
                : '$resolvedBaseUrl/';
            final url = src.startsWith('http') ? src : '$base$src';
            _logger.t('$_sourceId chapterDataScript: image $url');
            return url;
          })
          .whereType<String>()
          .toList();
    } catch (e) {
      _logger.w('$_sourceId chapterDataScript: JSON parse FAILED', error: e);
      return const [];
    }
  }

  List<String> normalizeChapterImageUrls(List<String> values) {
    if (values.isEmpty) return const [];

    final expanded = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final parsed = json.decode(trimmed);
          if (parsed is List) {
            for (final entry in parsed) {
              final asString = entry.toString();
              if (asString.isNotEmpty) {
                expanded.add(asString);
              }
            }
            continue;
          }
        } catch (_) {}
      }
      expanded.add(value);
    }

    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in expanded) {
      final sanitized = sanitizeImageUrl(raw);
      if (sanitized.isEmpty) continue;
      final resolved = _urlBuilder.resolve(sanitized, const {});
      if (seen.add(resolved)) {
        normalized.add(resolved);
      }
    }

    return normalized;
  }

  List<String> extractPreviewCdnImageUrls(String htmlContent) {
    final matches = RegExp(
      r'''https?:\/\/hencover\.xyz\/preview\/[^"' <]+''',
      caseSensitive: false,
    ).allMatches(htmlContent);

    final urls = <String>[];
    final seen = <String>{};
    for (final match in matches) {
      final raw = match.group(0);
      if (raw == null || raw.isEmpty) continue;
      final cleaned = raw.replaceAll(r'\/', '/');
      if (seen.add(cleaned)) {
        urls.add(cleaned);
      }
    }
    return urls;
  }

  String sanitizeImageUrl(String value) {
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

    //  fix broken hostname in HTML (missing dot). Known cases:
    // "images2/imgbox.com" -> "images2.imgbox.com"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'//([^./]+)/((?:imgbox|imgbb|pixhost|ibucket|imagebam)\.com/)'),
      (m) => '//${m[1]}.${m[2]}',
    );

    if (cleaned.startsWith('//')) {
      cleaned = 'https:$cleaned';
    }

    // Relative paths (e.g. photos18 `/images/node/...avif`) resolve against
    // the source baseUrl so list covers are always fetchable.
    if (cleaned.startsWith('/') &&
        !cleaned.startsWith('//') &&
        !_urlBuilder.baseUrl.startsWith('/')) {
      cleaned = '${_urlBuilder.baseUrl}$cleaned';
    }

    // Android network_security_config blocks cleartext http:// — native
    // image downloads fail with a transport error. Sites serving page markup
    // over https but embedding `http://` image srcs (madara themes:
    // manhwaclub.net) always also answer on https (301 at worst), so upgrade
    // when the host matches the source baseUrl.
    if (cleaned.startsWith('http://')) {
      final baseHost = Uri.tryParse(_urlBuilder.baseUrl)?.host ?? '';
      final imgHost = Uri.tryParse(cleaned)?.host ?? '';
      if (baseHost.isNotEmpty && imgHost == baseHost) {
        cleaned = 'https:${cleaned.substring(5)}';
      }
    }

    return cleaned;
  }

  String inferImageExtension(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return 'jpg';

    final clean = imageUrl.split('?').first;
    final extMatch = RegExp(
            r'\.(jpg|jpeg|webp|png|gif)$|\d+t\.(jpg|jpeg|webp|png|gif)$',
            caseSensitive: false)
        .firstMatch(clean);
    return (extMatch?.group(1) ?? extMatch?.group(2) ?? 'jpg').toLowerCase();
  }

  // Build HentaiFox image URLs using per-page extension mapping from `g_th`.
  List<String> buildHentaiFoxImageUrlsFromSample(
    String sampleUrl,
    int pageCount,
    Map<int, String> extByPage,
  ) {
    if (sampleUrl.isEmpty || pageCount <= 0) return const [];

    final normalized =
        sampleUrl.startsWith('//') ? 'https:$sampleUrl' : sampleUrl;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty || uri.pathSegments.isEmpty) {
      return const [];
    }

    final segments = List<String>.from(uri.pathSegments);
    final fileName = segments.removeLast();
    final defaultExtMatch =
        RegExp(r'^\d+\.(jpg|jpeg|webp|png|gif)$', caseSensitive: false)
            .firstMatch(fileName);
    final defaultExt = (defaultExtMatch?.group(1) ?? 'jpg').toLowerCase();

    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final origin = uri.hasPort
        ? '$scheme://${uri.host}:${uri.port}'
        : '$scheme://${uri.host}';
    final pathPrefix = '/${segments.join('/')}';

    return List<String>.generate(
      pageCount,
      (index) {
        final page = index + 1;
        final ext = (extByPage[page] ?? defaultExt).toLowerCase();
        return '$origin$pathPrefix/$page.$ext';
      },
      growable: false,
    );
  }

  // Parse HentaiFox `g_th` map and return image extension by page number.
  Map<int, String> extractHentaiFoxExtensionsByPage(String html) {
    if (html.isEmpty) return const {};

    String? rawJson;
    final parseJsonMatch = RegExp(
      r"var\s+g_th\s*=\s*\$\.parseJSON\(\s*'(.+?)'\s*\)\s*;",
      dotAll: true,
    ).firstMatch(html);
    if (parseJsonMatch != null) {
      rawJson = parseJsonMatch.group(1);
    }

    rawJson ??= RegExp(
      r'var\s+g_th\s*=\s*(\{.+?\})\s*;',
      dotAll: true,
    ).firstMatch(html)?.group(1);

    if (rawJson == null || rawJson.isEmpty) {
      return const {};
    }

    try {
      final parsed = json.decode(rawJson) as Map<String, dynamic>;
      const extMap = {
        'j': 'jpg',
        'w': 'webp',
        'p': 'png',
        'g': 'gif',
        'b': 'bmp',
      };

      final result = <int, String>{};
      parsed.forEach((key, value) {
        final page = int.tryParse(key);
        if (page == null) return;

        final parts = value.toString().split(',');
        if (parts.isEmpty || parts.first.isEmpty) return;

        final extCode = parts.first.trim().toLowerCase();
        final ext = extMap[extCode];
        if (ext != null && ext.isNotEmpty) {
          result[page] = ext;
        }
      });
      return result;
    } catch (_) {
      return const {};
    }
  }

}