import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nhasixapp/core/services/report/report_builder.dart';
import 'anomaly_store_contract.dart' as anomaly;
import 'error_log_contract.dart' as elog;

/// Group 6 integration: turns anomaly/error records into prefilled
/// GitHub issue URLs (Keputusan 4: single channel, user holds Submit).
///
/// URL construction is pure and unit-tested; only [openUrl] touches
/// the platform (injectable fake in tests, `launchUrl` in production).
typedef OpenUrl = Future<bool> Function(Uri url);

/// Pure builders (no platform): repo is chosen by the caller so the
/// user can override the suggestion (spec: repo bisa diganti user).
Uri buildAnomalyReportUrl(
  anomaly.AnomalyRecord record,
  String repo,
  String appVersion,
) {
  final title = ReportBuilder.buildIssueTitle(
    sourceId: record.sourceId,
    feature: record.feature,
    kind: record.kind,
  );
  final body = ReportBuilder.buildReportBody(
    sourceId: record.sourceId,
    feature: record.feature,
    kind: record.kind,
    fingerprint: record.fingerprint,
    templatePath: record.context?['template'] as String?,
    configVersion: record.configVersion,
    appVersion: appVersion,
  );
  return ReportBuilder.buildPrefilledUrl(
    repo: repo,
    title: title,
    body: body,
    fingerprint: record.fingerprint,
  );
}

Uri buildErrorReportUrl(
  elog.ErrorLogEntry entry,
  String repo,
  String appVersion,
) {
  const kind = 'error-log';
  final title = ReportBuilder.buildIssueTitle(
    sourceId: entry.sourceId,
    feature: entry.feature,
    kind: kind,
  );
  final body = ReportBuilder.buildReportBody(
    sourceId: entry.sourceId,
    feature: entry.feature,
    kind: kind,
    fingerprint: '',
    statusCode: entry.statusCode,
    urlPath: entry.urlPath,
    message: entry.message,
    appVersion: appVersion,
  );
  return ReportBuilder.buildPrefilledUrl(
    repo: repo,
    title: title,
    body: body,
  );
}

String suggestedAnomalyRepo() =>
    ReportBuilder.suggestRepo(isSourceLayer: true);

String suggestedErrorRepo(elog.ErrorLogEntry entry) =>
    ReportBuilder.suggestRepo(isSourceLayer: entry.sourceId.isNotEmpty);

Future<String> _appVersion() async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    return '';
  }
}

/// Shows the repo picker (suggested first), builds the prefilled URL,
/// and opens it. Returns silently when the user dismisses the sheet.
Future<void> launchAnomalyReport(
  BuildContext context,
  anomaly.AnomalyRecord record, {
  OpenUrl openUrl = launchUrl,
}) async {
  final repo = await _pickRepo(context, suggestedAnomalyRepo());
  if (repo == null || !context.mounted) return;
  final url = buildAnomalyReportUrl(record, repo, await _appVersion());
  await openUrl(url);
}

Future<void> launchErrorReport(
  BuildContext context,
  elog.ErrorLogEntry entry, {
  OpenUrl openUrl = launchUrl,
}) async {
  final repo = await _pickRepo(context, suggestedErrorRepo(entry));
  if (repo == null || !context.mounted) return;
  final url = buildErrorReportUrl(entry, repo, await _appVersion());
  await openUrl(url);
}

Future<String?> _pickRepo(BuildContext context, String suggested) {
  final other = suggested == ReportBuilder.extensionsRepo
      ? ReportBuilder.mobileRepo
      : ReportBuilder.extensionsRepo;
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text('$suggested (disarankan)'),
            onTap: () => Navigator.pop(ctx, suggested),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(other),
            onTap: () => Navigator.pop(ctx, other),
          ),
        ],
      ),
    ),
  );
}
