import 'package:flutter/material.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/settings_theme_widgets.dart';
import 'anomaly/anomaly_list_screen.dart';
import 'anomaly/anomaly_store_contract.dart';
import 'anomaly/error_log_contract.dart';
import 'anomaly/error_log_screen.dart';
import 'anomaly/report_launcher.dart';

class _NoOpAnomalyStore implements AnomalyStoreContract {
  @override
  Future<List<AnomalyRecord>> records() async => <AnomalyRecord>[];

  @override
  Future<void> deleteRecord(String fingerprint) async {}
}

class _NoOpErrorLog implements ErrorLogContract {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<List<ErrorLogEntry>> entries({int? limit}) async => <ErrorLogEntry>[];

  @override
  Future<void> deleteEntry(int id) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<String> exportText() async => '';
}

/// Settings section for Source Anomalies & Error-response logging.
Widget buildAnomalySection(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n, {
  AnomalyStoreContract? anomalyStore,
  ErrorLogContract? errorLogStore,
}) {
  final resolvedAnomalyStore = anomalyStore ??
      (getIt.isRegistered<AnomalyStoreContract>()
          ? getIt<AnomalyStoreContract>()
          : _NoOpAnomalyStore());

  final resolvedErrorLog = errorLogStore ??
      (getIt.isRegistered<ErrorLogContract>()
          ? getIt<ErrorLogContract>()
          : _NoOpErrorLog());

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      buildSettingsSectionHeader(
        Icons.healing_outlined,
        'DIAGNOSTIK & ANOMALI SOURCE',
        theme,
      ),
      const SizedBox(height: 12),
      buildSettingsCard([
        buildSettingsActionTile(
          title: 'Anomali Source',
          subtitle: 'Daftar kegagalan config ekstensi yang terdeteksi saat runtime',
          actionLabel: 'Lihat',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AnomalyListScreen(store: resolvedAnomalyStore, onReport: (ctx, record) => launchAnomalyReport(ctx, record)),
            ),
          ),
          theme: theme,
        ),
        buildSettingsDivider(theme),
        buildSettingsActionTile(
          title: 'Log Error Respons',
          subtitle: 'Rekam dan ekspor log error HTTP 5xx, timeout, dan network',
          actionLabel: 'Buka',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ErrorLogScreen(store: resolvedErrorLog, onReport: (ctx, entry) => launchErrorReport(ctx, entry)),
            ),
          ),
          theme: theme,
        ),
      ], theme),
    ],
  );
}
