import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'anomaly_store_contract.dart';

/// Screen displaying the details of an anomaly record.
class AnomalyDetailScreen extends StatelessWidget {
  const AnomalyDetailScreen({
    super.key,
    required this.record,
    this.store,
    this.onReport,
    this.onDelete,
  });

  final AnomalyRecord record;
  final AnomalyStoreContract? store;
  final void Function(BuildContext context, AnomalyRecord record)? onReport;
  final VoidCallback? onDelete;

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Record Anomali'),
        content: const Text('Apakah Anda yakin ingin menghapus record anomali ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (store != null) {
        await store!.deleteRecord(record.fingerprint);
      }
      onDelete?.call();
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detail Anomali',
          style: TextStyleConst.titleLarge.copyWith(color: colorScheme.onSurface),
        ),
        centerTitle: true,
        elevation: DesignTokens.elevationNone,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: colorScheme.error),
            tooltip: 'Hapus Anomali',
            onPressed: () => _handleDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header Card with Threshold Status
          Card(
            elevation: DesignTokens.elevationNone,
            color: colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (record.eligible ? Colors.green : Colors.orange)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                        ),
                        child: Text(
                          record.eligible ? 'Eligible untuk Lapor' : 'Belum Eligible',
                          style: TextStyleConst.bodySmall.copyWith(
                            color: record.eligible ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${record.count}× kejadian',
                        style: TextStyleConst.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${record.sourceId} : ${record.feature}',
                    style: TextStyleConst.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.kind,
                    style: TextStyleConst.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: DesignTokens.spaceLg),

          // Details List
          Card(
            elevation: DesignTokens.elevationNone,
            color: colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDetailRow('Source ID', record.sourceId, theme),
                  _buildDivider(theme),
                  _buildDetailRow('Feature', record.feature, theme),
                  _buildDivider(theme),
                  _buildDetailRow('Kind', record.kind, theme),
                  _buildDivider(theme),
                  _buildDetailRow('Count', '${record.count} kali', theme),
                  if (record.configVersion != null) ...[
                    _buildDivider(theme),
                    _buildDetailRow('Config Version', record.configVersion!, theme),
                  ],
                  _buildDivider(theme),
                  _buildDetailRow(
                    'Last Seen',
                    record.lastSeen.toLocal().toString().split('.').first,
                    theme,
                  ),
                  if (record.firstSeen != null) ...[
                    _buildDivider(theme),
                    _buildDetailRow(
                      'First Seen',
                      record.firstSeen!.toLocal().toString().split('.').first,
                      theme,
                    ),
                  ],
                  _buildDivider(theme),
                  _buildDetailRow('Fingerprint', record.fingerprint, theme, isMonospace: true),
                ],
              ),
            ),
          ),

          if (record.context != null && record.context!.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spaceLg),
            Text(
              'CONTEXT / PAYLOAD',
              style: TextStyleConst.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Card(
              elevation: DesignTokens.elevationNone,
              color: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(record.context),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: DesignTokens.space2xl),

          // Tombol Lapor — MUNCUL HANYA BILA ELIGIBLE == TRUE
          if (record.eligible) ...[
            FilledButton.icon(
              key: const Key('report_anomaly_button'),
              onPressed: () {
                if (onReport != null) {
                  onReport!(context, record);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Membuka form laporan GitHub...'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send),
              label: const Text('Lapor ke GitHub'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tombol lapor belum aktif: anomaly butuh 2 kejadian lintas sesi untuk mencegah false-positive.',
                      style: TextStyleConst.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme, {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyleConst.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyleConst.bodyMedium.copyWith(
                fontFamily: isMonospace ? 'monospace' : null,
                fontSize: isMonospace ? 11 : null,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      color: theme.dividerColor.withValues(alpha: 0.15),
    );
  }
}
