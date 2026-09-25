import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/usecases/imports/nclient_backup.dart';
import 'package:nhasixapp/domain/usecases/imports/import_nclient_backup_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

import 'settings_theme_widgets.dart';

// Settings tile + pick → preview → progress → summary flow.
// ponytail: no cubit — the use case is synchronous enough that three plain
// dialogs plus a ValueNotifier cover it; nothing here needs a bloc.
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
Map<String, String> _labels(AppLocalizations l10n) => {
      'favorites': l10n.favorites,
      'collections': l10n.collections,
      'history': l10n.history,
      'positions': l10n.nclientPositions,
      'malformed': l10n.nclientMalformedRows,
    };

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

  final counts = importer.preview(backup);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => NclientPreviewDialog(counts: counts, labels: _labels(l10n)),
  );
  if (confirmed != true || !context.mounted) return; // cancel = zero writes

  final progress = ValueNotifier<(String, int, int)>(('favorites', 0, 1));
  NclientImportSummary? summary;
  Object? failure;
  var finished = false;
  BuildContext? dialogContext;

  // Always pop post-frame: the progress dialog is `barrierDismissible: false`,
  // so a throw (or a fast import that finished before the first frame) would
  // otherwise leave the user stuck on a dialog that can never close.
  void closeProgressDialog() {
    final ctx = dialogContext;
    if (ctx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
    });
  }

  void settle(NclientImportSummary? result, Object? error) {
    if (finished) return;
    finished = true;
    summary = result;
    failure = error;
    closeProgressDialog();
  }

  unawaited(importer
      .import(backup,
          onProgress: (cat, done, total) => progress.value = (cat, done, total))
      .then((s) => settle(s, null), onError: (Object e) => settle(null, e)));

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogContext = ctx;
      // A tiny backup can finish before the dialog is on screen; close it as
      // soon as it appears instead of waiting for a callback that already ran.
      if (finished) closeProgressDialog();
      return ValueListenableBuilder<(String, int, int)>(
        valueListenable: progress,
        builder: (_, p, __) => AlertDialog(
          title: Text(l10n.nclientImport),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: p.$3 == 0 ? null : (p.$2 / p.$3).clamp(0.0, 1.0)),
              const SizedBox(height: 12),
              Text('${_labels(l10n)[p.$1] ?? p.$1}: ${p.$2}/${p.$3}'),
            ],
          ),
        ),
      );
    },
  );
  progress.dispose();
  if (!context.mounted) return;
  final error = failure;
  if (error != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.importFailed('$error'))));
    return;
  }
  final result = summary;
  if (result == null) {
    // Dialog closed without a result (shouldn't happen): no summary to show.
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) =>
        NclientSummaryDialog(summary: result, labels: _labels(l10n)),
  );
}

// ponytail: public dialog widgets so the flow is widget-testable without DI.
class NclientPreviewDialog extends StatelessWidget {
  const NclientPreviewDialog(
      {super.key, required this.counts, required this.labels});

  final Map<String, int> counts;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.nclientPreview),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in counts.entries)
            Text('${labels[e.key] ?? e.key}: ${e.value}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.nclientImportAction),
        ),
      ],
    );
  }
}

class NclientSummaryDialog extends StatelessWidget {
  const NclientSummaryDialog(
      {super.key, required this.summary, required this.labels});

  final NclientImportSummary summary;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.nclientResult),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in summary.entries)
            Text(l10n.nclientSummaryRow(
              labels[e.key] ?? e.key,
              e.value.success,
              e.value.skipped,
              e.value.failed,
            )),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
