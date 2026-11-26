import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// Custom tooltip bubble drawn by this widget in the root overlay — no
/// dependency on the framework `Tooltip` paint. A long press shows the bubble,
/// fires the wordless-ring + KLIK! hollow beat on the icon, then auto-hides.
///
/// The bubble owns exactly one [OverlayEntry] and one [Timer], both torn down
/// by [dispose] (anti-leak). Reduced motion / quiet mode only suppresses the
/// FX through [KuronFx.triggerOn]; the informational bubble still appears.
class KuronTooltip extends StatefulWidget {
  const KuronTooltip({
    super.key,
    required this.message,
    required this.child,
    this.duration = const Duration(seconds: 2),
  });

  final String message;
  final Widget child;
  final Duration duration;

  @override
  State<KuronTooltip> createState() => _KuronTooltipState();
}

class _KuronTooltipState extends State<KuronTooltip> {
  final GlobalKey _iconKey = GlobalKey();
  OverlayEntry? _entry;
  Timer? _timer;

  static const double _bubbleWidth = 160;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _show() {
    if (_entry != null) return;
    final iconContext = _iconKey.currentContext;
    if (iconContext == null) return;
    final iconRect = KuronFx.targetRectOf(iconContext);
    if (iconRect == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // KLIK! hollow + procedural ring, anchored on the icon itself.
    KuronFx.triggerOn(context, rect: iconRect, kind: KuronFxKind.tooltipPop);

    final entry = OverlayEntry(
      opaque: false,
      builder: (overlayContext) {
        final size = MediaQuery.sizeOf(overlayContext);
        final maxLeft = math.max(8.0, size.width - _bubbleWidth - 8);
        final left = (iconRect.center.dx - _bubbleWidth / 2).clamp(
          8.0,
          maxLeft,
        );
        final above = iconRect.top - 56;
        final top = above >= 8 ? above : iconRect.bottom + 8;
        final colors = Theme.of(overlayContext).colorScheme;
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _bubbleWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.inverseSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.message,
                  style: TextStyle(
                    color: colors.onInverseSurface,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(widget.duration, _hide);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onLongPress: _show,
    child: KeyedSubtree(key: _iconKey, child: widget.child),
  );
}
