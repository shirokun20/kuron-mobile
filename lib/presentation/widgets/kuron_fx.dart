import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

/// The only moments allowed to fire a `kuron_fx` burst. Scroll, page turn,
/// tabs, sliders, inputs and tooltips are deliberately absent.
enum KuronFxKind { favorite, rating, downloadComplete, sheetConfirm }

/// Transparent die-cut satire stickers shipped as pre-sized WebP assets.
/// Each sticker is decorative and carries its own local SFX word.
enum KuronSticker {
  cair('01_cair.webp', 'CAIR!'),
  wibuDetect('02_wibu_detect.webp', 'WIBU DETECTED!'),
  acc('03_acc.webp', 'ACC!'),
  sah('04_sah.webp', 'SAH!'),
  gaspol('05_gaspol.webp', 'GASPOL!'),
  resmi('06_resmi.webp', 'RESMI!');

  const KuronSticker(this.asset, this.sfx);

  final String asset;
  final String sfx;

  String get path => 'assets/stickers/$asset';
}

/// Single shared overlay host for all sakuga bursts.
///
/// Constraints (hard-coded, not configurable): one overlay at a time, at most
/// 40 particles per burst, and a TTL of at most 800 ms. All resources are
/// released in [dispose].
class KuronFxController {
  KuronFxController({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 720),
      );

  final AnimationController _controller;
  OverlayEntry? _entry;
  Timer? _ttl;
  KuronSticker? _sticker;
  Rect? _targetRect;
  KuronFxKind _kind = KuronFxKind.favorite;
  int _particleCount = 0;
  int _burstCount = 0;

  static const int maxParticles = 40;
  static const Duration maxDuration = Duration(milliseconds: 800);
  static const double stickerLogicalSize = 72;

  bool get isActive => _entry != null;
  int get particleCount => _particleCount;
  int get burstCount => _burstCount;

  /// At most one overlay is ever mounted (testable invariant).
  int get activeEntryCount => _entry == null ? 0 : 1;

  /// At most one TTL timer is ever pending (testable invariant).
  int get activeTimerCount => _ttl == null ? 0 : 1;

  /// Overshoot ~9% (damping ratio ~0.6), no linear easing.
  static final SpringSimulation spring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 90, damping: 11.5),
    0,
    1,
    0,
  );

  /// Replaces any in-flight burst: rapid taps coalesce instead of stacking.
  ///
  /// When [targetRect] is given, the burst is drawn anchored on that button
  /// bounding box (in overlay coordinates) instead of the screen center.
  void show({
    required OverlayState overlay,
    required KuronFxMode mode,
    required KuronFxKind kind,
    KuronSticker? sticker,
    Rect? targetRect,
  }) {
    if (mode == KuronFxMode.quiet) {
      // Switching to quiet mid-burst must also tear down an in-flight effect.
      _clear();
      return;
    }
    _clear();

    _kind = kind;
    _sticker = mode == KuronFxMode.satire ? sticker : null;
    _targetRect = targetRect;
    _particleCount = mode == KuronFxMode.standard
        ? 14
        : 18; // always <= maxParticles
    assert(_particleCount <= maxParticles);
    _burstCount++;

    final entry = OverlayEntry(
      opaque: false,
      builder: (context) => RepaintBoundary(
        child: IgnorePointer(
          child: SizedBox.expand(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: KuronFxOverlayPainter(
                  progress: _controller.value,
                  kind: _kind,
                  particleCount: _particleCount,
                  sticker: _sticker,
                  monochrome: false,
                  dpr: MediaQuery.devicePixelRatioOf(context),
                  targetRect: _targetRect,
                ),
                child: _sticker == null
                    ? null
                    : ExcludeSemantics(
                        child: Center(
                          child: Image(
                            image: ResizeImage(
                              AssetImage(_sticker!.path),
                              width:
                                  (stickerLogicalSize *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round(),
                              height:
                                  (stickerLogicalSize *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round(),
                            ),
                            width: stickerLogicalSize,
                            height: stickerLogicalSize,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _controller
      ..reset()
      ..forward(from: 0);
    _ttl = Timer(maxDuration, _clear);
  }

  void _clear() {
    _ttl?.cancel();
    _ttl = null;
    if (_controller.isAnimating) _controller.stop();
    _controller.reset();
    _entry?.remove();
    _entry = null;
    _sticker = null;
    _targetRect = null;
    _particleCount = 0;
  }

  void dispose() {
    _clear();
    _controller.dispose();
  }
}

/// Procedural sakuga burst anchored on the triggering button: an impact ring
/// expanding from the button perimeter, diagonal slash cuts across it, and
/// diamond sparkles bursting out of its edges — all sized proportionally to
/// the button, plus transient manga SFX lettering in Kuron's warm palette.
/// A null [targetRect] keeps the legacy screen-center fallback (used by tests
/// and by callers whose render box is unavailable).
class KuronFxOverlayPainter extends CustomPainter {
  const KuronFxOverlayPainter({
    required this.progress,
    required this.kind,
    required this.particleCount,
    required this.sticker,
    required this.monochrome,
    required this.dpr,
    this.targetRect,
  });

  final double progress;
  final KuronFxKind kind;
  final int particleCount;
  final KuronSticker? sticker;
  final bool monochrome;
  final double dpr;

  /// Button bounding box in overlay coordinates. Null = screen center.
  final Rect? targetRect;

  static const _coral = Color(0xFFF1958E);
  static const _deep = Color(0xFFC76A62);
  static const _gold = Color(0xFFC8A06A);
  static const _paper = Color(0xFFEFE6DC);

  static const int maxParticles = KuronFxController.maxParticles;

  Color get _accent => monochrome ? _paper : _coral;
  Color get _accentDeep => monochrome ? _paper : _deep;
  Color get _accentGold => monochrome ? _paper : _gold;

  @override
  void paint(Canvas canvas, Size size) {
    // The spring may overshoot slightly; keep it inside a bounded range.
    final t = progress.clamp(0.0, 1.0);
    // Spring position from a real SpringSimulation (overshoot, then settle).
    final springValue = (KuronFxController.spring.x(
      (t * 0.72).clamp(0.0, 0.72),
    )).clamp(0.0, 1.15);
    final alpha = (1 - t * t).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    // Anchor on the triggering button; fall back to the screen center when
    // no target was captured (tests, missing render box).
    final Rect? target = targetRect;
    final Offset center =
        target?.center ?? Offset(size.width / 2, size.height / 2);
    // Effect scale follows the button: half the shortest side, clamped so a
    // 48dp icon button bursts ~24dp while a wide download bar stays bounded.
    final double base = target == null
        ? 60.0
        : math.min(96.0, math.max(16.0, target.shortestSide / 2));
    // Hoisted paints: nothing is allocated inside the loops below.
    final double strokeScale = base / 60;
    final ring = Paint()
      ..color = _accent.withValues(alpha: 0.85 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScale * (3 + 5 * (1 - t))
      ..strokeCap = StrokeCap.round;
    final slash = Paint()
      ..color = _accentGold.withValues(alpha: 0.75 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScale * 3
      ..strokeCap = StrokeCap.round;
    final sparkA = Paint()
      ..color = _accent.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScale * 2
      ..strokeCap = StrokeCap.round;
    final sparkB = Paint()
      ..color = _accentDeep.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScale * 2
      ..strokeCap = StrokeCap.round;
    final sparkC = Paint()
      ..color = _accentGold.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeScale * 2
      ..strokeCap = StrokeCap.round;

    // 1. Impact ring: thin shockwave expanding from the button perimeter,
    // fading out fast.
    canvas.drawCircle(center, base * 0.7 + base * 2.0 * springValue, ring);

    // 2. Slash cuts: three parallel diagonal light slashes across the
    // button (classic bottom-left -> top-right sakuga angle).
    final slashDir = Offset(math.cos(-math.pi / 4), math.sin(-math.pi / 4));
    final slashNormal = Offset(-slashDir.dy, slashDir.dx);
    final slashLen = base * (1.6 + 1.2 * springValue);
    for (var i = -1; i <= 1; i++) {
      final c = center + slashNormal * (i * base * 0.45);
      canvas.drawLine(c - slashDir * slashLen, c + slashDir * slashLen, slash);
    }

    // 3. Spark burst: diamond sparkles (crossed ticks) and embers flying
    // out of the button edges. Deterministic, hard-capped count.
    final count = particleCount.clamp(0, maxParticles);
    for (var i = 0; i < count; i++) {
      final angle = (i * 137.5) * math.pi / 180;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final radius = base * (1.0 + 2.0 * springValue) * (0.55 + (i % 5) * 0.11);
      final p = center + dir * radius;
      final arm = base * 0.22 * (1 - 0.4 * t) * (0.6 + (i % 3) * 0.2);
      final paint = i % 3 == 0
          ? sparkB
          : i % 3 == 1
          ? sparkC
          : sparkA;
      if (i % 3 == 2) {
        // Diamond sparkle: crossed ticks along the travel direction.
        final perp = Offset(-dir.dy, dir.dx);
        canvas.drawLine(p - dir * arm, p + dir * arm, paint);
        canvas.drawLine(p - perp * arm * 0.6, p + perp * arm * 0.6, paint);
      } else {
        canvas.drawCircle(p, arm * 0.45, paint);
      }
    }

    // Transient manga SFX lettering, sized to the button.
    final sfx = switch (kind) {
      KuronFxKind.favorite => 'ドン!',
      KuronFxKind.rating => 'カチッ!',
      KuronFxKind.downloadComplete => 'ズザッ!',
      KuronFxKind.sheetConfirm => 'ポン!',
    };
    final sfxSize = math.min(22.0, math.max(12.0, strokeScale * 18));
    if (sticker != null) _drawSfx(canvas, center, sticker!.sfx, alpha, 22);
    _drawSfx(canvas, center - Offset(0, base * 1.9), sfx, alpha * 0.9, sfxSize);
  }

  void _drawSfx(
    Canvas canvas,
    Offset center,
    String text,
    double alpha,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _paper.withValues(alpha: alpha),
          fontSize: size,
          fontWeight: FontWeight.w900,
          fontFamily: 'Bangers',
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(KuronFxOverlayPainter old) =>
      old.progress != progress ||
      old.kind != kind ||
      old.particleCount != particleCount ||
      old.sticker != sticker ||
      old.dpr != dpr ||
      old.targetRect != targetRect;
}

/// Host widget: owns the single shared controller and keeps the whole burst
/// tree inside one [RepaintBoundary].
class KuronFxHost extends StatefulWidget {
  const KuronFxHost({super.key, required this.child});

  final Widget child;

  @override
  State<KuronFxHost> createState() => _KuronFxHostState();
}

class _KuronFxHostState extends State<KuronFxHost>
    with TickerProviderStateMixin {
  late final KuronFxController _controller;

  @override
  void initState() {
    super.initState();
    _controller = KuronFxController(vsync: this);
    KuronFx._controller = _controller;
  }

  @override
  void dispose() {
    if (identical(KuronFx._controller, _controller)) {
      KuronFx._controller = null;
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: widget.child);
}

/// Public trigger facade. Calling this in `quiet` mode, reduced motion, note
/// themes or the reader is a no-op: the underlying state change still happens
/// at the call site, only the decoration is suppressed.
abstract final class KuronFx {
  static KuronFxController? _controller;

  /// Exposed for tests and diagnostics.
  static KuronFxController? get activeController => _controller;

  /// Fires an anchored sakuga burst on the given [context]'s render box:
  /// the effect is drawn around that button's bounding box, sized to it.
  ///
  /// Pass an explicit [targetRect] (in overlay coordinates) when the firing
  /// context is not the button itself — e.g. capture it with [targetRectOf]
  /// before an `await` gap and hand it over afterwards.
  static void trigger(
    BuildContext context, {
    required KuronFxKind kind,
    KuronSticker? sticker,
    bool isReader = false,
    Rect? targetRect,
  }) {
    // Triggered from callbacks: read once, never register a rebuild dependency.
    final mode = KuronMotionPolicy.effectiveMode(
      context,
      isReader: isReader,
      listen: false,
    );
    if (mode == KuronFxMode.quiet) return;
    final controller = _controller;
    if (controller == null) return;
    // Always target the root overlay: a trigger fired from a bottom sheet or
    // dialog must render above that route, not into a short-lived nested one.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    controller.show(
      overlay: overlay,
      mode: mode,
      kind: kind,
      sticker: sticker ?? _defaultStickerFor(kind),
      targetRect: targetRect ?? targetRectOf(context),
    );
  }

  /// Button bounding box of [context] in global (overlay) coordinates.
  /// Returns null when there is no attached render box — callers then fall
  /// back to the legacy screen-center burst. Never throws.
  static Rect? targetRectOf(BuildContext context) {
    try {
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) return null;
      if (!renderObject.attached || !renderObject.hasSize) return null;
      if (renderObject.size.isEmpty) return null;
      final offset = renderObject.localToGlobal(Offset.zero);
      if (!offset.dx.isFinite || !offset.dy.isFinite) return null;
      return offset & renderObject.size;
    } catch (_) {
      return null;
    }
  }

  /// Button bursts (favorite, download complete) never show the giant satire
  /// sticker — the anchored slash/sparks/ring carry the feedback on their own.
  /// Stickers stay available in `assets/stickers` for mascot/gamification
  /// surfaces, which pass an explicit [KuronSticker].
  static KuronSticker? _defaultStickerFor(KuronFxKind kind) => switch (kind) {
    KuronFxKind.favorite => null,
    KuronFxKind.rating => KuronSticker.sah,
    KuronFxKind.downloadComplete => null,
    KuronFxKind.sheetConfirm => KuronSticker.resmi,
  };
}
