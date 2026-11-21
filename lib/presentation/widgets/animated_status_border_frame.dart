import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class AnimatedStatusBorderFrame extends StatefulWidget {
  const AnimatedStatusBorderFrame({
    super.key,
    required this.child,
    required this.colors,
    required this.borderRadius,
    this.enabled = true,
    this.strokeWidth = 1.6,
    this.duration = const Duration(seconds: 4),
    this.shadowColor,
    this.animation,
  });

  final Widget child;
  final List<Color> colors;
  final BorderRadius borderRadius;
  final bool enabled;
  final double strokeWidth;
  final Duration duration;
  final Color? shadowColor;
  final Animation<double>? animation;
  @override
  State<AnimatedStatusBorderFrame> createState() =>
      _AnimatedStatusBorderFrameState();
}

class _AnimatedStatusBorderFrameState extends State<AnimatedStatusBorderFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double> get _effectiveAnimation => widget.animation ?? _controller!;

  @override
  void initState() {
    super.initState();
    if (widget.animation == null) {
      _controller = AnimationController(vsync: this, duration: widget.duration)
        ..forward()
        ..repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedStatusBorderFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != null && _controller != null) {
      _controller!.dispose();
      _controller = null;
    } else if (widget.animation == null && _controller == null) {
      _controller = AnimationController(vsync: this, duration: widget.duration)
        ..forward()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.colors.isEmpty) {
      return widget.child;
    }

    final colors = widget.colors.length == 1
        ? <Color>[
            widget.colors.first.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            widget.colors.first,
            widget.colors.first.withValues(alpha: 0.42),
            widget.colors.first,
          ]
        : widget.colors;

    return AnimatedBuilder(
      animation: _effectiveAnimation,
      child: widget.child,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: SweepGradient(
              transform: GradientRotation(
                _effectiveAnimation.value * math.pi * 2,
              ),
              colors: colors,
            ),
            boxShadow: [
              if (widget.shadowColor != null)
                BoxShadow(
                  color: widget.shadowColor!,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.strokeWidth),
            child: child,
          ),
        );
      },
    );
  }
}
