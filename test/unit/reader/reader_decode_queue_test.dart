import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/reader/decode_queue.dart';

// 4.2 verification: clearing the decode queue on large jumps.
//
// A full ReaderScreen pump harness is infeasible here (the screen requires a
// loaded ReaderCubit + chapter content + source registry + getIt graph), so
// the queue + generation policy the widget drives is verified directly: the
// widget calls `isLargeJump`/`clear` on jumps and skips stale tasks before
// `precacheImage`, which this test simulates faithfully.
void main() {
  test('jump 5->20 is large; 6..8 recognized as skipped pages', () {
    expect(ReaderDecodeQueue.isLargeJump(5, 20), true);
    expect(ReaderDecodeQueue.isLargeJump(5, 7), false);
    expect(ReaderDecodeQueue.isLargeJump(5, 8), false);
    expect(ReaderDecodeQueue.isLargeJump(20, 5), true);
  });

  test('large jump: no precache issued for pages 6-7', () {
    final queue = ReaderDecodeQueue();
    final precachedPages = <int>[];

    // Widget enqueued decode tasks for pages 6 and 7 while on page 5.
    for (final page in [6, 7]) {
      final gen = queue.generation;
      queue.enqueue(() {
        // Same guard the widget's decode closure applies before precacheImage.
        if (gen != queue.generation) return;
        precachedPages.add(page);
      });
    }
    expect(queue.length, 2);

    // User jumps 5 -> 20: widget clears the queue, bumping the generation.
    expect(ReaderDecodeQueue.isLargeJump(5, 20), true);
    queue.clear();

    // Frame tick drains: stale tasks are skipped, never run.
    while (queue.isNotEmpty) {
      final task = queue.pop()!;
      if (queue.isStale(task)) continue;
      task.run();
    }
    expect(precachedPages, isEmpty,
        reason: 'no precache may be issued for pages 6-7 after jump to 20');
  });

  test('overlapping pages enqueued after the jump still decode', () {
    final queue = ReaderDecodeQueue();
    final precachedPages = <int>[];
    queue.enqueue(() => precachedPages.add(6));
    queue.clear(); // jump 5 -> 20

    // New tasks for pages around 20 run normally.
    for (final page in [19, 21]) {
      final gen = queue.generation;
      queue.enqueue(() {
        if (gen != queue.generation) return;
        precachedPages.add(page);
      });
    }
    while (queue.isNotEmpty) {
      final task = queue.pop()!;
      if (queue.isStale(task)) continue;
      task.run();
    }
    expect(precachedPages, [19, 21]);
  });
}
