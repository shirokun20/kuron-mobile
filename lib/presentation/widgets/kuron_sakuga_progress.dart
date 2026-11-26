import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

/// Sakuga-styled download progress bar inspired by `progress.js`:
/// eases smoothly toward [progress], renders skewed highlight streaks inside
/// the fill, and rides a rolling storm cloud + speed lines on the leading edge
/// when [KuronMotionPolicy.effectiveMode] is active.
///
/// In `quiet`, `reducedMotion`, `note` themes, or [isReader], it degrades to a
/// clean, static progress bar with zero cloud or animation.
class KuronSakugaProgressBar extends StatefulWidget {
  const KuronSakugaProgressBar({
    super.key,
    required this.progress,
    required this.height,
    required this.borderRadius,
    required this.color,
    required this.backgroundColor,
    this.isReader = false,
  });

  final double progress;
  final double height;
  final BorderRadius borderRadius;
  final Color color;
  final Color backgroundColor;
  final bool isReader;

  @override
  State<KuronSakugaProgressBar> createState() => _KuronSakugaProgressBarState();
}

class _KuronSakugaProgressBarState extends State<KuronSakugaProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _boilController;

  @override
  void initState() {
    super.initState();
    _boilController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void dispose() {
    _boilController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = KuronMotionPolicy.effectiveMode(
      context,
      isReader: widget.isReader,
    );
    final sakugaEnabled = mode != KuronFxMode.quiet;
    final target = widget.progress.clamp(0.0, 1.0);
    final shouldBoil = sakugaEnabled && target > 0.015 && target < 1.0;

    if (shouldBoil && !_boilController.isAnimating) {
      _boilController.repeat();
    } else if (!shouldBoil && _boilController.isAnimating) {
      _boilController.stop();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: sakugaEnabled
            ? const Duration(milliseconds: 260)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) => AnimatedBuilder(
          animation: _boilController,
          builder: (context, _) => CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _SakugaProgressPainter(
              progress: animatedProgress,
              boilPhase: _boilController.value * math.pi * 2,
              sakugaEnabled: sakugaEnabled,
              borderRadius: widget.borderRadius,
              fillColor: widget.color,
              trackColor: widget.backgroundColor,
              cloudShade: colorScheme.primaryContainer,
              cloudOutline: colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _SakugaProgressPainter extends CustomPainter {
  const _SakugaProgressPainter({
    required this.progress,
    required this.boilPhase,
    required this.sakugaEnabled,
    required this.borderRadius,
    required this.fillColor,
    required this.trackColor,
    required this.cloudShade,
    required this.cloudOutline,
  });

  final double progress;
  final double boilPhase;
  final bool sakugaEnabled;
  final BorderRadius borderRadius;
  final Color fillColor;
  final Color trackColor;
  final Color cloudShade;
  final Color cloudOutline;

  /// Cumulus cloud lobes from `progress.js` (`LOBES`), normalized to radius 1.
  static const List<(double dx, double dy, double r)> _lobes = [
    (0.0, -0.95, 1.0),
    (0.78, -0.55, 0.74),
    (-0.72, -0.78, 0.72),
    (0.36, -1.7, 0.7),
    (-0.4, -1.62, 0.62),
    (1.1, -1.32, 0.52),
    (-1.18, -0.28, 0.52),
    (0.62, 0.3, 0.5),
    (-0.86, 0.5, 0.52),
    (-1.5, 0.82, 0.38),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // 1. Track + clipped progress fill.
    canvas.drawRRect(rrect, Paint()..color = trackColor);
    final fillW = (size.width * progress).clamp(0.0, size.width);
    if (fillW > 0) {
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillW, size.height),
        Paint()..color = fillColor,
      );

      // Two skewed highlight streaks (`progress.js` .bar i::before / ::after).
      if (sakugaEnabled && fillW > 28) {
        final streakPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.32)
          ..style = PaintingStyle.fill;
        canvas.save();
        canvas.translate(math.min(fillW - 22, 18.0), 4);
        canvas.skew(-0.48, 0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 8, 9),
            const Radius.circular(2),
          ),
          streakPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(13, 0, 5, 9),
            const Radius.circular(2),
          ),
          streakPaint,
        );
        canvas.restore();
      }
      canvas.restore();
    }

    // 2. Leading-edge storm cloud + trailing speed lines (`progress.js`).
    if (!sakugaEnabled || progress <= 0.015 || progress >= 1.0) return;

    final leadX = fillW.clamp(8.0, size.width - 4.0);
    final scale = (5.0 + 9.0 * math.sqrt(progress)).clamp(5.0, 14.0);
    final cloudCenter = Offset(leadX, 2.0);

    // Trailing speed lines behind the cloud.
    final linePaint = Paint()
      ..color = fillColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final y = cloudCenter.dy - scale * (0.45 + i * 0.55);
      final x0 = leadX - scale * 1.3;
      final x1 = x0 - (12.0 + 10.0 * progress - i * 4.0);
      if (x1 > 0) {
        canvas.drawLine(Offset(x0, y), Offset(x1, y), linePaint);
      }
    }

    final cloudPath = Path();
    for (var i = 0; i < _lobes.length; i++) {
      final (lx, ly, lr) = _lobes[i];
      final boil = 1.0 + 0.12 * math.sin(boilPhase + i * 1.1);
      final cx = cloudCenter.dx + lx * scale;
      final cy = cloudCenter.dy + ly * scale * 0.72;
      final r = lr * scale * 0.62 * boil;
      if (r > 0.5) {
        cloudPath.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      }
    }

    canvas.drawPath(
      cloudPath,
      Paint()
        ..color = cloudOutline.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawPath(cloudPath, Paint()..color = cloudShade);
    canvas.save();
    canvas.clipPath(cloudPath);
    canvas.translate(-scale * 0.14, -scale * 0.22);
    canvas.drawPath(cloudPath, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SakugaProgressPainter old) =>
      old.progress != progress ||
      old.boilPhase != boilPhase ||
      old.sakugaEnabled != sakugaEnabled ||
      old.fillColor != fillColor ||
      old.trackColor != trackColor;
}
