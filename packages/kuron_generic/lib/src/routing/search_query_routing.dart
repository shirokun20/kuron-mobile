// Search/query routing extracted from
// [GenericScraperAdapter] (task 5.1). Pattern-key resolution, page
// params, query encoding, and category routing live here; list
// fetching stays in the adapter. Behavior is unchanged.
library;

import 'dart:convert';

import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

class SearchQueryRouting {
  final Logger _logger;
  final String _sourceId;

  SearchQueryRouting({
    required Logger logger,
    required String sourceId,
  })  : _logger = logger,
        _sourceId = sourceId;

  String encodeRawQueryValue(String key, String value) {
    // HentaiNexus query grammar treats '+' as word separator in q values.
    // Normalize user-entered '+' to spaces so query encoding emits '+'
    // (instead of '%2B') and matches the site's expected parser behavior.
    if (_sourceId == 'hentainexus' && key == 'q') {
      final normalized = value.replaceAll('+', ' ');
      return Uri.encodeQueryComponent(normalized);
    }

    return Uri.encodeComponent(value);
  }


  String resolvePageParamName({
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> urlPatternsCfg,
    required Iterable<String> patternKeys,
    String fallback = 'paged',
  }) {
    final searchFormCfg = rawConfig['searchForm'] as Map<String, dynamic>?;
    final formParams =
        (searchFormCfg?['params'] as Map?)?.cast<String, dynamic>() ?? {};

    for (final entry in formParams.entries) {
      final def = entry.value as Map<String, dynamic>?;
      if ((def?['type'] as String?) != 'page') continue;
      final configured = (def?['queryParam'] as String?)?.trim() ?? '';
      if (configured.isNotEmpty) {
        return configured;
      }
    }

    for (final key in patternKeys) {
      if (key.isEmpty) continue;
      final template = patternUrl(urlPatternsCfg, key);
      final inferred = inferPageParamFromTemplate(template);
      if (inferred != null && inferred.isNotEmpty) {
        return inferred;
      }
    }

    return fallback;
  }

  String? inferPageParamFromTemplate(String templateUrl) {
    if (templateUrl.isEmpty) return null;
    final queryIndex = templateUrl.indexOf('?');
    if (queryIndex < 0 || queryIndex >= templateUrl.length - 1) {
      return null;
    }

    final query = templateUrl.substring(queryIndex + 1);
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eqIndex = pair.indexOf('=');
      if (eqIndex <= 0) continue;
      final rawKey = pair.substring(0, eqIndex).trim();
      if (rawKey.isEmpty) continue;
      final rawValue = pair.substring(eqIndex + 1).trim();
      if (safeDecodeComponent(rawValue) == '{page}') {
        return safeDecodeComponent(rawKey);
      }
    }

    return null;
  }

  bool queryContainsPagePlaceholder(String query) {
    if (query.isEmpty) return false;
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eqIndex = pair.indexOf('=');
      if (eqIndex < 0 || eqIndex >= pair.length - 1) continue;
      final value = pair.substring(eqIndex + 1).trim();
      if (safeDecodeComponent(value) == '{page}') {
        return true;
      }
    }
    return false;
  }

  String ensurePageQueryForStandardSearch({
    required String resolvedUrl,
    required String patternKey,
    required SearchFilter filter,
    required Map<String, dynamic> rawConfig,
    required Map<String, dynamic> urlPatternsCfg,
  }) {
    if (filter.page <= 1) {
      return resolvedUrl;
    }

    // Raw-mode search already handles page injection explicitly.
    if (filter.query.startsWith('raw:')) {
      return resolvedUrl;
    }

    final patternValue = urlPatternsCfg[patternKey];
    String template = '';
    if (patternValue is String) {
      template = patternValue;
    } else if (patternValue is Map<String, dynamic>) {
      template = (patternValue['url'] as String?) ?? '';
    }

    // If template already encodes page placeholder, do not append fallback.
    if (template.contains('{page}')) {
      return resolvedUrl;
    }

    final lowerPath = Uri.tryParse(resolvedUrl)?.path.toLowerCase() ?? '';
    if (RegExp(r'/page/\d+/?$').hasMatch(lowerPath)) {
      return resolvedUrl;
    }

    final pageParam = resolvePageParamName(
      rawConfig: rawConfig,
      urlPatternsCfg: urlPatternsCfg,
      patternKeys: [patternKey],
    );

    final pageParamRegex = RegExp('([?&])${RegExp.escape(pageParam)}=');
    if (pageParamRegex.hasMatch(resolvedUrl)) {
      return resolvedUrl;
    }

    final separator = resolvedUrl.contains('?') ? '&' : '?';
    return '$resolvedUrl$separator$pageParam=${Uri.encodeComponent(filter.page.toString())}';
  }

  String resolveBrowsePatternKey({
    required SearchFilter filter,
    required Map<String, dynamic> scraper,
    required Map<String, dynamic> urlPatternsCfg,
  }) {
    final fallback = homeFallbackPatternKey(
      page: filter.page,
      urlPatternsCfg: urlPatternsCfg,
    );

    final routing = (scraper['routing'] as Map?)?.cast<String, dynamic>();
    final categoryPatterns =
        (routing?['categoryPatterns'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    if (categoryPatterns.isEmpty) return fallback;

    var selectedCategory = (filter.category ?? '').trim();
    if (selectedCategory.isEmpty) {
      selectedCategory = (routing?['defaultCategory'] as String? ?? '').trim();
    }
    if (selectedCategory.isEmpty) return fallback;

    final route = resolveCategoryRoute(
      selectedCategory: selectedCategory,
      categoryPatterns: categoryPatterns,
    );
    if (route == null) {
      _logger.w(
        '$_sourceId: browse category "$selectedCategory" is unknown; fallback to "$fallback"',
      );
      return fallback;
    }

    final firstPageKey = (route['firstPage'] ?? '').trim();
    final pagedKey = (route['paged'] ?? '').trim();
    final candidate = filter.page > 1
        ? (pagedKey.isNotEmpty ? pagedKey : firstPageKey)
        : firstPageKey;

    if (candidate.isEmpty) {
      _logger.w(
        '$_sourceId: category "$selectedCategory" has empty route; fallback to "$fallback"',
      );
      return fallback;
    }

    if (!urlPatternsCfg.containsKey(candidate)) {
      _logger.w(
        '$_sourceId: category "$selectedCategory" maps to missing pattern "$candidate"; fallback to "$fallback"',
      );
      return fallback;
    }

    return candidate;
  }

  Map<String, String>? resolveCategoryRoute({
    required String selectedCategory,
    required Map<String, dynamic> categoryPatterns,
  }) {
    final byAlias = <String, Map<String, String>>{};
    for (final entry in categoryPatterns.entries) {
      final route = parseCategoryRoute(entry.value);
      if (route == null) continue;

      final aliases = <String>{
        ...splitCategoryAliasTokens(entry.key),
      };

      final raw = entry.value;
      if (raw is Map) {
        final aliasRaw = raw['aliases'];
        if (aliasRaw is List) {
          for (final value in aliasRaw) {
            aliases.addAll(splitCategoryAliasTokens(value.toString()));
          }
        } else if (aliasRaw is String) {
          aliases.addAll(splitCategoryAliasTokens(aliasRaw));
        }
      }

      if (aliases.isEmpty) {
        aliases.add(entry.key);
      }

      for (final alias in aliases) {
        final normalized = normalizeCategoryKey(alias);
        if (normalized.isEmpty) continue;
        byAlias.putIfAbsent(normalized, () => route);
      }
    }

    final selected = normalizeCategoryKey(selectedCategory);
    if (selected.isEmpty) return null;
    return byAlias[selected];
  }

  Map<String, String>? parseCategoryRoute(dynamic raw) {
    if (raw is String) {
      final firstPage = raw.trim();
      if (firstPage.isEmpty) return null;
      return <String, String>{'firstPage': firstPage};
    }

    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();

    final firstPage = (map['firstPage'] as String?)?.trim() ??
        (map['first'] as String?)?.trim() ??
        (map['pattern'] as String?)?.trim() ??
        (map['key'] as String?)?.trim() ??
        '';
    final paged = (map['paged'] as String?)?.trim() ??
        (map['page'] as String?)?.trim() ??
        (map['pagedPattern'] as String?)?.trim() ??
        '';

    if (firstPage.isEmpty && paged.isEmpty) {
      return null;
    }

    return <String, String>{
      if (firstPage.isNotEmpty) 'firstPage': firstPage,
      if (paged.isNotEmpty) 'paged': paged,
    };
  }

  Set<String> splitCategoryAliasTokens(String raw) {
    return raw
        .split(RegExp(r'[|,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String normalizeCategoryKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String homeFallbackPatternKey({
    required int page,
    required Map<String, dynamic> urlPatternsCfg,
  }) {
    return page > 1 && urlPatternsCfg.containsKey('homePage')
        ? 'homePage'
        : 'home';
  }

  // URL string from a urlPatterns entry (plain String or `{url:…}` Map).
  String patternUrl(Map<String, dynamic> urlPatternsCfg, String key) {
    final val = urlPatternsCfg[key];
    if (val is String) return val;
    if (val is Map<String, dynamic>) return val['url'] as String? ?? '';
    return '';
  }


  String safeDecodeComponent(String value) {
    if (value.isEmpty || !value.contains('%')) {
      return value;
    }

    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return decodePercentEncodedSegments(value) ?? value;
    }
  }

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
}