import 'dart:math' as math;

import 'package:flutter/material.dart';

// Kuro mascot, moods A–F (mirrors prototype/kuro-mascot-prototype.html).
//
// CSS -> Dart mapping (timings copied from the prototype):
// - blink 4.2s  -> [_idle], eyes scaleY 1 -> 0.08 at the tail Interval.
// - breathe 3s  -> sin on [_idle] (3s ~= 4.2s / 1.4, close enough visually).
// - tearfall 1.4s + .7s right-eye delay -> [_cry] + Interval(0-0.7 / 0.3-1).
// - sob .5s     -> sin(value * pi * 6): 3 shakes per 1.4s loop, no 2nd controller.
// - glance 5s / flick 3.5s / huff 2.4s (tsundere) -> piecewise on [_idle].
//
// F (frozenCry) = F static design (pools + wail + -8deg tilt) + D motion.
// RemoteViews widgets can't animate, so export F frames as PNG for home;
// this widget is the in-app animated source of truth.
enum KuroMood {
  happy, // A — Blob Cat
  reader, // B — Ninja Reader (book)
  ghost, // C — Ghost Hood
  cry, // D — Nangis (tears + sob)
  tsundere, // E — seminggu gak buka
  frozenCry, // F — beku design + cry motion
  waiting, // G — sedang menunggu (loading): noleh kiri-kanan lambat
}

class KuroMascot extends StatefulWidget {
  final KuroMood mood;
  final double size;

  const KuroMascot({super.key, required this.mood, this.size = 160});

  @override
  State<KuroMascot> createState() => _KuroMascotState();
}

class _KuroMascotState extends State<KuroMascot> with TickerProviderStateMixin {
  // Idle loop 6s dengan SEMUA osilasi kelipatan bulat per loop — sebelumnya
  // 4.2s dengan breathe/float 1.4 cycle (sin(2π·1.4·1) ≠ sin(0)) bikin sentak
  // tiap wrap dari akhir ke awal loop.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6000),
  );
  late final AnimationController _cry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _needsCry =>
      widget.mood == KuroMood.cry || widget.mood == KuroMood.frozenCry;

  @override
  void initState() {
    super.initState();
    _idle.repeat();
    if (_needsCry) _cry.repeat();
  }

  @override
  void didUpdateWidget(KuroMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_needsCry && !_cry.isAnimating) {
      _cry.repeat();
    } else if (!_needsCry && _cry.isAnimating) {
      _cry
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _cry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _cry]),
      builder: (_, __) {
        final t = _idle.value;
        final c = _cry.value;

        // blink: smooth cosine dip (0→1→0), bukan threshold jepret.
        // Threshold kemarin (1→0.08 instan) yang bikin kedip patah.
        final blink = _blinkBump(t);
        final eyeScale = 1 - 0.92 * blink;
        // breathe 3s x2 = 2 cycle/loop (nutup sempurna, tanpa sentak wrap).
        final breathe = 1 + 0.04 * math.sin(t * math.pi * 4);
        // floaty 3s x2 (happy + ghost only).
        final floatY =
            (widget.mood == KuroMood.happy || widget.mood == KuroMood.ghost)
                ? -12 * (0.5 - 0.5 * math.cos(t * math.pi * 4))
                : 0.0;
        // sob-shake for cry moods (3 cycle/loop, sudah nutup).
        final sobX = _needsCry ? 3 * math.sin(c * math.pi * 6) : 0.0;
        // tsundere glance: stare right, flick back at the end.
        // waiting glance: slow L-R oscillation, 1 cycle/loop (nutup mulus).
        final glanceX = widget.mood == KuroMood.tsundere
            ? (t < 0.3 ? 0.0 : (t < 0.8 ? 8.0 : -2.0))
            : widget.mood == KuroMood.waiting
                ? 5.0 * math.sin(t * math.pi * 2)
                : 0.0;

        Widget body = CustomPaint(
          size: Size.square(widget.size),
          painter: _KuroPainter(
            mood: widget.mood,
            // Tsundere kedip dari base half-lid 0.75 -> 0.06, ikut bump halus.
            eyeScale: widget.mood == KuroMood.tsundere
                ? 0.75 * (1 - 0.92 * blink)
                : eyeScale,
            glanceX: glanceX,
            tearL: _tear(const Interval(0.0, 0.7).transform(c)),
            tearR: _tear(const Interval(0.3, 1.0).transform(c)),
            huff: 0.5 - 0.5 * math.cos(t * math.pi * 4),
          ),
        );

        if (widget.mood == KuroMood.frozenCry) {
          body = Transform.rotate(angle: -8 * math.pi / 180, child: body);
        }

        return Transform.translate(
          offset: Offset(sobX, floatY),
          child: Transform.scale(scale: breathe, child: body),
        );
      },
    );
  }

  // blink bump: 0 di luar jendela, cosine 0→1→0 di dalam (center 0.95,
  // setengah-lebar 0.035). Kedua ujung = 0 persis -> wrap loop mulus.
  static double _blinkBump(double t) {
    const c = 0.95, w = 0.035;
    final d = ((t - c).abs()) / w;
    if (d >= 1) return 0.0;
    return 0.5 + 0.5 * math.cos(d * math.pi);
  }

  // tearfall: fade in by 20%, fall 26px, fade out by 100%.
  static ({double dy, double opacity}) _tear(double p) {
    if (p <= 0 || p >= 1) return (dy: 0, opacity: 0);
    return (
      dy: -2 + 28 * p,
      opacity: p < 0.2 ? p / 0.2 : 1 - (p - 0.2) / 0.8,
    );
  }
}

class _KuroPainter extends CustomPainter {
  final KuroMood mood;
  final double eyeScale;
  final double glanceX;
  final ({double dy, double opacity}) tearL;
  final ({double dy, double opacity}) tearR;
  final double huff;

  const _KuroPainter({
    required this.mood,
    required this.eyeScale,
    required this.glanceX,
    required this.tearL,
    required this.tearR,
    required this.huff,
  });

  static const _ink = Color(0xFF1A1A1F);
  static const _hood = Color(0xFF3A3A48);
  static const _coral = Color(0xFFF1958E);
  static const _pupil = Color(0xFF3A2B2B);
  static const _tear = Color(0xFF7DD3FC);
  static const _wail = Color(0xFF5B2226);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200; // prototype viewBox 0 0 200 200
    canvas.scale(s);
    final w = Paint()..color = Colors.white;
    final ink = Paint()..color = Colors.black;

    // shadow
    canvas.drawOval(
      const Rect.fromLTWH(48, 167, 104, 18),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // tail (reader + tsundere)
    if (mood == KuroMood.reader || mood == KuroMood.tsundere) {
      canvas.drawPath(
        Path()
          ..moveTo(148, 150)
          ..quadraticBezierTo(178, 158, 168, 122),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round,
      );
    }

    final isGhost = mood == KuroMood.ghost;
    final bodyPaint = Paint()..color = isGhost ? _hood : _ink;

    // ears
    for (final left in [true, false]) {
      final x = left ? 42.0 : 158.0;
      final ear = Path()
        ..moveTo(x, 70)
        ..lineTo(left ? x + 10 : x - 10, 28)
        ..lineTo(left ? x + 40 : x - 40, 52)
        ..close();
      canvas.drawPath(ear, bodyPaint);
      canvas.drawPath(
          ear,
          ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
      ink.style = PaintingStyle.fill;
      // inner ear pink (prototipe A/B/D/E; ghost tanpa pink)
      if (!isGhost) {
        final inner = Path()
          ..moveTo(left ? 48.0 : 152.0, 62)
          ..lineTo(left ? 54.0 : 146.0, 40)
          ..lineTo(left ? 72.0 : 128.0, 52)
          ..close();
        canvas.drawPath(inner, Paint()..color = _coral.withValues(alpha: 0.7));
      }
    }

    // hood (ghost): WIDER than head so the silhouette differs, black outline
    // + scallop hem (ikut prototipe C). Hood lama kekecilan (x45-155 di dalam
    // head x36-164) makanya tenggelam di screenshot device.
    if (isGhost) {
      final hood = Path()
        ..moveTo(32, 168)
        ..quadraticBezierTo(28, 88, 62, 54)
        ..quadraticBezierTo(76, 40, 100, 40)
        ..quadraticBezierTo(124, 40, 138, 54)
        ..quadraticBezierTo(172, 88, 168, 168)
        ..quadraticBezierTo(158, 158, 148, 168)
        ..quadraticBezierTo(138, 178, 128, 168)
        ..quadraticBezierTo(118, 158, 108, 168)
        ..quadraticBezierTo(98, 178, 88, 168)
        ..quadraticBezierTo(78, 158, 68, 168)
        ..quadraticBezierTo(58, 178, 48, 168)
        ..quadraticBezierTo(38, 158, 32, 168)
        ..close();
      canvas.drawPath(hood, bodyPaint);
      canvas.drawPath(
          hood,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round);
    }
    // kepala near-circle (120x116) ikut referensi splash; dulu 128x112 pipih.
    final head = RRect.fromLTRBR(
      40,
      50,
      160,
      isGhost ? 150 : 166,
      const Radius.circular(58),
    );
    canvas.drawRRect(head, Paint()..color = _ink);
    canvas.drawRRect(
        head,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    if (isGhost) {
      canvas.drawOval(
        const Rect.fromLTWH(58, 65, 84, 80),
        Paint()..color = _ink,
      );
      // sparkles (prototipe C)
      _sparkle(canvas, 40, 60, 7, const Color(0xFF9D8CFF));
      _sparkle(canvas, 162, 90, 7, const Color(0xFFFFE66D));
    }
    if (mood == KuroMood.happy) {
      // sparkle (prototipe A)
      _sparkle(canvas, 160, 40, 8, const Color(0xFFFFE66D));
    }

    _eyes(canvas, w);
    _mouth(canvas);

    // static blush (cry moods skip pulsing; widget has no cheap static hook)
    if (mood != KuroMood.cry && mood != KuroMood.frozenCry) {
      final blush = Paint()..color = _coral.withValues(alpha: 0.8);
      canvas.drawOval(const Rect.fromLTWH(44, 122, 24, 12), blush);
      canvas.drawOval(const Rect.fromLTWH(132, 122, 24, 12), blush);
    }

    if (mood == KuroMood.reader) _book(canvas);
    if (mood == KuroMood.cry || mood == KuroMood.frozenCry) _cryFace(canvas);
    if (mood == KuroMood.tsundere) {
      // blush nyebrang batang hidung = malu ketahuan (ciri tsundere inti).
      canvas.drawOval(
        const Rect.fromLTWH(88, 112, 24, 10),
        Paint()..color = _coral.withValues(alpha: 0.5),
      );
      _arms(canvas);
      _huff(canvas);
    }
  }

  void _eyes(Canvas canvas, Paint w) {
    final pupil = Paint()..color = _pupil;
    if (mood == KuroMood.cry || mood == KuroMood.frozenCry) {
      // >_< merem nahan nangis: stroke TEBAL (4->6, span 12->16) + wrinkle di
      // sudut luar tiap mata. X tipis = kebaca "mati" di 48dp (temuan dari
      // screenshot device); X tebal + wrinkle = "merem sekencengnya".
      final shut = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      final wrinkle = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final cx in [64.0, 136.0]) {
        canvas.drawLine(Offset(cx - 8, 98), Offset(cx + 8, 110), shut);
        canvas.drawLine(Offset(cx + 8, 98), Offset(cx - 8, 110), shut);
        final dir = cx < 100 ? -1.0 : 1.0; // wrinkle di sudut luar mata
        canvas.drawLine(
            Offset(cx + dir * 12, 100), Offset(cx + dir * 18, 97), wrinkle);
        canvas.drawLine(
            Offset(cx + dir * 12, 108), Offset(cx + dir * 18, 111), wrinkle);
      }
      return;
    }
    final small = mood == KuroMood.ghost;
    final isTsun = mood == KuroMood.tsundere;
    final rx = small ? 13.0 : 18.0;
    final ry = (small ? 16.0 : 20.0) * (isTsun ? 0.75 : 1.0);
    for (final cx in [72.0, 128.0]) {
      canvas.save();
      canvas.translate(cx, 106);
      canvas.scale(1, eyeScale);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
          w);
      // half-lid: tutup 40% atas mata pakai warna kepala -> tatapan jutek
      // setengah merem (tetap keliatan di kepala hitam karena nutup putih).
      if (isTsun) {
        canvas.drawRRect(
          RRect.fromLTRBR(-rx, -ry, rx, -ry * 0.2, const Radius.circular(6)),
          Paint()..color = _ink,
        );
      }
      final px = (small ? 1.0 : 5.0) + glanceX;
      // happy/reader noleh ke bawah (ikut referensi splash): pupil +highlight
      // turun; ghost/tsundere tidak (punya tatapan sendiri).
      final down = (!small && !isTsun) ? 3.0 : 0.0;
      canvas.drawCircle(
          Offset(px + 1, 4 + down), small ? 7.0 : (isTsun ? 6.5 : 9.0), pupil);
      canvas.drawCircle(Offset(px + 3, 1 + down), 3, w);
      canvas.restore();
    }
    if (isTsun) {
      // alis jutek: abu terang (alis _ink kemarin tenggelam di kepala hitam),
      // tipis, tinggi, miring tajem. Marah + malu, bukan marah doang.
      final brow = Paint()
        ..color = const Color(0xFF55556A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(54, 90), const Offset(90, 80), brow);
      canvas.drawLine(const Offset(146, 90), const Offset(110, 80), brow);
    }
  }

  void _mouth(Canvas canvas) {
    final line = Paint()
      ..color = _coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    switch (mood) {
      case KuroMood.cry:
        canvas.drawPath(
          Path()
            ..moveTo(90, 144)
            ..quadraticBezierTo(100, 136, 110, 144)
            ..quadraticBezierTo(100, 152, 90, 144),
          Paint()..color = _wail,
        );
      case KuroMood.frozenCry:
        canvas.drawRRect(
          RRect.fromLTRBR(89, 140, 111, 156, const Radius.circular(8)),
          Paint()..color = _wail,
        );
        canvas.drawOval(
          const Rect.fromLTWH(93, 148, 14, 8),
          Paint()..color = _coral,
        );
      case KuroMood.tsundere:
        // pout ASIMETRIS geser ke arah nolehan + congklak di ujung.
        // Mulut simetris = netral; mulut minggir = "hmph, terserah".
        final p = Path()
          ..moveTo(94, 140)
          ..quadraticBezierTo(106, 134, 120, 141)
          ..lineTo(120, 147);
        canvas.drawPath(p, line);
      case KuroMood.ghost:
        canvas.drawOval(
          const Rect.fromLTWH(95, 124, 10, 7),
          Paint()..color = _coral,
        );
      case KuroMood.happy:
      case KuroMood.reader:
        final p = Path()
          ..moveTo(94, 132)
          ..quadraticBezierTo(100, 138, 106, 132);
        canvas.drawPath(p, line..strokeWidth = 3);
      case KuroMood.waiting:
        // garis datar netral: sabar menunggu, bukan senang/pout.
        canvas.drawLine(const Offset(92, 140), const Offset(108, 140),
            line..strokeWidth = 3);
    }
    if (mood != KuroMood.cry &&
        mood != KuroMood.frozenCry &&
        mood != KuroMood.ghost) {
      canvas.drawOval(
        const Rect.fromLTWH(93, 128, 14, 10),
        Paint()..color = _coral,
      );
    }
  }

  // book dipersempit (x56-144) supaya blush pipi ngintip di sisi kiri-kanan;
  // buku selebar prototipe (x48-152) nutup blush total di screenshot device.
  void _book(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromLTRBR(56, 118, 144, 174, const Radius.circular(10)),
      Paint()..color = _coral,
    );
    canvas.drawLine(
      const Offset(100, 118),
      const Offset(100, 174),
      Paint()
        ..color = Colors.black
        ..strokeWidth = 4,
    );
    final page = Paint()..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawRRect(
      RRect.fromLTRBR(66, 132, 92, 138, const Radius.circular(3)),
      page,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(108, 132, 134, 138, const Radius.circular(3)),
      page,
    );
  }

  // 4-point sparkle (pernak-pernik prototipe A/C).
  void _sparkle(Canvas canvas, double cx, double cy, double r, Color color) {
    final p = Path()
      ..moveTo(cx, cy - r)
      ..quadraticBezierTo(cx, cy, cx + r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy + r)
      ..quadraticBezierTo(cx, cy, cx - r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _cryFace(Canvas canvas) {
    if (mood == KuroMood.frozenCry) {
      // Duo-style static pools + hanging drops (the PNG-safe part).
      final pool = Paint()..color = _tear;
      canvas.drawOval(const Rect.fromLTWH(47, 131, 26, 18), pool);
      canvas.drawOval(const Rect.fromLTWH(127, 131, 26, 18), pool);
      final hi = Paint()..color = Colors.white.withValues(alpha: 0.9);
      canvas.drawOval(const Rect.fromLTWH(52, 134, 8, 5), hi);
      canvas.drawOval(const Rect.fromLTWH(132, 134, 8, 5), hi);
    }
    // falling drops (animated; opacity 0 when idle).
    for (final (cx, t) in [(64.0, tearL), (136.0, tearR)]) {
      if (t.opacity <= 0) continue;
      final drop = Paint()..color = _tear.withValues(alpha: t.opacity);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 118 + t.dy), width: 12, height: 18),
        drop,
      );
    }
  }

  // huff keluar dari sudut mulut (dulu melayang di luar kepala, jauh dari mulut).
  void _huff(Canvas canvas) {
    final bubble = Paint()..color = Colors.white;
    for (final (d, r, o) in [
      (0.0, 6.0, 0.8),
      (10.0, 4.0, 0.6),
      (17.0, 2.5, 0.4)
    ]) {
      bubble.color = Colors.white.withValues(alpha: o * (0.5 + 0.5 * huff));
      canvas.drawCircle(
          Offset(134 + d * 1.2, 140 - d), r * (0.8 + 0.4 * huff), bubble);
    }
  }

  // lengan disilangkan di perut + TANGAN (paw) di ujungnya. Tanpa paw, lengan
  // kemarin kebaca syal (temuan screenshot device). Paw = bukti "ini tangan
  // bersedekap", bukan dekorasi. Turun 6px biar mulut bebas.
  void _arms(Canvas canvas) {
    const arms = [
      (Offset(152, 142), Offset(98, 160)), // kanan (bawah)
      (Offset(48, 142), Offset(102, 160)), // kiri (atas)
    ];
    for (final (a, b) in arms) {
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 22
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = _hood
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..strokeCap = StrokeCap.round);
    }
    // paws: lingkaran + outline, di ujung dalam tiap lengan (dekat siku lawan).
    for (final paw in [const Offset(98, 160), const Offset(102, 160)]) {
      canvas.drawCircle(paw, 10, Paint()..color = Colors.black);
      canvas.drawCircle(paw, 7, Paint()..color = _hood);
    }
  }

  @override
  bool shouldRepaint(_KuroPainter old) =>
      old.mood != mood ||
      old.eyeScale != eyeScale ||
      old.glanceX != glanceX ||
      old.tearL != tearL ||
      old.tearR != tearR ||
      old.huff != huff;
}

/// Full-screen loading: Kuro waiting + message. Pengganti
/// `AppProgressIndicator` khusus loading sepenuh layar (detail header,
/// reader, pdf). Spinner inline di list/button TETAP pakai yang lama
/// (mascot animasi di list = puluhan ticker, boros).
class KuroLoading extends StatelessWidget {
  final String? message;
  final double size;

  const KuroLoading({super.key, this.message, this.size = 120});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Tanpa message (overlay detail/pdf) = badge LINGKARAN pas badan Kuro.
    // Ada message (reader) = rounded rect biar teks nggak kepotong.
    final circle = message == null;
    return Container(
      width: circle ? size + 48 : null,
      height: circle ? size + 48 : null,
      padding: circle
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      alignment: circle ? Alignment.center : null,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KuroMascot(mood: KuroMood.waiting, size: size),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
