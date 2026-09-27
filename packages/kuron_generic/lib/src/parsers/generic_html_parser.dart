// CSS selector-based HTML parser for scraper-type sources.
///
// Wraps the `html` package to evaluate CSS selectors and extract text
// or attribute values from HTML documents.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:logger/logger.dart';

import '../models/source_config_runtime.dart';

// Ordered list of lazy-load image attributes to check as fallbacks.
// `data-default-src` is used by FIFU-mature cards (e.g. mangadistrict)
// where `src` is an inline SVG placeholder until age-gate interaction.
const _kImageFallbackAttributes = [
  'data-default-src',
  'data-src',
  'data-lazy-src',
  'data-pagespeed-lazy-src',
  'src',
];

// Placeholder / lazy-load src values that image optimizers (mod_pagespeed,
// WP-Manga "result" variant, etc.) serve in `src` in place of the real image.
// When a value matches, we treat it as empty so the fallback chain runs and we
// pick up the true image URL from `data-src`/`data-lazy-src`.
//
// Patterns:
//   - `^/pagespeed_static/`  — mod_pagespeed placeholder bundle.
//   - `…_result.<ext>`       — WP-Manga image-optimizer placeholder (e.g.
//                               `Ideal-(1)_result.jpg` on mangaforfree). The
//                               real chapter image lives in `data-src`.
final _kPlaceholderSrcPattern = RegExp(
  r'^(/pagespeed_static/|.*[-_]result\.(?:jpe?g|png|webp|gif)$)',
  caseSensitive: false,
);

class GenericHtmlParser {
  final Logger _logger;

  GenericHtmlParser({required Logger logger}) : _logger = logger;

  dom.Document parse(String htmlString) => html_parser.parse(htmlString);

  /// Applies optional prefix/suffix (mirrors generic_json_parser).
  /// Null-safe: configs without prefix/suffix behave exactly as before.
  String _applyAffixes(String value, FieldSelector selector) {
    final prefix = selector.prefix;
    final suffix = selector.suffix;
    if (prefix == null && suffix == null) return value;
    return '${prefix ?? ''}$value${suffix ?? ''}';
  }

  String? extractString(dom.Document document, FieldSelector selector) {
    try {
      if (selector.regex != null) {
        final elements = _selectAll(document, selector.selector);
        _logger.d(
            'GenericHtmlParser.extractString: selector="${selector.selector}", regex=${selector.regex}, found ${elements.length} elements');

        for (final element in elements) {
          final value = selector.attribute != null
              ? _resolveAttribute(element, selector.attribute!)
              : element.text.trim();
          if (value == null || value.isEmpty) continue;

          final matched = _applyRegex(value, selector.regex!);
          if (matched != null && matched.isNotEmpty) {
            _logger.d(
                'GenericHtmlParser.extractString: regex matched on element: "$value" → "$matched"');
            return _applyAffixes(matched, selector);
          }
        }
        _logger.w(
            'GenericHtmlParser.extractString: regex did not match any element for "${selector.selector}"');
        return selector.fallback;
      }

      final elements = _selectAll(document, selector.selector);
      if (elements.isEmpty) {
        _logger.t(
            'GenericHtmlParser.extractString: selector "${selector.selector}" matched no elements');
        return selector.fallback;
      }
      final element = elements.first;
      final value = selector.attribute != null
          ? _resolveAttribute(element, selector.attribute!)
          : element.text.trim();
      if (value == null || value.isEmpty) {
        _logger.t(
            'GenericHtmlParser.extractString: selector "${selector.selector}" matched element but value empty');
        return selector.fallback;
      }
      _logger.d(
          'GenericHtmlParser.extractString: selector="${selector.selector}" → "$value"');
      return _applyAffixes(value, selector);
    } catch (e) {
      _logger.w('GenericHtmlParser: failed to extract "${selector.selector}"',
          error: e);
      return selector.fallback;
    }
  }

  List<String> extractList(dom.Document document, FieldSelector selector) {
    try {
      final elements = _selectAll(document, selector.selector);
      _logger.d(
          'GenericHtmlParser.extractList: selector="${selector.selector}", multi=true, regex=${selector.regex}, found ${elements.length} elements');

      final rawValues = elements
          .map((el) => selector.attribute != null
              ? (_resolveAttribute(el, selector.attribute!) ?? '')
              : el.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (selector.regex == null) {
        _logger.d(
            'GenericHtmlParser.extractList: no regex, returning ${rawValues.length} raw values');
        return rawValues.map((v) => _applyAffixes(v, selector)).toList();
      }

      final regexed = <String>[];
      for (final value in rawValues) {
        final matched = _applyRegex(value, selector.regex!);
        if (matched != null && matched.isNotEmpty) {
          regexed.add(_applyAffixes(matched, selector));
          _logger.t(
              'GenericHtmlParser.extractList: regex matched: "$value" → "$matched"');
        } else {
          _logger.t(
              'GenericHtmlParser.extractList: regex rejected: "$value" (pattern: ${selector.regex})');
        }
      }
      _logger.d(
          'GenericHtmlParser.extractList: regex-filtered ${rawValues.length} → ${regexed.length} values');
      return regexed;
    } catch (e) {
      _logger.w(
          'GenericHtmlParser: failed to extract list "${selector.selector}"',
          error: e);
      return const [];
    }
  }

  List<dom.Element> selectAll(dom.Document document, String cssSelector) {
    try {
      return _selectAll(document, cssSelector);
    } catch (e) {
      _logger.w('GenericHtmlParser: querySelectorAll failed for "$cssSelector"',
          error: e);
      return const [];
    }
  }

  String? extractFromElement(dom.Element element, FieldSelector selector) {
    try {
      final children = _selectAll(element, selector.selector);
      final target = children.isNotEmpty ? children.first : element;
      final value = selector.attribute != null
          ? _resolveAttribute(target, selector.attribute!)
          : target.text.trim();
      if (value == null || value.isEmpty) return selector.fallback;
      if (selector.regex != null) return _applyRegex(value, selector.regex!);
      return value;
    } catch (e) {
      return selector.fallback;
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  // Query selector with :contains(text) pseudo-class support.
  ///
  // The standard CSS parser from `html` package does not support :contains(),
  // so we preprocess selectors to handle it manually.
  List<dom.Element> _selectAll(dynamic parent, String selector) {
    final containsRE = RegExp(r':contains\(([^)]+)\)');
    final match = containsRE.firstMatch(selector);
    if (match == null) return parent.querySelectorAll(selector);

    final searchText =
        match.group(1)!.replaceAll('"', '').replaceAll("'", '').trim();
    final beforePseudo = selector.substring(0, match.start).trim();
    final afterPseudo = selector.substring(match.end);

    final bases = (parent.querySelectorAll(beforePseudo) as List)
        .whereType<dom.Element>()
        .toList();
    final filtered =
        bases.where((dom.Element el) => el.text.contains(searchText)).toList();

    if (filtered.isEmpty || afterPseudo.trim().isEmpty) return filtered;

    // Adjacent sibling: A:contains(text) + B
    final adjMatch = RegExp(r'^\s*\+\s*(.+)$').firstMatch(afterPseudo);
    if (adjMatch != null) {
      final nextSel = adjMatch.group(1)!.trim();
      final result = <dom.Element>[];
      for (final el in filtered) {
        final sibling = el.nextElementSibling;
        if (sibling == null) continue;
        result.addAll(_resolveAdjacentSiblingTargets(sibling, nextSel));
      }
      return result;
    }

    // Descendant: A:contains(text) B or A:contains(text) > B
    final remaining = afterPseudo.trimLeft();
    final result = <dom.Element>[];
    for (final el in filtered) {
      try {
        result.addAll(el.querySelectorAll(remaining));
      } catch (_) {}
    }
    return result;
  }

  List<dom.Element> _resolveAdjacentSiblingTargets(
    dom.Element sibling,
    String selector,
  ) {
    final splitMatch = RegExp(r'^([^\s>+~]+)(.*)$').firstMatch(selector.trim());
    if (splitMatch == null) {
      return const [];
    }

    final siblingSelector = splitMatch.group(1)!.trim();
    var remainder = (splitMatch.group(2) ?? '').trimLeft();

    if (!_matchesSimpleSelector(sibling, siblingSelector)) {
      return const [];
    }

    if (remainder.isEmpty) {
      return [sibling];
    }

    if (remainder.startsWith('>')) {
      remainder = remainder.substring(1).trimLeft();
    }
    if (remainder.isEmpty) {
      return [sibling];
    }

    try {
      return sibling.querySelectorAll(remainder);
    } catch (_) {
      return const [];
    }
  }

  bool _matchesSimpleSelector(dom.Element element, String selectorToken) {
    final token = selectorToken.trim();
    if (token.isEmpty || token == '*') return true;

    if (token.startsWith('.')) {
      final classTokens = token
          .split('.')
          .where((part) => part.isNotEmpty)
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty);
      if (classTokens.isEmpty) return true;
      for (final className in classTokens) {
        if (!element.classes.contains(className)) return false;
      }
      return true;
    }

    if (token.startsWith('#')) {
      return element.id == token.substring(1);
    }

    return element.localName?.toLowerCase() == token.toLowerCase();
  }

  String? _resolveAttribute(dom.Element element, String attribute) {
    final value = (element.attributes[attribute] ?? '').trim();

    if (element.localName != 'img') return value.isEmpty ? null : value;

    if (value.isNotEmpty &&
        !value.startsWith('data:') &&
        !_kPlaceholderSrcPattern.hasMatch(value)) {
      return value;
    }

    for (final fallbackAttr in _kImageFallbackAttributes) {
      if (fallbackAttr == attribute) continue;
      final fallbackValue = (element.attributes[fallbackAttr] ?? '').trim();
      if (fallbackValue.isEmpty || fallbackValue.startsWith('data:')) continue;
      _logger.d(
          'GenericHtmlParser: image lazy-load fallback: $attribute=${value.isEmpty ? "null" : "placeholder"} → $fallbackAttr="$fallbackValue"');
      return fallbackValue;
    }

    return value.isEmpty ? null : value;
  }

  String? _applyRegex(String input, String pattern) {
    try {
      // dotAll: extracted text commonly spans newlines (badge markup above
      // the title line); without it `.+`/`$` anchors fail on those values.
      final match = RegExp(pattern, dotAll: true).firstMatch(input);
      if (match == null) return null;
      return match.groupCount > 0 ? match.group(1) : match.group(0);
    } catch (e) {
      return null;
    }
  }
}
