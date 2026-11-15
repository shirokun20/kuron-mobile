import 'package:path/path.dart' as path;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const Set<String> kReaderRepairSupportedImageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.avif',
  '.bmp',
};

const String kEhentaiDefaultImageSelector = '#img';
const List<String> kEhentaiDefaultImageAttributes = <String>[
  'src',
  'data-src',
  'data-lazy-src',
  'data-original',
];
const List<String> kEhentaiDefaultLinkSelectors = <String>[
  'a[href*="/fullimg/"]',
];

bool isLocalReaderImagePath(String value) {
  // Failed-page placeholders are NOT local paths — they embed a remote URL
  if (value.startsWith('__failed__:')) return false;
  return value.startsWith('/') ||
      value.startsWith('\\') ||
      value.startsWith('file://') ||
      (!value.startsWith('http://') && !value.startsWith('https://'));
}

String normalizeLocalReaderImagePath(String value) {
  if (value.startsWith('file://')) {
    return value.replaceFirst('file://', '');
  }
  return value;
}

bool looksLikeDirectImagePath(String pathValue) {
  final loweredPath = pathValue.toLowerCase();
  return kReaderRepairSupportedImageExtensions
      .any((extension) => loweredPath.endsWith(extension));
}

String buildReplacementImagePath({
  required String currentImagePath,
  required String extension,
}) {
  final normalizedExtension = extension.startsWith('.')
      ? extension.toLowerCase()
      : '.${extension.toLowerCase()}';
  final directory = path.dirname(currentImagePath);
  final basename = path.basenameWithoutExtension(currentImagePath);
  return path.join(directory, '$basename$normalizedExtension');
}

String? inferImageExtension({
  required List<int> bytes,
  String? contentType,
  String? sourceUrl,
}) {
  final headerType = _extensionFromContentType(contentType);
  if (headerType != null) {
    return headerType;
  }

  final sniffedType = _extensionFromBytes(bytes);
  if (sniffedType != null) {
    return sniffedType;
  }

  if (sourceUrl != null && sourceUrl.isNotEmpty) {
    final loweredPath = Uri.tryParse(sourceUrl)?.path.toLowerCase() ??
        sourceUrl.toLowerCase().split('?').first;
    for (final extension in kReaderRepairSupportedImageExtensions) {
      if (loweredPath.endsWith(extension)) {
        return extension.replaceFirst('.', '');
      }
    }
  }

  return null;
}

typedef SourceImageResolutionRules = ({
  String mode,
  List<String> imageSelectors,
  List<String> imageAttributes,
  List<String> linkSelectors,
  bool supportsManualSourcePageRepair,
});

typedef EhentaiImageResolutionRules = SourceImageResolutionRules;

SourceImageResolutionRules resolveSourceImageResolutionRules(
  Map<String, dynamic>? rawConfig,
) {
  final imageUrlsConfig = _resolveSourceImageUrlsConfig(rawConfig);
  final imageSelectors = _normalizeSelectorList(
    imageUrlsConfig['imageSelector'],
    fallback: const <String>[kEhentaiDefaultImageSelector],
  );
  final imageAttributes = _normalizeSelectorList(
    imageUrlsConfig['imageAttributes'],
    fallback: kEhentaiDefaultImageAttributes,
  );
  final linkSelectors = _normalizeSelectorList(
    imageUrlsConfig['linkSelector'] ?? imageUrlsConfig['linkSelectors'],
    fallback: kEhentaiDefaultLinkSelectors,
  );
  // Capability is purely config-driven: a source opts into the reader
  // source-page (browser) fallback by declaring
  // `scraper.selectors.detail.imageUrls` in its extension config
  // (e.g. ehentai `mode: ehentai_page_fetch` + `imageSelector: #img`).
  // No per-sourceId branching here — setup lives in kuron-extensions.
  final supportsManualSourcePageRepair = imageUrlsConfig.isNotEmpty &&
      (imageSelectors.isNotEmpty || linkSelectors.isNotEmpty);

  return (
    mode: (imageUrlsConfig['mode'] as String?)?.trim().toLowerCase() ?? '',
    imageSelectors: imageSelectors,
    imageAttributes: imageAttributes,
    linkSelectors: linkSelectors,
    supportsManualSourcePageRepair: supportsManualSourcePageRepair,
  );
}

EhentaiImageResolutionRules resolveEhentaiImageResolutionRules(
  Map<String, dynamic>? rawConfig,
) {
  return resolveSourceImageResolutionRules(rawConfig);
}

bool supportsSourcePageManualRepair(Map<String, dynamic>? rawConfig) {
  return resolveSourceImageResolutionRules(rawConfig)
      .supportsManualSourcePageRepair;
}

String? extractSourceImageUrlFromHtml(
  String html,
  String baseUrl, {
  Map<String, dynamic>? rawConfig,
}) {
  if (html.trim().isEmpty) {
    return null;
  }

  final rules = resolveSourceImageResolutionRules(rawConfig);
  final doc = html_parser.parse(html);

  for (final selector in rules.imageSelectors) {
    dom.Element? match;
    try {
      match = doc.querySelector(selector);
    } catch (_) {
      continue;
    }
    if (match == null) {
      continue;
    }

    final resolved = _extractSourceUrlFromElement(
      element: match,
      baseUrl: baseUrl,
      imageAttributes: rules.imageAttributes,
    );
    if (resolved != null) {
      return resolved;
    }
  }

  for (final selector in rules.linkSelectors) {
    dom.Element? match;
    try {
      match = doc.querySelector(selector);
    } catch (_) {
      continue;
    }
    final href = match?.attributes['href']?.trim();
    if (href != null && href.isNotEmpty) {
      return toAbsoluteRepairUrl(href, baseUrl);
    }
  }

  return null;
}

String? extractEhentaiImageUrlFromHtml(
  String html,
  String baseUrl, {
  Map<String, dynamic>? rawConfig,
}) {
  return extractSourceImageUrlFromHtml(
    html,
    baseUrl,
    rawConfig: rawConfig,
  );
}

String toAbsoluteRepairUrl(String value, String baseUrl) {
  String resolved;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    resolved = value;
  } else if (value.startsWith('//')) {
    resolved = 'https:$value';
  } else {
    try {
      resolved = Uri.parse(baseUrl).resolve(value).toString();
    } catch (_) {
      resolved = value;
    }
  }

  // Security hardening: Upgrade http:// -> https:// to avoid cleartext image transport.
  // Note: Fallback at this resolution level is not feasible because this is a synchronous
  // pure string resolver without network I/O. If a source host is strictly http-only,
  // it would be blocked by Android network_security_config cleartextTrafficPermitted=false anyway.
  if (resolved.startsWith('http://')) {
    return 'https://${resolved.substring(7)}';
  }

  return resolved;
}

String? _extensionFromContentType(String? contentType) {
  if (contentType == null || contentType.trim().isEmpty) {
    return null;
  }

  final normalized = contentType.split(';').first.trim().toLowerCase();
  switch (normalized) {
    case 'image/jpeg':
    case 'image/jpg':
    case 'image/pjpeg':
      return 'jpg';
    case 'image/png':
    case 'image/x-png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'image/avif':
      return 'avif';
    case 'image/bmp':
    case 'image/x-ms-bmp':
      return 'bmp';
    default:
      return null;
  }
}

String? _extensionFromBytes(List<int> bytes) {
  if (bytes.length < 12) {
    return null;
  }

  if (_matchesBytes(bytes, 0, <int>[0xFF, 0xD8, 0xFF])) {
    return 'jpg';
  }

  if (_matchesBytes(
    bytes,
    0,
    <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  )) {
    return 'png';
  }

  if (_matchesBytes(bytes, 0, <int>[0x47, 0x49, 0x46, 0x38])) {
    return 'gif';
  }

  if (_matchesBytes(bytes, 0, <int>[0x42, 0x4D])) {
    return 'bmp';
  }

  if (_matchesBytes(bytes, 0, <int>[0x52, 0x49, 0x46, 0x46]) &&
      _matchesBytes(bytes, 8, <int>[0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }

  if (_matchesBytes(bytes, 4, <int>[0x66, 0x74, 0x79, 0x70]) &&
      (_containsBytes(bytes, 'avif'.codeUnits) ||
          _containsBytes(bytes, 'avis'.codeUnits) ||
          _containsBytes(bytes, 'mif1'.codeUnits))) {
    return 'avif';
  }

  return null;
}

bool _matchesBytes(List<int> bytes, int offset, List<int> expected) {
  if (bytes.length < offset + expected.length) {
    return false;
  }

  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) {
      return false;
    }
  }
  return true;
}

bool _containsBytes(List<int> bytes, List<int> needle) {
  if (needle.isEmpty || bytes.length < needle.length) {
    return false;
  }

  for (var start = 0; start <= bytes.length - needle.length; start++) {
    if (_matchesBytes(bytes, start, needle)) {
      return true;
    }
  }
  return false;
}

Map<String, dynamic> _resolveSourceImageUrlsConfig(
  Map<String, dynamic>? rawConfig,
) {
  final scraper = _asStringMap(rawConfig?['scraper']);
  final selectors = _asStringMap(scraper['selectors']);
  final detail = _asStringMap(selectors['detail']);
  return _asStringMap(detail['imageUrls']);
}

Map<String, dynamic> _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry),
    );
  }
  return <String, dynamic>{};
}

List<String> _normalizeSelectorList(
  dynamic value, {
  required List<String> fallback,
}) {
  if (value is String) {
    final selectors = value
        .split(RegExp(r'[\r\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (selectors.isNotEmpty) {
      return selectors;
    }
  }

  if (value is Iterable) {
    final selectors = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (selectors.isNotEmpty) {
      return selectors;
    }
  }

  return fallback;
}

String? _extractSourceUrlFromElement({
  required dom.Element element,
  required String baseUrl,
  required List<String> imageAttributes,
}) {
  final candidates = <dom.Element>[
    element,
    ...element.querySelectorAll('img'),
  ];

  for (final candidate in candidates) {
    final directUrl = _extractFirstImageAttribute(candidate, imageAttributes);
    if (directUrl != null) {
      return toAbsoluteRepairUrl(directUrl, baseUrl);
    }

    final srcSet = _extractFirstSrcSetValue(candidate.attributes['srcset']);
    if (srcSet != null) {
      return toAbsoluteRepairUrl(srcSet, baseUrl);
    }

    final wrappedLink = _nearestAnchorHref(candidate);
    if (wrappedLink != null) {
      return toAbsoluteRepairUrl(wrappedLink, baseUrl);
    }
  }

  final directLink = element.attributes['href']?.trim();
  if (directLink != null && directLink.isNotEmpty) {
    return toAbsoluteRepairUrl(directLink, baseUrl);
  }

  final nestedLink =
      element.querySelector('a[href]')?.attributes['href']?.trim();
  if (nestedLink != null && nestedLink.isNotEmpty) {
    return toAbsoluteRepairUrl(nestedLink, baseUrl);
  }

  return null;
}

String? _extractFirstImageAttribute(
  dom.Element element,
  List<String> imageAttributes,
) {
  for (final attribute in imageAttributes) {
    final value = element.attributes[attribute]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _extractFirstSrcSetValue(String? srcSet) {
  if (srcSet == null || srcSet.trim().isEmpty) {
    return null;
  }

  final first = srcSet.split(',').first.trim().split(' ').first.trim();
  if (first.isEmpty) {
    return null;
  }
  return first;
}

String? _nearestAnchorHref(dom.Element element) {
  dom.Element? current = element;
  while (current != null) {
    if (current.localName?.toLowerCase() == 'a') {
      final href = current.attributes['href']?.trim();
      if (href != null && href.isNotEmpty) {
        return href;
      }
    }

    final parent = current.parent;
    current = parent is dom.Element ? parent : null;
  }

  return null;
}
