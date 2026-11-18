# Baseline Area 3 — durasi prefetch spekulatif per halaman (read-only dari kode)

Tanggal: 2026-11-18. Sumber: komentar/konstanta kode, TANPA device (angka ~2.6 dtk adalah klaim komentar kode, bukan hasil ukur profiler).

## 1. Angka ringkas

| Item | Nilai | Sumber |
|---|---|---|
| 1 run ONNX detect per halaman | ~2.6 dtk | `reader_translation_cubit.dart:90`, `:769`, `:777` (komentar, bukan konstanta) |
| Busy-wait maks translate-vs-prefetch | 5.0 dtk = 50 × 100 ms | `reader_translation_cubit.dart:777-780` |
| Gate berbasis intent translate | TIDAK ADA | `reader_mode_widgets.dart:249-255` + 6 call-site di bawah |

## 2. Kondisi pemicu saat ini (nol gate intent)

- Penjadwalan: idle-timer 600 ms pasca aktivitas terakhir, fire saat gambar settle (spec 2.2):
  `lib/presentation/pages/reader/reader_mode_widgets.dart:249-255`:
  ```dart
  void _schedulePrefetchDetection() {
    _prefetchIdleTimer?.cancel();
    _prefetchIdleTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _translationCubit.prefetchDetection();
    });
  }
  ```
  Komentar spec di `:246-248`: "fire 600ms after the last scroll/page-change when the image has settled (spec 2.2). The cubit itself skips when busy / memory-pressured (spec 2.3)."
- 6 call-site — semuanya tanpa cek intent translate (halaman tanpa rencana translate tetap membayar 1 run ONNX):
  - `:312` — `onPageChanged` (horizontal/single page) + `resetPage()` tepat sebelumnya (`:311`)
  - `:388` — `onPageChanged` (varian mode baca kedua)
  - `:477` — tiap `ScrollUpdateNotification` (continuous scroll)
  - `:916`, `:961`, `:995` — tiap selesai capture viewport/page (`capturePage` path)
- Gate yang ADA (semua non-intent, di cubit): `_prefetchBlocked()` (`reader_translation_cubit.dart:104-123`) — skip bila `_prefetchRunning || _drawMode` (`:105`), pipeline sibuk (`Detecting/BuildingMosaic/Translating/TranslatingBubble`, `:106-110`), atau low-RAM (`:112-119`); plus skip cache-hit (`:276-279`) dan skip bila `_detectedBoxes` sudah ada (`:280-287`). Tidak satu pun memeriksa apakah user akan menekan Translate.

## 3. Jalur prefetch / biaya tabrakan

- Prefetch = `prefetchDetection()` (`reader_translation_cubit.dart:268-314`): `if (_prefetchBlocked()) return;` (`:269`), lalu `await _detect(bytes, ...)` = `KuronNative.instance.detectBubbles` (`:857-864`) — 1 inferensi ONNX penuh per halaman.
- Klaim durasi (komentar, bukan timer): `:89-90` "so the Translate tap skips the 2.6s ONNX wait", `:768-769` "skip the 2.6s ONNX wait (spec 2.4)", `:777` "5s covers the ~2.6s ONNX run".
- Tabrakan: bila Translate ditekan saat prefetch mid-run, `translatePage` TIDAK re-run `_detect` paralel (alasan: "same Kotlin executor AND the same OrtSession (not thread-safe)", `:770-773`) melainkan poll-wait (`:774-781`):
  ```dart
  if (_prefetchRunning) {
    ...
    // Bounded wait: 5s covers the ~2.6s ONNX run; past that, proceed
    // with our own detect rather than hang forever.
    for (var i = 0; i < 50 && _prefetchRunning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  ```
  Biaya tabrakan worst-case: s.d. 5 dtk stall SEBELUM reuse-check (`:790-792`) / re-detect (`:803-804`). Bila halaman berganti saat menunggu → translate abort (`:782-787`).
- Reuse bila prefetch selesai tepat waktu: `_prefetchedBoxes` + `_prefetchKey == _capturedPageSignature` → pakai tanpa re-detect (`:790-797`); stale/empty → re-detect penuh (`:798-813`), empty prefetch sengaja tidak di-cache (`:293-305`).

## 4. Test terkait di `test/`

- `test/unit/presentation/reader_translation_cubit_test.dart` — group `T2 detection prefetch` (`:722+`), mengukur JUMLAH panggilan ONNX (`detectCalls` via mock `MethodChannel('kuron_native')` / `detectBubbles`, `:17-37`), BUKAN durasi/wall-clock:
  - `:723` reuse prefetch → `expect(detectCalls, 1)` (prefetch 1×, translate 0×)
  - `:754` prefetch kosong tidak di-reuse → `expect(detectCalls, 2)`
  - `:815` signature capture beda → stale → `expect(detectCalls, 2)`
  - `:870+`, `:890`, `:922`, `:936`, `:959` — varian cache/draw-mode/satellite reuse (semua assertion hitungan panggilan)
- `test/unit/presentation/reader_prefetch_cubit_test.dart` — prefetch GAMBAR (ReaderPrefetchCubit, `prefetchImages`), bukan deteksi ONNX; fast-path URL non-http. Tidak relevan untuk angka Area 3.
- `test/unit/reader/reader_jank_regression_test.dart` — jank download/paused-manager + `ReaderPrefetchCubit` per-window cancellation (`:418+`); tidak mengukur durasi ONNX detect.

## 5. Cara re-run / verifikasi ulang (tanpa device)

```bash
# Klaim durasi ONNX (~2.6s) — hanya ada di komentar:
rg -n "2\.6" lib/presentation/cubits/reader/reader_translation_cubit.dart
# → baris 90, 769, 777
# Busy-wait bound:
rg -n "Bounded wait|_prefetchRunning|100ms|spec 2" lib/presentation/cubits/reader/reader_translation_cubit.dart
# → 774-781 (+ flag di 96, set 288/312, gate 105,269)
# Trigger tanpa gate intent:
rg -n "_schedulePrefetchDetection" lib/presentation/pages/reader/reader_mode_widgets.dart
# → definisi 249-255, call-site 312, 388, 477, 916, 961, 995
# Test hitungan panggilan (bukan durasi):
fvm flutter test test/unit/presentation/reader_translation_cubit_test.dart
```
