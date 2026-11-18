# Baseline Area 2 — Waktu download chapter serial vs target konkuren-3

> Read-only + scratch. Tanpa network. Tanpa git commit.
> Tanggal: 2026-11-18. Sumber kode: `lib/core/services/download_service.dart`.

## 1. Loop serial yang diukur (kutipan baris persis)

`lib/core/services/download_service.dart`:

- L134: `for (int pageNum = actualStartPage; pageNum <= actualEndPage; pageNum++) {`
- L135: `final i = pageNum - 1; // Convert to 0-based index for imageUrls array`
- L137–143: cek cancel **hanya di awal iterasi** (`if (cancelToken?.isCancelled == true) throw ...`)
- L146–156: `while (DownloadManager().isPaused(content.id))` + `await Future.delayed(const Duration(seconds: 1))`
  (cek cancel saat pause di L149–150)
- L158: `final imageUrl = content.imageUrls[i];`
- L163–164: `fileName = 'page_...jpg'`, `filePath = path.join(...)`
- L167–190: skip file yang sudah ada (`continue`, tanpa network)
- L192–201: `await _downloadSingleImage(sourceId: ..., imageUrl: ..., filePath: ..., cancelToken: ..., timeoutDuration: ..., cookies: ...)`
- L203–223: progress + `downloadedCount++`
- L224–229:
  ```dart
  } catch (e, stackTrace) {
    _logger.e('Failed to download page $pageNum: $e and $stackTrace');
    // Continue with next image instead of failing completely,
    // but we will catch the discrepancy at the end.
    continue;
  }
  ```

Karakterisasi dari KODE (tanpa network):

- **SERIAL murni**: satu `await _downloadSingleImage(...)` per iterasi di dalam `for` — tidak ada
  `Future.wait`, tidak ada pool/semaphore, tidak ada batch paralel.
  Maka `T_total ≈ Σ t_gambar` (plus `Future.delayed(1s)` per iterasi saat pause aktif).
- **Head-of-line blocking**: 1 gambar lambat/timeout men-stall seluruh chapter karena iterasi
  berikutnya tidak dimulai sebelum `await` saat ini selesai/fail. `catch { continue; }`
  hanya mencegah gagal total — waktu stall tetap dibayar penuh, diskrepansi baru ketahuan
  di fase verifikasi (L232+).
- Cancel tidak preemptif di tengah `await` download — hanya dicek di awal iterasi (L138)
  dan saat pause (L149–150).

## 2. Timeout per gambar (batas atas stall) + sumbernya

| Jalur | Nilai default | Sumber baris |
|---|---|---|
| `UserPreferences.timeoutDurationSeconds` | **300** (detik) | `lib/domain/entities/user_preferences.dart:86`, getter `timeoutDuration` (~L368), parse default 300 (~L485) |
| `DownloadSettings.timeoutDuration` (bloc state) | `const Duration(minutes: 5)` | `lib/presentation/blocs/download/download_state.dart:247` |
| `DownloadBloc._settings.timeoutDuration` | `userPrefs.timeoutDuration` (300 s bawaan) | `lib/presentation/blocs/download/download_bloc.dart:589` (juga L1393, L2443 via event) |
| `DownloadEvent.timeoutDuration` | opsional, nullable | `lib/presentation/blocs/download/download_event.dart:209,221` |
| `DownloadContentUseCase` → `downloadContent(timeoutDuration:)` | teruskan (atau bawaan use-case bila null) | `lib/domain/usecases/downloads/download_content_usecase.dart:105,147,309,325,350,367,383,432,446` |
| `DownloadService.downloadContent({timeoutDuration})` → `_downloadSingleImage(timeoutDuration:)` | teruskan | `lib/core/services/download_service.dart:45` → L199 |
| `_downloadSingleImage`: bila `timeoutDuration != null` → Dio baru dengan `connectTimeout = receiveTimeout = sendTimeout = timeoutDuration` | **300 s** bila override pengaturan mengalir | `lib/core/services/download_service.dart:364,368-379` |
| Bila `timeoutDuration == null` → `_httpClient` bersama | **30 s** (`connect/receive/sendTimeout`) | `lib/core/network/http_client_manager.dart:62-65` |

**Kesimpulan**: batas atas stall per gambar = **300 s** (jalur normal, default pengaturan pengguna)
atau **30 s** (bila override null dan Dio bersama dipakai). Timeout bukan percepatan —
ia hanya memotong stall terburuk; kasus 1-timeout di tabel memakai kedua angka ini.

## 3. Model waktu + tabel baseline (N = 200 halaman)

Model serial: `T_serial = N × t_gambar`.
Target proposal (konkurensi 3 pasca-fase-1): `T_target ≈ T_serial / 3`
(untuk tugas seragam; file-cached men-skip network dan mempercepat keduanya proporsional).

| Skenario latensi/gambar | T_serial (200 hal) | T_target konkuren-3 | Rasio |
|---|---|---|---|
| Tipikal 0.3 s | **60.0 s (1.00 mnt)** | **20.0 s (0.33 mnt)** | 3.0× |
| Lambat 0.8 s | **160.0 s (2.67 mnt)** | **53.3 s (0.89 mnt)** | 3.0× |
| Sangat lambat 2.0 s | **400.0 s (6.67 mnt)** | **133.3 s (2.22 mnt)** | 3.0× |
| 1 gambar timeout 300 s, sisa 199×0.8 s | **459.2 s (7.65 mnt)** | **≈353.1 s** (lane lambat mendominasi) | ~1.3× |
| 1 gambar timeout 30 s (Dio default), sisa 199×0.8 s | **189.2 s (3.15 mnt)** | **≈83.1 s** (jalur kritis = 199×0.8/3 + 30) | ~2.3× |

Catatan model: kasus timeout memakai `T_pool3 ≈ (N-1)×t/3 + T_timeout` — satu worker
tersangkut di gambar timeout sementara 2 lainnya menghabiskan sisa antrean; head-of-line
blocking tidak hilang total, hanya dibagi per-lane. Resolusi sub-detik diabaikan
(`Future.delayed` pause 1 s hanya saat pause aktif).

## 4. Validasi model (tanpa network, tanpa file simulasi)

Scaling pool-3 ≈ 3× divalidasi dengan event-loop setara (`asyncio`, analogi
`Future.delayed` serial vs semaphore-3), inline tanpa menulis file:

```bash
python3 -c "
import asyncio, time
async def one(t): await asyncio.sleep(t); return t
async def serial(n,t):
    s=time.monotonic()
    for _ in range(n): await one(t)
    return time.monotonic()-s
async def pool(n,t,k=3):
    s=time.monotonic()
    sem=asyncio.Semaphore(k)
    async def w():
        async with sem: await one(t)
    await asyncio.gather(*[w() for _ in range(n)])
    return time.monotonic()-s
async def main():
    for t in (0.05,0.1):
        ts=await serial(12,t); tp=await pool(12,t)
        print(f't={t}s n=12 serial={ts:.2f}s pool3={tp:.2f}s ratio={ts/tp:.2f}')
asyncio.run(main())
"
```

Hasil observasi: `t=0.05s n=12 serial=0.61s pool3=0.21s ratio=2.97`,
`t=0.1s n=12 serial=1.21s pool3=0.40s ratio=3.00` → model `/3` valid.
Angka tabel §3 dihitung dengan:

```bash
python3 -c "
N=200
for t in (0.3,0.8,2.0):
    s=N*t
    print(f't={t}s serial={s:.1f}s ({s/60:.2f} min) pool3={s/3:.1f}s ({s/3/60:.2f} min)')
print('timeout 300s:', 199*0.8+300, (199*0.8)/3+300)
print('timeout 30s:', 199*0.8+30, (199*0.8)/3+30)
"
```

## 5. Test terkait di `test/` (angka pendukung)

Tidak ada test yang mengukur waktu download nyata (semua mock/tanpa network).
Yang memberi angka/plumbing pendukung:

- `test/unit/domain/usecases/download_content_usecase_test.dart` — usecase download (mock repo/service).
- `test/unit/domain/usecases/downloads/download_content_usecase_test.dart` — varian usecase
  (berisi grup `dynamic maxParallelImages`, fallback `params.maxParallelImages = 3`,
  koordinator memangkas ke 1 saat reader aktif) → asal konvensi angka **3** untuk pool.
- `test/unit/domain/entities/download_settings_test.dart` — default `DownloadSettings`
  (termasuk `maxConcurrentDownloads`, `pauseOnOnlineReaderOnly`).
- `test/unit/services/download_worker_test.dart` — worker download.
- `test/unit/services/download_lifecycle_mixin_test.dart` — lifecycle download.

## 6. Cara re-run

1. Baca loop: `lib/core/services/download_service.dart` L134–L230.
2. Cek rantai timeout: `user_preferences.dart:86` → `download_bloc.dart:589` →
   `download_content_usecase.dart:105,383` → `download_service.dart:45,199,364-379`
   (fallback `http_client_manager.dart:62-65` bila null).
3. Hitung ulang tabel dengan dua perintah `python3 -c` di §4.
4. (Opsional) `fvm flutter test test/unit/domain/usecases/downloads/download_content_usecase_test.dart`
   — verifikasi plumbing, bukan angka waktu.
