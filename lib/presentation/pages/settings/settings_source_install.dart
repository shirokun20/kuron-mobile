part of 'settings_screen.dart';

Widget _buildAvailableSourcesSection(
    ThemeData theme,
    AppLocalizations l10n,
    BuildContext context,
    Map<String, SourceHealthStatus> healthStatuses,
    VoidCallback runHealthCheck) {
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
                  onPressed: () => _installSourceFromLink(context),
                  icon: const Icon(Icons.link),
                  label: Text(l10n.settingsAddViaLink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _installSourceFromZip(context),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: Text(l10n.settingsImportZip),
                ),
              ),
            ],
          ),
        ),
      ], theme),
      const SizedBox(height: 12),
      BlocBuilder<SourceCubit, SourceState>(
        builder: (context, srcState) {
          final reachableCount = srcState.availableSources
              .where(
                  (s) => healthStatuses[s.id] == SourceHealthStatus.reachable)
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
            if (srcState.availableSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$reachableCount/${srcState.availableSources.length} sources reachable',
                        style: TextStyleConst.bodySmall.copyWith(
                          color:
                              reachableCount == srcState.availableSources.length
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
            if (srcState.availableSources.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l10n.sourceSelectorNoSourceSelected,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...srcState.availableSources.map((source) {
                final isActive = srcState.activeSource?.id == source.id;
                final canUninstall = source.id != 'nhentai';
                final health =
                    healthStatuses[source.id] ?? SourceHealthStatus.unknown;
                final remoteConfig = getIt<RemoteConfigService>();
                final sourceInfo = resolveSourceConfigDisplayInfo(
                  remoteConfigService: remoteConfig,
                  sourceId: source.id,
                );
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
                          onPressed: () =>
                              _confirmAndUninstallSource(context, source.id),
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
      ),
    ],
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

Future<void> _registerSourceInRegistry(
    BuildContext context, String sourceId) async {
  final remoteConfig = getIt<RemoteConfigService>();
  final registry = getIt<ContentSourceRegistry>();
  final resolver = getIt<SourceFactoryResolver>();
  final logger = getIt<Logger>();
  final raw = remoteConfig.getRawConfig(sourceId);

  if (raw == null) {
    throw StateError('$sourceId config missing after apply');
  }

  final wasActive = registry.currentSourceId == sourceId;
  if (registry.hasSource(sourceId)) {
    registry.unregister(sourceId);
  }

  ContentSource instance;
  try {
    instance = resolver.createSource(raw);
  } catch (e, stackTrace) {
    logger.w(
      'Specialized source factory failed for $sourceId, falling back to GenericSourceFactory',
      error: e,
      stackTrace: stackTrace,
    );
    instance = getIt<GenericSourceFactory>().create(raw);
  }

  registry.register(instance);
  if (wasActive) {
    registry.switchSource(sourceId);
  }

  context.read<SourceCubit>().refreshSources();
}

Future<void> _confirmAndUninstallSource(
    BuildContext context, String sourceId) async {
  if (sourceId == 'nhentai') {
    return;
  }

  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final sourceCubit = context.read<SourceCubit>();
  final theme = Theme.of(context);
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
    final remoteConfig = getIt<RemoteConfigService>();
    final registry = getIt<ContentSourceRegistry>();
    final wasActive = registry.currentSourceId == sourceId;

    await remoteConfig.uninstallSourceConfig(sourceId);
    if (registry.hasSource(sourceId)) {
      registry.unregister(sourceId);
    }

    sourceCubit.refreshSources();

    if (wasActive && registry.currentSourceId != null) {
      sourceCubit.switchSource(registry.currentSourceId!);
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

Future<void> _installSourceFromLink(BuildContext context) async {
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
    final dio = getIt<Dio>();
    final candidates = await _buildCandidatesFromLinkManifest(
      context: context,
      link: link,
      dio: dio,
      l10n: l10n,
    );

    if (candidates.isEmpty) {
      messenger.hideCurrentSnackBar();
      return;
    }

    if (!context.mounted) return;
    final shouldInstall = candidates.length == 1
        ? await _showInstallPreviewDialog(context, candidates.first)
        : await _showBatchInstallPreviewDialog(context, candidates);
    if (!shouldInstall) {
      messenger.hideCurrentSnackBar();
      return;
    }

    final remoteConfig = getIt<RemoteConfigService>();
    final installed = <String>[];
    final failed = <String>[];
    final failedReasons = <String, String>{};

    for (final candidate in candidates) {
      try {
        await remoteConfig.applySourceConfigFromJson(
          sourceId: candidate.sourceId,
          rawJson: candidate.rawJson,
          sourceLabel: 'link',
        );
        await remoteConfig.markSourceInstalled(candidate.sourceId);

        if (!context.mounted) return;
        await _registerSourceInRegistry(context, candidate.sourceId);
        installed.add(candidate.sourceId);
      } catch (e, stackTrace) {
        Logger().e(
          'Failed installing source from link ${candidate.sourceId}: $e',
          stackTrace: stackTrace,
        );
        failed.add(candidate.sourceId);
        failedReasons[candidate.sourceId] = e.toString();
      }
    }

    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (failed.isEmpty) {
      final message = installed.length == 1
          ? l10n.sourceImportInstalledFromLink(installed.first)
          : l10n.installedSourcesFromZip(installed.length);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      final reasonHint = failed.isNotEmpty
          ? ' • ${failed.first}: ${failedReasons[failed.first] ?? 'unknown error'}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${installed.length}, failed ${failed.length}: ${failed.join(', ')}$reasonHint',
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

Future<void> _installSourceFromZip(BuildContext context) async {
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

    final candidates = await _buildCandidateFromZip(
      context: context,
      bytes: bytes,
      l10n: l10n,
    );

    if (candidates.isEmpty) {
      messenger.hideCurrentSnackBar();
      return;
    }

    if (!context.mounted) return;
    final shouldInstall = candidates.length == 1
        ? await _showInstallPreviewDialog(context, candidates.first)
        : await _showBatchInstallPreviewDialog(context, candidates);
    if (!shouldInstall) {
      messenger.hideCurrentSnackBar();
      return;
    }

    final remoteConfig = getIt<RemoteConfigService>();
    final installed = <String>[];
    final failed = <String>[];
    final failedReasons = <String, String>{};

    for (final candidate in candidates) {
      try {
        await remoteConfig.applySourceConfigFromJson(
          sourceId: candidate.sourceId,
          rawJson: candidate.rawJson,
          sourceLabel: 'ZIP',
        );
        await remoteConfig.markSourceInstalled(candidate.sourceId);

        if (!context.mounted) return;
        await _registerSourceInRegistry(context, candidate.sourceId);
        installed.add(candidate.sourceId);
      } catch (e, stackTrace) {
        Logger().e(
          'Failed installing ZIP source ${candidate.sourceId}: $e',
          stackTrace: stackTrace,
        );
        failed.add(candidate.sourceId);
        failedReasons[candidate.sourceId] = e.toString();
      }
    }

    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (failed.isEmpty) {
      final message = installed.length == 1
          ? l10n.sourceImportInstalledFromZip(installed.first)
          : AppLocalizations.of(context)!
              .installedSourcesFromZip(installed.length);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      final reasonHint = failed.isNotEmpty
          ? ' • ${failed.first}: ${failedReasons[failed.first] ?? 'unknown error'}'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${installed.length}, failed ${failed.length}: ${failed.join(', ')}$reasonHint',
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

Future<List<_InstallCandidate>> _buildCandidatesFromLinkManifest({
  required BuildContext context,
  required String link,
  required Dio dio,
  required AppLocalizations l10n,
}) async {
  final manifestResponse = await dio.get<String>(
    link,
    options: Options(
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ),
  );

  final manifestRaw = manifestResponse.data;
  if (manifestRaw == null || manifestRaw.trim().isEmpty) {
    throw FormatException(l10n.sourceImportManifestInvalid);
  }

  final manifestMap = _decodeJsonObject(
    rawJson: manifestRaw,
    invalidMessage: l10n.sourceImportManifestInvalid,
  );

  if (manifestMap.containsKey('source')) {
    final sourceId = _requiredString(
      manifestMap,
      'source',
      l10n.sourceImportSourceMismatch,
    );
    final version = (manifestMap['version'] as String?)?.trim() ?? 'unknown';
    return [
      _InstallCandidate(
        sourceId: sourceId,
        version: version,
        displayName: null,
        description: null,
        rawJson: manifestRaw,
        isVerified: false,
      )
    ];
  }

  final installableSources =
      _parseGlobalManifestEntries(manifestMap, l10n).toList();
  if (installableSources.isNotEmpty) {
    if (!context.mounted) {
      throw StateError('SettingsScreen is no longer mounted');
    }
    final selectedEntries = await _selectGlobalManifestEntries(
      context: context,
      entries: installableSources,
    );
    if (selectedEntries.isEmpty) {
      throw const FormatException('Source selection cancelled');
    }

    final candidates = await Future.wait(
      selectedEntries.map(
        (entry) => _downloadCandidateFromEntry(
          baseLink: link,
          dio: dio,
          entry: entry,
          l10n: l10n,
        ),
      ),
    );
    return candidates;
  }

  final manifest = _SourcePackageManifest.fromMap(manifestMap, l10n);
  final resolvedConfigUrl =
      Uri.parse(link).resolve(manifest.configPath).toString();
  final configResponse = await dio.get<String>(
    resolvedConfigUrl,
    options: Options(
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ),
  );

  final rawJson = configResponse.data;
  if (rawJson == null || rawJson.trim().isEmpty) {
    throw FormatException(l10n.sourceImportConfigEmpty);
  }

  final configBytes = utf8.encode(rawJson);
  _validateChecksum(
    contentBytes: configBytes,
    expectedSha256: manifest.checksumSha256,
    checksumMismatchMessage: l10n.sourceImportChecksumMismatch,
  );

  final configMap = _decodeJsonObject(
    rawJson: rawJson,
    invalidMessage: l10n.sourceImportManifestInvalid,
  );
  final sourceIdFromConfig = _requiredString(
    configMap,
    'source',
    l10n.sourceImportSourceMismatch,
  );
  if (sourceIdFromConfig != manifest.sourceId) {
    throw FormatException(l10n.sourceImportSourceMismatch);
  }

  return [
    _InstallCandidate(
      sourceId: manifest.sourceId,
      version: manifest.version,
      displayName: manifest.displayName,
      description: null,
      rawJson: rawJson,
      isVerified: true,
    )
  ];
}

Future<_InstallCandidate> _downloadCandidateFromEntry({
  required String baseLink,
  required Dio dio,
  required _GlobalManifestEntry entry,
  required AppLocalizations l10n,
}) async {
  final resolvedConfigUrl = Uri.parse(baseLink).resolve(entry.url).toString();
  final configResponse = await dio.get<String>(
    resolvedConfigUrl,
    options: Options(
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ),
  );

  final rawJson = configResponse.data;
  if (rawJson == null || rawJson.trim().isEmpty) {
    throw FormatException(l10n.sourceImportConfigEmpty);
  }

  var isVerified = false;
  final checksum = entry.checksumSha256;
  if (checksum != null && checksum.isNotEmpty) {
    final configBytes = utf8.encode(rawJson);
    _validateChecksum(
      contentBytes: configBytes,
      expectedSha256: checksum,
      checksumMismatchMessage: l10n.sourceImportChecksumMismatch,
    );
    isVerified = true;
  }

  final configMap = _decodeJsonObject(
    rawJson: rawJson,
    invalidMessage: l10n.sourceImportManifestInvalid,
  );
  final sourceIdFromConfig = _requiredString(
    configMap,
    'source',
    l10n.sourceImportSourceMismatch,
  );
  if (sourceIdFromConfig != entry.id) {
    throw FormatException(l10n.sourceImportSourceMismatch);
  }

  _attachManifestMetadata(
    configMap,
    displayName: entry.displayName,
    description: entry.description,
  );
  await _cacheIconForLinkCandidate(
    sourceId: entry.id,
    configMap: configMap,
    entryIconUrl: entry.iconUrl,
    baseLink: baseLink,
    dio: dio,
  );

  return _InstallCandidate(
    sourceId: entry.id,
    version: entry.version,
    displayName: entry.displayName,
    description: entry.description,
    rawJson: jsonEncode(configMap),
    isVerified: isVerified,
  );
}

Iterable<_GlobalManifestEntry> _parseGlobalManifestEntries(
    Map<String, dynamic> map, AppLocalizations l10n) sync* {
  final rawList = map['installableSources'];
  if (rawList is! List<dynamic>) return;

  for (final item in rawList) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    try {
      yield _GlobalManifestEntry.fromMap(item, l10n);
    } catch (e) {
      getIt<Logger>().w('Settings manifest parse failed', error: e);
      continue;
    }
  }
}

Future<List<_GlobalManifestEntry>> _selectGlobalManifestEntries({
  required BuildContext context,
  required List<_GlobalManifestEntry> entries,
}) async {
  if (entries.length == 1) {
    return entries;
  }

  final selected = <_GlobalManifestEntry>{};
  var searchQuery = '';
  final result = await showModalBottomSheet<List<_GlobalManifestEntry>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final theme = Theme.of(ctx);
        final query = searchQuery.trim().toLowerCase();
        final filtered = query.isEmpty
            ? entries
            : entries.where((entry) {
                final name =
                    (entry.displayName ?? entry.id).toLowerCase();
                return name.contains(query) ||
                    entry.id.toLowerCase().contains(query);
              }).toList(growable: false);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                      AppLocalizations.of(context)!.selectSourceFromManifest),
                  subtitle: Text(
                      AppLocalizations.of(context)!.chooseMultipleSources),
                  // ponytail: filtered-scoped toggle; select-all installs
                  // everything visible, tap again clears just that scope.
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
                    child: Text(filtered.isNotEmpty &&
                            filtered.every(selected.contains)
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
                      hintText: AppLocalizations.of(context)!
                          .sourceSelectorSearchHint,
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
                        borderRadius: BorderRadius.circular(
                            DesignTokens.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              AppLocalizations.of(context)!
                                  .sourceSelectorNoResults,
                              textAlign: TextAlign.center,
                              style: TextStyleConst.bodyMedium.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final entry = filtered[index];
                            final isSelected = selected.contains(entry);
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(entry.displayName ?? entry.id),
                              subtitle:
                                  Text('${entry.id} • v${entry.version}'),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => ctx.pop(const []),
                        child: Text(AppLocalizations.of(context)!.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => ctx.pop(
                                  entries
                                      .where(
                                          (entry) => selected.contains(entry))
                                      .toList(growable: false),
                                ),
                        child: Text(AppLocalizations.of(context)!
                            .installSelectedCount(selected.length)),
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

Future<List<_InstallCandidate>> _buildCandidateFromZip({
  required BuildContext context,
  required List<int> bytes,
  required AppLocalizations l10n,
}) async {
  final archive = ZipDecoder().decodeBytes(bytes);

  final manifestFile = archive.files.where((file) {
    if (!file.isFile) return false;
    final segments = file.name.split('/');
    final name = segments.isEmpty ? file.name : segments.last;
    return name.toLowerCase() == 'manifest.json';
  }).firstOrNull;

  if (manifestFile == null) {
    throw FormatException(l10n.sourceImportZipManifestRequired);
  }

  final manifestBytes = _archiveFileBytes(manifestFile);
  final manifestRaw = utf8.decode(manifestBytes);
  final manifestMap = _decodeJsonObject(
    rawJson: manifestRaw,
    invalidMessage: l10n.sourceImportManifestInvalid,
  );

  final installableSources =
      _parseGlobalManifestEntries(manifestMap, l10n).toList(growable: false);
  if (installableSources.isNotEmpty) {
    if (!context.mounted) {
      throw StateError('SettingsScreen is no longer mounted');
    }

    final selectedEntries = await _selectGlobalManifestEntries(
      context: context,
      entries: installableSources,
    );
    if (selectedEntries.isEmpty) {
      return const [];
    }

    final candidates = <_InstallCandidate>[];
    for (final selectedEntry in selectedEntries) {
      final configFile = _findConfigFileInArchive(
        archive: archive,
        targetPath: selectedEntry.url,
      );
      if (configFile == null) {
        continue;
      }

      final configBytes = _archiveFileBytes(configFile);
      final checksum = selectedEntry.checksumSha256;
      var isVerified = false;
      if (checksum != null && checksum.isNotEmpty) {
        _validateChecksum(
          contentBytes: configBytes,
          expectedSha256: checksum,
          checksumMismatchMessage: l10n.sourceImportChecksumMismatch,
        );
        isVerified = true;
      }

      final rawJson = utf8.decode(configBytes);
      final configMap = _decodeJsonObject(
        rawJson: rawJson,
        invalidMessage: l10n.sourceImportManifestInvalid,
      );
      final sourceIdFromConfig = _requiredString(
        configMap,
        'source',
        l10n.sourceImportSourceMismatch,
      );
      if (sourceIdFromConfig != selectedEntry.id) {
        continue;
      }

      _attachManifestMetadata(
        configMap,
        displayName: selectedEntry.displayName,
        description: selectedEntry.description,
      );
      await _cacheIconForZipCandidate(
        sourceId: selectedEntry.id,
        configMap: configMap,
        archive: archive,
        entryIconUrl: selectedEntry.iconUrl,
      );

      candidates.add(
        _InstallCandidate(
          sourceId: selectedEntry.id,
          version: selectedEntry.version,
          displayName: selectedEntry.displayName,
          description: selectedEntry.description,
          rawJson: jsonEncode(configMap),
          isVerified: isVerified,
        ),
      );
    }

    return candidates;
  }

  if (manifestMap.containsKey('source')) {
    final sourceId = _requiredString(
      manifestMap,
      'source',
      l10n.sourceImportSourceMismatch,
    );
    final version = (manifestMap['version'] as String?)?.trim() ?? 'unknown';
    return [
      _InstallCandidate(
        sourceId: sourceId,
        version: version,
        displayName: null,
        description: null,
        rawJson: manifestRaw,
        isVerified: false,
      ),
    ];
  }

  final manifest = _SourcePackageManifest.fromMap(manifestMap, l10n);

  final configFile = _findConfigFileInArchive(
    archive: archive,
    targetPath: manifest.configPath,
  );

  if (configFile == null) {
    throw FormatException(l10n.sourceImportManifestInvalid);
  }

  final configBytes = _archiveFileBytes(configFile);
  if (manifest.checksumSha256.isNotEmpty) {
    _validateChecksum(
      contentBytes: configBytes,
      expectedSha256: manifest.checksumSha256,
      checksumMismatchMessage: l10n.sourceImportChecksumMismatch,
    );
  }

  final rawJson = utf8.decode(configBytes);
  final configMap = _decodeJsonObject(
    rawJson: rawJson,
    invalidMessage: l10n.sourceImportManifestInvalid,
  );
  final sourceIdFromConfig = _requiredString(
    configMap,
    'source',
    l10n.sourceImportSourceMismatch,
  );

  if (sourceIdFromConfig != manifest.sourceId) {
    throw FormatException(l10n.sourceImportSourceMismatch);
  }

  return [
    _InstallCandidate(
      sourceId: manifest.sourceId,
      version: manifest.version,
      displayName: manifest.displayName,
      description: null,
      rawJson: rawJson,
      isVerified: manifest.checksumSha256.isNotEmpty,
    ),
  ];
}

void _attachManifestMetadata(
  Map<String, dynamic> configMap, {
  String? displayName,
  String? description,
}) {
  final meta = (configMap['meta'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};

  if (displayName != null && displayName.trim().isNotEmpty) {
    meta['displayName'] = displayName.trim();
  }
  if (description != null && description.trim().isNotEmpty) {
    meta['description'] = description.trim();
  }

  if (meta.isNotEmpty) {
    configMap['meta'] = meta;
  }
}

Future<void> _cacheIconForZipCandidate({
  required String sourceId,
  required Map<String, dynamic> configMap,
  required Archive archive,
  String? entryIconUrl,
}) async {
  final configIconPath = _readConfigIconPath(configMap);
  final candidatePath = (entryIconUrl != null && entryIconUrl.trim().isNotEmpty)
      ? entryIconUrl.trim()
      : configIconPath;
  if (candidatePath == null || candidatePath.isEmpty) {
    return;
  }

  final iconFile = _findConfigFileInArchive(
    archive: archive,
    targetPath: candidatePath,
  );
  if (iconFile == null) {
    return;
  }

  final iconBytes = _archiveFileBytes(iconFile);
  final localPath = await _persistSourceIconBytes(
    sourceId: sourceId,
    iconBytes: iconBytes,
    originalPath: candidatePath,
  );
  if (localPath != null) {
    _setConfigIconPath(configMap, localPath);
  }
}

Future<void> _cacheIconForLinkCandidate({
  required String sourceId,
  required Map<String, dynamic> configMap,
  required String baseLink,
  required Dio dio,
  String? entryIconUrl,
}) async {
  final configIconPath = _readConfigIconPath(configMap);
  final candidatePath = (entryIconUrl != null && entryIconUrl.trim().isNotEmpty)
      ? entryIconUrl.trim()
      : configIconPath;
  if (candidatePath == null || candidatePath.isEmpty) {
    return;
  }

  final iconUri = Uri.tryParse(candidatePath);
  final isAbsoluteHttp = iconUri != null &&
      (iconUri.scheme == 'http' || iconUri.scheme == 'https');
  final resolvedUrl = isAbsoluteHttp
      ? candidatePath
      : Uri.parse(baseLink).resolve(candidatePath).toString();

  try {
    final response = await dio.get<List<int>>(
      resolvedUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    final localPath = await _persistSourceIconBytes(
      sourceId: sourceId,
      iconBytes: bytes,
      originalPath: candidatePath,
    );
    if (localPath != null) {
      _setConfigIconPath(configMap, localPath);
    }
  } catch (e, stackTrace) {
    Logger().w(
      'Failed to cache icon for $sourceId from $resolvedUrl',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

String? _readConfigIconPath(Map<String, dynamic> configMap) {
  final rawTopLevel = configMap['iconPath'] as String?;
  if (rawTopLevel != null && rawTopLevel.trim().isNotEmpty) {
    return rawTopLevel.trim();
  }

  final uiMap = (configMap['ui'] as Map?)?.cast<String, dynamic>();
  final rawUi = uiMap?['iconPath'] as String?;
  if (rawUi != null && rawUi.trim().isNotEmpty) {
    return rawUi.trim();
  }
  return null;
}

void _setConfigIconPath(Map<String, dynamic> configMap, String localPath) {
  configMap['iconPath'] = localPath;

  final uiMap =
      (configMap['ui'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  uiMap['iconPath'] = localPath;
  configMap['ui'] = uiMap;
}

Future<String?> _persistSourceIconBytes({
  required String sourceId,
  required List<int> iconBytes,
  required String originalPath,
}) async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final iconDir = Directory(p.join(appDir.path, 'source_icons'));
    if (!await iconDir.exists()) {
      await iconDir.create(recursive: true);
    }

    final extension = _resolveImageExtension(originalPath);
    final filePath = p.join(iconDir.path, '$sourceId$extension');
    final iconFile = File(filePath);
    await iconFile.writeAsBytes(iconBytes, flush: true);
    return filePath;
  } catch (e, stackTrace) {
    Logger().w(
      'Failed to persist local icon for $sourceId',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

String _resolveImageExtension(String pathOrUrl) {
  final uri = Uri.tryParse(pathOrUrl);
  final rawPath = (uri?.path.isNotEmpty == true) ? uri!.path : pathOrUrl;
  final ext = p.extension(rawPath).toLowerCase();
  switch (ext) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.webp':
    case '.gif':
    case '.svg':
      return ext;
    default:
      return '.png';
  }
}

ArchiveFile? _findConfigFileInArchive({
  required Archive archive,
  required String targetPath,
}) {
  final target = targetPath.replaceAll('\\', '/').toLowerCase();
  return archive.files.where((file) {
    if (!file.isFile) return false;
    final normalized = file.name.replaceAll('\\', '/').toLowerCase();
    return normalized == target || normalized.endsWith('/$target');
  }).firstOrNull;
}

Future<bool> _showInstallPreviewDialog(
    BuildContext context, _InstallCandidate candidate) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final l10n = AppLocalizations.of(context)!;
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
          Text('${l10n.sourceImportPreviewVersion}: ${candidate.version}',
              style: TextStyle(color: cs.onSurface)),
          if (candidate.displayName != null &&
              candidate.displayName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
                '${l10n.sourceImportPreviewDisplayName}: ${candidate.displayName}',
                style: TextStyle(color: cs.onSurface)),
          ],
          const SizedBox(height: 6),
          Text(
            '${l10n.sourceImportPreviewVerified}: ${candidate.isVerified ? l10n.sourceImportPreviewVerifiedYes : l10n.sourceImportPreviewVerifiedNo}',
            style: TextStyle(color: cs.onSurface),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => ctx.pop(true),
          child: Text(l10n.sourceImportConfirmInstall),
        ),
      ],
    ),
  );

  return result ?? false;
}

Future<bool> _showBatchInstallPreviewDialog(
    BuildContext context, List<_InstallCandidate> candidates) async {
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
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, index) {
                  final candidate = candidates[index];
                  return Text(
                    '- ${candidate.displayName ?? candidate.sourceId} (v${candidate.version})',
                    style: TextStyle(color: cs.onSurface),
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

Map<String, dynamic> _decodeJsonObject({
  required String rawJson,
  required String invalidMessage,
}) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException(invalidMessage);
  }
  return decoded;
}

String _requiredString(
    Map<String, dynamic> map, String key, String errorMessage) {
  final value = map[key] as String?;
  if (value == null || value.trim().isEmpty) {
    throw FormatException(errorMessage);
  }
  return value.trim();
}

List<int> _archiveFileBytes(ArchiveFile file) {
  return file.content;
}

void _validateChecksum({
  required List<int> contentBytes,
  required String expectedSha256,
  required String checksumMismatchMessage,
}) {
  final actual = sha256.convert(contentBytes).toString().toLowerCase();
  if (actual != expectedSha256.toLowerCase()) {
    throw FormatException(checksumMismatchMessage);
  }
}

class _SourcePackageManifest {
  const _SourcePackageManifest({
    required this.schemaVersion,
    required this.sourceId,
    required this.version,
    required this.configPath,
    required this.checksumSha256,
    required this.displayName,
  });

  final int schemaVersion;
  final String sourceId;
  final String version;
  final String configPath;
  final String checksumSha256;
  final String? displayName;

  static _SourcePackageManifest fromMap(
      Map<String, dynamic> map, AppLocalizations l10n) {
    final rawSchemaVersion = map['schemaVersion'];
    final schemaVersion = rawSchemaVersion is int ? rawSchemaVersion : 1;

    String readAnyString(List<String> keys, {bool required = true}) {
      for (final key in keys) {
        final value = map[key] as String?;
        if (value != null && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      if (!required) return '';
      throw FormatException(l10n.sourceImportManifestInvalid);
    }

    String normalizeConfigPath(String rawPath) {
      if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
        final uri = Uri.tryParse(rawPath);
        if (uri != null && uri.path.isNotEmpty) {
          rawPath = uri.path;
        }
      }

      var normalized = rawPath.replaceAll('\\', '/').trim();
      while (normalized.startsWith('/')) {
        normalized = normalized.substring(1);
      }
      if (normalized.startsWith('./')) {
        normalized = normalized.substring(2);
      }
      return normalized;
    }

    final sourceId = readAnyString(const ['sourceId', 'id', 'source']);
    final version = readAnyString(const ['version']);
    final configPathRaw = readAnyString(const ['configPath', 'path', 'url']);
    final checksum = readAnyString(
      const ['checksumSha256', 'checksum'],
      required: false,
    );

    return _SourcePackageManifest(
      schemaVersion: schemaVersion,
      sourceId: sourceId,
      version: version,
      configPath: normalizeConfigPath(configPathRaw),
      checksumSha256: checksum,
      displayName: (map['displayName'] as String?)?.trim(),
    );
  }
}

class _InstallCandidate {
  const _InstallCandidate({
    required this.sourceId,
    required this.version,
    required this.displayName,
    required this.description,
    required this.rawJson,
    required this.isVerified,
  });

  final String sourceId;
  final String version;
  final String? displayName;
  final String? description;
  final String rawJson;
  final bool isVerified;
}

class _GlobalManifestEntry {
  const _GlobalManifestEntry({
    required this.id,
    required this.version,
    required this.url,
    required this.checksumSha256,
    required this.displayName,
    required this.description,
    required this.iconUrl,
  });

  final String id;
  final String version;
  final String url;
  final String? checksumSha256;
  final String? displayName;
  final String? description;
  final String? iconUrl;

  static _GlobalManifestEntry fromMap(
      Map<String, dynamic> map, AppLocalizations l10n) {
    String readRequired(String key) {
      final value = map[key] as String?;
      if (value == null || value.trim().isEmpty) {
        throw FormatException(l10n.sourceImportManifestInvalid);
      }
      return value.trim();
    }

    final meta = map['meta'];
    String? displayName;
    String? description;
    String? iconUrl;
    if (meta is Map<String, dynamic>) {
      displayName = (meta['displayName'] as String?)?.trim();
      description = (meta['description'] as String?)?.trim();
      iconUrl = (meta['iconUrl'] as String?)?.trim();
    }

    return _GlobalManifestEntry(
      id: readRequired('id'),
      version: readRequired('version'),
      url: readRequired('url'),
      checksumSha256: (map['checksum'] as String?)?.trim(),
      displayName: displayName,
      description: description,
      iconUrl: iconUrl,
    );
  }
}
