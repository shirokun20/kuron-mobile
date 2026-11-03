// Decode pre-cache queue for the reader (4.2 regression gate).
//
// The widget enqueues BuildContext-bound decode tasks (precacheImage needs a
// context) and drains at most N per frame tick. Whenever the queue is dropped
// — dispose, chapter change, or a large page jump (>3 pages) — the generation
// is bumped so already-dequeued tasks that are still awaiting their
// `getLocalImagePath` future observe staleness and skip `precacheImage`
// instead of decoding pages the user has already left behind.
class ReaderDecodeQueue {
  final List<ReaderDecodeTask> _entries = [];
  int _generation = 0;

  /// Current generation; bumped by every [clear].
  int get generation => _generation;

  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;
  int get length => _entries.length;

  /// Large-jump threshold shared with the reader widget: a jump bigger than
  /// this many pages drops the queue.
  static const int largeJumpThreshold = 3;

  static bool isLargeJump(int lastReportedPage, int currentPage) =>
      (currentPage - lastReportedPage).abs() > largeJumpThreshold;

  /// Enqueues [task], stamped with the current generation.
  void enqueue(void Function() task) {
    _entries.add(ReaderDecodeTask(generation: _generation, run: task));
  }

  /// Drops all pending tasks and bumps the generation so in-flight tasks
  /// observe staleness via [isStale].
  void clear() {
    _entries.clear();
    _generation++;
  }

  /// Pops the next task, or null when empty.
  ReaderDecodeTask? pop() => isEmpty ? null : _entries.removeAt(0);

  /// True when [task] was stamped before the latest [clear].
  bool isStale(ReaderDecodeTask task) => task.generation != _generation;
}

/// A single queued decode task with its enqueue-time generation stamp.
class ReaderDecodeTask {
  const ReaderDecodeTask({required this.generation, required this.run});
  final int generation;
  final void Function() run;
}
