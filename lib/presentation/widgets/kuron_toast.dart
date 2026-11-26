import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_snack_bar_content.dart';

/// Kuron's own success toast, replacing the plain SnackBar at the two
/// "download started" moments.
///
/// Katalog toast §10 pacing (≈3.7 s total): streak-in from x=-280 with
/// `Spring(280, 18)`, v0=1000 over 0.5 s; land at x>-10 with ground
/// puffs/shards/ticks and the dotted BYAR! burst; 2.6 s hold; 0.6 s shrink-out
/// (`Spring(500, 26)` → 0). Effects leave by shrinking, never by fading.
/// Only one toast is ever mounted; it reuses the single [KuronFx] ticker host,
/// the baked word cache and [KuronSnackBarContent]'s anchor math — no assets.
///
/// [KuronMotionPolicy] is the only gate: quiet / reduced motion / note themes
/// / reader get a plain SnackBar (or nothing when no messenger exists), so the
/// caller's state change always lands and no decoration leaks into those modes.
abstract final class KuronToast {
  static const Duration totalDuration = Duration(milliseconds: 3700);
  static const double _showSeconds = 0.5;
  static const double _hideStart = 3.1;
  static const double _hideSeconds = 0.6;

  static OverlayEntry? _entry;
  static Timer? _timer;
  static AnimationController? _controller;

  /// Katalog toast §10: `sx` spring -280→0, k280/d18, v0=1000.
  static final SpringSimulation _streak = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 280, damping: 18),
    -280,
    0,
    1000,
  );

  /// Katalog hide: `ss` shrink to 0, k500 (damping from the same `ss` 420/26
  /// family). Scale only — opacity is never animated.
  static final SpringSimulation _hide = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 500, damping: 26),
    1,
    0,
    0,
  );

  static bool get isActive => _entry != null;

  static void show(
    BuildContext context, {
    required String message,
    bool isReader = false,
  }) {
    final mode = KuronMotionPolicy.effectiveMode(
      context,
      isReader: isReader,
      listen: false,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (mode == KuronFxMode.quiet) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final vsync = KuronFx.activeController?.vsync;
    if (overlay == null || vsync == null) {
      // No host (isolated widget/early startup): keep the message, drop the FX.
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    dismiss();
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final monochrome = KuronMotionPolicy.isNoteTheme(context, listen: false);

    // Reuse the snack-bar anchor math with a synthetic content box standing in
    // for the toast surface (no SnackBar ancestor exists for a custom toast).
    final safeBottom = media.viewPadding.bottom;
    final surfaceBottom = media.size.height - safeBottom - 16;
    final contentRect = Rect.fromLTWH(
      16,
      surfaceBottom - 48,
      math.max(0.0, media.size.width - 32),
      48,
    );
    final anchor = KuronSnackBarContent.anchorRectOf(context, contentRect);
    final toastKey = GlobalKey();

    final controller = AnimationController(
      vsync: vsync,
      duration: totalDuration,
    );
    var landed = false;
    _controller = controller;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      opaque: false,
      builder: (context) => Directionality(
        textDirection: direction,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value * (totalDuration.inMilliseconds / 1000);
            if (!landed && t >= _showSeconds) {
              landed = true;
              // Fire off-frame: measure the actual laid-out toast box so tall
              // multi-line messages never overlap or cover the BYAR! burst.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_entry == entry && _controller == controller) {
                  final liveRect = toastKey.currentContext != null
                      ? KuronFx.targetRectOf(toastKey.currentContext!)
                      : null;
                  final base = liveRect ?? contentRect;
                  final liveAnchor = Rect.fromLTWH(
                    base.center.dx - 24,
                    (base.top - 28).clamp(
                      0.0,
                      math.max(0.0, media.size.height - safeBottom - 12),
                    ),
                    48,
                    12,
                  );
                  KuronFx.triggerOn(
                    context,
                    rect: liveAnchor,
                    kind: KuronFxKind.toastLand,
                  );
                }
              });
            }

            final shown = math.min(t, _showSeconds);
            final x = _streak.x(shown);
            final v = _streak.dx(shown).abs();
            final stretch = 1 + math.min(1.5, v * 0.0017);
            final hideT = ((t - _hideStart) / _hideSeconds).clamp(0.0, 1.0);
            final scale =
                stretch * _hide.x(hideT * _hideSeconds).clamp(0.0, 1.0);

            return Stack(
              children: [
                if (t < _showSeconds)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _KuronToastStreakPainter(
                          progress: t / _showSeconds,
                          anchor: anchor,
                          monochrome: monochrome,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16 + x,
                  bottom: safeBottom + 16,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0.0, media.size.width - 32),
                      ),
                      child: Material(
                        key: toastKey,
                        color: monochrome
                            ? const Color(0xFF111111)
                            : theme.colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: monochrome
                                  ? Colors.white
                                  : theme.colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    _entry = entry;
    overlay.insert(entry);
    controller.forward(from: 0);
    _timer = Timer(totalDuration, dismiss);
  }

  /// Tear down the one toast (entry, timer, controller) without touching the
  /// caller's state or the shared [KuronFx] controller.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    final controller = _controller;
    _controller = null;
    controller
      ?..stop()
      ..dispose();
  }
}

/// Streak-in tail line and the ground puffs/shards/ticks that accompany the
/// landing BYAR! burst. All paints are hoisted; loops are bounded and allocate
/// nothing per frame beyond the geometry values passed to [Canvas].
class _KuronToastStreakPainter extends CustomPainter {
  const _KuronToastStreakPainter({
    required this.progress,
    required this.anchor,
    required this.monochrome,
  });

  final double progress;
  final Rect anchor;
  final bool monochrome;

  static const Color _coral = Color(0xFFF1958E);
  static const Color _gold = Color(0xFFC8A06A);
  static final Paint _tail = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _puff = Paint()..style = PaintingStyle.fill;
  static final Paint _shard = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _tick = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = monochrome ? Colors.white : _coral;
    final ground = monochrome ? Colors.white : _gold;
    if (progress < 1) {
      // One speed line at the tail, thinning out (never fading) as it lands.
      _tail.color = accent;
      _tail.strokeWidth = 3 * (1 - progress);
      final tail = anchor.center - Offset(anchor.width * 2.2, 0);
      canvas.drawLine(
        tail - Offset(40 * (1 - progress), 0),
        tail + Offset(20 * progress, 0),
        _tail,
      );
      return;
    }
    // Land: 3 ground puffs, 4 shards and 2 ticks under the anchor.
    _puff.color = accent;
    for (var i = 0; i < 3; i++) {
      final p =
          anchor.center +
          Offset((i - 1) * anchor.width * 0.8, anchor.height * 1.6);
      canvas.drawCircle(p, anchor.width * (0.22 - i * 0.04), _puff);
    }
    _shard.color = ground;
    _shard.strokeWidth = 2;
    for (var i = 0; i < 4; i++) {
      final p =
          anchor.center + Offset((i - 1.5) * anchor.width, anchor.height * 1.4);
      canvas.drawLine(p, p + Offset((i - 1.5) * 4, -anchor.height), _shard);
    }
    _tick.color = accent;
    _tick.strokeWidth = 2.5;
    for (var i = 0; i < 2; i++) {
      final p =
          anchor.center +
          Offset((i == 0 ? -1 : 1) * anchor.width * 1.8, anchor.height);
      canvas.drawLine(p, p + Offset(0, -anchor.height * 0.9), _tick);
    }
  }

  @override
  bool shouldRepaint(_KuronToastStreakPainter old) =>
      old.progress != progress || old.anchor != anchor;
}
