import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/text_style_const.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/services/history_cleanup_service.dart';
import '../../../cubits/history/history_cubit.dart';

// Widget for displaying history cleanup information and settings
class HistoryCleanupInfoWidget extends StatefulWidget {
  const HistoryCleanupInfoWidget({super.key, required this.historyCubit});

  final HistoryCubit historyCubit;

  @override
  State<HistoryCleanupInfoWidget> createState() =>
      _HistoryCleanupInfoWidgetState();
}

class _HistoryCleanupInfoWidgetState extends State<HistoryCleanupInfoWidget> {
  HistoryCleanupStatus? _cleanupStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCleanupStatus();
  }

  Future<void> _loadCleanupStatus() async {
    setState(() => _isLoading = true);
    try {
      final status = await widget.historyCubit.getCleanupStatus();
      if (mounted) {
        setState(() {
          _cleanupStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.cleaning_services,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.historyCleanup,
                      style: TextStyleConst.headingMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(context, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ScrollController scrollController,
  ) {
    if (_cleanupStatus == null) {
      return Center(
        child: Text(AppLocalizations.of(context)!.failedToLoadCleanupStatus),
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current status
          _buildStatusCard(context),

          const SizedBox(height: 20),

          // Settings info
          _buildSettingsInfo(context),

          const SizedBox(height: 20),

          // History stats
          _buildHistoryStats(context),

          const SizedBox(height: 20),

          // Actions
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final status = _cleanupStatus!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.isEnabled ? Icons.check_circle : Icons.pause_circle,
                  color: status.isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.autoCleanupHistory,
                  style: TextStyleConst.headingSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              status.statusDescription,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (status.isEnabled && status.nextCleanupEstimate != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                context,
                AppLocalizations.of(context)!.nextCleanup,
                _formatDateTime(status.nextCleanupEstimate!),
                Icons.schedule,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsInfo(BuildContext context) {
    final status = _cleanupStatus!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.cleanupSettings,
              style: TextStyleConst.headingSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              AppLocalizations.of(context)!.cleanupInterval,
              AppLocalizations.of(context)!.hours(status.intervalHours),
              Icons.timer,
            ),
            if (status.maxHistoryDays > 0)
              _buildInfoRow(
                context,
                AppLocalizations.of(context)!.maxHistoryDays,
                AppLocalizations.of(context)!.days(status.maxHistoryDays),
                Icons.calendar_today,
              ),
            if (status.inactivityCleanupEnabled)
              _buildInfoRow(
                context,
                AppLocalizations.of(context)!.cleanupOnInactivity,
                AppLocalizations.of(context)!
                    .days(status.inactivityThresholdDays),
                Icons.schedule_outlined,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryStats(BuildContext context) {
    final status = _cleanupStatus!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.historyStatistics,
              style: TextStyleConst.headingSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              AppLocalizations.of(context)!.totalItems,
              '${status.historyCount}',
              Icons.history,
            ),
            if (status.lastCleanup != null)
              _buildInfoRow(
                context,
                AppLocalizations.of(context)!.lastCleanup,
                _formatDateTime(status.lastCleanup!),
                Icons.cleaning_services,
              ),
            if (status.lastAppAccess != null)
              _buildInfoRow(
                context,
                AppLocalizations.of(context)!.lastAppAccess,
                _formatDateTime(status.lastAppAccess!),
                Icons.access_time,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _performManualCleanup(context),
            icon: const Icon(Icons.cleaning_services),
            label: Text(AppLocalizations.of(context)!.manualCleanup),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _navigateToSettings(context),
            icon: const Icon(Icons.settings),
            label: Text(AppLocalizations.of(context)!.cleanupSettings),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyleConst.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    final l10n = AppLocalizations.of(context)!;

    if (difference.inDays > 0) {
      return l10n.daysAgo(difference.inDays, difference.inDays == 1 ? '' : 's');
    } else if (difference.inHours > 0) {
      return l10n.hoursAgo(
        difference.inHours,
        difference.inHours == 1 ? '' : 's',
      );
    } else if (difference.inMinutes > 0) {
      return l10n.minutesAgo(
        difference.inMinutes,
        difference.inMinutes == 1 ? '' : 's',
      );
    } else {
      return l10n.justNow;
    }
  }

  void _performManualCleanup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.manualCleanup),
        content: Text(AppLocalizations.of(context)!.manualCleanupConfirmation),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              context.pop();
              context.pop(); // Close bottom sheet
              widget.historyCubit.performManualCleanup();
            },
            child: Text(AppLocalizations.of(context)!.cleanup),
          ),
        ],
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    context.pop(); // Close bottom sheet
    context.push('/settings');
  }
}
