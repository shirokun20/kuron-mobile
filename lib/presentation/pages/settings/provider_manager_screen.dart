import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/ai_settings/ai_settings_cubit.dart';
import 'settings_theme_widgets.dart';

/// Dedicated AI provider (BYOK) manager: list, CRUD, set-default, validate.
/// Reuses [AiSettingsCubit] — no separate cubit.
class ProviderManagerScreen extends StatelessWidget {
  const ProviderManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AiSettingsCubit(
        providerRepository: getIt(),
        preferencesRepository: getIt(),
        providerFactory: getIt(),
        cacheRepository: getIt(),
        modelCatalog: getIt(),
        logger: getIt(),
        localizations: AppLocalizations.of(context),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('AI Providers')),
        body: const _ProviderManagerBody(),
      ),
    );
  }
}

class _ProviderManagerBody extends StatelessWidget {
  const _ProviderManagerBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<AiSettingsCubit, AiSettingsState>(
      builder: (context, state) {
        if (state is AiSettingsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is AiSettingsError) {
          return Center(child: Text(state.message));
        }
        if (state is! AiSettingsLoaded) {
          return const SizedBox.shrink();
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            buildSettingsCard([
              for (final p in state.providers) ...[
                _ProviderTile(provider: p),
                if (p != state.providers.last) buildSettingsDivider(theme),
              ],
            ], theme),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showProviderForm(context, null),
                icon: const Icon(Icons.add),
                label: Text(l10n.aiAddProvider),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showProviderForm(BuildContext context, AiProviderConfig? provider) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      // Modal sheets live on the root navigator and lose the screen-scoped
      // cubit — re-provide by value.
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<AiSettingsCubit>(),
        child: _ProviderFormSheet(provider: provider),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider});

  final AiProviderConfig provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AiSettingsCubit>();
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: InkWell(
          onTap: () => cubit.setDefault(provider.id),
          borderRadius: BorderRadius.circular(20),
          child: Icon(
            provider.isDefault
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: provider.isDefault
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        title: Text(
          provider.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${provider.type.displayName} • ${provider.model.isEmpty ? '—' : provider.model}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () {
          final sheetCtx = context;
          showModalBottomSheet<void>(
            context: sheetCtx,
            isScrollControlled: true,
            backgroundColor: theme.colorScheme.surfaceContainer,
            builder: (sheetContext) => BlocProvider.value(
              value: cubit,
              child: _ProviderFormSheet(provider: provider),
            ),
          );
        },
      ),
    );
  }
}

class _ProviderFormSheet extends StatefulWidget {
  const _ProviderFormSheet({required this.provider});

  final AiProviderConfig? provider;

  @override
  State<_ProviderFormSheet> createState() => _ProviderFormSheetState();
}

class _ProviderFormSheetState extends State<_ProviderFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _keyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;
  late AiProviderType _type;
  bool _isTesting = false;
  String? _testResult;
  bool _testRan = false;
  List<AiModelOption>? _models;
  String? _modelsError;
  bool _isLoadingModels = false;
  bool _manualMode = false;
  bool? _selectedVision;
  String _modelFilter = 'all';
  String _searchQuery = '';

  bool get _isEditing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _type = p?.type ?? AiProviderType.openCodeGo;
    _nameController = TextEditingController(text: p?.displayName ?? '');
    _keyController = TextEditingController(text: p?.apiKey ?? '');
    _modelController = TextEditingController(text: p?.model ?? '');
    _baseUrlController = TextEditingController(text: p?.baseUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  AiProviderConfig _buildConfig() {
    final existing = widget.provider;
    return AiProviderConfig(
      id: existing?.id ?? 'prov_${DateTime.now().millisecondsSinceEpoch}',
      displayName: _nameController.text.trim().isEmpty
          ? _type.displayName
          : _nameController.text.trim(),
      type: _type,
      model: _modelController.text.trim(),
      apiKey: _keyController.text.trim().isEmpty
          ? null
          : _keyController.text.trim(),
      baseUrl: _type == AiProviderType.custom
          ? (_baseUrlController.text.trim().isEmpty
              ? null
              : _baseUrlController.text.trim())
          : existing?.baseUrl,
      isDefault: existing?.isDefault ?? false,
      modelIsVision: _selectedVision,
    );
  }

  Future<void> _loadModels() async {
    if (_type == AiProviderType.custom) return;
    setState(() {
      _isLoadingModels = true;
      _modelsError = null;
    });
    try {
      final apiKey = _keyController.text.trim().isEmpty
          ? null
          : _keyController.text.trim();
      final models = await context
          .read<AiSettingsCubit>()
          .fetchModels(type: _type, apiKey: apiKey);
      if (!mounted) return;
      setState(() {
        _models = models;
        _isLoadingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsError = e.toString();
        _isLoadingModels = false;
      });
    }
  }

  Widget _buildModelField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_type == AiProviderType.custom) {
      return TextField(
        controller: _modelController,
        decoration: InputDecoration(
            labelText: l10n.aiModel, hintText: 'e.g. gpt-4o-mini'),
      );
    }
    if (_manualMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _modelController,
            decoration: InputDecoration(labelText: l10n.aiModel),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _manualMode = false),
            icon: const Icon(Icons.list, size: 16),
            label: Text(l10n.aiUseLov),
          ),
        ],
      );
    }
    if (_isLoadingModels) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    }
    if (_modelsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_modelsError!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(onPressed: _loadModels, child: Text(l10n.aiReload)),
            const SizedBox(width: 8),
            TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: Text(l10n.aiManualEntry)),
          ]),
        ],
      );
    }
    if (_models == null) {
      final needsKey =
          _type.needsKeyForListing && _keyController.text.trim().isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: needsKey ? null : _loadModels,
            icon: const Icon(Icons.cloud_download, size: 16),
            label: Text(l10n.aiLoadModels),
          ),
          if (needsKey)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.aiEnterApiKeyFirst,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.orange))),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () => setState(() => _manualMode = true),
                  child: Text(l10n.aiManualEntry))),
        ],
      );
    }
    final filtered = _models!.where((m) {
      if (_modelFilter == 'vision' && m.isVision != true) {
        return false;
      }
      if (_modelFilter == 'text' && m.isVision != false) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !m.id.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    final isLarge = _models!.length > 80;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          ChoiceChip(
              label: Text(l10n.aiAll),
              selected: _modelFilter == 'all',
              onSelected: (_) => setState(() => _modelFilter = 'all')),
          const SizedBox(width: 6),
          ChoiceChip(
              label: Text(l10n.aiVision),
              selected: _modelFilter == 'vision',
              onSelected: (_) => setState(() => _modelFilter = 'vision')),
          const SizedBox(width: 6),
          ChoiceChip(
              label: Text(l10n.aiTextOnly),
              selected: _modelFilter == 'text',
              onSelected: (_) => setState(() => _modelFilter = 'text')),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadModels,
              tooltip: l10n.aiReload),
        ]),
        const SizedBox(height: 8),
        if (isLarge)
          TextField(
            decoration: InputDecoration(
                hintText: l10n.aiSearchModels,
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        if (isLarge) const SizedBox(height: 8),
        if (isLarge)
          OutlinedButton.icon(
            onPressed: () => _showModelPicker(context, filtered),
            icon: const Icon(Icons.list),
            label: Text(_modelController.text.isEmpty
                ? l10n.aiSelectModel
                : _modelController.text),
          )
        else
          DropdownButtonFormField<String>(
            initialValue:
                _modelController.text.isEmpty ? null : _modelController.text,
            decoration: InputDecoration(labelText: l10n.aiModel),
            isExpanded: true,
            items: filtered
                .map((m) => DropdownMenuItem(
                    value: m.id,
                    child: Row(children: [
                      Expanded(
                          child: Text(m.id,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                      if (m.isVision != null) ...[
                        const SizedBox(width: 6),
                        Icon(m.isVision! ? Icons.visibility : Icons.text_fields,
                            size: 14,
                            color: m.isVision! ? Colors.green : Colors.grey)
                      ]
                    ])))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final opt = filtered.firstWhere((e) => e.id == v);
              setState(() {
                _modelController.text = v;
                _selectedVision = opt.isVision;
              });
            },
          ),
        const SizedBox(height: 4),
        TextButton(
            onPressed: () => setState(() => _manualMode = true),
            child: Text(l10n.aiManualEntry)),
        if (_models != null &&
            widget.provider != null &&
            widget.provider!.model.isNotEmpty &&
            !_models!.any((m) => m.id == widget.provider!.model))
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.aiStaleModel(widget.provider!.model),
                  style:
                      TextStyle(color: Colors.orange.shade700, fontSize: 11))),
      ],
    );
  }

  void _showModelPicker(BuildContext context, List<AiModelOption> options) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String q = _searchQuery;
        String filter = _modelFilter;
        return StatefulBuilder(builder: (ctx, setSheet) {
          final filtered = options.where((m) {
            if (filter == 'vision' && m.isVision != true) {
              return false;
            }
            if (filter == 'text' && m.isVision != false) {
              return false;
            }
            if (q.isNotEmpty && !m.id.toLowerCase().contains(q.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (_, ctrl) => Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                            decoration: InputDecoration(
                                hintText: l10n.aiSearchModels,
                                prefixIcon: const Icon(Icons.search)),
                            onChanged: (v) => setSheet(() => q = v))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          ChoiceChip(
                              label: Text(l10n.aiAll),
                              selected: filter == 'all',
                              onSelected: (_) =>
                                  setSheet(() => filter = 'all')),
                          const SizedBox(width: 6),
                          ChoiceChip(
                              label: Text(l10n.aiVision),
                              selected: filter == 'vision',
                              onSelected: (_) =>
                                  setSheet(() => filter = 'vision')),
                          const SizedBox(width: 6),
                          ChoiceChip(
                              label: Text(l10n.aiTextOnly),
                              selected: filter == 'text',
                              onSelected: (_) =>
                                  setSheet(() => filter = 'text')),
                        ])),
                    Expanded(
                        child: ListView.builder(
                            controller: ctrl,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              return ListTile(
                                  title: Text(m.id,
                                      style: const TextStyle(fontSize: 13)),
                                  trailing: m.isVision == null
                                      ? null
                                      : Icon(
                                          m.isVision!
                                              ? Icons.visibility
                                              : Icons.text_fields,
                                          size: 16,
                                          color: m.isVision!
                                              ? Colors.green
                                              : Colors.grey),
                                  onTap: () {
                                    setState(() {
                                      _modelController.text = m.id;
                                      _selectedVision = m.isVision;
                                      _searchQuery = q;
                                      _modelFilter = filter;
                                    });
                                    Navigator.pop(ctx);
                                  });
                            })),
                  ]));
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AiSettingsCubit>();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? l10n.aiEditProvider : l10n.aiAddProvider,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (!_isEditing) ...[
              DropdownButtonFormField<AiProviderType>(
                initialValue: _type,
                decoration: InputDecoration(labelText: l10n.aiProviderType),
                items: AiProviderType.values
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t.displayName)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _type = v;
                    _modelController.clear();
                    _models = null;
                    _modelsError = null;
                    _isLoadingModels = false;
                    _selectedVision = null;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.aiDisplayName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.aiApiKey,
                hintText: l10n.aiApiKeyHint,
              ),
            ),
            const SizedBox(height: 12),
            _buildModelField(context),
            if (_type == AiProviderType.custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                decoration: InputDecoration(labelText: l10n.aiBaseUrl),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isTesting
                        ? null
                        : () async {
                            setState(() {
                              _isTesting = true;
                              _testResult = null;
                              _testRan = false;
                            });
                            final result =
                                await cubit.validateProvider(_buildConfig());
                            if (!context.mounted) return;
                            setState(() {
                              _isTesting = false;
                              _testResult = result;
                              _testRan = true;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result == null
                                    ? l10n.aiCheckIconD(_modelController.text)
                                    : '✗ ${result.substring(0, result.length > 100 ? 100 : result.length)}'),
                              ),
                            );
                          },
                    child: Text(_isTesting ? l10n.aiTesting : l10n.aiTestKey),
                  ),
                ),
                const SizedBox(width: 12),
                if (_isEditing)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () async {
                        await cubit.deleteProvider(widget.provider!.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(l10n.aiDelete),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () async {
                      final config = _buildConfig();
                      await cubit.saveProvider(config);
                      // New provider becomes the active (default) one.
                      if (!_isEditing) {
                        await cubit.setDefault(config.id);
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(l10n.aiSave),
                  ),
                ),
              ],
            ),
            if (_testRan) ...[
              const SizedBox(height: 12),
              Text(
                _testResult == null ? l10n.aiValidKey : '✗ $_testResult',
                style: TextStyle(
                  color: _testResult == null
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
            ],
            if (_type != AiProviderType.custom &&
                !_manualMode &&
                _models == null &&
                _modelsError == null) ...[
              const SizedBox(height: 8),
              Text(l10n.aiModelHint, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
