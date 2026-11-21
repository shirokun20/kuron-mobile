import 'package:kuron_core/kuron_core.dart';

/// Pure-Dart helpers that decide chapter ordering and next/previous navigation.
///
/// Shared by [ReaderCubit] (reader prev/next) and the continue-reading FAB so
/// both use the exact same numeric parsing and ordering rules — no per-config
/// regex workarounds.
///
/// Key rules:
/// * Never parse chapter numbers out of MangaDex-style UUIDs/hashes.
/// * Compare volume **only when both sides declare one** — otherwise a
///   `Vol. 1 Ch. 1` vs `Ch. 2 (volume = null -> 0)` comparison inverts.
/// * Resolve next/previous by numeric progression, skipping duplicate
///   scanlation-group entries of the same chapter and unreadable chapters.
abstract final class ChapterOrderUtils {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static final RegExp _chapterKeywordPattern = RegExp(
    r'(?:chapter|chap|ch|bab|episode|eps|ep|第)\s*[.\-:]?\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );

  static final RegExp _bareNumberPattern = RegExp(r'(\d+(?:[.,]\d+)?)');

  static final RegExp _volumePattern = RegExp(
    r'(?:\bvol(?:ume)?\b\s*[:\.-]?)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// Parses a chapter number from a label, preferring a keyword form
  /// (`Chapter 12`, `Bab 1`, `Ep. 2`, `第3話`, ...).
  ///
  /// A bare number is accepted only when [input] is not a UUID — this is what
  /// stops `9f8e7d6c-...` from being read as chapter `9`.
  static double? parseChapterNumber(String input) {
    final match = _chapterKeywordPattern.firstMatch(input);
    final effectiveMatch =
        match ??
        (_uuidPattern.hasMatch(input.trim())
            ? null
            : _bareNumberPattern.firstMatch(input));
    final raw = effectiveMatch?.group(1);
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  /// Parses an optional volume number (`Vol. 2`, `Volume 3`, ...).
  static double? parseVolumeNumber(String input) {
    final raw = _volumePattern.firstMatch(input)?.group(1);
    if (raw == null) return null;
    return double.tryParse(raw);
  }

  /// Chapter number (and optional volume) declared by [chapter].
  ///
  /// Title wins; URL/id are consulted only when they are not UUIDs.
  static ({double chapter, double? volume})? extractOrder(Chapter chapter) {
    final titleOrder = parseChapterNumber(chapter.title);
    if (titleOrder != null) {
      return (chapter: titleOrder, volume: parseVolumeNumber(chapter.title));
    }

    final url = chapter.url;
    final fromUrl = _uuidPattern.hasMatch(url.trim())
        ? null
        : parseChapterNumber(url);
    final id = chapter.id;
    final fallback =
        fromUrl ??
        (_uuidPattern.hasMatch(id.trim()) ? null : parseChapterNumber(id));
    if (fallback == null) return null;

    return (chapter: fallback, volume: parseVolumeNumber(chapter.title));
  }

  /// Compares two chapters by declared order.
  ///
  /// Negative when [a] comes before [b] in ascending numbering, positive when
  /// it comes after, `0` when equal, `null` when either is unnumbered.
  /// Volume is compared **only when both chapters declare one**.
  static int? compareOrder(Chapter a, Chapter b) {
    final orderA = extractOrder(a);
    final orderB = extractOrder(b);
    if (orderA == null || orderB == null) return null;
    return _compareOrders(orderA, orderB);
  }

  static int _compareOrders(
    ({double chapter, double? volume}) a,
    ({double chapter, double? volume}) b,
  ) {
    if (a.volume != null && b.volume != null) {
      final volumeCompare = a.volume!.compareTo(b.volume!);
      if (volumeCompare != 0) return volumeCompare;
    }
    return a.chapter.compareTo(b.chapter);
  }

  /// Majority-vote direction of [chapters] based on consecutive numbered pairs.
  ///
  /// `true` = ascending (Ch. 1 -> Ch. 2 -> ...), `false` = descending.
  /// Falls back to first-vs-last numbered chapter when no consecutive pair
  /// differs, and returns `null` when there is nothing to compare.
  static bool? isAscendingPool(List<Chapter> chapters) {
    var ascending = 0;
    var descending = 0;
    for (var i = 0; i < chapters.length - 1; i++) {
      final comparison = compareOrder(chapters[i], chapters[i + 1]);
      if (comparison == null || comparison == 0) continue;
      if (comparison < 0) {
        ascending++;
      } else {
        descending++;
      }
    }

    if (ascending == 0 && descending == 0) {
      final numbered = chapters
          .where((chapter) => extractOrder(chapter) != null)
          .toList();
      if (numbered.length >= 2) {
        final comparison = compareOrder(numbered.first, numbered.last);
        if (comparison != null && comparison != 0) return comparison < 0;
      }
      return null;
    }

    return ascending > descending;
  }

  /// Resolves the chapter adjacent to [currentChapter] in [pool].
  ///
  /// [step] > 0 means next chapter, [step] < 0 means previous chapter. When the
  /// current chapter is numbered, the closest chapter **by number** is chosen
  /// and same-number scanlation-group duplicates plus unreadable entries are
  /// skipped. Only a fully unnumbered current chapter falls back to index
  /// stepping following the pool's detected direction.
  static Chapter? resolveAdjacentChapter({
    required List<Chapter> pool,
    required Chapter currentChapter,
    required int step,
  }) {
    if (pool.isEmpty || step == 0) return null;

    final currentOrder = extractOrder(currentChapter);
    if (currentOrder != null) {
      final currentIndex = pool.indexWhere((c) => c.id == currentChapter.id);
      final ranked =
          <
            ({
              Chapter chapter,
              ({double chapter, double? volume}) order,
              int distance,
            })
          >[];

      for (var i = 0; i < pool.length; i++) {
        final candidate = pool[i];
        if (candidate.id == currentChapter.id) continue;
        if (!candidate.isReadableInApp) continue;
        final order = extractOrder(candidate);
        if (order == null) continue;
        final comparison = _compareOrders(order, currentOrder);
        if (step > 0 ? comparison <= 0 : comparison >= 0) continue;
        ranked.add((
          chapter: candidate,
          order: order,
          distance: (i - currentIndex).abs(),
        ));
      }

      if (ranked.isEmpty) return null;
      ranked.sort((a, b) {
        final orderCompare = _compareOrders(a.order, b.order);
        if (orderCompare != 0) return step > 0 ? orderCompare : -orderCompare;
        return a.distance.compareTo(b.distance);
      });
      return ranked.first.chapter;
    }

    // Unnumbered current chapter: step by index in the pool's direction.
    final currentIndex = pool.indexWhere((c) => c.id == currentChapter.id);
    if (currentIndex == -1) return null;
    final isAscending = isAscendingPool(pool) ?? true;
    final effectiveStep = isAscending ? step : -step;
    final targetIndex = currentIndex + effectiveStep;
    if (targetIndex < 0 || targetIndex >= pool.length) return null;

    final target = pool[targetIndex];
    if (target.id.isEmpty ||
        target.id == currentChapter.id ||
        !target.isReadableInApp) {
      return null;
    }
    return target;
  }
}
