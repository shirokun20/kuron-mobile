// Runtime representation of a parsed source config.
///
// This bridges the raw JSON config (from [SourceConfig]) into typed,
// validated objects used by [GenericHttpSource] at runtime. Constructed
// once during source registration.
library;

// Resolved URL template with placeholders like `{contentId}`, `{page}`, etc.
class UrlTemplate {
  final String template;

  const UrlTemplate(this.template);

  // Resolve the template by substituting [params].
  String resolve(Map<String, String> params) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

// Parsed endpoint map for a source (search, detail, pages, etc.).
class SourceEndpoints {
  final String? search;
  final String? detail;
  final String? pages;
  final String? related;
  final String? allContent;
  final String? tagSearch;
  final String? autocomplete;
  final Map<String, String> extra;

  const SourceEndpoints({
    this.search,
    this.detail,
    this.pages,
    this.related,
    this.allContent,
    this.tagSearch,
    this.autocomplete,
    this.extra = const {},
  });

  factory SourceEndpoints.fromMap(Map<String, String> map) {
    final known = {
      'search',
      'detail',
      'pages',
      'related',
      'allContent',
      'tagSearch',
      'autocomplete',
    };
    final extra = Map.of(map)..removeWhere((k, _) => known.contains(k));
    return SourceEndpoints(
      search: map['search'],
      detail: map['detail'],
      pages: map['pages'],
      related: map['related'],
      allContent: map['allContent'],
      tagSearch: map['tagSearch'],
      autocomplete: map['autocomplete'],
      extra: extra,
    );
  }
}

// Defines how to extract a field from a parsed document.
class FieldSelector {
  // JSONPath expression (e.g. `$.result[*].id`) or CSS selector string.
  final String selector;

  // `"jsonpath"` or `"css"` or `"regex"`.
  final String type;

  // Optional attribute to extract from a CSS-selected element (e.g. `"href"`).
  // With a chain (`attribute: ["data-src", "src"]`) this holds the FIRST
  // entry so callers that only read one attribute keep working.
  final String? attribute;

  // Ordered attribute fallback chain. Empty for the plain single-attribute
  // form, in which case [attribute] is the only candidate.
  final List<String> attributes;

  // Effective chain — first non-empty attribute wins.
  List<String> get attributeChain => attributes.isNotEmpty
      ? attributes
      : (attribute == null ? const [] : [attribute!]);

  // Optional regex to apply to extracted text.
  final String? regex;

  // Optional prefix to prepend to extracted string.
  final String? prefix;

  // Optional suffix to append to extracted string.
  final String? suffix;

  // Fallback value if selector yields nothing.
  final String? fallback;

  const FieldSelector({
    required this.selector,
    this.type = 'jsonpath',
    this.attribute,
    this.attributes = const [],
    this.regex,
    this.prefix,
    this.suffix,
    this.fallback,
  });

  factory FieldSelector.fromMap(Map<String, dynamic> map) {
    final rawAttribute = map['attribute'];
    final chain = rawAttribute is List
        ? rawAttribute.map((e) => e.toString().trim()).toList()
        : const <String>[];
    return FieldSelector(
      selector: map['selector']?.toString() ?? '',
      type: map['type']?.toString() ?? 'jsonpath',
      attribute: chain.isNotEmpty ? chain.first : rawAttribute?.toString(),
      attributes: chain,
      regex: map['regex']?.toString(),
      prefix: map['prefix']?.toString(),
      suffix: map['suffix']?.toString(),
      fallback: map['fallback']?.toString(),
    );
  }
}
