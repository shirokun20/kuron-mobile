import 'package:flutter/material.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';

// Dedicated tier avatar: same black-cat base for every tier, one accessory
// each. Deliberately NOT a KuroMascot mood — avatars are 40-52px identity
// marks, drawn bold to survive the size. Static paint (no tickers):
// a drawer badge doesn't need a heartbeat.
//
// - santai   : plain, calm
// - kutubuku : round glasses (bookworm)
// - otaku    : headphone band + pads
// - resi     : dusty hood ring (jubah pertapa)
// - shaker   : sweat drop + worried mouth (badge of shame)
class KuroTierAvatar extends StatelessWidget {
  const KuroTierAvatar({super.key, required this.tier, required this.size});

  final ReaderTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _KuroTierAvatarPainter(tier),
    );
  }
}

class _KuroTierAvatarPainter extends CustomPainter {
  _KuroTierAvatarPainter(this.tier);

  final ReaderTier tier;

  static const _ink = Color(0xFF1A1A1F);
  static const _innerEar = Color(0xFFF1958E);
  static const _mouth = Color(0xFFF1958E);
  static const _blush = Color(0xFFE0827E);
  static const _glasses = Color(0xFFF5EDE4);
  static const _hood = Color(0xFF9D555B);
  static const _pad = Color(0xFFF1958E);
  static const _sweat = Color(0xFF7DD3FC);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.save();
    canvas.scale(s);

    if (tier == ReaderTier.resi) _paintHoodBack(canvas);

    // Ears.
    final earL = Path()
      ..moveTo(52, 80)
      ..lineTo(64, 26)
      ..lineTo(102, 62)
      ..close();
    final earR = Path()
      ..moveTo(148, 80)
      ..lineTo(136, 26)
      ..lineTo(98, 62)
      ..close();
    canvas.drawPath(earL, Paint()..color = _ink);
    canvas.drawPath(earR, Paint()..color = _ink);
    canvas.drawPath(
      Path()
        ..moveTo(62, 70)
        ..lineTo(68, 42)
        ..lineTo(90, 60)
        ..close(),
      Paint()..color = _innerEar,
    );
    canvas.drawPath(
      Path()
        ..moveTo(138, 70)
        ..lineTo(132, 42)
        ..lineTo(110, 60)
        ..close(),
      Paint()..color = _innerEar,
    );

    // Head.
    canvas.drawCircle(const Offset(100, 112), 64, Paint()..color = _ink);

    // Eyes (white + pupil + highlight), slight down-glance.
    for (final cx in [76.0, 124.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 112), width: 28, height: 34),
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(Offset(cx, 116), 6.5, Paint()..color = Colors.black);
      canvas.drawCircle(Offset(cx + 2, 113), 2, Paint()..color = Colors.white);
    }

    // Blush.
    for (final cx in [58.0, 142.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, 132), width: 16, height: 10),
        Paint()..color = _blush.withValues(alpha: 0.55),
      );
    }

    // Mouth: default w, worried o for shaker.
    final mouthPaint = Paint()
      ..color = _mouth
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (tier == ReaderTier.shaker) {
      canvas.drawCircle(const Offset(100, 138), 5, mouthPaint);
    } else {
      final mouth = Path()
        ..moveTo(100, 130)
        ..lineTo(100, 135)
        ..moveTo(100, 135)
        ..quadraticBezierTo(100, 141, 93, 141)
        ..moveTo(100, 135)
        ..quadraticBezierTo(100, 141, 107, 141);
      canvas.drawPath(mouth, mouthPaint);
    }

    // Whiskers.
    final whisker = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final dy in [-4.0, 4.0, 12.0]) {
      canvas.drawLine(Offset(40, 124 + dy), Offset(16, 120 + dy), whisker);
      canvas.drawLine(Offset(160, 124 + dy), Offset(184, 120 + dy), whisker);
    }

    // Per-tier accessory, drawn last (front layer).
    switch (tier) {
      case ReaderTier.santai:
        break;
      case ReaderTier.kutubuku:
        _paintGlasses(canvas);
      case ReaderTier.otaku:
        _paintHeadphones(canvas);
      case ReaderTier.resi:
        break; // hood ring already behind the head
      case ReaderTier.shaker:
        _paintSweat(canvas);
    }

    canvas.restore();
  }

  void _paintHoodBack(Canvas canvas) {
    canvas.drawCircle(const Offset(100, 108), 80, Paint()..color = _hood);
    canvas.drawPath(
      Path()
        ..moveTo(100, 18)
        ..lineTo(78, 48)
        ..lineTo(122, 48)
        ..close(),
      Paint()..color = _hood,
    );
  }

  void _paintGlasses(Canvas canvas) {
    final frame = Paint()
      ..color = _glasses
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(76, 112), 21, frame);
    canvas.drawCircle(const Offset(124, 112), 21, frame);
    canvas.drawLine(const Offset(97, 108), const Offset(103, 108), frame);
    canvas.drawLine(const Offset(55, 106), const Offset(42, 98), frame);
    canvas.drawLine(const Offset(145, 106), const Offset(158, 98), frame);
  }

  void _paintHeadphones(Canvas canvas) {
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(100, 104), width: 150, height: 150),
      3.1416,
      3.1416,
      false,
      Paint()
        ..color = _hood
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round,
    );
    for (final x in [36.0, 140.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 96, 24, 44), const Radius.circular(10)),
        Paint()..color = _pad,
      );
    }
  }

  void _paintSweat(Canvas canvas) {
    final drop = Path()
      ..moveTo(160, 44)
      ..cubicTo(160, 44, 146, 66, 146, 76)
      ..cubicTo(146, 86, 152, 92, 160, 92)
      ..cubicTo(168, 92, 174, 86, 174, 76)
      ..cubicTo(174, 66, 160, 44, 160, 44)
      ..close();
    canvas.drawPath(drop, Paint()..color = _sweat);
    canvas.drawCircle(const Offset(155, 76), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_KuroTierAvatarPainter oldDelegate) =>
      oldDelegate.tier != tier;
}
