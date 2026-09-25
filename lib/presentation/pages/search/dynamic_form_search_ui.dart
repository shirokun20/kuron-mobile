import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_generic/kuron_generic.dart'
    show DynamicSearchFormContract;
import 'package:kuron_special/kuron_special.dart' show doujinDesuDecrypt;
import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/colors_const.dart' show AppColors;
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/tag_data_manager.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/entities/search_filter.dart';
import 'package:nhasixapp/presentation/blocs/search/search_bloc.dart';
import 'package:nhasixapp/presentation/pages/search/search_form_contract_adapter.dart';

import 'package:nhasixapp/l10n/app_localizations.dart';

// Generic search form UI driven entirely by [SearchFormConfig].
///
// Renders form fields based on the `searchForm.params` block in the source
// config JSON. Supports field types:
//   - `text`   → [TextFormField]
//   - `select` → segmented choice chips
//   - `tag`    → text field (genre slug)
//   - `page`   → hidden (managed internally)
///
// On submit it saves a `SearchFilter` with `query = "raw:<params>"` which
// is consumed by [GenericScraperAdapter.search] to build the search URL.

/// Prepares a `searchForm.dataSources` payload for path extraction.
///
/// Sources whose API wraps every response in an encrypted envelope declare
/// `decrypt` in the dataSource config; the envelope is unwrapped here because
/// the picker fetches over plain HTTP instead of going through the source
/// adapter. `itemsPath` may be `""` to read a top-level JSON array.
dynamic decodeDataSourcePayload(dynamic payload, String? decrypt) {
  if (decrypt == 'doujindesuxxx' &&
      payload is Map &&
      payload['_enc_resp_'] is String) {
    final decoded = doujinDesuDecrypt(payload['_enc_resp_'] as String);
    if (decoded == null) {
      throw const FormatException('Failed to decrypt _enc_resp_ payload');
    }
    return decoded;
  }
  return payload;
}

class DynamicFormSearchUI extends StatefulWidget {
  final SearchFormConfig config;
  final String sourceId;
  final DynamicSearchFormContract? canonicalContract;
  final int reloadSignal;

  const DynamicFormSearchUI({
    super.key,
    required this.config,
    required this.sourceId,
    this.canonicalContract,
    this.reloadSignal = 0,
  });

  @override
  State<DynamicFormSearchUI> createState() => _DynamicFormSearchUIState();
}

class _DynamicFormSearchUIState extends State<DynamicFormSearchUI> {
  final _formKey = GlobalKey<FormState>();
  final _logger = getIt<Logger>();
  final _dio = getIt<Dio>();
  final _remoteConfigService = getIt<RemoteConfigService>();

  // Keyed by field logical name (e.g. "query", "status", "order", "genre")
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String?> _selectValues = {};
  final Map<String, List<_DynamicOption>> _multiSelectValues = {};
  final Map<String, List<String>> _tagChipValues = {};
  final Map<String, List<String>> _pendingMultiRestore = {};
  int _lastReloadSignal = 0;

  Map<String, dynamic>? _rawSearchForm;
  Map<String, dynamic> _dataSources = const {};
  final Map<String, List<_DynamicOption>> _optionCacheBySource = {};
  final Set<String> _loadingPickerSources = <String>{};
  final Map<String, String> _pickerLoadErrorBySource = <String, String>{};
  final Map<String, List<_DynamicOption>> _checkboxOptionCache = {};
  final Set<String> _loadingCheckboxFields = <String>{};
  final Map<String, String> _checkboxLoadErrorByField = {};

  bool _showAdvancedFilters = false;

  @override
  void initState() {
    super.initState();
    _lastReloadSignal = widget.reloadSignal;
    _initRawSearchForm();
    _initFields();
    context
        .read<SearchBloc>()
        .add(SearchInitializeEvent(sourceId: widget.sourceId));
    _initializeDynamicOptions();
  }

  @override
  void didUpdateWidget(covariant DynamicFormSearchUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadSignal != oldWidget.reloadSignal &&
        widget.reloadSignal != _lastReloadSignal) {
      _lastReloadSignal = widget.reloadSignal;
      _reloadDynamicOptions();
    }
  }

  void _initRawSearchForm() {
    final canonicalRaw = widget.canonicalContract == null
        ? null
        : SearchFormContractAdapter.toRawSearchForm(
            widget.canonicalContract!,
          );
    if (canonicalRaw != null) {
      _rawSearchForm = canonicalRaw;
      final dynamic dataSources = canonicalRaw['dataSources'];
      if (dataSources is Map<String, dynamic>) {
        _dataSources = dataSources;
      }
      return;
    }

    final rawSource = _remoteConfigService.getRawConfig(widget.sourceId);
    final rawForm = rawSource?['searchForm'];
    if (rawForm is Map<String, dynamic>) {
      _rawSearchForm = rawForm;
      final dynamic dataSources = rawForm['dataSources'];
      if (dataSources is Map<String, dynamic>) {
        _dataSources = dataSources;
      }
    }
  }

  void _initFields() {
    for (final entry in widget.config.params.entries) {
      final field = entry.value;
      if (_isPickerField(entry.key, field)) {
        _multiSelectValues[entry.key] = [];
        continue;
      }

      if (_isTagChipsField(entry.key, field)) {
        _textControllers[entry.key] = TextEditingController();
        _tagChipValues[entry.key] = <String>[];
        continue;
      }

      switch (field.type) {
        case 'text':
        case 'tag':
          _textControllers[entry.key] = TextEditingController();
        case 'select':
        case 'sort':
        case 'radio':
          _selectValues[entry.key] = null; // null = "all" / no filter
        case 'checkbox':
          _multiSelectValues[entry.key] = [];
        default:
          break; // 'page' and unknown types are ignored in the UI
      }
    }
  }

  Future<void> _initializeDynamicOptions() async {
    await _loadPickerOptions();
    await _loadCheckboxOptions();
    await _restoreSaved();
  }

  Future<void> _reloadDynamicOptions() async {
    _optionCacheBySource.clear();
    _pickerLoadErrorBySource.clear();
    _loadingPickerSources.clear();
    _checkboxOptionCache.clear();
    _checkboxLoadErrorByField.clear();
    _loadingCheckboxFields.clear();
    await _loadPickerOptions();
    await _loadCheckboxOptions();
    if (mounted) setState(() {});
  }

  Future<void> _loadPickerOptions() async {
    final sourceIds = <String>{};
    for (final entry in widget.config.params.entries) {
      final sourceId = _pickerDataSource(entry.key, entry.value);
      if (sourceId != null && sourceId.isNotEmpty) {
        sourceIds.add(sourceId);
      }
    }

    for (final sourceId in sourceIds) {
      if (_optionCacheBySource.containsKey(sourceId)) continue;
      await _loadPickerOptionsForSource(sourceId);
    }
  }

  Future<void> _loadPickerOptionsForSource(String sourceId,
      {bool force = false}) async {
    if (_loadingPickerSources.contains(sourceId)) return;
    if (!force && _optionCacheBySource.containsKey(sourceId)) return;

    final dynamic sourceConfig = _dataSources[sourceId];
    if (sourceConfig is! Map<String, dynamic>) return;

    final localOptions = sourceConfig['options'];
    if (localOptions is List) {
      final valuePath = sourceConfig['valuePath'] as String? ?? 'id';
      final labelPath = sourceConfig['labelPath'] as String? ?? 'id';
      final groupPath = sourceConfig['groupPath'] as String?;

      final options = <_DynamicOption>[];
      for (final item in localOptions) {
        final value = _extractByPath(item, valuePath)?.toString() ?? '';
        final label = _extractByPath(item, labelPath)?.toString() ?? value;
        if (value.isEmpty || label.isEmpty) continue;
        final group = groupPath == null
            ? null
            : _extractByPath(item, groupPath)?.toString();
        options.add(_DynamicOption(value: value, label: label, group: group));
      }
      _optionCacheBySource[sourceId] = options;
      _pickerLoadErrorBySource.remove(sourceId);
      if (mounted) setState(() {});
      return;
    }

    final endpoint = sourceConfig['endpoint'] as String?;
    if (endpoint == null || endpoint.isEmpty) {
      _optionCacheBySource[sourceId] = const [];
      _pickerLoadErrorBySource[sourceId] = 'Missing endpoint or options';
      return;
    }

    _loadingPickerSources.add(sourceId);
    if (mounted) setState(() {});

    try {
      final rawConfig = _remoteConfigService.getRawConfig(widget.sourceId);
      final baseUrl = ((rawConfig?['api'] as Map?)?['baseUrl'] as String?) ??
          (rawConfig?['baseUrl'] as String?) ??
          '';
      final url = endpoint.startsWith('http')
          ? endpoint
          : '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}${endpoint.startsWith('/') ? endpoint : '/$endpoint'}';

      final response = await _dio.get<dynamic>(url);
      // The global Dio client uses ResponseType.plain, so data may arrive as a
      // raw JSON string. Decode it so _extractByPath can navigate the Map/List.
      dynamic payload = response.data;
      if (payload is String) {
        try {
          payload = jsonDecode(payload);
        } catch (e) {
          _optionCacheBySource[sourceId] = const [];
          _pickerLoadErrorBySource[sourceId] =
              'Failed to parse response as JSON: $e';
          return;
        }
      }
      try {
        payload = decodeDataSourcePayload(
            payload, sourceConfig['decrypt'] as String?);
      } catch (e) {
        _optionCacheBySource[sourceId] = const [];
        _pickerLoadErrorBySource[sourceId] = '$e';
        return;
      }
      final itemsPath = sourceConfig['itemsPath'] as String? ?? 'data';
      final valuePath = sourceConfig['valuePath'] as String? ?? 'id';
      final labelPath = sourceConfig['labelPath'] as String? ?? 'id';
      final groupPath = sourceConfig['groupPath'] as String?;

      final items = _extractByPath(payload, itemsPath);
      if (items is! List) {
        _optionCacheBySource[sourceId] = const [];
        _pickerLoadErrorBySource[sourceId] =
            'Invalid response shape at "$itemsPath"';
        return;
      }

      final options = <_DynamicOption>[];
      for (final item in items) {
        final value = _extractByPath(item, valuePath)?.toString() ?? '';
        final label = _extractByPath(item, labelPath)?.toString() ?? value;
        if (value.isEmpty || label.isEmpty) continue;
        final group = groupPath == null
            ? null
            : _extractByPath(item, groupPath)?.toString();
        options.add(_DynamicOption(value: value, label: label, group: group));
      }

      _optionCacheBySource[sourceId] = options;
      _pickerLoadErrorBySource.remove(sourceId);
    } catch (e) {
      _logger.w('DynamicFormSearchUI: failed loading source $sourceId: $e');
      _optionCacheBySource[sourceId] = const [];
      _pickerLoadErrorBySource[sourceId] = e.toString();
    } finally {
      _loadingPickerSources.remove(sourceId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadCheckboxOptions() async {
    for (final entry in widget.config.params.entries) {
      final fieldName = entry.key;
      final field = entry.value;
      if (!_isDynamicCheckboxField(fieldName, field)) continue;
      if (_checkboxOptionCache.containsKey(fieldName)) continue;
      await _loadCheckboxOptionsForField(fieldName);
    }
  }

  Future<void> _loadCheckboxOptionsForField(
    String fieldName, {
    bool force = false,
  }) async {
    if (_loadingCheckboxFields.contains(fieldName)) return;
    if (!force && _checkboxOptionCache.containsKey(fieldName)) return;

    final rawField = _rawFieldConfig(fieldName);
    if (rawField == null) return;

    final dynamic rawOptions = rawField['options'];
    final hasStaticOptions = rawOptions is List && rawOptions.isNotEmpty;
    final tagSourceUrl = rawField['tagSourceUrl'] as String?;
    final loadFromTags = rawField['loadFromTags'] as bool? ?? false;
    final tagType = rawField['tagType']?.toString();

    if ((tagSourceUrl == null || tagSourceUrl.isEmpty) &&
        (tagType == null || tagType.isEmpty) &&
        !loadFromTags &&
        !hasStaticOptions) {
      return;
    }

    _loadingCheckboxFields.add(fieldName);
    if (mounted) setState(() {});

    try {
      final tagManager = getIt<TagDataManager>();
      final List<_DynamicOption> options;
      if (tagSourceUrl != null && tagSourceUrl.isNotEmpty) {
        final allTags = await tagManager.loadTagsFromUrl(tagSourceUrl);
        var filtered = allTags;
        if (tagType != null && tagType.isNotEmpty) {
          filtered = allTags.where((t) => t.type == tagType).toList();
        }
        options = filtered
            .map(
              (tag) => _DynamicOption(
                value: (tag.slug ?? '').isNotEmpty ? tag.slug! : tag.name,
                label: tag.name,
              ),
            )
            .toList(growable: false);
      } else if (loadFromTags && tagType != null && tagType.isNotEmpty) {
        final tags = await tagManager.getTagsByType(
          tagType,
          source: widget.sourceId,
        );
        options = tags
            .map(
              (tag) => _DynamicOption(
                value: (tag.slug ?? '').isNotEmpty ? tag.slug! : tag.name,
                label: tag.name,
              ),
            )
            .toList(growable: false);
      } else {
        options = _optionsForStaticField(rawField);
      }

      _checkboxOptionCache[fieldName] = options;
      _checkboxLoadErrorByField.remove(fieldName);
    } catch (e) {
      _logger.w(
        'DynamicFormSearchUI: failed loading checkbox field $fieldName: $e',
      );
      _checkboxOptionCache[fieldName] = const [];
      _checkboxLoadErrorByField[fieldName] = e.toString();
    } finally {
      _loadingCheckboxFields.remove(fieldName);
      if (mounted) setState(() {});
    }
  }

  Future<void> _restoreSaved() async {
    try {
      final saved = await getIt<UserDataRepository>()
          .getLastSearchFilter(widget.sourceId);
      if (saved == null) return;
      final query = saved.query;
      if (query == null || !query.startsWith('raw:')) return;

      final parsed = _parseRaw(query.substring(4));

      final fieldsByParam =
          <String, List<MapEntry<String, SearchFormFieldConfig>>>{};
      for (final entry in widget.config.params.entries) {
        final qp = entry.value.queryParam;
        if (qp == null) continue;
        (fieldsByParam[qp] ??= <MapEntry<String, SearchFormFieldConfig>>[])
            .add(entry);
      }

      for (final grouped in fieldsByParam.entries) {
        final queryParam = grouped.key;
        final fields = grouped.value;
        final values = parsed[queryParam] ?? const <String>[];
        if (values.isEmpty) continue;

        final hasSpaceJoin = fields.any((entry) {
          final raw = _rawFieldConfig(entry.key);
          return ((raw?['joinMode'] as String?)?.trim().toLowerCase() ?? '') ==
              'space';
        });

        if (fields.length > 1 && hasSpaceJoin) {
          _restoreJoinedParamGroup(queryParam, values.first, fields);
          continue;
        }

        for (final entry in fields) {
          final field = entry.value;
          final rawField = _rawFieldConfig(entry.key);
          final prefix = (rawField?['valuePrefix'] as String? ?? '').trim();

          if (_isPickerField(entry.key, field)) {
            final validValues = <String>[];
            for (final v in values) {
              if (prefix.isEmpty || v.startsWith(prefix)) {
                validValues.add(v.substring(prefix.length));
              }
            }
            if (validValues.isNotEmpty) {
              _pendingMultiRestore[entry.key] = validValues;
            }
            continue;
          }

          // Only restore value to fields whose valuePrefix matches the raw value.
          // This prevents cross-contamination when multiple fields share the same
          // queryParam (e.g. spyfakku: includeTag/excludeTag/artist/parody all → q).
          if (prefix.isNotEmpty && values.any((v) => v.startsWith(prefix))) {
            _setRestoredFieldValue(entry.key, field, values);
          } else if (prefix.isEmpty) {
            _setRestoredFieldValue(entry.key, field, values);
          }
        }
      }

      // Chip/text/select restoration does not always go through
      // _applyPendingMultiRestore(), so ensure UI reflects restored values.
      if (mounted) {
        setState(() {});
      }

      _applyPendingMultiRestore();
    } catch (e) {
      _logger.w('DynamicFormSearchUI: failed to restore filter: $e');
    }
  }

  void _applyPendingMultiRestore() {
    if (_pendingMultiRestore.isEmpty) return;

    for (final entry in _pendingMultiRestore.entries) {
      final fieldName = entry.key;
      final field = widget.config.params[fieldName];
      if (field == null) continue;
      final sourceId = _pickerDataSource(fieldName, field);
      if (sourceId == null) continue;

      final options =
          _optionCacheBySource[sourceId] ?? const <_DynamicOption>[];
      final selected = entry.value
          .map((value) => options.firstWhere(
                (o) => o.value == value,
                orElse: () => _DynamicOption(value: value, label: value),
              ))
          .toList();
      _multiSelectValues[fieldName] = selected;
    }

    _pendingMultiRestore.clear();
    if (mounted) setState(() {});
  }

  Map<String, List<String>> _parseRaw(String raw) {
    final result = <String, List<String>>{};
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) continue;
      final k = Uri.decodeComponent(pair.substring(0, idx));
      final v = Uri.decodeComponent(pair.substring(idx + 1));
      (result[k] ??= []).add(v);
    }
    return result;
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onSearch() async {
    if (!_formKey.currentState!.validate()) return;

    //  numeric-only query --> redirect langsung ke halaman detail
    final queryValue = _textControllers['query']?.text.trim() ?? '';
    if (queryValue.isNotEmpty && RegExp(r'^\d+$').hasMatch(queryValue)) {
      if (!mounted) return;
      context.push('/content/${Uri.encodeComponent(queryValue)}');
      return;
    }

    final selectedTagItems = <FilterItem>[];
    final parts = _collectEncodedQueryParts(selectedTagItems: selectedTagItems);
    final rawQuery = parts.isNotEmpty ? 'raw:${parts.join('&')}' : '';
    final filter = SearchFilter(
      query: rawQuery,
      tags: selectedTagItems,
    );

    try {
      await getIt<UserDataRepository>()
          .saveSearchFilter(widget.sourceId, filter);
      _logger.d(
        'DynamicFormSearchUI: saved search filter for ${widget.sourceId} '
        'query=$rawQuery sort=${filter.sortBy.name}',
      );
    } catch (e) {
      _logger.e('DynamicFormSearchUI: failed to save filter: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .failedToApplySearch(e.toString()))),
        );
      }
      return;
    }

    if (!mounted) return;
    if (context.canPop()) {
      context.pop(true);
      return;
    }

    _logger.w('DynamicFormSearchUI: search filter saved but route cannot pop');
  }

  Future<void> _onReset() async {
    for (final c in _textControllers.values) {
      c.clear();
    }
    setState(() {
      for (final key in _selectValues.keys) {
        _selectValues[key] = null;
      }
      for (final key in _multiSelectValues.keys) {
        _multiSelectValues[key] = [];
      }
      for (final key in _tagChipValues.keys) {
        _tagChipValues[key] = [];
      }
    });
    await getIt<UserDataRepository>().clearSearchFilter(widget.sourceId);
    if (mounted && context.canPop()) {
      context.pop(true);
    }
  }

  bool _isAdvancedField(String name, SearchFormFieldConfig field) {
    // Primary: text search query (name=query or search) and sort. Everything else is advanced.
    if (field.type == 'sort') return false;
    final lowerName = name.toLowerCase();
    if (lowerName == 'query' || lowerName == 'search') return false;
    return true;
  }

  int _countActiveAdvancedFilters() {
    var count = 0;
    for (final entry in widget.config.params.entries) {
      final name = entry.key;
      final field = entry.value;
      if (!_isAdvancedField(name, field)) continue;
      if (field.type == 'page') continue;
      if (_shouldHideBecauseCombinedPicker(name, field)) continue;

      if (field.type == 'select' || field.type == 'radio') {
        if (_selectValues[name] != null) count++;
      } else if (_isPickerField(name, field)) {
        if ((_multiSelectValues[name] ?? const <_DynamicOption>[]).isNotEmpty) {
          count++;
        }
      } else if (_isTagChipsField(name, field)) {
        if ((_tagChipValues[name] ?? const <String>[]).isNotEmpty ||
            (_textControllers[name]?.text.trim().isNotEmpty ?? false)) {
          count++;
        }
      } else if (field.type == 'text' || field.type == 'tag') {
        if (_textControllers[name]?.text.trim().isNotEmpty ?? false) count++;
      } else if (field.type == 'checkbox') {
        if ((_multiSelectValues[name] ?? const <_DynamicOption>[]).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final allFields = widget.config.params.entries
        .where((e) =>
            e.value.type != 'page' &&
            !_shouldHideBecauseCombinedPicker(e.key, e.value))
        .toList();

    final primaryFields =
        allFields.where((e) => !_isAdvancedField(e.key, e.value)).toList();

    final advancedFields =
        allFields.where((e) => _isAdvancedField(e.key, e.value)).toList();

    final hasAdvanced = advancedFields.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in primaryFields)
                    _buildField(entry.key, entry.value),
                  if (hasAdvanced) ...[
                    const SizedBox(height: DesignTokens.spaceSm),
                    _buildAdvancedToggle(),
                    const SizedBox(height: DesignTokens.spaceSm),
                  ],
                  if (hasAdvanced)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: _showAdvancedFilters
                            ? Column(
                                key: const ValueKey('advanced_open'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final entry in advancedFields)
                                    _buildField(entry.key, entry.value),
                                ],
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('advanced_closed'),
                              ),
                      ),
                    ),
                  _buildQueryPreviewCard(),
                  const SizedBox(height: DesignTokens.spaceXl),
                  FilledButton.icon(
                    onPressed: _onSearch,
                    icon: const Icon(Icons.search),
                    label: Text(AppLocalizations.of(context)!.search),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceSm),
                  OutlinedButton(
                    onPressed: _onReset,
                    child: Text(AppLocalizations.of(context)!.reset),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedToggle() {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = _countActiveAdvancedFilters();

    return InkWell(
      onTap: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _showAdvancedFilters
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _showAdvancedFilters
                ? Colors.transparent
                : colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              scale: _showAdvancedFilters ? 1.08 : 1.0,
              child: Icon(
                Icons.tune_rounded,
                color: _showAdvancedFilters
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.advancedFilters,
              style: TextStyle(
                color: _showAdvancedFilters
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Container(
                  key: ValueKey(activeCount),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _showAdvancedFilters
                        ? colorScheme.onPrimary
                        : colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: TextStyle(
                      color: _showAdvancedFilters
                          ? colorScheme.primary
                          : colorScheme.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            AnimatedRotation(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              turns: _showAdvancedFilters ? 0.5 : 0,
              child: Icon(
                Icons.expand_more,
                color: _showAdvancedFilters
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String name, SearchFormFieldConfig field) {
    if (_isPickerField(name, field) && _isIncludedTagField(name, field)) {
      final excludedName = _findPairedExcludedFieldName();
      if (excludedName != null) {
        final excludedField = widget.config.params[excludedName];
        if (excludedField != null &&
            _isPickerField(excludedName, excludedField)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildCombinedPickerField(
              includedName: name,
              includedField: field,
              excludedName: excludedName,
              excludedField: excludedField,
            ),
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (field.type) {
        _ when _isPickerField(name, field) => _buildPickerField(name, field),
        'text' => _buildTextField(name, field),
        'tag' => _isTagChipsField(name, field)
            ? _buildTagChipsField(name, field)
            : _buildTagField(name, field),
        'select' => _buildSelectField(name, field),
        'sort' => _buildSelectField(name, field),
        'radio' => _buildSelectField(name, field),
        'checkbox' => _buildCheckboxField(name, field),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildTextField(String name, SearchFormFieldConfig field) {
    return TextFormField(
      controller: _textControllers[name],
      decoration: InputDecoration(
        labelText: _labelFor(name),
        hintText: field.placeholder,
        prefixIcon: _iconFor(name),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
        filled: true,
      ),
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => _onSearch(),
    );
  }

  Widget _buildTagField(String name, SearchFormFieldConfig field) {
    return TextFormField(
      controller: _textControllers[name],
      decoration: InputDecoration(
        labelText: _labelFor(name),
        hintText: field.placeholder ?? 'Enter ${_labelFor(name).toLowerCase()}',
        prefixIcon: const Icon(Icons.tag),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
        filled: true,
      ),
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => _onSearch(),
    );
  }

  Widget _buildTagChipsField(String name, SearchFormFieldConfig field) {
    final chips = _tagChipValues[name] ?? const <String>[];
    final controller = _textControllers[name];
    final accent = _isExcludedTagField(name, field)
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;

    void addCurrentInput() {
      final value = controller?.text.trim() ?? '';
      if (value.isEmpty) return;
      final split = _splitFieldInput(_rawFieldConfig(name), value, field.type);
      if (split.isEmpty) return;

      setState(() {
        final next = <String>[...chips];
        for (final item in split) {
          if (!next.contains(item)) {
            next.add(item);
          }
        }
        _tagChipValues[name] = next;
        controller?.clear();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: _labelFor(name),
            hintText: field.placeholder ?? 'Add tag and press +',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              tooltip: AppLocalizations.of(context)!.addTag,
              onPressed: addCurrentInput,
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
            filled: true,
          ),
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => addCurrentInput(),
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)!.tagInputTip,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.9),
              ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips
                .map(
                  (chip) => InputChip(
                    label: Text(chip),
                    backgroundColor: accent.withValues(alpha: 0.14),
                    side: BorderSide(color: accent.withValues(alpha: 0.55)),
                    deleteIconColor: accent,
                    onDeleted: () {
                      setState(() {
                        _tagChipValues[name] =
                            chips.where((x) => x != chip).toList();
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildPickerField(String name, SearchFormFieldConfig field) {
    final selected = _multiSelectValues[name] ?? const <_DynamicOption>[];
    final sourceId = _pickerDataSource(name, field);
    final pickerColors = _pickerSelectedColors(name, field, context);
    final accentColor = pickerColors.accent;
    final baseIcon = _pickerLeadingIcon(name, field);
    final isLoading =
        sourceId != null && _loadingPickerSources.contains(sourceId);
    final hasLoadError =
        sourceId != null && _pickerLoadErrorBySource.containsKey(sourceId);
    final hasCachedOptions = sourceId != null &&
        (_optionCacheBySource[sourceId]?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name).toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            onTap: () => _openPicker(name, field),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                border: Border.all(
                  color: hasLoadError
                      ? Theme.of(context).colorScheme.error
                      : selected.isEmpty
                          ? Theme.of(context).colorScheme.outline
                          : accentColor.withValues(alpha: 0.75),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasLoadError ? Icons.warning_amber_rounded : baseIcon,
                    color: hasLoadError
                        ? Theme.of(context).colorScheme.error
                        : accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected.isEmpty
                          ? (isLoading
                              ? AppLocalizations.of(context)!.loadingOptions
                              : hasLoadError
                                  ? AppLocalizations.of(context)!
                                      .failedToLoadOptionsTap
                                  : hasCachedOptions
                                      ? (field.placeholder ??
                                          AppLocalizations.of(context)!
                                              .chooseField(_labelFor(name)))
                                      : AppLocalizations.of(context)!
                                          .tapToLoadOptions)
                          : AppLocalizations.of(context)!
                              .nSelectedItems(selected.length),
                      style: selected.isEmpty
                          ? null
                          : TextStyle(
                              color: pickerColors.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ),
                  if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    )
                  else
                    Icon(Icons.chevron_right, color: accentColor),
                ],
              ),
            ),
          ),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selected
                .map(
                  (e) => InputChip(
                    label: Text(e.label),
                    labelStyle: TextStyle(
                      color: pickerColors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: pickerColors.background,
                    side: BorderSide(color: pickerColors.border),
                    deleteIconColor: accentColor,
                    onDeleted: () {
                      setState(() {
                        _multiSelectValues[name] =
                            selected.where((x) => x.value != e.value).toList();
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildCombinedPickerField({
    required String includedName,
    required SearchFormFieldConfig includedField,
    required String excludedName,
    required SearchFormFieldConfig excludedField,
  }) {
    final included =
        _multiSelectValues[includedName] ?? const <_DynamicOption>[];
    final excluded =
        _multiSelectValues[excludedName] ?? const <_DynamicOption>[];

    final sourceId = _pickerDataSource(includedName, includedField) ??
        _pickerDataSource(excludedName, excludedField);
    final isLoading =
        sourceId != null && _loadingPickerSources.contains(sourceId);
    final hasLoadError =
        sourceId != null && _pickerLoadErrorBySource.containsKey(sourceId);
    final hasCachedOptions = sourceId != null &&
        (_optionCacheBySource[sourceId]?.isNotEmpty ?? false);

    final includeColors = _tagChipColors(_TagPickState.include, context);
    final excludeColors = _tagChipColors(_TagPickState.exclude, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.filterTags,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            onTap: () => _openCombinedPicker(
              includedName: includedName,
              includedField: includedField,
              excludedName: excludedName,
              excludedField: excludedField,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                border: Border.all(
                  color: hasLoadError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasLoadError ? Icons.warning_amber_rounded : Icons.tune,
                    color: hasLoadError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (included.isEmpty && excluded.isEmpty)
                          ? (isLoading
                              ? AppLocalizations.of(context)!.loadingOptions
                              : hasLoadError
                                  ? AppLocalizations.of(context)!
                                      .failedToLoadOptionsTap
                                  : hasCachedOptions
                                      ? AppLocalizations.of(context)!
                                          .tapToChooseTags
                                      : AppLocalizations.of(context)!
                                          .tapToLoadOptions)
                          : AppLocalizations.of(context)!.includeExcludeCount(
                              included.length, excluded.length),
                    ),
                  ),
                  if (isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        if (included.isNotEmpty || excluded.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...included.map(
                (e) => InputChip(
                  label: Text(e.label),
                  labelStyle: TextStyle(
                    color: includeColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  avatar: Icon(
                    Icons.add,
                    size: 14,
                    color: includeColors.accent,
                  ),
                  backgroundColor: includeColors.background,
                  side: BorderSide(color: includeColors.border),
                  deleteIconColor: includeColors.accent,
                  onDeleted: () {
                    setState(() {
                      _multiSelectValues[includedName] =
                          included.where((x) => x.value != e.value).toList();
                    });
                  },
                ),
              ),
              ...excluded.map(
                (e) => InputChip(
                  label: Text(e.label),
                  labelStyle: TextStyle(
                    color: excludeColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  avatar: Icon(
                    Icons.remove,
                    size: 14,
                    color: excludeColors.accent,
                  ),
                  backgroundColor: excludeColors.background,
                  side: BorderSide(color: excludeColors.border),
                  deleteIconColor: excludeColors.accent,
                  onDeleted: () {
                    setState(() {
                      _multiSelectValues[excludedName] =
                          excluded.where((x) => x.value != e.value).toList();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openCombinedPicker({
    required String includedName,
    required SearchFormFieldConfig includedField,
    required String excludedName,
    required SearchFormFieldConfig excludedField,
  }) async {
    final sourceId = _pickerDataSource(includedName, includedField) ??
        _pickerDataSource(excludedName, excludedField);
    if (sourceId == null) return;

    if (_loadingPickerSources.contains(sourceId)) return;

    final hasOptions = _optionCacheBySource[sourceId]?.isNotEmpty ?? false;
    if (!hasOptions) {
      await _loadPickerOptionsForSource(sourceId, force: true);
    }

    final options = List<_DynamicOption>.from(
      _optionCacheBySource[sourceId] ?? const <_DynamicOption>[],
    );

    if (options.isEmpty) {
      if (!mounted) return;
      final loadError = _pickerLoadErrorBySource[sourceId];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loadError == null || loadError.isEmpty
              ? AppLocalizations.of(context)!.noOptionsAvailable
              : AppLocalizations.of(context)!.failedLoadingOptions),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.retryAction,
            onPressed: () => _openCombinedPicker(
              includedName: includedName,
              includedField: includedField,
              excludedName: excludedName,
              excludedField: excludedField,
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    final includeColors = _tagChipColors(_TagPickState.include, context);
    final excludeColors = _tagChipColors(_TagPickState.exclude, context);

    final selectedState = <String, _TagPickState>{
      for (final o
          in _multiSelectValues[includedName] ?? const <_DynamicOption>[])
        o.value: _TagPickState.include,
      for (final o
          in _multiSelectValues[excludedName] ?? const <_DynamicOption>[])
        o.value: _TagPickState.exclude,
    };

    var query = '';

    if (!mounted) return;

    final result = await showModalBottomSheet<_CombinedPickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = options.where((o) {
              if (query.isEmpty) return true;
              return o.label.toLowerCase().contains(query.toLowerCase());
            }).toList();

            final grouped = <String, List<_DynamicOption>>{};
            for (final option in filtered) {
              final groupRaw = option.group?.trim();
              final key = (groupRaw == null || groupRaw.isEmpty)
                  ? 'other'
                  : groupRaw.toLowerCase();
              (grouped[key] ??= <_DynamicOption>[]).add(option);
            }

            const groupOrder = <String>[
              'format',
              'genre',
              'theme',
              'content',
              'other',
            ];

            final groupKeys = grouped.keys.toList()
              ..sort((a, b) {
                final ia = groupOrder.indexOf(a);
                final ib = groupOrder.indexOf(b);
                final ra = ia == -1 ? groupOrder.length : ia;
                final rb = ib == -1 ? groupOrder.length : ib;
                if (ra != rb) return ra.compareTo(rb);
                return a.compareTo(b);
              });

            int includeCount = 0;
            int excludeCount = 0;
            for (final state in selectedState.values) {
              if (state == _TagPickState.include) includeCount++;
              if (state == _TagPickState.exclude) excludeCount++;
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.8),
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusFull),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.filterTags,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: selectedState.isEmpty
                                ? null
                                : () => setSheetState(selectedState.clear),
                            child: Text(AppLocalizations.of(context)!.reset),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spaceXs),
                      Row(
                        children: [
                          Icon(Icons.add_circle_outline,
                              size: 16, color: includeColors.accent),
                          const SizedBox(width: 4),
                          Text(AppLocalizations.of(context)!
                              .includeCountLabel(includeCount)),
                          const SizedBox(width: 12),
                          Icon(Icons.remove_circle_outline,
                              size: 16, color: excludeColors.accent),
                          const SizedBox(width: 4),
                          Text(AppLocalizations.of(context)!
                              .excludeCountLabel(excludeCount)),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spaceSm),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText:
                              AppLocalizations.of(context)!.searchTagsHint,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusLg),
                          ),
                          filled: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  AppLocalizations.of(context)!.noTagsFound,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            : ListView(
                                controller: scrollController,
                                children: [
                                  for (final groupKey in groupKeys) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 6, bottom: 8),
                                      child: Text(
                                        _capitalize(groupKey),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children:
                                          grouped[groupKey]!.map((option) {
                                        final pickState =
                                            selectedState[option.value];
                                        final isInclude =
                                            pickState == _TagPickState.include;
                                        final isExclude =
                                            pickState == _TagPickState.exclude;
                                        final selectedColors = isInclude
                                            ? includeColors
                                            : isExclude
                                                ? excludeColors
                                                : null;
                                        final fallbackBorder = Theme.of(context)
                                            .colorScheme
                                            .outlineVariant;

                                        return FilterChip(
                                          showCheckmark: false,
                                          label: Text(option.label),
                                          selected: isInclude || isExclude,
                                          avatar: isInclude
                                              ? Icon(Icons.add,
                                                  size: 14,
                                                  color: includeColors.accent)
                                              : isExclude
                                                  ? Icon(Icons.remove,
                                                      size: 14,
                                                      color:
                                                          excludeColors.accent)
                                                  : null,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerLow,
                                          selectedColor:
                                              selectedColors?.background,
                                          side: BorderSide(
                                            color: (isInclude || isExclude)
                                                ? selectedColors!.border
                                                : fallbackBorder,
                                          ),
                                          checkmarkColor:
                                              selectedColors?.foreground,
                                          labelStyle: TextStyle(
                                            color: (isInclude || isExclude)
                                                ? selectedColors!.foreground
                                                : null,
                                            fontWeight: (isInclude || isExclude)
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                          onSelected: (_) {
                                            setSheetState(() {
                                              final current =
                                                  selectedState[option.value];
                                              if (current == null) {
                                                selectedState[option.value] =
                                                    _TagPickState.include;
                                              } else if (current ==
                                                  _TagPickState.include) {
                                                selectedState[option.value] =
                                                    _TagPickState.exclude;
                                              } else {
                                                selectedState
                                                    .remove(option.value);
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(
                                        height: DesignTokens.spaceMd),
                                  ],
                                  const SizedBox(height: DesignTokens.spaceSm),
                                ],
                              ),
                      ),
                      const SizedBox(height: DesignTokens.spaceSm),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final include = options
                                .where((o) =>
                                    selectedState[o.value] ==
                                    _TagPickState.include)
                                .toList();
                            final exclude = options
                                .where((o) =>
                                    selectedState[o.value] ==
                                    _TagPickState.exclude)
                                .toList();
                            context.pop(
                              _CombinedPickerResult(
                                included: include,
                                excluded: exclude,
                              ),
                            );
                          },
                          child: Text(AppLocalizations.of(context)!
                              .applyWithCounts(includeCount, excludeCount)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _multiSelectValues[includedName] = result.included;
        _multiSelectValues[excludedName] = result.excluded;

        if (result.included.isNotEmpty) {
          final includedModeName =
              _findFieldNameByQueryParam('includedTagsMode');
          if (includedModeName != null &&
              _selectValues[includedModeName] == null) {
            _selectValues[includedModeName] = 'AND';
          }
        }

        if (result.excluded.isNotEmpty) {
          final excludedModeName =
              _findFieldNameByQueryParam('excludedTagsMode');
          if (excludedModeName != null &&
              _selectValues[excludedModeName] == null) {
            _selectValues[excludedModeName] = 'AND';
          }
        }
      });
    }
  }

  Future<void> _openPicker(String name, SearchFormFieldConfig field) async {
    final sourceId = _pickerDataSource(name, field);
    final pickerColors = _pickerSelectedColors(name, field, context);
    final accentColor = pickerColors.accent;
    final pickerIcon = _pickerLeadingIcon(name, field);
    if (sourceId == null) return;

    if (_loadingPickerSources.contains(sourceId)) {
      return;
    }

    final hasOptions = _optionCacheBySource[sourceId]?.isNotEmpty ?? false;
    if (!hasOptions) {
      await _loadPickerOptionsForSource(sourceId, force: true);
    }

    final options = List<_DynamicOption>.from(
      _optionCacheBySource[sourceId] ?? const <_DynamicOption>[],
    );
    if (options.isEmpty) {
      if (!mounted) return;
      final loadError = _pickerLoadErrorBySource[sourceId];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loadError == null || loadError.isEmpty
              ? AppLocalizations.of(context)!.noOptionsAvailable
              : AppLocalizations.of(context)!.failedLoadingOptions),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.retryAction,
            onPressed: () => _openPicker(name, field),
          ),
        ),
      );
      return;
    }

    final selected = List<_DynamicOption>.from(_multiSelectValues[name] ?? []);
    final selectedValues = selected.map((e) => e.value).toSet();
    var query = '';

    if (!mounted) return;

    final result = await showModalBottomSheet<List<_DynamicOption>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = options.where((o) {
              if (query.isEmpty) return true;
              return o.label.toLowerCase().contains(query.toLowerCase());
            }).toList();

            final grouped = <String, List<_DynamicOption>>{};
            for (final option in filtered) {
              final groupRaw = option.group?.trim();
              final key = (groupRaw == null || groupRaw.isEmpty)
                  ? 'other'
                  : groupRaw.toLowerCase();
              (grouped[key] ??= <_DynamicOption>[]).add(option);
            }

            const groupOrder = <String>[
              'format',
              'genre',
              'theme',
              'content',
              'other',
            ];

            final groupKeys = grouped.keys.toList()
              ..sort((a, b) {
                final ia = groupOrder.indexOf(a);
                final ib = groupOrder.indexOf(b);
                final ra = ia == -1 ? groupOrder.length : ia;
                final rb = ib == -1 ? groupOrder.length : ib;
                if (ra != rb) return ra.compareTo(rb);
                return a.compareTo(b);
              });

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.8),
                          borderRadius:
                              BorderRadius.circular(DesignTokens.radiusFull),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(pickerIcon, color: accentColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select ${_labelFor(name)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: accentColor,
                            ),
                            onPressed: selectedValues.isEmpty
                                ? null
                                : () =>
                                    setSheetState(() => selectedValues.clear()),
                            child: Text(AppLocalizations.of(context)!.reset),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spaceSm),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText:
                              AppLocalizations.of(context)!.searchTagsHint,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusLg),
                          ),
                          filled: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  AppLocalizations.of(context)!.noTagsFound,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            : ListView(
                                controller: scrollController,
                                children: [
                                  for (final groupKey in groupKeys) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 6, bottom: 8),
                                      child: Text(
                                        _capitalize(groupKey),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: grouped[groupKey]!.map(
                                        (option) {
                                          final isSelected = selectedValues
                                              .contains(option.value);
                                          return FilterChip(
                                            label: Text(option.label),
                                            selected: isSelected,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerLow,
                                            selectedColor:
                                                pickerColors.background,
                                            side: BorderSide(
                                              color: isSelected
                                                  ? pickerColors.border
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .outlineVariant,
                                            ),
                                            checkmarkColor:
                                                pickerColors.foreground,
                                            labelStyle: TextStyle(
                                              color: isSelected
                                                  ? pickerColors.foreground
                                                  : null,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                            onSelected: (isSelected) {
                                              setSheetState(() {
                                                if (isSelected) {
                                                  selectedValues
                                                      .add(option.value);
                                                } else {
                                                  selectedValues
                                                      .remove(option.value);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ).toList(),
                                    ),
                                    const SizedBox(
                                        height: DesignTokens.spaceMd),
                                  ],
                                  const SizedBox(height: DesignTokens.spaceSm),
                                ],
                              ),
                      ),
                      const SizedBox(height: DesignTokens.spaceSm),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: _onAccentColor(accentColor),
                            textStyle: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          onPressed: () {
                            final applied = options
                                .where((o) => selectedValues.contains(o.value))
                                .toList();
                            context.pop(applied);
                          },
                          child: Text(AppLocalizations.of(context)!
                              .applyWithCount(selectedValues.length)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _multiSelectValues[name] = result;
      });
    }
  }

  bool _isPickerField(String name, SearchFormFieldConfig field) {
    if (field.type != 'tag') return false;
    final rawField = _rawFieldConfig(name);
    final ui = rawField?['ui'];
    if (ui is Map<String, dynamic>) {
      return (ui['selector'] as String?) == 'picker' &&
          (ui['multi'] as bool? ?? false);
    }
    return false;
  }

  bool _isTagChipsField(String name, SearchFormFieldConfig field) {
    if (field.type != 'tag') return false;
    final rawField = _rawFieldConfig(name);
    final ui = rawField?['ui'];
    if (ui is Map<String, dynamic>) {
      return (ui['selector'] as String?) == 'chips';
    }
    return false;
  }

  bool _isIncludedTagField(String name, SearchFormFieldConfig field) {
    final lowerName = name.toLowerCase();
    final lowerQueryParam = (field.queryParam ?? '').toLowerCase();
    return lowerName.contains('included') ||
        lowerQueryParam.contains('includedtags');
  }

  bool _isExcludedTagField(String name, SearchFormFieldConfig field) {
    final lowerName = name.toLowerCase();
    final lowerQueryParam = (field.queryParam ?? '').toLowerCase();
    return lowerName.contains('excluded') ||
        lowerQueryParam.contains('excludedtags');
  }

  bool _shouldHideBecauseCombinedPicker(
      String name, SearchFormFieldConfig field) {
    if (!_isPickerField(name, field)) return false;
    if (!_isExcludedTagField(name, field)) return false;
    return _findPairedIncludedFieldName() != null;
  }

  String? _findPairedIncludedFieldName() {
    for (final entry in widget.config.params.entries) {
      if (_isIncludedTagField(entry.key, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  String? _findPairedExcludedFieldName() {
    for (final entry in widget.config.params.entries) {
      if (_isExcludedTagField(entry.key, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  String? _findFieldNameByQueryParam(String queryParam) {
    for (final entry in widget.config.params.entries) {
      if (entry.value.queryParam == queryParam) {
        return entry.key;
      }
    }
    return null;
  }

  IconData _pickerLeadingIcon(String name, SearchFormFieldConfig field) {
    if (_isIncludedTagField(name, field)) {
      return Icons.add_circle_outline;
    }
    if (_isExcludedTagField(name, field)) {
      return Icons.remove_circle_outline;
    }
    return Icons.local_offer_outlined;
  }

  Color _pickerAccentColor(
    String name,
    SearchFormFieldConfig field,
    BuildContext context,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isIncludedTagField(name, field)) {
      return _tagChipColors(_TagPickState.include, context).accent;
    }
    if (_isExcludedTagField(name, field)) {
      return _tagChipColors(_TagPickState.exclude, context).accent;
    }
    return colorScheme.primary;
  }

  Color _onAccentColor(Color accentColor) {
    final brightness = ThemeData.estimateBrightnessForColor(accentColor);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }

  _TagChipColors _tagChipColors(_TagPickState state, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color foreground;
    switch (state) {
      case _TagPickState.include:
        accent = isDark ? AppColors.success : AppColors.success;
        foreground = isDark ? const Color(0xFFB9F6CA) : const Color(0xFF006C45);
      case _TagPickState.exclude:
        accent = isDark ? AppColors.error : AppColors.error;
        foreground = isDark ? const Color(0xFFFFD6D6) : const Color(0xFF9F1D1D);
    }

    return _TagChipColors(
      accent: accent,
      foreground: foreground,
      background: accent.withValues(alpha: isDark ? 0.18 : 0.14),
      border: accent.withValues(alpha: isDark ? 0.78 : 0.62),
    );
  }

  _TagChipColors _pickerSelectedColors(
    String name,
    SearchFormFieldConfig field,
    BuildContext context,
  ) {
    if (_isIncludedTagField(name, field)) {
      return _tagChipColors(_TagPickState.include, context);
    }
    if (_isExcludedTagField(name, field)) {
      return _tagChipColors(_TagPickState.exclude, context);
    }

    final accent = _pickerAccentColor(name, field, context);
    return _TagChipColors(
      accent: accent,
      foreground: accent,
      background: accent.withValues(alpha: 0.16),
      border: accent.withValues(alpha: 0.62),
    );
  }

  String? _pickerDataSource(String name, SearchFormFieldConfig field) {
    final rawField = _rawFieldConfig(name);
    final ui = rawField?['ui'];
    if (ui is Map<String, dynamic>) {
      return ui['dataSource'] as String?;
    }
    return null;
  }

  Map<String, dynamic>? _rawFieldConfig(String name) {
    final rawParams = _rawSearchForm?['params'];
    if (rawParams is! Map<String, dynamic>) return null;
    final dynamic field = rawParams[name];
    if (field is Map<String, dynamic>) return field;
    return null;
  }

  String _formatFieldValue(Map<String, dynamic>? rawField, String value) {
    var result = value.trim();
    if (result.isEmpty) return result;

    final transform = (rawField?['transform'] as String? ?? '').trim();
    if (transform == 'lowercase') {
      result = result.toLowerCase();
    } else if (transform == 'uppercase') {
      result = result.toUpperCase();
    } else if (transform == 'spaceToPlus') {
      result = result.replaceAll(' ', '+');
    }

    final quoteIfContainsSpace = rawField?['quoteIfContainsSpace'] as bool?;
    if (quoteIfContainsSpace == true &&
        result.contains(' ') &&
        !result.startsWith('"') &&
        !result.endsWith('"')) {
      result = '"$result"';
    }

    final valuePrefix = (rawField?['valuePrefix'] as String? ?? '').trim();
    final valueSuffix = (rawField?['valueSuffix'] as String? ?? '').trim();
    if (valuePrefix.isNotEmpty) {
      result = '$valuePrefix$result';
    }
    if (valueSuffix.isNotEmpty) {
      result = '$result$valueSuffix';
    }

    return result;
  }

  List<String> _splitFieldInput(
    Map<String, dynamic>? rawField,
    String rawValue,
    String fieldType,
  ) {
    final value = rawValue.trim();
    if (value.isEmpty) return const <String>[];

    final multiInput = rawField?['multiInput'] as bool? ?? false;
    final shouldSplit = fieldType == 'tag' || multiInput;
    if (!shouldSplit) return <String>[value];

    return value
        .split(RegExp(r'[\n,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _setRestoredFieldValue(
    String name,
    SearchFormFieldConfig field,
    List<String> values,
  ) {
    if (values.isEmpty) return;

    switch (field.type) {
      case 'text':
      case 'tag':
        if (_isTagChipsField(name, field)) {
          final rawField = _rawFieldConfig(name);
          final parsed = <String>[];
          for (final value in values) {
            // Strip prefix/suffix so _formatFieldValue re-adds them.
            final core = _extractFieldCoreFromToken(value, rawField);
            if (core != null) {
              parsed.add(core);
            }
          }
          if (parsed.isEmpty) {
            // Fallback — split as raw tag input
            for (final value in values) {
              parsed.addAll(_splitFieldInput(rawField, value, 'tag'));
            }
          }
          _tagChipValues[name] = parsed.toSet().toList();
          _textControllers[name]?.clear();
        } else {
          _textControllers[name]?.text = values.join(', ');
        }
      case 'select':
      case 'sort':
      case 'radio':
        final options = _optionsForField(name, field, _rawFieldConfig(name));
        final match = values.firstWhere(
          (val) => options.any((opt) => opt.value == val),
          orElse: () => values.first,
        );
        _selectValues[name] = match;
      case 'checkbox':
        final options = _optionsForField(name, field, _rawFieldConfig(name));
        _multiSelectValues[name] = values
            .map((value) => options.firstWhere(
                  (option) => option.value == value,
                  orElse: () => _DynamicOption(value: value, label: value),
                ))
            .toList(growable: false);
      default:
        break;
    }
  }

  List<String> _collectTagFieldValues(
    String name,
    Map<String, dynamic>? rawField,
  ) {
    final field = widget.config.params[name];
    if (field == null || field.type != 'tag') return const <String>[];

    final values = <String>[];
    if (_isTagChipsField(name, field)) {
      values.addAll(_tagChipValues[name] ?? const <String>[]);

      final trailingInput = _textControllers[name]?.text.trim() ?? '';
      if (trailingInput.isNotEmpty) {
        values.addAll(_splitFieldInput(rawField, trailingInput, field.type));
      }

      return values;
    }

    final val = _textControllers[name]?.text.trim() ?? '';
    if (val.isNotEmpty) {
      values.addAll(_splitFieldInput(rawField, val, field.type));
    }

    return values;
  }

  List<String> _collectEncodedQueryParts({List<FilterItem>? selectedTagItems}) {
    final parts = <String>[];
    final partsByParam = <String, List<String>>{};
    final joinModeByParam = <String, String>{};

    void addParamValue(String queryParam, String value, {String? joinMode}) {
      final normalized = value.trim();
      if (normalized.isEmpty) return;
      (partsByParam[queryParam] ??= <String>[]).add(normalized);
      if (joinMode != null && joinMode.isNotEmpty) {
        joinModeByParam[queryParam] = joinMode;
      }
    }

    for (final entry in widget.config.params.entries) {
      final name = entry.key;
      final field = entry.value;
      final qp = field.queryParam;
      if (qp == null) continue;
      final rawField = _rawFieldConfig(name);
      final joinMode = (rawField?['joinMode'] as String?)?.trim();

      if (_isPickerField(name, field)) {
        final selected = _multiSelectValues[name] ?? const <_DynamicOption>[];
        for (final option in selected) {
          final formatted = _formatFieldValue(rawField, option.value);
          addParamValue(qp, formatted, joinMode: joinMode);

          if (selectedTagItems != null) {
            selectedTagItems.add(
              FilterItem(
                value: option.label,
                isExcluded: _isExcludedTagField(name, field),
              ),
            );
          }
        }
        continue;
      }

      switch (field.type) {
        case 'text':
          final val = _textControllers[name]?.text.trim() ?? '';
          if (val.isNotEmpty) {
            final splitValues = _splitFieldInput(rawField, val, field.type);
            for (final item in splitValues) {
              final formatted = _formatFieldValue(rawField, item);
              addParamValue(qp, formatted, joinMode: joinMode);
            }
          }
        case 'tag':
          final values = _collectTagFieldValues(name, rawField);
          for (final item in values) {
            final formatted = _formatFieldValue(rawField, item);
            addParamValue(qp, formatted, joinMode: joinMode);
          }
        case 'select':
        case 'sort':
        case 'radio':
          final val = _selectValues[name];
          if (val != null && val.isNotEmpty) {
            final formatted = _formatFieldValue(rawField, val);
            addParamValue(qp, formatted, joinMode: joinMode);
          }
        case 'checkbox':
          final selected = _multiSelectValues[name] ?? const <_DynamicOption>[];
          for (final option in selected) {
            final formatted = _formatFieldValue(rawField, option.value);
            addParamValue(qp, formatted, joinMode: joinMode);
          }
        default:
          break;
      }
    }

    partsByParam.forEach((queryParam, values) {
      if (values.isEmpty) return;
      final mode = (joinModeByParam[queryParam] ?? '').toLowerCase();
      if (mode == 'space') {
        final joined = values.join(' ');
        parts.add(
          '${Uri.encodeComponent(queryParam)}=${Uri.encodeComponent(joined)}',
        );
        return;
      }

      for (final value in values) {
        parts.add(
          '${Uri.encodeComponent(queryParam)}=${Uri.encodeComponent(value)}',
        );
      }
    });

    return parts;
  }

  Widget _buildQueryPreviewCard() {
    final parts = _collectEncodedQueryParts();
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    final rawQuery = 'raw:${parts.join('&')}';
    final parsed = _parseRaw(rawQuery.substring(4));
    final queryExpression = _extractPreviewQueryExpression(parsed);
    if (queryExpression.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.previewQuery,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            queryExpression,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _extractPreviewQueryExpression(Map<String, List<String>> parsed) {
    const candidateKeys = <String>['q', 's', 'query'];
    for (final key in candidateKeys) {
      final values = parsed[key];
      if (values == null || values.isEmpty) continue;
      final expression = values.join(' ').trim();
      if (expression.isNotEmpty) {
        return expression;
      }
    }

    for (final entry in parsed.entries) {
      if (entry.key == 'page' || entry.key == 'sort') continue;
      final expression = entry.value.join(' ').trim();
      if (expression.isNotEmpty) {
        return expression;
      }
    }

    return '';
  }

  void _restoreJoinedParamGroup(
    String queryParam,
    String joinedValue,
    List<MapEntry<String, SearchFormFieldConfig>> fields,
  ) {
    final tokens = _tokenizeQueryExpression(joinedValue);
    final consumed = List<bool>.filled(tokens.length, false);

    for (final entry in fields) {
      final name = entry.key;
      final field = entry.value;
      final rawField = _rawFieldConfig(name);

      if (_isPickerField(name, field)) continue;

      final hasAffix =
          ((rawField?['valuePrefix'] as String?)?.isNotEmpty ?? false) ||
              ((rawField?['valueSuffix'] as String?)?.isNotEmpty ?? false);
      if (!hasAffix) continue;

      final matched = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        if (consumed[i]) continue;
        final extracted = _extractFieldCoreFromToken(tokens[i], rawField);
        if (extracted == null) continue;
        matched.add(extracted);
        consumed[i] = true;
      }

      if (matched.isNotEmpty) {
        _setRestoredFieldValue(name, field, matched);
      }
    }

    final leftovers = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (!consumed[i]) leftovers.add(tokens[i]);
    }

    if (leftovers.isEmpty) return;

    MapEntry<String, SearchFormFieldConfig>? fallback;
    for (final entry in fields) {
      final name = entry.key;
      final field = entry.value;
      final rawField = _rawFieldConfig(name);
      if (_isPickerField(name, field)) continue;
      if (field.type != 'text' && field.type != 'tag') continue;

      final hasAffix =
          ((rawField?['valuePrefix'] as String?)?.isNotEmpty ?? false) ||
              ((rawField?['valueSuffix'] as String?)?.isNotEmpty ?? false);
      if (!hasAffix) {
        if (name == 'query') {
          fallback = entry;
          break;
        }
        fallback ??= entry;
      }
    }

    if (fallback != null) {
      _setRestoredFieldValue(
        fallback.key,
        fallback.value,
        <String>[leftovers.join(' ')],
      );
    }
  }

  List<String> _tokenizeQueryExpression(String expression) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (final rune in expression.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '"') {
        inQuotes = !inQuotes;
        buffer.write(ch);
        continue;
      }

      if (!inQuotes && ch.trim().isEmpty) {
        final token = buffer.toString().trim();
        if (token.isNotEmpty) tokens.add(token);
        buffer.clear();
        continue;
      }

      buffer.write(ch);
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) tokens.add(last);

    return tokens;
  }

  String? _extractFieldCoreFromToken(
    String token,
    Map<String, dynamic>? rawField,
  ) {
    var current = token.trim();
    if (current.isEmpty) return null;

    final prefix = (rawField?['valuePrefix'] as String? ?? '').trim();
    final suffix = (rawField?['valueSuffix'] as String? ?? '').trim();

    if (prefix.isNotEmpty) {
      if (!current.startsWith(prefix)) return null;
      current = current.substring(prefix.length);
    }

    if (suffix.isNotEmpty) {
      if (!current.endsWith(suffix)) return null;
      current = current.substring(0, current.length - suffix.length);
    }

    if (current.length >= 2 &&
        current.startsWith('"') &&
        current.endsWith('"')) {
      current = current.substring(1, current.length - 1);
    }

    return current.trim().isEmpty ? null : current.trim();
  }

  dynamic _extractByPath(dynamic node, String path) {
    if (path.isEmpty) return node;
    dynamic current = node;
    for (final seg in path.split('.')) {
      if (current is Map<String, dynamic>) {
        current = current[seg];
      } else if (current is Map) {
        current = current[seg];
      } else {
        return null;
      }
    }
    return current;
  }

  Widget _buildSelectField(String name, SearchFormFieldConfig field) {
    final colorScheme = Theme.of(context).colorScheme;
    final rawField = _rawFieldConfig(name);
    final options = _optionsForField(name, field, rawField);
    final selected = _selectValues[name];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name).toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            // "All" chip = clear selection
            _buildSelectChip(
              colorScheme: colorScheme,
              label: AppLocalizations.of(context)!.all,
              isSelected: selected == null,
              onSelected: (_) => setState(() => _selectValues[name] = null),
            ),
            for (final opt in options)
              _buildSelectChip(
                colorScheme: colorScheme,
                label: opt.label,
                isSelected: selected == opt.value,
                onSelected: (v) =>
                    setState(() => _selectValues[name] = v ? opt.value : null),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectChip({
    required ColorScheme colorScheme,
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: true,
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      checkmarkColor: colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color:
            isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.45)
            : colorScheme.outline.withValues(alpha: 0.25),
      ),
      onSelected: onSelected,
    );
  }

  Widget _buildCheckboxField(String name, SearchFormFieldConfig field) {
    final colorScheme = Theme.of(context).colorScheme;
    final rawField = _rawFieldConfig(name);
    final options = _optionsForField(name, field, rawField);
    final selected = _multiSelectValues[name] ?? const <_DynamicOption>[];
    final selectedValues = selected.map((option) => option.value).toSet();
    final isDynamic = _isDynamicCheckboxField(name, field);
    final isLoading = _loadingCheckboxFields.contains(name);
    final loadError = _checkboxLoadErrorByField[name];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name).toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        if (options.isEmpty && isDynamic) ...[
          _buildCheckboxRemoteStateCard(
            fieldName: name,
            isLoading: isLoading,
            loadError: loadError,
            colorScheme: colorScheme,
          ),
        ] else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in options)
                _buildCheckboxChip(
                  colorScheme: colorScheme,
                  option: option,
                  isSelected: selectedValues.contains(option.value),
                  onSelected: (enabled) {
                    setState(() {
                      final next = <_DynamicOption>[...selected];
                      if (enabled) {
                        next.add(option);
                      } else {
                        next.removeWhere((item) => item.value == option.value);
                      }
                      _multiSelectValues[name] = next;
                    });
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCheckboxChip({
    required ColorScheme colorScheme,
    required _DynamicOption option,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(option.label),
      selected: isSelected,
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      checkmarkColor: colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color:
            isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.45)
            : colorScheme.outline.withValues(alpha: 0.25),
      ),
      onSelected: onSelected,
    );
  }

  List<_DynamicOption> _optionsForField(
    String name,
    SearchFormFieldConfig field,
    Map<String, dynamic>? rawField,
  ) {
    if (_isDynamicCheckboxField(name, field)) {
      return _checkboxOptionCache[name] ?? const <_DynamicOption>[];
    }

    final rawOptions = rawField?['options'];
    if (rawOptions is List) {
      return rawOptions
          .map<_DynamicOption?>((dynamic option) {
            if (option is Map<String, dynamic>) {
              final value = option['value']?.toString() ?? '';
              if (value.isEmpty) return null;
              return _DynamicOption(
                value: value,
                label: option['name']?.toString() ??
                    option['label']?.toString() ??
                    value,
              );
            }
            final value = option?.toString() ?? '';
            if (value.isEmpty) return null;
            return _DynamicOption(value: value, label: _capitalize(value));
          })
          .whereType<_DynamicOption>()
          .toList(growable: false);
    }

    return (field.options ?? const <SearchFormOptionConfig>[])
        .map((opt) => _DynamicOption(
              value: opt.value,
              label: opt.name ?? opt.label ?? _capitalize(opt.value),
            ))
        .toList(growable: false);
  }

  List<_DynamicOption> _optionsForStaticField(Map<String, dynamic>? rawField) {
    final rawOptions = rawField?['options'];
    if (rawOptions is List) {
      return rawOptions
          .map<_DynamicOption?>((dynamic option) {
            if (option is Map<String, dynamic>) {
              final value = option['value']?.toString() ?? '';
              if (value.isEmpty) return null;
              return _DynamicOption(
                value: value,
                label: option['name']?.toString() ??
                    option['label']?.toString() ??
                    value,
              );
            }
            final value = option?.toString() ?? '';
            if (value.isEmpty) return null;
            return _DynamicOption(value: value, label: _capitalize(value));
          })
          .whereType<_DynamicOption>()
          .toList(growable: false);
    }
    return const <_DynamicOption>[];
  }

  bool _isDynamicCheckboxField(String name, SearchFormFieldConfig field) {
    if (field.type != 'checkbox') return false;
    final rawField = _rawFieldConfig(name);
    if (rawField == null) return false;
    final tagSourceUrl = rawField['tagSourceUrl'] as String?;
    final loadFromTags = rawField['loadFromTags'] as bool? ?? false;
    final tagType = rawField['tagType']?.toString();
    return (tagSourceUrl != null && tagSourceUrl.isNotEmpty) ||
        loadFromTags ||
        (tagType != null && tagType.isNotEmpty);
  }

  Widget _buildCheckboxRemoteStateCard({
    required String fieldName,
    required bool isLoading,
    required String? loadError,
    required ColorScheme colorScheme,
  }) {
    final sourceUrl = _rawFieldConfig(fieldName)?['tagSourceUrl']?.toString();
    final sourceHost = sourceUrl == null || sourceUrl.isEmpty
        ? null
        : Uri.tryParse(sourceUrl)?.host;
    final theme = Theme.of(context);
    final isError = loadError != null;
    final isIdle = !isLoading && !isError;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey<String>(
          'checkbox-remote-state-$fieldName-${isLoading ? 'loading' : isError ? 'error' : 'idle'}',
        ),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: isError
                ? colorScheme.error.withValues(alpha: 0.38)
                : colorScheme.outlineVariant.withValues(alpha: 0.50),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isError
                        ? colorScheme.errorContainer
                        : colorScheme.primaryContainer.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                  child: Icon(
                    isError
                        ? Icons.warning_amber_rounded
                        : Icons.cloud_download_outlined,
                    color: isError
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isError
                                  ? AppLocalizations.of(context)!
                                      .genreOptionsFailed
                                  : AppLocalizations.of(context)!
                                      .loadingGenreOptions,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildRemoteStateBadge(
                            colorScheme: colorScheme,
                            label: isLoading
                                ? AppLocalizations.of(context)!.statusLoading
                                : isError
                                    ? AppLocalizations.of(context)!.statusError
                                    : AppLocalizations.of(context)!.statusIdle,
                            filled: isLoading || isIdle,
                            isError: isError,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sourceHost == null
                            ? (isError
                                ? AppLocalizations.of(context)!
                                    .failedToLoadOptionsTap
                                : AppLocalizations.of(context)!.loadingOptions)
                            : isError
                                ? 'Could not read tags from $sourceHost'
                                : 'Fetching tags from $sourceHost',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (sourceUrl != null && sourceUrl.isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spaceSm),
                        Text(
                          sourceUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (isLoading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                'Loading remote genres from GitHub raw. This can take a moment.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  10,
                  (index) => _buildSkeletonChip(colorScheme, index),
                ),
              ),
            ] else if (isError) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  loadError,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildGhostChip(
                    label: AppLocalizations.of(context)!.remoteSource,
                    colorScheme: colorScheme,
                    emphasized: true,
                  ),
                  _buildGhostChip(
                    label: AppLocalizations.of(context)!.retryFetch,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ] else ...[
              Text(
                'No remote genre list is loaded yet. Reload to sync from source.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildGhostChip(
                    label: AppLocalizations.of(context)!.statusIdle,
                    colorScheme: colorScheme,
                    emphasized: true,
                  ),
                  _buildGhostChip(
                    label: AppLocalizations.of(context)!.gitHubRaw,
                    colorScheme: colorScheme,
                  ),
                  _buildGhostChip(
                    label: AppLocalizations.of(context)!.liveTags,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _loadCheckboxOptionsForField(
                              fieldName,
                              force: true,
                            ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      isError
                          ? AppLocalizations.of(context)!.retryAction
                          : AppLocalizations.of(context)!.reloadSearchUI,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteStateBadge({
    required ColorScheme colorScheme,
    required String label,
    required bool filled,
    required bool isError,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer.withValues(alpha: 0.7)
            : filled
                ? colorScheme.primaryContainer.withValues(alpha: 0.75)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(
          color: isError
              ? colorScheme.error.withValues(alpha: 0.30)
              : filled
                  ? colorScheme.primary.withValues(alpha: 0.28)
                  : colorScheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isError
                  ? colorScheme.onErrorContainer
                  : filled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildSkeletonChip(ColorScheme colorScheme, int index) {
    final widths = <double>[72, 96, 60, 84, 68, 104, 88, 76];
    return Container(
      width: widths[index % widths.length],
      height: 34,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _buildGhostChip({
    required String label,
    required ColorScheme colorScheme,
    bool emphasized = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized
            ? colorScheme.primaryContainer.withValues(alpha: 0.7)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(
          color: emphasized
              ? colorScheme.primary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: emphasized
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  String _labelFor(String name) => switch (name) {
        _ when _rawFieldConfig(name)?['label'] is String =>
          (_rawFieldConfig(name)?['label'] as String).trim().isEmpty
              ? _capitalize(name)
              : (_rawFieldConfig(name)?['label'] as String),
        'query' => AppLocalizations.of(context)!.searchLabel,
        'genre' => AppLocalizations.of(context)!.genreLabel,
        'status' => AppLocalizations.of(context)!.statusLabel,
        'order' => AppLocalizations.of(context)!.orderBy,
        'author' => AppLocalizations.of(context)!.authorLabel,
        'artist' => AppLocalizations.of(context)!.artistFilterLabel,
        _ => _capitalize(name),
      };

  Icon _iconFor(String name) => switch (name) {
        'query' => const Icon(Icons.search),
        'genre' => const Icon(Icons.category),
        'author' => const Icon(Icons.person),
        'artist' => const Icon(Icons.brush),
        _ => const Icon(Icons.edit),
      };

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _DynamicOption {
  const _DynamicOption({
    required this.value,
    required this.label,
    this.group,
  });

  final String value;
  final String label;
  final String? group;
}

class _TagChipColors {
  const _TagChipColors({
    required this.accent,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color accent;
  final Color foreground;
  final Color background;
  final Color border;
}

enum _TagPickState {
  include,
  exclude,
}

class _CombinedPickerResult {
  const _CombinedPickerResult({
    required this.included,
    required this.excluded,
  });

  final List<_DynamicOption> included;
  final List<_DynamicOption> excluded;
}
