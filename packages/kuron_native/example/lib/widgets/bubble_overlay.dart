import 'package:material_ui/material_ui.dart';

import '../models/page_translation.dart';

class BubbleOverlay extends StatelessWidget {
  final BubbleTranslation bubble;
  final double scaleX;
  final double scaleY;
  final bool isEditing;
  final VoidCallback? onTap;

  const BubbleOverlay({
    super.key,
    required this.bubble,
    required this.scaleX,
    required this.scaleY,
    this.isEditing = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final left = bubble.x * scaleX;
    final top = bubble.y * scaleY;
    final width = bubble.w * scaleX;
    final height = bubble.h * scaleY;

    // Detection mode: show blue box
    if (!bubble.isTranslated && !isEditing) {
      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueAccent, width: 2),
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '${bubble.id}',
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Translation overlay: white bg + text
    if (bubble.isTranslated && !bubble.isSkipped) {
      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber, width: 1.5),
            ),
            padding: const EdgeInsets.all(2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                bubble.translated,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
