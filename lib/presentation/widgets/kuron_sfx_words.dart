import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/core/constants/colors_const.dart';

/// Indonesian SFX word set for Item #79 (Lane A, P3).
///
/// Shape source: `assets/sfx/sfx_paths.json` — six `[w, h, path]` entries in
/// the upstream `WORDS` format (`M`/`L`/`C`/`Z` contours), custom hand-inked
/// vector artwork (Designer §9, FINAL). Runtime needs no font file.
///
/// Bake contract (Designer hand-off, gallery `bake()` 1:1):
/// pad 24, edge half-width `e = 0.035 * w`, `lineWidth = 2e = 36.4` nominal,
/// round join/cap; stroke edge → fill edge → fill `fill` (or white base +
/// 22×44 ink-dot tile clipped to the glyph for dotted). One raster per
/// `(word, style, fill, edge)`; the frame loop only does `drawImage`.

/// Fill style of a baked word.
enum KuronSfxStyle { solid, hollow, dotted }

/// One entry of the canonical Indonesian word set.
///
/// Dimensions are nominal units (all words 520 wide); [style] is the
/// Designer-assigned style from the JP→ID mapping table.
class KuronSfxWord {
  const KuronSfxWord({
    required this.name,
    required this.height,
    required this.style,
  });

  /// Canonical word text (LOCKED): JEDER! MANTAP! KLIK! SAH! CAIR! BYAR!.
  final String name;

  /// Nominal glyph-box height; width is always 520.
  final double height;

  final KuronSfxStyle style;

  static const double nominalWidth = 520;

  static const List<KuronSfxWord> all = [
    KuronSfxWord(name: 'JEDER!', height: 296, style: KuronSfxStyle.solid),
    KuronSfxWord(name: 'MANTAP!', height: 288, style: KuronSfxStyle.solid),
    KuronSfxWord(name: 'KLIK!', height: 294, style: KuronSfxStyle.hollow),
    KuronSfxWord(name: 'SAH!', height: 296, style: KuronSfxStyle.hollow),
    KuronSfxWord(name: 'CAIR!', height: 266, style: KuronSfxStyle.solid),
    KuronSfxWord(name: 'BYAR!', height: 287, style: KuronSfxStyle.dotted),
  ];

  static KuronSfxWord? byName(String name) =>
      all.where((w) => w.name == name).firstOrNull;
}

/// How one word is staged on a control: glyph width as a multiple of the
/// control width (~1.5–2×), rotation in radians, and visible life in seconds.
class KuronSfxSpec {
  const KuronSfxSpec({
    required this.word,
    required this.sizeFactor,
    required this.rot,
    required this.life,
    this.accent = false,
  });

  final KuronSfxWord word;
  final double sizeFactor;
  final double rot;
  final double life;

  /// Accent word (CAIR!): coral/violet fill instead of ink/paper.
  final bool accent;
}

/// Resolved bake colors for one `(style, theme)` pair.
class KuronSfxPalette {
  const KuronSfxPalette({
    required this.fill,
    required this.edge,
    required this.base,
  });

  /// Main fill (solid/hollow) or dot color (dotted).
  final Color fill;

  /// Keyline color.
  final Color edge;

  /// Base under the dots (dotted only); equals [fill] otherwise.
  final Color base;

  /// Gallery `P`/VARS mapped to Kuron tokens (P0).
  ///
  /// Light follows the gallery (ink on white); dark swaps solid to
  /// paper `#EFE6DC` fill + ink `#1D1A4A` edge (paper + coral edge for the
  /// accent word); dotted stays ink-on-paper on both. Monochrome (note
  /// themes) collapses to a black/white pair. Hollow keeps a white fill
  /// with an ink edge on both brightnesses — it reads on light and dark.
  static KuronSfxPalette resolve(
    KuronSfxStyle style, {
    required bool dark,
    required bool monochrome,
    bool accent = false,
  }) {
    const white = Color(0xFFFFFFFF);
    if (monochrome) {
      const fill = Color(0xFFFFFFFF);
      const edge = Color(0xFF000000);
      if (dark) {
        return const KuronSfxPalette(fill: edge, edge: fill, base: edge);
      }
      return const KuronSfxPalette(fill: fill, edge: edge, base: fill);
    }
    switch (style) {
      case KuronSfxStyle.solid:
        if (accent) {
          return dark
              ? const KuronSfxPalette(
                  fill: AppColors.sfxPaper,
                  edge: AppColors.brandCoral,
                  base: AppColors.sfxPaper,
                )
              : const KuronSfxPalette(
                  fill: AppColors.sfxLine,
                  edge: white,
                  base: AppColors.sfxLine,
                );
        }
        return dark
            ? const KuronSfxPalette(
                fill: AppColors.sfxPaper,
                edge: AppColors.sfxInk,
                base: AppColors.sfxPaper,
              )
            : const KuronSfxPalette(
                fill: AppColors.sfxInk,
                edge: white,
                base: AppColors.sfxInk,
              );
      case KuronSfxStyle.hollow:
        return const KuronSfxPalette(
          fill: white,
          edge: AppColors.sfxInk,
          base: white,
        );
      case KuronSfxStyle.dotted:
        return const KuronSfxPalette(
          fill: AppColors.sfxInk,
          edge: AppColors.sfxInk,
          base: white,
        );
    }
  }
}

/// Landing motion (gallery §1.4, exact): `Spring(0.2, k=520, d=17)`.
/// First overshoot ~28% at ~148 ms, ~2% settle at ~471 ms.
abstract final class KuronSfxMotion {
  static final SpringSimulation spring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 520, damping: 17),
    0.2,
    1,
    0,
  );

  /// Jitter amplitude in logical px at 31/27 rad·s⁻¹.
  static const double jitter = 0.8;

  /// Roll amplitude in radians at 6 rad·s⁻¹.
  static const double roll = 0.03;

  /// Word shrinks (cubically, never fades) over the last 14% of its life.
  static const double fadeStart = 0.86;
}

/// Parses the `M`/`L`/`C`/`Z` path subset used by `sfx_paths.json`.
/// Throws [FormatException] on anything else — the asset is fixed data, so
/// an unknown command is a corrupt asset, not a fallback case.
ui.Path parseSfxPathData(String data) {
  final path = ui.Path();
  final token = RegExp(r'[MLCZmlcz]|-?\d*\.?\d+(?:e-?\d+)?');
  final tokens = token.allMatches(data).map((m) => m.group(0)!).toList();
  var i = 0;
  double readNum() {
    if (i >= tokens.length) {
      throw const FormatException('truncated SFX path data');
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    final cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(readNum(), readNum());
      case 'L':
        path.lineTo(readNum(), readNum());
      case 'C':
        path.cubicTo(
          readNum(),
          readNum(),
          readNum(),
          readNum(),
          readNum(),
          readNum(),
        );
      case 'Z':
        path.close();
      default:
        throw FormatException('unsupported SFX path command: $cmd');
    }
  }
  return path;
}

/// Bake cache: one [ui.Image] per `(word, style, fill, edge)`.
///
/// Bakes at a fixed 2× nominal scale so every control size shares the same
/// raster; the frame loop scales via `drawImageRect`. Call [evict] or
/// [dispose] to release the images — the owner (the fx controller) must do
/// this in its own `dispose` (anti-leak).
class KuronSfxBakeCache {
  final Map<String, ui.Image> _cache = {};
  final Map<String, Future<ui.Image?>> _inflight = {};
  bool _disposed = false;

  int get size => _cache.length;

  bool contains({
    required String word,
    required KuronSfxPalette palette,
    required KuronSfxStyle style,
  }) => _cache.containsKey(_key(word, style, palette));

  static String _key(
    String word,
    KuronSfxStyle style,
    KuronSfxPalette palette,
  ) =>
      '$word|${style.name}|${palette.fill.toARGB32()}|'
      '${palette.edge.toARGB32()}|${palette.base.toARGB32()}';

  /// Loads `[w, h, path]` entries from the bundled asset (memoized).
  static Map<String, List<dynamic>>? _wordsJson;

  static Future<Map<String, List<dynamic>>> loadWords() async {
    final cached = _wordsJson;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/sfx/sfx_paths.json');
    final decoded = (jsonDecode(raw) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as List).toList()),
    );
    _wordsJson = decoded;
    return decoded;
  }

  /// Returns the baked image, baking once on first use. Concurrent callers
  /// share the in-flight bake; failures resolve to null, never throw.
  Future<ui.Image?> bake({
    required String word,
    required KuronSfxStyle style,
    required KuronSfxPalette palette,
  }) {
    if (_disposed) return Future.value(null);
    final key = _key(word, style, palette);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _bake(word, style, palette).then((img) {
      _inflight.remove(key);
      // A bake may land after the owner disposed us: never re-populate the
      // cache with an image nobody will release.
      if (_disposed) {
        img?.dispose();
      } else if (img != null) {
        _cache[key] = img;
      }
      return img;
    });
    _inflight[key] = future;
    return future;
  }

  // Fixed bake scale: one raster shared by all control sizes.
  static const double _bakeScale = 2;

  static Future<ui.Image?> _bake(
    String word,
    KuronSfxStyle style,
    KuronSfxPalette palette,
  ) async {
    try {
      final words = await loadWords();
      final entry = words[word];
      if (entry == null || entry.length < 3) return null;
      final h = (entry[1] as num).toDouble();
      final path = parseSfxPathData(entry[2] as String);

      const pad = 24.0;
      const lineWidth = 36.4; // 2 * 0.035 * 520, gallery bake constant
      const tile = 22.0;
      const tileH = 44.0;
      const dotR = 5.2;
      const nominalW = KuronSfxWord.nominalWidth;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(_bakeScale, _bakeScale);
      canvas.translate(pad, pad);

      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = palette.edge;
      canvas.drawPath(path, edgePaint);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = palette.edge,
      );
      if (style == KuronSfxStyle.dotted) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = palette.base,
        );
        canvas.save();
        canvas.clipPath(path);
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = palette.fill;
        // Bounded grid over the nominal box: 24 cols × ~8 rows.
        var row = 0;
        for (var y = 0.0; y < nominalW * 0.6 + tileH; y += tileH, row++) {
          final xOff = (row.isOdd ? tile / 2 : 0.0) - tile;
          for (var x = xOff; x < nominalW + tile; x += tile) {
            canvas.drawCircle(Offset(x, y), dotR, dotPaint);
          }
        }
        canvas.restore();
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = palette.fill,
        );
      }
      final img = await recorder.endRecording().toImage(
        ((nominalW + pad * 2) * _bakeScale).round(),
        ((h + pad * 2) * _bakeScale).round(),
      );
      return img;
    } catch (_) {
      return null;
    }
  }

  /// Releases one entry ([word] key as in [bake]) or everything.
  void evict([String? key]) {
    if (key == null) {
      for (final img in _cache.values) {
        img.dispose();
      }
      _cache.clear();
      return;
    }
    final img = _cache.remove(key);
    img?.dispose();
  }

  void dispose() {
    _disposed = true;
    evict();
  }
}
