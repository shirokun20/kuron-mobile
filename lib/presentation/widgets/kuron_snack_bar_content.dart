import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// Snack-bar content wrapper that fires the toast-landing beat once, anchored
/// just below the message, when the snack bar is shown.
///
/// Hit-test transparent by construction: a [KeyedSubtree] adds no render box
/// of its own and never intercepts the snack bar's action button — the same
/// intent as [KuronSquash]'s translucent hit testing, without a gesture
/// detector. The single overlay entry and its TTL timer are owned by
/// [KuronFx], so this widget allocates nothing long-lived.
class KuronSnackBarContent extends StatefulWidget {
  const KuronSnackBarContent({super.key, required this.child});

  final Widget child;

  @override
  State<KuronSnackBarContent> createState() => _KuronSnackBarContentState();
}

class _KuronSnackBarContentState extends State<KuronSnackBarContent> {
  final GlobalKey _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // The content box exists only after layout; post-frame also lets the
    // snack bar's slide-in start before the burst is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fire());
  }

  void _fire() {
    if (!mounted) return;
    final contentContext = _contentKey.currentContext;
    if (contentContext == null) return;
    final contentRect = KuronFx.targetRectOf(contentContext);
    if (contentRect == null) return;
    // Below-content anchor: a small box centered under the message. The
    // painter sizes the dotted BYAR! word relative to this box.
    final anchor = Rect.fromLTWH(
      contentRect.center.dx - 24,
      contentRect.bottom + 8,
      48,
      12,
    );
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
