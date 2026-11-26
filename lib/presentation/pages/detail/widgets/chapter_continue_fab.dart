import 'package:material_ui/material_ui.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/domain/entities/history.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/utils/chapter_order_utils.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

const double _fabWidth = 236;
const double _fabHeight = 64;

enum ChapterContinueMode {
  /// Reopen the last-read chapter where the reader left off.
  resume,

  /// Last-read chapter is finished: open the next chapter by number.
  nextChapter,

  /// Last-read chapter is the last of the series: restart from the first.
  restart,
}

class ChapterContinueTarget {
  const ChapterContinueTarget({
    required this.chapter,
    required this.page,
    required this.mode,
    this.chapterNumber,
  });

  final Chapter chapter;
  final int page;
  final ChapterContinueMode mode;

  /// Number parsed from the chapter name, for the button title.
  final double? chapterNumber;
}

/// `3` for 3.0, `2.5` for 2.5 — chapter numbers are shown as declared.
String formatChapterNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Picks what the button should open:
/// - unfinished chapter -> that chapter, on its last page ([resume]);
/// - finished chapter with a later chapter -> the next chapter by number;
/// - finished last chapter -> first chapter of the series.
/// Chapters that exist in [chapters] but are not readable in-app
/// (external/unavailable sources) are skipped.
ChapterContinueTarget? resolveChapterContinueTarget({
  required Map<String, History>? chapterHistory,
  required List<Chapter> chapters,
}) {
  if (chapterHistory == null || chapterHistory.isEmpty) return null;

  final byId = {for (final chapter in chapters) chapter.id: chapter};
  final entries =
      chapterHistory.entries
          .where((entry) => (entry.value.chapterId ?? '').isNotEmpty)
          .toList()
        ..sort((a, b) => b.value.lastViewed.compareTo(a.value.lastViewed));

  for (final entry in entries) {
    final history = entry.value;
    final chapterId = history.chapterId!;
    final known = byId[chapterId];
    if (known != null && !known.isReadableInApp) continue;

    final totalPages = history.totalPages;
    final finished =
        history.isCompleted ||
        (totalPages > 0 && history.lastPage >= totalPages);
    var page = finished ? 1 : history.lastPage;
    if (totalPages > 0) page = page.clamp(1, totalPages).toInt();
    if (page < 1) page = 1;

    // Number parsed from the chapter name (or its slug) for the button title.
    final currentNumber =
        chapterNumberFromName(
          known?.title ?? history.chapterTitle ?? chapterId,
        ) ??
        (known == null ? null : chapterNumberFromName(known.url));

    if (!finished) {
      return ChapterContinueTarget(
        chapter:
            known ??
            Chapter(
              id: chapterId,
              title: history.chapterTitle ?? chapterId,
              url: chapterId,
            ),
        page: page,
        mode: ChapterContinueMode.resume,
        chapterNumber: currentNumber,
      );
    }

    // Finished: walk the series by chapter number parsed from the name, never
    // by array position (sources usually list newest-first).
    final ordered = _orderedReadableChapters(chapters);

    if (currentNumber != null) {
      for (final candidate in ordered) {
        final number = candidate.$2;
        if (number > currentNumber) {
          return ChapterContinueTarget(
            chapter: candidate.$1,
            page: 1,
            mode: ChapterContinueMode.nextChapter,
            chapterNumber: number,
          );
        }
      }
    }

    if (ordered.isNotEmpty) {
      return ChapterContinueTarget(
        chapter: ordered.first.$1,
        page: 1,
        mode: ChapterContinueMode.restart,
        chapterNumber: ordered.first.$2,
      );
    }

    // No numbered chapter list: keep the button usable as a plain restart.
    return ChapterContinueTarget(
      chapter:
          known ??
          Chapter(
            id: chapterId,
            title: history.chapterTitle ?? chapterId,
            url: chapterId,
          ),
      page: 1,
      mode: ChapterContinueMode.restart,
      chapterNumber: currentNumber,
    );
  }

  return null;
}

/// Chapter order as declared by its name: `Chapter 12`, `Bab 12.5`, `Ch. 3`,
/// `第12話`, or a bare leading number. Numeric (`2` < `10`), never lexical.
double? chapterNumberFromName(String name) =>
    ChapterOrderUtils.parseChapterNumber(name);

/// Readable chapters with a parsed number, ascending. Unnumbered and
/// unreadable chapters are dropped — they cannot be ordered by name.
List<(Chapter, double)> _orderedReadableChapters(List<Chapter> chapters) {
  final ordered = <(Chapter, double)>[];
  for (final chapter in chapters) {
    if (!chapter.isReadableInApp) continue;
    final number =
        chapterNumberFromName(chapter.title) ??
        chapterNumberFromName(chapter.url);
    if (number == null) continue;
    ordered.add((chapter, number));
  }
  ordered.sort((a, b) => a.$2.compareTo(b.$2));
  return ordered;
}

class ChapterContinueFab extends StatefulWidget {
  const ChapterContinueFab({
    super.key,
    required this.target,
    required this.onTap,
  });

  final ChapterContinueTarget target;
  final VoidCallback onTap;

  @override
  State<ChapterContinueFab> createState() => _ChapterContinueFabState();
}

class _ChapterContinueFabState extends State<ChapterContinueFab> {
  Offset? _position;

  Offset _clamp(Offset position, BoxConstraints constraints, EdgeInsets inset) {
    final minLeft = 8.0;
    final maxLeft = (constraints.maxWidth - _fabWidth - 8).clamp(
      minLeft,
      double.infinity,
    );
    final minTop = 8.0 + inset.top;
    final maxTop = (constraints.maxHeight - _fabHeight - 8 - inset.bottom)
        .clamp(minTop, double.infinity);
    return Offset(
      position.dx.clamp(minLeft, maxLeft),
      position.dy.clamp(minTop, maxTop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final target = widget.target;

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = MediaQuery.paddingOf(context);
        final defaultPosition = Offset(
          constraints.maxWidth - _fabWidth - 16,
          constraints.maxHeight - _fabHeight - 16 - inset.bottom,
        );
        final position = _clamp(
          _position ?? defaultPosition,
          constraints,
          inset,
        );

        return Stack(
          children: [
            Positioned(
              left: position.dx,
              top: position.dy,
              child: GestureDetector(
                onTap: widget.onTap,
                onPanUpdate: (details) => setState(
                  () => _position = _clamp(
                    position + details.delta,
                    constraints,
                    inset,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.45,
                        ),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.4,
                      ),
                    ),
                    child: SizedBox(
                      width: _fabWidth,
                      height: _fabHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            RepaintBoundary(
                              child: KuroMascot(
                                mood: target.mode == ChapterContinueMode.restart
                                    ? KuroMood.happy
                                    : KuroMood.reader,
                                size: 38,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _label(l10n),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _subtitle(l10n),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _label(AppLocalizations l10n) {
    final number = widget.target.chapterNumber;
    switch (widget.target.mode) {
      case ChapterContinueMode.resume:
        // Unnumbered chapter names fall back to a plain "Continue".
        return number == null
            ? l10n.continueReading
            : l10n.continueFromChapter(formatChapterNumber(number));
      case ChapterContinueMode.nextChapter:
        return number == null
            ? l10n.continueReading
            : l10n.continueToChapter(formatChapterNumber(number));
      case ChapterContinueMode.restart:
        return l10n.readerScreenGoToFirstPage;
    }
  }

  String _subtitle(AppLocalizations l10n) =>
      l10n.continuePageSubtitle(widget.target.page);
}
