import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:nhasixapp/core/utils/native_theme_helper.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_auth/crotpedia_auth_cubit.dart';
import 'package:nhasixapp/presentation/cubits/source_auth/source_auth_cubit.dart';

class SourceLoginPage extends StatefulWidget {
  final String sourceId;
  final SourceAuthCubit? sourceAuthCubit;
  final SourceAuthCubit Function()? sourceAuthCubitFactory;

  const SourceLoginPage({
    super.key,
    required this.sourceId,
    this.sourceAuthCubit,
    this.sourceAuthCubitFactory,
  });

  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _justLoggedIn = false;

  @override
  void initState() {
    super.initState();
    // Ancestor-provided cubit; check once here, not on every build.
    if (widget.sourceId == 'crotpedia') {
      context.read<CrotpediaAuthCubit>().checkLoginStatus();
    }
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sourceId == 'crotpedia') {
      return BlocProvider.value(
        value: context.read<CrotpediaAuthCubit>(),
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              AppLocalizations.of(context)!
                  .sourceAuthLoginTitle(widget.sourceId),
            ),
          ),
          body: BlocConsumer<CrotpediaAuthCubit, CrotpediaAuthState>(
            listener: (context, state) {
              if (state is CrotpediaAuthError) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(state.message)));
              }
              if (state is CrotpediaAuthSuccess && _justLoggedIn) {
                _justLoggedIn = false;
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (context.mounted) Navigator.of(context).pop();
                });
              }
            },
            builder: (context, state) {
              if (state is CrotpediaAuthLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is CrotpediaAuthSuccess) {
                return _buildAuthenticatedSimple(
                  context,
                  username: state.username,
                  onLogout: () async {
                    await context.read<CrotpediaAuthCubit>().logout();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                );
              }
              return _buildLoginButton(
                context,
                onLogin: () => _launchCrotpediaLogin(context),
              );
            },
          ),
        ),
      );
    }

    // ── Default: SourceAuthCubit (nhentai etc) ──
    return BlocProvider(
      create: (_) =>
          (widget.sourceAuthCubitFactory != null
                ? widget.sourceAuthCubitFactory!()
                : (widget.sourceAuthCubit ?? context.read<SourceAuthCubit>()))
            ..initialize(widget.sourceId),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: BlocBuilder<SourceAuthCubit, SourceAuthState>(
            builder: (context, state) {
              final l10n = AppLocalizations.of(context)!;
              return Text(
                state.authenticated
                    ? l10n.sourceAuthProfileTitle(widget.sourceId)
                    : l10n.sourceAuthLoginTitle(widget.sourceId),
              );
            },
          ),
        ),
        body: BlocConsumer<SourceAuthCubit, SourceAuthState>(
          listener: (context, state) {
            if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
              final l10n = AppLocalizations.of(context)!;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(_mapError(l10n, state.errorMessage!))),
                );
            }
            if (state.authenticated && _justLoggedIn) {
              _justLoggedIn = false;
              Future.delayed(const Duration(milliseconds: 600), () {
                if (context.mounted) Navigator.of(context).pop();
              });
            }
          },
          builder: (context, state) {
            final l10n = AppLocalizations.of(context)!;
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.authenticated) {
              return _buildAuthenticatedFull(context, state, l10n);
            }
            return _buildLoginButton(
              context,
              onLogin: () => _launchTokenLogin(context),
            );
          },
        ),
      ),
    );
  }

  // ── Shared UI ──

  Widget _buildLoginButton(
    BuildContext context, {
    required VoidCallback onLogin,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.surfaceContainerLow,
                    Theme.of(context).colorScheme.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.lock_person,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              l10n.sourceAuthLoginTitle(widget.sourceId),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.sourceAuthLoginDescription,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 36),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: Text(l10n.sourceAuthSecureLogin),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticatedSimple(
    BuildContext context, {
    required String username,
    required VoidCallback onLogout,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final initial = username.substring(0, 1).toUpperCase();
    final avatarColor = HSLColor.fromAHSL(1.0, 200.0, 0.5, 0.4).toColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: _buildAvatarCard(
              context,
              avatarColor,
              initial,
              username,
              null,
            ),
          ),
          const SizedBox(height: 16),
          _buildConnectedBadge(context, l10n),
          const SizedBox(height: 32),
          _buildGimmick(context, l10n),
          const SizedBox(height: 28),
          _buildLogoutButton(context, onLogout, l10n),
        ],
      ),
    );
  }

  Widget _buildAuthenticatedFull(
    BuildContext context,
    SourceAuthState state,
    AppLocalizations l10n,
  ) {
    final initial = (state.accountName ?? 'U').substring(0, 1).toUpperCase();
    final hues = [170, 200, 220];
    final avatarColor = HSLColor.fromAHSL(
      1.0,
      hues[widget.sourceId.hashCode % hues.length].toDouble(),
      0.5,
      0.4,
    ).toColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: _buildAvatarCard(
              context,
              avatarColor,
              initial,
              state.accountName ?? l10n.sourceAuthUser,
              state.profileEmail,
            ),
          ),
          if (state.profileSlug != null) ...[
            const SizedBox(height: 8),
            Text(
              '${l10n.sourceAuthSlug}: ${state.profileSlug}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildConnectedBadge(context, l10n),
          const SizedBox(height: 32),
          _buildGimmick(context, l10n),
          const SizedBox(height: 28),
          _buildLogoutButton(context, () {
            context.read<SourceAuthCubit>().logout();
            if (context.mounted) Navigator.of(context).pop();
          }, l10n),
        ],
      ),
    );
  }

  Widget _buildAvatarCard(
    BuildContext context,
    Color avatarColor,
    String initial,
    String name,
    String? email,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
        gradient: LinearGradient(
          colors: [
            avatarColor.withValues(alpha: 0.2),
            avatarColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: avatarColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: avatarColor,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (email != null) ...[
            const SizedBox(height: 4),
            Text(
              email,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectedBadge(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.sourceAuthConnectedAccount,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGimmick(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.sourceAuthConnectedDescription,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(
    BuildContext context,
    VoidCallback onLogout,
    AppLocalizations l10n,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout, size: 18),
        label: Text(l10n.sourceAuthLogout),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
        ),
      ),
    );
  }

  // ── Login methods ──

  Future<void> _launchCrotpediaLogin(BuildContext context) async {
    try {
      final result = await KuronNative.instance.showLoginWebView(
        url: 'https://crotpedia.net/login/',
        autoCloseOnCookie: 'wordpress_logged_in',
        backgroundColor: NativeThemeHelper.backgroundColorHex,
        textColor: NativeThemeHelper.textColorHex,
      );
      if (!context.mounted) return;
      if (result != null && result['success'] == true) {
        final cookies =
            (result['cookies'] as List<dynamic>?)?.cast<String>() ?? [];
        await context.read<CrotpediaAuthCubit>().loginWithRawCookies(cookies);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.loginFailedError(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _launchTokenLogin(BuildContext context) async {
    final cubit = context.read<SourceAuthCubit>();
    final urls = cubit.getLoginUrls(widget.sourceId);
    if (urls == null) return;
    try {
      final result = await KuronNative.instance.showLoginWebView(
        url: urls.url,
        autoCloseOnCookie: urls.autoCloseCookie,
        successUrlFilters: urls.successFilters,
        clearCookies: true,
        backgroundColor: NativeThemeHelper.backgroundColorHex,
        textColor: NativeThemeHelper.textColorHex,
      );
      if (!context.mounted) return;
      if (result != null && result['success'] == true) {
        final cookies =
            (result['cookies'] as List<dynamic>?)?.cast<String>() ?? [];
        await cubit.saveWebViewSession(
          sourceId: widget.sourceId,
          cookies: cookies,
          cookieName: urls.autoCloseCookie,
        );
        _justLoggedIn = true;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.loginFailedError(e.toString()),
            ),
          ),
        );
      }
    }
  }

  String _mapError(AppLocalizations l10n, String raw) {
    final text = raw.toLowerCase();
    if (text.contains('timeout')) return l10n.errorConnectionTimeout;
    if (text.contains('connection')) return l10n.errorNetwork;
    if (text.contains('session expired') ||
        text.contains('unauthorized') ||
        text.contains('401') ||
        text.contains('403')) {
      return l10n.errorServer;
    }
    if (text.contains('500')) return l10n.errorServer;
    return l10n.errorUnknown;
  }
}
