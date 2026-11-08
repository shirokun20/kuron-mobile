// JSONPath-based parser for JSON API responses.
///
// Uses the `json_path` package to evaluate JSONPath expressions against
// parsed JSON objects, extracting field values based on selectors defined
// in the source config.
library;

import 'package:json_path/json_path.dart';
import 'package:logger/logger.dart';

import '../models/source_config_runtime.dart';

class GenericJsonParser {
  final Logger _logger;

  GenericJsonParser({required this._logger});

  // Extract a single string value from [data] using [selector].
  String? extractString(dynamic data, FieldSelector selector) {
    try {
      final value = _evaluate(data, selector);
      if (value == null) return selector.fallback;

      String? str;
      if (value is Map) {
        if (value.containsKey('en')) {
          str = value['en']?.toString();
        } else if (value.isNotEmpty) {
          str = value.values.first?.toString();
        }
      } else if (value is List) {
        if (value.isNotEmpty) {
          str = value.first?.toString();
        }
      } else {
        str = value.toString();
      }

      if (str == null || str.isEmpty) return selector.fallback;

      if (selector.regex != null) {
        str = _applyRegex(str, selector.regex!);
        if (str == null || str.isEmpty) return selector.fallback;
      }
      if (selector.prefix != null) {
        str = '${selector.prefix}$str';
      }
      if (selector.suffix != null) {
        str = '$str${selector.suffix}';
      }
      return str;
    } catch (e) {
      _logger.w('GenericJsonParser: failed to extract "${selector.selector}"',
          error: e);
      return selector.fallback;
    }
  }

  // Extract a raw dynamic value from [data] using [selector].
  dynamic extractRaw(dynamic data, FieldSelector selector) {
    try {
      dynamic value = _evaluate(data, selector);
      if (selector.prefix != null || selector.suffix != null) {
        if (value != null) {
          String strValue = value.toString();
          if (selector.prefix != null) {
            strValue = '${selector.prefix}$strValue';
          }
          if (selector.suffix != null) {
            strValue = '$strValue${selector.suffix}';
          }
          value = strValue;
        }
      }
      return value;
    } catch (e) {
      _logger.w(
          'GenericJsonParser: failed to extract raw "${selector.selector}"',
          error: e);
      return null;
    }
  }

  // Extract a list of values from [data] using [selector].
  List<String> extractList(dynamic data, FieldSelector selector) {
    try {
      if (selector.type == 'jsonpath') {
        final path = JsonPath(selector.selector);
        return path
            .read(data)
            .map((m) => m.value?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (e) {
      _logger.w(
          'GenericJsonParser: failed to extract list "${selector.selector}"',
          error: e);
    }
    return const [];
  }

  // Extract a list of maps (items list) from [data] using [selector].
  List<Map<String, dynamic>> extractItems(
      dynamic data, FieldSelector selector) {
    try {
      if (selector.type == 'jsonpath') {
        final path = JsonPath(selector.selector);
        return path
            .read(data)
            .map((m) => m.value)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    } catch (e) {
      _logger.w(
          'GenericJsonParser: failed to extract items "${selector.selector}"',
          error: e);
    }
    return const [];
  }

  // ── Private ────────────────────────────────────────────────────────────────

  dynamic _evaluate(dynamic data, FieldSelector selector) {
    if (selector.type != 'jsonpath') return null;
    final path = JsonPath(selector.selector);
    final matches = path.read(data);
    if (matches.isEmpty) return null;
    return matches.first.value;
  }

  String? _applyRegex(String input, String pattern) {
    try {
      final match = RegExp(pattern).firstMatch(input);
      if (match == null) return null;
      // Return first capture group if present, else full match.
      return match.groupCount > 0 ? match.group(1) : match.group(0);
    } catch (e) {
      return null;
    }
  }
}
