import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/app_state_manager.dart';
import '../../core/constants/text_style_const.dart';
import '../../l10n/app_localizations.dart';

import 'package:nhasixapp/presentation/widgets/app_drawer_content.dart';
import 'package:nhasixapp/presentation/widgets/global_download_progress_widget.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';

// Reusable scaffold widget that shows offline indicators and "Go Online" functionality
// This widget wraps around any page content to provide consistent offline mode UI
class AppScaffoldWithOffline extends StatefulWidget {
  const AppScaffoldWithOffline({
    super.key,
    required this.body,
    required this.title,
    this.appBar,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.backgroundColor,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final String title;
  final PreferredSizeWidget? appBar;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Color? backgroundColor;
  final bool extendBodyBehindAppBar;

  @override
  State<AppScaffoldWithOffline> createState() => _AppScaffoldWithOfflineState();
}

class _AppScaffoldWithOfflineState extends State<AppScaffoldWithOffline> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          // Check if drawer is open using the GlobalKey
          if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
            _scaffoldKey.currentState?.closeDrawer();
            return;
          }

          // Pop nested routes; drawer is handled above.
          if (context.canPop()) {
            context.pop();
            return;
          }

          // At root: do nothing here. Root exit UX is owned solely by the
          // main screen's double-press snackbar — a second exit dialog here
          // fired together with the snackbar on a single back press (and a
          // cancelled dialog still left the snackbar timer armed).
        },
        child: StreamBuilder<bool>(
          // Listen to offline mode changes from AppStateManager
          stream: AppStateManager().offlineModeStream,
          initialData: AppStateManager().isOfflineMode,
          builder: (context, snapshot) {
            final isOfflineMode = snapshot.data ?? false;

            return LayoutBuilder(
              builder: (context, constraints) {
                // Early safety check for extremely small windows (popup/floating mode)
                if (constraints.maxWidth < 100 || constraints.maxHeight < 100) {
                  return Scaffold(
                    key: _scaffoldKey,
                    backgroundColor: widget.backgroundColor,
                    body: Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Center(
                        child: Icon(Icons.fullscreen_exit, size: 24),
                      ),
                    ),
                  );
                }

                // Adaptive layout for large screens (Tablet/Desktop/DeX)
                // Use persistent sidebar if width > 900dp
                final isLargeScreen = constraints.maxWidth > 900;

                final topHeaderInset = widget.extendBodyBehindAppBar
                    ? (MediaQuery.paddingOf(context).top +
                        (widget.appBar != null
                            ? (widget.appBar is PreferredSizeWidget
                                ? (widget.appBar as PreferredSizeWidget)
                                    .preferredSize
                                    .height
                                : kToolbarHeight)
                            : 0.0))
                    : 0.0;

                final scaffold = Scaffold(
                  key: _scaffoldKey,
                  appBar: widget.appBar ??
                      _buildAppBarWithOfflineIndicator(context, isOfflineMode),
                  backgroundColor: widget.backgroundColor,
                  // On large screens, hide the drawer from Scaffold (sidebar is used instead)
                  // On small screens, use the provided drawer
                  drawer: isLargeScreen ? null : widget.drawer,
                  extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
                  // Increase drawer edge drag width to 25% of screen width for easier gesture
                  drawerEdgeDragWidth:
                      isLargeScreen ? 0 : constraints.maxWidth * 0.25,
                  // Add haptic feedback when drawer state changes
                  onDrawerChanged: (isOpen) {
                    if (isOpen) {
                      HapticFeedback.lightImpact();
                    }
                  },
                  floatingActionButton: widget.floatingActionButton,
                  bottomNavigationBar: widget.bottomNavigationBar,
                  body: Column(
                    children: [
                      // GLOBAL DOWNLOAD HEADER
                      GlobalDownloadProgressWidget(
                        topInset: topHeaderInset,
                      ),

                      // Show offline banner when in offline mode
                      if (isOfflineMode) _buildOfflineBanner(context),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            // Safety check for extremely small windows - show compact fallback
                            if (innerConstraints.maxWidth < 80 ||
                                innerConstraints.maxHeight < 80) {
                              return Container(
                                color: Theme.of(context).colorScheme.surface,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.open_in_full,
                                        size: 24,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppLocalizations.of(context)!.resize,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return SafeArea(
                              left: false,
                              right: false,
                              top: false,
                              bottom: true,
                              child: widget.body,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );

                // Desktop pin: the same drawer widget, no Drawer wrapper
                // (M3 hard-codes a 16px trailing curve), wrapped in a
                // transparent Material — without it, texts inherit
                // WidgetsApp's fallback style (double-yellow underline)
                // for every unset decoration field.
                if (isLargeScreen) {
                  return Row(
                    children: [
                      const SizedBox(
                        width: 300,
                        child: Material(
                          type: MaterialType.transparency,
                          child: AppDrawerContent(isDrawer: false),
                        ),
                      ),
                      Expanded(child: scaffold),
                    ],
                  );
                }
                return scaffold;
              },
            );
          },
        ));
  }

  // Build app bar with offline indicator badge
  // Shows orange badge when offline, normal appearance when online
  AppBar _buildAppBarWithOfflineIndicator(
      BuildContext context, bool isOfflineMode) {
    return AppBar(
      title: Text(widget.title),
      backgroundColor:
          isOfflineMode ? Theme.of(context).colorScheme.errorContainer : null,
      actions: [
        // Show offline badge in app bar when in offline mode
        if (isOfflineMode) _buildOfflineBadge(context),
        ...?widget.actions,
      ],
    );
  }

  // Build compact offline badge for app bar
  // Small badge that clearly indicates offline status
  Widget _buildOfflineBadge(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border:
            Border.all(color: Theme.of(context).colorScheme.error, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.offline_bolt,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 4),
          Text(
            (AppLocalizations.of(context)?.offline ?? 'OFFLINE').toUpperCase(),
            style: TextStyleConst.overline.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  // Build prominent offline banner below app bar
  // Provides information and "Go Online" action button
  Widget _buildOfflineBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.youAreOfflineShort ??
                      AppLocalizations.of(context)!.youAreOffline,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)?.someFeaturesLimited ??
                      AppLocalizations.of(context)!.offlineFeaturesLimited,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // "Go Online" button to manually check connection
          TextButton.icon(
            onPressed: () => _checkConnectionAndGoOnline(context),
            icon: Icon(
              Icons.wifi,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              AppLocalizations.of(context)?.goOnline ?? 'Go Online',
              style: TextStyleConst.buttonSmall.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outline, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Check internet connection and switch to online mode if available
  // Provides feedback to user about connection status
  void _checkConnectionAndGoOnline(BuildContext context) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.checkingConnection),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );

      // Check actual connectivity
      final connectivity = Connectivity();
      final connectivityResults = await connectivity.checkConnectivity();
      final connectivityResult = connectivityResults.isNotEmpty
          ? connectivityResults.first
          : ConnectivityResult.none;

      if (!context.mounted) return;

      if (connectivityResult != ConnectivityResult.none) {
        // Connection available - switch to online mode
        AppStateManager().enableOnlineMode();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.onPrimary),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.backOnline),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      } else {
        // Still no connection
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_off,
                    color: Theme.of(context).colorScheme.onError),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.stillNoInternet),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      // Error checking connection
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.onError),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.unableToCheck),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// Simplified version for pages that don't need custom app bars
// Provides quick offline-aware scaffold for simple pages
class SimpleOfflineScaffold extends StatelessWidget {
  const SimpleOfflineScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.drawer,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? drawer;

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWithOffline(
      title: title,
      body: body,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
    );
  }
}

// Mixin to add offline awareness to any StatefulWidget
// Provides convenient methods for checking offline status
mixin OfflineAwareMixin<T extends StatefulWidget> on State<T> {
  late StreamSubscription<bool>? _offlineSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to offline mode changes
    _offlineSubscription = AppStateManager().offlineModeStream.listen(
      (isOffline) {
        onOfflineModeChanged(isOffline);
      },
    );
  }

  @override
  void dispose() {
    _offlineSubscription?.cancel();
    super.dispose();
  }

  // Override this method to handle offline mode changes
  // Called whenever the app switches between online/offline mode
  void onOfflineModeChanged(bool isOffline) {
    // Default implementation - can be overridden by widgets
  }

  // Check if app is currently in offline mode
  bool get isOffline => AppStateManager().isOfflineMode;

  // Check if app is currently in online mode
  bool get isOnline => !AppStateManager().isOfflineMode;

  // Show offline-specific message to user
  void showOfflineMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.offline_bolt,
                  color: Theme.of(context).colorScheme.onError),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Show online-specific message to user
  void showOnlineMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi, color: Theme.of(context).colorScheme.onPrimary),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
