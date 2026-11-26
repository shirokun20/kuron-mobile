import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/constants/design_tokens.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final slide = (slidePercent * 2 - 1) * bounds.width;
    return Matrix4.translationValues(slide, 0.0, 0.0);
  }
}

class KuronShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;

  const KuronShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 1500),
  });

  @override
  State<KuronShimmer> createState() => _KuronShimmerState();
}

class ShimmerControllerScope extends InheritedWidget {
  final Animation<double> animation;

  const ShimmerControllerScope({
    super.key,
    required this.animation,
    required super.child,
  });

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ShimmerControllerScope>()
        ?.animation;
  }

  @override
  bool updateShouldNotify(ShimmerControllerScope oldWidget) =>
      animation != oldWidget.animation;
}

/// Counts live [KuronShimmer] descendants. The scope ticker only runs while
/// at least one shimmer is mounted, so wrapping a live feed does not leave an
/// idle 60–120fps ticker running after loading finishes.
class ShimmerActivity extends ValueNotifier<int> {
  ShimmerActivity() : super(0);
}

class ShimmerActivityScope extends InheritedWidget {
  const ShimmerActivityScope({
    super.key,
    required this.activity,
    required super.child,
  });

  final ShimmerActivity activity;

  static ShimmerActivity? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ShimmerActivityScope>()
      ?.activity;

  @override
  bool updateShouldNotify(ShimmerActivityScope oldWidget) => false;
}

class ShimmerScope extends StatefulWidget {
  final Widget child;
  final Duration period;

  const ShimmerScope({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final ShimmerActivity _activity = ShimmerActivity();
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    _activity.addListener(_onActivityChanged);
  }

  void _onActivityChanged() {
    if (_reducedMotion) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if (_activity.value > 0) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = KuronMotionPolicy.reducedMotion(context);
    _onActivityChanged();
  }

  @override
  void dispose() {
    _activity.removeListener(_onActivityChanged);
    _activity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShimmerActivityScope(
      activity: _activity,
      child: ShimmerControllerScope(
        animation: _controller,
        child: widget.child,
      ),
    );
  }
}

class _KuronShimmerState extends State<KuronShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _ownController;
  ShimmerActivity? _activity;

  AnimationController _ensureOwnController() {
    return _ownController ??= AnimationController(
      vsync: this,
      duration: widget.period,
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = ShimmerActivityScope.maybeOf(context);
    if (!identical(activity, _activity)) {
      if (_activity != null) _activity!.value--;
      _activity = activity;
      if (activity != null) activity.value++;
    }
    // If this shimmer later lands under a ShimmerScope, the private ticker
    // becomes redundant: stop and release it instead of running two clocks.
    if (_ownController != null &&
        ShimmerControllerScope.maybeOf(context) != null) {
      _ownController!.stop();
      _ownController!.dispose();
      _ownController = null;
    }
  }

  @override
  void didUpdateWidget(KuronShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ownController != null) {
      if (widget.enabled != oldWidget.enabled) {
        if (widget.enabled) {
          _ownController!.repeat();
        } else {
          _ownController!.stop();
        }
      }
      if (widget.period != oldWidget.period) {
        _ownController!.duration = widget.period;
        if (widget.enabled) {
          _ownController!.repeat();
        }
      }
    }
  }

  @override
  void dispose() {
    if (_activity != null) _activity!.value--;
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled && KuronMotionPolicy.ambientAnimationsEnabled(context);
    if (!enabled) {
      _ownController?.stop();
      return RepaintBoundary(child: widget.child);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final baseColor =
        widget.baseColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final highlightColor =
        widget.highlightColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.1);

    final sharedAnimation = ShimmerControllerScope.maybeOf(context);
    final effectiveAnimation = sharedAnimation ?? _ensureOwnController();

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: effectiveAnimation,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: [baseColor, highlightColor, baseColor],
                stops: const [0.1, 0.5, 0.9],
                begin: const Alignment(-1.0, -0.3),
                end: const Alignment(1.0, 0.3),
                transform: _SlidingGradientTransform(
                  slidePercent: effectiveAnimation.value,
                ),
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// Base shimmer widget providing consistent styling across the app
class BaseShimmer extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const BaseShimmer({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return KuronShimmer(enabled: enabled, child: child);
  }
}

// Generic shimmer loading widget with customizable dimensions
class ShimmerBox extends StatelessWidget {
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  const ShimmerBox({
    super.key,
    this.height,
    this.width,
    this.borderRadius,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      margin: margin,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius:
            borderRadius ?? BorderRadius.circular(DesignTokens.radiusSm),
      ),
    );
  }
}

// Shimmer placeholder for content card
class ContentCardShimmer extends StatelessWidget {
  const ContentCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BaseShimmer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            const ShimmerBox(
              height: 120,
              width: 90,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            // Content placeholder
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    const ShimmerBox(height: 16, width: double.infinity),
                    const SizedBox(height: 8),
                    // Subtitle
                    ShimmerBox(
                      height: 14,
                      width: MediaQuery.of(context).size.width * 0.4,
                    ),
                    const SizedBox(height: 12),
                    // Tags
                    Row(
                      children: List.generate(
                        3,
                        (index) => ShimmerBox(
                          height: 20,
                          width: 60,
                          margin: const EdgeInsets.only(right: 8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Stats
                    const Row(
                      children: [
                        ShimmerBox(
                          height: 12,
                          width: 50,
                          margin: EdgeInsets.only(right: 12),
                        ),
                        ShimmerBox(height: 12, width: 50),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shimmer placeholder for grid content card
class ContentGridCardShimmer extends StatelessWidget {
  const ContentGridCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BaseShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            const ShimmerBox(
              height: 200,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            // Content placeholder
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const ShimmerBox(height: 16, width: double.infinity),
                  const SizedBox(height: 8),
                  // Subtitle
                  ShimmerBox(
                    height: 14,
                    width: MediaQuery.of(context).size.width * 0.3,
                  ),
                  const SizedBox(height: 8),
                  // Tags
                  Row(
                    children: List.generate(
                      2,
                      (index) => ShimmerBox(
                        height: 20,
                        width: 50,
                        margin: const EdgeInsets.only(right: 8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shimmer placeholder for list view
class ListShimmer extends StatelessWidget {
  final int itemCount;

  const ListShimmer({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) => const ContentCardShimmer(),
      ),
    );
  }
}

// Shimmer placeholder for grid view
class GridShimmer extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const GridShimmer({super.key, this.itemCount = 6, this.crossAxisCount = 2});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 600
              ? 3
              : crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ContentGridCardShimmer(),
      ),
    );
  }
}

// Shimmer placeholder for reader page thumbnail
class ReaderThumbnailShimmer extends StatelessWidget {
  const ReaderThumbnailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseShimmer(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: const Center(
          child: ShimmerBox(
            height: 80,
            width: 60,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ),
    );
  }
}

// Shimmer placeholder for Genre List
class GenreListShimmer extends StatelessWidget {
  const GenreListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ShimmerScope(
      child: CustomScrollView(
        slivers: [
          // Header shimmer
          SliverToBoxAdapter(
            child: BaseShimmer(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    ShimmerBox(
                      height: 20,
                      width: 20,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ShimmerBox(height: 20, width: 140),
                    const Spacer(),
                    ShimmerBox(
                      height: 24,
                      width: 36,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusLg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Grid shimmer
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                return BaseShimmer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusXl,
                      ),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ShimmerBox(
                            height: 14,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShimmerBox(
                          width: 32,
                          height: 20,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ],
                    ),
                  ),
                );
              }, childCount: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple List Shimmer for text-only lists (like Doujin List)
class SimpleListShimmer extends StatelessWidget {
  const SimpleListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 15,
        itemBuilder: (context, index) {
          return BaseShimmer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusSm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
