import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:image/image.dart' as img;

import '../../../core/di/service_locator.dart';
import '../../../core/services/memory_budget_coordinator.dart';
import '../../../core/utils/webtoon_detector.dart';
import '../../../data/repositories/ai/ai_provider_factory.dart';
import '../../../data/repositories/ai/fallback_image_handler.dart';
import '../../../data/repositories/ai/mosaic_builder.dart';
import '../../../domain/entities/ai_translation.dart';
import '../../../domain/entities/glossary.dart';
import '../../../domain/entities/reader_settings_entity.dart';
import '../../../domain/repositories/ai_translation_repositories.dart';
import '../base/base_cubit.dart';

part 'reader_translation_state.dart';

/// Executes a CPU-bound computation off the UI isolate (mosaic crop/encode,
/// full-page compress, webtoon chunking). Production default: [Isolate.run].
/// Tests inject a synchronous runner because fake-async `testWidgets` cannot
/// await real isolate replies (they are delivered via real ports, not the
/// fake event queue).
typedef HeavyRunner = Future<T> Function<T>(FutureOr<T> Function() computation);

/// Orchestrates the AI translation pipeline for the active reader page:
/// webtoon detection → ONNX bubble detection → mosaic/fallback → provider →
/// cache → translated state.
///
/// Guard: disabled in `ReadingMode.continuousScroll`.
class ReaderTranslationCubit extends BaseCubit<ReaderTranslationState> {
  ReaderTranslationCubit({
    required AiProviderRepository providerRepository,
    required AiProviderFactory providerFactory,
    required AiPreferencesRepository preferencesRepository,
    required TranslationCacheRepository cacheRepository,
    required MosaicBuilder mosaicBuilder,
    required FallbackImageHandler fallbackHandler,
    HeavyRunner? heavyRunner,
    GlossaryRepository? glossaryRepository,
    required super.logger,
  })  : _providerRepository = providerRepository,
        _providerFactory = providerFactory,
        _preferencesRepository = preferencesRepository,
        _cacheRepository = cacheRepository,
        _mosaicBuilder = mosaicBuilder,
        _fallbackHandler = fallbackHandler,
        _heavyRunner = heavyRunner ?? Isolate.run,
        _glossaryRepository = glossaryRepository,
        super(initialState: const ReaderTranslationIdle());

  final AiProviderRepository _providerRepository;
  final AiProviderFactory _providerFactory;
  final AiPreferencesRepository _preferencesRepository;
  final TranslationCacheRepository _cacheRepository;
  final MosaicBuilder _mosaicBuilder;
  final FallbackImageHandler _fallbackHandler;
  final HeavyRunner _heavyRunner;

  /// Optional glossary source for prompt enrichment. Null in production DI
  /// falls back to `getIt<GlossaryRepository>` (best-effort: unregistered in
  /// tests → no glossary block, prompt unchanged).
  final GlossaryRepository? _glossaryRepository;

  PageTranslation? _currentResult;
  bool _overlayVisible = false;
  final List<BubbleBox> _manualBubbles = [];
  final Map<int, String> _failedBubbles = {};

  /// ONNX-detected bubbles from the last detection (blue reference in
  /// draw mode). Set by [detectBubblesOnly] and after each translate.
  List<BubbleBox> _detectedBoxes = [];

  /// Same content as [_detectedBoxes] — kept as a separate field so future
  /// translate-specific post-processing (e.g. merging balloons, dropping SFX)
  /// can diverge from draw-mode without refactoring call-sites.
  List<BubbleBox> _translationDetectedBoxes = [];

  // Current page context (set via capturePage) for detect-only runs.
  Uint8List? _pageBytes;
  int _pageWidth = 0;
  int _pageHeight = 0;
  String _capturedPageSignature = '';
  final Set<String> _userEditedKeys = {};
  bool _skipSfx = true;
  bool _drawMode = false;
  bool _rtlReading = false; // manga: right-to-left
  TranslationStyle? _currentStyle;

  // T2 prefetch: detection run in the background after the page settles, so
  // the Translate tap skips the 2.6s ONNX wait. Key is the capture signature
  // (same bytes → same boxes); reused only when translatePage runs on the
  // exact captured image. A different signature (new page, CS crop scrolled
  // away) invalidates stale results — the translate path re-detects.
  List<BubbleBox>? _prefetchedBoxes;
  String _prefetchKey = '';
  bool _prefetchRunning = false;

  /// Rough captured-image size in bytes (kept for the low-RAM prefetch gate).
  int? _imageBytesApprox;

  /// True while the prefetch pipeline is busy (translate, manual editing,
  /// draw mode) or under memory pressure — the states where a background
  /// detection would contend with the UI.
  bool _prefetchBlocked() {
    if (_prefetchRunning || _drawMode) return true;
    if (state is ReaderTranslationDetecting ||
        state is ReaderTranslationBuildingMosaic ||
        state is ReaderTranslationTranslating ||
        state is ReaderTranslationTranslatingBubble) {
      return true;
    }
    try {
      final heap = MemoryBudgetCoordinator().appHeapEstimateMB;
      if (heap >= 512) return false;
      // Low-RAM device: only prefetch when the reader's decoded-image budget
      // is comfortably free; skip under pressure rather than risk OOM.
      return _imageBytesApprox != null &&
          _imageBytesApprox! >=
              MemoryBudgetCoordinator().readerDecodedBudgetBytes ~/ 2;
    } catch (_) {
      return false;
    }
  }

  // Image/page context of the current translation (for coordinate scaling).
  int _currentImageWidth = 0;
  int _currentImageHeight = 0;
  int _currentPageIndex = -1;
  String _currentContentId = '';
  String _currentImageUrl = '';

  ReaderTranslationTranslated _translatedState() => ReaderTranslationTranslated(
        result: _currentResult!,
        imageWidth: _currentImageWidth,
        imageHeight: _currentImageHeight,
        pageIndex: _currentPageIndex,
        contentId: _currentContentId,
        imageUrl: _currentImageUrl,
        failedBubbles: Map.unmodifiable(_failedBubbles),
        uiVersion: _uiVersion,
      );

  bool get drawMode => _drawMode;

  /// Human-readable reading direction for AI prompts (T4.2): manga/RTL →
  /// right-to-left, manhwa/webtoon/ltr → left-to-right. Matches the bubble
  /// sort in [_translationBoxes] so the prompt order mirrors chip numbering.
  String get readingDirectionLabel =>
      _rtlReading ? 'right-to-left' : 'left-to-right';

  /// Notified whenever [drawMode] flips. Lets the reader chrome auto-hide
  /// while drawing.
  VoidCallback? onDrawModeChanged;

  void setDrawMode(bool value) {
    _setDrawMode(value);
    _bumpUi();
  }

  void setReadingDirection(ReadingMode mode) {
    _rtlReading = mode == ReadingMode.singlePage;
  }

  void _setDrawMode(bool value) {
    if (_drawMode == value) return;
    _drawMode = value;
    onDrawModeChanged?.call();
  }

  PageTranslation? get currentResult => _currentResult;
  bool get overlayVisible => _overlayVisible;
  List<BubbleBox> get manualBubbles => List.unmodifiable(_manualBubbles);
  List<BubbleBox> get detectedBoxes => List.unmodifiable(_detectedBoxes);
  bool get skipSfx => _skipSfx; // default on; toggle from toolbar

  /// Captured page dimensions — the coordinate space detected bubbles live
  /// in. Used by draw mode to map image px → screen px (fitWidth), even
  /// before any translate happened.
  int get pageWidth => _pageWidth;
  int get pageHeight => _pageHeight;
  bool get hasPage => _pageBytes != null && _pageWidth > 0 && _pageHeight > 0;

  /// Cache the active page image so draw-mode "Detect" can run without a
  /// full translate. Call from the reader on the current page.
  void capturePage({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) {
    final newSignature =
        _buildCaptureSignature(imageBytes, imageWidth, imageHeight);
    final captureChanged = _capturedPageSignature != newSignature;

    _pageBytes = imageBytes;
    _pageWidth = imageWidth;
    _pageHeight = imageHeight;
    _capturedPageSignature = newSignature;
    _imageBytesApprox = imageBytes.length;

    // Continuous-scroll viewport crops reuse the same page index, so a new
    // capture must invalidate old box coordinates from previous captures.
    // Keeping stale boxes causes severe overlay drift on the new viewport.
    // NOTE: _manualBubbles is deliberately NOT cleared here — manual bubbles
    // are user corrections drawn on THIS viewport; translate re-captures the
    // same viewport (bytes may differ in encoding/signature) and wiping them
    // would silently drop every manual bubble. Clear via clearManualBubbles.
    if (captureChanged) {
      // Detected boxes survive too: re-capture of the same logical page
      // (translate re-fetches/encodes, bytes differ) must not discard a
      // draw-mode 🛰 detection — re-detecting on translate defeats the
      // purpose of the user pressing Detect first. resetPage() clears both
      // on actual page navigation.
      // _detectedBoxes.clear();
      // _translationDetectedBoxes.clear();
      // Prefetched boxes were computed for the OLD image — discard (spec 2.4).
      _prefetchedBoxes = null;
      _prefetchKey = '';
      logInfo(
          'capturePage: new capture ${imageWidth}x$imageHeight bytes=${imageBytes.length} -> clear stale boxes');
      if (_drawMode) {
        _bumpUi();
      }
    }
  }

  String _buildCaptureSignature(
      Uint8List bytes, int imageWidth, int imageHeight) {
    final headLen = bytes.length < 24 ? bytes.length : 24;
    final tailLen = bytes.length < 24 ? 0 : 24;
    final head = bytes.sublist(0, headLen);
    final tail =
        tailLen == 0 ? const <int>[] : bytes.sublist(bytes.length - tailLen);
    return '$imageWidth:$imageHeight:${bytes.length}:${head.join(',')}:${tail.join(',')}';
  }

  /// ONNX-only detection for draw mode — renders blue reference bubbles
  /// without calling any AI provider.
  Future<List<BubbleBox>> detectBubblesOnly() async {
    final bytes = _pageBytes;
    if (bytes == null || _pageWidth <= 0 || _pageHeight <= 0) {
      logWarning(
          'detectBubblesOnly: page belum di-capture (bytes=${bytes != null}, ${_pageWidth}x$_pageHeight)');
      return const [];
    }
    emit(const ReaderTranslationDetecting());
    final raw = await _detect(bytes, _pageWidth, _pageHeight);
    logInfo(
        'detectBubblesOnly: raw ${raw.length} → post ${postProcessBoxes(raw).length}');
    final boxes = postProcessBoxes(raw);
    _detectedBoxes = boxes;
    _translationDetectedBoxes = boxes;
    if (state is ReaderTranslationDetecting) {
      _bumpUi();
    }
    logInfo('detectBubblesOnly: ${boxes.length} detections');
    return boxes;
  }

  /// T2 prefetch: background detection for the CURRENTLY CAPTURED page, run
  /// after the reader settles (idle timer in the reader widget). Result is
  /// cached against the capture signature and reused by [translatePage] when
  /// the same image is still active — the Translate tap then skips the ONNX
  /// wait entirely.
  ///
  /// Skipped (silently) when the pipeline is busy, draw mode is active, or the
  /// device is under memory pressure (spec 2.3). Never emits — this is a
  /// fire-and-forget warm-up, not user-facing state.
  Future<void> prefetchDetection() async {
    if (_prefetchBlocked()) return;
    final bytes = _pageBytes;
    if (bytes == null || _pageWidth <= 0 || _pageHeight <= 0) {
      logInfo('prefetchDetection: no captured page — skip');
      return;
    }
    final key = _capturedPageSignature;
    if (key.isEmpty || key == _prefetchKey && _prefetchedBoxes != null) {
      logInfo('prefetchDetection: cache hit (sig same) — skip');
      return;
    }
    if (_detectedBoxes.isNotEmpty) {
      // Draw mode / earlier detection already ran on this capture — nothing
      // to warm up; reuse the existing result for future translates.
      logInfo('prefetchDetection: existing detection — cache it');
      _prefetchedBoxes = _detectedBoxes;
      _prefetchKey = key;
      return;
    }
    _prefetchRunning = true;
    try {
      logInfo('prefetchDetection: running (${_pageWidth}x$_pageHeight)...');
      final raw = await _detect(bytes, _pageWidth, _pageHeight);
      final boxes = postProcessBoxes(raw);
      // Cache only non-empty results. An empty prefetch must NOT shadow the
      // translate path: reusing it would skip the re-detect and fall straight
      // into full-image upload. Stale key is dropped so translate re-detects.
      if (boxes.isNotEmpty) {
        _prefetchedBoxes = boxes;
        _prefetchKey = key;
        logInfo('prefetchDetection: done — ${boxes.length} boxes cached');
      } else {
        _prefetchedBoxes = null;
        _prefetchKey = '';
        logWarning(
            'prefetchDetection: empty result — nothing cached, translate will re-detect');
      }
    } catch (e) {
      logWarning('prefetchDetection failed: $e');
      // Also drop a stale cache on failure — same re-detect guarantee.
      _prefetchedBoxes = null;
      _prefetchKey = '';
    } finally {
      _prefetchRunning = false;
    }
  }

  Future<void> setSkipSfx(bool value) async {
    _skipSfx = value;
    await _preferencesRepository.setSkipSfx(value);
    _bumpUi();
  }

  /// Load persisted skipSfx (e.g. toolbar init).
  Future<void> initPreferences() async {
    _skipSfx = await _preferencesRepository.getSkipSfx();
    _bumpUi();
  }

  int _uiVersion = 0;

  /// Re-emits with a bumped uiVersion so Equatable-based builders rebuild
  /// (identical states are otherwise skipped by the bloc).
  void _bumpUi() {
    _uiVersion++;
    if (state is ReaderTranslationTranslated) {
      emit((state as ReaderTranslationTranslated)
          .copyWithUi(uiVersion: _uiVersion));
    } else {
      emit(ReaderTranslationIdle(uiVersion: _uiVersion));
    }
  }

  /// User-edited translation override (spec 9.2): stored in cache with
  /// `isUserEdited: true`, AI never overwrites it.
  void editBubbleTranslation(int index, String newText) {
    final result = _currentResult;
    if (result == null || index < 0 || index >= result.bubbles.length) return;
    final bubbles = List<BubbleTranslation>.from(result.bubbles);
    final b = bubbles[index];
    bubbles[index] = b.copyWith(
      translated: newText,
      isUserEdited: true,
    );
    _userEditedKeys.add(_bubbleKey(index, b));
    _currentResult = result.copyWith(bubbles: bubbles);
    emit(_translatedState());
  }

  String _bubbleKey(int index, BubbleTranslation b) =>
      '${b.rect.left}_${b.rect.top}_$index';

  /// Style → font family map (spec 6.3). Default: Komika/KosugiMaru.
  /// Anime Ace → ComicNeue, CC Wild Words → Bangers (OFL substitutes, T6.1).
  static const _styleFontMap = <TranslationStyle, String>{
    TranslationStyle.natural: 'Komika',
    TranslationStyle.genz: 'Komika',
    TranslationStyle.action: 'Bangers',
    TranslationStyle.romantis: 'Komika',
    TranslationStyle.formal: 'ComicNeue',
    TranslationStyle.kasar: 'Komika',
    TranslationStyle.literal: 'KosugiMaru',
  };

  /// Translation cache schema version. Bump to invalidate OLD cached results
  /// when the output shape changes (e.g. box-only → polygon: old entries lack
  /// `shape`, so re-translate to carry the polygon).
  static const int _cacheSchemaVersion = 2;

  /// Max glossary entries injected into a single AI prompt.
  static const int glossaryMaxEntries = 5;

  /// Selects glossary entries relevant to the given bubble texts: entries
  /// whose [GlossaryEntry.sourceText] appears as a case-insensitive
  /// substring of any text, most-recently saved first, at most [limit].
  /// Empty texts or no match → empty (prompt stays unchanged).
  static List<GlossaryEntry> selectRelevantGlossaryEntries(
    List<GlossaryEntry> entries,
    List<String> bubbleTexts, {
    int limit = glossaryMaxEntries,
  }) {
    if (entries.isEmpty || bubbleTexts.isEmpty) return [];
    final haystacks = [
      for (final t in bubbleTexts)
        if (t.trim().isNotEmpty) t.toLowerCase(),
    ];
    if (haystacks.isEmpty) return [];
    final matched = entries.where((e) {
      final needle = e.sourceText.trim().toLowerCase();
      if (needle.isEmpty) return false;
      return haystacks.any((h) => h.contains(needle));
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return matched.take(limit).toList();
  }

  /// Renders selected entries as prompt context lines:
  /// `Glossary:\n"src" -> "dst"\n...`. Embedded in the SAME AI request —
  /// never an extra call.
  static String buildGlossaryBlock(List<GlossaryEntry> entries) {
    final lines =
        entries.map((e) => '"${e.sourceText}" -> "${e.translatedText}"');
    return 'Glossary:\n${lines.join('\n')}';
  }

  /// Loads stored glossary and builds the prompt block for [bubbleTexts].
  ///
  /// Known bubble texts (same-content previous result, single-bubble retry)
  /// are substring-matched; with no known texts yet (fresh page) the most
  /// recent entries are used as the relevance proxy — the model ignores
  /// irrelevant lines. Empty glossary or a true no-match with known texts
  /// → null (prompt unchanged). Never throws.
  Future<String?> _glossaryContextFor(List<String> bubbleTexts) async {
    try {
      final repo = _glossaryRepository ?? getIt<GlossaryRepository>();
      final entries = await repo.getAll();
      if (entries.isEmpty) return null;
      var relevant = selectRelevantGlossaryEntries(entries, bubbleTexts);
      if (relevant.isEmpty && bubbleTexts.isEmpty) {
        final recent = List<GlossaryEntry>.of(entries)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        relevant = recent.take(glossaryMaxEntries).toList();
      }
      if (relevant.isEmpty) return null;
      return buildGlossaryBlock(relevant);
    } catch (_) {
      return null;
    }
  }

  /// Returns the cache key: `SHA256('$contentId:$pageIndex:$urlHash')` (16 hex).
  static String buildCacheKey(
      String contentId, int pageIndex, String imageUrl) {
    final digest = sha256.convert(utf8.encode(
        'v$_cacheSchemaVersion:$contentId:$pageIndex:${imageUrl.hashCode}'));
    return digest.toString().substring(0, 16);
  }

  bool get isBusy =>
      state is ReaderTranslationDetecting ||
      state is ReaderTranslationBuildingMosaic ||
      state is ReaderTranslationTranslating ||
      state is ReaderTranslationTranslatingBubble;

  void toggleOverlay() {
    _overlayVisible = !_overlayVisible;
    _bumpUi();
  }

  /// Reset per-page state when the reader navigates to a new page.
  void resetPage() {
    _currentResult = null;
    _overlayVisible = false;
    _manualBubbles.clear();
    _detectedBoxes.clear();
    _translationDetectedBoxes.clear();
    _failedBubbles.clear();
    _currentImageWidth = 0;
    _currentImageHeight = 0;
    _currentPageIndex = -1;
    _currentContentId = '';
    _currentImageUrl = '';
    _pageBytes = null;
    _pageWidth = 0;
    _pageHeight = 0;
    _imageBytesApprox = 0;
    _capturedPageSignature = '';
    // Emit Idle DIRECTLY (not via _bumpUi which re-emits the old Translated
    // state) so the overlay layer clears immediately.
    _uiVersion++;
    emit(ReaderTranslationIdle(uiVersion: _uiVersion));
  }

  /// Add a manual bubble (draw mode). [bubble.shape] carries the user-drawn
  /// polygon (ellipse/freeform); null = plain rect.
  void addManualBubble(BubbleBox bubble) {
    _manualBubbles.add(bubble);
    _bumpUi();
  }

  void undoLastManual() {
    if (_manualBubbles.isNotEmpty) _manualBubbles.removeLast();
    _bumpUi();
  }

  /// Add a tail polygon to a manual bubble (spec 7.1).
  void addTailToBubble(int index, List<List<int>> tail) {
    if (index < 0 || index >= _manualBubbles.length) return;
    _manualBubbles[index] = _manualBubbles[index].copyWith(tail: tail);
    _bumpUi();
  }

  /// Remove the tail from a manual bubble (spec 7.3).
  void removeTail(int index) {
    if (index < 0 || index >= _manualBubbles.length) return;
    _manualBubbles[index] = _manualBubbles[index].copyWith(clearTail: true);
    _bumpUi();
  }

  void clearManualBubbles() {
    _manualBubbles.clear();
    _bumpUi();
  }

  /// Tap on a detected (ONNX) bubble in draw mode removes it — mirrors the
  /// example app (tap bubble → delete).
  @Deprecated('Only caller is the draw-mode tap handler; keep for now.')
  void removeDetectedBubble(int index) {
    if (index < 0 || index >= _detectedBoxes.length) return;
    _detectedBoxes.removeAt(index);
    _bumpUi();
  }

  /// Tap on a manual bubble removes it.
  void removeManualBubble(int index) {
    if (index < 0 || index >= _manualBubbles.length) return;
    _manualBubbles.removeAt(index);
    _bumpUi();
  }

  /// NMS (IoU 0.45) + false-positive filter — same post-processing as the
  /// example app. ONNX raw output has duplicate/oversized boxes; without
  /// this the blue bubbles look wrong (double boxes, giant false positives).
  List<BubbleBox> postProcessBoxes(List<BubbleBox> boxes,
      {bool dropTextInBalloon = true}) {
    if (boxes.isEmpty) return [];
    final sorted = List<BubbleBox>.from(boxes)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    if (dropTextInBalloon) {
      // Balloon (cls 2) menang: text (cls 1) yang terserap di dalam balloon
      // adalah teks asli yang mau ditimpa terjemahan → buang, jangan render
      // terpisah. Text standalone (thought bubble) tetap. Kalau tak ada
      // balloon, tak ada yang dibuang (query aman).
      final balloons = sorted.where((b) => b.kind == 'balloon').toList();
      sorted.removeWhere(
          (b) => b.kind == 'text' && balloons.any((bb) => _contains(bb, b)));
    }
    // Frame (panel border) bukan bubble — buang dari hasil deteksi.
    sorted.removeWhere((b) => b.kind == 'frame');
    // NMS directly on sorted — no box merge. Merging same-kind boxes (incl.
    // balloons) unioned adjacent dialogue into one giant flat shape:null box
    // (the "giant green box"). dropTextInBalloon already prunes the split-line
    // text-in-balloon case T5 was meant to solve, so merge is dead weight here.
    final keep = <BubbleBox>[];
    final afterMerge = List<BubbleBox>.from(sorted);
    while (afterMerge.isNotEmpty) {
      final best = afterMerge.removeAt(0);
      keep.add(best);
      afterMerge.removeWhere((b) => _iou(best, b) > 0.45);
    }
    return _removeFalsePositives(keep);
  }

  double _iou(BubbleBox a, BubbleBox b) {
    final x1 = a.x > b.x ? a.x.toDouble() : b.x.toDouble();
    final y1 = a.y > b.y ? a.y.toDouble() : b.y.toDouble();
    final x2 = (a.x + a.w) < (b.x + b.w)
        ? (a.x + a.w).toDouble()
        : (b.x + b.w).toDouble();
    final y2 = (a.y + a.h) < (b.y + b.h)
        ? (a.y + a.h).toDouble()
        : (b.y + b.h).toDouble();
    final inter =
        (x2 - x1) < 0 ? 0.0 : (x2 - x1) * ((y2 - y1) < 0 ? 0.0 : (y2 - y1));
    if (inter <= 0) return 0;
    final areaA = a.w * a.h;
    final areaB = b.w * b.h;
    return inter / (areaA + areaB - inter);
  }

  bool _contains(BubbleBox outer, BubbleBox inner) {
    return outer.x <= inner.x &&
        outer.y <= inner.y &&
        outer.x + outer.w >= inner.x + inner.w &&
        outer.y + outer.h >= inner.y + inner.h;
  }

  /// Removes giant boxes that engulf a >2.5× smaller box (cypy PR#2 rule).
  List<BubbleBox> _removeFalsePositives(List<BubbleBox> boxes) {
    final toRemove = <int>{};
    for (var i = 0; i < boxes.length; i++) {
      for (var j = 0; j < boxes.length; j++) {
        if (i == j) continue;
        final areaI = boxes[i].w * boxes[i].h;
        final areaJ = boxes[j].w * boxes[j].h;
        if (areaJ * 2.5 < areaI && _contains(boxes[i], boxes[j])) {
          toRemove.add(i);
        }
      }
    }
    return [
      for (var i = 0; i < boxes.length; i++)
        if (!toRemove.contains(i)) boxes[i],
    ];
  }

  Future<void> translatePage({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required String contentId,
    required int pageIndex,
    required String imageUrl,
    required ReadingMode readingMode,
    // Total image URLs in the chapter. Kept for diagnostics/logging only — the
    // continue-scroll gate no longer uses it (the widget sends a WYSIWYG
    // viewport snapshot, so there is always a well-defined active region).
    required int imageUrlCount,
    // Original-image y of the cropped viewport sent here. Every distinct crop
    // produces its own translated result, so it must be part of the cache key —
    // otherwise scrolling to a new position and translating again returns the
    // stale bubbles from the previous crop (misaligned with the new viewport).
    int cropYTop = 0,
  }) async {
    // Keep page context for flat-bubble detection even when called without
    // capturePage (tests, direct callers).
    _pageBytes = imageBytes;
    _pageWidth = imageWidth;
    _pageHeight = imageHeight;
    logInfo(
        'translatePage input: mode=$readingMode page=$pageIndex size=${imageWidth}x$imageHeight cropYTop=$cropYTop urls=$imageUrlCount');
    // Continue-scroll is always allowed now: the widget sends a WYSIWYG
    // snapshot of the ACTUAL visible viewport, so there is always a well-defined
    // active region to translate (unlike the old offset-math path, where a
    // multi-image chapter had no reliable "active page").
    if (isBusy) return;

    final targetLang = await _preferencesRepository.getTargetLanguage();
    final style = await _preferencesRepository.getTranslationStyle();
    _currentStyle = style;
    setReadingDirection(readingMode);

    // Cache hit → skip pipeline. BUT: manual bubbles change the mosaic input,
    // and the cached result was generated without them — reusing it would
    // show the old translation and silently ignore the user's drawn bubbles.
    // Any manual bubble present → bypass the cache and run the full pipeline.
    final cacheKey = buildCacheKey(contentId, pageIndex, '$imageUrl#$cropYTop');
    final cached =
        _manualBubbles.isEmpty ? await _cacheRepository.get(cacheKey) : null;
    if (cached != null) {
      _currentImageWidth = imageWidth;
      _currentImageHeight = imageHeight;
      _currentPageIndex = pageIndex;
      _currentContentId = contentId;
      _currentImageUrl = imageUrl;
      // Re-attach shapes if cache was saved before shape detection existed
      // and _detectedBoxes is already populated (draw mode ran first).
      _currentResult = _attachShapes(cached);
      _overlayVisible = true;
      emit(_translatedState());
      logInfo('translatePage: cache hit, ${cached.bubbles.length} bubbles');
      return;
    }

    // Show the spinner immediately on tap — provider resolution + prefetch
    // wait + mosaic build can each take a beat, and the tap must never look
    // frozen. T2 reuse skips the ONNX wait, but the first frame is the same.
    emit(const ReaderTranslationDetecting());

    // Active provider (must be vision-capable for image translation).
    // Text-only free models (deepseek-v4-flash-free) can't read the page
    // image — prefer any vision-capable provider, else guide to Settings.
    final providers = await _providerRepository.getProviders();
    final active = providers.where((p) => p.isDefault).firstOrNull ??
        (providers.isEmpty ? null : providers.first);
    if (active == null) {
      emit(const ReaderTranslationNoProvider());
      return;
    }
    if (!active.isVisionCapable) {
      final visionProvider =
          providers.where((p) => p.isVisionCapable).firstOrNull;
      if (visionProvider != null) {
        await _providerRepository.setDefault(visionProvider.id);
        logInfo(
            'Active provider ${active.model} text-only — switched to ${visionProvider.model}');
      } else {
        emit(ReaderTranslationNoProvider(modelName: active.model));
        return;
      }
    }

    // Glossary enrichment (no extra AI request): known bubble texts from a
    // previous same-content result are substring-matched; fresh pages fall
    // back to the most recent entries. Null → prompt unchanged.
    final previousOriginals = _currentContentId == contentId
        ? [
            for (final b
                in _currentResult?.bubbles ?? const <BubbleTranslation>[])
              if (b.original.trim().isNotEmpty) b.original,
          ]
        : const <String>[];
    final glossaryContext = await _glossaryContextFor(previousOriginals);

    // Mosaic quality tier (default high = legacy behavior).
    final mosaicQuality = await _preferencesRepository.getMosaicQuality();
    logInfo('translatePage: provider=${active.displayName}, '
        'mosaic=${mosaicQuality.name}, glossary=${glossaryContext == null ? 'off' : 'on'}');

    try {
      // 1. Webtoon strip → chunk via ImageSplitter (1280px). Decoding + crop
      // + encode per chunk is CPU-bound, so run it in a background isolate —
      // otherwise the Detecting spinner cannot render until chunking finishes.
      if (WebtoonDetector.isWebtoon(
          Size(imageWidth.toDouble(), imageHeight.toDouble()))) {
        final chunks = await _heavyRunner(
          () => _splitWebtoonIsolate(imageBytes, imageWidth, imageHeight),
        );
        final allBoxes = <BubbleBox>[];
        var offsetY = 0;
        for (final chunk in chunks) {
          emit(const ReaderTranslationDetecting());
          final boxes = await _detect(chunk.bytes, chunk.width, chunk.height);
          for (final b in boxes) {
            allBoxes.add(BubbleBox(
              x: b.x,
              y: b.y + offsetY,
              w: b.w,
              h: b.h,
              confidence: b.confidence,
              shape: b.shape,
              kind: b.kind,
            ));
          }
          offsetY += chunk.height;
        }
        _detectedBoxes = postProcessBoxes(allBoxes);
        _translationDetectedBoxes = _detectedBoxes;
        logInfo(
            'translatePage webtoon: rawBoxes=${allBoxes.length} → postProcess=${_detectedBoxes.length}');
        // Use POST-PROCESSED boxes (same as draw mode), NOT the raw detections:
        // raw output carries duplicate/oversized boxes that became duplicate
        // mosaic chips — the model then merged the duplicate-text chips into
        // one bubble ("translation digabung").
        final boxes = _translationBoxes();
        final result = await _translateWithBubbles(
          imageBytes: imageBytes,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          boxes: boxes,
          targetLang: targetLang,
          style: style,
          providers: providers,
          glossaryContext: glossaryContext,
          mosaicQuality: mosaicQuality,
        );
        _finish(result, cacheKey, contentId, pageIndex, imageWidth, imageHeight,
            imageUrl);
        logInfo(
            'translatePage done: ${result.bubbles.length} bubbles, usedFallback=${result.usedFallback}');
        return;
      }

      // 2. Normal page: ONNX detect — only when the user did not already
      //    provide boxes. A prior draw-mode Detect (or user deletes) set
      //    _detectedBoxes, and manual bubbles are user-drawn corrections —
      //    re-detecting would resurrect unchecked bubbles AND (with manual
      //    boxes only) throw away the user's work in favor of the detector.
      if (_manualBubbles.isEmpty && _detectedBoxes.isEmpty) {
        // T2 prefetch reuse: background detection already ran for this exact
        // captured image → skip the 2.6s ONNX wait (spec 2.4).
        // While a prefetch is MID-RUN, the ONNX session is busy: re-running
        // `_detect` here competes for the same Kotlin executor AND the same
        // OrtSession (not thread-safe). Wait for it to finish, then fall
        // through to the reuse check below — no double inference.
        if (_prefetchRunning) {
          logInfo('translatePage: prefetch in-flight — waiting for it...');
          final keyAtStart = _capturedPageSignature;
          // Bounded wait: 5s covers the ~2.6s ONNX run; past that, proceed
          // with our own detect rather than hang forever.
          for (var i = 0; i < 50 && _prefetchRunning; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (keyAtStart != _capturedPageSignature) {
            // Page changed while waiting — abort this translate entirely
            // (the caller will re-invoke for the new page).
            logInfo('translatePage: page changed during prefetch wait — abort');
            return;
          }
          logInfo('translatePage: prefetch finished (waited)');
        }
        final prefetchedMatches = _prefetchedBoxes != null &&
            _prefetchKey.isNotEmpty &&
            _prefetchKey == _capturedPageSignature;
        if (prefetchedMatches) {
          _detectedBoxes = List.of(_prefetchedBoxes!);
          _translationDetectedBoxes = _detectedBoxes;
          logInfo(
              'translatePage: reuse prefetch — ${_detectedBoxes.length} boxes (no re-detect)');
        } else {
          if (_prefetchedBoxes != null && _prefetchKey.isNotEmpty) {
            logInfo(
                'translatePage: prefetch STALE (sig differs: captures $_capturedPageSignature prefetch $_prefetchKey) — re-detect');
          }
          emit(const ReaderTranslationDetecting());
          final rawBoxes = await _detect(imageBytes, imageWidth, imageHeight);
          _detectedBoxes = postProcessBoxes(rawBoxes);
          _translationDetectedBoxes = _detectedBoxes;
          logInfo(
              'translatePage: detect ${rawBoxes.length} → ${_detectedBoxes.length} boxes');
          for (final b in _detectedBoxes) {
            logInfo(
                '  box kind=${b.kind} conf=${b.confidence.toStringAsFixed(2)} ${b.x},${b.y},${b.w}x${b.h} shape=${b.shape?.length}');
          }
        }
      }
      // Manual bubbles are the user's authoritative correction: drop any
      // detected box a manual bubble covers, so the same text is NOT sent to
      // the AI twice. Previously the duplicate chip confused the model into
      // merging/swapping the per-bubble translations.
      final boxes = _translationBoxes();
      logInfo(
          'translatePage: mosaic input=${boxes.length} box (manual=${_manualBubbles.length}, detected=${_detectedBoxes.length})');

      // 3. Mosaic (≥1 bubble) or full-image fallback (0 bubbles)
      final result = await _translateWithBubbles(
        imageBytes: imageBytes,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        boxes: boxes,
        targetLang: targetLang,
        style: style,
        providers: providers,
        glossaryContext: glossaryContext,
        mosaicQuality: mosaicQuality,
      );
      // Diagnostic: AI merging/skipping chips (or fallback full-image when
      // boxes is empty) is the usual cause of "translations look merged".
      if (boxes.isNotEmpty && result.bubbles.length != boxes.length) {
        logWarning(
            'translatePage: AI mengembalikan ${result.bubbles.length}/${boxes.length} bubble — ada chip di-SKIP atau digabung oleh model');
      }
      _finish(result, cacheKey, contentId, pageIndex, imageWidth, imageHeight,
          imageUrl);
    } on AiTranslationException catch (e) {
      if (isClosed) return;
      if (e.isRateLimited) {
        emit(ReaderTranslationRateLimited(cooldownSeconds: 60));
      } else {
        emit(ReaderTranslationError(message: e.message));
      }
    } catch (e) {
      if (isClosed) return;
      logWarning('translatePage failed: $e');
      emit(ReaderTranslationError(message: e.toString()));
    }
  }

  Future<List<BubbleBox>> _detect(
      Uint8List bytes, int width, int height) async {
    try {
      final result = await KuronNative.instance.detectBubbles(
        imageBytes: bytes,
        imageWidth: width,
        imageHeight: height,
      );
      return result ?? [];
    } catch (e) {
      logWarning('ONNX detectBubbles failed: $e');
      return [];
    }
  }

  Future<PageTranslation> _translateWithBubbles({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required List<BubbleBox> boxes,
    required String targetLang,
    required TranslationStyle style,
    required List<AiProviderConfig> providers,
    String? glossaryContext,
    MosaicQuality mosaicQuality = MosaicQuality.high,
  }) async {
    var provider = providers.where((p) => p.isDefault).firstOrNull ??
        (providers.isEmpty ? null : providers.first);
    if (provider == null) {
      emit(const ReaderTranslationNoProvider());
      throw const AiTranslationException('No provider');
    }
    if (!provider.isVisionCapable) {
      final vision = providers.where((p) => p.isVisionCapable).firstOrNull;
      if (vision == null) {
        emit(ReaderTranslationNoProvider(modelName: provider.model));
        throw const AiTranslationException('No vision provider');
      }
      provider = vision;
    }
    var current = provider;

    // Multi-key / multi-provider round robin on 429
    final usedIds = <String>{};
    while (true) {
      final impl = _providerFactory.create(current);
      logInfo('_translateWithBubbles: attempt via ${current.displayName} '
          '(${current.model}, ${boxes.length} bubbles)');
      try {
        final PageTranslation result;
        if (boxes.isEmpty) {
          logWarning(
              'translatePage: FALLBACK full-image (0 bubble) — posisi ditentukan model, bukan bubble detector');
          emit(const ReaderTranslationBuildingMosaic());
          final fallback = _fallbackHandler;
          final pageBytes = imageBytes;
          // Full-page compress (decode + resize + JPEG85) is CPU-bound — run
          // on a background isolate so the loading frame renders immediately.
          final compressed =
              await _heavyRunner(() => fallback.compressPage(pageBytes));
          result = await impl.translatePage(
            image: compressed,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            bubbles: const [],
            targetLang: targetLang,
            style: style,
            skipSfx: skipSfx,
            readingDirection: readingDirectionLabel,
          );
        } else {
          emit(const ReaderTranslationBuildingMosaic());
          // Mosaic build (decode page, crop each bubble, 2× scale, composite,
          // JPEG85 + downscale loop) is CPU-bound — run on a background
          // isolate so the spinner appears right away instead of after the
          // bubble cuts finish. Only sendable locals are captured.
          final mosaicBuilder = _mosaicBuilder;
          final pageBytes = imageBytes;
          final likeBoxes = boxes.map(_toLike).toList();
          final mosaic = await _heavyRunner(() => mosaicBuilder
              .buildMosaic(pageBytes, likeBoxes, quality: mosaicQuality));
          emit(ReaderTranslationTranslating(total: boxes.length));
          result = await impl.translatePage(
            image: mosaic,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            bubbles: likeBoxes,
            targetLang: targetLang,
            style: style,
            skipSfx: skipSfx,
            readingDirection: readingDirectionLabel,
            glossaryContext: glossaryContext,
          );
        }
        // 9.1 per-bubble partial progress: report parsed bubbles as they land
        if (result.bubbles.isNotEmpty) {
          emit(ReaderTranslationTranslatingBubble(
            current: result.bubbles.length,
            total: boxes.isEmpty ? result.bubbles.length : boxes.length,
          ));
        }
        return result;
      } on AiTranslationException catch (e) {
        if (!e.isRateLimited) {
          logWarning('_translateWithBubbles: ${current.displayName} failed: '
              '${e.message}');
          rethrow;
        }
        logWarning('_translateWithBubbles: ${current.displayName} '
            'rate-limited — trying fallback');
        usedIds.add(current.id);
        final next = _fallbackProvider(current, providers, usedIds);
        if (next == null) {
          emit(ReaderTranslationRateLimited(
            cooldownSeconds: 60,
            fallbackName: null,
          ));
          throw const AiTranslationException('All providers rate limited',
              isRateLimited: true);
        }
        emit(ReaderTranslationRateLimited(
          cooldownSeconds: 60,
          fallbackName: next.displayName,
        ));
        current = next;
      }
    }
  }

  /// Flags flat/wide text boxes (cypy "bubble flat"): ratio ≥ 2.4, at least
  /// 45% of image width, at most 22% of image height — text sitting directly
  /// on busy artwork. Such bubbles render a white patch behind the text.
  PageTranslation _flagFlatBubbles(PageTranslation result) {
    final imageBytes = _pageBytes;
    if (imageBytes == null || imageBytes.isEmpty) return result;
    img.Image? page;
    try {
      page = img.decodeImage(imageBytes);
    } catch (_) {
      return result;
    }
    if (page == null) return result;
    final w = page.width.toDouble();
    final h = page.height.toDouble();
    return result.copyWith(bubbles: [
      for (final b in result.bubbles)
        b.copyWith(
          needsWhitePatch: b.rect.width / b.rect.height >= 2.4 &&
              b.rect.width >= w * 0.45 &&
              b.rect.height <= h * 0.22,
        ),
    ]);
  }

  void _finish(PageTranslation result, String cacheKey, String contentId,
      int pageIndex, int imageWidth, int imageHeight, String imageUrl) {
    result = _attachShapes(result);
    result = _flagFlatBubbles(result);
    // Track per-bubble failures (empty translation = AI skipped)
    _failedBubbles.clear();
    final fontFamily =
        _currentStyle != null ? _styleFontMap[_currentStyle] : null;
    if (fontFamily != null) {
      result = result.copyWith(
        bubbles: result.bubbles
            .map((b) =>
                b.fontFamily == null ? b.copyWith(fontFamily: fontFamily) : b)
            .toList(),
      );
    }
    for (var i = 0; i < result.bubbles.length; i++) {
      if (result.bubbles[i].translated.trim().isEmpty) {
        _failedBubbles[i] = 'AI skipped this bubble';
      }
    }
    _currentImageWidth = imageWidth;
    _currentImageHeight = imageHeight;
    _currentPageIndex = pageIndex;
    _currentContentId = contentId;
    _currentImageUrl = imageUrl;
    _currentResult = result;
    _overlayVisible = true;
    if (result.bubbles.isNotEmpty) {
      final first = result.bubbles.first.rect;
      logInfo(
          'translatePage output: firstBubble=(${first.left.toStringAsFixed(1)},${first.top.toStringAsFixed(1)}) ${first.width.toStringAsFixed(1)}x${first.height.toStringAsFixed(1)} image=${imageWidth}x$imageHeight');
    } else {
      logInfo(
          'translatePage output: no bubbles image=${imageWidth}x$imageHeight');
    }
    unawaited(_cacheRepository.put(
      cacheKey,
      result,
      contentId: contentId,
      pageIndex: pageIndex,
    ));
    if (isClosed) return;
    emit(_translatedState());
  }

  /// Re-attach ONNX polygon `shape` to translated bubbles by matching the
  /// detection box (same rect). The AI/mosaic round-trip only carries boxes,
  /// so shape is re-joined here from [_detectedBoxes].
  PageTranslation _attachShapes(PageTranslation result) {
    if (_detectedBoxes.isEmpty) {
      logInfo('_attachShapes: _detectedBoxes kosong, shape kosong');
      return result;
    }
    final detected = _detectedBoxes;
    var attached = 0;
    final bubbles = <BubbleTranslation>[];
    for (final b in result.bubbles) {
      if (b.shape != null) {
        bubbles.add(b);
        continue;
      }
      // Manual bubble:
      //  - user drew a RECT (no shape) → text must fit that box. Never hand
      //    it a detected polygon — the text would wrap to the balloon's
      //    inscribed shape instead.
      //  - user drew an ellipse/freeform → re-attach THEIR shape (survives
      //    the AI/mosaic round-trip), detected shape excluded (centers may
      //    differ, and the user's outline wins over a hit-missed detection).
      final manualShape = _nearestManualShape(b.rect);
      if (manualShape != null) {
        bubbles.add(b.copyWith(shape: manualShape));
        attached++;
        continue;
      }
      if (_manualCovers(b.rect)) {
        bubbles.add(b);
        continue;
      }
      final s = _nearestShape(detected, b.rect);
      if (s != null) attached++;
      bubbles.add(b.copyWith(shape: s));
    }
    logInfo(
        '_attachShapes: ${result.bubbles.length} bubble, shape-attached=$attached, detected=${_detectedBoxes.length}');
    return result.copyWith(bubbles: bubbles);
  }

  /// Shape of the manual bubble (ellipse/freeform) whose box contains the
  /// bulk (>60% of its area) of [rect] — the AI-returned box of the same
  /// region. Null when the user drew a rect (shape null) or nothing covers.
  List<List<int>>? _nearestManualShape(Rect rect) {
    if (_manualBubbles.isEmpty) return null;
    final rArea = rect.width * rect.height;
    if (rArea <= 0) return null;
    for (final m in _manualBubbles) {
      final shape = m.shape;
      if (shape == null || shape.length < 3) continue;
      final mRect = Rect.fromLTWH(
          m.x.toDouble(), m.y.toDouble(), m.w.toDouble(), m.h.toDouble());
      final inter = rect.intersect(mRect);
      if (inter.isEmpty) continue;
      final smaller = rArea < m.w * m.h ? rArea : m.w * m.h;
      if (inter.width * inter.height / smaller >= 0.6) return shape;
    }
    return null;
  }

  /// Best-matching detected bubble's shape for an AI-returned rect. The AI
  /// round-trip returns per-bubble boxes that may differ by a few px from the
  /// ONNX detection box (model or edit shift). Exact rect match would drop the
  /// polygon → bubble renders as a plain box. Match on closest center + IoU
  /// so shape survives small coord drift but a far frame never steals it.
  /// True when any manual bubble covers >60% of [rect]'s smaller area.
  bool _manualCovers(Rect rect) {
    if (_manualBubbles.isEmpty) return false;
    final rArea = rect.width * rect.height;
    if (rArea <= 0) return false;
    for (final m in _manualBubbles) {
      final mRect = Rect.fromLTWH(
          m.x.toDouble(), m.y.toDouble(), m.w.toDouble(), m.h.toDouble());
      final inter = rect.intersect(mRect);
      if (inter.isEmpty) continue;
      final smaller = rArea < m.w * m.h ? rArea : m.w * m.h;
      if (inter.width * inter.height / smaller >= 0.6) return true;
    }
    return false;
  }

  List<List<int>>? _nearestShape(List<BubbleBox> detected, Rect rect) {
    BubbleBox? best;
    var bestScore = double.negativeInfinity;
    for (final d in detected) {
      final shape = d.shape;
      if (shape == null || shape.length < 3) continue;
      final iou = _iou(
        d,
        BubbleBox(
          x: rect.left.round(),
          y: rect.top.round(),
          w: rect.width.round(),
          h: rect.height.round(),
        ),
      );
      // IoU dominates; center distance breaks ties. Normalized by img area.
      final dx = (d.cx - rect.center.dx).abs();
      final dy = (d.cy - rect.center.dy).abs();
      final score = iou - (dx + dy) * 1e-4;
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best?.shape;
  }

  AiProviderConfig? _fallbackProvider(
    AiProviderConfig current,
    List<AiProviderConfig> providers,
    Set<String> usedIds,
  ) {
    final sameType = providers
        .where((p) =>
            p.type == current.type &&
            p.id != current.id &&
            !usedIds.contains(p.id))
        .toList();
    if (sameType.isNotEmpty) return sameType.first;
    final others = providers
        .where((p) => p.type != current.type && !usedIds.contains(p.id))
        .toList();
    return others.isEmpty ? null : others.first;
  }

  /// Re-translate a single failed bubble (spec 3.2). Builds a 1-chip mosaic
  /// for that bubble, calls the AI provider, and merges the result back.
  Future<void> retryBubble(int index) async {
    final result = _currentResult;
    if (result == null || index < 0 || index >= result.bubbles.length) return;
    final bubble = result.bubbles[index];
    final providers = await _providerRepository.getProviders();
    var provider = providers.where((p) => p.isDefault).firstOrNull ??
        (providers.isEmpty ? null : providers.first);
    if (provider == null) return;
    if (!provider.isVisionCapable) {
      final vision = providers.where((p) => p.isVisionCapable).firstOrNull;
      if (vision == null) return;
      provider = vision;
    }
    final impl = _providerFactory.create(provider);
    final targetLang = await _preferencesRepository.getTargetLanguage();
    final style = await _preferencesRepository.getTranslationStyle();

    // Build single-bubble mosaic
    final singleBox = BubbleBoxLike(
      bubble.rect.left.round(),
      bubble.rect.top.round(),
      bubble.rect.width.round(),
      bubble.rect.height.round(),
    );
    final pageBytes = _pageBytes;
    if (pageBytes == null) return;
    final mosaicQuality = await _preferencesRepository.getMosaicQuality();
    // The retried bubble's own original text is known — match glossary
    // against it so the retry reuses the user's saved terminology.
    final glossaryContext = await _glossaryContextFor([bubble.original]);
    final mosaic = await _heavyRunner(() => _mosaicBuilder
        .buildMosaic(pageBytes, [singleBox], quality: mosaicQuality));
    try {
      final retryResult = await impl.translatePage(
        image: mosaic,
        imageWidth: _currentImageWidth,
        imageHeight: _currentImageHeight,
        bubbles: [singleBox],
        targetLang: targetLang,
        style: style,
        skipSfx: skipSfx,
        readingDirection: readingDirectionLabel,
        glossaryContext: glossaryContext,
      );
      if (retryResult.bubbles.isNotEmpty) {
        final updated = List<BubbleTranslation>.from(_currentResult!.bubbles);
        updated[index] = retryResult.bubbles.first;
        _currentResult = _currentResult!.copyWith(bubbles: updated);
      }
    } catch (e) {
      logWarning('retryBubble[$index] failed: $e');
    }
    // Clear failed entry regardless of outcome
    final newFailed = Map<int, String>.from(_translatedState().failedBubbles);
    newFailed.remove(index);
    emit(ReaderTranslationTranslated(
      result: _currentResult!,
      imageWidth: _currentImageWidth,
      imageHeight: _currentImageHeight,
      pageIndex: _currentPageIndex,
      contentId: _currentContentId,
      imageUrl: _currentImageUrl,
      failedBubbles: newFailed,
    ));
  }

  BubbleBoxLike _toLike(BubbleBox b) => BubbleBoxLike(b.x, b.y, b.w, b.h);

  /// Mosaic input boxes: manual bubbles (user-corrected) first, then detected
  /// boxes NOT already covered by a manual bubble. Prevents the same text from
  /// being cropped into two mosaic chips (manual + detected duplicates of one
  /// region), which made the model merge/swap per-bubble translations.
  /// Mosaic input boxes: manual bubbles (user-corrected) first, then detected
  /// boxes NOT already covered by a manual bubble. Prevents the same text from
  /// being cropped into two mosaic chips (manual + detected duplicates of one
  /// region), which made the model merge/swap per-bubble translations.
  List<BubbleBox> _translationBoxes() {
    final manual = List<BubbleBox>.from(_manualBubbles);
    final detected = List<BubbleBox>.from(_translationDetectedBoxes);
    if (manual.isEmpty || detected.isEmpty) {
      return [...manual, ...detected];
    }
    final kept = <BubbleBox>[];
    for (final d in detected) {
      final dRect = Rect.fromLTWH(
          d.x.toDouble(), d.y.toDouble(), d.w.toDouble(), d.h.toDouble());
      final coveredByManual = manual.any((m) {
        final mRect = Rect.fromLTWH(
            m.x.toDouble(), m.y.toDouble(), m.w.toDouble(), m.h.toDouble());
        final inter = dRect.intersect(mRect);
        final interArea = inter.isEmpty ? 0.0 : inter.width * inter.height;
        final dArea = dRect.width * dRect.height;
        final mArea = mRect.width * mRect.height;
        if (dArea <= 0 || mArea <= 0) return false;
        final smaller = dArea < mArea ? dArea : mArea;
        return interArea / smaller >= 0.6;
      });
      if (!coveredByManual) kept.add(d);
    }
    // Sort in reading order: RTL manga = right-to-left, LTR manhwa/webtoon = left-to-right
    // Both top-to-bottom, X direction flips.
    kept.sort((a, b) {
      final ay = a.y.compareTo(b.y);
      if (ay != 0) return ay;
      return _rtlReading
          ? b.x.compareTo(a.x) // RTL: rightmost first
          : a.x.compareTo(b.x); // LTR: leftmost first
    });
    return [...manual, ...kept];
  }
}

class _ImageChunk {
  const _ImageChunk(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Webtoon: slice into ≤1280px chunks. Runs inside a background isolate from
/// [ReaderTranslationCubit.translatePage] — decode + per-chunk crop/encode is
/// CPU-bound and would otherwise jank the UI and delay the loading state.
/// Pure Dart (`package:image`); undecodable input returns bytes unchanged.
List<_ImageChunk> _splitWebtoonIsolate(Uint8List bytes, int width, int height) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return [_ImageChunk(bytes, width, height)];
  }
  const maxHeight = 1280;
  final chunks = <_ImageChunk>[];
  for (var y = 0; y < height; y += maxHeight) {
    final h = (height - y).clamp(0, maxHeight);
    final crop = img.copyCrop(decoded, x: 0, y: y, width: width, height: h);
    chunks.add(_ImageChunk(img.encodeJpg(crop, quality: 90), width, h));
  }
  return chunks;
}
