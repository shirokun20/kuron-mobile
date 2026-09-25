import 'package:flutter/material.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/usecases/imports/import_nclient_backup_usecase.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/backup_flow.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_theme_widgets.dart';

// Settings tile + pick → preview → progress → summary flow.
// ponytail: no cubit — the flow is shared with the Kuron backup restore via
// runBackupImportFlow, so nothing here duplicates the dialog/error handling.
Widget buildNclientImportTile(
    BuildContext context, ThemeData theme, AppLocalizations l10n) {
  return buildSettingsActionTile(
    title: l10n.nclientImport,
    subtitle: l10n.nclientImportSubtitle,
    actionLabel: l10n.nclientImportAction,
    onTap: () => runNclientImport(context),
    theme: theme,
  );
}

// Preview and summary must advertise the same categories, otherwise the result
// dialog can mention a row the preview never showed. Membership counts are
// reported inside the `collections` row (that is what colOk/colSkip track).
Map<String, String> nclientLabels(AppLocalizations l10n) {
  final labels = backupCategoryLabels(l10n)..remove('memberships');
  return labels;
}

Future<void> runNclientImport(
  BuildContext context, {
  ImportNclientBackupUseCase? useCase,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final importer = useCase ?? getIt<ImportNclientBackupUseCase>();
  NclientBackup? backup;
  try {
    backup = await importer.pickAndParse();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.importFailed('$e'))));
    }
    return;
  }
  if (backup == null || !context.mounted) return; // cancelled
  final parsed = backup;

  await runBackupImportFlow(
    context: context,
    counts: importer.preview(parsed),
    labels: nclientLabels(l10n),
    run: (onProgress) => importer.import(parsed, onProgress: onProgress),
  );
}

// ponytail: kept as thin subclasses so existing call sites and widget tests
// keep working while the dialog itself is shared with the Kuron backup flow.
class NclientPreviewDialog extends BackupPreviewDialog {
  const NclientPreviewDialog({
    super.key,
    required super.counts,
    required super.labels,
  });
}

class NclientSummaryDialog extends BackupSummaryDialog {
  const NclientSummaryDialog({
    super.key,
    required super.summary,
    required super.labels,
  });
}
