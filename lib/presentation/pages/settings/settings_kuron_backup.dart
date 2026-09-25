import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/usecases/exports/export_kuron_backup_usecase.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_parser.dart';
import 'package:nhasixapp/domain/usecases/exports/restore_kuron_backup_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/backup_flow.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_theme_widgets.dart';
import 'package:share_plus/share_plus.dart';

// Settings section "Backup & Restore": Kuron's own backup now + restore, sharing
// the same preview/progress/summary flow as the NClient import.
Widget buildKuronBackupTile(
    BuildContext context, ThemeData theme, AppLocalizations l10n) {
  return buildSettingsActionTile(
    title: l10n.kuronBackupNow,
    subtitle: l10n.kuronBackupNowSubtitle,
    actionLabel: l10n.kuronBackupNowAction,
    onTap: () => runKuronBackup(context),
    theme: theme,
  );
}

Widget buildKuronRestoreTile(
    BuildContext context, ThemeData theme, AppLocalizations l10n) {
  return buildSettingsActionTile(
    title: l10n.kuronRestore,
    subtitle: l10n.kuronRestoreSubtitle,
    actionLabel: l10n.kuronRestoreAction,
    onTap: () => runKuronRestore(context),
    theme: theme,
  );
}

Map<String, String> _labels(AppLocalizations l10n) =>
    backupCategoryLabels(l10n);

/// Exports the library + settings to `KuronBackup_<epoch>.zip` and hands the
/// file to the share sheet (the same delivery the legacy ExportService uses, so
/// no new native code and no new dependency).
Future<void> runKuronBackup(
  BuildContext context, {
  ExportKuronBackupUseCase? useCase,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final exporter = useCase ?? getIt<ExportKuronBackupUseCase>();

  final exported = await runBackupProgressFlow<ExportedBackupFile>(
    context: context,
    title: l10n.kuronBackupNow,
    labels: _labels(l10n),
    run: (onProgress) => exporter.writeToTempFile(onProgress: onProgress),
  );
  if (exported == null || !context.mounted) return;

  final shared = await _share(context, exported, l10n);
  if (shared && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.kuronBackupReady(exported.path))),
    );
  }
}

Future<bool> _share(
  BuildContext context,
  ExportedBackupFile file,
  AppLocalizations l10n,
) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: l10n.kuronBackupNow,
      ),
    );
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.kuronBackupFailed('$e'))),
      );
    }
    return false;
  }
}

/// Restore from a `KuronBackup_*.zip`: pick → preview → progress → summary.
Future<void> runKuronRestore(
  BuildContext context, {
  RestoreKuronBackupUseCase? useCase,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final restorer = useCase ?? getIt<RestoreKuronBackupUseCase>();

  Uint8List? bytes;
  try {
    bytes = await KuronNative.instance.pickBinaryFile(
      mimeType: 'application/zip',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.importFailed('$e'))));
    }
    return;
  }
  if (bytes == null || !context.mounted) return; // cancelled

  KuronBackup backup;
  try {
    // Parsed off the UI isolate: a large library payload is multi-MB.
    backup = await restorer.parseBytesAsync(bytes);
  } on UnsupportedBackupVersionException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.kuronBackupIncompatible('${e.found}'))),
      );
    }
    return;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.importFailed('$e'))));
    }
    return;
  }
  if (!context.mounted) return;

  await runBackupImportFlow(
    context: context,
    counts: restorer.preview(backup),
    labels: _labels(l10n),
    run: (onProgress) => restorer.restore(backup, onProgress: onProgress),
    progressTitle: l10n.kuronRestore,
    previewTitle: l10n.kuronRestorePreview,
    resultTitle: l10n.kuronRestoreResult,
  );
}
