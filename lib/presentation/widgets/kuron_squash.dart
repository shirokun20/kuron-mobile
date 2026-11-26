import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

/// Press-feel wrapper: port of the gallery `squashy()`.
///
/// While pressed the child squashes vertically toward [low] (volume is kept
/// by widening with [wide]); on release a spring takes over, overshooting
/// past rest with a slight tilt toward the finger before settling.
///
/// Hit testing is translucent: inner buttons, ink wells and scrollables keep
/// receiving their gestures — this widget only mirrors them for the feel.
/// Under reduced motion the child renders plain with no animation.
class KuronSquash extends StatefulWidget {
  const KuronSquash({
    super.key,
    required this.child,
    this.low = 0.72,
    this.wide = 0.24,
    this.enabled = true,
  });

  final Widget child;

  /// Pressed vertical scale. Gallery: 0.5 primary, 0.72 secondary/ghost.
  final double low;

  /// Volume compensation: `scaleX = 1 + (1 - scaleY) * wide`.
  final double wide;

  final bool enabled;

  @override
  State<KuronSquash> createState() => _KuronSquashState();
}

class _KuronSquashState extends State<KuronSquash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _tiltSign = 0;

  /// Cached in [didChangeDependencies]: gesture callbacks (and recognizer
  /// teardown, which can fire after unmount starts) must never do an
  /// inherited-widget lookup on a deactivated context.
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: 1,
      lowerBound: 0.2,
      upperBound: 1.6,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = !MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _animated => widget.enabled && _animationsEnabled;

  void _press(TapDownDetails details) {
    if (!mounted || !_animated) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final dx = details.localPosition.dx - box.size.width / 2;
      _tiltSign = (dx / (box.size.width / 2)).clamp(-1.0, 1.0);
    } else {
      _tiltSign = 0;
    }
    _controller.animateTo(
      widget.low,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    if (!mounted || !_animated) return;
    // Overshoot past 1 with damping ratio ~0.39 (≈25% pop), then settle.
    _controller.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 320, damping: 14),
        _controller.value,
        1,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_animated) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: _press,
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final y = _controller.value;
          final x = 1 + (1 - y) * widget.wide;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..rotateZ(_tiltSign * (1 - y) * 0.08)
              ..scaleByDouble(x, y, 1, 1),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
