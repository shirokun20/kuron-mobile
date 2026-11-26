import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// Snack-bar content wrapper that fires the toast-landing beat once, anchored
/// just **above** the snack bar, when the snack bar is shown.
///
/// Hit-test transparent by construction: a [KeyedSubtree] adds no render box
/// of its own and never intercepts the snack bar's action button — the same
/// intent as [KuronSquash]'s translucent hit testing, without a gesture
/// detector. The single overlay entry and its TTL timer are owned by
/// [KuronFx], so this widget allocates nothing long-lived.
class KuronSnackBarContent extends StatefulWidget {
  const KuronSnackBarContent({super.key, required this.child});

  final Widget child;

  /// Anchor for the toast burst in root-overlay (== global) coordinates.
  ///
  /// Uses the enclosing [SnackBar]'s own box — not just the message box — so
  /// the BYAR! word and its puff/slash burst sit above the bottom bar and the
  /// ScaffoldMessenger padding instead of being sunk into the snack bar. The
  /// result is clamped to the view and its bottom safe area.
  static Rect anchorRectOf(BuildContext context, Rect contentRect) {
    final screen = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    Element? snackElement;
    context.visitAncestorElements((element) {
      if (element.widget is SnackBar) {
        snackElement = element;
        return false;
      }
      return true;
    });
    // A non-floating SnackBar rests against the bottom SafeArea. Use its
    // **height** (stable) rather than its live `top` (mid slide-in animation)
    // to derive the resting top; otherwise the burst ships off-screen.
    final snackBox = snackElement?.findRenderObject();
    final measured = snackBox is RenderBox && snackBox.hasSize
        ? snackBox.size.height
        : 0.0;
    // The box can still be unsized mid slide-in; fall back to the message
    // height + Material's 14dp vertical padding on each side.
    final snackHeight = measured > 0 ? measured : contentRect.height + 28;
    final top = snackElement == null
        ? contentRect.top - 8
        : screen.height - safeBottom - snackHeight;
    const clearance = 24.0;
    const height = 12.0;
    final upper = (screen.height - safeBottom - height).clamp(0.0, screen.height);
    final anchorTop = (top - clearance).clamp(0.0, upper);
    return Rect.fromLTWH(contentRect.center.dx - 24, anchorTop, 48, height);
  }

  @override
  State<KuronSnackBarContent> createState() => _KuronSnackBarContentState();
}

class _KuronSnackBarContentState extends State<KuronSnackBarContent> {
  final GlobalKey _contentKey = GlobalKey();
  Timer? _fireTimer;

  @override
  void initState() {
    super.initState();
    // The snack bar slides in from below: anchoring on its live box at frame
    // zero would place the burst off-screen. Wait for the slide-in to settle,
    // then use the resting geometry (above the bottom bar, inside the view).
    _fireTimer = Timer(const Duration(milliseconds: 220), _fire);
  }

  @override
  void dispose() {
    _fireTimer?.cancel();
    super.dispose();
  }

  void _fire() {
    if (!mounted) return;
    final contentContext = _contentKey.currentContext;
    if (contentContext == null) return;
    final contentRect = KuronFx.targetRectOf(contentContext);
    if (contentRect == null) return;
    final anchor = KuronSnackBarContent.anchorRectOf(contentContext, contentRect);
    KuronFx.triggerOn(
      contentContext,
      rect: anchor,
      kind: KuronFxKind.toastLand,
    );
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _contentKey, child: widget.child);
}
