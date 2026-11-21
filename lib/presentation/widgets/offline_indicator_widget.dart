import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';
import '../cubits/network/network_cubit.dart';

// Widget that shows offline/online status indicator
class OfflineIndicatorWidget extends StatelessWidget {
  const OfflineIndicatorWidget({
    super.key,
    this.showWhenOnline = false,
    this.compact = false,
  });

  final bool showWhenOnline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NetworkCubit, NetworkState>(
      builder: (context, state) {
        if (state is NetworkConnected && !showWhenOnline) {
          return const SizedBox.shrink();
        }

        final isOffline = state is! NetworkConnected;
        final connectionType = state is NetworkConnected
            ? state.connectionType
            : null;

        return AnimatedContainer(
          duration: DesignTokens.durationNormal,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 2 : 4,
          ),
          decoration: BoxDecoration(
            color: isOffline
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.2)
                : _getConnectionColor(
                    context,
                    connectionType,
                  ).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(compact ? 4 : 6),
            border: Border.all(
              color: isOffline
                  ? Theme.of(context).colorScheme.error
                  : _getConnectionColor(context, connectionType),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOffline
                    ? Icons.cloud_off
                    : _getConnectionIcon(connectionType),
                size: compact ? 12 : 16,
                color: isOffline
                    ? Theme.of(context).colorScheme.error
                    : _getConnectionColor(context, connectionType),
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                Text(
                  isOffline
                      ? AppLocalizations.of(context)!.offlineStatus
                      : (connectionType == NetworkConnectionType.other
                            ? AppLocalizations.of(context)!.onlineStatus
                            : _getConnectionText(connectionType)),
                  style: compact
                      ? TextStyleConst.overline.copyWith(
                          color: isOffline
                              ? Theme.of(context).colorScheme.error
                              : _getConnectionColor(context, connectionType),
                        )
                      : TextStyleConst.label.copyWith(
                          color: isOffline
                              ? Theme.of(context).colorScheme.error
                              : _getConnectionColor(context, connectionType),
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _getConnectionColor(BuildContext context, NetworkConnectionType? type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case NetworkConnectionType.wifi:
      case NetworkConnectionType.ethernet:
        return colorScheme.tertiary; // Green for good connection
      case NetworkConnectionType.mobile:
        return colorScheme.secondary; // Amber/orange for mobile
      case NetworkConnectionType.other:
        return colorScheme.primary; // Primary blue for other
      case null:
        return colorScheme.error; // Red for error/offline
    }
  }

  IconData _getConnectionIcon(NetworkConnectionType? type) {
    switch (type) {
      case NetworkConnectionType.wifi:
        return Icons.wifi;
      case NetworkConnectionType.ethernet:
        return Icons.lan;
      case NetworkConnectionType.mobile:
        return Icons.signal_cellular_4_bar;
      case NetworkConnectionType.other:
        return Icons.device_hub;
      case null:
        return Icons.cloud_off;
    }
  }

  String _getConnectionText(NetworkConnectionType? type) {
    switch (type) {
      case NetworkConnectionType.wifi:
        return 'WIFI';
      case NetworkConnectionType.ethernet:
        return 'ETHERNET';
      case NetworkConnectionType.mobile:
        return 'MOBILE';
      case NetworkConnectionType.other:
        return 'ONLINE';
      case null:
        return 'OFFLINE';
    }
  }
}

// Compact offline indicator for app bars and small spaces
class CompactOfflineIndicator extends StatelessWidget {
  const CompactOfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const OfflineIndicatorWidget(compact: true);
  }
}

// Full offline indicator with text
class FullOfflineIndicator extends StatelessWidget {
  const FullOfflineIndicator({super.key, this.showWhenOnline = false});

  final bool showWhenOnline;

  @override
  Widget build(BuildContext context) {
    return OfflineIndicatorWidget(
      showWhenOnline: showWhenOnline,
      compact: false,
    );
  }
}

// Offline banner that appears at the top when offline
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NetworkCubit, NetworkState>(
      builder: (context, state) {
        if (state is NetworkConnected) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: DesignTokens.durationNormal,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                size: 16,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.offlineSomeFeaturesUnavailable,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  context.read<NetworkCubit>().checkConnectivity();
                },
                child: Text(
                  AppLocalizations.of(context)?.retry ?? 'Retry',
                  style: TextStyleConst.buttonSmall.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Offline mode toggle for settings
class OfflineModeToggle extends StatelessWidget {
  const OfflineModeToggle({
    super.key,
    required this.isOfflineMode,
    required this.onToggle,
  });

  final bool isOfflineMode;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: isOfflineMode
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOfflineMode ? Icons.offline_bolt : Icons.cloud,
            color: isOfflineMode
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.offlineMode ?? 'Offline Mode',
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOfflineMode
                      ? AppLocalizations.of(context)!.usingDownloadedContentOnly
                      : AppLocalizations.of(context)!
                            .onlineModeWithNetworkAccess,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isOfflineMode,
            onChanged: onToggle,
            activeThumbColor: Theme.of(context).colorScheme.tertiary,
            inactiveThumbColor: Theme.of(context).colorScheme.onSurfaceVariant,
            inactiveTrackColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}
