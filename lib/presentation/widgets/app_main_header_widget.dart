import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

import '../../core/constants/text_style_const.dart';
import '../../core/config/remote_config_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/routing/app_router.dart';
import 'random_gallery_button.dart';

class AppMainHeaderWidget extends StatelessWidget
    implements PreferredSizeWidget {
  final bool isOffline;
  final VoidCallback? onRefresh;
  final VoidCallback? onImport;
  final VoidCallback? onImportZip;
  final VoidCallback? onExport;
  final Future<Map<String, dynamic>>? offlineStats;
  final String? title;
  final String? sourceId; // For feature flag checking
  final bool isListMode;
  final VoidCallback? onToggleViewMode;

  const AppMainHeaderWidget({
    super.key,
    this.onSearchPressed,
    this.onOpenBrowser,
    this.onDownloadAll,
    this.isOffline = false,
    this.onRefresh,
    this.onImport,
    this.onImportZip,
    this.onExport,
    this.offlineStats,
    this.title,
    this.sourceId, // Optional sourceId for feature checking
    this.isListMode = false,
    this.onToggleViewMode,
  });

  final VoidCallback? onSearchPressed;
  final VoidCallback? onOpenBrowser;
  final VoidCallback? onDownloadAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      // No explicit hamburger: AppBar auto-implies the drawer button when
      // the Scaffold has a drawer (mobile) and hides it on desktop where
      // the sidebar is permanent. Back navigation still auto-implies.
      actions: isOffline
          ? [
              // Offline Stats
              if (offlineStats != null)
                FutureBuilder<Map<String, dynamic>>(
                  future: offlineStats,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final stats = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${stats['totalContent']} items',
                                style: TextStyleConst.bodySmall.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                stats['formattedSize'] ?? '',
                                style: TextStyleConst.bodySmall.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              // View Mode Toggle
              if (onToggleViewMode != null)
                IconButton(
                  onPressed: onToggleViewMode,
                  icon: Icon(
                    isListMode ? Icons.grid_view : Icons.view_list,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  tooltip: isListMode ? 'Grid View' : 'List View',
                ),
              // More Actions Menu
              if (onRefresh != null ||
                  onImport != null ||
                  onImportZip != null ||
                  onExport != null)
                PopupMenuButton<String>(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  icon: Icon(
                    Icons.more_vert,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onSelected: (String item) {
                    switch (item) {
                      case 'refresh':
                        if (onRefresh != null) onRefresh!();
                        break;
                      case 'import':
                        if (onImport != null) onImport!();
                        break;
                      case 'import_zip':
                        if (onImportZip != null) onImportZip!();
                        break;
                      case 'export':
                        if (onExport != null) onExport!();
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      if (onRefresh != null)
                        PopupMenuItem<String>(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(
                                Icons.sync,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)!.syncRefresh,
                                style: TextStyleConst.bodyMedium.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (onImport != null)
                        PopupMenuItem<String>(
                          value: 'import',
                          child: Row(
                            children: [
                              Icon(
                                Icons.create_new_folder_outlined,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)!.importFromBackup,
                                style: TextStyleConst.bodyMedium.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (onImportZip != null)
                        PopupMenuItem<String>(
                          value: 'import_zip',
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_zip,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)!.importZipFile,
                                style: TextStyleConst.bodyMedium.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (onExport != null)
                        PopupMenuItem<String>(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(
                                Icons.file_upload,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context)!.exportLibrary,
                                style: TextStyleConst.bodyMedium.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ];
                  },
                ),
            ]
          : [
              IconButton(
                onPressed:
                    onSearchPressed ??
                    () {
                      // Navigate to dedicated SearchScreen
                      AppRouter.goToSearch(context);
                    },
                color: Theme.of(context).colorScheme.onSurface,
                icon: const Icon(Icons.search),
                tooltip: l10n.search,
              ),
              const RandomGalleryButton(),
              PopupMenuButton<String>(
                color: Theme.of(context).colorScheme.surfaceContainer,
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onSelected: (String item) {
                  switch (item) {
                    case 'opob':
                      if (onOpenBrowser != null) {
                        onOpenBrowser!();
                      }
                      break;
                    case 'download-all':
                      // Check feature flag before downloading
                      if (sourceId != null) {
                        final remoteConfig = getIt<RemoteConfigService>();
                        if (!remoteConfig.isFeatureEnabled(
                          sourceId!,
                          (f) => f.download,
                        )) {
                          _showFeatureDisabledDialog(context);
                          return;
                        }
                      }
                      if (onDownloadAll != null) {
                        onDownloadAll!();
                      }
                      break;
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<String>(
                      value: 'opob',
                      child: Text(
                        l10n.openInBrowser,
                        style: TextStyleConst.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ],
      title: Text(
        title ?? l10n.appTitle,
        style: TextStyleConst.headingMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _showFeatureDisabledDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.featureDisabledTitle),
        content: Text(l10n.downloadFeatureDisabled),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }
}
