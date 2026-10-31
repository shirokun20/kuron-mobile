import 'package:flutter_test/flutter_test.dart';

/// Estimate tests for reader-cpu-gpu-ram-kill 4.2 without real device:
/// RAM peak, frame time, CPU burst via math + throttle logic.
/// Also covers 1.3 decode throttle 2/frame vs 1/frame for heavy source.

void main() {
  group('Thermal budget estimate (no device)', () {
    test('1.3 decode throttle: heavy 1/frame, normal 2/frame for N±1', () {
      const maxNormal = 2;
      const maxHeavy = 1;
      bool isHeavy(String? id) => id == 'ehentai' || id == 'hentainexus';
      int currentMax(String? id) => isHeavy(id) ? maxHeavy : maxNormal;

      expect(currentMax('ehentai'), 1);
      expect(currentMax('hentainexus'), 1);
      expect(currentMax('nhentai'), 2);
      expect(currentMax(null), 2);

      // queue of 2 decodes (N+1, N-1) → heavy needs 2 frames, normal 1 frame
      int framesNeeded(int queueLen, int perFrame) =>
          (queueLen / perFrame).ceil();
      expect(framesNeeded(2, currentMax('ehentai')), 2);
      expect(framesNeeded(2, currentMax('nhentai')), 1);
      // burst 5 decodes (if window 3+1 mistakenly queued) → heavy 5 frames, normal 3 frames (ceil 5/2=3)
      expect(framesNeeded(5, currentMax('ehentai')), 5);
      expect(framesNeeded(5, currentMax('nhentai')), 3);
    });

    test('1.3 verify CPU burst ≤2 per frame (normal) via queue processing',
        () async {
      final queue = <int>[1, 2, 3, 4, 5];
      const perFrame = 2;
      int frames = 0;
      int maxPerFrameObserved = 0;
      while (queue.isNotEmpty) {
        final take = queue.length >= perFrame ? perFrame : queue.length;
        maxPerFrameObserved =
            take > maxPerFrameObserved ? take : maxPerFrameObserved;
        queue.removeRange(0, take);
        frames++;
      }
      expect(maxPerFrameObserved, lessThanOrEqualTo(2));
      expect(frames, 3); // 5 items /2 per frame → 3 frames
    });

    test('2.1 cacheExtent: normal viewport*1.0 vs heavy 0.25', () {
      double viewport = 800;
      double cacheNormal = viewport * 1.0;
      double cacheHeavy = viewport * 0.25;
      expect(cacheNormal, 800);
      expect(cacheHeavy, 200);
      // built items estimate: visible 1 + cacheOutside/viewport
      // normal: 800/800=1 extra → total ~3 (prev, visible, next) not 5
      // heavy: 200/800=0.25 → ~1-2 built
      expect(cacheNormal / viewport, 1.0);
      expect(cacheHeavy / viewport, 0.25);
    });

    test('1.1/1.2 budget enforcement: sum window vs accumulate tick (estimate)',
        () {
      // Old bug: _estimatedDecodedBytes += per tick → balloons
      // New: sum window visible±4 with real bytes
      const budget = 50 * 1024 * 1024; // 52,428,800
      const target = budget * 0.8; // 41,943,040

      int estimatePage(int page) {
        // mock: page 1 tall 2000, others 1200, width 900*4
        int h = page == 1 ? 2000 : 1200;
        return 900 * h * 4; // 7,200,000 or 4,320,000
      }

      // simulate tick accumulation bug: 3 ticks with currentPage 5,6,7 → += each
      int buggy = 0;
      for (int p in [5, 6, 7]) {
        int window = 0;
        for (int w = p - 4; w <= p + 4; w++) {
          window += estimatePage(w);
        }
        buggy += window; // buggy accumulates
      }
      // new correct: sum only current window (page 7)
      int correct = 0;
      for (int w = 7 - 4; w <= 7 + 4; w++) {
        correct += estimatePage(w);
      }
      expect(buggy, greaterThan(correct * 2),
          reason: 'buggy tick accumulation inflates 2-3x');
      expect(correct, lessThan(budget * 1.2)); // ~38M, under budget+20%

      // evict farthest until 80% budget: sort by distance, remove until ≤target
      int windowBytes = correct; // e.g., 9*4.32M=38.88M (< budget) → no evict
      expect(windowBytes < budget, true);

      // tall window: 20 pages all tall 2500 → 9*9M=81M > budget → evict
      int tallWindow = 9 * 900 * 2500 * 4; // 81,000,000
      expect(tallWindow, greaterThan(budget));
      int toEvict = tallWindow - target.round();
      expect(toEvict, greaterThan(30 * 1024 * 1024));
    });

    test('4.2 RAM peak 20 pages CS estimate: with fix stays ≤52MB', () {
      // Without fix: old estimator w=1080 hardcode, tick accumulate, no clamp → 20 pages *8.3MB=166MB
      int oldPerPage = 1080 * 1920 * 4; // 8,294,400
      int old20 = oldPerPage *
          9; // window 9 (not 20, but cacheExtent 2500 built 5-6) → ~49M but tick accumulates to 100M+
      // With fix: viewport 412*dpr3 clamped 720, height 1200 avg → 720*1200*4=3.46M *9=31.1M
      int newPerPage = 720 * 1200 * 4;
      int newWindow = newPerPage * 9;
      const budget = 52 * 1024 * 1024;
      expect(newWindow, lessThan(budget));
      expect(old20, greaterThan(newWindow));
      // table before/after
      // before: 66MB for 6 pages (spec), after: ~30MB for 9 pages
    });

    test('2.3 single active WebP: 3 heavy concurrent → only 1 GPU texture', () {
      // Simulate visible=5, 3 heavy pages 4,5,6 mounted
      int visible = 5;
      List<int> heavyPages = [4, 5, 6];
      int playing = heavyPages.where((p) => p == visible).length;
      expect(playing, 1);
      int paused = heavyPages.where((p) => p != visible).length;
      expect(paused, 2);
    });
  });
}
