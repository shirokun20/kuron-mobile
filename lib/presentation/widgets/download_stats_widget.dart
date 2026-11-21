import 'package:material_ui/material_ui.dart';

import '../../../domain/entities/entities.dart';
import '../../core/constants/text_style_const.dart';
import '../../core/constants/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../blocs/download/download_bloc.dart';

// Widget for displaying download statistics and overall progress
class DownloadStatsWidget extends StatelessWidget {
  const DownloadStatsWidget({super.key, required this.state});

  final DownloadLoaded state;

  @override
  Widget build(BuildContext context) {
    final activeDownloads = state.downloads
        .where((d) => d.state == DownloadState.downloading)
        .toList();
    final completedDownloads = state.downloads
        .where((d) => d.state == DownloadState.completed)
        .toList();
    final queuedDownloads = state.downloads
        .where((d) => d.state == DownloadState.queued)
        .toList();
    final failedDownloads = state.downloads
        .where((d) => d.state == DownloadState.failed)
        .toList();
    final totalProgress = _calcTotalProgress(activeDownloads);
    final totalSpeed = activeDownloads.fold<double>(0, (s, d) => s + d.speed);
    final totalSize = state.downloads.fold<int>(0, (s, d) => s + d.fileSize);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          if (activeDownloads.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.overallProgress,
                        style: TextStyleConst.headingSmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: totalProgress,
                        backgroundColor: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                        minHeight: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${(totalProgress * 100).toInt()}%',
                  style: TextStyleConst.headingLarge.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context: context,
                  icon: Icons.download,
                  label: AppLocalizations.of(context)!.total,
                  value: state.downloads.length.toString(),
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context: context,
                  icon: Icons.downloading,
                  label: AppLocalizations.of(context)!.active,
                  value: activeDownloads.length.toString(),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context: context,
                  icon: Icons.schedule,
                  label: AppLocalizations.of(context)!.queued,
                  value: queuedDownloads.length.toString(),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context: context,
                  icon: Icons.check_circle,
                  label: AppLocalizations.of(context)!.done,
                  value: completedDownloads.length.toString(),
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          if (activeDownloads.isNotEmpty || totalSize > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (totalSpeed > 0) ...[
                  Expanded(
                    child: _buildInfoRow(
                      context: context,
                      icon: Icons.speed,
                      label: AppLocalizations.of(context)!.speed,
                      value: _formatSpeed(totalSpeed),
                    ),
                  ),
                ],
                if (totalSize > 0) ...[
                  if (totalSpeed > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _buildInfoRow(
                      context: context,
                      icon: Icons.storage,
                      label: AppLocalizations.of(context)!.download,
                      value: _formatSize(totalSize),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (failedDownloads.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error
                      .withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.downloadsFailed(
                        failedDownloads.length,
                        failedDownloads.length == 1 ? '' : 's',
                      ),
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.view,
                      style: TextStyleConst.labelLarge.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.isProcessing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  state is DownloadProcessing
                      ? (state as DownloadProcessing).operation
                      : AppLocalizations.of(context)!.processing,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double _calcTotalProgress(List<DownloadStatus> active) {
    if (active.isEmpty) return 0.0;
    final total = active.fold<int>(0, (s, d) => s + d.totalPages);
    final done = active.fold<int>(0, (s, d) => s + d.downloadedPages);
    return total == 0 ? 0.0 : done / total;
  }

  String _formatSpeed(double speed) {
    if (speed <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var v = speed;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  String _formatSize(int bytes) {
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }

  Widget _buildStatCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyleConst.headingMedium.copyWith(color: color),
          ),
          Text(
            label,
            style: TextStyleConst.bodySmall.copyWith(
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyleConst.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: TextStyleConst.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
