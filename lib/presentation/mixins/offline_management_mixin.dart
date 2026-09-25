import 'package:logger/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/utils/directory_utils.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/core/utils/permission_helper.dart';
import 'package:nhasixapp/core/utils/storage_settings.dart';
import 'package:nhasixapp/domain/usecases/imports/import_zip_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/offline_search/offline_search_cubit.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/core/services/export_service.dart';
import 'package:nhasixapp/core/services/notification_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

mixin OfflineManagementMixin<T extends StatefulWidget> on State<T> {
  Future<void> importFromBackup(BuildContext context) async {
    final selectedSourceId = _currentOfflineSourceId(context);

    final hasPermission = await PermissionHelper.hasStoragePermission();
    if (!hasPermission) {
      if (context.mounted) {
        final granted =
            await PermissionHelper.requestStoragePermission(context);
        if (!granted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.storagePermissionRequired)),
          );
          return;
        }
      }
    }

    if (context.mounted) {
      context.read<OfflineSearchCubit>().setLoadingState();
    }

    if (context.mounted) {
      await _autoScanBackupFolder(context, sourceId: selectedSourceId);
    }
  }

  Future<void> exportLibrary(BuildContext context) async {
    final exportService = getIt<ExportService>();

    String progressMessage = AppLocalizations.of(context)!.preparingExport;
    double progressValue = 0.0;

    StateSetter? dialogSetState;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          dialogSetState = setDialogState;
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.exportingLibrary),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progressValue),
                const SizedBox(height: 16),
                Text(progressMessage),
              ],
            ),
          );
        },
      ),
    );

    try {
      final exportPath = await exportService.exportLibrary(
        onProgress: (progress, message) {
          progressValue = progress;
          progressMessage = message;
          if (dialogSetState != null && context.mounted) {
            dialogSetState!(() {});
          }
        },
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.exportComplete),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.libraryExportSuccess),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.exportPath(exportPath),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.close),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await exportService.shareExport(exportPath);
                },
                icon: const Icon(Icons.share),
                label: Text(AppLocalizations.of(context)!.share),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.errorGeneric(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _autoScanBackupFolder(
    BuildContext context, {
    String? sourceId,
  }) async {
    Logger().i('OFFLINE_AUTO_SCAN: Starting auto-scan for backup folder...');

    final backupPath = await DirectoryUtils.findNhasixBackupFolder();
    Logger().i(
        'OFFLINE_AUTO_SCAN: DirectoryUtils.findNhasixBackupFolder() returned: $backupPath');

    if (backupPath != null) {
      final scanPath = _resolveBackupSourcePath(backupPath, sourceId);
      Logger().i(
          'OFFLINE_AUTO_SCAN: Found backup path: $scanPath, starting sync...');

      final offlineManager = getIt<OfflineContentManager>();

      final notificationService = getIt<NotificationService>();
      await notificationService.showSyncStarted();

      final syncResult = await offlineManager.syncBackupToDatabase(
        scanPath,
        sourceId: sourceId,
        onProgress: (processed, total) {
          final percentage =
              total > 0 ? ((processed / total) * 100).toInt() : 0;
          notificationService.updateSyncProgress(
            progress: percentage,
            message: 'Sync $processed/$total',
          );
        },
      );
      final synced = syncResult['synced'] ?? 0;
      final updated = syncResult['updated'] ?? 0;

      await notificationService.showSyncCompleted(itemCount: synced + updated);

      if (!context.mounted) return;

      if (synced > 0 || updated > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.syncResult(synced, updated)),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Must run unconditionally to stop loading shimmer
      await context.read<OfflineSearchCubit>().forceRefresh();

      if (!context.mounted) return;

      try {
        context.read<DownloadBloc>().add(const DownloadRefreshEvent());
        Logger()
            .i('OFFLINE_AUTO_SCAN: Triggered DownloadBloc refresh after sync');
      } catch (e) {
        // DownloadBloc might not be available in all contexts (e.g., if Downloads Screen hasn't been visited)
        // This is non-critical, so just log and continue
        Logger().i(
            'OFFLINE_AUTO_SCAN: Could not refresh DownloadBloc (not initialized yet): $e');
      }
    } else {
      Logger().i('OFFLINE_AUTO_SCAN: No backup folder found automatically');

      if (!context.mounted) return;

      final shouldPick = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.backupNotFound),
          content: Text(AppLocalizations.of(context)!.backupNotFoundMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context)!.selectFolder),
            ),
          ],
        ),
      );

      if (shouldPick == true && context.mounted) {
        final pickedPath = await StorageSettings.pickAndSaveCustomRoot(context);
        if (pickedPath != null && context.mounted) {
          await _autoScanBackupFolder(context, sourceId: sourceId);
          return;
        }
      }

      // Ensure loading state cleared if no recursion
      if (context.mounted) {
        await context.read<OfflineSearchCubit>().forceRefresh();
      }
    }
  }

  String? _currentOfflineSourceId(BuildContext context) {
    final currentState = context.read<OfflineSearchCubit>().state;
    if (currentState is OfflineSearchLoaded) {
      return currentState.selectedSourceId;
    }

    return getIt<SharedPreferences>()
        .getString('offline_selected_source_filter');
  }

  String _resolveBackupSourcePath(String backupPath, String? sourceId) {
    if (sourceId == null || sourceId.trim().isEmpty) {
      return backupPath;
    }

    final normalizedBackupPath = path.normalize(backupPath);
    final backupBase = path.basename(normalizedBackupPath);
    if (backupBase.toLowerCase() == sourceId.toLowerCase()) {
      return normalizedBackupPath;
    }

    return path.join(backupPath, sourceId);
  }

  Future<void> importFromZip(BuildContext context) async {
    final hasPermission = await PermissionHelper.hasStoragePermission();
    if (!hasPermission) {
      if (context.mounted) {
        final granted =
            await PermissionHelper.requestStoragePermission(context);
        if (!granted) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.storagePermissionRequired)),
          );
          return;
        }
      }
    }

    if (!context.mounted) return;

    context.read<OfflineSearchCubit>().setLoadingState();

    final notificationService = getIt<NotificationService>();

    try {
      final importZipUseCase = getIt<ImportZipUseCase>();

      final result = await importZipUseCase(
        ImportZipParams(
          onStarted: (totalFiles) async {
            await notificationService.showZipExtractionStarted();
          },
          onProgress:
              (fileIndex, totalFiles, processed, total, imgCount, currentFile) {
            final percentage =
                total > 0 ? ((processed / total) * 100).toInt() : 0;

            final String prefix =
                totalFiles > 1 ? '[$fileIndex/$totalFiles] ' : '';
            notificationService.updateZipExtractionProgress(
              progress: percentage,
              message: prefix +
                  AppLocalizations.of(context)!
                      .syncProgressMessage(processed, total),
            );
          },
        ),
      );

      if (!context.mounted) return;

      if (result['success'] == true) {
        final contentId = result['contentId'] as String? ?? '';
        final imageCount = (result['imageCount'] as num?)?.toInt() ?? 0;
        final importedCount = (result['importedCount'] as num?)?.toInt() ?? 1;

        await notificationService.showZipExtractionCompleted(
          imageCount: imageCount,
        );

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              importedCount > 1
                  ? '$importedCount ZIP diimpor ke folder terpisah'
                  : AppLocalizations.of(context)!
                      .importedContentWithImages(contentId, imageCount),
            ),
            duration: const Duration(seconds: 3),
          ),
        );

        // ZIP import is always local content, so switch the offline view to local
        // instead of preserving an unrelated source filter that would hide it.
        await context.read<OfflineSearchCubit>().filterBySource('local');

        if (context.mounted) {
          try {
            context.read<DownloadBloc>().add(const DownloadRefreshEvent());
          } catch (e) {
            Logger().i('Could not refresh DownloadBloc: $e');
          }
        }
      } else {
        final error = result['error'] as String? ?? 'Unknown error';

        if (error != 'Cancelled') {
          await notificationService.showZipExtractionError(error: error);

          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .importFailedError(error.toString())),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        await context.read<OfflineSearchCubit>().forceRefresh();
      }
    } catch (e) {
      await notificationService.showZipExtractionError(error: e.toString());

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context)!.errorImportingZip(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );

      await context.read<OfflineSearchCubit>().forceRefresh();
    }
  }
}
