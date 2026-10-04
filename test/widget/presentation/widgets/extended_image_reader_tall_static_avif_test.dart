import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/utils/header_inspector.dart';
import 'package:nhasixapp/core/utils/reader_image_repair_utils.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/presentation/widgets/extended_image_reader_widget.dart';
import 'package:path/path.dart' as path;

// Regression: cocomic serves a TALL STATIC AVIF (720x14870, `ftyp` major brand
// `avif`, no `avis`/`iref`/`moof`) behind a `.jpg` URL. Two gates dropped it on
// the floor:
//   1. the tall predicate required `isAvisBrand` — a static AVIF never matches,
//      so Flutter tried to decode 720x14870 and blew past Android's decode
//      limits;
//   2. the cached-file inspect gate only matched `ehentai` / webp-capable /
//      `.avif` URLs, so a `.jpg` URL was never inspected at all.
//
// Expected after the fix: the payload is inspected by content (not extension),
// tall static AVIF routes to native WebP conversion.

// Real 240-byte header slice from the failing cocomic file
// (/tmp/coco_001.jpg): ftyp(avif/mif1) + meta + ispe 720x14870. No avis/iref/moof.
final Uint8List _tallStaticAvifBytes = Uint8List.fromList([
  0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66,
  0x00, 0x00, 0x00, 0x00, 0x61, 0x76, 0x69, 0x66, 0x6D, 0x69, 0x66, 0x31,
  0x6D, 0x69, 0x61, 0x66, 0x00, 0x00, 0x00, 0xEA, 0x6D, 0x65, 0x74, 0x61,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0x68, 0x64, 0x6C, 0x72,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x70, 0x69, 0x63, 0x74,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x0E, 0x70, 0x69, 0x74, 0x6D, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x22, 0x69, 0x6C, 0x6F, 0x63, 0x00,
  0x00, 0x00, 0x00, 0x44, 0x40, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00,
  0x00, 0x01, 0x0E, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x26,
  0x60, 0x00, 0x00, 0x00, 0x23, 0x69, 0x69, 0x6E, 0x66, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x15, 0x69, 0x6E, 0x66, 0x65, 0x02,
  0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x61, 0x76, 0x30, 0x31, 0x00,
  0x00, 0x00, 0x00, 0x6A, 0x69, 0x70, 0x72, 0x70, 0x00, 0x00, 0x00, 0x4B,
  0x69, 0x70, 0x63, 0x6F, 0x00, 0x00, 0x00, 0x13, 0x63, 0x6F, 0x6C, 0x72,
  0x6E, 0x63, 0x6C, 0x78, 0x00, 0x01, 0x00, 0x0D, 0x00, 0x06, 0x80, 0x00,
  0x00, 0x00, 0x0C, 0x61, 0x76, 0x31, 0x43, 0x81, 0x1F, 0x0C, 0x00, 0x00,
  0x00, 0x00, 0x14, 0x69, 0x73, 0x70, 0x65, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x02, 0xD0, 0x00, 0x00, 0x3A, 0x16, 0x00, 0x00, 0x00, 0x10, 0x70,
  0x69, 0x78, 0x69, 0x00, 0x00, 0x00, 0x00, 0x03, 0x08, 0x08, 0x08, 0x00,
]);

const String _cocomicJpgUrl =
    'https://v3.cocomic.net/2024/09/01/ch01/page001.jpg';

// Same file, but animated: `avis` in the compatible-brand list.
final Uint8List _tallAnimatedAvifBytes = Uint8List.fromList([
  ..._tallStaticAvifBytes.take(12),
  0x00, 0x00, 0x00, 0x00, // minor version
  0x61, 0x76, 0x69, 0x73, // 'avis'
  0x6D, 0x69, 0x66, 0x31, // 'mif1'
  ..._tallStaticAvifBytes.skip(24),
]);

/// Rewrite the payload's `ispe` width/height, so height-predicate tests can
/// vary dimensions without hand-building a second ISOBMFF header.
Uint8List _withIspeSize(
  Uint8List src, {
  required int width,
  required int height,
}) {
  const ispe = <int>[0x69, 0x73, 0x70, 0x65]; // 'ispe'
  final out = Uint8List.fromList(src);
  void put(int at, int v) {
    out[at] = (v >> 24) & 0xFF;
    out[at + 1] = (v >> 16) & 0xFF;
    out[at + 2] = (v >> 8) & 0xFF;
    out[at + 3] = v & 0xFF;
  }

  for (var i = 0; i <= out.length - 16; i++) {
    if (out[i] != ispe[0] ||
        out[i + 1] != ispe[1] ||
        out[i + 2] != ispe[2] ||
        out[i + 3] != ispe[3]) {
      continue;
    }
    put(i + 8, width);
    put(i + 12, height);
    return out;
  }
  throw StateError('no ispe box in fixture');
}

/// A plain *static* WebP: `RIFF....WEBP` + a lossy `VP8 ` chunk, no `VP8X`,
/// no `ANIM`/`ANMF`. This is what a converted tall static AVIF ends up as, so
/// it must never be re-detected as animated, nor as something needing AVIF
/// conversion a second time.
Uint8List _staticWebpBytes() {
  const vp8 = <int>[0x9D, 0x01, 0x2A, 0x00];
  const body = <int>[
    0x57, 0x45, 0x42, 0x50, // 'WEBP'
    0x56, 0x50, 0x38, 0x20, // 'VP8 '
    0x04, 0x00, 0x00, 0x00, // chunk size
    ...vp8,
  ];
  final out = Uint8List(8 + body.length);
  out.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
  final size = out.length - 8;
  out[4] = size & 0xFF;
  out[5] = (size >> 8) & 0xFF;
  out[6] = (size >> 16) & 0xFF;
  out[7] = (size >> 24) & 0xFF;
  out.setRange(8, out.length, body);
  return out;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tall_static_avif_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ─── GREEN today: header detection is content-based, extension-agnostic. ───
  group('tall static AVIF header detection', () {
    test('static AVIF payload is AVIF, not avis, and measures 720x14870', () {
      final r = inspectAvifBytesForRouting(_tallStaticAvifBytes);

      expect(r.isAvif, isTrue);
      expect(
        r.isAvisBrand,
        isFalse,
        reason: 'ftyp major=avif with no avis/iref/moof => static, not animated',
      );
      expect(r.width, 720);
      expect(r.height, 14870);
    });

    test('static tall AVIF satisfies the >4096 native-height predicate', () {
      final r = inspectAvifBytesForRouting(_tallStaticAvifBytes);

      expect(
        r.isAvif && (r.height ?? 0) > maxNativeAvifHeight,
        isTrue,
        reason: '14870 >> maxNativeAvifHeight=$maxNativeAvifHeight',
      );
    });

    test('file-level inspect agrees with byte-level inspect', () {
      final f = File('${tempDir.path}/page001.jpg')
        ..writeAsBytesSync(_tallStaticAvifBytes);

      final r = inspectAvifHeaderForRouting(f);

      expect(r.isAvif, isTrue);
      expect(r.isAvisBrand, isFalse);
      expect(r.width, 720);
      expect(r.height, 14870);
    });

    test('animated twin (avis compat brand) still reports isAvisBrand=true', () {
      final r = inspectAvifBytesForRouting(_tallAnimatedAvifBytes);

      expect(r.isAvif, isTrue);
      expect(r.isAvisBrand, isTrue);
      expect(r.height, 14870);
    });
  });

  // ─── Conversion predicate: static tall AVIF must convert, animated must not regress. ───
  group('tall AVIF conversion predicate', () {
    test('static .jpg-named tall AVIF file is queued for conversion', () {
      final f = File('${tempDir.path}/page001.jpg')
        ..writeAsBytesSync(_tallStaticAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isTrue,
        reason:
            'static AVIF taller than maxNativeAvifHeight must convert too — '
            'Android cannot decode 720x14870 in Flutter',
      );
    });

    test('static tall AVIF converts even under a .jpeg name', () {
      final f = File('${tempDir.path}/page001.jpeg')
        ..writeAsBytesSync(_tallStaticAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isTrue,
      );
    });

    test('animated tall AVIF still converts', () {
      final f = File('${tempDir.path}/anim.avif')
        ..writeAsBytesSync(_tallAnimatedAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isTrue,
      );
    });

    test('normal-height static AVIF is left alone', () {
      // Same ftyp/brand, but ispe rewritten to 720x1080.
      final short = _withIspeSize(_tallStaticAvifBytes, width: 720, height: 1080);
      final f = File('${tempDir.path}/short.avif')
        ..writeAsBytesSync(short);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isFalse,
        reason: 'height 1080 <= maxNativeAvifHeight — no conversion needed',
      );
    });

    test('non-AVIF payload (real JPEG header) is not converted', () {
      final f = File('${tempDir.path}/normal.jpg')
        ..writeAsBytesSync(<int>[
          0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
          0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
          0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
        ]);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isFalse,
      );
    });

    test('missing file and no-native-view both short-circuit to false', () {
      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          File('${tempDir.path}/nope.jpg'),
          nativeViewAvailable: true,
        ),
        isFalse,
      );

      final f = File('${tempDir.path}/page001.jpg')
        ..writeAsBytesSync(_tallStaticAvifBytes);
      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: false,
        ),
        isFalse,
      );
    });
  });

  // ─── Inspect gate: brand/height are invisible to the extension, so inspect .jpg too. ───
  group('cached-file inspect gate', () {
    test('cocomic .jpg URL is inspected, not skipped by extension', () {
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: _cocomicJpgUrl,
          sourceId: 'cocomic',
        ),
        isTrue,
        reason:
            'a .jpg URL can carry AVIF bytes — brand and height are invisible '
            'to the extension, so the file must be inspected',
      );
    });

    test('.jpeg URL is inspected too', () {
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://example.com/page.jpeg',
          sourceId: 'cocomic',
        ),
        isTrue,
      );
    });

    test('query-string .jpg URL is inspected', () {
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://example.com/page.jpg?token=abc',
          sourceId: 'cocomic',
        ),
        isTrue,
      );
    });

    test('existing gates are preserved', () {
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://e-hentai.org/s/token/whatever',
          sourceId: 'ehentai',
        ),
        isTrue,
      );
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://example.com/page.avif',
          sourceId: 'mangapill',
        ),
        isTrue,
      );
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://example.com/page-wbp',
          sourceId: 'mangapill',
        ),
        isTrue,
      );
    });

    test('known-non-native .webp still inspects (unchanged)', () {
      expect(
        ExtendedImageReaderWidget.shouldInspectForNativeAnimatedForTesting(
          url: 'https://example.com/page.webp',
          sourceId: 'mangapill',
        ),
        isTrue,
      );
    });
  });

  // ─── The regression itself: converting a tall STATIC AVIF to WebP must NOT
  // make the page "heavy"/"confirmed animated". Marking it did two things:
  //   1. fired onHeavyImageDetected in continuous-scroll mode, flipping the
  //      reader webtoon -> singlePage for one absurdly tall image;
  //   2. rendered through AnimatedWebPView, whose AspectRatio handling differs
  //      from the normal webtoon strip.
  // Only the avis brand (real animation) may be marked.
  group('converted tall static AVIF is not a heavy animated page', () {
    test('tall static AVIF is NOT marked heavy/confirmed after conversion', () {
      final r = inspectAvifBytesForRouting(_tallStaticAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldMarkConvertedAvifHeavyForTesting(
          isAvif: r.isAvif,
          isAvisBrand: r.isAvisBrand,
          height: r.height,
        ),
        isFalse,
        reason: '720x14870 static AVIF converts to a plain WebP image — it is '
            'not animation, so no heavy/native route and no notify',
      );
    });

    test('tall animated (avis) AVIF is still marked heavy/confirmed', () {
      final r = inspectAvifBytesForRouting(_tallAnimatedAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldMarkConvertedAvifHeavyForTesting(
          isAvif: r.isAvif,
          isAvisBrand: r.isAvisBrand,
          height: r.height,
        ),
        isTrue,
        reason: 'avis brand = real animation, unchanged behaviour',
      );
    });

    test('short animated (avis) AVIF is still marked — height is irrelevant', () {
      final short = _withIspeSize(
        _tallAnimatedAvifBytes,
        width: 480,
        height: 640,
      );
      final r = inspectAvifBytesForRouting(short);

      expect(r.isAvisBrand, isTrue);
      expect(
        ExtendedImageReaderWidget.shouldMarkConvertedAvifHeavyForTesting(
          isAvif: r.isAvif,
          isAvisBrand: r.isAvisBrand,
          height: r.height,
        ),
        isTrue,
      );
    });

    test('non-AVIF payload is never marked heavy', () {
      expect(
        ExtendedImageReaderWidget.shouldMarkConvertedAvifHeavyForTesting(
          isAvif: false,
          isAvisBrand: false,
          height: 14870,
        ),
        isFalse,
      );
    });

    test('static convert therefore never fires onHeavyImageDetected', () {
      // The two seams composed: "is it marked?" feeds "does it notify?".
      final r = inspectAvifBytesForRouting(_tallStaticAvifBytes);
      final marked = ExtendedImageReaderWidget
          .shouldMarkConvertedAvifHeavyForTesting(
        isAvif: r.isAvif,
        isAvisBrand: r.isAvisBrand,
        height: r.height,
      );

      expect(
        ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
          readingMode: ReadingMode.continuousScroll,
          confirmedAnimatedWebP: marked,
          hasCallback: true,
          alreadyNotified: false,
        ),
        isFalse,
        reason: 'a static strip must never auto-switch webtoon -> singlePage',
      );
    });

    test('animated convert still fires onHeavyImageDetected', () {
      final r = inspectAvifBytesForRouting(_tallAnimatedAvifBytes);
      final marked = ExtendedImageReaderWidget
          .shouldMarkConvertedAvifHeavyForTesting(
        isAvif: r.isAvif,
        isAvisBrand: r.isAvisBrand,
        height: r.height,
      );

      expect(marked, isTrue);
      expect(
        ExtendedImageReaderWidget.shouldNotifyHeavyImageDetectedForTesting(
          readingMode: ReadingMode.continuousScroll,
          confirmedAnimatedWebP: marked,
          hasCallback: true,
          alreadyNotified: false,
        ),
        isTrue,
      );
    });
  });

  // ─── Idempotence: after the conversion the page is a normal .webp file. It
  // must not re-enter the AVIF conversion / animated-header paths.
  group('already-converted static WebP is not re-processed', () {
    test('a static RIFF/WEBP file is not queued for AVIF conversion', () {
      final f = File('${tempDir.path}/page001.webp')
        ..writeAsBytesSync(_staticWebpBytes());

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          f,
          nativeViewAvailable: true,
        ),
        isFalse,
        reason: 'conversion already happened; a WebP is never AVIF',
      );
    });

    test('converted file is recognised as webp, not as animated webp', () {
      final bytes = _staticWebpBytes();

      expect(
        ExtendedImageReaderWidget.isAnimatedWebPHeaderForTesting(bytes),
        isFalse,
        reason: 'no VP8X/ANIM — Flutter decodes it like any other image',
      );
      expect(
        ExtendedImageReaderWidget.isSupportedImageHeaderForTesting(bytes),
        isTrue,
      );

      final f = File('${tempDir.path}/page002.webp')
        ..writeAsBytesSync(bytes);
      expect(
        inspectFileHeader(f.path).format,
        isNot('avif'),
        reason: 'inspectFileHeader reports avif only for avis+short payloads',
      );
    });

    test('convert path wins over the original local path', () {
      expect(
        ExtendedImageReaderWidget.resolvedConvertedImagePathForTesting(
          convertedPath: '/cache/page001.webp',
          resolvedPath: '/cache/page001.jpg',
        ),
        '/cache/page001.webp',
      );
    });

    test('no converted path falls back to the resolved path', () {
      expect(
        ExtendedImageReaderWidget.resolvedConvertedImagePathForTesting(
          convertedPath: null,
          resolvedPath: '/cache/page001.jpg',
        ),
        '/cache/page001.jpg',
      );
    });
  });

  // ─── Regression: the in-place conversion must happen EXACTLY ONCE. ───
  // The converter used to be called without `outputPath`, so it wrote a
  // hash-named file into cacheDir and the `.jpg` source stayed on disk. Every
  // scroll-back builds a fresh State, resolves the same still-present source
  // and re-runs the whole conversion. The fix passes the sibling `.webp` as
  // `outputPath` (buildReplacementImagePath) and deletes the source afterwards
  // (_deleteLocalPageFormatConflicts).
  group('in-place AVIF→WebP conversion happens exactly once', () {
    test('output path is a sibling .webp, not a cacheDir hash', () {
      final sourcePath = '${tempDir.path}/page001.jpg';
      final outputPath = buildReplacementImagePath(
        currentImagePath: sourcePath,
        extension: 'webp',
      );

      expect(
        outputPath,
        path.join(tempDir.path, 'page001.webp'),
        reason: 'the converted file must land beside the source so deleting '
            'the source leaves the WebP as the only copy of the page',
      );
      expect(
        path.dirname(outputPath),
        path.dirname(sourcePath),
        reason: 'a cacheDir path would keep the source as the resolved page '
            'and re-convert it on every scroll-back',
      );
      expect(path.extension(outputPath), '.webp');
      expect(
        buildReplacementImagePath(
          currentImagePath: outputPath,
          extension: 'webp',
        ),
        outputPath,
        reason: 'rebuilding the replacement path must be idempotent',
      );
    });

    test('deleted source and converted WebP both fail the convert predicate',
        () {
      final source = File('${tempDir.path}/page001.jpg')
        ..writeAsBytesSync(_tallStaticAvifBytes);

      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          source,
          nativeViewAvailable: true,
        ),
        isTrue,
        reason: 'precondition: the tall static AVIF does convert once',
      );

      // Exactly what the widget does after a successful conversion.
      final outputPath = buildReplacementImagePath(
        currentImagePath: source.path,
        extension: 'webp',
      );
      File(outputPath).writeAsBytesSync(_staticWebpBytes());
      source.deleteSync();

      expect(source.existsSync(), isFalse);
      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          File(source.path),
          nativeViewAvailable: true,
        ),
        isFalse,
        reason: 'the deleted source must not be convertible again',
      );
      expect(
        ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
          File(outputPath),
          nativeViewAvailable: true,
        ),
        isFalse,
        reason: 'the converted WebP is never AVIF',
      );
      expect(
        ExtendedImageReaderWidget.resolvedConvertedImagePathForTesting(
          convertedPath: outputPath,
          resolvedPath: source.path,
        ),
        outputPath,
        reason: 'the WebP is what the builders must render',
      );
    });

    test('no file left in the page directory re-enters conversion', () {
      final source = File('${tempDir.path}/page001.jpg')
        ..writeAsBytesSync(_tallStaticAvifBytes);
      final outputPath = buildReplacementImagePath(
        currentImagePath: source.path,
        extension: 'webp',
      );
      File(outputPath).writeAsBytesSync(_staticWebpBytes());
      source.deleteSync();

      // "New State, scrolled back to this page": re-run the predicate over
      // everything the resolver can see on disk. Pre-fix (source kept) the
      // `.jpg` entry converted again; in-place it must find nothing to do.
      final reConverted = tempDir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                ExtendedImageReaderWidget.shouldConvertTallAvifFileForTesting(
              f,
              nativeViewAvailable: true,
            ),
          )
          .map((f) => path.basename(f.path))
          .toList();

      expect(reConverted, isEmpty);
      expect(
        tempDir.listSync().map((e) => path.basename(e.path)).toList(),
        <String>['page001.webp'],
        reason: 'the WebP is the only file left for the page',
      );
    });
  });

}