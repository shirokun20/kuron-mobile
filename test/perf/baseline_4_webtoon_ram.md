# Baseline Area 4 — RAM translate webtoon full-strip (read-only, tanpa device)

Tanggal: 2026-11-18. Sumber: baca kode `lib/presentation/cubits/reader/reader_translation_cubit.dart`
+ aritmetika buffer (tanpa device). Tidak ada file repo yang diubah selain file ini.

## 1. Temuan jalur kode (nomor baris persis, file `lib/presentation/cubits/reader/reader_translation_cubit.dart`)

- Baris 30: `typedef HeavyRunner = Future<T> Function<T>(FutureOr<T> Function() computation);`
- Baris 48: default `_heavyRunner = heavyRunner ?? Isolate.run` — semua `_heavyRunner(...)` = worker isolate via `Isolate.run` (argumen di-copy antar isolate).
- Baris 712–716 (jalur webtoon di `translatePage`): `if (WebtoonDetector.isWebtoon(...))` lalu
  `final chunks = await _heavyRunner(() => _splitWebtoonIsolate(imageBytes, imageWidth, imageHeight));`
  → `await` mengembalikan **`List<_ImageChunk>` lengkap — semua chunk hidup sekaligus** (bukan streaming).
- Baris 719–734: `for (final chunk in chunks)` + baris 720 `emit(const ReaderTranslationDetecting())` **per chunk**
  + `await _detect(chunk.bytes, ...)` + akumulasi `allBoxes` dengan `offsetY += chunk.height` (baris 733).
- Baris 744–754: `_translateWithBubbles(imageBytes: imageBytes, ...)` menerima **strip FULL** (`imageBytes` asli, baris 745),
  bukan chunk — memori full strip tetap hidup setelah loop chunk.
- Baris 929–937 (di `_translateWithBubbles`, cabang mosaic): `buildMosaic(pageBytes=imageBytes FULL, ...)`
  via `_heavyRunner` → **decode full-strip ke-2** (transien, di worker isolate).
- Baris 1311–1324 `_splitWebtoonIsolate`: baris 1312 `img.decodeImage(bytes)` (**full decode RGBA**, di worker isolate);
  baris 1316 `maxHeight = 1280`; baris 1320 `img.copyCrop(decoded, ...)` (alokasi crop RGBA per chunk);
  baris 1321 `img.encodeJpg(crop, quality: 90)` → tiap chunk JPEG q90 diakumulasi di `chunks` list.
- Baris 989–998 `_flagFlatBubbles`: baris 992–994 `img.decodeImage(imageBytes)` **inline, tanpa `_heavyRunner`**.
  Dipanggil sinkron dari `_finish` (baris 1014), dan `_finish` dipanggil langsung dari `translatePage` (baris 755)
  → **jalan di thread utama (UI), bukan heavy runner**; = **decode full-strip ke-3** (transien, di main isolate → jank).
- Total decode full-strip per 1× translate webtoon sukses: **3×** (split worker + mosaic worker + flagFlat main thread).

## 2. Aritmetika bitmap (package:image decode → RGBA 8-bit = W × H × 4 byte)

| Strip (W×H) | Piksel | RGBA decoded | MiB (÷2²⁰) | MB desimal (÷10⁶) | Chunk ≤1280px (N=⌈H/1280⌉) |
|---|---|---|---|---|---|
| 1080×8000 | 8.640.000 | 34.560.000 B | **32,96 MiB** | **34,56 MB** | 7 (6×1280 + 320) |
| 1080×12000 | 12.960.000 | 51.840.000 B | **49,44 MiB** | **51,84 MB** | 10 (9×1280 + 480) |
| 1080×20000 | 21.600.000 | 86.400.000 B | **82,40 MiB** | **86,40 MB** | 16 (15×1280 + 800) |

Transien tambahan per chunk saat encode: satu crop RGBA 1080×1280×4 = **5,53 MB (5,27 MiB)**.

## 3. Komposisi peak estimasi (1080×12000 sebagai acuan)

Asumsi JPEG (tidak dari kode — kode tidak mencatat ukuran tipikal): strip asli J ≈ 2–4 MB;
chunk JPEG q90 foto ≈ 0,3–0,5 MB → Σ 10 chunk ≈ 3–5 MB (≈ 1,0–1,5× J karena re-encode q90).

- **Worker isolate (selama `_splitWebtoonIsolate`)**: RGBA full 51,8 MB + JPEG input (salinan `Isolate.run`, +J)
  + crop transien 5,5 MB + N chunk JPEG yang terakumulasi (±3–5 MB) → **≈ 60–65 MB transien**.
- **Main isolate (selama loop detect, baris 719–734)**: JPEG asli J + SEMUA N chunk JPEG (±3–5 MB) → **≈ 5–9 MB steady**,
  lalu `_translateWithBubbles` + `_finish`/`_flagFlatBubbles` menambah decode RGBA ke-2 (worker) dan ke-3 (main, +51,8 MB transien di UI thread).
- Kunci dari kode: `await _heavyRunner(...) → List` (baris 714) berarti tidak ada streaming —
  `decoded` full + semua chunk encoded hidup bersamaan di worker; `chunks` list + `imageBytes` full hidup bersamaan di main.

## 4. Gap vs target proposal (puncak < 20 MB untuk 1080×12000)

- Decoded RGBA saja = **51,84 MB** → **kelebihan +31,84 MB (≈ 2,59× target)**.
- Peak transien worker (≈ 60–65 MB) → **kelebihan ≈ +40–45 MB (≈ 3,0–3,3× target)**.
- Steady main isolate (JPEG + chunks, ≈ 5–9 MB) SAJA yang di bawah 20 MB — setiap decode RGBA full melanggar target.
- Implikasi: target < 20 MB **tidak tercapai** selama ada `decodeImage` full-strip (3× per translate);
  perlu streaming/decode bertahap per chunk tanpa memegang bitmap full (pekerjaan optimasi, di luar baseline ini).

## 5. Test terkait di `test/` (hanya dicatat, tidak diubah)

- `test/unit/presentation/reader_translation_cubit_test.dart` — cubit translate (cek ada/tidaknya kasus webtoon di sini saat optimasi).
- `test/unit/data/mosaic_builder_test.dart` — mosaic builder (decode full-strip ke-2).
- `test/unit/data/ai_preferences_mosaic_test.dart` — preferensi kualitas mosaic.
- `test/unit/data/image_pipeline_native_test.dart` — pipeline image.
- Tidak ada test baseline RAM webtoon saat file ini ditulis (`test/perf/` sebelumnya tidak ada).

## 6. Cara re-run validasi aritmetika

File Dart murni (tanpa flutter, hanya aritmetika buffer), sudah dijalankan sekali — output persis tabel §2:

```bash
dart /tmp/a4/calc.dart
# 1080 x 8000:  ... = 32.96 MiB / 34.56 MB; chunks=7; ...
# 1080 x 12000: ... = 49.44 MiB / 51.84 MB; chunks=10; ...
# 1080 x 20000: ... = 82.40 MiB / 86.40 MB; chunks=16; ...
# gap12000_MB=31.84 ratio=2.59x
```

Isi `/tmp/a4/calc.dart`: loop `w=1080, h in [8000,12000,20000]`, `rgba = w*h*4`,
`mib = rgba/2^20`, `mb = rgba/1e6`, `n = ceil(h/1280)`, plus `gap = 1080*12000*4/1e6 − 20`.
Re-run tidak butuh device, network, atau `flutter pub get`. Catatan: file `/tmp` di luar repo, tidak di-commit.
