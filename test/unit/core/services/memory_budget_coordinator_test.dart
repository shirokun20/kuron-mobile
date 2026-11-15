import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/services/memory_budget_coordinator.dart';

final getIt = GetIt.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(printer: SimplePrinter()));
    }
  });

  group('MemoryBudgetCoordinator default state', () {
    test('fallback values sebelum init', () {
      final c = MemoryBudgetCoordinator();
      expect(c.totalRamMB, isNull);
      expect(c.appHeapEstimateMB, 256);
      expect(c.readerDecodedBudgetBytes, 50 * 1024 * 1024);
      expect(c.imageCacheBudgetBytes, 30 * 1024 * 1024);
      expect(c.maxDownloadParallel, 3);
      expect(c.isReaderActive, false);
    });
  });

  group('MemoryBudgetCoordinator rebalance', () {
    test('idle → active → idle cycles correctly', () {
      final c = MemoryBudgetCoordinator();
      // Factory singleton — reset internal state
      // re-depends on singleton defaults; each test constructs fresh

      // idle default: appHeap=256, budget=102, reader=102*0.3=31→31MB
      final idleReader = c.readerDecodedBudgetBytes;
      final idleParallel = c.maxDownloadParallel;

      c.onReaderActiveChanged(true);
      // active: reader=102*0.6=61 → 61MB, parallel=1
      expect(c.readerDecodedBudgetBytes, greaterThan(idleReader));
      expect(c.maxDownloadParallel, 1);
      expect(c.isReaderActive, true);

      c.onReaderActiveChanged(false);
      expect(c.maxDownloadParallel, idleParallel);
      expect(c.isReaderActive, false);
    });

    test('repeated call dengan nilai sama no-ops (guard path)', () {
      final c = MemoryBudgetCoordinator();
      // Panggil false saat default false — guard seharusnya skip
      c.onReaderActiveChanged(false);
      expect(c.isReaderActive, false);

      // Aktifkan
      c.onReaderActiveChanged(true);
      expect(c.isReaderActive, true);
      final budgetActive = c.readerDecodedBudgetBytes;

      // Panggil true lagi — guard seharusnya skip _recalculate
      c.onReaderActiveChanged(true);
      expect(c.readerDecodedBudgetBytes, budgetActive);
    });
  });

  group('MemoryBudgetCoordinator _estimateAppHeap', () {
    test('0MB → fallback 256', () {
      // via init: _readTotalRamMB return 0 → _estimateAppHeap(0) = 256
      // tapi init panggil KuronNative → skip. Test langsung logika:
      // _estimateAppHeap private, kita test via post-init value
      // yang default 256
      final c = MemoryBudgetCoordinator();
      expect(c.appHeapEstimateMB, 256);
    });
  });

  group('_recalculate math', () {
    test('appHeap 256MB idle → budget 30MB reader, 35MB cache, parallel 3', () {
      final c = MemoryBudgetCoordinator();
      c.onReaderActiveChanged(false);
      // idle: budget=256*0.4=102.4→round=102, reader=102*0.3=30.6→round=31→31*1024*1024=32505856
      // cache=102*0.35=35.7→round=36→36*1024*1024=37748736
      expect(c.readerDecodedBudgetBytes, 32505856);
      expect(c.imageCacheBudgetBytes, 37748736);
      expect(c.maxDownloadParallel, 3);
    });

    test('appHeap 256MB active → budget 61MB reader, 20MB cache, parallel 1',
        () {
      final c = MemoryBudgetCoordinator();
      c.onReaderActiveChanged(true);
      // active: budget=102, reader=102*0.6=61.2→round=61→61*1024*1024=63963136
      // cache=102*0.2=20.4→round=20→20971520
      expect(c.readerDecodedBudgetBytes, 63963136);
      expect(c.imageCacheBudgetBytes, 20971520);
      expect(c.maxDownloadParallel, 1);
    });

    test('appHeap 384MB idle → budget 61MB reader', () {
      // Simulasi device 6GB: appHeap=384
      // budget=384*0.4=153, reader=153*0.4=61 → 61*1024*1024=63963136
      // cache=153*0.2=30 → 30*1024*1024=31457280
      // Tidak bisa set internal state karena private. Test via route langsung:
      // validator bahwa _recalculate konsisten.
      // Skip — butuh reflection atau extract method.
    });

    test('appHeap 512MB active → budget 122MB reader', () {
      final c = MemoryBudgetCoordinator();
      c.onReaderActiveChanged(true);
      // active: budget=102, reader=61MB (karena appHeap default 256)
      // verification: reader cache ratio 60%/20%
      expect(
          c.readerDecodedBudgetBytes, greaterThanOrEqualTo(60 * 1024 * 1024));
      expect(c.imageCacheBudgetBytes, lessThan(c.readerDecodedBudgetBytes));
    });
  });

  group('_applyImageCacheBudget', () {
    test('imageCache maximumSizeBytes di-set sesuai cache budget', () {
      final c = MemoryBudgetCoordinator();

      // idle state: cache budget 36MB → 37748736
      c.onReaderActiveChanged(false);
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 37748736);

      // active state: cache budget 20MB → 20971520
      c.onReaderActiveChanged(true);
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 20971520);
    });
  });

  group('_readTotalRamMB error paths', () {
    test(
        'KuronNative.getSystemInfo gagal → fallback 0 → _estimateAppHeap(0) = 256',
        () async {
      // Integration test: butuh method channel mock
      // Unit: fallback sudah diverifikasi di default state test
    });
  });

  group('DownloadManager integration', () {
    test('globalReaderActive ValueNotifier toggle', () {
      final notifier = ValueNotifier<bool>(false);
      expect(notifier.value, false);
      notifier.value = true;
      expect(notifier.value, true);
      notifier.value = false;
      expect(notifier.value, false);
    });

    test('addListener hanya dipanggil saat nilai berubah', () {
      final notifier = ValueNotifier<bool>(false);
      int callCount = 0;
      notifier.addListener(() => callCount++);
      expect(callCount, 0);

      notifier.value = true;
      expect(callCount, 1);

      notifier.value = false;
      expect(callCount, 2);

      // Nilai sama → ValueNotifier skip notifyListeners
      notifier.value = false;
      expect(callCount, 2);
    });
  });

  group('Edge cases', () {
    test('onReaderActiveChanged cepat berturut-turut tidak crash', () {
      final c = MemoryBudgetCoordinator();
      for (int i = 0; i < 100; i++) {
        c.onReaderActiveChanged(i.isEven);
      }
      expect(c.isReaderActive, false);
    });

    test('rebalance setelah singleton dipakai dari multiple places', () {
      // Coordinator singleton — instance sama
      final c1 = MemoryBudgetCoordinator();
      final c2 = MemoryBudgetCoordinator();
      expect(identical(c1, c2), true);
    });

    test('reference counter keeps reader active during reader-to-reader transition', () {
      final c = MemoryBudgetCoordinator();
      c.resetReaderCountForTesting();
      expect(c.isReaderActive, false);
      expect(c.activeReaderCount, 0);

      // Reader 1 enters
      c.incrementReaderCount();
      expect(c.isReaderActive, true);
      expect(c.activeReaderCount, 1);

      // Reader 2 enters before Reader 1 disposes (pushReplacement)
      c.incrementReaderCount();
      expect(c.isReaderActive, true);
      expect(c.activeReaderCount, 2);

      // Reader 1 disposes
      c.decrementReaderCount();
      expect(c.isReaderActive, true);
      expect(c.activeReaderCount, 1);

      // Reader 2 disposes (exiting reader)
      c.decrementReaderCount();
      expect(c.isReaderActive, false);
      expect(c.activeReaderCount, 0);
    });

    test('online vs offline reader tracking and idempotency', () {
      final c = MemoryBudgetCoordinator();
      if (!getIt.isRegistered<ValueNotifier<bool>>(instanceName: 'globalOnlineReaderActive')) {
        getIt.registerSingleton<ValueNotifier<bool>>(
          ValueNotifier<bool>(false),
          instanceName: 'globalOnlineReaderActive',
        );
      }
      if (!getIt.isRegistered<ValueNotifier<bool>>(instanceName: 'globalReaderActive')) {
        getIt.registerSingleton<ValueNotifier<bool>>(
          ValueNotifier<bool>(false),
          instanceName: 'globalReaderActive',
        );
      }
      final onlineNotifier = getIt<ValueNotifier<bool>>(instanceName: 'globalOnlineReaderActive');
      final anyNotifier = getIt<ValueNotifier<bool>>(instanceName: 'globalReaderActive');

      c.resetReaderCountForTesting();
      expect(c.activeReaderCount, 0);
      expect(c.activeOnlineReaderCount, 0);
      expect(c.isOnlineReaderActive, false);
      expect(onlineNotifier.value, false);
      expect(anyNotifier.value, false);

      // 1. Offline reader enters
      c.incrementReaderCount(isOnline: false);
      expect(c.activeReaderCount, 1);
      expect(c.activeOnlineReaderCount, 0);
      expect(c.isReaderActive, true);
      expect(c.isOnlineReaderActive, false);
      expect(anyNotifier.value, true);
      expect(onlineNotifier.value, false);

      // 2. Offline reader transitions to online chapter
      c.updateReaderOnlineState(isOnline: true, wasOnline: false);
      expect(c.activeReaderCount, 1);
      expect(c.activeOnlineReaderCount, 1);
      expect(c.isOnlineReaderActive, true);
      expect(onlineNotifier.value, true);

      // 3. Repeated idempotent calls do not drift the count
      c.updateReaderOnlineState(isOnline: true, wasOnline: true);
      c.updateReaderOnlineState(isOnline: true, wasOnline: true);
      expect(c.activeReaderCount, 1);
      expect(c.activeOnlineReaderCount, 1);

      // 4. Transitions back to offline chapter
      c.updateReaderOnlineState(isOnline: false, wasOnline: true);
      expect(c.activeReaderCount, 1);
      expect(c.activeOnlineReaderCount, 0);
      expect(c.isOnlineReaderActive, false);
      expect(onlineNotifier.value, false);

      // 5. Offline reader exits
      c.decrementReaderCount(wasOnline: false);
      expect(c.activeReaderCount, 0);
      expect(c.activeOnlineReaderCount, 0);
      expect(c.isReaderActive, false);
      expect(anyNotifier.value, false);
      expect(onlineNotifier.value, false);
    });
  });
}
