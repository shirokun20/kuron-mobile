import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_sfx_words.dart';

/// The only moments allowed to fire a `kuron_fx` burst.
///
/// Allow-list: the four original beats (`favorite`, `rating`,
/// `downloadComplete`, `sheetConfirm`) plus the P2 anchored control beats
/// `toggleOn`, `toggleOff`, `sliderFling`, `tabSwitch`, `toastLand`,
/// `tooltipPop` and `progressComplete`. Scroll, page turns, inputs and idle
/// states stay deliberately absent.
enum KuronFxKind {
  favorite,
  rating,
  downloadComplete,
  sheetConfirm,
  toggleOn,
  toggleOff,
  sliderDrag,
  sliderFling,
  tabSwitch,
  toastLand,
  tooltipPop,
  progressComplete,
}

/// Single shared overlay host for all sakuga bursts.
///
/// Constraints (hard-coded, not configurable): one overlay at a time, at most
/// 40 particles per burst, and a TTL of at most 800 ms. All resources are
/// released in [dispose].
class KuronFxController {
  KuronFxController({required TickerProvider vsync})
    : _vsync = vsync,
      _controller = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 720),
      );

  final TickerProvider _vsync;
  final AnimationController _controller;
  OverlayEntry? _entry;
  Timer? _ttl;
  Rect? _targetRect;
  KuronFxKind _kind = KuronFxKind.favorite;
  int _particleCount = 0;
  int _burstCount = 0;
  bool _monochrome = false;
  double _direction = 1.0;
  KuronSfxSpec? _wordSpec;
  ui.Image? _wordImage;
  final KuronSfxBakeCache _words = KuronSfxBakeCache();

  static const int maxParticles = 40;
  static const Duration maxDuration = Duration(milliseconds: 800);

  /// Katalog toggle §2: ON plays frames 0→42 at 30 fps (1.433 s), OFF plays
  /// frames 11→0 backward (0.4 s). Every other beat keeps the shared 720 ms
  /// animation / 800 ms TTL.
  static Duration animationDurationFor(KuronFxKind kind) => switch (kind) {
    KuronFxKind.toggleOn => const Duration(milliseconds: 1433),
    KuronFxKind.toggleOff => const Duration(milliseconds: 400),
    KuronFxKind.sliderDrag => const Duration(milliseconds: 360),
    _ => const Duration(milliseconds: 720),
  };

  /// Live animation duration (exposed for diagnostics/tests).
  Duration? get duration => _controller.duration;

  /// Shared ticker host, reused by the custom Kuron toast so it needs no
  /// second [TickerProviderStateMixin] or extra host widget.
  TickerProvider get vsync => _vsync;

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
    Rect? targetRect,
    bool monochrome = false,
    bool dark = false,
    double direction = 1.0,
  }) {
    if (mode == KuronFxMode.quiet) {
      // Switching to quiet mid-burst must also tear down an in-flight effect.
      _clear();
      return;
    }
    _clear();

    _kind = kind;
    _targetRect = targetRect;
    _monochrome = monochrome;
    _direction = direction >= 0 ? 1.0 : -1.0;
    _wordSpec = _specForKind(kind);
    _wordImage = null;
    _particleCount = mode == KuronFxMode.standard
        ? 14
        : 18; // always <= maxParticles
    assert(_particleCount <= maxParticles);
    _burstCount++;
    _bakeWord(dark: dark);

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
                  monochrome: _monochrome,
                  dpr: MediaQuery.devicePixelRatioOf(context),
                  targetRect: _targetRect,
                  wordSpec: _wordSpec,
                  wordImage: _wordImage,
                  direction: _direction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _controller.duration = animationDurationFor(kind);
    _controller
      ..reset()
      ..forward(from: 0);
    // Toggle beats own their katalog pacing; other beats keep the 800 ms cap.
    _ttl = Timer(switch (kind) {
      KuronFxKind.toggleOn => const Duration(milliseconds: 1450),
      KuronFxKind.toggleOff => const Duration(milliseconds: 430),
      KuronFxKind.sliderDrag => const Duration(milliseconds: 380),
      _ => maxDuration,
    }, _clear);
  }

  void _clear() {
    _ttl?.cancel();
    _ttl = null;
    if (_controller.isAnimating) _controller.stop();
    _controller.reset();
    _entry?.remove();
    _entry = null;
    _targetRect = null;
    _wordSpec = null;
    _wordImage = null;
    _particleCount = 0;
  }

  /// Canonical Indonesian word per kind (LOCKED). Every current kind carries
  /// a word; kinds added later without an entry stay wordless.
  static KuronSfxSpec? _specForKind(KuronFxKind kind) => switch (kind) {
    // Button confirm + progress 100%: JEDER! solid.
    KuronFxKind.favorite => KuronSfxSpec(
      word: KuronSfxWord.byName('JEDER!')!,
      sizeFactor: 1.75,
      rot: -0.12,
      life: 1.05,
    ),
    KuronFxKind.downloadComplete => KuronSfxSpec(
      word: KuronSfxWord.byName('JEDER!')!,
      sizeFactor: 1.75,
      rot: -0.12,
      life: 1.05,
    ),
    // Radio/rating: SAH! hollow.
    KuronFxKind.rating => KuronSfxSpec(
      word: KuronSfxWord.byName('SAH!')!,
      sizeFactor: 1.5,
      rot: 0.08,
      life: 0.85,
    ),
    // Sheet confirm: KLIK! hollow (lock/confirm beat).
    KuronFxKind.sheetConfirm => KuronSfxSpec(
      word: KuronSfxWord.byName('KLIK!')!,
      sizeFactor: 1.5,
      rot: -0.08,
      life: 0.8,
    ),
    // P2 anchored beats. Staging follows the katalog §2 numbers mapped to
    // control-relative factors (gallery sizes are absolute px on small
    // controls); every word still bakes/evicts through the same cache.
    //
    // Progress/download leading edge: JEDER! solid, ~control x 1.2 / 1.05 s.
    KuronFxKind.progressComplete => KuronSfxSpec(
      word: KuronSfxWord.byName('JEDER!')!,
      sizeFactor: 1.2,
      rot: -0.12,
      life: 1.05,
    ),
    // Toast landing: BYAR! dotted (LOCKED handoff; SAH!-vs-BYAR! flagged).
    KuronFxKind.toastLand => KuronSfxSpec(
      word: KuronSfxWord.byName('BYAR!')!,
      sizeFactor: 1.2,
      rot: -0.1,
      life: 1.0,
    ),
    // Tooltip icon: KLIK! hollow + procedural ring (drawn by the painter).
    KuronFxKind.tooltipPop => KuronSfxSpec(
      word: KuronSfxWord.byName('KLIK!')!,
      sizeFactor: 1.8,
      rot: -0.08,
      life: 0.8,
    ),
    // Slider fast release: CAIR! accent solid above the thumb only.
    KuronFxKind.sliderFling => KuronSfxSpec(
      word: KuronSfxWord.byName('CAIR!')!,
      sizeFactor: 1.2,
      rot: -0.06,
      life: 0.75,
      accent: true,
    ),
    // Wordless beats: motion comes from the control's own layout / painter.
    KuronFxKind.sliderDrag => null,
    KuronFxKind.tabSwitch => null,
    KuronFxKind.toggleOn => null,
    KuronFxKind.toggleOff => null,
  };

  /// Bakes the kind's word off the frame loop; when the raster lands, the
  /// in-flight burst picks it up on its next frame. Stale completions
  /// (a newer burst replaced this one) are dropped — the cache owns them.
  void _bakeWord({required bool dark}) {
    final spec = _wordSpec;
    if (spec == null) return;
    final token = _burstCount;
    final palette = KuronSfxPalette.resolve(
      spec.word.style,
      dark: dark,
      monochrome: _monochrome,
      accent: spec.accent,
    );
    _words
        .bake(word: spec.word.name, style: spec.word.style, palette: palette)
        .then((img) {
          if (img == null) return;
          if (token == _burstCount && _entry != null) {
            _wordImage = img;
            _entry?.markNeedsBuild();
          }
        });
  }

  void dispose() {
    _clear();
    _words.dispose();
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
    required this.monochrome,
    required this.dpr,
    this.targetRect,
    this.wordSpec,
    this.wordImage,
    this.direction = 1.0,
  });

  final double progress;
  final KuronFxKind kind;
  final int particleCount;
  final bool monochrome;
  final double dpr;

  /// Button bounding box in overlay coordinates. Null = screen center.
  final Rect? targetRect;

  /// Baked SFX word (P3): raster produced off the frame loop. Null until
  /// the bake lands or when the kind carries no word.
  final KuronSfxSpec? wordSpec;
  final ui.Image? wordImage;
  final double direction;

  static const _coral = Color(0xFFF1958E);
  static const _deep = Color(0xFFC76A62);
  static const _gold = Color(0xFFC8A06A);
  static const _paper = Color(0xFFEFE6DC);

  static const int maxParticles = KuronFxController.maxParticles;

  /// Hoisted: the word paint never changes per frame.
  static final Paint _wordPaint = Paint();

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

    // Wordless control beats (P2): a lighter procedural silhouette that
    // reuses the paints above — no word raster, no per-frame
    // image work. Toggle = knob stretch + splash + flood wash; tab = ticks
    // and puffs only (velocity stretch comes from the tab layout itself).
    if (kind == KuronFxKind.toggleOn || kind == KuronFxKind.toggleOff) {
      _paintToggle(
        canvas,
        center,
        base,
        t,
        springValue,
        ring,
        sparkA,
        sparkB,
        sparkC,
      );
      return;
    }
    if (kind == KuronFxKind.tabSwitch) {
      _paintTabTicks(
        canvas,
        center,
        base,
        t,
        springValue,
        ring,
        sparkA,
        sparkB,
      );
      return;
    }
    if (kind == KuronFxKind.sliderDrag) {
      _paintSliderDrag(canvas, center, base, t, alpha);
      return;
    }
    if (kind == KuronFxKind.sliderFling) {
      _paintSliderFling(canvas, center, base, t, springValue, alpha);
    } else {
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
        canvas.drawLine(
          c - slashDir * slashLen,
          c + slashDir * slashLen,
          slash,
        );
      }

      // 3. Spark burst: diamond sparkles (crossed ticks) and embers flying
      // out of the button edges. Deterministic, hard-capped count.
      final count = particleCount.clamp(0, maxParticles);
      for (var i = 0; i < count; i++) {
        final angle = (i * 137.5) * math.pi / 180;
        final dir = Offset(math.cos(angle), math.sin(angle));
        final radius =
            base * (1.0 + 2.0 * springValue) * (0.55 + (i % 5) * 0.11);
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
    }

    // Baked Indonesian SFX word (P3): one drawImage per frame, driven by the
    // gallery spring (0.2, 520, 17) with jitter/roll; shrinks (never fades)
    // over the last 14% of its life. ~1.5–2× the control width, floating
    // above the button. Null until the bake lands — no TextPainter.layout()
    // in the frame loop anymore.
    final spec = wordSpec;
    final baked = wordImage;
    if (spec != null && baked != null && spec.life > 0) {
      // The overlay is hard-capped at 720 ms, while a word's gallery life can
      // be longer: use `life` as the spring's time base and `t` for the
      // end-of-life shrink so every word actually reaches its last 14%.
      final age = t * spec.life;
      final k = t;
      if (k <= 1) {
        var wordScale = KuronSfxMotion.spring.x(age);
        if (k > KuronSfxMotion.fadeStart) {
          final f =
              (k - KuronSfxMotion.fadeStart) / (1 - KuronSfxMotion.fadeStart);
          wordScale *= 1 - f * f * f;
        }
        if (wordScale > 0.01) {
          final controlW = target?.width ?? base * 2;
          final dstW = controlW * spec.sizeFactor;
          final dstH = dstW * baked.height / baked.width;
          canvas.save();
          canvas.translate(
            center.dx + math.sin(age * 31) * KuronSfxMotion.jitter,
            center.dy - base * 1.9 + math.cos(age * 27) * KuronSfxMotion.jitter,
          );
          canvas.rotate(spec.rot + math.sin(age * 6) * KuronSfxMotion.roll);
          canvas.drawImageRect(
            baked,
            Rect.fromLTWH(
              0,
              0,
              baked.width.toDouble(),
              baked.height.toDouble(),
            ),
            Rect.fromCenter(
              center: Offset.zero,
              width: dstW * wordScale,
              height: dstH * wordScale,
            ),
            _wordPaint,
          );
          canvas.restore();
        }
      }
    }
  }

  /// Gallery toggle.js: `N = 43, FPS = 30, COLS = 8`; ON = `[0..42]`,
  /// OFF = `[11,10,…,0]` (12 frames played backward). No words, no sheet.
  static const double _toggleFps = 30;
  static const int toggleOnFrames = 43;
  static const int toggleOffFrames = 12;

  /// The discrete sprite-sheet frame the gallery would draw at [progress].
  /// ON advances 0→42; OFF replays only the first 12 frames in reverse, so
  /// the splash/flood/glint (later frames) never appear on OFF.
  static int toggleFrameFor(KuronFxKind kind, double progress) {
    final reversed = kind == KuronFxKind.toggleOff;
    final raw = reversed
        ? (1 - progress) * ((toggleOffFrames - 1) / toggleOnFrames)
        : progress;
    return (raw * toggleOnFrames).floor().clamp(0, toggleOnFrames - 1);
  }

  /// Knob spring, katalog slider §3 (420/30) — the only spring number the
  /// catalog gives for a control thumb. The gallery toggle itself is a frame
  /// sheet; this spring maps those frames onto a procedural knob smear/slam.
  static final SpringSimulation _knobSpring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 420, damping: 30),
    0,
    1,
    0,
  );

  /// Splash crown defaults, katalog effect #10: w34 / h26 / life 0.7 s,
  /// 7 tongues + 7 teardrop drops under gravity 520 (no random numbers).
  static const double _splashW = 34;
  static const double _splashH = 26;
  static const double _splashLife = 0.7;
  static const double _dropGravity = 520;

  /// Procedural redraw of the gallery's 43 drawn frames with Kuron painter
  /// primitives: frames 0–11 knob smear with a torn tail, slam, frames 12–42
  /// splash crown + flood/slosh wash + glint + settle. OFF replays only frames
  /// 11→0 backward (gallery `OFF = [11..0]`), so it has no crown/flood/glint.
  /// Wordless — the state change is the message; reduced motion never reaches
  /// this painter because the shared gate jumps to the end state instead.
  void _paintToggle(
    Canvas canvas,
    Offset center,
    double base,
    double t,
    double springValue,
    Paint ring,
    Paint sparkA,
    Paint sparkB,
    Paint sparkC,
  ) {
    // Gallery frame stepping: ON 0→42, OFF 11→0 (reverse, early frames only).
    final frame = toggleFrameFor(kind, t);
    final local = frame / toggleOnFrames;
    final seconds = local * (toggleOnFrames / _toggleFps); // 30 fps time base
    final knob = _knobSpring.x(seconds).clamp(0.0, 1.15);
    final isOff = kind == KuronFxKind.toggleOff;

    // Track-sized smear/dash anchored directly on the Switch bounds.
    final smearProgress = (local / 0.32).clamp(0.0, 1.0);
    final smearFade = isOff
        ? (1.0 - t)
        : (1.0 - ((local - 0.25) / 0.25).clamp(0.0, 1.0));
    if (smearFade > 0.02) {
      final dir = isOff ? -1.0 : 1.0;
      final smearPaint = Paint()
        ..color = _accent.withValues(alpha: 0.42 * smearFade)
        ..style = PaintingStyle.fill;
      final smearW = base * (1.1 + 0.9 * smearProgress);
      final smearH = base * 0.52 * (1.0 - 0.3 * smearProgress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(dir * base * 0.22 * (knob - 0.5), 0),
            width: smearW,
            height: smearH,
          ),
          Radius.circular(smearH / 2),
        ),
        smearPaint,
      );

      // Trailing speed lines behind the knob.
      final linePaint = Paint()
        ..color = _accentGold.withValues(alpha: 0.65 * smearFade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, base * 0.08)
        ..strokeCap = StrokeCap.round;
      for (var i = -1; i <= 1; i++) {
        final yOff = i * base * 0.26;
        final xStart = center.dx - dir * base * (0.2 + 0.35 * smearProgress);
        final xEnd = xStart - dir * base * (0.55 - 0.15 * i.abs());
        canvas.drawLine(
          Offset(xStart, center.dy + yOff),
          Offset(xEnd, center.dy + yOff),
          linePaint,
        );
      }
    }

    if (isOff) return;

    // Splash crown at the slam point (right side of the switch):
    // 7 filled curved tongues + 7 falling teardrop droplets.
    final crownT = ((local - 0.28) / _splashLife).clamp(0.0, 1.0);
    if (crownT > 0 && crownT < 1) {
      final scale = base / _splashW;
      final crown = center + Offset(base * 0.55, -base * 0.52);
      final rise = math.sin(crownT * math.pi);
      final crownAlpha = (1.0 - crownT * crownT).clamp(0.0, 1.0);

      final crownFill = Paint()
        ..color = _accent.withValues(alpha: 0.85 * crownAlpha)
        ..style = PaintingStyle.fill;
      final crownPath = Path();
      final crownW = _splashW * scale * 1.15;
      crownPath.moveTo(crown.dx - crownW * 0.55, crown.dy);
      for (var i = 0; i < 7; i++) {
        final u = i / 6 - 0.5;
        final h = _splashH * (1.0 - u.abs() * 0.65) * scale * rise * 1.1;
        final bx = crown.dx + u * crownW;
        final half = crownW / 12;
        final tx = bx + u * h * 0.55;
        crownPath.quadraticBezierTo(
          bx - half,
          crown.dy - h * 0.35,
          tx,
          crown.dy - h,
        );
        crownPath.quadraticBezierTo(
          bx + half,
          crown.dy - h * 0.35,
          bx + half,
          crown.dy,
        );
      }
      crownPath.close();
      canvas.drawPath(crownPath, crownFill);

      final dropFill = Paint()
        ..color = _accentGold.withValues(alpha: 0.9 * crownAlpha)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 7; i++) {
        final a = -math.pi / 2 + ((i - 3) / 3) * 1.05;
        final v = (95 + (i % 3) * 50) * scale;
        final tt = crownT * _splashLife;
        final px = crown.dx + math.cos(a) * v * tt;
        final py =
            crown.dy -
            4 * scale +
            math.sin(a) * v * tt +
            _dropGravity * scale * tt * tt;
        final r = base * 0.085 * (1 - crownT);
        if (r > 0.3) {
          canvas.drawCircle(Offset(px, py), r, i.isEven ? crownFill : dropFill);
        }
      }
    }

    // Late glint (katalog kira), crisp 4-point star at top-right of the switch.
    if (local > 0.72) {
      final g = ((local - 0.72) / 0.28).clamp(0.0, 1.0);
      final s = base * 0.42 * math.sin(g * math.pi);
      if (s > 0.5) {
        final gc = center + Offset(base * 0.85, -base * 0.58);
        final glintPaint = Paint()
          ..color = _accentGold.withValues(alpha: math.sin(g * math.pi))
          ..style = PaintingStyle.fill;
        final star = Path()
          ..moveTo(gc.dx, gc.dy - s)
          ..quadraticBezierTo(
            gc.dx + s * 0.16,
            gc.dy - s * 0.16,
            gc.dx + s,
            gc.dy,
          )
          ..quadraticBezierTo(
            gc.dx + s * 0.16,
            gc.dy + s * 0.16,
            gc.dx,
            gc.dy + s,
          )
          ..quadraticBezierTo(
            gc.dx - s * 0.16,
            gc.dy + s * 0.16,
            gc.dx - s,
            gc.dy,
          )
          ..quadraticBezierTo(
            gc.dx - s * 0.16,
            gc.dy - s * 0.16,
            gc.dx,
            gc.dy - s,
          )
          ..close();
        canvas.drawPath(star, glintPaint);
      }
    }
  }

  /// Slider mid-drag trail (katalog slider §3): cumulus puffs + horizontal
  /// speed lines rolling behind the thumb in `-direction`.
  void _paintSliderDrag(
    Canvas canvas,
    Offset center,
    double base,
    double t,
    double alpha,
  ) {
    final dir = direction >= 0 ? 1.0 : -1.0;
    final grow = (t / 0.25).clamp(0.0, 1.0);
    final die = (1.0 - ((t - 0.45) / 0.55).clamp(0.0, 1.0));
    final s = grow * die;
    if (s <= 0.02) return;

    final puffPaint = Paint()
      ..color = _accent.withValues(alpha: 0.42 * alpha)
      ..style = PaintingStyle.fill;
    final puffCore = Paint()
      ..color = _paper.withValues(alpha: 0.55 * alpha)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final drift = base * (0.65 + i * 0.45 + t * 1.1);
      final px = center.dx - dir * drift;
      final py = center.dy - base * (0.15 + i * 0.22 + t * 0.6);
      final r = base * (0.36 - i * 0.06) * s;
      canvas.drawCircle(Offset(px, py), r, puffPaint);
      canvas.drawCircle(
        Offset(px - dir * r * 0.15, py - r * 0.18),
        r * 0.55,
        puffCore,
      );
    }

    final linePaint = Paint()
      ..color = _accentGold.withValues(alpha: 0.7 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, base * 0.09)
      ..strokeCap = StrokeCap.round;
    for (var i = -1; i <= 1; i++) {
      final yOff = i * base * 0.28;
      final x0 = center.dx - dir * (base * 0.4 + t * base * 1.4);
      final x1 = x0 - dir * base * (0.85 - 0.2 * i.abs()) * (1.0 - 0.5 * t);
      canvas.drawLine(
        Offset(x0, center.dy + yOff),
        Offset(x1, center.dy + yOff),
        linePaint,
      );
    }
  }

  /// Slider fast-release (katalog slider §3): directional crescent slash
  /// flying ahead of the thumb (`+direction`), impact star, and trailing puffs.
  void _paintSliderFling(
    Canvas canvas,
    Offset center,
    double base,
    double t,
    double springValue,
    double alpha,
  ) {
    final dir = direction >= 0 ? 1.0 : -1.0;

    // 1. Directional crescent slash ahead of the thumb.
    final head = (1.0 - math.pow(1.0 - (t / 0.45).clamp(0.0, 1.0), 3))
        .toDouble();
    final tail = math.pow(((t - 0.22) / 0.78).clamp(0.0, 1.0), 3).toDouble();
    if (head - tail > 0.02) {
      final arcR = base * 2.2;
      final arcCenter =
          center + Offset(dir * base * (0.4 + 0.8 * springValue), 0);
      final baseAngle = dir > 0 ? 0.0 : math.pi;
      final startA = baseAngle - 0.75 + 1.5 * tail;
      final sweepA = 1.5 * (head - tail);
      final slashPaint = Paint()
        ..color = _accent.withValues(alpha: 0.85 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = base * 0.36 * (1.0 - 0.4 * tail)
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: arcCenter, radius: arcR),
        startA,
        sweepA,
        false,
        slashPaint,
      );
    }

    // 2. Impact spikes + directional ticks at thumb.
    final tickPaint = Paint()
      ..color = _accentGold.withValues(alpha: 0.9 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, base * 0.12)
      ..strokeCap = StrokeCap.round;
    for (var i = -2; i <= 2; i++) {
      final a = (dir > 0 ? 0.0 : math.pi) + i * 0.45;
      final r0 = base * (0.45 + 0.6 * t);
      final r1 = r0 + base * (0.75 * (1.0 - t * 0.6));
      canvas.drawLine(
        center + Offset(math.cos(a) * r0, math.sin(a) * r0),
        center + Offset(math.cos(a) * r1, math.sin(a) * r1),
        tickPaint,
      );
    }

    // 3. Trailing puffs behind the thumb.
    final puffPaint = Paint()
      ..color = _accentDeep.withValues(alpha: 0.35 * alpha)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 2; i++) {
      final px = center.dx - dir * base * (1.2 + i * 0.8 + t * 0.9);
      final py = center.dy - base * (0.45 + t * 0.7);
      final r = base * (0.42 - i * 0.1) * (1.0 - 0.5 * t);
      if (r > 0.5) canvas.drawCircle(Offset(px, py), r, puffPaint);
    }
  }

  /// Tab landing beat: three ticks above the selected label and side puffs.
  /// No word and no slash cuts — the springy indicator supplies the stretch.
  void _paintTabTicks(
    Canvas canvas,
    Offset center,
    double base,
    double t,
    double springValue,
    Paint ring,
    Paint sparkA,
    Paint sparkB,
  ) {
    canvas.drawCircle(center, base * (0.5 + springValue * 0.7), ring);
    for (var i = -1; i <= 1; i++) {
      final top =
          center +
          Offset(i * base * 0.6, -base * 0.9 - springValue * base * 0.5);
      canvas.drawLine(top, top + Offset(0, -base * 0.4 * (1 - t)), sparkB);
    }
    for (var i = 0; i < 4; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final p =
          center +
          Offset(side * base * (1.0 + springValue), (i - 1.5) * base * 0.35);
      canvas.drawCircle(p, base * 0.14 * (1 - t * 0.5), sparkA);
    }
  }

  @override
  bool shouldRepaint(KuronFxOverlayPainter old) =>
      old.progress != progress ||
      old.kind != kind ||
      old.particleCount != particleCount ||
      old.dpr != dpr ||
      old.targetRect != targetRect ||
      old.wordSpec != wordSpec ||
      old.wordImage != wordImage ||
      old.direction != direction;
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
    bool isReader = false,
    Rect? targetRect,
  }) {
    _fire(
      context,
      kind: kind,
      isReader: isReader,
      targetRect: targetRect ?? targetRectOf(context),
    );
  }

  /// Fires a burst anchored on an explicit [rect] instead of a render box.
  ///
  /// Non-widget anchors (a tab label captured through a `GlobalKey`, a slider
  /// thumb fraction, a snack-bar content box, a toggle tile) hand over their
  /// rect here. Gating is identical to [trigger] — quiet mode, reduced motion,
  /// note themes and the reader are all no-ops — and both funnel through the
  /// same [_fire] path, so there is exactly one overlay entry and one timer.
  static void triggerOn(
    BuildContext context, {
    required Rect rect,
    required KuronFxKind kind,
    bool isReader = false,
    double direction = 1.0,
  }) {
    _fire(
      context,
      kind: kind,
      isReader: isReader,
      targetRect: rect,
      direction: direction,
    );
  }

  /// Single shared gate + dispatch path for [trigger] and [triggerOn].
  static void _fire(
    BuildContext context, {
    required KuronFxKind kind,
    required bool isReader,
    required Rect? targetRect,
    double direction = 1.0,
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
      targetRect: targetRect,
      monochrome: KuronMotionPolicy.isNoteTheme(context, listen: false),
      dark: Theme.of(context).brightness == Brightness.dark,
      direction: direction,
    );
  }

  /// Thumb-center box for a horizontal [Slider] track, derived from the value
  /// fraction (katalog slider §3). [thumbSize] matches Material's thumb
  /// diameter; the result is passed straight to [triggerOn] for `sliderFling`.
  /// The caller decides *when* to fire (fast release only); this only computes
  /// where the word lands.
  static Rect thumbRectOf(
    Rect trackRect,
    double value, {
    double min = 0,
    double max = 1,
    double thumbSize = 20,
  }) {
    final span = max - min;
    final fraction = span <= 0 ? 0.0 : ((value - min) / span).clamp(0.0, 1.0);
    final inset = thumbSize / 2;
    final usable = math.max(0.0, trackRect.width - thumbSize);
    final cx = trackRect.left + inset + usable * fraction;
    return Rect.fromCenter(
      center: Offset(cx, trackRect.center.dy),
      width: thumbSize,
      height: thumbSize,
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
}
