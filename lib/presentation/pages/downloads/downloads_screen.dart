import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';

import '../../../core/constants/text_style_const.dart';
import '../../../core/routing/app_route.dart';
import '../../../core/routing/reader_route_extra.dart';
import '../../../core/utils/storage_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../domain/entities/entities.dart';
import '../../blocs/download/download_bloc.dart';
import '../../widgets/widgets.dart';
import '../../widgets/app_scaffold_with_offline.dart';
import '../../widgets/permission_request_sheet.dart';
import '../../widgets/kuron_fx.dart';

// Screen for managing downloads with status tracking and progress indicators
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _permissionsChecked = false;

  /// Label render boxes for the wordless tab-switch beat. Keys are stable so
  /// the post-frame callback can capture the selected label's rect.
  final List<GlobalKey> _tabKeys = List.generate(5, (_) => GlobalKey());

  void _onTabTap(int index) {
    // The indicator settles after the tap frame; capture the label there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _tabKeys[index].currentContext;
      if (tabContext == null) return;
      final rect = KuronFx.targetRectOf(tabContext);
      if (rect == null) return;
      KuronFx.triggerOn(context, rect: rect, kind: KuronFxKind.tabSwitch);
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    // Check permissions before initializing downloads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndInitialize();
    });
  }

  Future<void> _checkPermissionsAndInitialize() async {
    if (!mounted || _permissionsChecked) return;

    // Always request storage + notification permissions first
    final hasPermissions = await showPermissionRequestSheet(
      context,
      requireStorage: true,
      requireNotification: true,
    );
    if (!mounted) return;

    if (!hasPermissions) {
      _showSnackBar(AppLocalizations.of(context)!.permissionDenied);
    }

    // Warn if storage root not set
    final hasCustomRoot = await StorageSettings.hasCustomRoot();
    if (!mounted) return;

    if (!hasCustomRoot) {
      _showStorageLocationRequiredSnackBar();
    }

    if (!mounted) return;

    setState(() {
      _permissionsChecked = true;
    });

    // Initialize download manager even when notification permission is denied.
    // Custom download root is the storage source of truth; full storage access
    // should not block users from viewing existing download state.
    final downloadBloc = context.read<DownloadBloc>();
    if (downloadBloc.state is DownloadInitial) {
      downloadBloc.add(const DownloadInitializeEvent());
    }
  }

  Future<bool> _ensureCustomStorageRoot() async {
    final hasCustomRoot = await StorageSettings.hasCustomRoot();
    if (!mounted) return false;
    if (!hasCustomRoot) {
      _showStorageLocationRequiredSnackBar();
      return false;
    }
    return true;
  }

  void _showStorageLocationRequiredSnackBar() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.pleaseSetStorageLocation),
        backgroundColor: Theme.of(context).colorScheme.error,
        action: SnackBarAction(
          label: l10n.settings,
          textColor: Theme.of(context).colorScheme.onError,
          onPressed: () => context.push(AppRoute.settings),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppScaffoldWithOffline(
      title: AppLocalizations.of(context)!.downloads,
      backgroundColor: colorScheme.surface,
      drawer: AppMainDrawerWidget(context: context),
      appBar: _buildAppBar(), // Use custom AppBar with menu actions
      body: BlocConsumer<DownloadBloc, DownloadBlocState>(
        listener: (context, state) {
          if (state is DownloadError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
                action: state.canRetry
                    ? SnackBarAction(
                        label: AppLocalizations.of(context)!.retryAction,
                        textColor: colorScheme.onError,
                        onPressed: () {
                          context.read<DownloadBloc>().add(
                            const DownloadRefreshEvent(),
                          );
                        },
                      )
                    : null,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is DownloadInitial || state is DownloadInitializing) {
            return Center(
              child: AppProgressIndicator(
                message: AppLocalizations.of(context)!.initializingDownloads,
              ),
            );
          }

          if (state is DownloadError) {
            if (state.previousState is DownloadLoaded) {
              return _buildLoadedContent(state.previousState as DownloadLoaded);
            }
            // If no previous loaded state, show error widget
            if (state.previousState == null) {
              return AppErrorWidget(
                title: AppLocalizations.of(context)!.downloadError,
                message: state.message,
                onRetry: state.canRetry
                    ? () => context.read<DownloadBloc>().add(
                        const DownloadInitializeEvent(),
                      )
                    : null,
              );
            }
          }

          if (state is DownloadLoaded) {
            return _buildLoadedContent(state);
          }

          return Center(
            child: AppProgressIndicator(
              message: AppLocalizations.of(context)!.loadingDownloads,
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + kTextTabBarHeight),
      child: BlocBuilder<DownloadBloc, DownloadBlocState>(
        builder: (context, state) {
          if (state is! DownloadLoaded) {
            return AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              title: Text(
                AppLocalizations.of(context)!.downloads,
                style: TextStyleConst.headlineMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            );
          }

          // Selection mode AppBar
          if (state.isSelectionMode) {
            return AppBar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.read<DownloadBloc>().add(
                  const DownloadSelectionActionEvent(
                    SelectionAction.toggleSelectionMode,
                  ),
                ),
              ),
              title: Text(
                AppLocalizations.of(context)!
                    .nSelected(state.selectedItems.length),
                style: TextStyleConst.headlineSmall.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              actions: [
                if (state.selectedItems.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: () => context.read<DownloadBloc>().add(
                      const DownloadSelectionActionEvent(
                        SelectionAction.selectAll,
                      ),
                    ),
                    tooltip: AppLocalizations.of(context)!.selectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => context.read<DownloadBloc>().add(
                      const DownloadSelectionActionEvent(
                        SelectionAction.clearSelection,
                      ),
                    ),
                    tooltip: AppLocalizations.of(context)!.clearSelection,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _showBulkDeleteDialog(state),
                    tooltip: AppLocalizations.of(context)!.delete,
                  ),
                ],
              ],
            );
          }

          // Normal AppBar
          return AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            title: Text(
              AppLocalizations.of(context)!.downloads,
              style: TextStyleConst.headlineMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            actions: [
              // ✅ NEW: Manual Refresh Button
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  context.read<DownloadBloc>().add(
                    const DownloadRefreshEvent(),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.refreshingDownloads,
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                tooltip: AppLocalizations.of(context)!.refresh,
              ),
              IconButton(
                icon: const Icon(Icons.checklist),
                onPressed: () => context.read<DownloadBloc>().add(
                  const DownloadSelectionActionEvent(
                    SelectionAction.toggleSelectionMode,
                  ),
                ),
                tooltip: AppLocalizations.of(context)!.selectMode,
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                color: Theme.of(context).colorScheme.surface,
                onSelected: (value) => _handleMenuAction(value, state),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'pause_all',
                    enabled:
                        state.downloads.any(
                          (d) => d.state == DownloadState.downloading,
                        ) ||
                        state.downloads.any(
                          (d) => d.state == DownloadState.queued,
                        ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pause,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.pauseAll,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'resume_all',
                    enabled: state.downloads.any(
                      (d) => d.state == DownloadState.paused,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.resumeAll,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'cancel_all',
                    enabled: state.downloads.any((d) => d.canCancel),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.cancelAll,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'clear_completed',
                    enabled: state.downloads.any(
                      (d) => d.state == DownloadState.completed,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.clear_all,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.clearCompleted,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'cleanup_storage',
                    child: Row(
                      children: [
                        Icon(
                          Icons.cleaning_services,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.cleanupStorage,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(
                          Icons.file_download,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.exportList,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              onTap: _onTabTap,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.6),
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: [
                Tab(key: _tabKeys[0], text: AppLocalizations.of(context)!.all),
                Tab(
                  key: _tabKeys[1],
                  text: AppLocalizations.of(context)!.active,
                ),
                Tab(
                  key: _tabKeys[2],
                  text: AppLocalizations.of(context)!.queued,
                ),
                Tab(
                  key: _tabKeys[3],
                  text: AppLocalizations.of(context)!.completed,
                ),
                Tab(
                  key: _tabKeys[4],
                  text: AppLocalizations.of(context)!.failed,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadedContent(DownloadLoaded state) {
    return Column(
      children: [
        // Download stats
        DownloadStatsWidget(state: state),

        // Downloads list
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDownloadsList(
                state.downloads,
                AppLocalizations.of(context)!.noDownloadsYet,
              ),
              _buildDownloadsList(
                state.downloads
                    .where((d) => d.state == DownloadState.downloading)
                    .toList(),
                AppLocalizations.of(context)!.noActiveDownloads,
              ),
              _buildDownloadsList(
                state.downloads
                    .where((d) => d.state == DownloadState.queued)
                    .toList(),
                AppLocalizations.of(context)!.noQueuedDownloads,
              ),
              _buildDownloadsList(
                state.downloads
                    .where((d) => d.state == DownloadState.completed)
                    .toList(),
                AppLocalizations.of(context)!.noCompletedDownloads,
              ),
              _buildDownloadsList(
                state.downloads
                    .where((d) => d.state == DownloadState.failed)
                    .toList(),
                AppLocalizations.of(context)!.noFailedDownloads,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsList(
    List<DownloadStatus> downloads,
    String emptyMessage,
  ) {
    return BlocBuilder<DownloadBloc, DownloadBlocState>(
      builder: (context, state) {
        if (downloads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  emptyMessage,
                  style: TextStyleConst.bodyLarge.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        final isSelectionMode =
            state is DownloadLoaded && state.isSelectionMode;

        return RefreshIndicator(
          onRefresh: () async {
            context.read<DownloadBloc>().add(const DownloadRefreshEvent());
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final download = downloads[index];
              final isSelected =
                  state is DownloadLoaded &&
                  state.selectedItems.contains(download.contentId);

              return DownloadItemWidget(
                download: download,
                onTap: () => _handleDownloadTap(download),
                onAction: (action) => _handleDownloadAction(action, download),
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
              );
            },
          ),
        );
      },
    );
  }

  void _handleMenuAction(String action, DownloadLoaded state) {
    final downloadBloc = context.read<DownloadBloc>();

    switch (action) {
      case 'pause_all':
        downloadBloc.add(const DownloadBulkActionEvent(BulkAction.pauseAll));
        break;
      case 'resume_all':
        downloadBloc.add(const DownloadBulkActionEvent(BulkAction.resumeAll));
        break;
      case 'cancel_all':
        _showCancelAllDialog();
        break;
      case 'clear_completed':
        downloadBloc.add(
          const DownloadBulkActionEvent(BulkAction.clearCompleted),
        );
        break;
      case 'cleanup_storage':
        _showCleanupDialog();
        break;
      case 'export':
        downloadBloc.add(const DownloadExportEvent());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.downloadListExported),
          ),
        );
        break;
    }
  }

  void _handleDownloadTap(DownloadStatus download) {
    final downloadBloc = context.read<DownloadBloc>();
    final currentState = downloadBloc.state;

    if (currentState is DownloadLoaded && currentState.isSelectionMode) {
      // In selection mode, toggle selection
      final isSelected = currentState.selectedItems.contains(
        download.contentId,
      );
      downloadBloc.add(
        DownloadSelectionActionEvent(
          SelectionAction.selectItem,
          contentId: download.contentId,
          isSelected: !isSelected,
        ),
      );
    } else {
      // Normal mode behavior
      if (download.isCompleted) {
        // Navigate to reader if download is completed
        // Create Content object from offline data asynchronously
        _navigateToReader(download);
      } else {
        // Show download details
        _showDownloadDetails(download);
      }
    }
  }

  Future<void> _navigateToReader(DownloadStatus download) async {
    // 🚀 OFFLINE-FIRST: Preload content from OfflineContentManager
    // This ensures the reader screen receives fully-populated Content with local imageUrls.
    // IMPORTANT: Always wrap in buildReaderRouteExtra() so ReaderScreen can parse
    // preloadedContent correctly (expects Map<String, dynamic>, not a raw Content object).

    if (!mounted) return;

    final offlineManager = getIt<OfflineContentManager>();

    // Try to get offline content directly - more robust than checking DB status first
    // This handles cases where DB might be out of sync
    try {
      final offlineContent = await offlineManager.createOfflineContent(
        download.contentId,
      );

      if (offlineContent != null && offlineContent.imageUrls.isNotEmpty) {
        // ✅ Offline content loaded successfully, navigate with properly-wrapped data
        if (!mounted) return;
        final encodedContentId = Uri.encodeComponent(download.contentId);
        await context.push(
          '/reader/$encodedContentId?fromOffline=true',
          extra: buildReaderRouteExtra(
            content: offlineContent,
            fromOffline: true,
          ),
        );
        return;
      }
    } catch (e) {
      //  assert-only debug logging — intentional, class has no _logger
    }

    // Fallback: Build a minimal Content so ReaderCubit can handle loading
    // via Strategy B (offline) or Strategy C (online fallback)
    final content = Content(
      id: download.contentId,
      title: download.title ?? download.contentId,
      coverUrl: download.coverUrl ?? '',
      pageCount: download.totalPages,
      imageUrls: [], // Empty — ReaderCubit will load from offline or network
      sourceId: download.sourceId ?? 'nhentai', // Default fallback
      // Required empty fields
      uploadDate: DateTime.now(),
      tags: [],
      artists: [],
      characters: [],
      groups: [],
      parodies: [],
      language: '',
      favorites: 0,
    );

    if (!mounted) return;
    final encodedContentId = Uri.encodeComponent(download.contentId);
    await context.push(
      '/reader/$encodedContentId?fromOffline=true',
      extra: buildReaderRouteExtra(content: content, fromOffline: true),
    );
  }

  void _handleDownloadAction(
    String action,
    DownloadStatus download, {
    String? sourceId,
  }) {
    final downloadBloc = context.read<DownloadBloc>();

    switch (action) {
      case 'start':
        downloadBloc.add(DownloadStartEvent(download.contentId));
        break;
      case 'pause':
        downloadBloc.add(DownloadPauseEvent(download.contentId));
        break;
      case 'cancel':
        _showCancelDialog(download);
        break;
      case 'retry':
        downloadBloc.add(DownloadRetryEvent(download.contentId));
        break;
      case 'remove':
        _showRemoveDialog(download);
        break;
      case 'details':
        _showDownloadDetails(download);
        break;
      case 'convert_pdf':
        // Check permissions before PDF conversion
        _handlePdfConversion(download);
        break;
      case 'open_pdf':
        // Check feature flag
        final remoteConfig = getIt<RemoteConfigService>();
        // Offline content always has sourceId
        final isEnabled = remoteConfig.isFeatureEnabled(
          sourceId ?? SourceType.nhentai.id,
          (f) => f.generatePdf,
        );

        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.premiumFeature),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          break;
        }
        downloadBloc.add(DownloadOpenContentEvent(download.contentId));
        break;
    }
  }

  Future<void> _handlePdfConversion(DownloadStatus download) async {
    // Check feature flag first
    final remoteConfig = getIt<RemoteConfigService>();
    final isEnabled = remoteConfig.isFeatureEnabled(
      download.sourceId ?? SourceType.nhentai.id,
      (f) => f.generatePdf,
    );

    if (!isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.premiumFeature),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final hasCustomRoot = await _ensureCustomStorageRoot();
    if (!hasCustomRoot || !mounted) return;

    // Check runtime permissions before starting PDF conversion.
    // Requires MANAGE_EXTERNAL_STORAGE to write to user-selected SAF directory.
    final hasPermissions = await showPermissionRequestSheet(
      context,
      requireStorage: true,
      requireNotification: true,
    );

    if (!mounted || !hasPermissions) {
      if (mounted && !hasPermissions) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.permissionDenied),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Trigger PDF conversion
    if (!mounted) return;
    final downloadBloc = context.read<DownloadBloc>();
    downloadBloc.add(DownloadConvertToPdfEvent(download.contentId));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!
                .pdfConversionStarted(download.contentId),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCancelAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          AppLocalizations.of(context)!.cancelAllDownloads,
          style: TextStyleConst.headlineSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.cancelAllConfirmation,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              context.read<DownloadBloc>().add(
                const DownloadBulkActionEvent(BulkAction.cancelAll),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.cancelAll,
              style: TextStyleConst.labelLarge.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(DownloadStatus download) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          AppLocalizations.of(context)!.cancelDownload,
          style: TextStyleConst.headlineSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.cancelDownloadConfirmation,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              context.read<DownloadBloc>().add(
                DownloadCancelEvent(download.contentId),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.cancelDownload,
              style: TextStyleConst.labelLarge.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(DownloadStatus download) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          AppLocalizations.of(context)!.removeDownload,
          style: TextStyleConst.headlineSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.removeDownloadConfirmation,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              context.read<DownloadBloc>().add(
                DownloadRemoveEvent(download.contentId),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.remove,
              style: TextStyleConst.labelLarge.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCleanupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          AppLocalizations.of(context)!.cleanupStorage,
          style: TextStyleConst.headlineSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!.cleanupConfirmation,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              context.read<DownloadBloc>().add(
                const DownloadCleanupStorageEvent(),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.cleanup,
              style: TextStyleConst.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  void _showBulkDeleteDialog(DownloadLoaded state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          AppLocalizations.of(context)!.bulkDelete,
          style: TextStyleConst.headlineSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          AppLocalizations.of(context)!
              .bulkDeleteConfirmation(state.selectedItems.length),
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyleConst.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              context.read<DownloadBloc>().add(
                DownloadBulkDeleteEvent(state.selectedItems.toList()),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.delete,
              style: TextStyleConst.labelLarge.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadDetails(DownloadStatus download) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.downloadDetails,
                style: TextStyleConst.headlineSmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow(
                AppLocalizations.of(context)!.status,
                download.statusText,
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.progress,
                _buildProgressText(download),
              ),
              _buildDetailRow(
                AppLocalizations.of(context)!.progressPercent,
                '${(download.progressPercentage > 100) ? '100' : download.progressPercentage}%',
              ),
              if (download.speed > 0)
                _buildDetailRow(
                  AppLocalizations.of(context)!.speed,
                  download.formattedSpeed,
                ),
              if (download.fileSize > 0)
                _buildDetailRow(
                  AppLocalizations.of(context)!.size,
                  download.formattedFileSize,
                ),
              if (download.startTime != null)
                _buildDetailRow(
                  AppLocalizations.of(context)!.started,
                  _formatDateTime(download.startTime!),
                ),
              if (download.endTime != null)
                _buildDetailRow(
                  AppLocalizations.of(context)!.ended,
                  _formatDateTime(download.endTime!),
                ),
              if (download.downloadDuration != null)
                _buildDetailRow(
                  AppLocalizations.of(context)!.duration,
                  _formatDuration(download.downloadDuration!),
                ),
              if (download.estimatedTimeRemaining != null)
                _buildDetailRow(
                  AppLocalizations.of(context)!.eta,
                  _formatDuration(download.estimatedTimeRemaining!),
                ),
              if (download.error != null)
                _buildDetailRow(
                  AppLocalizations.of(context)!.error,
                  download.error!,
                  isError: true,
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      AppLocalizations.of(context)!.close,
                      style: TextStyleConst.labelLarge,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyleConst.labelMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyleConst.bodySmall.copyWith(
                color: isError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    // Use localized date format - DD/MM/YYYY HH:MM
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${AppLocalizations.of(context)!.hours(hours)} ${AppLocalizations.of(context)!.minutes(minutes)} ${AppLocalizations.of(context)!.seconds(seconds)}';
    } else if (minutes > 0) {
      return '${AppLocalizations.of(context)!.minutes(minutes)} ${AppLocalizations.of(context)!.seconds(seconds)}';
    } else {
      return AppLocalizations.of(context)!.seconds(seconds);
    }
  }

  String _buildProgressText(DownloadStatus download) {
    if (download.isRangeDownload) {
      // For range downloads, show: "X/Y pages (Pages A-B of C)"
      final loc = AppLocalizations.of(context)!;
      return '${download.downloadedPages}/${download.pagesToDownload} ${loc.pages} (${loc.rangeLabel} ${download.startPage}-${download.endPage} ${loc.ofWord} ${download.totalPages})';
    } else {
      // For full downloads, show: "X/Y pages"
      final loc = AppLocalizations.of(context)!;
      return '${download.downloadedPages}/${download.totalPages} ${loc.pages}';
    }
  }
}
