import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/presentation/cubits/network/network_cubit.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/source_auth_service.dart';
import '../../core/routing/app_route.dart';
import '../../domain/entities/reader_badge.dart';
import '../../domain/usecases/reader_identity/reader_identity_usecases.dart';
import 'common/source_selector.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'reader_avatar.dart';

class _SourceAuthIdentity {
  final bool authenticated;
  final String? displayName;

  const _SourceAuthIdentity({
    required this.authenticated,
    this.displayName,
  });
}

class AppDrawerContent extends StatefulWidget {
  const AppDrawerContent({
    super.key,
    this.isDrawer = true,
  });

  final bool isDrawer;

  @override
  State<AppDrawerContent> createState() => _AppDrawerContentState();
}

class _AppDrawerContentState extends State<AppDrawerContent>
    with SingleTickerProviderStateMixin {
  String _appVersion = '';
  ReaderBadge? _badge;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadAppVersion();
    _loadReaderBadge();

    // Setup pulse animation for logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    await Connectivity().checkConnectivity();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${packageInfo.version}';
      });
    }
  }

  // Reader identity is local-only (SQLite aggregates) — cheap enough to
  // reload every time the drawer opens. Never throws into the UI.
  Future<void> _loadReaderBadge() async {
    try {
      final badge = await getIt<GetReaderBadgeUseCase>()();
      if (mounted) setState(() => _badge = badge);
    } catch (_) {
      // No badge: drawer keeps working without the identity row.
    }
  }

  void _handleNavigation(BuildContext context, String route) {
    if (widget.isDrawer) {
      Navigator.pop(context); // Close drawer first
    }

    // Use go() for root navigation (Home/Main) to clear stack
    // Use push() for everything else (Settings, About, etc) to preserve back navigation
    if (route == AppRoute.home || route == AppRoute.main || route == '/') {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  Future<_SourceAuthIdentity> _loadSourceAuthIdentity(String sourceId) async {
    final authService = getIt<SourceAuthService>();
    final authenticated = await authService.hasSession(sourceId);
    if (!authenticated) {
      return const _SourceAuthIdentity(authenticated: false);
    }

    final displayName = await authService.getSessionDisplayName(sourceId);
    return _SourceAuthIdentity(
      authenticated: true,
      displayName: displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentRoute = GoRouterState.of(context).uri.path;

    bool isSelected(String route) {
      if (route == AppRoute.home) {
        return currentRoute == AppRoute.home ||
            currentRoute == AppRoute.main ||
            currentRoute == '/' ||
            currentRoute.isEmpty;
      }
      return currentRoute.startsWith(route);
    }

    return Drawer(
      backgroundColor: Colors.transparent,
      width: 300,
      elevation: DesignTokens.elevationNone,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ],
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          border: Border(
            right: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
          child: Column(
            children: [
              // 1. Premium Animated Header
              _buildDrawerHeader(theme, l10n),

              // 2. Scrollable Navigation Items
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    const SourceSelector(),
                    SizedBox(height: DesignTokens.spaceSm),

                    if (context.watch<SourceCubit>().state.activeSource !=
                            null &&
                        context
                            .watch<SourceCubit>()
                            .state
                            .activeSource!
                            .supportsAuthentication &&
                        context.watch<SourceCubit>().state.activeSource!.id !=
                            SourceType.crotpedia.id) ...[
                      Builder(
                        builder: (_) {
                          final sourceId = context
                              .watch<SourceCubit>()
                              .state
                              .activeSource!
                              .id;

                          return FutureBuilder<_SourceAuthIdentity>(
                            future: _loadSourceAuthIdentity(sourceId),
                            builder: (context, snapshot) {
                              final identity = snapshot.data;
                              final isLoggedIn =
                                  identity?.authenticated == true;
                              final displayName =
                                  identity?.displayName?.trim() ?? '';

                              final label = isLoggedIn
                                  ? (displayName.isNotEmpty
                                      ? AppLocalizations.of(context)!
                                          .profileWithName(displayName)
                                      : AppLocalizations.of(context)!.profile)
                                  : AppLocalizations.of(context)!.loginAccount;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionLabel('ACCOUNT', theme),
                                  SizedBox(height: DesignTokens.spaceSm),
                                  _buildNavItem(
                                    context,
                                    icon: isLoggedIn
                                        ? Icons.verified_user_rounded
                                        : Icons.account_circle_rounded,
                                    label: label,
                                    route:
                                        '${AppRoute.sourceLogin}?source=$sourceId',
                                    isSelected:
                                        isSelected(AppRoute.sourceLogin),
                                    theme: theme,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                    ],

                    // Crotpedia specific actions
                    if (context.watch<SourceCubit>().state.activeSource?.id ==
                        SourceType.crotpedia.id) ...[
                      Builder(
                        builder: (context) {
                          final adapter = getIt<WebViewSessionAdapter>();
                          final isLoggedIn = adapter.isLoggedIn;
                          final name = adapter.username;
                          final label = isLoggedIn && name != null
                              ? AppLocalizations.of(context)!
                                  .accountWithName(name)
                              : AppLocalizations.of(context)!.loginAccount;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel('ACCOUNT', theme),
                              SizedBox(height: DesignTokens.spaceSm),
                              _buildNavItem(
                                context,
                                icon: isLoggedIn
                                    ? Icons.verified_user_rounded
                                    : Icons.account_circle_rounded,
                                label: label,
                                route: AppRoute.crotpediaLogin,
                                isSelected: isSelected(AppRoute.crotpediaLogin),
                                theme: theme,
                              ),
                              SizedBox(height: DesignTokens.spaceLg),
                            ],
                          );
                        },
                      ),

                      // Dynamic Crotpedia Menu
                      Builder(builder: (context) {
                        final configService = getIt<RemoteConfigService>();
                        final rawConfig =
                            configService.getRawConfig('crotpedia');
                        if (rawConfig != null) {
                          Map<String, dynamic>? menuConfig;
                          if (rawConfig['menuConfig'] is Map<String, dynamic>) {
                            menuConfig =
                                rawConfig['menuConfig'] as Map<String, dynamic>;
                          } else if (rawConfig['featurePages']
                              is Map<String, dynamic>) {
                            final featurePages = rawConfig['featurePages']
                                as Map<String, dynamic>;
                            // Fallback: auto-build drawer menu from featurePages
                            // so menu still appears even without legacy menuConfig.
                            final generatedMenu = <String, dynamic>{};
                            if (featurePages.containsKey('genreList')) {
                              generatedMenu['genreList'] = {
                                'enabled': true,
                                'label': 'Genres',
                                'icon': 'category',
                              };
                            }
                            if (featurePages.containsKey('doujinList')) {
                              generatedMenu['doujinList'] = {
                                'enabled': true,
                                'label': 'Doujin List',
                                'icon': 'library_books',
                              };
                            }
                            if (featurePages.containsKey('requestList')) {
                              generatedMenu['requestList'] = {
                                'enabled': true,
                                'label': 'Request List',
                                'icon': 'assignment',
                              };
                            }
                            menuConfig = generatedMenu;
                          }

                          if (menuConfig == null) {
                            return const SizedBox.shrink();
                          }

                          final List<Widget> menuItems = [];

                          // Helper for icon mapping
                          IconData getIcon(String? iconName) {
                            switch (iconName) {
                              case 'volunteer_activism':
                                return Icons.volunteer_activism;
                              case 'category':
                                return Icons.category;
                              case 'library_books':
                                return Icons.library_books;
                              case 'assignment':
                                return Icons.assignment;
                              default:
                                return Icons.circle;
                            }
                          }

                          // Helper for route mapping
                          String getRoute(String key) {
                            switch (key) {
                              case 'genreList':
                                return AppRoute.crotpediaGenreList;
                              case 'doujinList':
                                return AppRoute.crotpediaDoujinList;
                              case 'requestList':
                                return AppRoute.crotpediaRequestList;
                              case 'donation':
                                return AppRoute
                                    .crotpediaDonation; // Needs handling
                              default:
                                return '';
                            }
                          }

                          menuConfig.forEach((key, value) {
                            if (value is Map<String, dynamic> &&
                                value['enabled'] == true) {
                              final label = value['label']?.toString() ?? '';
                              final iconName = value['icon'] as String?;
                              final route = getRoute(key);

                              if (route.isNotEmpty) {
                                menuItems.add(_buildNavItem(
                                  context,
                                  icon: getIcon(iconName),
                                  label: label,
                                  route: route,
                                  isSelected: isSelected(route),
                                  theme: theme,
                                ));
                              }
                            }
                          });

                          if (menuItems.isNotEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionLabel('MENU', theme),
                                SizedBox(height: DesignTokens.spaceSm),
                                ...menuItems,
                                SizedBox(height: DesignTokens.spaceLg),
                              ],
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      }),
                    ],

                    _buildSectionLabel(l10n.home.toUpperCase(), theme),
                    SizedBox(height: DesignTokens.spaceSm),
                    _buildNavItem(
                      context,
                      icon: Icons.home_rounded,
                      label: l10n.home,
                      route: AppRoute.home,
                      isSelected: isSelected(AppRoute.home),
                      theme: theme,
                    ),

                    // NETWORK-AWARE MENU ITEMS: Auto-rebuild when connectivity changes
                    BlocBuilder<NetworkCubit, NetworkState>(
                      builder: (context, networkState) {
                        final isOffline = networkState is! NetworkConnected;

                        // Get active source ID once for all feature checks
                        final sourceId = context
                                .read<SourceCubit>()
                                .state
                                .activeSource
                                ?.id ??
                            'nhentai';
                        final config = getIt<RemoteConfigService>();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Downloaded Galleries
                            if (config.isFeatureEnabled(
                                sourceId, (f) => f.download))
                              _buildNavItem(
                                context,
                                icon: Icons.download_rounded,
                                label: l10n.downloadedGalleries,
                                route: AppRoute.downloads,
                                isSelected: isSelected(AppRoute.downloads),
                                theme: theme,
                              ),

                            // Offline Content (Linked to Download feature)
                            if (config.isFeatureEnabled(
                                sourceId, (f) => f.offlineMode))
                              _buildNavItem(
                                context,
                                icon: Icons.offline_bolt_rounded,
                                label: l10n.offlineContent,
                                route: AppRoute.offline,
                                isSelected: isSelected(AppRoute.offline),
                                theme: theme,
                              ),

                            // EXPLORE section (only when online)
                            if (!isOffline) ...[
                              SizedBox(height: DesignTokens.spaceLg),
                              _buildSectionLabel('EXPLORE', theme),
                              SizedBox(height: DesignTokens.spaceSm),

                              // Favorite Galleries
                              if (config.isFeatureEnabled(
                                  sourceId, (f) => f.favorite))
                                _buildNavItem(
                                  context,
                                  icon: Icons.favorite_rounded,
                                  label: l10n.favoriteGalleries,
                                  route: AppRoute.favorites,
                                  isSelected: isSelected(AppRoute.favorites),
                                  theme: theme,
                                ),

                              _buildNavItem(
                                context,
                                icon: Icons.history_rounded,
                                label: l10n.viewHistory,
                                route: AppRoute.history,
                                isSelected: isSelected(AppRoute.history),
                                theme: theme,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    SizedBox(height: DesignTokens.spaceLg),
                    _buildSectionLabel('MORE', theme),
                    SizedBox(height: DesignTokens.spaceSm),
                    _buildNavItem(
                      context,
                      icon: Icons.settings_rounded,
                      label: l10n.settings,
                      route: AppRoute.settings,
                      isSelected: isSelected(AppRoute.settings),
                      theme: theme,
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.info_outline_rounded,
                      label: l10n.about,
                      route: AppRoute.about,
                      isSelected: isSelected(AppRoute.about),
                      theme: theme,
                    ),
                  ],
                ),
              ),

              // 3. Footer Card
              _buildDrawerFooter(theme, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(ThemeData theme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        bottom: 20,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.1),
            theme.colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        children: [
          // Animated Logo
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: theme.colorScheme.surface,
                    child: const CircleAvatar(
                      radius: 38,
                      backgroundImage: AssetImage('assets/icons/logo_app.webp'),
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(height: DesignTokens.spaceLg),

          // App Name with gradient text effect
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.secondary,
              ],
            ).createShader(bounds),
            child: Text(
              l10n.appTitle,
              style: TextStyleConst.headingMedium.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 28,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              l10n.appSubtitleDescription,
              style: TextStyleConst.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_badge != null) ...[
            const SizedBox(height: 12),
            _buildIdentityRow(theme, l10n, _badge!),
          ],
        ],
      ),
    );
  }

  Widget _buildIdentityRow(
      ThemeData theme, AppLocalizations l10n, ReaderBadge badge) {
    final source = badge.topSourceDisplayName.isNotEmpty
        ? badge.topSourceDisplayName
        : '–';
    // Full-width card matching the menu-item rhythm (same fill, radius,
    // and horizontal insets as the navigation rows below).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          ReaderAvatar(tier: badge.tier, radius: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  readerTierName(l10n, badge.tier),
                  style: TextStyleConst.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.readerStatsLine(
                    badge.completedCount.toString(),
                    source,
                  ),
                  style: TextStyleConst.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
    required bool isSelected,
    required ThemeData theme,
  }) {
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleNavigation(context, route),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: DesignTokens.durationPageTurn,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: 3,
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Icon with background
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyleConst.bodyMedium.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerFooter(ThemeData theme, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.verified,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.appTitle,
                  style: TextStyleConst.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  _appVersion,
                  style: TextStyleConst.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
