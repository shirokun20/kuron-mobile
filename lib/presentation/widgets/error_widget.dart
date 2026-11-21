import 'package:material_ui/material_ui.dart';

import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';

import 'package:nhasixapp/core/constants/design_tokens.dart';

// Custom error widget with black theme and contextual information
class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.iconColor,
    this.onRetry,
    this.retryText,
    this.onSecondaryAction,
    this.secondaryActionText,
    this.showDetails = false,
    this.details,
    this.suggestions = const [],
  });

  final String title;
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onRetry;
  final String? retryText;
  final VoidCallback? onSecondaryAction;
  final String? secondaryActionText;
  final bool showDetails;
  final String? details;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Error icon
          Icon(
            icon ?? Icons.error_outline,
            size: 64,
            color: iconColor ?? Theme.of(context).colorScheme.error,
          ),

          const SizedBox(height: 16),

          // Error title
          Text(
            title,
            style: TextStyleConst.headingMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Error message
          Text(
            message,
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          // Suggestions
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSuggestions(context),
          ],

          // Error details (expandable)
          if (showDetails && details != null) ...[
            const SizedBox(height: 16),
            _buildErrorDetails(context),
          ],

          const SizedBox(height: 24),

          // Action buttons
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.suggestions,
            style: TextStyleConst.labelMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ...suggestions.map(
            (suggestion) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyleConst.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: TextStyleConst.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorDetails(BuildContext context) {
    return ExpansionTile(
      title: Text(
        AppLocalizations.of(context)!.error,
        style: TextStyleConst.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      collapsedIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: Text(
            details!,
            style: TextStyleConst.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // Primary action (Retry)
        if (onRetry != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
              ),
              child: Text(
                retryText ?? AppLocalizations.of(context)!.tryAgain,
                style: TextStyleConst.buttonMedium.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),

        // Secondary action
        if (onSecondaryAction != null && secondaryActionText != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onSecondaryAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline
                      .withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
              ),
              child: Text(
                secondaryActionText!,
                style: TextStyleConst.buttonMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Network error widget
class NetworkErrorWidget extends StatelessWidget {
  const NetworkErrorWidget({super.key, this.onRetry, this.onGoOffline});

  final VoidCallback? onRetry;
  final VoidCallback? onGoOffline;

  @override
  Widget build(BuildContext context) {
    return AppErrorWidget(
      title: AppLocalizations.of(context)!.connectionError,
      message: AppLocalizations.of(context)!.unableToCheckConnection,
      icon: Icons.wifi_off,
      iconColor: Theme.of(context).colorScheme.error,
      onRetry: onRetry,
      retryText: AppLocalizations.of(context)!.tryAgain,
      onSecondaryAction: onGoOffline,
      secondaryActionText: AppLocalizations.of(context)!.offline,
      suggestions: [
        AppLocalizations.of(context)!.suggestionCheckConnection,
        AppLocalizations.of(context)!.suggestionTryWifiMobile,
        AppLocalizations.of(context)!.suggestionRestartRouter,
        AppLocalizations.of(context)!.suggestionCheckWebsite,
      ],
    );
  }
}

// Server error widget
class ServerErrorWidget extends StatelessWidget {
  const ServerErrorWidget({super.key, this.onRetry, this.statusCode});

  final VoidCallback? onRetry;
  final int? statusCode;

  @override
  Widget build(BuildContext context) {
    return AppErrorWidget(
      title: AppLocalizations.of(context)!.serverError,
      message: statusCode != null
          ? AppLocalizations.of(context)!.serverReturnedError(statusCode!)
          : AppLocalizations.of(context)!.serverUnavailable,
      icon: Icons.dns,
      iconColor: Theme.of(context).colorScheme.error,
      onRetry: onRetry,
      suggestions: [
        AppLocalizations.of(context)!.waitAndTry(5),
        AppLocalizations.of(context)!.serviceUnderMaintenance,
        AppLocalizations.of(context)!.tryRefreshingPage,
      ],
    );
  }
}

// Cloudflare error widget
class CloudflareErrorWidget extends StatelessWidget {
  const CloudflareErrorWidget({super.key, this.onRetry, this.onBypass});

  final VoidCallback? onRetry;
  final VoidCallback? onBypass;

  @override
  Widget build(BuildContext context) {
    return AppErrorWidget(
      title: AppLocalizations.of(context)!.error,
      message: AppLocalizations.of(context)!.cloudflareBypassMessage,
      icon: Icons.security,
      iconColor: Theme.of(context).colorScheme.tertiary,
      onRetry: onRetry,
      retryText: AppLocalizations.of(context)!.tryAgain,
      onSecondaryAction: onBypass,
      secondaryActionText: AppLocalizations.of(context)!.forceBypass,
      suggestions: [
        AppLocalizations.of(context)!.waitForBypass,
        AppLocalizations.of(context)!.tryUsingVpn,
        AppLocalizations.of(context)!.checkBackLater,
      ],
    );
  }
}

// Parse error widget
class ParseErrorWidget extends StatelessWidget {
  const ParseErrorWidget({super.key, this.onRetry, this.onReport});

  final VoidCallback? onRetry;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    return AppErrorWidget(
      title: AppLocalizations.of(context)!.error,
      message: AppLocalizations.of(context)!.unableToProcessData,
      icon: Icons.code_off,
      iconColor: Theme.of(context).colorScheme.error,
      onRetry: onRetry,
      retryText: AppLocalizations.of(context)!.retryAction,
      onSecondaryAction: onReport,
      secondaryActionText: AppLocalizations.of(context)!.reportIssue,
      suggestions: [
        AppLocalizations.of(context)!.tryRefreshingContent,
        AppLocalizations.of(context)!.checkForAppUpdate,
        AppLocalizations.of(context)!.reportIfPersists,
      ],
    );
  }
}

// Empty state widget
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onAction,
    this.actionText,
    this.suggestions = const [],
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionText;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyleConst.headingMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyleConst.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...suggestions.map(
              (suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $suggestion',
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          if (onAction != null && actionText != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
              ),
              child: Text(
                actionText!,
                style: TextStyleConst.buttonMedium.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// No search results widget
class NoSearchResultsWidget extends StatelessWidget {
  const NoSearchResultsWidget({
    super.key,
    this.query,
    this.onClearFilters,
    this.onTryDifferentSearch,
  });

  final String? query;
  final VoidCallback? onClearFilters;
  final VoidCallback? onTryDifferentSearch;

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      title: AppLocalizations.of(context)!.noResults,
      message: query != null
          ? AppLocalizations.of(context)!.noContentFoundWithQuery(query!)
          : AppLocalizations.of(context)!.noContentFound,
      icon: Icons.search_off,
      onAction: onClearFilters,
      actionText: AppLocalizations.of(context)!.clearFilters,
      suggestions: [
        AppLocalizations.of(context)!.suggestionTryDifferentKeywords,
        AppLocalizations.of(context)!.suggestionRemoveFilters,
        AppLocalizations.of(context)!.suggestionCheckSpelling,
        AppLocalizations.of(context)!.suggestionUseBroaderTerms,
      ],
    );
  }
}

// Maintenance mode widget
class MaintenanceWidget extends StatelessWidget {
  const MaintenanceWidget({super.key, this.onCheckAgain});

  final VoidCallback? onCheckAgain;

  @override
  Widget build(BuildContext context) {
    return AppErrorWidget(
      title: AppLocalizations.of(context)!.underMaintenanceTitle,
      message: AppLocalizations.of(context)!.underMaintenanceMessage,
      icon: Icons.build,
      iconColor: Theme.of(context).colorScheme.tertiary,
      onRetry: onCheckAgain,
      retryText: AppLocalizations.of(context)!.tryAgain,
      suggestions: [
        AppLocalizations.of(context)!.suggestionMaintenanceHours,
        AppLocalizations.of(context)!.suggestionCheckSocial,
        AppLocalizations.of(context)!.suggestionTryLater,
      ],
    );
  }
}
