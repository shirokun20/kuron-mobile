// Typed dynamic search form contract.
///
// Parses the `searchForm` block of a Source Config into strongly-typed
// models so the validator and the UI filter system can work without
// inspecting raw maps.
///
// Supported dialects:
//   - HentaiNexus-style: `searchForm.params.*` with valuePrefix, operators,
//     quoteIfContainsSpace, joinMode, multiInput, ui.selector.
//   - KomikCast-style: `searchConfig.sortingConfig` separate from
//     `searchForm`.
library;

import 'package:equatable/equatable.dart';
import 'package:kuron_core/kuron_core.dart';

// Kind of a single search form field.
enum SearchFormFieldType {
  // Free-text input.
  text,

  // Single-value radio group.
  radio,

  // Tag chips input (multiInput true by default).
  tag,

  // Single-value dropdown.
  select,

  // Boolean checkbox.
  checkbox,

  // Sort order selector. Serialized as `sort`.
  sort,

  // Hidden transport field such as pagination.
  hidden,

  // Visual separator — no value.
  separator,

  // Unknown type preserved verbatim.
  unknown,
}

// A selectable option in a `select`, `checkbox`, or `sort` field.
class SearchFormFieldOption extends Equatable {
  const SearchFormFieldOption({required this.value, this.label});

  final String value;
  final String? label;

  factory SearchFormFieldOption.fromMap(Map<String, Object?> map) {
    final value = map['apiValue']?.toString() ?? map['value']?.toString() ?? '';
    return SearchFormFieldOption(
      value: value,
      label: map['displayLabel']?.toString() ??
          map['label']?.toString() ??
          map['name']?.toString(),
    );
  }

  factory SearchFormFieldOption.fromObject(Object? value) {
    if (value is Map) {
      return SearchFormFieldOption.fromMap(value.cast<String, Object?>());
    }

    final text = value?.toString() ?? '';
    return SearchFormFieldOption(value: text, label: text);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'value': value,
        if (label != null) 'label': label,
      };

  @override
  List<Object?> get props => <Object?>[value, label];
}

// Contract for a single field in a dynamic search form.
class SearchFormFieldContract extends Equatable {
  const SearchFormFieldContract({
    required this.id,
    required this.queryParam,
    required this.type,
    this.label,
    this.placeholder,
    this.valuePrefix,
    this.valueSuffix,
    this.quoteIfContainsSpace = false,
    this.multiInput = false,
    this.joinMode,
    this.uiSelector,
    this.uiDataSource,
    this.loadFromTags = false,
    this.tagType,
    this.tagSourceUrl,
    this.operators = const <String>[],
    this.options = const <SearchFormFieldOption>[],
  });

  // Field identifier (key in `searchForm.params` map).
  final String id;

  // Query parameter name the value is appended to.
  final String queryParam;

  final SearchFormFieldType type;

  final String? label;
  final String? placeholder;

  // Prefix prepended to the value before appending to [queryParam].
  // Example: `"artist:"` for HentaiNexus artist search.
  final String? valuePrefix;

  // Suffix appended after the value.
  final String? valueSuffix;

  // When true, the value is quoted if it contains whitespace.
  final bool quoteIfContainsSpace;

  // When true, multiple values can be submitted for this field.
  final bool multiInput;

  // How multiple values are joined. Common: `"space"`, `"comma"`, `"+"`.
  final String? joinMode;

  // UI control hint from `ui.selector` (e.g. `"chips"`, `"dropdown"`).
  final String? uiSelector;

  // Optional option source key from `searchForm.dataSources`.
  final String? uiDataSource;

  // Legacy checkbox metadata for sources that source options from tags.
  final bool loadFromTags;
  final String? tagType;
  final String? tagSourceUrl;

  // Operator list for range/comparison fields (e.g. `[">=", "<="]`).
  final List<String> operators;

  // Selectable options for `select`, `checkbox`, or `sort` fields.
  final List<SearchFormFieldOption> options;

  factory SearchFormFieldContract.fromEntry(
    String id,
    Map<String, Object?> map,
  ) {
    final String typeStr = map['type']?.toString() ?? 'text';
    final SearchFormFieldType type = switch (typeStr) {
      'radio' => SearchFormFieldType.radio,
      'tag' => SearchFormFieldType.tag,
      'picker' || 'lov' => SearchFormFieldType.tag,
      'select' => SearchFormFieldType.select,
      'checkbox' => SearchFormFieldType.checkbox,
      'sort' => SearchFormFieldType.sort,
      'page' || 'hidden' => SearchFormFieldType.hidden,
      'separator' => SearchFormFieldType.separator,
      'text' || 'input' || 'query' => SearchFormFieldType.text,
      _ => SearchFormFieldType.text,
    };

    final Object? uiRaw = map['ui'];
    final String? uiSelector = uiRaw is Map
        ? uiRaw.cast<String, Object?>()['selector']?.toString()
        : null;
    final String? uiDataSource = uiRaw is Map
        ? uiRaw.cast<String, Object?>()['dataSource']?.toString()
        : null;

    final Object? opsRaw = map['operators'];
    final List<String> operators = opsRaw is List
        ? opsRaw
            .map<String>((Object? e) => e.toString())
            .toList(growable: false)
        : const <String>[];

    final Object? optsRaw = map['options'];
    final List<SearchFormFieldOption> options = optsRaw is List
        ? optsRaw
            .map<SearchFormFieldOption>(SearchFormFieldOption.fromObject)
            .where((SearchFormFieldOption option) => option.value.isNotEmpty)
            .toList(growable: false)
        : const <SearchFormFieldOption>[];

    return SearchFormFieldContract(
      id: id,
      queryParam: map['queryParam']?.toString() ?? id,
      type: type,
      label: map['label']?.toString(),
      placeholder: map['placeholder']?.toString(),
      valuePrefix: map['valuePrefix']?.toString(),
      valueSuffix: map['valueSuffix']?.toString(),
      quoteIfContainsSpace: map['quoteIfContainsSpace'] as bool? ?? false,
      multiInput:
          map['multiInput'] as bool? ?? (type == SearchFormFieldType.tag),
      joinMode: map['joinMode']?.toString(),
      uiSelector: uiSelector,
      uiDataSource: uiDataSource,
      loadFromTags: map['loadFromTags'] as bool? ?? false,
      tagType: map['tagType']?.toString(),
      tagSourceUrl: map['tagSourceUrl']?.toString(),
      operators: operators,
      options: options,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'queryParam': queryParam,
        'type': type.name,
        if (label != null) 'label': label,
        if (placeholder != null) 'placeholder': placeholder,
        if (valuePrefix != null) 'valuePrefix': valuePrefix,
        if (valueSuffix != null) 'valueSuffix': valueSuffix,
        if (quoteIfContainsSpace) 'quoteIfContainsSpace': quoteIfContainsSpace,
        if (multiInput) 'multiInput': multiInput,
        if (joinMode != null) 'joinMode': joinMode,
        if (uiSelector != null) 'uiSelector': uiSelector,
        if (uiDataSource != null) 'uiDataSource': uiDataSource,
        if (loadFromTags) 'loadFromTags': loadFromTags,
        if (tagType != null) 'tagType': tagType,
        if (tagSourceUrl != null) 'tagSourceUrl': tagSourceUrl,
        if (operators.isNotEmpty) 'operators': operators,
        if (options.isNotEmpty)
          'options': options
              .map((SearchFormFieldOption o) => o.toJson())
              .toList(growable: false),
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        queryParam,
        type,
        label,
        placeholder,
        valuePrefix,
        valueSuffix,
        quoteIfContainsSpace,
        multiInput,
        joinMode,
        uiSelector,
        uiDataSource,
        loadFromTags,
        tagType,
        tagSourceUrl,
        operators,
        options,
      ];
}

// Aggregated dynamic search form contract for a source.
class DynamicSearchFormContract extends Equatable {
  DynamicSearchFormContract({
    required this.urlPattern,
    required List<SearchFormFieldContract> fields,
    this.dataSources = const <String, Object?>{},
    this.defaultSort,
    this.diagnostics = const <ValidationDiagnostic>[],
  }) : fields = List<SearchFormFieldContract>.unmodifiable(fields);

  // URL pattern identifier this form maps to (e.g. `"search"`).
  final String urlPattern;

  final List<SearchFormFieldContract> fields;

  // Optional picker or LOV data source declarations keyed by field UI hints.
  final Map<String, Object?> dataSources;

  // Default sort option when none is selected.
  final String? defaultSort;

  final List<ValidationDiagnostic> diagnostics;

  // Whether any field uses operators (e.g. `>=`, `<=`).
  bool get hasOperators =>
      fields.any((SearchFormFieldContract f) => f.operators.isNotEmpty);

  // Whether any field uses quoteIfContainsSpace.
  bool get hasQuoteWhitespace =>
      fields.any((SearchFormFieldContract f) => f.quoteIfContainsSpace);

  // Required engine primitives implied by this form contract.
  Set<String> get impliedPrimitives => <String>{
        EnginePrimitive.dynamicFormBasic,
        if (hasOperators) EnginePrimitive.dynamicFormOperators,
        if (hasQuoteWhitespace) EnginePrimitive.dynamicFormQuoteWhitespace,
      };

  // Parses a `searchForm` block from the raw config.
  ///
  // Handles both the HentaiNexus-style `searchForm.params` block and the
  // KomikCast-style `searchConfig.sortingConfig` block.
  factory DynamicSearchFormContract.fromConfig(
    Map<String, Object?> rawConfig,
  ) {
    final List<ValidationDiagnostic> diags = <ValidationDiagnostic>[];
    final Object? sfRaw = rawConfig['searchForm'];
    final bool hasSfBlock = sfRaw is Map;
    final bool hasScBlock = rawConfig['searchConfig'] is Map;

    if (!hasSfBlock && !hasScBlock) {
      final inferred = _inferMinimalQueryForm(rawConfig, diags);
      if (inferred != null) return inferred;

      return DynamicSearchFormContract(
        urlPattern: 'search',
        fields: const <SearchFormFieldContract>[],
        dataSources: const <String, Object?>{},
        diagnostics: diags,
      );
    }

    String urlPattern = 'search';
    final List<SearchFormFieldContract> fields = <SearchFormFieldContract>[];
    Map<String, Object?> dataSources = const <String, Object?>{};

    // Parse HentaiNexus-style `params` map.
    if (sfRaw is Map) {
      final Map<String, Object?> sf = sfRaw.cast<String, Object?>();
      urlPattern = sf['urlPattern']?.toString() ?? 'search';
      final Object? dataSourcesRaw = sf['dataSources'];
      if (dataSourcesRaw is Map) {
        dataSources = dataSourcesRaw.cast<String, Object?>();
      }
      final Object? paramsRaw = sf['params'];
      if (paramsRaw is Map) {
        for (final MapEntry<Object?, Object?> entry in paramsRaw.entries) {
          final String id = entry.key.toString();
          final Object? value = entry.value;
          if (value is Map) {
            final map = value.cast<String, Object?>();
            _addUnsupportedFieldDiagnostics(id, map, diags);
            fields.add(SearchFormFieldContract.fromEntry(
              id,
              map,
            ));
          }
        }
      }
    }

    // Parse KomikCast-style `sortingConfig` if present in searchConfig.
    final Object? scRaw = rawConfig['searchConfig'];
    if (scRaw is Map) {
      final Map<String, Object?> sc = scRaw.cast<String, Object?>();
      final bool hasExplicitLegacyFields =
          (sc['textFields'] is List && (sc['textFields'] as List).isNotEmpty) ||
              (sc['radioGroups'] is List &&
                  (sc['radioGroups'] as List).isNotEmpty) ||
              (sc['checkboxGroups'] is List &&
                  (sc['checkboxGroups'] as List).isNotEmpty);
      final String queryParam = _firstString(sc, const <String>[
            'queryParam',
            'queryParamName',
            'searchParam',
          ]) ??
          _inferQueryParamFromUrlPattern(rawConfig) ??
          'q';
      if (!hasExplicitLegacyFields &&
          !fields.any((SearchFormFieldContract f) =>
              f.queryParam == queryParam &&
              f.type == SearchFormFieldType.text)) {
        fields.insert(
          0,
          SearchFormFieldContract(
            id: 'query',
            queryParam: queryParam,
            type: SearchFormFieldType.text,
            label: 'Search',
          ),
        );
      }

      _addLegacyFormFields(sc, fields);

      final Object? sortingRaw = sc['sortingConfig'];
      if (sortingRaw is Map) {
        final Map<String, Object?> sorting = sortingRaw.cast<String, Object?>();
        final Object? optionsRaw = sorting['options'];
        final List<SearchFormFieldOption> sortOptions = optionsRaw is List
            ? optionsRaw
                .map<SearchFormFieldOption>(SearchFormFieldOption.fromObject)
                .where(
                    (SearchFormFieldOption option) => option.value.isNotEmpty)
                .toList(growable: false)
            : const <SearchFormFieldOption>[];
        if (sortOptions.isNotEmpty) {
          fields.add(SearchFormFieldContract(
            id: '_sort',
            queryParam: sorting['queryParam']?.toString() ??
                sc['sortParam']?.toString() ??
                sc['sortParamName']?.toString() ??
                'sort',
            type: SearchFormFieldType.sort,
            label: sorting['label']?.toString() ?? 'Sort',
            uiSelector: sorting['widgetType']?.toString(),
            options: sortOptions,
          ));
        }
      } else {
        final Object? sortValuesRaw = sc['sortValues'];
        if (sortValuesRaw is Map && sortValuesRaw.isNotEmpty) {
          fields.add(SearchFormFieldContract(
            id: '_sort',
            queryParam: sc['sortParam']?.toString() ??
                sc['sortParamName']?.toString() ??
                'sort',
            type: SearchFormFieldType.sort,
            label: 'Sort',
            options: sortValuesRaw.entries
                .map((MapEntry<Object?, Object?> entry) =>
                    SearchFormFieldOption(
                      value: entry.value?.toString() ?? entry.key.toString(),
                      label: entry.key.toString(),
                    ))
                .toList(growable: false),
          ));
        }
      }

      final String? pageParam = _firstString(sc, const <String>[
        'pageParam',
        'pageParamName',
        'paginationParam',
      ]);
      if (pageParam != null && pageParam.isNotEmpty) {
        fields.add(SearchFormFieldContract(
          id: '_page',
          queryParam: pageParam,
          type: SearchFormFieldType.hidden,
          label: 'Page',
        ));
      }
    }

    if (fields.isEmpty) {
      diags.add(const ValidationDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'dynamicFormNoFields',
        message:
            'searchForm block is present but no parseable fields were found.',
        feature: FeatureKind.dynamicForm,
        path: 'searchForm.params',
      ));
    }

    return DynamicSearchFormContract(
      urlPattern: urlPattern,
      fields: fields,
      dataSources: dataSources,
      diagnostics: diags,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'urlPattern': urlPattern,
        if (defaultSort != null) 'defaultSort': defaultSort,
        if (dataSources.isNotEmpty) 'dataSources': dataSources,
        'fields': fields
            .map((SearchFormFieldContract f) => f.toJson())
            .toList(growable: false),
      };

  @override
  List<Object?> get props =>
      <Object?>[urlPattern, fields, dataSources, defaultSort];

  static DynamicSearchFormContract? _inferMinimalQueryForm(
    Map<String, Object?> rawConfig,
    List<ValidationDiagnostic> diags,
  ) {
    final String? queryParam = _inferQueryParamFromUrlPattern(rawConfig);
    if (queryParam == null || queryParam.isEmpty) return null;

    final String? pageParam = _inferPageParamFromUrlPattern(rawConfig);
    diags.add(ValidationDiagnostic(
      severity: DiagnosticSeverity.info,
      code: 'searchAutowiringInferred',
      message:
          'Search form inferred from conventional query parameters: $queryParam.',
      feature: FeatureKind.dynamicForm,
      path: 'scraper.urlPatterns.search',
      context: <String, Object?>{
        'queryParam': queryParam,
        'pageParam': ?pageParam,
      },
    ));

    return DynamicSearchFormContract(
      urlPattern: 'search',
      fields: <SearchFormFieldContract>[
        SearchFormFieldContract(
          id: 'query',
          queryParam: queryParam,
          type: SearchFormFieldType.text,
          label: 'Search',
        ),
        if (pageParam != null)
          SearchFormFieldContract(
            id: '_page',
            queryParam: pageParam,
            type: SearchFormFieldType.hidden,
            label: 'Page',
          ),
      ],
      diagnostics: diags,
    );
  }

  static String? _inferQueryParamFromUrlPattern(
      Map<String, Object?> rawConfig) {
    final template = _searchUrlTemplate(rawConfig);
    if (template == null) return null;

    const candidates = <String>['q', 'query', 'search', 's', 'keyword', 'term'];
    for (final candidate in candidates) {
      if (RegExp('(?:[?&])$candidate=\\{[^}]+\\}').hasMatch(template)) {
        return candidate;
      }
    }

    final conventionalParam = RegExp(
      r'(?:[?&])([^=&]+)=\{(?:query|keyword|search|term)\}',
    ).firstMatch(template);
    if (conventionalParam != null) {
      return Uri.decodeComponent(conventionalParam.group(1)!);
    }

    return template.contains('{query}') ? 'q' : null;
  }

  static String? _inferPageParamFromUrlPattern(Map<String, Object?> rawConfig) {
    final template = _searchUrlTemplate(rawConfig);
    if (template == null) return null;

    const candidates = <String>['page', 'p', 'paged'];
    for (final candidate in candidates) {
      if (RegExp('(?:[?&])$candidate=\\{[^}]+\\}').hasMatch(template)) {
        return candidate;
      }
    }

    final conventionalParam = RegExp(
      r'(?:[?&])([^=&]+)=\{(?:page|p|paged)\}',
    ).firstMatch(template);
    if (conventionalParam != null) {
      return Uri.decodeComponent(conventionalParam.group(1)!);
    }

    return null;
  }

  static String? _searchUrlTemplate(Map<String, Object?> rawConfig) {
    final scraper = rawConfig['scraper'];
    if (scraper is Map) {
      final urlPatterns = scraper.cast<String, Object?>()['urlPatterns'];
      if (urlPatterns is Map) {
        final search = urlPatterns.cast<String, Object?>()['search'];
        if (search is String) return search;
        if (search is Map) {
          return search.cast<String, Object?>()['url']?.toString();
        }
      }
    }

    final api = rawConfig['api'];
    if (api is Map) {
      final endpoints = api.cast<String, Object?>()['endpoints'];
      if (endpoints is Map) {
        final search = endpoints.cast<String, Object?>()['search'];
        if (search is String) return search;
        if (search is Map) {
          return search.cast<String, Object?>()['url']?.toString();
        }
      }
    }

    return null;
  }

  static String? _firstString(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static void _addLegacyFormFields(
    Map<String, Object?> searchConfig,
    List<SearchFormFieldContract> fields,
  ) {
    final textFields = searchConfig['textFields'];
    if (textFields is List) {
      for (final item in textFields.whereType<Map>()) {
        final map = item.cast<String, Object?>();
        final name = map['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final queryParam = map['queryParam']?.toString() ?? name;
        if (fields.any((SearchFormFieldContract field) =>
            field.queryParam == queryParam)) {
          continue;
        }
        fields.add(SearchFormFieldContract(
          id: name,
          queryParam: queryParam,
          type: SearchFormFieldType.text,
          label: map['label']?.toString(),
          placeholder: map['placeholder']?.toString(),
        ));
      }
    }

    final radioGroups = searchConfig['radioGroups'];
    if (radioGroups is List) {
      for (final item in radioGroups.whereType<Map>()) {
        final map = item.cast<String, Object?>();
        final name = map['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final queryParam = map['queryParam']?.toString() ?? name;
        if (fields.any((SearchFormFieldContract field) =>
            field.queryParam == queryParam)) {
          continue;
        }
        fields.add(SearchFormFieldContract(
          id: name,
          queryParam: queryParam,
          type: SearchFormFieldType.radio,
          label: map['label']?.toString(),
          options: _optionsFromRawList(map['options']),
        ));
      }
    }

    final checkboxGroups = searchConfig['checkboxGroups'];
    if (checkboxGroups is List) {
      for (final item in checkboxGroups.whereType<Map>()) {
        final map = item.cast<String, Object?>();
        final name = map['name']?.toString();
        if (name == null || name.isEmpty) continue;
        final queryParam = map['paramName']?.toString() ??
            map['queryParam']?.toString() ??
            name;
        if (fields.any((SearchFormFieldContract field) =>
            field.queryParam == queryParam)) {
          continue;
        }
        fields.add(SearchFormFieldContract(
          id: name,
          queryParam: queryParam,
          type: SearchFormFieldType.checkbox,
          label: map['label']?.toString(),
          loadFromTags: map['loadFromTags'] as bool? ?? false,
          tagType: map['tagType']?.toString(),
          tagSourceUrl: map['tagSourceUrl']?.toString(),
          options: _optionsFromRawList(map['options']),
        ));
      }
    }
  }

  static List<SearchFormFieldOption> _optionsFromRawList(Object? raw) {
    if (raw is! List) return const <SearchFormFieldOption>[];
    return raw
        .map<SearchFormFieldOption>(SearchFormFieldOption.fromObject)
        .where((SearchFormFieldOption option) => option.value.isNotEmpty)
        .toList(growable: false);
  }

  static void _addUnsupportedFieldDiagnostics(
    String id,
    Map<String, Object?> map,
    List<ValidationDiagnostic> diags,
  ) {
    final type = map['type']?.toString() ?? 'text';
    const supported = <String>{
      'text',
      'input',
      'query',
      'radio',
      'tag',
      'picker',
      'lov',
      'select',
      'checkbox',
      'sort',
      'page',
      'hidden',
      'separator',
    };
    if (!supported.contains(type)) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'searchFieldUnsupported',
        message: 'Search field "$id" uses unsupported type "$type".',
        feature: FeatureKind.dynamicForm,
        path: 'searchForm.params.$id.type',
        context: <String, Object?>{'field': id, 'type': type},
      ));
    }

    final operators = map['operators'];
    if (operators is List && operators.isNotEmpty) {
      diags.add(ValidationDiagnostic(
        severity: DiagnosticSeverity.info,
        code: 'searchFieldOperatorsDetected',
        message: 'Search field "$id" uses operator serialization.',
        feature: FeatureKind.dynamicForm,
        path: 'searchForm.params.$id.operators',
        context: <String, Object?>{'field': id},
      ));
    }
  }
}
