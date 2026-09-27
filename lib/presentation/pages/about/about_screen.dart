import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/core/services/github_release_stats_service.dart';
import 'package:nhasixapp/presentation/cubits/update/update_cubit.dart';
import 'package:nhasixapp/presentation/cubits/update/update_state.dart';
import 'package:nhasixapp/presentation/widgets/app_main_drawer_widget.dart';
import 'package:nhasixapp/presentation/widgets/update_available_sheet.dart';
import 'package:nhasixapp/presentation/widgets/legal_content_sheet.dart';
import 'package:nhasixapp/core/services/legal_content_service.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<UpdateCubit>(),
      child: const _AboutContent(),
    );
  }
}

class _AboutContent extends StatefulWidget {
  const _AboutContent();

  @override
  State<_AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends State<_AboutContent>
    with SingleTickerProviderStateMixin {
  String _version = '';
  String? _downloadsLabel;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadDownloadCount();

    // Setup pulse animation for logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = 'v${info.version}';
      });
    }
  }

  // Community download counter: cache-first, fail-silent. Null keeps the
  // row hidden — a zero or a spinner here would mislead or clutter.
  Future<void> _loadDownloadCount() async {
    try {
      final total =
          await getIt<GithubReleaseStatsService>().getTotalDownloads();
      if (mounted && total != null) {
        final lang = Localizations.localeOf(context).languageCode;
        setState(() {
          _downloadsLabel = AppLocalizations.of(context)!
              .appDownloadsFromGithub(
                  compactCount(total, languageCode: lang));
        });
      }
    } catch (_) {
      // Row stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.aboutTitle,
          style: TextStyleConst.titleLarge.copyWith(color: onSurface),
        ),
        centerTitle: true,
        elevation: DesignTokens.elevationNone,
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
      ),
      drawer: AppMainDrawerWidget(context: context),
      extendBodyBehindAppBar: true,
      body: BlocListener<UpdateCubit, UpdateState>(
        listener: (context, state) {
          if (state is UpdateAvailable) {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (context) =>
                  UpdateAvailableSheet(updateInfo: state.updateInfo),
            );
          } else if (state is UpdateNotAvailable && state.isManualCheck) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.appIsUpToDate)),
            );
          } else if (state is UpdateError && state.isManualCheck) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.checkFailedMessage(state.message))),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 20),

                // Hero Section
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          height: 120,
                          width: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Image(
                            image: AssetImage('assets/icons/logo_app.webp'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXl),

                Text(
                  l10n.appTitle,
                  style: TextStyleConst.headingLarge.copyWith(
                    fontSize: 32,
                    color: onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radius2xl),
                    ),
                    child: Text(
                      _version,
                      style: TextStyleConst.bodyMedium.copyWith(
                        color: onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_downloadsLabel != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radius2xl),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 14,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _downloadsLabel!,
                            style: TextStyleConst.bodySmall.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: DesignTokens.space3xl),

                // Update Card
                _buildSectionTitle(l10n.updatesSection),
                const SizedBox(height: DesignTokens.spaceSm),
                _buildUpdateCard(theme),

                const SizedBox(height: DesignTokens.space2xl),

                // Links Section
                _buildSectionTitle(l10n.communityAndInfo),
                const SizedBox(height: DesignTokens.spaceSm),
                _buildMenuCard([
                  _buildMenuItem(
                    context,
                    icon: Icons.code,
                    title: l10n.githubRepository,
                    subtitle: l10n.viewSourceCodeContribute,
                    onTap: () =>
                        _launchURL('https://github.com/shirokun20/nhasixapp'),
                    isExternal: true,
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context,
                    icon: Icons.description_outlined,
                    title: l10n.openSourceLicenses,
                    subtitle: l10n.librariesUsedInApp,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: l10n.appTitle,
                      applicationVersion: _version,
                      applicationIcon: const Image(
                        image: AssetImage('assets/icons/frame.webp'),
                        height: 48,
                        width: 48,
                      ),
                    ),
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context,
                    icon: Icons.gavel_outlined,
                    title: l10n.termsAndConditions,
                    subtitle: l10n.termsAndConditionsSubtitle,
                    onTap: () => LegalContentSheet.show(
                      context,
                      contentType: LegalContentType.termsAndConditions,
                      locale: Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context,
                    icon: Icons.privacy_tip_outlined,
                    title: l10n.privacyPolicy,
                    subtitle: l10n.privacyPolicySubtitle,
                    onTap: () => LegalContentSheet.show(
                      context,
                      contentType: LegalContentType.privacyPolicy,
                      locale: Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context,
                    icon: Icons.help_outline,
                    title: l10n.faq,
                    subtitle: l10n.faqSubtitle,
                    onTap: () => LegalContentSheet.show(
                      context,
                      contentType: LegalContentType.faq,
                      locale: Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  _buildDivider(),
                  _buildMenuItem(
                    context,
                    icon: Icons.coffee_outlined,
                    title: l10n.supportDeveloper,
                    subtitle: l10n.supportDeveloperSubtitle,
                    onTap: () => _showDonationDialog(context, l10n),
                  ),
                ], theme),

                const SizedBox(height: DesignTokens.space2xl),

                // Tech Stack
                _buildSectionTitle(l10n.builtWith),
                const SizedBox(height: DesignTokens.spaceLg),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildTechBadge('Flutter', colorScheme.primary),
                    _buildTechBadge('Dart', colorScheme.secondary),
                    _buildTechBadge('Bloc', colorScheme.tertiary),
                    _buildTechBadge('Clean Arch', colorScheme.error),
                    _buildTechBadge(
                      'GetIt',
                      colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space3xl),

                // Footer
                Text(
                  l10n.madeWithLoveBy,
                  style: TextStyleConst.caption.copyWith(
                    color: onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  l10n.allRightsReserved,
                  style: TextStyleConst.caption.copyWith(
                    fontSize: 10,
                    color: onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildUpdateCard(ThemeData theme) {
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final colorScheme = Theme.of(context).colorScheme;
        String status = l10n.checkForUpdates;
        IconData icon = Icons.refresh;
        final bool isLoading = state is UpdateChecking;

        if (isLoading) {
          status = l10n.checking;
        } else if (state is UpdateAvailable) {
          status = l10n.updateAvailable;
          icon = Icons.file_download_outlined;
        } else if (state is UpdateNotAvailable) {
          status = l10n.upToDate;
          icon = Icons.check_circle_outline;
        } else if (state is UpdateError) {
          status = l10n.checkFailed;
          icon = Icons.error_outline;
        }

        return Card(
          elevation: DesignTokens.elevationNone,
          color: theme.colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusXl)),
          child: InkWell(
            onTap: isLoading
                ? null
                : () {
                    context.read<UpdateCubit>().checkForUpdate(isManual: true);
                  },
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(icon, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appUpdates,
                          style: TextStyleConst.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          status,
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: theme.iconTheme.color?.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuCard(List<Widget> children, ThemeData theme) {
    return Card(
      elevation: DesignTokens.elevationNone,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl)),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isExternal = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyleConst.bodyLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyleConst.bodySmall.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isExternal
          ? Icon(Icons.open_in_new,
              size: 16, color: colorScheme.onSurfaceVariant)
          : Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
    );
  }

  Widget _buildTechBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.couldNotLaunchUrl(urlString))),
        );
      }
    }
  }

  void _showDonationDialog(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.coffee, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              l10n.supportDeveloper,
              style: TextStyleConst.titleLarge.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.donateMessage,
              style: TextStyleConst.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceLg),
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              child: Image.asset(
                'assets/images/donation_qris.jpeg',
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceLg),
            FilledButton.icon(
              onPressed: () =>
                  _launchURL('https://github.com/sponsors/shirokun20'),
              icon: const Icon(Icons.favorite),
              label: const Text('GitHub Sponsors'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEA4AAA),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceLg),
            Text(
              l10n.thankYouMessage,
              style: TextStyleConst.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              l10n.close,
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
