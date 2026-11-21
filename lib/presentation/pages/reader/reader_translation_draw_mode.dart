import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kuron_native/kuron_native.dart' show BubbleBox;
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_translation_cubit.dart';

import '../../../core/utils/polygon_geometry.dart';
import 'reader_translation_widgets.dart';

/// Shape tools for manual bubble drawing.
enum DrawShapeTool { rect, ellipse, freeform }

extension DrawShapeToolX on DrawShapeTool {
  IconData get icon => switch (this) {
    DrawShapeTool.rect => Icons.crop_square,
    DrawShapeTool.ellipse => Icons.circle_outlined,
    DrawShapeTool.freeform => Icons.gesture,
  };

  String tooltip(AppLocalizations l10n) => switch (this) {
    DrawShapeTool.rect => l10n.aiDrawRect,
    DrawShapeTool.ellipse => l10n.aiDrawEllipse,
    DrawShapeTool.freeform => l10n.aiDrawFreeform,
  };
}

/// Screen-space shape entry for one detected bubble.
class _BubbleDrawEntry {
  const _BubbleDrawEntry({required this.rect, this.poly, this.kind});
  final Rect rect; // bounding box (screen px) — used for hit testing
  final List<Offset>? poly; // polygon in screen px, null = box fallback
  final String? kind; // "balloon" | "text" | null
}

/// Manual bubble drawing mode (spec 9.5): shape tools → red bubble outline.
/// ONNX-detected bubbles shown in BLUE as reference; manual bubbles in RED.
/// Controls: tool select / Detect / Undo / Clear / Done.
///
/// Repaint is driven by local [setState] — the cubit state is Equatable and
/// emitting identical states is skipped by the bloc, so painter freshes
/// must not rely on state changes.
class ReaderTranslationDrawMode extends StatefulWidget {
  const ReaderTranslationDrawMode({super.key, this.onCaptureNeeded});

  /// Called before running detection when no page is captured yet (lazy
  /// capture). Lets the reader capture the current viewport only on demand,
  /// instead of on every draw-mode entry (which janks on repeated toggles).
  final Future<void> Function()? onCaptureNeeded;

  @override
  State<ReaderTranslationDrawMode> createState() =>
      _ReaderTranslationDrawModeState();
}

class _ReaderTranslationDrawModeState extends State<ReaderTranslationDrawMode> {
  DrawShapeTool _tool = DrawShapeTool.rect;
  List<Offset>? _freeformPoints;
  List<_BubbleDrawEntry> _onnxEntries = const [];
  List<_BubbleDrawEntry> _manualEntries = const [];
  bool _detecting = false;

  // Entry points (private, of library scope) used by widget tests to drive
  // the gesture layer. Kept minimal and private so test setup can reach the
  // controller without tapping the real UI.
  @visibleForTesting
  void setToolForTest(DrawShapeTool tool) => _tool = tool;

  @visibleForTesting
  void onTapForTest(
    ReaderTranslationCubit cubit,
    Offset pos,
    double scaleX,
    double scaleY,
    double topOffset,
  ) => _handleTap(cubit, pos, scaleX, scaleY, topOffset);

  @visibleForTesting
  void onPanEndForTest(
    ReaderTranslationCubit cubit,
    Offset start,
    Offset end,
    double scaleX,
    double scaleY,
    double topOffset,
  ) {
    _freeformPoints = [start, end];
    _onPanEnd(cubit, scaleX, scaleY, topOffset);
  }

  void _repaint() => setState(() {});

  /// Rect currently being dragged (rect/ellipse tools only).
  Rect? get _draggingRect {
    if (_freeformPoints == null || _freeformPoints!.isEmpty) return null;
    return Rect.fromPoints(_freeformPoints!.first, _freeformPoints!.last);
  }

  /// Tap on a bubble removes it — mirrors the example app. Topmost hit wins:
  /// manual bubbles (red) checked before ONNX (blue).
  void _handleTap(
    ReaderTranslationCubit cubit,
    Offset pos,
    double scaleX,
    double scaleY,
    double topOffset,
  ) {
    for (var i = _manualEntries.length - 1; i >= 0; i--) {
      if (_manualEntries[i].rect.contains(pos)) {
        cubit.removeManualBubble(i);
        _repaint();
        return;
      }
    }
    for (var i = _onnxEntries.length - 1; i >= 0; i--) {
      if (_onnxEntries[i].rect.contains(pos)) {
        cubit.removeDetectedBubble(i);
        _repaint();
        return;
      }
    }
  }

  /// Pan start: seed the shape for the active tool.
  void _onPanStart(DragStartDetails d) {
    if (_tool == DrawShapeTool.freeform) {
      setState(() => _freeformPoints = [d.localPosition]);
    } else {
      setState(() => _freeformPoints = [d.localPosition, d.localPosition]);
    }
  }

  /// Pan update: accumulate freeform points or grow the drag rect.
  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      if (_tool == DrawShapeTool.freeform) {
        _freeformPoints!.add(d.localPosition);
      } else {
        _freeformPoints = [_freeformPoints!.first, d.localPosition];
      }
    });
  }

  /// Pan end: build the manual bubble (image px) for the finished shape.
  void _onPanEnd(
    ReaderTranslationCubit cubit,
    double scaleX,
    double scaleY,
    double topOffset,
  ) {
    final pts = _freeformPoints;
    if (pts != null && pts.length >= 2) {
      final rect = Rect.fromPoints(pts.first, pts.last);
      if (rect.width > 4 && rect.height > 4) {
        // Screen space → image space (ONNX bubbles are image px).
        // Note: renderedH may exceed the screen (tall pages) —
        // vertical scale is renderedH/imgH, NOT screenH/imgH.
        final imgRect = Rect.fromLTRB(
          rect.left / scaleX,
          (rect.top - topOffset) / scaleY,
          rect.right / scaleX,
          (rect.bottom - topOffset) / scaleY,
        );
        cubit.addManualBubble(
          BubbleBox(
            x: imgRect.left.round(),
            y: imgRect.top.round(),
            w: imgRect.width.round(),
            h: imgRect.height.round(),
            confidence: 1.0,
            shape: _shapeForTool(pts, scaleX, scaleY, topOffset),
          ),
        );
      }
    }
    setState(() => _freeformPoints = null);
  }

  /// Polygon (image px) for the finished drag, per tool.
  /// rect → null (box-only render, current behavior); ellipse → inscribed
  /// ellipse; freeform → the traced loop.
  List<List<int>>? _shapeForTool(
    List<Offset> screenPts,
    double scaleX,
    double scaleY,
    double topOffset,
  ) {
    switch (_tool) {
      case DrawShapeTool.rect:
        return null;
      case DrawShapeTool.ellipse:
        final rect = Rect.fromPoints(screenPts.first, screenPts.last);
        return _ellipsePolygon(rect)
            .map(
              (o) => [
                (o.dx / scaleX).round(),
                ((o.dy - topOffset) / scaleY).round(),
              ],
            )
            .toList();
      case DrawShapeTool.freeform:
        var pts = List<Offset>.from(screenPts);
        // Close the loop: drop terminal backtracking points (finger lift
        // jitter), then cap length — a full trace at 60hz can exceed a few
        // hundred points; beyond ~160 the polygon is dense enough to keep
        // the outline while staying cheap to render.
        if (pts.length > 2) {
          final first = pts.first;
          while (pts.length > 2 && (first - pts.last).distance < 6.0) {
            pts.removeLast();
          }
        }
        if (pts.length > 160) {
          pts = _simplify(pts, 160);
        }
        if (pts.length < 3) return null;
        return pts
            .map(
              (o) => [
                (o.dx / scaleX).round(),
                ((o.dy - topOffset) / scaleY).round(),
              ],
            )
            .toList();
    }
  }

  /// Uniform-cap point list (greedy stride sampling).
  List<Offset> _simplify(List<Offset> pts, int cap) {
    if (pts.length <= cap) return pts;
    final step = pts.length / cap;
    return [for (var i = 0; i < cap; i++) pts[(i * step).floor()]];
  }

  /// Inscribed ellipse of [rect], sampled with ~24 vertices — dense enough
  /// for `_smoothPath` (midpoint quadratics) to render a clean oval.
  static List<Offset> _ellipsePolygon(Rect rect) {
    const n = 24;
    final c = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    return [
      for (var i = 0; i < n; i++)
        Offset(
          c.dx + rx * math.cos(2 * math.pi * i / n),
          c.dy + ry * math.sin(2 * math.pi * i / n),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReaderTranslationCubit, ReaderTranslationState>(
      builder: (context, state) {
        final cubit = context.read<ReaderTranslationCubit>();
        final drawMode = cubit.drawMode;
        // Keep reference lines visible outside draw mode; z-order in the
        // reader keeps them below loading and chrome.
        final showBoxes = state is! ReaderTranslationTranslated;
        final colorScheme = Theme.of(context).colorScheme;

        final screenSize = MediaQuery.sizeOf(context);
        // Coordinate mapping: image px ↔ screen px — SAME fitWidth math as
        // the translated overlay (image fills width; rendered height derived
        // from aspect ratio; vertical letterbox when shorter than screen).
        // Use the CAPTURED page dimensions (not Translated state): detect
        // runs pre-translate, and the page is always captured on draw entry.
        final imgW = (cubit.pageWidth > 0
            ? cubit.pageWidth.toDouble()
            : screenSize.width);
        final imgH = (cubit.pageHeight > 0
            ? cubit.pageHeight.toDouble()
            : screenSize.height);
        final scaleX = screenSize.width / imgW;
        final renderedH = screenSize.width * (imgH / imgW);
        final scaleY = renderedH / imgH;
        final topOffset = renderedH < screenSize.height
            ? (screenSize.height - renderedH) / 2
            : 0.0;

        // ONNX-detected bubbles — polygon shape + kind, mirroring Python output.
        _onnxEntries = cubit.detectedBoxes.map((b) {
          final rect = Rect.fromLTWH(
            b.x * scaleX,
            b.y * scaleY + topOffset,
            b.w * scaleX,
            b.h * scaleY,
          );
          final poly = b.shape
              ?.map((p) => Offset(p[0] * scaleX, p[1] * scaleY + topOffset))
              .toList();
          return _BubbleDrawEntry(rect: rect, poly: poly, kind: b.kind);
        }).toList();

        return Stack(
          children: [
            // Drag layer — interactive only in draw mode. Reference bubbles
            // (ONNX blue / manual red) render while [showBoxes]; otherwise
            // the translated overlay stays clean (no stray boxes over text).
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !drawMode,
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(
                    cubit,
                    d.localPosition,
                    scaleX,
                    scaleY,
                    topOffset,
                  ),
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: (_) => _onPanEnd(cubit, scaleX, scaleY, topOffset),
                  child: CustomPaint(
                    painter: _DrawPainter(
                      tool: _tool,
                      draggingRect: showBoxes ? _draggingRect : null,
                      freeformPoints: showBoxes ? _freeformPoints : null,
                      manualColor: colorScheme.primary,
                      onnxEntries: showBoxes ? _onnxEntries : const [],
                      manualEntries: showBoxes
                          ? (_manualEntries = cubit.manualBubbles.map((b) {
                              final rect = Rect.fromLTWH(
                                b.x * scaleX,
                                b.y * scaleY + topOffset,
                                b.w * scaleX,
                                b.h * scaleY,
                              );
                              final poly = b.shape
                                  ?.map(
                                    (p) => Offset(
                                      p[0] * scaleX,
                                      p[1] * scaleY + topOffset,
                                    ),
                                  )
                                  .toList();
                              return _BubbleDrawEntry(rect: rect, poly: poly);
                            }).toList())
                          : const [],
                    ),
                  ),
                ),
              ),
            ),
            // Busy overlay — shown while the viewport snapshot / ONNX
            // detection runs (substantial work: toImage → PNG → JPG + YOLO).
            // Blocks input + visually tells the user work is happening instead
            // of a silent freeze.
            if (_detecting)
              AiBusyOverlay(label: AppLocalizations.of(context)!.aiDetecting),
            // Controls — draw mode only. A small pill that expands into the
            // action panel on tap, so it never blocks the reader chrome or
            // the page below.
            if (drawMode)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: _DrawModeControls(
                    tool: _tool,
                    onToolChanged: (t) => setState(() => _tool = t),
                    onDetect: () async {
                      // Always capture the CURRENT viewport first — the user may
                      // have scrolled since the last capture, so a stale bitmap
                      // (from another scroll position) would mis-detect bubbles.
                      setState(() => _detecting = true);
                      try {
                        await widget.onCaptureNeeded?.call();
                        if (!mounted) return;
                        await cubit.detectBubblesOnly();
                      } finally {
                        if (mounted) {
                          setState(() => _detecting = false);
                          _repaint();
                        }
                      }
                    },
                    onUndo: () {
                      cubit.undoLastManual();
                      _repaint();
                    },
                    onClear: () {
                      cubit.clearManualBubbles();
                      _repaint();
                    },
                    onDone: () => cubit.setDrawMode(false),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Expandable action pill for draw mode. Collapsed: a single round button.
/// Expanded: shape tools + Detect / Undo / Clear / Done actions.
class _DrawModeControls extends StatefulWidget {
  const _DrawModeControls({
    required this.tool,
    required this.onToolChanged,
    required this.onDetect,
    required this.onUndo,
    required this.onClear,
    required this.onDone,
  });

  final DrawShapeTool tool;
  final ValueChanged<DrawShapeTool> onToolChanged;
  final VoidCallback onDetect;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onDone;

  @override
  State<_DrawModeControls> createState() => _DrawModeControlsState();
}

class _DrawModeControlsState extends State<_DrawModeControls> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Shared pill visuals — matches the mini chrome toggle look.
    final pillDecoration = BoxDecoration(
      color: colorScheme.inverseSurface.withValues(alpha: 0.88),
      shape: BoxShape.circle,
      border: Border.all(
        color: colorScheme.onInverseSurface.withValues(alpha: 0.18),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? Material(
                  color: colorScheme.inverseSurface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(28),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final t in DrawShapeTool.values) ...[
                          _DrawToolButton(
                            tool: t,
                            selected: widget.tool == t,
                            onTap: () => widget.onToolChanged(t),
                          ),
                          const SizedBox(width: 2),
                        ],
                        const _DividerDot(),
                        _DrawAction(
                          icon: Icons.radar,
                          tooltip: l10n.aiDrawDetect,
                          onTap: widget.onDetect,
                        ),
                        _DrawAction(
                          icon: Icons.undo,
                          tooltip: l10n.aiDrawUndo,
                          onTap: widget.onUndo,
                        ),
                        _DrawAction(
                          icon: Icons.delete_sweep_outlined,
                          tooltip: l10n.aiDrawClear,
                          onTap: widget.onClear,
                        ),
                        _DrawAction(
                          icon: Icons.check,
                          tooltip: l10n.aiExitDrawMode,
                          onTap: widget.onDone,
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: Tooltip(
            message: _expanded ? l10n.aiCollapseDraw : l10n.aiExpandDraw,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _expanded ? 48 : 56,
                height: _expanded ? 48 : 56,
                decoration: pillDecoration,
                child: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.edit_outlined,
                  size: 24,
                  color: colorScheme.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawAction extends StatelessWidget {
  const _DrawAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: colorScheme.onInverseSurface),
        ),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  const _DrawPainter({
    this.tool = DrawShapeTool.rect,
    this.draggingRect,
    this.freeformPoints,
    this.onnxEntries = const [],
    this.manualEntries = const [],
    this.manualColor = const Color(0xFFFFFFFF),
  });

  final DrawShapeTool tool;
  final Rect? draggingRect;
  final List<Offset>? freeformPoints;
  final List<_BubbleDrawEntry> onnxEntries;
  final List<_BubbleDrawEntry> manualEntries;
  final Color manualColor;

  // Mirror Python seg_fixed.py LINE_COLOR: balloon=green, text=cyan.
  static const _balloonColor = Color(0xFF00E000);
  static const _textColor = Color(0xFF00C8C8);

  /// Smooth polygon outline via midpoint quadratic curves.
  static Path _smoothPath(List<Offset> pts) {
    final n = pts.length;
    final path = Path();
    final start = Offset(
      (pts[n - 1].dx + pts[0].dx) / 2,
      (pts[n - 1].dy + pts[0].dy) / 2,
    );
    path.moveTo(start.dx, start.dy);
    for (int i = 0; i < n; i++) {
      final ctrl = pts[i];
      final next = pts[(i + 1) % n];
      final mid = Offset((ctrl.dx + next.dx) / 2, (ctrl.dy + next.dy) / 2);
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in onnxEntries) {
      final color = e.kind == 'balloon' ? _balloonColor : _textColor;
      if (e.poly != null && e.poly!.length >= 3) {
        // Rect-like shapes (frames/narration boxes) keep sharp corners —
        // smoothing them would render square frames as ovals.
        final path = isRectLikePolygon(e.poly!)
            ? (Path()..addPolygon(e.poly!, true))
            : _smoothPath(e.poly!);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = color,
        );
      } else {
        // Defensive: polygon collapsed (unreachable post BubbleDetector box
        // fallback) — draw a thin solid rect so the bubble stays visible,
        // colored by class (not orange) so text boxes don't stand out.
        canvas.drawRect(
          e.rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color,
        );
      }
    }

    final manualPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = manualColor;
    for (final e in manualEntries) {
      // Shape-aware like ONNX entries: smooth non-rect polygons, keep sharp
      // corners for rect-like frames — same code path, so manual bubbles
      // render identical to detected ones after translation.
      final drawPath = e.poly != null && e.poly!.length >= 3
          ? (isRectLikePolygon(e.poly!)
                ? (Path()..addPolygon(e.poly!, true))
                : _smoothPath(e.poly!))
          : null;
      if (drawPath != null) {
        canvas.drawPath(drawPath, manualPaint);
      } else {
        canvas.drawRect(e.rect, manualPaint);
      }
    }

    // Live preview of the in-progress shape (image space, like manualEntries).
    final previewPath = _previewPath();
    if (previewPath != null) {
      canvas.drawPath(
        previewPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  /// In-progress shape path for the active tool:
  /// rect/ellipse → the drag rect (or its inscribed polygon); freeform → the
  /// open point path (closed with a straight segment to the start).
  Path? _previewPath() {
    final rect = draggingRect;
    if (rect == null) return null;
    switch (tool) {
      case DrawShapeTool.rect:
        return Path()..addRect(rect);
      case DrawShapeTool.ellipse:
        return Path()..addOval(rect);
      case DrawShapeTool.freeform:
        final pts = freeformPoints;
        if (pts == null || pts.length < 2) return null;
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        return path;
    }
  }

  @override
  bool shouldRepaint(_DrawPainter oldDelegate) =>
      oldDelegate.tool != tool ||
      oldDelegate.draggingRect != draggingRect ||
      !listEquals(oldDelegate.freeformPoints, freeformPoints) ||
      oldDelegate.manualColor != manualColor ||
      !listEquals(oldDelegate.onnxEntries, onnxEntries) ||
      !listEquals(oldDelegate.manualEntries, manualEntries);
}

/// Small dot separator between shape tools and actions.
class _DividerDot extends StatelessWidget {
  const _DividerDot();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: colorScheme.onInverseSurface.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Circular tool button; selected tool gets a filled accent + icon tint.
class _DrawToolButton extends StatefulWidget {
  const _DrawToolButton({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final DrawShapeTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DrawToolButton> createState() => _DrawToolButtonState();
}

class _DrawToolButtonState extends State<_DrawToolButton> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: widget.tool.tooltip(l10n),
      child: InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.selected ? colorScheme.primary : Colors.transparent,
          ),
          child: Icon(
            widget.tool.icon,
            size: 20,
            color: widget.selected
                ? colorScheme.onPrimary
                : colorScheme.onInverseSurface,
          ),
        ),
      ),
    );
  }
}
