import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Shared pick-free import/export flow used by every Settings importer
// (NClient backup, Kuron backup restore) so the UX stays one pattern and the
// error handling lives in exactly one place.
//
// Labels are keyed by category id: 'favorites', 'collections', 'history',
// 'positions', 'settings', 'malformed'. A key without a label falls back to the
// raw category id, which keeps a new category from silently disappearing.
typedef BackupCategoryLabels = Map<String, String>;

/// Per-category counters shared by both import use cases.
typedef BackupCategoryResult = ({int success, int skipped, int failed});
typedef BackupFlowSummary = Map<String, BackupCategoryResult>;

/// Progress callback shape used by the backup use cases:
/// `(category, done, total)`.
typedef BackupProgress = void Function(String category, int done, int total);

Map<String, String> backupCategoryLabels(AppLocalizations l10n) => {
      'favorites': l10n.favorites,
      'collections': l10n.collections,
      'memberships': l10n.nclientMemberships,
      'history': l10n.history,
      'positions': l10n.nclientPositions,
      'settings': l10n.settings,
      'malformed': l10n.nclientMalformedRows,
    };

/// Shows a non-dismissable progress dialog while [run] works, then closes it.
///
/// Returns the result, or `null` when the run failed (error surfaced as a
/// snackbar). The dialog is always closed, including when the work finishes
/// before the first frame — a stuck `barrierDismissible: false` dialog is the
/// one failure mode users cannot escape.
Future<T?> runBackupProgressFlow<T>({
  required BuildContext context,
  required String title,
  required BackupCategoryLabels labels,
  required Future<T> Function(BackupProgress onProgress) run,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final progress = ValueNotifier<(String, int, int)>(('favorites', 0, 1));
  T? result;
  Object? failure;
  var finished = false;
  BuildContext? dialogContext;

  void closeProgressDialog() {
    final ctx = dialogContext;
    if (ctx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
    });
  }

  void settle(T? value, Object? error) {
    if (finished) return;
    finished = true;
    result = value;
    failure = error;
    closeProgressDialog();
  }

  unawaited(run((cat, done, total) => progress.value = (cat, done, total))
      .then((v) => settle(v, null), onError: (Object e) => settle(null, e)));

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogContext = ctx;
      if (finished) closeProgressDialog();
      return ValueListenableBuilder<(String, int, int)>(
        valueListenable: progress,
        builder: (_, p, __) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: p.$3 == 0 ? null : (p.$2 / p.$3).clamp(0.0, 1.0)),
              const SizedBox(height: 12),
              Text('${labels[p.$1] ?? p.$1}: ${p.$2}/${p.$3}'),
            ],
          ),
        ),
      );
    },
  );
  progress.dispose();
  if (!context.mounted) return null;
  final error = failure;
  if (error != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.importFailed('$error'))));
    return null;
  }
  return result;
}

/// Runs confirm → progress → summary for a destructive-ish import.
///
/// [counts] are shown in a preview dialog first; dismissing it means zero
/// writes. The returned summary is `null` when the user cancelled or the run
/// failed.
Future<BackupFlowSummary?> runBackupImportFlow({
  required BuildContext context,
  required Map<String, int> counts,
  required BackupCategoryLabels labels,
  required Future<BackupFlowSummary> Function(BackupProgress onProgress) run,
  String? progressTitle,
  String? previewTitle,
  String? resultTitle,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => BackupPreviewDialog(
      counts: counts,
      labels: labels,
      title: previewTitle,
    ),
  );
  if (confirmed != true || !context.mounted) return null; // zero writes

  final summary = await runBackupProgressFlow<BackupFlowSummary>(
    context: context,
    title: progressTitle ?? l10n.nclientImport,
    labels: labels,
    run: run,
  );
  if (summary == null || !context.mounted) return null;

  await showDialog<void>(
    context: context,
    builder: (_) => BackupSummaryDialog(
      summary: summary,
      labels: labels,
      title: resultTitle,
    ),
  );
  return summary;
}

class BackupPreviewDialog extends StatelessWidget {
  const BackupPreviewDialog({
    super.key,
    required this.counts,
    required this.labels,
    this.title,
  });

  final Map<String, int> counts;
  final BackupCategoryLabels labels;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(title ?? l10n.nclientPreview),
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

class BackupSummaryDialog extends StatelessWidget {
  const BackupSummaryDialog({
    super.key,
    required this.summary,
    required this.labels,
    this.title,
  });

  final BackupFlowSummary summary;
  final BackupCategoryLabels labels;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(title ?? l10n.nclientResult),
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
