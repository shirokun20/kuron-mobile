import 'dart:io';
import 'dart:typed_data';

import 'reader_image_repair_utils.dart';

// Result from a single file header inspection.
typedef FileHeaderResult = ({
  String? format, // 'webp', 'avif', or null
  int? width,
  int? height,
});

const int maxNativeAvifHeight = 4096;

// Inspect a single file's header for animated WebP/AVIF routing.
///
// Reads up to 4KB of the file header to determine format and dimensions.
// Designed to be `compute()`-eligible — top-level function, no closures.
FileHeaderResult inspectFileHeader(String path) {
  const empty = (format: null, width: null, height: null) as FileHeaderResult;

  // Pure Dart path (sole implementation).
  File file;
  RandomAccessFile? raf;
  try {
    file = File(path);
    if (!file.existsSync()) return empty;
    raf = file.openSync(mode: FileMode.read);
    final length = raf.lengthSync();
    if (length < 16) return empty;

    final sampleLength = length < 4096 ? length : 4096;
    final bytes = raf.readSync(sampleLength);
    final ext = inferImageExtension(bytes: bytes);
    if (ext == 'webp') {
      if (!looksLikeAnimatedWebPHeader(bytes)) return empty;
      int? width;
      int? height;
      int offset = 12;
      while (offset + 8 <= bytes.length) {
        final chunkType =
            String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);

        if (chunkType == 'VP8X' &&
            chunkSize >= 10 &&
            offset + 18 <= bytes.length) {
          width = 1 +
              (bytes[offset + 12] |
                  (bytes[offset + 13] << 8) |
                  (bytes[offset + 14] << 16));
          height = 1 +
              (bytes[offset + 15] |
                  (bytes[offset + 16] << 8) |
                  (bytes[offset + 17] << 16));
          break;
        }
        offset += 8 + chunkSize;
        if (chunkSize % 2 != 0) offset++;
      }
      return (format: 'webp', width: width, height: height);
    }

    if (ext == 'avif') {
      if (bytes.length < 12) return empty;
      const kAvis0 = 0x61;
      const kAvis1 = 0x76;
      const kAvis2 = 0x69;
      const kAvis3 = 0x73;
      if (bytes[8] != kAvis0 ||
          bytes[9] != kAvis1 ||
          bytes[10] != kAvis2 ||
          bytes[11] != kAvis3) {
        return empty;
      }
      const kIspe = <int>[0x69, 0x73, 0x70, 0x65];
      for (int i = 0; i <= bytes.length - 16; i++) {
        if (matchesBytes(bytes, i, kIspe)) {
          final w = ((bytes[i + 8] & 0xFF) << 24) |
              ((bytes[i + 9] & 0xFF) << 16) |
              ((bytes[i + 10] & 0xFF) << 8) |
              (bytes[i + 11] & 0xFF);
          final h = ((bytes[i + 12] & 0xFF) << 24) |
              ((bytes[i + 13] & 0xFF) << 16) |
              ((bytes[i + 14] & 0xFF) << 8) |
              (bytes[i + 15] & 0xFF);
          if (h > maxNativeAvifHeight) return empty;
          return (
            format: 'avif',
            width: w > 0 ? w : null,
            height: h > 0 ? h : null
          );
        }
      }
      return empty;
    }
    return empty;
  } catch (_) {
    return empty;
  } finally {
    raf?.closeSync();
  }
}

// Batch inspect file headers via [compute] or sync loop.
// Used when >10 files need inspection.
List<FileHeaderResult> batchInspectHeaders(List<String> paths) {
  // Pure Dart — sequential per-file inspect (sole implementation).
  return [for (final p in paths) inspectFileHeader(p)];
}

// ─── Static helpers (duplicated from extended_image_reader_widget.dart for
//      compute()-eligibility — top-level functions cannot reference class members) ───

bool looksLikeAnimatedWebPHeader(Uint8List bytes) {
  const riff = <int>[0x52, 0x49, 0x46, 0x46];
  const webp = <int>[0x57, 0x45, 0x42, 0x50];
  const vp8x = <int>[0x56, 0x50, 0x38, 0x58];
  const anim = <int>[0x41, 0x4E, 0x49, 0x4D];

  if (!matchesBytes(bytes, 0, riff) || !matchesBytes(bytes, 8, webp)) {
    return false;
  }
  if (matchesBytes(bytes, 12, vp8x) &&
      bytes.length > 20 &&
      (bytes[20] & 0x02) != 0) {
    return true;
  }
  return containsBytes(bytes, anim);
}

bool matchesBytes(Uint8List bytes, int offset, List<int> expected) {
  if (bytes.length < offset + expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected[i]) return false;
  }
  return true;
}

bool containsBytes(Uint8List bytes, List<int> needle) {
  if (bytes.length < needle.length) return false;
  for (int start = 0; start <= bytes.length - needle.length; start++) {
    if (matchesBytes(bytes, start, needle)) return true;
  }
  return false;
}

({bool isAvif, bool isAvisBrand, int? width, int? height})
    inspectAvifHeaderForRouting(File file) {
  const empty = (
    isAvif: false,
    isAvisBrand: false,
    width: null,
    height: null,
  );

  RandomAccessFile? raf;
  try {
    raf = file.openSync(mode: FileMode.read);
    final length = raf.lengthSync();
    if (length < 16) return empty;
    final sampleLength = length < 4096 ? length : 4096;
    final bytes = raf.readSync(sampleLength);
    return inspectAvifBytesForRouting(bytes);
  } catch (_) {
    return empty;
  } finally {
    raf?.closeSync();
  }
}

/// Bytes-based AVIF brand/animation detection (works for online-cached and
/// local files alike).
///
/// FIX: previous detection (Rust `header.rs`/Dart fallback) only returned an
/// AVIF when the MAJOR brand (bytes 8–12) was exactly `avis`. Many animated
/// AVIFs (e.g. manga "motion" CDNs like manga18) use `ftyp` major brand
/// `avif`/`mif1` with `avis` as a MINOR brand, or signal animation via an
/// `iref`/`moof` box — so they were never routed to WebP conversion and
/// Flutter's decoder showed a broken image. Here we treat any AVIF `ftyp` as
/// `isAvif`, and `isAvisBrand` (needs WebP conversion) as true when `avis`
/// appears in any brand position OR an `iref`/`moof` box is present.
({bool isAvif, bool isAvisBrand, int? width, int? height})
    inspectAvifBytesForRouting(Uint8List bytes) {
  const empty = (
    isAvif: false,
    isAvisBrand: false,
    width: null,
    height: null,
  );
  if (bytes.length < 12) return empty;

  // ISOBMFF `ftyp` box: [size:4]['ftyp'][major:4][minor:4][compat:4...]
  const kFtyp = <int>[0x66, 0x74, 0x79, 0x70]; // 'ftyp'
  const kAvif = <int>[0x61, 0x76, 0x69, 0x66]; // 'avif'
  const kAvis = <int>[0x61, 0x76, 0x69, 0x73]; // 'avis'
  const kMif1 = <int>[0x6d, 0x69, 0x66, 0x31]; // 'mif1'
  const kIref = <int>[0x69, 0x72, 0x65, 0x66]; // 'iref'
  const kMoof = <int>[0x6d, 0x6f, 0x6f, 0x66]; // 'moof'
  const kIspe = <int>[0x69, 0x73, 0x70, 0x65]; // 'ispe'

  if (!matchesBytes(bytes, 4, kFtyp)) return empty;
  final isAvifBrand = matchesBytes(bytes, 8, kAvif) ||
      matchesBytes(bytes, 8, kAvis) ||
      matchesBytes(bytes, 8, kMif1);
  if (!isAvifBrand) return empty;

  var hasAvisBrand = matchesBytes(bytes, 8, kAvis);
  if (!hasAvisBrand) {
    // Scan compatible brands (immediately after ftyp header, 4-byte aligned).
    for (var i = 16; i <= bytes.length - 4; i += 4) {
      if (matchesBytes(bytes, i, kAvis)) {
        hasAvisBrand = true;
        break;
      }
    }
  }
  final animated = hasAvisBrand ||
      containsBytes(bytes, kIref) ||
      containsBytes(bytes, kMoof);

  int? width;
  int? height;
  for (var i = 0; i <= bytes.length - 16; i++) {
    if (matchesBytes(bytes, i, kIspe)) {
      final w = ((bytes[i + 8] & 0xFF) << 24) |
          ((bytes[i + 9] & 0xFF) << 16) |
          ((bytes[i + 10] & 0xFF) << 8) |
          (bytes[i + 11] & 0xFF);
      final h = ((bytes[i + 12] & 0xFF) << 24) |
          ((bytes[i + 13] & 0xFF) << 16) |
          ((bytes[i + 14] & 0xFF) << 8) |
          (bytes[i + 15] & 0xFF);
      width = w > 0 ? w : null;
      height = h > 0 ? h : null;
      break;
    }
  }
  return (
    isAvif: true,
    isAvisBrand: animated,
    width: width,
    height: height,
  );
}
