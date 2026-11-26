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
  void show({
    required OverlayState overlay,
    required KuronFxMode mode,
    required KuronFxKind kind,
    KuronSticker? sticker,
  }) {
    if (mode == KuronFxMode.quiet) return;
    _clear();

    _kind = kind;
    _sticker = mode == KuronFxMode.satire ? sticker : null;
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
    _particleCount = 0;
  }

  void dispose() {
    _clear();
    _controller.dispose();
  }
}

/// Procedural sakuga burst: impact ring, speed lines, sparkles and transient
/// manga SFX lettering in Kuron's warm editorial palette.
class KuronFxOverlayPainter extends CustomPainter {
  const KuronFxOverlayPainter({
    required this.progress,
    required this.kind,
    required this.particleCount,
    required this.sticker,
    required this.monochrome,
    required this.dpr,
  });

  final double progress;
  final KuronFxKind kind;
  final int particleCount;
  final KuronSticker? sticker;
  final bool monochrome;
  final double dpr;

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
    canvas.save();
    final center = Offset(size.width / 2, size.height / 2);

    // Impact ring.
    final ring = Paint()
      ..color = _accent.withValues(alpha: 0.85 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + 5 * (1 - t);
    canvas.drawCircle(center, 18 + 120 * springValue, ring);

    // Speed lines: bounded loop, hard cap enforced here as well.
    final lines = math.min(12, maxParticles);
    for (var i = 0; i < lines; i++) {
      final angle = (i / lines) * math.pi * 2;
      final inner = 40 + 70 * springValue;
      final outer = inner + 26 + 18 * springValue;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        Paint()
          ..color = _accentGold.withValues(alpha: 0.55 * alpha)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Particles: deterministic directions, hard-capped count.
    final count = particleCount.clamp(0, maxParticles);
    for (var i = 0; i < count; i++) {
      final angle = (i * 137.5) * math.pi / 180;
      final radius = (28 + 96 * springValue) * (0.55 + (i % 5) * 0.11);
      final offset = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      final color = i % 3 == 0
          ? _accentDeep
          : i % 3 == 1
          ? _accentGold
          : _accent;
      canvas.drawCircle(
        center + offset,
        (2.5 + (i % 4) * 1.2) * (1 - 0.4 * t),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }

    // Transient manga SFX lettering.
    final sfx = switch (kind) {
      KuronFxKind.favorite => 'ドン!',
      KuronFxKind.rating => 'カチッ!',
      KuronFxKind.downloadComplete => 'ズザッ!',
      KuronFxKind.sheetConfirm => 'ポン!',
    };
    if (sticker != null) _drawSfx(canvas, center, sticker!.sfx, alpha, 22);
    _drawSfx(canvas, center - const Offset(0, 92), sfx, alpha * 0.9, 18);
    canvas.restore();
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
      old.dpr != dpr;
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

  static void trigger(
    BuildContext context, {
    required KuronFxKind kind,
    KuronSticker? sticker,
    bool isReader = false,
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
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    controller.show(
      overlay: overlay,
      mode: mode,
      kind: kind,
      sticker: sticker ?? _defaultStickerFor(kind),
    );
  }

  static KuronSticker? _defaultStickerFor(KuronFxKind kind) => switch (kind) {
    KuronFxKind.favorite => KuronSticker.acc,
    KuronFxKind.rating => KuronSticker.sah,
    KuronFxKind.downloadComplete => KuronSticker.cair,
    KuronFxKind.sheetConfirm => KuronSticker.resmi,
  };
}
