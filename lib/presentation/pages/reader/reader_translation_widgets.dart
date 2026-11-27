import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/glossary.dart';
import 'package:nhasixapp/domain/repositories/ai_translation_repositories.dart';
import 'package:nhasixapp/domain/usecases/reader/save_glossary_entry_usecase.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_translation_cubit.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import '../../../core/utils/polygon_geometry.dart';

import 'package:kuron_native/kuron_native.dart';

import '../../../domain/entities/ai_translation.dart';

/// Toolbar button group for AI translation: ✨ translate, then overlay toggle.
class ReaderTranslationToolbar extends StatelessWidget {
  const ReaderTranslationToolbar({
    super.key,
    required this.readingMode,
    required this.onTranslate,
  });

  final ReadingMode readingMode;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    // Translate + draw stay enabled in continuous scroll. The cubit gates
    // translate on the fetched page's aspect ratio (webtoon); draw/detect
    // work on the visible page (captured on entry). Nothing is disabled in CS.
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<ReaderTranslationCubit, ReaderTranslationState>(
      builder: (context, state) {
        final cubit = context.read<ReaderTranslationCubit>();
        final active =
            state is ReaderTranslationTranslated && cubit.overlayVisible;
        final busy =
            state is ReaderTranslationDetecting ||
            state is ReaderTranslationBuildingMosaic ||
            state is ReaderTranslationTranslating ||
            state is ReaderTranslationTranslatingBubble;
        final shouldRefreshViewport =
            readingMode == ReadingMode.continuousScroll;
        final activeColor = Theme.of(context).colorScheme.primary;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: (active
                  ? l10n.aiHideTranslation
                  : busy
                  ? l10n.aiTranslating
                  : l10n.aiTranslatePage),
              onPressed: busy
                  ? null
                  : () {
                      if (state is ReaderTranslationTranslated &&
                          !shouldRefreshViewport) {
                        cubit.toggleOverlay();
                      } else {
                        onTranslate();
                      }
                    },
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      active ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                      color: active ? activeColor : null,
                    ),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
            // Reset translate result + reference bubbles
            if (state is ReaderTranslationTranslated ||
                cubit.detectedBoxes.isNotEmpty ||
                cubit.manualBubbles.isNotEmpty)
              IconButton(
                tooltip: l10n.aiClearTranslateBubbles,
                onPressed: cubit.resetPage,
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: Colors.redAccent,
                ),
                visualDensity: VisualDensity.compact,
              ),
            // Manual bubble drawing toggle (9.5)
            IconButton(
              tooltip: cubit.drawMode
                  ? l10n.aiExitDrawMode
                  : l10n.aiDrawBubbles,
              onPressed: () {
                if (cubit.drawMode) {
                  cubit.setDrawMode(false);
                } else {
                  cubit.setDrawMode(true);
                }
              },
              icon: Icon(
                Icons.draw_outlined,
                color: cubit.drawMode ? activeColor : null,
              ),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
          ],
        );
      },
    );
  }
}

/// Model switcher sheet (opened from the reader ⋮ menu): picks the active AI
/// provider from the already-configured list (vision-capable only). No
/// add/manage here — that lives in Settings → AI Translation. Takes effect
/// on next translate.
Future<void> showReaderModelSwitcherSheet(BuildContext context) async {
  final repository = getIt<AiProviderRepository>();
  final providers = await repository.getProviders();
  if (!context.mounted) return;
  // Outer context survives the sheet pop — used for SnackBar.
  final outerContext = context;
  final l10n = AppLocalizations.of(context)!;
  final vision = providers.where((p) => p.isVisionCapable).toList();
  if (vision.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.aiNeedVisionProvider)));
    return;
  }
  var defaultId = vision.first.id;
  for (final p in vision) {
    if (p.isDefault) defaultId = p.id;
  }
  // Tile contexts keyed by provider id, so the group onChanged can anchor
  // the rating burst on the tapped tile without per-tile onChanged.
  final tileContexts = <String, BuildContext>{};
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final sheetL10n = AppLocalizations.of(sheetContext)!;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                sheetL10n.aiSwitchModel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: RadioGroup<String>(
                groupValue: defaultId,
                onChanged: (id) async {
                  if (id == null) return;
                  final tileContext = tileContexts[id];
                  final rect = tileContext == null
                      ? null
                      : KuronFx.targetRectOf(tileContext);
                  if (tileContext != null && rect != null) {
                    KuronFx.triggerOn(
                      tileContext,
                      rect: rect,
                      kind: KuronFxKind.rating,
                    );
                  }
                  final selected = vision.firstWhere((p) => p.id == id);
                  await repository.setDefault(selected.id);
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                  if (outerContext.mounted) {
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.aiModelSwitched(selected.displayName),
                        ),
                      ),
                    );
                  }
                },
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: vision.length,
                  itemBuilder: (_, i) {
                    final p = vision[i];
                    return Builder(
                      builder: (tileContext) {
                        tileContexts[p.id] = tileContext;
                        return RadioListTile<String>(
                          value: p.id,
                          title: Text(p.displayName),
                          subtitle: Text(p.model),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Overlay layer: positions translated bubbles over the reader image.
///
/// The reader renders the page with `BoxFit.fitWidth`, so bubble rects in
/// ORIGINAL-image pixel space are mapped to screen space by scaling with
/// `screenW / imageW` (X) and `screenH / imageH` (Y). Vertical alignment:
/// image height = `screenW * imgH / imgW`, letterboxed/centered vertically
/// if the image is shorter than the viewport.
class ReaderTranslationOverlay extends StatelessWidget {
  const ReaderTranslationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return BlocBuilder<ReaderTranslationCubit, ReaderTranslationState>(
      builder: (context, state) {
        if (state is! ReaderTranslationTranslated) {
          // Show the same busy overlay while any heavy AI step runs, so the
          // user gets feedback identical to draw-mode Detect instead of a
          // silent page. refreshOnCropViewport reuses the cached snapshot, so
          // translation without movement runs fast, but the visual contract
          // (busy → spinner card) is consistent.
          if (state is ReaderTranslationDetecting ||
              state is ReaderTranslationBuildingMosaic ||
              state is ReaderTranslationTranslating ||
              state is ReaderTranslationTranslatingBubble) {
            return AiBusyOverlay(
              label: state is ReaderTranslationDetecting
                  ? AppLocalizations.of(context)!.aiDetecting
                  : AppLocalizations.of(context)!.aiTranslating,
            );
          }
          return const SizedBox.shrink();
        }
        final result = state.result;
        final imgW = state.imageWidth.toDouble();
        final imgH = state.imageHeight.toDouble();
        if (imgW <= 0 || imgH <= 0) return const SizedBox.shrink();

        // fitWidth scale: image fills screen width; height derived from AR.
        final scaleX = screenSize.width / imgW;
        final renderedH = screenSize.width * (imgH / imgW);
        final scaleY = renderedH / imgH;
        // Vertical letterbox offset (image centered when shorter than screen)
        final topOffset = renderedH < screenSize.height
            ? (screenSize.height - renderedH) / 2
            : 0.0;

        final cubit = context.read<ReaderTranslationCubit>();
        return Stack(
          children: [
            for (var i = 0; i < result.bubbles.length; i++)
              _positionedBubble(
                result.bubbles[i],
                scaleX,
                scaleY,
                topOffset,
                i,
                manualBubbles: cubit.manualBubbles,
                isFailed: state.failedBubbles.containsKey(i),
                onRetry: state.failedBubbles.containsKey(i)
                    ? () => cubit.retryBubble(i)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Maps a bubble to its screen rect, inflating tiny bubbles (below the 44px
/// touch target) outward from center so short text still fits and remains
/// tappable. Expansion keeps the bubble visually anchored to its position.
Widget _positionedBubble(
  BubbleTranslation bubble,
  double scaleX,
  double scaleY,
  double topOffset,
  int index, {
  List<BubbleBox> manualBubbles = const [],
  bool isFailed = false,
  VoidCallback? onRetry,
}) {
  const minDim = 44.0;
  var rect = Rect.fromLTWH(
    bubble.rect.left * scaleX,
    bubble.rect.top * scaleY + topOffset,
    bubble.rect.width * scaleX,
    bubble.rect.height * scaleY,
  );
  // Shape-following bubble: keep the box tight (no inflate) so the polygon
  // maps 1:1; only inflate the box-only fallback for the touch target.
  final shape = bubble.shape?.map((p) {
    // orig px → screen px, relative to the screen rect's top-left
    final sx = p[0] * scaleX - rect.left;
    final sy = p[1] * scaleY + topOffset - rect.top;
    return Offset(sx, sy);
  }).toList();
  if (shape == null) {
    if (rect.width < minDim || rect.height < minDim) {
      final inflate = (minDim - rect.shortestSide).clamp(0.0, 24.0);
      rect = rect.inflate(inflate);
    }
  }
  // The polygon's bounding rect reaches into corners that sit OUTSIDE the
  // oval curve. Fit text against the ~0.8× inscribed rect so wrapped lines
  // stay inside the visible bubble instead of overflowing past its outline.
  final effectiveBox = shape != null && shape.length >= 3
      ? _inscribedBox(shape)
      : null;

  // Find tail for manual bubbles at this index
  final tail = index < manualBubbles.length ? manualBubbles[index].tail : null;
  final tailPoints = tail
      ?.map((p) => Offset(p[0].toDouble(), p[1].toDouble()))
      .toList();

  return Positioned(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    child: ReaderTranslatedBubble(
      bubble: bubble,
      index: index,
      shapeLocal: shape,
      effectiveBox: effectiveBox,
      tailPoints: tailPoints,
      isFailed: isFailed,
      onRetry: onRetry,
    ),
  );
}

/// Smallest axis-aligned rect tightly around every polygon point, then shrunk
/// to its ~0.8× inscribed area (~10% per side). This is a pragmatic stand-in
/// for the exact ellipse inscribed rect: roomy enough to keep readable font
/// sizes while staying clear of the oval's corners — where text is most prone
/// to overflow.
Rect _inscribedBox(List<Offset> points) {
  var b = Rect.fromPoints(points.first, points.first);
  for (final p in points.skip(1)) {
    b = b.expandToInclude(Rect.fromPoints(p, p));
  }
  final shrinkW = b.width * 0.1;
  final shrinkH = b.height * 0.1;
  return Rect.fromLTRB(
    b.left + shrinkW,
    b.top + shrinkH,
    b.right - shrinkW,
    b.bottom - shrinkH,
  );
}

class ReaderTranslatedBubble extends StatelessWidget {
  const ReaderTranslatedBubble({
    super.key,
    required this.bubble,
    required this.index,
    this.shapeLocal,
    this.effectiveBox,
    this.tailPoints,
    this.isFailed = false,
    this.onRetry,
  });

  final BubbleTranslation bubble;
  final int index;

  /// Polygon in SCREEN coords relative to the bubble rect's top-left.
  /// Null → box-only fallback (rounded-rect).
  final List<Offset>? shapeLocal;

  /// Inscribed rect of [shapeLocal] (screen coords relative to the bubble
  /// rect's top-left) — the polygon bounding rect shrunk ~0.8× (`_inscribedBox`).
  /// Text is fit against this instead of the full `Positioned` bounds so
  /// wrapped lines stay inside the oval outline. Only honored when
  /// [shapeLocal] is a valid polygon.
  final Rect? effectiveBox;

  /// User-drawn tail polygon in screen coords relative to the bubble rect.
  final List<Offset>? tailPoints;

  /// Whether this bubble's translation failed (tap → retry).
  final bool isFailed;

  /// Callback when user taps a failed bubble to retry.
  final VoidCallback? onRetry;

  /// Font family: per-bubble fontFamily (from TranslationStyle map), else
  /// fallback to CJK detection (KosugiMaru for CJK, Komika for Latin).
  static final _cjk = RegExp(r'[぀-ゟ゠-ヿ一-鿿가-힯]');
  String get _fontFamily =>
      bubble.fontFamily ??
      (_cjk.hasMatch(bubble.translated) ? 'KosugiMaru' : 'Komika');

  @override
  Widget build(BuildContext context) {
    final shape = shapeLocal;
    final polygon = (shape != null && shape.length >= 3) ? shape : null;
    final hasShape = polygon != null;
    final bubbleBg = hasShape
        ? CustomPaint(
            painter: _BubbleShapePainter(polygon, tailPoints: tailPoints),
          )
        : (bubble.needsWhitePatch
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              : const SizedBox.shrink());
    return GestureDetector(
      onTap: isFailed && onRetry != null
          ? onRetry
          : () => _showEditSheet(context),
      onLongPress: () => _showSaveToGlossarySheet(context),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          bubbleBg,
          LayoutBuilder(
            builder: (context, constraints) {
              // Shape bubbles: fit against the polygon's inscribed rect (~0.8× of
              // the bounds) so text stays inside the oval curve. Box-only bubbles
              // use the full Positioned bounds.
              final box = hasShape && effectiveBox != null
                  ? Size(effectiveBox!.width, effectiveBox!.height)
                  : Size(constraints.maxWidth, constraints.maxHeight);
              return Padding(
                padding: hasShape
                    ? const EdgeInsets.all(1)
                    : const EdgeInsets.all(3),
                // Center the whole text block INSIDE the bubble, not just per-line.
                // Without this the Text fills its tight Stack bounds and is painted
                // from the top edge, stranding the (now smaller) fitted text at the
                // top with the rest of the oval/frame empty below.
                child: Center(
                  child: Text(
                    bubble.translated,
                    textAlign: TextAlign.center,
                    style: _fitText(
                      bubble.translated,
                      box,
                      _fontFamily,
                      hasShape: hasShape,
                    ),
                  ),
                ),
              );
            },
          ),
          if (isFailed)
            // Error indicator: red X icon top-right corner
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.error_outline, size: 16, color: Colors.red),
            ),
        ],
      ),
    );
  }

  /// Tap → edit translation bottom sheet (spec 9.2).
  void _showEditSheet(BuildContext context) {
    final controller = TextEditingController(text: bubble.translated);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(sheetContext)!.aiEditTranslation,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(sheetContext)!.aiTranslation,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                context.read<ReaderTranslationCubit>().editBubbleTranslation(
                  index,
                  controller.text.trim(),
                );
                Navigator.pop(sheetContext);
              },
              child: Text(AppLocalizations.of(sheetContext)!.aiSave),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press → "Save to Glossary" action sheet (spec 7.1).
  void _showSaveToGlossarySheet(BuildContext context) {
    final state = context.read<ReaderTranslationCubit>().state;
    final contentId = state is ReaderTranslationTranslated
        ? state.contentId
        : '';
    final pageIndex = state is ReaderTranslationTranslated
        ? state.pageIndex
        : 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(bubble.translated),
              subtitle: Text(
                bubble.original.isEmpty
                    ? AppLocalizations.of(sheetContext)!.aiSaveToGlossaryHint
                    : bubble.original,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(AppLocalizations.of(sheetContext)!.aiSaveToGlossary),
              onTap: () async {
                getIt<Logger>().d(
                  'Glossary: saving "${bubble.translated}" from page $pageIndex',
                );
                try {
                  await getIt<SaveGlossaryEntryUsecase>().call(
                    GlossaryEntry(
                      id: 'gl_${DateTime.now().millisecondsSinceEpoch}_${bubble.rect.hashCode}',
                      sourceText: bubble.original,
                      translatedText: bubble.translated,
                      reading: bubble.reading,
                      contentId: contentId,
                      pageIndex: pageIndex,
                      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    ),
                  );
                  getIt<Logger>().i('Glossary saved OK');
                } catch (e) {
                  getIt<Logger>().e('Glossary save FAILED: $e');
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.aiSavedToGlossary,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Font-fit: largest size (descending) whose wrapped text fits the bubble.
/// Mirrors cypy `tulis_teks_di_balon` — score `size*10 + fillRatio`; pick
/// first size that fits (descending order makes it the max).
///
/// [hasShape] — for shape-following bubbles, [box] is the polygon's inscribed
/// rect (see [_inscribedBox]) instead of the full bounding rect, so the
/// fitted text stays inside the curved outline.
TextStyle _fitText(
  String text,
  Size box,
  String fontFamily, {
  bool hasShape = false,
}) {
  // Base range [6,32], scaled down proportionally for small bubbles so the
  // text shrinks instead of overflowing. Hard cap: a giant bubble must not
  // balloon the font — manga text stays modest even on page-wide balloons.
  // Bounded ≤ ~30 layout iterations.
  final shortSide = box.shortestSide < 40.0 ? box.shortestSide / 40.0 : 1.0;
  final maxSize = (32.0 * shortSide).clamp(6.0, 32.0);
  final minSize = (7.0 * shortSide).clamp(4.0, 7.0);
  final maxW = box.width * (hasShape ? 0.98 : 0.8);
  // The inscribed rect already provides the ~0.8× safety margin; with ClipPath
  // as the safety net we can fill almost the entire inscribed box instead of
  // shrinking twice (inscribed × font-fit). Box-only keeps a 10 % buffer.
  final maxH = box.height * (hasShape ? 0.98 : 0.9);

  for (var size = maxSize; size >= minSize; size -= 1) {
    final style = _textStyle(size, fontFamily);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxW);
    if (painter.height <= maxH && painter.width <= maxW) return style;
  }
  return _textStyle(minSize, fontFamily);
}

/// Draws the bubble polygon (feathered white fill) beneath translated text,
/// following the detected bubble shape instead of a rounded rect. The edge
/// has NO border line — a blurred white halo fades the bubble into the page.
class _BubbleShapePainter extends CustomPainter {
  _BubbleShapePainter(this.points, {this.tailPoints});

  final List<Offset> points;
  final List<Offset>? tailPoints;

  /// Smooth polygon via midpoint-quadratic-bezier: avoids jagged straight
  /// segments from approxPolyDP, producing the clean oval look of real bubbles.
  static Path _smoothPath(List<Offset> pts) {
    final n = pts.length;
    final path = Path();
    // Start at midpoint of last→first edge so every vertex is a control point.
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

  /// Bubble polygon path: smooth bezier ONLY for oval/jagged bubbles.
  /// Rect-like shapes (frames, narration boxes, square balloons) keep their
  /// straight edges and sharp corners — smoothing them turns them into ovals.
  static Path _shapePath(List<Offset> pts) => isRectLikePolygon(pts)
      ? (Path()..addPolygon(pts, true))
      : _smoothPath(pts);

  @override
  void paint(Canvas canvas, Size size) {
    final path = points.length >= 3
        ? _shapePath(points)
        : (Path()..addPolygon(points, true));
    // Merge tail (spec 7.2): append tail triangle to bubble shape
    final merged = tailPoints != null && tailPoints!.length >= 3
        ? _mergeTail(path, tailPoints!)
        : path;
    // Soft halo: blurred white border zone — replaces the old hard 1.5px
    // black stroke. Renders the edge as a gentle fade into the page.
    canvas.drawPath(
      merged,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Solid core: the same shape shrunk ~20% toward its centroid (per-vertex
    // lerp), so the feather band only covers the outer ring — before the text
    // area — leaving the interior fully opaque white for text contrast.
    canvas.drawPath(
      _deflate(merged, 0.8),
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  /// Merge tail polygon into bubble path (spec 7.2).
  static Path _mergeTail(Path bubble, List<Offset> tail) {
    final result = Path()..addPath(bubble, Offset.zero);
    // Find nearest point on bubble edge to tail start, connect
    final tailStart = tail.first;
    result.addPolygon([...tail, tailStart], true);
    return result;
  }

  /// Shrinks [path] toward its centroid by [scale] (1.0 = unchanged, 0.8 =
  /// 20% closer to center). Lerp per control point — quadratic curves keep
  /// their shape.
  static Path _deflate(Path path, double scale) {
    final bounds = path.getBounds();
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;
    final dst = Path();
    for (final metric in path.computeMetrics()) {
      final pts = <Offset>[];
      const step = 2.0;
      for (var d = 0.0; d <= metric.length; d += step) {
        pts.add(metric.getTangentForOffset(d)!.position);
      }
      if (pts.isEmpty) continue;
      dst.addPolygon([
        for (final p in pts)
          Offset(cx + (p.dx - cx) * scale, cy + (p.dy - cy) * scale),
      ], true);
    }
    return dst;
  }

  @override
  bool shouldRepaint(covariant _BubbleShapePainter old) => old.points != points;
}

/// Hitam dengan outline putih tebal (stroke manga) — 8 arah shadow offset
/// membentuk outline tajam penuh mengelilingi glyph (bukan halo blur), jadi
/// teks tetap terbaca di atas gambar rumit tanpa patch putih.
TextStyle _textStyle(double size, String fontFamily) {
  final stroke = size * 0.16;
  return TextStyle(
    fontSize: size,
    color: Colors.black,
    fontWeight: FontWeight.w600,
    fontFamily: fontFamily,
    height: 1.25,
    shadows: [
      for (final o in const [
        Offset(-1, -1),
        Offset(0, -1),
        Offset(1, -1),
        Offset(-1, 0),
        Offset(1, 0),
        Offset(-1, 1),
        Offset(0, 1),
        Offset(1, 1),
      ])
        Shadow(color: Colors.white, offset: o * stroke, blurRadius: 0),
    ],
  );
}

/// Full-screen busy overlay with an animated manga-style caption. Blocks
/// input while a heavy AI pipeline step runs (viewport snapshot, ONNX
/// detection, mosaic build, translate). Reused by draw-mode Detect and the
/// translate path so the "is it working?" feedback is consistent everywhere.
class AiBusyOverlay extends StatelessWidget {
  const AiBusyOverlay({super.key, required this.label});

  /// Text shown next to the spinner — call site picks the stage-specific
  /// localised label (draw-mode detect vs translate), never hardcoded.
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 14),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
