import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_generic/kuron_generic.dart'
    show DynamicSearchFormContract;
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/domain/entities/search/dynamic_option.dart';
import 'package:nhasixapp/domain/entities/search_filter.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/search/search_bloc.dart';
import 'package:nhasixapp/presentation/cubits/dynamic_form_search/dynamic_form_search_cubit.dart';
import 'package:nhasixapp/presentation/pages/search/dynamic_form_search/dynamic_form_filter_parser.dart';
import 'package:nhasixapp/presentation/pages/search/dynamic_form_search/dynamic_form_multi_select_picker.dart';

export 'package:nhasixapp/data/datasources/remote/search/dynamic_form_remote_option_datasource.dart'
    show decodeDataSourcePayload;
export 'package:nhasixapp/domain/entities/search/dynamic_option.dart';
export 'package:nhasixapp/presentation/cubits/dynamic_form_search/dynamic_form_search_cubit.dart';

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

class DynamicFormSearchUI extends StatefulWidget {
  final SearchFormConfig config;
  final String sourceId;
  final DynamicSearchFormContract? canonicalContract;
  final int reloadSignal;
  final DynamicFormSearchCubit? cubit;
  final DynamicFormSearchCubit Function()? cubitFactory;
  final Logger? logger;

  const DynamicFormSearchUI({
    super.key,
    required this.config,
    required this.sourceId,
    this.canonicalContract,
    this.reloadSignal = 0,
    this.cubit,
    this.cubitFactory,
    this.logger,
  });

  /// A field participates in the built query only when it declares a
  /// non-empty `queryParam`. Empty params would emit garbage `=value` pairs
  /// the server ignores (ext-config-audit-fixes 1.1).
  @visibleForTesting
  static bool emitsQueryParam(String? queryParam) =>
      queryParam != null && queryParam.trim().isNotEmpty;

  @override
  State<DynamicFormSearchUI> createState() => _DynamicFormSearchUIState();
}

class _DynamicFormSearchUIState extends State<DynamicFormSearchUI> {
  final _formKey = GlobalKey<FormState>();
  late final Logger _logger = widget.logger ?? Logger();

  // Keyed by field logical name (e.g. "query", "status", "order", "genre")
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String?> _selectValues = {};
  final Map<String, List<DynamicOption>> _multiSelectValues = {};
  final Map<String, List<String>> _tagChipValues = {};
  final Map<String, List<String>> _pendingMultiRestore = {};
  int _lastReloadSignal = 0;

  bool _showAdvancedFilters = false;
  DynamicFormSearchCubit? _cubit;
  bool _ownsCubit = false;
  bool _initializedCubit = false;

  DynamicFormSearchCubit _resolveCubit() {
    if (widget.cubit != null) return widget.cubit!;
    if (widget.cubitFactory != null) {
      if (_cubit == null) {
        _cubit = widget.cubitFactory!();
        _ownsCubit = true;
      }
      return _cubit!;
    }
    if (_cubit != null) return _cubit!;
    try {
      return context.read<DynamicFormSearchCubit>();
    } catch (_) {
      _cubit = DynamicFormSearchCubit.createDefault();
      _ownsCubit = true;
      return _cubit!;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastReloadSignal = widget.reloadSignal;
    _initFields();
    context.read<SearchBloc>().add(
      SearchInitializeEvent(sourceId: widget.sourceId),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedCubit) {
      _initializedCubit = true;
      _resolveCubit().initialize(
        sourceId: widget.sourceId,
        config: widget.config,
        canonicalContract: widget.canonicalContract,
      );
    }
  }

  @override
  void didUpdateWidget(covariant DynamicFormSearchUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadSignal != oldWidget.reloadSignal &&
        widget.reloadSignal != _lastReloadSignal) {
      _lastReloadSignal = widget.reloadSignal;
      _resolveCubit().reloadDynamicOptions(
        sourceId: widget.sourceId,
        config: widget.config,
        canonicalContract: widget.canonicalContract,
      );
    }
  }

  void _initFields() {
    for (final entry in widget.config.params.entries) {
      final field = entry.value;
      if (field.type == 'tag') {
        _multiSelectValues[entry.key] = [];
        _textControllers[entry.key] = TextEditingController();
        _tagChipValues[entry.key] = <String>[];
        continue;
      }

      switch (field.type) {
        case 'text':
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

  void _restoreSaved(SearchFilter saved, DynamicFormSearchState cubitState) {
    try {
      final query = saved.query;
      if (query == null || !query.startsWith('raw:')) return;

      final parsed = parseRaw(query.substring(4));

      final fieldsByParam =
          <String, List<MapEntry<String, SearchFormFieldConfig>>>{};
      for (final entry in widget.config.params.entries) {
        final qp = entry.value.queryParam;
        if (qp == null) continue;
        (fieldsByParam[qp] ??= <MapEntry<String, SearchFormFieldConfig>>[]).add(
          entry,
        );
      }

      for (final grouped in fieldsByParam.entries) {
        final queryParam = grouped.key;
        final fields = grouped.value;
        final values = parsed[queryParam] ?? const <String>[];
        if (values.isEmpty) continue;

        final hasSpaceJoin = fields.any((entry) {
          final raw = cubitState.rawFieldConfig(entry.key);
          return ((raw?['joinMode'] as String?)?.trim().toLowerCase() ?? '') ==
              'space';
        });

        if (fields.length > 1 && hasSpaceJoin) {
          restoreJoinedParamGroup(
            queryParam: queryParam,
            joinedValue: values.first,
            fields: fields,
            rawFieldConfig: (name) => cubitState.rawFieldConfig(name),
            setRestoredFieldValue: (name, field, vals) =>
                _setRestoredFieldValue(name, field, vals, cubitState),
          );
          continue;
        }

        for (final entry in fields) {
          final field = entry.value;
          final rawField = cubitState.rawFieldConfig(entry.key);
          final prefix = (rawField?['valuePrefix'] as String? ?? '').trim();

          if (isPickerField(entry.key, field, rawField)) {
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

          if (prefix.isNotEmpty && values.any((v) => v.startsWith(prefix))) {
            _setRestoredFieldValue(entry.key, field, values, cubitState);
          } else if (prefix.isEmpty) {
            _setRestoredFieldValue(entry.key, field, values, cubitState);
          }
        }
      }

      if (mounted) {
        setState(() {});
      }

      _applyPendingMultiRestore(cubitState);
    } catch (e) {
      _logger.w('DynamicFormSearchUI: failed to restore filter: $e');
    }
  }

  void _applyPendingMultiRestore(DynamicFormSearchState cubitState) {
    if (_pendingMultiRestore.isEmpty) return;

    for (final entry in _pendingMultiRestore.entries) {
      final fieldName = entry.key;
      final field = widget.config.params[fieldName];
      if (field == null) continue;
      final sourceId = cubitState.pickerDataSource(fieldName, field);
      if (sourceId == null) continue;

      final options =
          cubitState.optionCacheBySource[sourceId] ?? const <DynamicOption>[];
      final selected = entry.value
          .map(
            (value) => options.firstWhere(
              (o) => o.value == value,
              orElse: () => DynamicOption(value: value, label: value),
            ),
          )
          .toList();
      _multiSelectValues[fieldName] = selected;
    }

    _pendingMultiRestore.clear();
    if (mounted) setState(() {});
  }

  void _setRestoredFieldValue(
    String name,
    SearchFormFieldConfig field,
    List<String> values,
    DynamicFormSearchState cubitState,
  ) {
    if (values.isEmpty) return;
    final rawField = cubitState.rawFieldConfig(name);

    switch (field.type) {
      case 'text':
      case 'tag':
        if (isTagChipsField(name, field, rawField)) {
          final parsed = <String>[];
          for (final value in values) {
            final core = extractFieldCoreFromToken(value, rawField);
            if (core != null) {
              parsed.add(core);
            }
          }
          if (parsed.isEmpty) {
            for (final value in values) {
              parsed.addAll(splitFieldInput(rawField, value, 'tag'));
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
        final options = _optionsForField(name, field, cubitState);
        final match = values.firstWhere(
          (val) => options.any((opt) => opt.value == val),
          orElse: () => values.first,
        );
        _selectValues[name] = match;
      case 'checkbox':
        final options = _optionsForField(name, field, cubitState);
        _multiSelectValues[name] = values
            .map(
              (value) => options.firstWhere(
                (option) => option.value == value,
                orElse: () => DynamicOption(value: value, label: value),
              ),
            )
            .toList(growable: false);
      default:
        break;
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    if (_ownsCubit) {
      _cubit?.close();
    }
    super.dispose();
  }

  Future<void> _onSearch(
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    final queryValue = _textControllers['query']?.text.trim() ?? '';
    if (queryValue.isNotEmpty && RegExp(r'^\d+$').hasMatch(queryValue)) {
      if (!mounted) return;
      context.push('/content/${Uri.encodeComponent(queryValue)}');
      return;
    }

    final selectedTagItems = <FilterItem>[];
    final parts = _collectEncodedQueryParts(
      cubitState,
      selectedTagItems: selectedTagItems,
    );
    final rawQuery = parts.isNotEmpty ? 'raw:${parts.join('&')}' : '';
    final filter = SearchFilter(query: rawQuery, tags: selectedTagItems);

    final ok = await cubit.saveSearchFilter(
      sourceId: widget.sourceId,
      filter: filter,
    );
    if (!ok) {
      if (mounted) {
        final err = cubit.state.saveFilterError ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.failedToApplySearch(err),
            ),
          ),
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

  Future<void> _onReset(DynamicFormSearchCubit cubit) async {
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
    await cubit.clearSearchFilter(sourceId: widget.sourceId);
    if (mounted && context.canPop()) {
      context.pop(true);
    }
  }

  bool _isAdvancedField(String name, SearchFormFieldConfig field) {
    if (field.type == 'sort') return false;
    final lowerName = name.toLowerCase();
    if (lowerName == 'query' || lowerName == 'search') return false;
    return true;
  }

  int _countActiveAdvancedFilters(DynamicFormSearchState cubitState) {
    var count = 0;
    for (final entry in widget.config.params.entries) {
      final name = entry.key;
      final field = entry.value;
      if (!_isAdvancedField(name, field)) continue;
      if (field.type == 'page') continue;
      if (shouldHideBecauseCombinedPicker(
        name: name,
        field: field,
        config: widget.config,
        rawFieldConfig: (n) => cubitState.rawFieldConfig(n),
      )) {
        continue;
      }

      final rawField = cubitState.rawFieldConfig(name);
      if (field.type == 'select' || field.type == 'radio') {
        if (_selectValues[name] != null) count++;
      } else if (isPickerField(name, field, rawField)) {
        if ((_multiSelectValues[name] ?? const <DynamicOption>[]).isNotEmpty) {
          count++;
        }
      } else if (isTagChipsField(name, field, rawField)) {
        if ((_tagChipValues[name] ?? const <String>[]).isNotEmpty ||
            (_textControllers[name]?.text.trim().isNotEmpty ?? false)) {
          count++;
        }
      } else if (field.type == 'text' || field.type == 'tag') {
        if (_textControllers[name]?.text.trim().isNotEmpty ?? false) count++;
      } else if (field.type == 'checkbox') {
        if ((_multiSelectValues[name] ?? const <DynamicOption>[]).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _resolveCubit();

    return BlocProvider.value(
      value: cubit,
      child: BlocConsumer<DynamicFormSearchCubit, DynamicFormSearchState>(
        bloc: cubit,
        listenWhen: (prev, curr) {
          return (prev.savedFilter != curr.savedFilter &&
                  curr.savedFilter != null) ||
              (prev.optionCacheBySource != curr.optionCacheBySource &&
                  _pendingMultiRestore.isNotEmpty);
        },
        listener: (context, state) {
          if (state.savedFilter != null) {
            _restoreSaved(state.savedFilter!, state);
          } else if (_pendingMultiRestore.isNotEmpty) {
            _applyPendingMultiRestore(state);
          }
        },
        builder: (context, state) {
          final allFields = widget.config.params.entries
              .where(
                (e) =>
                    e.value.type != 'page' &&
                    !shouldHideBecauseCombinedPicker(
                      name: e.key,
                      field: e.value,
                      config: widget.config,
                      rawFieldConfig: (n) => state.rawFieldConfig(n),
                    ),
              )
              .toList();

          final primaryFields = allFields
              .where((e) => !_isAdvancedField(e.key, e.value))
              .toList();

          final advancedFields = allFields
              .where((e) => _isAdvancedField(e.key, e.value))
              .toList();

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
                          _buildField(entry.key, entry.value, cubit, state),
                        if (hasAdvanced) ...[
                          const SizedBox(height: DesignTokens.spaceSm),
                          _buildAdvancedToggle(state),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (final entry in advancedFields)
                                          _buildField(
                                            entry.key,
                                            entry.value,
                                            cubit,
                                            state,
                                          ),
                                      ],
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('advanced_closed'),
                                    ),
                            ),
                          ),
                        _buildQueryPreviewCard(state),
                        const SizedBox(height: DesignTokens.spaceXl),
                        FilledButton.icon(
                          onPressed: () => _onSearch(cubit, state),
                          icon: const Icon(Icons.search),
                          label: Text(AppLocalizations.of(context)!.search),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spaceSm),
                        OutlinedButton(
                          onPressed: () => _onReset(cubit),
                          child: Text(AppLocalizations.of(context)!.reset),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdvancedToggle(DynamicFormSearchState cubitState) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = _countActiveAdvancedFilters(cubitState);

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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: _showAdvancedFilters
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _showAdvancedFilters
                      ? colorScheme.onPrimary.withValues(alpha: 0.22)
                      : colorScheme.primary,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                ),
                child: Text(
                  '$activeCount',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _showAdvancedFilters
                        ? colorScheme.onPrimary
                        : colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const Spacer(),
            AnimatedRotation(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              turns: _showAdvancedFilters ? 0.5 : 0.0,
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

  Widget _buildField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) {
    final rawField = cubitState.rawFieldConfig(name);
    final pairedExcludedName = _findPairedExcludedFieldName();
    final isPairedIncluded =
        isIncludedTagField(name, field) &&
        isPickerField(name, field, rawField) &&
        pairedExcludedName != null &&
        widget.config.params[pairedExcludedName] != null &&
        isPickerField(
          pairedExcludedName,
          widget.config.params[pairedExcludedName]!,
          cubitState.rawFieldConfig(pairedExcludedName),
        );

    if (isPairedIncluded) {
      final excludedField = widget.config.params[pairedExcludedName]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
        child: _buildCombinedPickerField(
          includedName: name,
          includedField: field,
          excludedName: pairedExcludedName,
          excludedField: excludedField,
          cubit: cubit,
          cubitState: cubitState,
        ),
      );
    }

    if (isPickerField(name, field, rawField)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
        child: _buildPickerField(name, field, cubit, cubitState),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
      child: switch (field.type) {
        'text' => _buildTextField(name, field, cubit, cubitState),
        'tag' =>
          isTagChipsField(name, field, rawField)
              ? _buildTagChipsField(name, field, cubitState)
              : _buildTagField(name, field, cubit, cubitState),
        'select' => _buildSelectField(name, field, cubitState),
        'sort' => _buildSelectField(name, field, cubitState),
        'radio' => _buildSelectField(name, field, cubitState),
        'checkbox' => _buildCheckboxField(name, field, cubit, cubitState),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildTextField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) {
    return TextFormField(
      controller: _textControllers[name],
      decoration: InputDecoration(
        labelText: _labelFor(name, cubitState),
        hintText: field.placeholder,
        prefixIcon: _iconFor(name),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        filled: true,
      ),
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => _onSearch(cubit, cubitState),
    );
  }

  Widget _buildTagField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) {
    return TextFormField(
      controller: _textControllers[name],
      decoration: InputDecoration(
        labelText: _labelFor(name, cubitState),
        hintText:
            field.placeholder ??
            'Enter ${_labelFor(name, cubitState).toLowerCase()}',
        prefixIcon: const Icon(Icons.tag),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        filled: true,
      ),
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => _onSearch(cubit, cubitState),
    );
  }

  Widget _buildTagChipsField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchState cubitState,
  ) {
    final chips = _tagChipValues[name] ?? const <String>[];
    final controller = _textControllers[name];
    final accent = isExcludedTagField(name, field)
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;

    void addCurrentInput() {
      final value = controller?.text.trim() ?? '';
      if (value.isEmpty) return;
      final split = splitFieldInput(
        cubitState.rawFieldConfig(name),
        value,
        field.type,
      );
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
            labelText: _labelFor(name, cubitState),
            hintText: field.placeholder ?? 'Add tag and press +',
            prefixIcon: const Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              tooltip: AppLocalizations.of(context)!.addTag,
              onPressed: addCurrentInput,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
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
            color: Theme.of(context).colorScheme.onSurfaceVariant
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
                        _tagChipValues[name] = chips
                            .where((x) => x != chip)
                            .toList();
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

  Widget _buildPickerField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) {
    final selected = _multiSelectValues[name] ?? const <DynamicOption>[];
    final sourceId = cubitState.pickerDataSource(name, field);
    final pickerColors = pickerSelectedColors(name, field, context);
    final accentColor = pickerColors.accent;
    final baseIcon = pickerLeadingIcon(name, field);
    final isLoading =
        sourceId != null && cubitState.loadingPickerSources.contains(sourceId);
    final hasLoadError =
        sourceId != null &&
        cubitState.pickerLoadErrorBySource.containsKey(sourceId);
    final hasCachedOptions =
        sourceId != null &&
        (cubitState.optionCacheBySource[sourceId]?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name, cubitState).toUpperCase(),
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
            onTap: () => _openPicker(name, field, cubit, cubitState),
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
                    baseIcon,
                    color: selected.isNotEmpty
                        ? accentColor
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected.isEmpty
                          ? (field.placeholder ??
                                'Select ${_labelFor(name, cubitState)}')
                          : '${selected.length} selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected.isEmpty
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                        fontWeight: selected.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (hasLoadError)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: Theme.of(context).colorScheme.error,
                      tooltip: AppLocalizations.of(context)!.retryAction,
                      onPressed: () {
                        cubit.loadPickerOptionsForSource(
                          sourceId: widget.sourceId,
                          dataSourceId: sourceId,
                          force: true,
                        );
                      },
                    )
                  else if (!hasCachedOptions)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      color: Theme.of(context).colorScheme.primary,
                      tooltip: AppLocalizations.of(context)!.tapToLoadOptions,
                      onPressed: () {
                        if (sourceId != null) {
                          cubit.loadPickerOptionsForSource(
                            sourceId: widget.sourceId,
                            dataSourceId: sourceId,
                            force: true,
                          );
                        }
                      },
                    )
                  else
                    const Icon(Icons.arrow_drop_down),
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
                  (opt) => FilterChip(
                    label: Text(opt.label),
                    selected: true,
                    showCheckmark: false,
                    backgroundColor: pickerColors.background,
                    selectedColor: pickerColors.background,
                    side: BorderSide(color: pickerColors.border),
                    labelStyle: TextStyle(
                      color: pickerColors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _multiSelectValues[name] = selected
                            .where((o) => o.value != opt.value)
                            .toList();
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
    required DynamicFormSearchCubit cubit,
    required DynamicFormSearchState cubitState,
  }) {
    final included =
        _multiSelectValues[includedName] ?? const <DynamicOption>[];
    final excluded =
        _multiSelectValues[excludedName] ?? const <DynamicOption>[];

    final sourceId =
        cubitState.pickerDataSource(includedName, includedField) ??
        cubitState.pickerDataSource(excludedName, excludedField);
    final isLoading =
        sourceId != null && cubitState.loadingPickerSources.contains(sourceId);
    final hasLoadError =
        sourceId != null &&
        cubitState.pickerLoadErrorBySource.containsKey(sourceId);
    final hasCachedOptions =
        sourceId != null &&
        (cubitState.optionCacheBySource[sourceId]?.isNotEmpty ?? false);

    final includeColors = tagChipColors(TagPickState.include, context);
    final excludeColors = tagChipColors(TagPickState.exclude, context);

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
              cubit: cubit,
              cubitState: cubitState,
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
                    Icons.label_outlined,
                    color: (included.isNotEmpty || excluded.isNotEmpty)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: (included.isEmpty && excluded.isEmpty)
                        ? Text(
                            AppLocalizations.of(context)!.tapToChooseTags,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          )
                        : Row(
                            children: [
                              if (included.isNotEmpty) ...[
                                Icon(
                                  Icons.add_circle,
                                  size: 14,
                                  color: includeColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${included.length}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: includeColors.accent,
                                  ),
                                ),
                              ],
                              if (included.isNotEmpty && excluded.isNotEmpty)
                                const SizedBox(width: 12),
                              if (excluded.isNotEmpty) ...[
                                Icon(
                                  Icons.remove_circle,
                                  size: 14,
                                  color: excludeColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${excluded.length}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: excludeColors.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (hasLoadError)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: Theme.of(context).colorScheme.error,
                      tooltip: AppLocalizations.of(context)!.retryAction,
                      onPressed: () {
                        cubit.loadPickerOptionsForSource(
                          sourceId: widget.sourceId,
                          dataSourceId: sourceId,
                          force: true,
                        );
                      },
                    )
                  else if (!hasCachedOptions)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      color: Theme.of(context).colorScheme.primary,
                      tooltip: AppLocalizations.of(context)!.tapToLoadOptions,
                      onPressed: () {
                        if (sourceId != null) {
                          cubit.loadPickerOptionsForSource(
                            sourceId: widget.sourceId,
                            dataSourceId: sourceId,
                            force: true,
                          );
                        }
                      },
                    )
                  else
                    const Icon(Icons.arrow_drop_down),
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
                (opt) => FilterChip(
                  label: Text(opt.label),
                  selected: true,
                  showCheckmark: false,
                  avatar: Icon(
                    Icons.add,
                    size: 14,
                    color: includeColors.accent,
                  ),
                  backgroundColor: includeColors.background,
                  selectedColor: includeColors.background,
                  side: BorderSide(color: includeColors.border),
                  labelStyle: TextStyle(
                    color: includeColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _multiSelectValues[includedName] = included
                          .where((o) => o.value != opt.value)
                          .toList();
                    });
                  },
                ),
              ),
              ...excluded.map(
                (opt) => FilterChip(
                  label: Text(opt.label),
                  selected: true,
                  showCheckmark: false,
                  avatar: Icon(
                    Icons.remove,
                    size: 14,
                    color: excludeColors.accent,
                  ),
                  backgroundColor: excludeColors.background,
                  selectedColor: excludeColors.background,
                  side: BorderSide(color: excludeColors.border),
                  labelStyle: TextStyle(
                    color: excludeColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _multiSelectValues[excludedName] = excluded
                          .where((o) => o.value != opt.value)
                          .toList();
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
    required DynamicFormSearchCubit cubit,
    required DynamicFormSearchState cubitState,
  }) async {
    final sourceId =
        cubitState.pickerDataSource(includedName, includedField) ??
        cubitState.pickerDataSource(excludedName, excludedField);
    if (sourceId == null) return;

    if (cubitState.loadingPickerSources.contains(sourceId)) return;

    final hasOptions =
        cubitState.optionCacheBySource[sourceId]?.isNotEmpty ?? false;
    if (!hasOptions) {
      await cubit.loadPickerOptionsForSource(
        sourceId: widget.sourceId,
        dataSourceId: sourceId,
        force: true,
      );
    }

    final options = List<DynamicOption>.from(
      cubit.state.optionCacheBySource[sourceId] ?? const <DynamicOption>[],
    );

    if (options.isEmpty) {
      if (!mounted) return;
      final loadError = cubit.state.pickerLoadErrorBySource[sourceId];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loadError == null || loadError.isEmpty
                ? AppLocalizations.of(context)!.noOptionsAvailable
                : AppLocalizations.of(context)!.failedLoadingOptions,
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.retryAction,
            onPressed: () => _openCombinedPicker(
              includedName: includedName,
              includedField: includedField,
              excludedName: excludedName,
              excludedField: excludedField,
              cubit: cubit,
              cubitState: cubit.state,
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final result = await showDynamicFormCombinedPicker(
      context: context,
      options: options,
      initialIncluded:
          _multiSelectValues[includedName] ?? const <DynamicOption>[],
      initialExcluded:
          _multiSelectValues[excludedName] ?? const <DynamicOption>[],
    );

    if (result != null && mounted) {
      setState(() {
        _multiSelectValues[includedName] = result.included;
        _multiSelectValues[excludedName] = result.excluded;
      });
    }
  }

  Future<void> _openPicker(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) async {
    final sourceId = cubitState.pickerDataSource(name, field);
    final pickerColors = pickerSelectedColors(name, field, context);
    final pickerIcon = pickerLeadingIcon(name, field);
    if (sourceId == null) return;

    if (cubitState.loadingPickerSources.contains(sourceId)) {
      return;
    }

    final hasOptions =
        cubitState.optionCacheBySource[sourceId]?.isNotEmpty ?? false;
    if (!hasOptions) {
      await cubit.loadPickerOptionsForSource(
        sourceId: widget.sourceId,
        dataSourceId: sourceId,
        force: true,
      );
    }

    final options = List<DynamicOption>.from(
      cubit.state.optionCacheBySource[sourceId] ?? const <DynamicOption>[],
    );
    if (options.isEmpty) {
      if (!mounted) return;
      final loadError = cubit.state.pickerLoadErrorBySource[sourceId];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loadError == null || loadError.isEmpty
                ? AppLocalizations.of(context)!.noOptionsAvailable
                : AppLocalizations.of(context)!.failedLoadingOptions,
          ),
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.retryAction,
            onPressed: () => _openPicker(name, field, cubit, cubit.state),
          ),
        ),
      );
      return;
    }

    final selected = List<DynamicOption>.from(_multiSelectValues[name] ?? []);

    if (!mounted) return;
    final result = await showDynamicFormMultiSelectPicker(
      context: context,
      title: 'Select ${_labelFor(name, cubit.state)}',
      leadingIcon: pickerIcon,
      colors: pickerColors,
      options: options,
      initialSelected: selected,
    );

    if (result != null && mounted) {
      setState(() {
        _multiSelectValues[name] = result;
      });
    }
  }

  List<String> _collectTagFieldValues(
    String name,
    Map<String, dynamic>? rawField,
  ) {
    final field = widget.config.params[name];
    if (field == null || field.type != 'tag') return const <String>[];

    final values = <String>[];
    if (isTagChipsField(name, field, rawField)) {
      values.addAll(_tagChipValues[name] ?? const <String>[]);

      final trailingInput = _textControllers[name]?.text.trim() ?? '';
      if (trailingInput.isNotEmpty) {
        values.addAll(splitFieldInput(rawField, trailingInput, field.type));
      }

      return values;
    }

    final val = _textControllers[name]?.text.trim() ?? '';
    if (val.isNotEmpty) {
      values.addAll(splitFieldInput(rawField, val, field.type));
    }

    return values;
  }

  List<String> _collectEncodedQueryParts(
    DynamicFormSearchState cubitState, {
    List<FilterItem>? selectedTagItems,
  }) {
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
      if (qp == null || !DynamicFormSearchUI.emitsQueryParam(qp)) continue;
      final rawField = cubitState.rawFieldConfig(name);
      final joinMode = (rawField?['joinMode'] as String?)?.trim();

      if (isPickerField(name, field, rawField)) {
        final selected = _multiSelectValues[name] ?? const <DynamicOption>[];
        for (final option in selected) {
          final formatted = formatFieldValue(rawField, option.value);
          addParamValue(qp, formatted, joinMode: joinMode);

          if (selectedTagItems != null) {
            selectedTagItems.add(
              FilterItem(
                value: option.label,
                isExcluded: isExcludedTagField(name, field),
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
            final splitValues = splitFieldInput(rawField, val, field.type);
            for (final item in splitValues) {
              final formatted = formatFieldValue(rawField, item);
              addParamValue(qp, formatted, joinMode: joinMode);
            }
          }
        case 'tag':
          final values = _collectTagFieldValues(name, rawField);
          for (final item in values) {
            final formatted = formatFieldValue(rawField, item);
            addParamValue(qp, formatted, joinMode: joinMode);
          }
        case 'select':
        case 'sort':
        case 'radio':
          final val = _selectValues[name];
          if (val != null && val.isNotEmpty) {
            final formatted = formatFieldValue(rawField, val);
            addParamValue(qp, formatted, joinMode: joinMode);
          }
        case 'checkbox':
          final selected = _multiSelectValues[name] ?? const <DynamicOption>[];
          for (final option in selected) {
            final formatted = formatFieldValue(rawField, option.value);
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

  Widget _buildQueryPreviewCard(DynamicFormSearchState cubitState) {
    final parts = _collectEncodedQueryParts(cubitState);
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    final rawQuery = 'raw:${parts.join('&')}';
    final parsed = parseRaw(parts.join('&'));
    final qExpr = _extractPreviewQueryExpression(parsed);

    final colorScheme = Theme.of(context).colorScheme;
    final otherParams = parsed.entries.where((e) => e.key != 'q').toList();

    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.preview_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.activeFilterPreview,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (qExpr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                qExpr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
            if (otherParams.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: otherParams.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                    child: Text(
                      '${e.key}: ${e.value.join(", ")}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              rawQuery,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colorScheme.outline, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _extractPreviewQueryExpression(Map<String, List<String>> parsed) {
    final qValues = parsed['q'];
    if (qValues == null || qValues.isEmpty) return '';
    return qValues.join(' ');
  }

  Widget _buildSelectField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchState cubitState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = _optionsForField(name, field, cubitState);
    final selected = _selectValues[name];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name, cubitState).toUpperCase(),
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
        color: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface,
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

  Widget _buildCheckboxField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchCubit cubit,
    DynamicFormSearchState cubitState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final rawField = cubitState.rawFieldConfig(name);
    final options = _optionsForField(name, field, cubitState);
    final selected = _multiSelectValues[name] ?? const <DynamicOption>[];
    final selectedValues = selected.map((option) => option.value).toSet();
    final isDynamic = _isDynamicCheckboxField(name, field, rawField);
    final isLoading = cubitState.loadingCheckboxFields.contains(name);
    final loadError = cubitState.checkboxLoadErrorByField[name];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _labelFor(name, cubitState).toUpperCase(),
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
            cubit: cubit,
            cubitState: cubitState,
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
                      final next = <DynamicOption>[...selected];
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
    required DynamicOption option,
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
        color: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface,
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

  List<DynamicOption> _optionsForField(
    String name,
    SearchFormFieldConfig field,
    DynamicFormSearchState cubitState,
  ) {
    final rawField = cubitState.rawFieldConfig(name);
    if (_isDynamicCheckboxField(name, field, rawField)) {
      return cubitState.checkboxOptionCache[name] ?? const <DynamicOption>[];
    }

    final rawOptions = rawField?['options'];
    if (rawOptions is List) {
      return rawOptions
          .map<DynamicOption?>((dynamic option) {
            if (option is Map<String, dynamic>) {
              final value = option['value']?.toString() ?? '';
              if (value.isEmpty) return null;
              return DynamicOption(
                value: value,
                label:
                    option['name']?.toString() ??
                    option['label']?.toString() ??
                    value,
              );
            }
            final value = option?.toString() ?? '';
            if (value.isEmpty) return null;
            return DynamicOption(value: value, label: _capitalize(value));
          })
          .whereType<DynamicOption>()
          .toList(growable: false);
    }

    return (field.options ?? const <SearchFormOptionConfig>[])
        .map(
          (opt) => DynamicOption(
            value: opt.value,
            label: opt.name ?? opt.label ?? _capitalize(opt.value),
          ),
        )
        .toList(growable: false);
  }

  bool _isDynamicCheckboxField(
    String name,
    SearchFormFieldConfig field,
    Map<String, dynamic>? rawField,
  ) {
    if (field.type != 'checkbox') return false;
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
    required DynamicFormSearchCubit cubit,
    required DynamicFormSearchState cubitState,
  }) {
    final rawField = cubitState.rawFieldConfig(fieldName);
    final sourceUrl = rawField?['tagSourceUrl']?.toString();
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
          'checkbox-remote-state-$fieldName-${isLoading
              ? 'loading'
              : isError
              ? 'error'
              : 'idle'}',
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
                                  : AppLocalizations.of(context)!
                                        .loadingOptions)
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
                            color: theme.colorScheme.outline,
                            fontFamily: 'monospace',
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
                        : () => cubit.loadCheckboxOptionsForField(
                            sourceId: widget.sourceId,
                            fieldName: fieldName,
                            rawField: rawField,
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

  String? _findPairedExcludedFieldName() {
    for (final entry in widget.config.params.entries) {
      if (isExcludedTagField(entry.key, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  String _labelFor(String name, DynamicFormSearchState cubitState) {
    final rawField = cubitState.rawFieldConfig(name);
    if (rawField?['label'] is String) {
      final l = (rawField!['label'] as String).trim();
      if (l.isNotEmpty) return l;
    }
    return switch (name) {
      'query' => AppLocalizations.of(context)!.searchLabel,
      'genre' => AppLocalizations.of(context)!.genreLabel,
      'status' => AppLocalizations.of(context)!.statusLabel,
      'order' => AppLocalizations.of(context)!.orderBy,
      'author' => AppLocalizations.of(context)!.authorLabel,
      'artist' => AppLocalizations.of(context)!.artistFilterLabel,
      _ => _capitalize(name),
    };
  }

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
