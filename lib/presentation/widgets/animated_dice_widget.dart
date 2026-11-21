import 'package:material_ui/material_ui.dart';

// Animated dice SVG widget that spins on demand
class AnimatedDiceWidget extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onSpinComplete;
  final bool isSpinning;
  final Color? color;

  const AnimatedDiceWidget({
    super.key,
    this.duration = const Duration(milliseconds: 600),
    this.onSpinComplete,
    required this.isSpinning,
    this.color,
  });

  @override
  State<AnimatedDiceWidget> createState() => _AnimatedDiceWidgetState();
}

class _AnimatedDiceWidgetState extends State<AnimatedDiceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.isSpinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedDiceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpinning && !oldWidget.isSpinning) {
      _controller
        ..reset()
        ..repeat();
    } else if (!widget.isSpinning && oldWidget.isSpinning) {
      _controller
        ..stop()
        ..reset();
      widget.onSpinComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;

    return RotationTransition(turns: _controller, child: _buildDiceSvg(color));
  }

  Widget _buildDiceSvg(Color color) {
    return CustomPaint(
      painter: _DicePainter(color: color),
      size: const Size(24, 24),
    );
  }
}

class _DicePainter extends CustomPainter {
  const _DicePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Main cube outline (isometric-style dice)
    final topLeft = Offset(size.width * 0.2, size.height * 0.15);
    final topRight = Offset(size.width * 0.8, size.height * 0.15);
    final bottomRight = Offset(size.width * 0.8, size.height * 0.65);
    final bottomLeft = Offset(size.width * 0.2, size.height * 0.65);
    final topBackLeft = Offset(size.width * 0.05, size.height * 0.35);
    final topBackRight = Offset(size.width * 0.95, size.height * 0.35);
    final bottomBackLeft = Offset(size.width * 0.05, size.height * 0.85);
    final bottomBackRight = Offset(size.width * 0.95, size.height * 0.85);

    // Draw front face (filled lighter)
    canvas.drawPath(
      Path()
        ..moveTo(topLeft.dx, topLeft.dy)
        ..lineTo(topRight.dx, topRight.dy)
        ..lineTo(bottomRight.dx, bottomRight.dy)
        ..lineTo(bottomLeft.dx, bottomLeft.dy)
        ..close(),
      fillPaint,
    );

    // Draw cube wireframe
    // Front face
    canvas.drawLine(topLeft, topRight, paint);
    canvas.drawLine(topRight, bottomRight, paint);
    canvas.drawLine(bottomRight, bottomLeft, paint);
    canvas.drawLine(bottomLeft, topLeft, paint);

    // Back face
    canvas.drawLine(topBackLeft, topBackRight, paint);
    canvas.drawLine(topBackRight, bottomBackRight, paint);
    canvas.drawLine(bottomBackRight, bottomBackLeft, paint);
    canvas.drawLine(bottomBackLeft, topBackLeft, paint);

    // Connect front to back
    canvas.drawLine(topLeft, topBackLeft, paint);
    canvas.drawLine(topRight, topBackRight, paint);
    canvas.drawLine(bottomRight, bottomBackRight, paint);
    canvas.drawLine(bottomLeft, bottomBackLeft, paint);

    // Draw dots on front face (like a die)
    final dotRadius = size.width * 0.05;
    final dotPaint = Paint()..color = color;

    // Center dot (always visible)
    final centerX = size.width * 0.5;
    final centerY = size.height * 0.4;
    canvas.drawCircle(Offset(centerX, centerY), dotRadius, dotPaint);

    // Top-left dot
    canvas.drawCircle(
      Offset(topLeft.dx + dotRadius * 3, topLeft.dy + dotRadius * 3),
      dotRadius,
      dotPaint,
    );

    // Bottom-right dot
    canvas.drawCircle(
      Offset(bottomRight.dx - dotRadius * 3, bottomRight.dy - dotRadius * 3),
      dotRadius,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(_DicePainter oldDelegate) => oldDelegate.color != color;
}
