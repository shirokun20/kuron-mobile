import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// One-line sakuga effects for **every** slider (and RangeSlider).
///
/// ```dart
/// Slider(...).withKuronSliderFx()               // settings
/// Slider(...).withKuronSliderFx(isReader: true) // reader: hard-off
/// ```
///
/// The wrapper listens to raw pointer events around the existing control, so
/// no slider callback needs rewiring. Velocity is normalised to **range
/// fractions per second** — the same unit as the gallery's slider thumb
/// spring (`Spring(0, 420, 30)` over a 0..1 fraction). Katalog slider §3 uses
/// |v| > 0.35 for a fast drag, |v| > 1.5 for the mid-drag word (1.1 s apart)
/// and |peak| > 1.3 on release; this fires the release beat only, so no
/// cooldown can swallow it. A real finger fling over a ~240 px track reaches
/// several ranges/s; a slow drag never clears the threshold.
///
/// Gating is identical to [KuronFx.triggerOn]: quiet / reduced motion / note
/// themes / reader are decoration-free no-ops. One bounded tracker, no timer,
/// no per-frame allocation and nothing left mounted after the pointer leaves.
class KuronSliderEffects extends StatefulWidget {
  const KuronSliderEffects({
    super.key,
    required this.child,
    this.isReader = false,
    this.thumbSize = 20,
  });

  final Widget child;

  /// Reader sliders stay hard-off even when the stored mode is not quiet.
  final bool isReader;

  /// Material thumb diameter (the reader settings sheet uses 12).
  final double thumbSize;

  /// Katalog release peak, in range fractions per second.
  static const double releaseThreshold = 1.3;

  @override
  State<KuronSliderEffects> createState() => _KuronSliderEffectsState();
}

/// Attach the fling beat to any existing slider with a single call.
extension KuronSliderFx on Widget {
  Widget withKuronSliderFx({bool isReader = false, double thumbSize = 20}) =>
      KuronSliderEffects(isReader: isReader, thumbSize: thumbSize, child: this);
}

class _KuronSliderEffectsState extends State<KuronSliderEffects> {
  VelocityTracker? _tracker;
  Rect? _trackRect;
  double _peak = 0;

  double get _usable => (_trackRect?.width ?? 0) - widget.thumbSize;

  void _sample(Duration time, Offset position) {
    final tracker = _tracker;
    final usable = _usable;
    if (tracker == null || usable <= 0) return;
    tracker.addPosition(time, position);
    final v = tracker.getVelocity().pixelsPerSecond.dx / usable;
    // Katalog peak: keep the largest signed velocity, decay the old peak.
    if (v.abs() > _peak.abs()) {
      _peak = v;
    } else {
      _peak *= 0.96;
    }
  }

  void _onDown(PointerDownEvent event) {
    _tracker = VelocityTracker.withKind(event.kind);
    _trackRect = KuronFx.targetRectOf(context);
    _peak = 0;
  }

  void _onMove(PointerMoveEvent event) =>
      _sample(event.timeStamp, event.localPosition);

  void _onUp(PointerUpEvent event) {
    _sample(event.timeStamp, event.localPosition);
    final rect = _trackRect;
    if (_peak.abs() > KuronSliderEffects.releaseThreshold && rect != null) {
      final usable = _usable;
      final fraction = usable <= 0
          ? 0.0
          : ((event.localPosition.dx - widget.thumbSize / 2) / usable).clamp(
              0.0,
              1.0,
            );
      KuronFx.triggerOn(
        context,
        rect: KuronFx.thumbRectOf(rect, fraction, thumbSize: widget.thumbSize),
        kind: KuronFxKind.sliderFling,
        isReader: widget.isReader,
      );
    }
    _tracker = null;
    _peak = 0;
  }

  void _onCancel(PointerCancelEvent event) {
    _tracker = null;
    _peak = 0;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: widget.child,
  );
}
