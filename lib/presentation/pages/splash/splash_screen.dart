import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/constants/colors_const.dart'
    show AppColors, KuronColors;
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/core/constants/text_style_const.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/routing/app_route.dart';
import 'package:nhasixapp/presentation/blocs/splash/splash_bloc.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<SplashBloc>(),
      child: const SplashMainWidget(),
    );
  }
}

class SplashMainWidget extends StatefulWidget {
  const SplashMainWidget({super.key});

  @override
  State<SplashMainWidget> createState() => _SplashMainWidgetState();
}

class _SplashMainWidgetState extends State<SplashMainWidget>
    with TickerProviderStateMixin {
  late AnimationController _dotsAnimationController;
  late List<Animation<double>> _dotAnimations;
  late AnimationController _successAnimationController;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successOpacityAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize dots animation controller
    _dotsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Create staggered animations for each dot
    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _dotsAnimationController,
          curve: Interval(
            index * 0.2,
            0.6 + (index * 0.2),
            curve: Curves.easeInOut,
          ),
        ),
      );
    });

    // Start dots animation
    _dotsAnimationController.repeat(reverse: true);

    // Initialize success animation controller
    _successAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400), // Optimized from 800ms
      vsync: this,
    );

    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _successOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Start the splash process after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SplashBloc>().add(SplashStartedEvent());
    });
  }

  void _showOfflineOptionsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              ),
              child: Icon(
                Icons.wifi_off,
                color: theme.colorScheme.onErrorContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.offlineMode,
              style: TextStyleConst.headingMedium.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.noInternetConnection,
              style: TextStyleConst.bodyMedium.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: DesignTokens.spaceSm),
            Text(
              l10n.youAreOffline,
              style: TextStyleConst.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              dialogContext.pop();
              context.read<SplashBloc>().add(SplashRetryBypassEvent());
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.retry,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              dialogContext.pop();
              context.read<SplashBloc>().add(SplashForceOfflineModeEvent());
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.continueReading,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              dialogContext.pop();
              SystemNavigator.pop();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.exit_to_app,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.exitApp,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dotsAnimationController.dispose();
    _successAnimationController.dispose();
    super.dispose();
  }

  /// Mascot mood synced to the splash process (same mapping as
  /// `resolveKuroMood` in openspec kuro-streak-widget-card).
  KuroMood _moodForState(SplashState state) {
    if (state is SplashBypassInProgress) return KuroMood.reader;
    if (state is SplashOfflineEmpty) return KuroMood.tsundere;
    if (state is SplashError) return KuroMood.cry;
    return KuroMood.happy;
  }

  /// Sync progress shown on the ring around the mascot.
  double _progressForState(SplashState state) {
    if (state is SplashInitializing) return 0.3;
    if (state is SplashBypassInProgress) return 0.7;
    if (state is SplashSuccess ||
        state is SplashOfflineReady ||
        state is SplashOfflineMode) {
      return 1.0;
    }
    return 0.0;
  }

  String _resolveSplashMessage(
    BuildContext context,
    String messageKeyOrText, {
    int? offlineCount,
  }) =>
      resolveSplashMessage(
        AppLocalizations.of(context)!,
        messageKeyOrText,
        offlineCount: offlineCount,
      );

  @override
  Widget build(BuildContext context) {
    final kuron = Theme.of(context).extension<KuronColors>();

    return Scaffold(
      backgroundColor: kuron?.readerBg ?? Theme.of(context).colorScheme.surface,
      body: BlocConsumer<SplashBloc, SplashState>(
        listenWhen: (previous, current) => previous != current,
        listener: (_, state) {
          if (!mounted) return;

          if (state is SplashSuccess) {
            // Stop dots animation and start success animation
            _dotsAnimationController.stop();
            _successAnimationController.forward().then((_) {
              // Navigate after success animation completes
              Timer(DesignTokens.durationPageTurn, () {
                // Optimized from 1200ms
                if (mounted) {
                  context.go(AppRoute.main);
                }
              });
            });
          } else if (state is SplashOfflineReady) {
            // Has offline content - auto navigate to main
            _dotsAnimationController.stop();
            _successAnimationController.forward().then((_) {
              Timer(DesignTokens.durationPageTurn, () {
                if (mounted) {
                  context.go(AppRoute.main);
                }
              });
            });
          } else if (state is SplashOfflineMode) {
            // Limited offline mode - still can navigate
            _dotsAnimationController.stop();
            _successAnimationController.forward().then((_) {
              Timer(DesignTokens.durationPageTurn, () {
                if (mounted) {
                  context.go(AppRoute.main);
                }
              });
            });
          } else if (state is SplashError) {
            // Stop dots animation on error
            _dotsAnimationController.stop();
          }
        },
        builder: (context, state) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Kuro mascot: mood follows bloc state, sync ring wraps it.
                // Initializing -> happy, bypass -> reader, success -> happy,
                // offline-empty -> tsundere, error -> cry.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _progressForState(state)),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, ring, __) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Segmented sync ring (ikut Figma Group.png: 4 segmen
                        // rounded, yang nyala = round(progress*4)).
                        _SyncRing(progress: ring, size: 260),
                        // inner thin ring (ikut referensi: ring tebal progres +
                        // ring tipis dalam).
                        Container(
                          width: 216,
                          height: 216,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  AppColors.brandCoral.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer
                                .withValues(alpha: 0.3),
                            border: Border.all(
                              color:
                                  AppColors.brandCoral.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.brandCoral.withValues(alpha: 0.2),
                                blurRadius: 30,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: KuroMascot(
                              key: ValueKey(_moodForState(state)),
                              mood: _moodForState(state),
                              size: 184,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 40),

                // App title (proporsi ikut Figma: judul 0.21 lebar layar)
                Text(
                  AppLocalizations.of(context)!.appTitle,
                  style: TextStyleConst.headingLarge.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.2,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: DesignTokens.spaceSm),
                Text(
                  AppLocalizations.of(context)?.appSubtitle ??
                      AppLocalizations.of(context)!.enhancedReadingExperience,
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 40),

                // Loading States with enhanced progress indicators
                if (state is SplashInitializing ||
                    state is SplashBypassInProgress)
                  Column(
                    children: [
                      // Single status pill (ikut Figma Group.png: 1 pill +
                      // dots, simple. Gear + detail text + linear bar dibuang).
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer
                                .withValues(alpha: 0.5),
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radius2xl),
                          ),
                          child: Text(
                            state is SplashInitializing
                                ? '${AppLocalizations.of(context)?.settingUpComponents ?? AppLocalizations.of(context)!.settingUpConnection} ${(_progressForState(state) * 100).toInt()}%'
                                : '${AppLocalizations.of(context)?.bypassingProtection ?? AppLocalizations.of(context)!.bypassingProtection} ${(_progressForState(state) * 100).toInt()}%',
                            style: TextStyleConst.bodyMedium.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildProgressDots(),
                    ],
                  ),

                // Success State
                if (state is SplashSuccess) _buildSuccessState(state),

                // Offline States
                if (state is SplashOfflineDetected)
                  Column(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                          strokeWidth: 4,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceXl),
                      Icon(
                        Icons.wifi_off,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _resolveSplashMessage(context, state.message),
                          style: TextStyleConst.headingSmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                      _buildProgressDots(),
                    ],
                  ),

                if (state is SplashOfflineReady)
                  Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.offline_bolt,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceXl),
                      Text(
                        AppLocalizations.of(context)!
                            .offlineContentAvailableLabel,
                        style: TextStyleConst.headingMedium.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: DesignTokens.spaceSm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _resolveSplashMessage(
                            context,
                            state.message,
                            offlineCount: state.offlineContentCount,
                          ),
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                      _buildProgressDots(),
                    ],
                  ),

                if (state is SplashOfflineEmpty)
                  Column(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(height: DesignTokens.spaceXl),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          AppLocalizations.of(context)!.noInternetConnection,
                          style: TextStyleConst.headingMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceSm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _resolveSplashMessage(context, state.message),
                          style: TextStyleConst.bodyMedium.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.space2xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _showOfflineOptionsDialog(context),
                            icon: const Icon(Icons.wifi_off),
                            label: Text(
                                AppLocalizations.of(context)!.offlineModeLabel),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              textStyle: TextStyleConst.buttonMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                if (state is SplashOfflineMode)
                  Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.offline_pin,
                          size: 48,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceXl),
                      Text(
                        AppLocalizations.of(context)!.offlineModeEnabled,
                        style: TextStyleConst.headingMedium.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: DesignTokens.spaceSm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _resolveSplashMessage(context, state.message),
                          style: TextStyleConst.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                      _buildProgressDots(),
                    ],
                  ),

                // Error State with Retry Button
                if (state is SplashError && state.canRetry)
                  Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      SizedBox(height: DesignTokens.spaceLg),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          AppLocalizations.of(context)?.connectionFailed ??
                              AppLocalizations.of(context)!.connectionFailed,
                          style: TextStyleConst.statusError.copyWith(
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: DesignTokens.spaceXl),
                      ElevatedButton.icon(
                        onPressed: () => context
                            .read<SplashBloc>()
                            .add(SplashRetryBypassEvent()),
                        icon: const Icon(Icons.refresh),
                        label: Text(AppLocalizations.of(context)!.retry),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: TextStyleConst.buttonMedium,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuccessState(SplashSuccess state) {
    return AnimatedBuilder(
      animation: _successAnimationController,
      builder: (context, child) {
        return Opacity(
          opacity: _successOpacityAnimation.value,
          child: Transform.scale(
            scale: _successScaleAnimation.value,
            child: Column(
              children: [
                // Success badge: coral penuh + centang gelap (ikut Figma).
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 56,
                    color: AppColors.brandDark,
                  ),
                ),

                // Success title (proporsi Figma: 0.33 lebar layar)
                Text(
                  AppLocalizations.of(context)!.readyToGo,
                  style: TextStyleConst.headingMedium.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: DesignTokens.spaceSm),

                // Success message
                Text(
                  _resolveSplashMessage(context, state.message),
                  style: TextStyleConst.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: DesignTokens.spaceMd),

                // Additional success info
                Text(
                  AppLocalizations.of(context)?.launchingApp ??
                      AppLocalizations.of(context)!.launchingApp,
                  style: TextStyleConst.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: DesignTokens.spaceLg),

                // Success indicator dots
                _buildSuccessDots(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _buildProgressDots() {
    return AnimatedBuilder(
      animation: _dotsAnimationController,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.brandCoral.withValues(
                  alpha: _dotAnimations[index].value,
                ),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Segmented sync ring (ikut Figma Group.png): 4 busur rounded dengan gap,
/// jumlah yang nyala = round(progress * 4), searah jarum jam dari atas.
class _SyncRing extends StatelessWidget {
  final double progress;
  final double size;

  const _SyncRing({required this.progress, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SyncRingPainter(
          progress: progress,
          lit: AppColors.brandCoral.withValues(alpha: 0.9),
          dim: AppColors.brandCoral.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

class _SyncRingPainter extends CustomPainter {
  final double progress;
  final Color lit;
  final Color dim;

  const _SyncRingPainter({
    required this.progress,
    required this.lit,
    required this.dim,
  });

  static const _sweep = 70 * 3.141592653589793 / 180;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    // Ready = lingkaran PENUH kontinyu (segmen selalu ninggalin gap,
    // makanya kemarin ready pun keliatan putus).
    if (progress >= 1.0) {
      canvas.drawArc(rect, 0, 3.141592653589793 * 2, false, paint..color = lit);
      return;
    }
    final litCount = (progress.clamp(0.0, 1.0) * 4).round();
    // top, right, bottom, left (canvas rad: 0 = timur, searah jarum jam).
    const starts = [-125.0, -35.0, 55.0, 145.0];
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(
        rect,
        starts[i] * 3.141592653589793 / 180,
        _sweep,
        false,
        paint..color = i < litCount ? lit : dim,
      );
    }
  }

  @override
  bool shouldRepaint(_SyncRingPainter old) => old.progress != progress;
}

final _splashLogger = Logger();

/// Resolve a splash message token to text the reader can read.
///
/// `token` is `key` or `key:payload`. Public and pure so the whole emission
/// surface can be walked in a test: while this was a private method that
/// returned its argument for anything unmapped, nine tokens — including two
/// inline English sentences — reached the screen untranslated.
String resolveSplashMessage(
  AppLocalizations l10n,
  String token, {
  int? offlineCount,
}) {
  final separatorIndex = token.indexOf(':');
  final key = separatorIndex == -1 ? token : token.substring(0, separatorIndex);
  final payload =
      separatorIndex == -1 ? '' : token.substring(separatorIndex + 1).trim();

  // Every error key takes an `{error}` placeholder. Emitted without one, the
  // sentence would end in a dangling colon, so fall back to the generic.
  String errorMessage(String Function(String) withError) =>
      payload.isNotEmpty ? withError(payload) : l10n.unexpectedError;

  switch (key) {
    // Legacy English sentences still emitted by SplashState defaults.
    case 'Initializing...':
    case 'initializingApplication':
      return l10n.initializingApplication;
    case 'Bypassing Cloudflare protection...':
      return l10n.bypassingProtection;
    case 'Successfully bypassed Cloudflare protection':
      return l10n.connectedSuccess;
    case 'No internet connection. Checking offline content...':
      return l10n.noInternetCheckOffline;
    case 'Offline Mode (Limited Features)':
      return l10n.offlineLimitedFeatures;

    // SplashBloc — configuration and tags.
    case 'loadingConfigMsg':
      return l10n.loadingConfigMsg;
    case 'initTagsDbMsg':
      return l10n.initTagsDbMsg;
    case 'downloadingTagsMsg':
      return payload.isNotEmpty
          ? l10n.downloadingTagsMsg(payload)
          : l10n.loadingConfigMsg;
    case 'downloadingInitConfig':
      return l10n.downloadingInitConfig;

    // RemoteConfigService.smartInitialize, while the app boots.
    case 'loadingBundledDefaults':
      return l10n.loadingBundledDefaults;
    case 'restoringLocalSources':
      return l10n.restoringLocalSources;
    case 'loadingTagsConfig':
      return l10n.loadingTagsConfig;
    case 'sourceConfigsReady':
      return l10n.sourceConfigsReady;
    case 'configReady':
      return l10n.configReady;

    // SplashBloc — bypass and connectivity.
    case 'checkingConnection':
      return l10n.checkingConnection;
    case 'connectingMsg':
      return l10n.connectingMsg;
    case 'connectingToSite':
      return l10n.connectingToSite;
    case 'initBypassMsg':
      return l10n.initBypassMsg;
    case 'connectedSuccess':
      return l10n.connectedSuccess;
    case 'readyLastSync':
      return payload.isNotEmpty
          ? l10n.readyLastSync(payload)
          : l10n.readyLastSyncUnavailable;

    // SplashBloc — failures.
    case 'initFailedMsg':
      return errorMessage(l10n.initFailedMsg);
    case 'failedToConnect':
      return l10n.failedToConnect;
    case 'failedInitBypass':
      return errorMessage(l10n.failedInitBypass);
    case 'bypassFailed':
      return l10n.bypassFailed;
    case 'offlineBypassFailed':
      return l10n.offlineBypassFailed;
    case 'errorBypassResult':
      return errorMessage(l10n.errorBypassResult);
    case 'failedEnableOffline':
      return errorMessage(l10n.failedEnableOffline);

    // SplashBloc — offline path.
    case 'noInternetCheckOffline':
      return l10n.noInternetCheckOffline;
    case 'noInternetNoOffline':
      return l10n.noInternetNoOffline;
    case 'unableCheckOffline':
      return errorMessage(l10n.unableCheckOffline);
    case 'failedCheckOffline':
      return errorMessage(l10n.failedCheckOffline);
    case 'failedLoadOffline':
      return errorMessage(l10n.failedLoadOffline);
    case 'foundOfflineItems':
      return l10n.foundOfflineItems(offlineCount ?? 0);
    case 'offlineModeAvailable':
      return l10n.offlineModeAvailable(offlineCount ?? 0);
    case 'noOfflineContentAvailable':
      return l10n.noOfflineContentAvailable;
    case 'offlineLimitedFeatures':
      return l10n.offlineLimitedFeatures;
    case 'readyOfflineLimited':
      return l10n.readyOfflineLimited;
    case 'readyOfflineLimitedFeatures':
      return l10n.readyOfflineLimitedFeatures;
    case 'readyOffline':
      return l10n.readyOffline;
    default:
      // Returning the argument here is what let an unmapped token paint its
      // own camelCase key on screen. Log it where a developer looks; show the
      // reader something readable.
      _splashLogger.w('unmapped splash message token "$key"');
      return l10n.initializingApplication;
  }
}
