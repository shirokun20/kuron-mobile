# Reader Thermal / Battery / Memory QA Checklist (issue #88)

Manual physical-device protocol that must pass after the core-network rework
(`3dd541fe`: `CancelToken` plumbing, home/download idle-churn elimination,
retry caps, RegExp caching) and before any sideload release (see also
`scripts/qa_verify_release_apk.sh` for the automated binary gates).

Run on **two devices minimum**: one low-end (≤4GB RAM, e.g. Android Go) and
one mid-range. Same build, same account state, airplane-mode baseline first.

## 1. Stress: 100 chapter flips (request-cancellation proof)

1. Open a manga source with full chapters (e.g. komiktap/komiku family).
2. Flip **forward 50 chapters then back 50** as fast as the UI allows
   (do not wait for images).
3. Expected:
   - No `DioException` surfacing in UI (cancellation maps to silent abort via
     `OperationCancelledException` → `ContentBloc`), no stuck loading spinners.
   - `adb logcat | grep -i "dio\|leak\|cancel"` shows cancels, not timeouts.
   - App stays responsive; back-navigation never hangs.

## 2. Memory: Dart VM heap + RSS Native (< 200MB, no creep)

1. Connect DevTools (memory view) or Android Studio Profiler.
2. Baseline: cold start → home → record **Dart heap + RSS**.
3. Open a 4K/WebP-heavy chapter, scroll end-to-end 3×, close reader, force
   back to home. Repeat 5×.
4. Expected:
   - Post-GC Dart heap returns to **≤ baseline + 20MB** every cycle.
   - RSS native stays **< 200MB** (reader image cache /
     `reader_image_resolver.dart` must evict; no monotonic creep).
   - No `ImageCache` live-image growth across cycles in DevTools.

## 3. Thermal + battery: 30-minute continuous read

1. Charge to 100%, unplug, brightness 50%, kill background apps.
2. Continuous-scroll read for **30+ minutes** (auto-advance or slow scroll).
3. Sample every 10 min: battery % (`adb shell dumpsys battery`), skin temp
   (`adb shell cat /sys/class/thermal/thermal_zone*/temp` or touch check),
   dropped frames (DevTools performance overlay).
4. Expected:
   - Battery drain **≤ 8% / 30 min** on mid-range (flag > 12%).
   - No thermal-throttling toast/visible clock-down; back cover warm, not hot.
   - **99% frame raster time ≤ 16.6ms** (stable 60 FPS, no sustained jank).

## 4. Automated gates (run first — fail fast)

```bash
# Binary gates: 16KB ELF, zipalign, v2/v3 signature, sha256 + Obtainium name
./scripts/qa_verify_release_apk.sh apk-output/kuron_<ver>_<date>_release_universal.apk
```

`sha256sum.txt` (auto-generated next to the APK) is what Obtainium tracks —
verify the file name + version embedded in the APK name match the GitHub
release assets before publishing.

## 5. Sign-off

| Device | SoC/RAM | 100-flip | Heap/RSS | 30-min drain | 60 FPS | QA |
|---|---|---|---|---|---|---|
| low-end | | ☐ | ☐ | ☐ | ☐ | |
| mid-range | | ☐ | ☐ | ☐ | ☐ | |

All boxes checked + `qa_verify_release_apk.sh` green + 24-source sweep
(`test/integration/sources_sweep_smoke_test.dart`, `@Tags(['live'])`) green
→ release may ship.
