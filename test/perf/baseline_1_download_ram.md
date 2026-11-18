# Baseline 1 — Puncak RAM transient download Dart (200 halaman)

Area 1, static analysis (tanpa network, tanpa run). Tanggal: 2026-11-18.
Scope: `DownloadService._downloadSingleImage` vs `LocalImagePreloader.downloadAndCacheImageStreaming`.

## 1. Kode yang dikutip (nomor baris persis)

### Jalur yang diukur — `lib/core/services/download_service.dart`
- Loop serial: baris 134 (`for (int pageNum = actualStartPage; ...)`) + baris 194
  (`await _downloadSingleImage(...)`). Satu halaman selesai (di-`await`) sebelum
  halaman berikut dimulai → **tidak ada konkurensi antar-halaman**; peak simultan ≈ 1 file.
- `_downloadSingleImage`: baris 359–405. Inti masalah (baris 384–395):
  ```dart
  final response = await dio.get<List<int>>(   // L384
    imageUrl,
    options: Options(
      responseType: ResponseType.bytes,        // L387 — buffer penuh di RAM
      headers: headers,
    ),
    cancelToken: cancelToken,
  );
  if (response.data != null) {
    final file = File(filePath);
    await file.writeAsBytes(response.data!);  // L395 — salinan ke-2/3
  }
  ```
- Varian baca-penuh lain di file yang sama: `fetchRemoteImageBytes` baris 412–434,
  baris 429 `Uint8List.fromList(response.data!)` = **salinan ekstra 1x** (dipakai pipeline
  reader-AI/page-capture, bukan loop download 200 hal — tidak dihitung di total bawah).
- Adapter: baris 6 `native_dio_adapter`, baris 377–379 `dio.httpClientAdapter =
  NativeAdapter()` hanya bila `timeoutDuration != null`, selain itu `_httpClient`
  default. Tidak menambah faktor heap-Dart (buffering Cronet terjadi di sisi native,
  chunked — lihat §3).

### Pembanding streaming — `lib/core/services/local_image_preloader.dart`
- Varian buffered (masalah sama): `downloadAndCacheImage` baris 779–858;
  baris 820–827 `dio.get<List<int>>` + `ResponseType.bytes`, baris 830
  `Uint8List.fromList(response.data!)`, baris 844–848 `_saveToInternalCache`
  → `file.writeAsBytes` (baris 384). Total ≈ 3x S (lihat §2).
- Varian streaming: `downloadAndCacheImageStreaming` baris 867–968; komentar desain
  baris 860–866; `dio.download(cleanUrl, tmpPath, ...)` baris 914–922 (stream ke
  `.part`, baris 897); publish atomik rename baris 942–946; cleanup `.part` baris
  952–960. **Caveat**: baris 930–937 membaca ulang seluruh file
  (`readAsBytes` + `maybeDescramble` + `writeAsBytes`) saat header comix terdeteksi —
  pada file ter-descramble peak streaming naik ke ~2x S untuk halaman itu saja.

## 2. Hasil angka (S = ukuran 1 gambar; 1 KB = 1024 B)

Faktor salinan jalur `_downloadSingleImage` (Dio `ResponseType.bytes`):
| Salinan | Sumber | Besaran |
|---|---|---|
| 1. Buffer respons Dio (`response.data`) + transient `BytesBuilder` saat akumulasi chunk | `download_service.dart` L384–391 | ~1x S menetap, ~2x S transient saat finalisasi |
| 2. `File.writeAsBytes(response.data!)` (salinan ke buffer native I/O) | L395 | ~1x S transient |
| **Total faktor k** | | **peak simultan ≈ 2–3x S** |

### Peak simultan (1 file di RAM — loop serial L134+L194)

| Ukuran tipikal/halaman | Peak simultan (2–3x S) |
|---|---|
| 300 KB (manga kompres/teroptimasi) | **0,6 – 0,9 MB** |
| 800 KB (manga tipikal) | **1,6 – 2,4 MB** |
| 1,5 MB (kualitas tinggi) | **3,0 – 4,5 MB** |

### Total transient dialokasikan selama 200 halaman (= 200 × peak)

| Ukuran tipikal/halaman | Total transient 200 hal |
|---|---|
| 300 KB | **120 – 180 MB** (kumulatif, di-GC per halaman) |
| 800 KB | **320 – 480 MB** |
| 1,5 MB | **600 – 900 MB** |

Catatan:
- Ini alokasi **kumulatif/transient**, bukan retained: tiap buffer dibebaskan setelah
  `writeAsBytes` halaman itu selesai, jadi heap menetap ≈ 0 dari jalur ini.
  Total di disk setelah selesai = 200 × S (60 / 160 / 300 MB).
- GC Dart generational menangani pola alokasi-besar-berumur-pendek ini dengan baik;
  risiko nyata hanya bila gambar terbesar > ~5 MB (peak > 15 MB) atau bila loop
  kelak dibuat paralel (peak × N konkurensi).
- Pembanding streaming (`dio.download`): peak per halaman O(buffer chunk ~8–64 KB),
  kecuali halaman ter-descramble comix (L930–937) yang menyentuh ~2x S.

## 3. Buffering tambahan (Dio adapter)

- `dio: ^5.9.0` (`pubspec.yaml` L47): `ResponseType.bytes` lewat `DefaultTransformer`
  mengumpulkan chunk `HttpClientResponse` lalu flatten menjadi satu `Uint8List` —
  flatten inilah transient ~2x S di §2. Tidak ada cache respons lain di jalur ini.
- `native_dio_adapter: ^1.3.0` (`pubspec.yaml` L48, dipakai L377–379 hanya saat
  `timeoutDuration != null`): Cronet mem-buffer di native heap per chunk jaringan,
  bukan di Dart heap → **tidak menambah faktor k di Dart**. Batas atas k=3 sudah
  mencakup kasus terburuk akumulasi `BytesBuilder` di sisi Dart.

## 4. Test timing terkait di `test/`

Hasil: **tidak ada test yang memberi angka RAM/timing download**.
- `test/unit/services/download_worker_test.dart` (75 baris) — lifecycle worker, tanpa
  asersi memori/waktu.
- `test/unit/domain/usecases/download_content_usecase_test.dart` — hanya menyebut
  `imageTimeoutMs: 60000` (L156, konstanta timeout) dan `DownloadContentParams.immediate`
  (L129, L215); bukan pengukuran.
- `grep -ri "ResponseType.bytes|writeAsBytes|peak|transient|Uint8List.fromList" test/`
  → tidak ada hit relevan; tidak ada file `test/perf/*` sebelum baseline ini dibuat.
- Micro-benchmark `/tmp` tidak dijalankan (tidak diperlukan — estimasi murni dari
  bentuk alokasi di kode; pola `bytes penuh + writeAsBytes` deterministik).

## 5. Cara re-run estimasi

1. Buka `lib/core/services/download_service.dart` L359–405; verifikasi masih
   `dio.get<List<int>>` + `ResponseType.bytes` + `File.writeAsBytes(response.data!)`.
2. Buka L134 + L194; verifikasi loop masih serial (`for` + `await`, tanpa
   `Future.wait`/pool). Jika paralelisme N ditambahkan → kalikan peak dengan N.
3. Buka `lib/core/services/local_image_preloader.dart` L914–946 untuk status
   pembanding streaming; cek L930–937 untuk caveat descramble.
4. Hitung ulang: `peak = S × 3` (batas atas), `total_transient_200 = 200 × peak`.
5. (Opsional, tanpa network, di `/tmp` — JANGAN commit) micro-benchmark alokasi murni:
   ```dart
   // /tmp/alloc_probe.dart — `dart /tmp/alloc_probe.dart`
   import 'dart:typed_data';
   void main() {
     for (final kb in [300, 800, 1536]) {
       final a = Uint8List(kb * 1024);          // tiruan response.data (1x)
       final b = Uint8List.fromList(a);        // tiruan salinan writeAsBytes/fromList (2x)
       print('$kb KB -> ${(a.length + b.length) ~/ 1024} KB hidup simultan');
     }
   }
   ```
