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
    final rawAttribute = def['attribute'];
    // `"attribute": "src"` (legacy) or `"attribute": ["data-src","src"]`
    // — the chain form is first-non-empty-wins.
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
      // A broad reader selector can grab `<source src="…master.m3u8">`; an
      // HLS/mp4 URL is not a page image. Drop it — video-only chapters
      // report zero images (issue #68) instead of a broken player.
      if (_isVideoUrl(sanitized)) continue;
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

  /// Images embedded as JSON in a script tag, e.g. hentai4free's
  /// `<script type="application/json" id="h4f-r2-data">`
  /// `{"images":[{"src":"https://…/1.webp"},…]}</script>`.
  /// Config: `images: {scriptJson: {id, items, url}}`.
  ///
  /// `scriptId` also matches a plain JS variable when no element with that
  /// id exists — `var ajax = {"pages":[…]}`, `var chapter_preloaded_images =
  /// ["…jpg", …]` (issue #67: those payloads have no DOM nodes at all).
  /// `items` is dotted (`"data.pages"`); `url` is ignored for plain-string
  /// arrays.
  List<String> extractScriptJsonImages(
    String htmlContent, {
    required String scriptId,
    required String itemsKey,
    required String urlKey,
  }) {
    if (scriptId.isEmpty) return const [];

    final elementMatch = RegExp(
      '<script[^>]*id="$scriptId"[^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(htmlContent);

    final dynamic decoded;
    if (elementMatch != null) {
      decoded = _tryDecodeJson(elementMatch.group(1)!.trim());
    } else {
      final variableBody = _jsVariableBody(htmlContent, scriptId);
      if (variableBody == null) {
        _logger.d('$_sourceId scriptJson: neither #id nor JS var "$scriptId"');
        return const [];
      }
      decoded = _tryDecodeJson(variableBody);
    }
    if (decoded == null) return const [];

    final items = itemsKey.isEmpty ? decoded : _digValue(decoded, itemsKey);
    if (items is! List) return const [];

    final urls = <String>[];
    final seen = <String>{};
    for (final item in items) {
      String url;
      if (item is Map) {
        url = item[urlKey]?.toString() ?? '';
      } else {
        // Flat string array (`["…/001.jpg", …]`) — the entry IS the URL, and
        // config `url` defaults to `src`, which never matches a bare string.
        final raw = item.toString().trim();
        url = raw.startsWith('http') || raw.startsWith('/') ? raw : '';
      }
      if (url.isNotEmpty && seen.add(url)) urls.add(url);
    }
    return urls;
  }

  dynamic _tryDecodeJson(String body) {
    try {
      return json.decode(body);
    } catch (e) {
      _logger.w('$_sourceId scriptJson: JSON parse FAILED', error: e);
      return null;
    }
  }

  /// Body of `name = <json>` inside any `<script>` block. Quote/bracket aware
  /// so a `;` or `}` inside a string or nested object doesn't truncate it.
  String? _jsVariableBody(String htmlContent, String name) {
    final assign = RegExp(
      '(?:var|let|const)?\\s*${RegExp.escape(name)}\\s*(?:\\.\\w+)*\\s*=\\s*',
    ).firstMatch(htmlContent);
    if (assign == null) return null;

    var depth = 0;
    var quote = '';
    var escaped = false;
    for (var i = assign.end; i < htmlContent.length; i++) {
      final c = htmlContent[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == r'\' && quote.isNotEmpty) {
        escaped = true;
        continue;
      }
      if (quote.isNotEmpty) {
        if (c == quote) quote = '';
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        continue;
      }
      if (c == '[' || c == '{') depth++;
      if (c == ']' || c == '}') {
        depth--;
        if (depth == 0) return htmlContent.substring(assign.end, i + 1);
      }
    }
    return null;
  }

  dynamic _digValue(dynamic root, String dottedKey) {
    var current = root;
    for (final part in dottedKey.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Video media referenced by a chapter page — direct mp4/webm or HLS
  /// `master.m3u8` (issue #68: poster-only readers look broken).
  /// Samplers use this to skip AI-animation chapters.
  ///
  /// No dedupe here: normalization comes later, in the caller, and only a
  /// normalized URL can be compared safely (`//host/x` vs `https://host/x`).
  List<String> extractChapterVideoUrls(String htmlContent) {
    final urls = <String>[];
    for (final match in _videoUrlPattern.allMatches(htmlContent)) {
      final url = match.group(1);
      if (url == null || url.isEmpty) continue;
      urls.add(url);
    }
    return urls;
  }

  /// Config-scoped chapter video extraction.
  ///
  /// Reads `scraper.selectors.reader.video`, the sibling of `reader.images`:
  ///
  /// ```jsonc
  /// "video": {
  ///   "container": ".chapter-video-frame",   // absent ⇒ whole chapter HTML
  ///   "selector": "video source, video",     // element carrying the stream
  ///   "attribute": "src",                    // URL attribute (string or list)
  ///   "dataAttribute": "data-vvl-src",       // wrapper carrying it in data-*
  ///   "requireChapterType": "chapter-type-video"  // site's "this is video" mark
  /// }
  /// ```
  ///
  /// No `video` block ⇒ [extractChapterVideoUrls] (page-wide scan) — the
  /// compatibility contract for every already-shipped config. Returns raw
  /// values; the caller sanitizes and then dedupes.
  /// `requireChapterType` carries the site's chapter marker: usually a bare
  /// class token (`chapter-type-video`), sometimes a ready-made selector.
  /// A bare token must become `[class~=…]` — `querySelector('x')` would look
  /// for a TAG named x, find nothing, and gate every stream away.
  static String _markerSelector(String marker) {
    final m = marker.trim();
    final looksLikeSelector = m.startsWith('.') ||
        m.startsWith('#') ||
        m.startsWith('[') ||
        m.contains(' ') ||
        m.contains('>');
    return looksLikeSelector ? m : '[class~="$m"]';
  }

  List<String> extractVideoUrls(
    String htmlContent,
    Map<String, dynamic> readerConfig,
  ) {
    final raw = readerConfig['video'];
    if (raw is! Map) return extractChapterVideoUrls(htmlContent);
    final video = raw.cast<String, dynamic>();

    final container = (video['container'] as String?)?.trim() ?? '';
    final marker = (video['requireChapterType'] as String?)?.trim() ?? '';
    final scopes = container
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (marker.isEmpty && scopes.isEmpty) {
      // Declared but unscoped ⇒ behave exactly as the legacy path.
      return extractChapterVideoUrls(htmlContent);
    }

    final doc = _parser.parse(htmlContent);
    if (marker.isNotEmpty &&
        doc.querySelector(_markerSelector(marker)) == null) {
      _logger.t(
        '$_sourceId reader.video: no "$marker" mark on page → no streams',
      );
      return const [];
    }
    if (scopes.isEmpty) {
      // Marker-gated but unscoped ⇒ page-wide scan, gated by the mark.
      return extractChapterVideoUrls(htmlContent);
    }

    final selector = (video['selector'] as String?)?.trim() ?? '';
    final dataAttribute = (video['dataAttribute'] as String?)?.trim() ?? '';
    final urls = <String>[];
    for (final scope in scopes) {
      if (dataAttribute.isNotEmpty) {
        // The wrapper may be the container itself or live inside it.
        for (final candidates in [
          _parser.selectAll(doc, '$scope[$dataAttribute]'),
          _parser.selectAll(doc, '$scope [$dataAttribute]'),
        ]) {
          for (final el in candidates) {
            final value = (el.attributes[dataAttribute] ?? '').trim();
            if (value.isNotEmpty) urls.add(value);
          }
        }
      }
      if (selector.isNotEmpty) {
        // Scope EVERY comma-separated arm, not just the first — otherwise
        // `video source, video` would leave the second arm page-wide.
        final scopedSelector = _scopedTo(scope, selector);
        final def = <String, dynamic>{
          'selector': scopedSelector,
          'attribute': video['attribute'] ?? 'src',
        };
        final field = fieldDefToSelector(def);
        if (field != null) urls.addAll(_parser.extractList(doc, field));
      }
    }
    // Video URLs bypass sanitizeImageUrl (that is the image path), so a
    // protocol-relative stream such as mangadistrict's
    // `//sv1-*.mangadistrict.com/videos/.../master.m3u8` would reach the
    // player and the download manager with no scheme at all. Handlers get
    // a parsed Uri, not a page to infer from, so it must be absolute here.
    final absolute = urls
        .map((url) => url.startsWith('//') ? 'https:$url' : url)
        .toList(growable: false);
    _logger.t(
      '$_sourceId reader.video: ${absolute.length} stream(s) in "$container"',
    );
    return absolute;
  }

  /// The chapter's stream URLs plus where the stream sits in the chapter's own
  /// order.
  ///
  /// [index] is how many pages the chapter's own `reader.images` selector
  /// matches *before* the first stream element, so the reader can put its play
  /// card where the site put the video instead of always after the last page.
  /// Null when the config declares no `video` block, when the harvest is
  /// unscoped (the legacy page-wide scan cannot attribute a position), or when
  /// there is no image selector to count against.
  ///
  /// Counting happens inside the stream's own scope only, so a promo embed
  /// elsewhere on the page can neither contribute nor shift the position.
  ({List<String> urls, int? index}) extractVideoPlacement(
    String htmlContent,
    Map<String, dynamic> readerConfig,
  ) {
    final urls = extractVideoUrls(htmlContent, readerConfig);
    if (urls.isEmpty) return (urls: urls, index: null);

    final raw = readerConfig['video'];
    if (raw is! Map) return (urls: urls, index: null);
    final video = raw.cast<String, dynamic>();
    final container = (video['container'] as String?)?.trim() ?? '';
    if (container.isEmpty) return (urls: urls, index: null);

    final imageDef = readerConfig['images'];
    if (imageDef is! Map) return (urls: urls, index: null);
    final imageSelector = (imageDef['selector'] as String?)?.trim() ?? '';
    final videoSelector = (video['selector'] as String?)?.trim() ?? '';
    if (imageSelector.isEmpty || videoSelector.isEmpty) {
      return (urls: urls, index: null);
    }

    final marker = (video['requireChapterType'] as String?)?.trim() ?? '';
    final doc = _parser.parse(htmlContent);
    if (marker.isNotEmpty &&
        doc.querySelector(_markerSelector(marker)) == null) {
      return (urls: urls, index: null);
    }

    for (final scope in container
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)) {
      final scopeElement = doc.querySelector(scope);
      if (scopeElement == null) continue;
      final first =
          _parser.selectAll(doc, _scopedTo(scope, videoSelector)).firstOrNull;
      if (first == null) continue;

      // Document order IS the site's order: count the page images that precede
      // the stream element and nothing else. `html` 0.15 has no
      // compareDocumentPosition, so rank every element under the scope once
      // and compare ranks.
      //
      // The two selectors are scoped differently on purpose. `video.selector`
      // is container-relative by contract (`container: .chapter-video-frame`,
      // `selector: video source, video`), so it gets the scope prefix.
      // `images.selector` is authored page-absolute (`.reading-content img…`,
      // `.entry-content.single-page .gallery-item img`) and prefixing it would
      // produce `.entry-content.single-page .entry-content.single-page …`.
      // Containment comes from the rank map instead: it only holds elements
      // under the scope, so an image elsewhere on the page is simply absent.
      final ranks = _documentRanks(scopeElement);
      final videoRank = ranks[first];
      if (videoRank == null) continue;

      var index = 0;
      for (final arm in imageSelector.split(',')) {
        final trimmed = arm.trim();
        if (trimmed.isEmpty) continue;
        for (final image in _parser.selectAll(doc, trimmed)) {
          final rank = ranks[image];
          if (rank != null && rank < videoRank) index++;
        }
      }
      _logger.i(
        '$_sourceId reader.video: stream sits after $index page(s) in "$scope"',
      );
      return (urls: urls, index: index);
    }
    return (urls: urls, index: null);
  }

  /// Scope every comma-separated arm, not just the first — `video source,
  /// video` would otherwise leave the second arm page-wide.
  static String _scopedTo(String scope, String selector) => selector
      .split(',')
      .map((arm) => arm.trim())
      .where((arm) => arm.isNotEmpty)
      .map((arm) => '$scope $arm')
      .join(', ');

  /// Rank every element under [root] by document order. The root itself ranks
  /// first so a selector that matches the container still sorts before its
  /// own children. Elements outside the subtree are absent from the map.
  static Map<dom.Element, int> _documentRanks(dom.Element root) {
    final ranks = <dom.Element, int>{};
    var next = 0;
    void walk(dom.Node node) {
      if (node is dom.Element) {
        ranks[node] = next++;
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(root);
    // Shift so the root outranks everything it contains.
    for (final entry in ranks.entries.toList()) {
      ranks[entry.key] = entry.value - 1;
    }
    return ranks;
  }

  final _videoUrlPattern = RegExp(
    r'''["'(]\s*((?:https?:)?//[^"' <>\s]+\.(?:m3u8|mp4|webm|mov)(?:\?[^"' <>\s]*)?)''',
    caseSensitive: false,
  );

  static bool _isVideoUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return RegExp(r'\.(m3u8|mp4|webm|mov)$').hasMatch(path);
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

    // Bare relative paths (e.g. hentairead `upload/pages/...jpg`, no leading
    // slash) resolve against the source baseUrl the same way. An empty value
    // is NOT a relative path — resolving it would fabricate the baseUrl as an
    // image URL.
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(cleaned);
    if (cleaned.isNotEmpty &&
        !hasScheme &&
        !cleaned.startsWith('/') &&
        !_urlBuilder.baseUrl.startsWith('/')) {
      cleaned = '${_urlBuilder.baseUrl}/$cleaned';
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
