part of 'settings_screen.dart';

SourceInstallerService _resolveInstaller(
  BuildContext context, [
  SourceInstallerService? service,
]) {
  if (service != null) return service;
  try {
    return context.read<SourceInstallerService>();
  } catch (_) {
    throw StateError(
      'SourceInstallerService is not available in the widget tree. '
      'Provide it via BlocProvider/RepositoryProvider, or pass it explicitly.',
    );
  }
}

Widget _buildSourceInstallCard(
  ThemeData theme,
  AppLocalizations l10n,
  BuildContext context, {
  SourceInstallerService? service,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      buildSettingsSectionHeader(
        Icons.download_outlined,
        l10n.availableSources,
        theme,
      ),
      const SizedBox(height: 12),
      buildSettingsCard([
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(
            l10n.settingsCustomSourceTitle,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            l10n.settingsCustomSourceSubtitle,
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _installSourceFromLink(context, service: service),
                  icon: const Icon(Icons.link),
                  label: Text(l10n.settingsAddViaLink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _installSourceFromZip(context, service: service),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: Text(l10n.settingsImportZip),
                ),
              ),
            ],
          ),
        ),
      ], theme),
    ],
  );
}

Widget _buildInstalledSourcesList(
  ThemeData theme,
  AppLocalizations l10n,
  BuildContext context,
  Map<String, SourceHealthStatus> healthStatuses,
  VoidCallback runHealthCheck,
  String searchQuery, {
  SourceInstallerService? service,
}) {
  final installer = _resolveInstaller(context, service);

  return BlocBuilder<SourceCubit, SourceState>(
    builder: (context, srcState) {
      final filteredSources = srcState.availableSources.where((s) {
        if (searchQuery.isEmpty) return true;
        final q = searchQuery.toLowerCase();
        return s.displayName.toLowerCase().contains(q) ||
            s.id.toLowerCase().contains(q);
      }).toList(growable: false);
      final reachableCount = filteredSources
          .where((s) => healthStatuses[s.id] == SourceHealthStatus.reachable)
          .length;
      return buildSettingsCard([
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(
            l10n.sourceSelectorSelectSource,
            style: TextStyleConst.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            AppLocalizations.of(context)!
                .nSourcesInstalled(srcState.availableSources.length),
            style: TextStyleConst.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (filteredSources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$reachableCount/${filteredSources.length} sources reachable',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: reachableCount == filteredSources.length
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => runHealthCheck(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check All'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        if (filteredSources.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                KuroMascot(
                  mood: searchQuery.isNotEmpty
                      ? KuroMood.cry
                      : KuroMood.waiting,
                  size: 96,
                ),
                const SizedBox(height: 8),
                Text(
                  searchQuery.isNotEmpty
                      ? l10n.sourceSelectorNoResults
                      : l10n.sourceSelectorNoSourceSelected,
                  textAlign: TextAlign.center,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          ...installer
              .sortSourcesUpdateFirst(
                  filteredSources, (source) => source.id)
              .map((ranked) {
            final source = ranked.source;
            final isActive = srcState.activeSource?.id == source.id;
            final canUninstall = source.id != 'nhentai';
            final health =
                healthStatuses[source.id] ?? SourceHealthStatus.unknown;
            final sourceInfo = installer.resolveDisplayInfo(source.id);
            final hasUpdate =
                ranked.status == SourceVersionStatus.updateAvailable;
            final description = sourceInfo.description;
            final subtitle = (description != null && description.isNotEmpty)
                ? '$description\n${sourceInfo.idWithVersion}'
                : sourceInfo.idWithVersion;
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: buildHealthDot(source, health, theme),
              title: Text(
                source.displayName,
                style: TextStyleConst.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyleConst.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUpdate)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.18),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusMd),
                      ),
                      child: Text(
                        l10n.sourceImportStatusUpdate,
                        style: TextStyleConst.bodySmall.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (hasUpdate && (isActive || canUninstall))
                    const SizedBox(width: 4),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusMd),
                      ),
                      child: Text(
                        l10n.sourceSelectorActiveSource,
                        style: TextStyleConst.bodySmall.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (canUninstall) ...[
                    if (isActive) const SizedBox(width: 4),
                    IconButton(
                      tooltip:
                          AppLocalizations.of(context)!.uninstallSource,
                      onPressed: () => _confirmAndUninstallSource(
                        context,
                        source.id,
                        service: installer,
                      ),
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
      ], theme);
    },
  );
}

Widget _buildSourcesShortcut(
    _SettingsScreenState state, ThemeData theme, AppLocalizations l10n) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      buildSettingsSectionHeader(
          Icons.download_outlined, l10n.availableSources, theme),
      const SizedBox(height: 12),
      BlocBuilder<SourceCubit, SourceState>(
        builder: (context, srcState) => buildSettingsCard([
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.dns_outlined),
            title: Text(
              l10n.settingsCustomSourceTitle,
              style: TextStyleConst.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              l10n.nSourcesInstalled(srcState.availableSources.length),
              style: TextStyleConst.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const SourceManagerScreen()),
            ),
          ),
        ], theme),
      ),
    ],
  );
}

Future<void> _confirmAndUninstallSource(
  BuildContext context,
  String sourceId, {
  SourceInstallerService? service,
}) async {
  if (sourceId == 'nhentai') {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final sourceCubit = context.read<SourceCubit>();
  final theme = Theme.of(context);
  // Resolve before any await: fail fast instead of confirming an action
  // that cannot run, and satisfy use_build_context_synchronously.
  final installer = _resolveInstaller(context, service);
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(AppLocalizations.of(context)!.uninstallSourceTitle,
              style: TextStyle(color: theme.colorScheme.onSurface)),
          content: Text(
            AppLocalizations.of(context)!.removeSourceConfirmation(sourceId),
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => ctx.pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => ctx.pop(true),
              child: Text(AppLocalizations.of(context)!.uninstall),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed) return;

  try {
    final result = await installer.uninstallSource(sourceId);

    sourceCubit.refreshSources();

    if (result.wasActive && result.nextActiveSourceId != null) {
      sourceCubit.switchSource(result.nextActiveSourceId!);
      sourceCubit.clearSwitching();
    }

    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(AppLocalizations.of(context)!.sourceUninstalled(sourceId)),
        backgroundColor: AppColors.success,
      ),
    );
  } catch (e, stackTrace) {
    Logger().e('Failed to uninstall source: $e', stackTrace: stackTrace);
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!
            .failedToUninstall(sourceId, e.toString())),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

Future<void> _installSourceFromLink(
  BuildContext context, {
  SourceInstallerService? service,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();

  final theme = Theme.of(context);
  final link = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      title: Text(l10n.sourceImportLinkDialogTitle,
          style: TextStyle(color: theme.colorScheme.onSurface)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.sourceImportConfigUrlHint,
          labelText: l10n.sourceImportConfigUrlLabel,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => ctx.pop(controller.text.trim()),
          child: Text(l10n.sourceImportConfirmInstall),
        ),
      ],
    ),
  );

  if (link == null || link.isEmpty) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.sourceImportInstallingFromLink),
      duration: const Duration(seconds: 10),
    ),
  );

  if (!context.mounted) return;

  try {
    final installer = _resolveInstaller(context, service);
    final plan = await installer.inspectLink(link);
    List<SourceInstallCandidate> candidates;

    if (plan is SourceInstallSelectionPlan) {
      if (!context.mounted) return;
      final selectedEntries = await _selectGlobalManifestEntries(
        context: context,
        entries: plan.entries,
        service: installer,
      );
      if (selectedEntries.isEmpty) {
        messenger.hideCurrentSnackBar();
        return;
      }
      candidates = await installer.resolveSelection(plan, selectedEntries);
    } else if (plan is SourceInstallDirectPlan) {
      candidates = plan.candidates;
    } else {
      messenger.hideCurrentSnackBar();
      return;
    }

    if (candidates.isEmpty) {
      messenger.hideCurrentSnackBar();
      return;
    }
    installer.rememberCandidateVersions(
      candidates.map((c) => (id: c.sourceId, version: c.version)),
    );

    if (!context.mounted) return;
    final shouldInstall = candidates.length == 1
        ? await _showInstallPreviewDialog(context, candidates.first,
            service: installer)
        : await _showBatchInstallPreviewDialog(context, candidates,
            service: installer);
    if (!shouldInstall) {
      messenger.hideCurrentSnackBar();
      return;
    }

    final result = await installer.installCandidates(
      candidates,
      sourceLabel: 'link',
    );

    if (!context.mounted) return;
    context.read<SourceCubit>().refreshSources();

    messenger.hideCurrentSnackBar();
    if (result.isAllSuccess) {
      final message = result.installed.length == 1
          ? l10n.sourceImportInstalledFromLink(result.installed.first)
          : l10n.installedSourcesFromZip(result.installed.length);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      final reasonHint = result.failed.isNotEmpty
          ? ' • ${result.failed.first}: ${result.failedReasons[result.failed.first] ?? 'unknown error'}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${result.installed.length}, failed ${result.failed.length}: ${result.failed.join(', ')}$reasonHint',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  } catch (e, stackTrace) {
    Logger()
        .e('Failed to install source from link: $e', stackTrace: stackTrace);
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.sourceImportFailedFromLink(e.toString())),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

Future<void> _installSourceFromZip(
  BuildContext context, {
  SourceInstallerService? service,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;

  try {
    final bytes = await KuronNative.instance.pickBinaryFile(
      mimeType: 'application/zip',
    );
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.sourceImportInstallingFromZip),
        duration: const Duration(seconds: 10),
      ),
    );

    if (!context.mounted) return;

    final installer = _resolveInstaller(context, service);
    final plan = await installer.inspectZip(bytes);
    List<SourceInstallCandidate> candidates;

    if (plan is SourceInstallSelectionPlan) {
      if (!context.mounted) return;
      final selectedEntries = await _selectGlobalManifestEntries(
        context: context,
        entries: plan.entries,
        service: installer,
      );
      if (selectedEntries.isEmpty) {
        messenger.hideCurrentSnackBar();
        return;
      }
      candidates = await installer.resolveSelection(plan, selectedEntries);
    } else if (plan is SourceInstallDirectPlan) {
      candidates = plan.candidates;
    } else {
      messenger.hideCurrentSnackBar();
      return;
    }

    if (candidates.isEmpty) {
      messenger.hideCurrentSnackBar();
      return;
    }
    installer.rememberCandidateVersions(
      candidates.map((c) => (id: c.sourceId, version: c.version)),
    );

    if (!context.mounted) return;
    final shouldInstall = candidates.length == 1
        ? await _showInstallPreviewDialog(context, candidates.first,
            service: installer)
        : await _showBatchInstallPreviewDialog(context, candidates,
            service: installer);
    if (!shouldInstall) {
      messenger.hideCurrentSnackBar();
      return;
    }

    final result = await installer.installCandidates(
      candidates,
      sourceLabel: 'ZIP',
    );

    if (!context.mounted) return;
    context.read<SourceCubit>().refreshSources();

    messenger.hideCurrentSnackBar();
    if (result.isAllSuccess) {
      final message = result.installed.length == 1
          ? l10n.sourceImportInstalledFromZip(result.installed.first)
          : AppLocalizations.of(context)!
              .installedSourcesFromZip(result.installed.length);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      final reasonHint = result.failed.isNotEmpty
          ? ' • ${result.failed.first}: ${result.failedReasons[result.failed.first] ?? 'unknown error'}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${result.installed.length}, failed ${result.failed.length}: ${result.failed.join(', ')}$reasonHint',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  } catch (e, stackTrace) {
    Logger().e('Failed to install source from ZIP: $e', stackTrace: stackTrace);
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.sourceImportFailedFromZip(e.toString())),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

String _sourceVersionStatusLabel(
    AppLocalizations l10n, SourceVersionStatus status) {
  switch (status) {
    case SourceVersionStatus.updateAvailable:
      return l10n.sourceImportStatusUpdate;
    case SourceVersionStatus.upToDate:
      return l10n.upToDate;
    case SourceVersionStatus.downgrade:
      return l10n.sourceImportStatusDowngrade;
    case SourceVersionStatus.notInstalled:
    case SourceVersionStatus.unknown:
      return '';
  }
}

String _manifestSortLabel(AppLocalizations l10n, ManifestSortMode mode) {
  switch (mode) {
    case ManifestSortMode.updatesFirst:
      return l10n.sourceImportSortUpdatesFirst;
    case ManifestSortMode.nameAsc:
      return l10n.sourceImportSortNameAsc;
    case ManifestSortMode.versionDesc:
      return l10n.sourceImportSortVersionDesc;
  }
}

String _manifestEntrySubtitle(
  AppLocalizations l10n,
  GlobalManifestEntry entry,
  String? installed,
  SourceVersionStatus status,
) {
  final versionDiff = installed == null
      ? 'v${entry.version}'
      : l10n.sourceImportVersionDiff(installed, entry.version);
  final statusLabel = _sourceVersionStatusLabel(l10n, status);
  final versionLine = statusLabel.isEmpty
      ? '${entry.id} • $versionDiff'
      : '${entry.id} • $versionDiff • $statusLabel';

  if (entry.description == null || entry.description!.isEmpty) {
    return versionLine;
  }
  return '${entry.description!}\n$versionLine';
}

Future<List<GlobalManifestEntry>> _selectGlobalManifestEntries({
  required BuildContext context,
  required List<GlobalManifestEntry> entries,
  required SourceInstallerService service,
}) async {
  service.rememberCandidateVersions(
    entries.map((entry) => (id: entry.id, version: entry.version)),
  );
  final sorted = service.sortEntriesUpdateFirst(entries);
  if (sorted.length == 1) {
    return sorted;
  }
  final selected = <GlobalManifestEntry>{};
  var searchQuery = '';
  var sortMode = ManifestSortMode.updatesFirst;
  final result = await showModalBottomSheet<List<GlobalManifestEntry>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
      final theme = Theme.of(ctx);
      final query = searchQuery.trim().toLowerCase();
      final base = query.isEmpty
          ? entries
          : entries.where((entry) {
              final name = (entry.displayName ?? entry.id).toLowerCase();
              return name.contains(query) ||
                  entry.id.toLowerCase().contains(query);
            }).toList(growable: false);
      final filtered = service.applyManifestSort(base, sortMode);
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              ListTile(
                title: Text(
                    AppLocalizations.of(context)!.selectSourceFromManifest),
                subtitle:
                    Text(AppLocalizations.of(context)!.chooseMultipleSources),
                trailing: TextButton(
                  onPressed: filtered.isEmpty
                      ? null
                      : () => setModalState(() {
                            if (filtered.every(selected.contains)) {
                              selected.removeAll(filtered);
                            } else {
                              selected.addAll(filtered);
                            }
                          }),
                  child: Text(
                      filtered.isNotEmpty && filtered.every(selected.contains)
                          ? AppLocalizations.of(context)!.clearSelection
                          : AppLocalizations.of(context)!.selectAll),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (value) {
                    setModalState(() {
                      searchQuery = value;
                    });
                  },
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(context)!.sourceSelectorSearchHint,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusLg),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.sort_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<ManifestSortMode>(
                        value: sortMode,
                        isExpanded: true,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() => sortMode = value);
                          }
                        },
                        items: [
                          for (final mode in ManifestSortMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(
                                _manifestSortLabel(
                                  AppLocalizations.of(context)!,
                                  mode,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            searchQuery.trim().isEmpty
                                ? AppLocalizations.of(context)!
                                    .sourceSelectorNoResults
                                : 'No sources matching "$searchQuery"',
                            textAlign: TextAlign.center,
                            style: TextStyleConst.bodyMedium.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final entry = filtered[index];
                          final isSelected = selected.contains(entry);
                          final installed =
                              service.getInstalledVersion(entry.id);
                          final status = resolveSourceVersionStatus(
                            installedVersion: installed,
                            candidateVersion: entry.version,
                          );
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(entry.displayName ?? entry.id),
                            subtitle: Text(
                              _manifestEntrySubtitle(
                                  AppLocalizations.of(context)!,
                                  entry,
                                  installed,
                                  status),
                            ),
                            onChanged: (value) {
                              setModalState(() {
                                if (value == true) {
                                  selected.add(entry);
                                } else {
                                  selected.remove(entry);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => ctx.pop(<GlobalManifestEntry>[]),
                        child: Text(AppLocalizations.of(context)!.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => ctx.pop(selected.toList(growable: false)),
                        child: Text(
                          selected.isEmpty
                              ? AppLocalizations.of(context)!.installSelected
                              : '${AppLocalizations.of(context)!.installSelected} (${selected.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );

  return result ?? const [];
}

Future<bool> _showInstallPreviewDialog(
  BuildContext context,
  SourceInstallCandidate candidate, {
  required SourceInstallerService service,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final installed = service.getInstalledVersion(candidate.sourceId);
  final status = resolveSourceVersionStatus(
    installedVersion: installed,
    candidateVersion: candidate.version,
  );
  final versionLine = installed == null
      ? 'v${candidate.version}'
      : l10n.sourceImportVersionDiff(installed, candidate.version);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cs.surface,
      title: Text(l10n.sourceImportPreviewTitle,
          style: TextStyle(color: cs.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${l10n.sourceImportPreviewSourceId}: ${candidate.sourceId}',
              style: TextStyle(color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('${l10n.sourceImportPreviewVersion}: $versionLine',
              style: TextStyle(color: cs.onSurface)),
          if (_sourceVersionStatusLabel(l10n, status).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_sourceVersionStatusLabel(l10n, status),
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          ],
          if (candidate.displayName != null &&
              candidate.displayName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
                '${l10n.sourceImportPreviewDisplayName}: ${candidate.displayName}',
                style: TextStyle(color: cs.onSurface)),
          ],
          if (candidate.description != null &&
              candidate.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(candidate.description!,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Text(
            '${l10n.sourceImportPreviewVerified}: ${candidate.isVerified ? l10n.sourceImportPreviewVerifiedYes : l10n.sourceImportPreviewVerifiedNo}',
            style: TextStyle(color: cs.onSurface),
          ),
          if (status == SourceVersionStatus.downgrade && installed != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.sourceImportDowngradeWarning(installed, candidate.version),
              style: TextStyle(color: cs.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => ctx.pop(true),
          child: Text(status == SourceVersionStatus.updateAvailable
              ? l10n.sourceImportConfirmUpdate
              : l10n.sourceImportConfirmInstall),
        ),
      ],
    ),
  );

  return result ?? false;
}

Future<bool> _showBatchInstallPreviewDialog(
  BuildContext context,
  List<SourceInstallCandidate> candidates, {
  required SourceInstallerService service,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cs.surface,
      title: Text(l10n.sourceImportPreviewTitle,
          style: TextStyle(color: cs.onSurface)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                AppLocalizations.of(context)!
                    .selectedSourcesCount(candidates.length),
                style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, index) {
                  final candidate = candidates[index];
                  final installed =
                      service.getInstalledVersion(candidate.sourceId);
                  final status = resolveSourceVersionStatus(
                    installedVersion: installed,
                    candidateVersion: candidate.version,
                  );
                  final versionText = installed == null
                      ? 'v${candidate.version}'
                      : l10n.sourceImportVersionDiff(
                          installed, candidate.version);
                  final label = _sourceVersionStatusLabel(l10n, status);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '- ${candidate.displayName ?? candidate.sourceId} ($versionText${label.isEmpty ? '' : ' • $label'})',
                        style: TextStyle(color: cs.onSurface),
                      ),
                      if (status == SourceVersionStatus.downgrade &&
                          installed != null)
                        Text(
                          l10n.sourceImportDowngradeWarning(
                              installed, candidate.version),
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => ctx.pop(true),
          child: Text(AppLocalizations.of(context)!.installSelected),
        ),
      ],
    ),
  );

  return result ?? false;
}
