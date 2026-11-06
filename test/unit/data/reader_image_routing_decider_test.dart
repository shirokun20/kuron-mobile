import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/data/datasources/reader_image_pipeline.dart';

void main() {
  // ── Byte Fixtures ──────────────────────────────────────────────────────────

  // Minimal JPEG (SOI + APP0 + SOS/EOI)
  final minimalJpeg = Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, // APP0
    0x00, 0x10,
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xFF, 0xD9, // EOI
  ]);

  // Minimal animated WebP (RIFF + WEBP + VP8X with animation flag bit 1)
  final minimalAnimatedWebP = Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x24, 0x00, 0x00, 0x00, // length
    0x57, 0x45, 0x42, 0x50, // WEBP
    0x56, 0x50, 0x38, 0x58, // VP8X
    0x0A, 0x00, 0x00, 0x00, // chunk size 10
    0x02, 0x00, 0x00, 0x00, // flags: animation bit set
    0x00, 0x00, 0x00, // width - 1 = 0 (1px)
    0x00, 0x00, 0x00, // height - 1 = 0 (1px)
  ]);

  // Minimal static WebP (lossy VP8, no VP8X animation flag)
  final minimalStaticWebP = Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x20, 0x00, 0x00, 0x00,
    0x57, 0x45, 0x42, 0x50, // WEBP
    0x56, 0x50, 0x38, 0x20, // "VP8 "
    0x14, 0x00, 0x00, 0x00,
    0x9D, 0x01, 0x2A, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]);

  // Animated AVIF: major brand 'avis'
  final avisAvif = Uint8List.fromList([
    0x00, 0x00, 0x00, 0x14, // ftyp size 20
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x61, 0x76, 0x69, 0x73, // 'avis'
    0x00, 0x00, 0x00, 0x00,
    0x6d, 0x69, 0x66, 0x31, // 'mif1'
  ]);

  // Animated AVIF: major brand 'avif', compatible brand 'avis'
  final compatAvisAvif = Uint8List.fromList([
    0x00, 0x00, 0x00, 0x18, // ftyp size 24
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x61, 0x76, 0x69, 0x66, // 'avif'
    0x00, 0x00, 0x00, 0x00,
    0x61, 0x76, 0x69, 0x73, // 'avis'
    0x6d, 0x69, 0x66, 0x31, // 'mif1'
  ]);

  // Tall non-avis static AVIF with ispe box: width 800, height 5000 (> 4096)
  final tallStaticAvif = Uint8List.fromList([
    0x00, 0x00, 0x00, 0x14, // ftyp size 20
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x61, 0x76, 0x69, 0x66, // 'avif'
    0x00, 0x00, 0x00, 0x00,
    0x6d, 0x69, 0x66, 0x31, // 'mif1'
    0x00, 0x00, 0x00, 0x14, // ispe box size 20
    0x69, 0x73, 0x70, 0x65, // 'ispe'
    0x00, 0x00, 0x00, 0x00, // version/flags
    0x00, 0x00, 0x03, 0x20, // width = 800
    0x00, 0x00, 0x13, 0x88, // height = 5000
  ]);

  // Normal height non-avis static AVIF with ispe box: width 800, height 1200 (<= 4096)
  final normalStaticAvif = Uint8List.fromList([
    0x00, 0x00, 0x00, 0x14, // ftyp size 20
    0x66, 0x74, 0x79, 0x70, // 'ftyp'
    0x61, 0x76, 0x69, 0x66, // 'avif'
    0x00, 0x00, 0x00, 0x00,
    0x6d, 0x69, 0x66, 0x31, // 'mif1'
    0x00, 0x00, 0x00, 0x14, // ispe box size 20
    0x69, 0x73, 0x70, 0x65, // 'ispe'
    0x00, 0x00, 0x00, 0x00, // version/flags
    0x00, 0x00, 0x03, 0x20, // width = 800
    0x00, 0x00, 0x04, 0xB0, // height = 1200
  ]);

  // Non-image garbage bytes
  final garbageBytes = Uint8List.fromList([
    0x3C, 0x21, 0x44, 0x4F, 0x43, 0x54, 0x59, 0x50, 0x45, 0x20, // "<!DOCTYPE "
    0x68, 0x74, 0x6D, 0x6C, 0x3E,
  ]);

  // ── Matrix Unit Tests ──────────────────────────────────────────────────────

  group('ImageRouteDecider matrix tests (Task 1.1)', () {
    test('avis major brand AVIF routes to nativeAnimated', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: avisAvif,
        fileSize: avisAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('avis compatible brand AVIF routes to nativeAnimated', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: compatAvisAvif,
        fileSize: compatAvisAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('tall non-avis AVIF (height > 4096) routes to convertAvifThenDirect',
        () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: tallStaticAvif,
        fileSize: tallStaticAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.convertAvifThenDirect));
    });

    test('normal non-avis AVIF (height <= 4096) routes to flutterDirect', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: normalStaticAvif,
        fileSize: normalStaticAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test('animated WebP routes to nativeAnimated', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalAnimatedWebP,
        fileSize: minimalAnimatedWebP.length,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('static WebP routes to flutterDirect', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalStaticWebP,
        fileSize: minimalStaticWebP.length,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test('JPEG routes to flutterDirect', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalJpeg,
        fileSize: minimalJpeg.length,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test(
        'payload beats URL: JPEG bytes served under .webp URL routes to flutterDirect',
        () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalJpeg,
        url: 'https://example.com/chapter1/page01.webp',
        isHeavy: true,
        fileSize: minimalJpeg.length,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test(
        'payload beats URL: tall AVIF bytes served under .jpg URL routes to convertAvifThenDirect',
        () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: tallStaticAvif,
        url: 'https://example.com/chapter1/page01.jpg',
        fileSize: tallStaticAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.convertAvifThenDirect));
    });

    test(
        'payload beats URL: avis AVIF bytes served under .jpg URL routes to nativeAnimated',
        () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: avisAvif,
        url: 'https://example.com/chapter1/page01.jpg',
        fileSize: avisAvif.length,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('empty header or zero fileSize routes to bypassError', () {
      expect(
        ImageRouteDecider.decide(
          headerBytes: Uint8List(0),
          fileSize: 0,
        ),
        equals(ImageRouteOutcome.bypassError),
      );

      expect(
        ImageRouteDecider.decide(
          fileSize: 0,
        ),
        equals(ImageRouteOutcome.bypassError),
      );

      expect(
        ImageRouteDecider.decide(
          fileSize: -1,
        ),
        equals(ImageRouteOutcome.bypassError),
      );
    });

    test('unknown/garbage payload routes to bypassError', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: garbageBytes,
        fileSize: garbageBytes.length,
      );
      expect(outcome, equals(ImageRouteOutcome.bypassError));
    });

    test('ReaderImagePipeline.decide delegates identically', () {
      final outcome = ReaderImagePipeline.decide(
        headerBytes: minimalAnimatedWebP,
        fileSize: minimalAnimatedWebP.length,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test(
        'nativeViewAvailable false falls back from nativeAnimated to flutterDirect',
        () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalAnimatedWebP,
        fileSize: minimalAnimatedWebP.length,
        nativeViewAvailable: false,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test('structured input: isConfirmedAnimatedWebP routes to nativeAnimated',
        () {
      final outcome = ImageRouteDecider.decide(
        isConfirmedAnimatedWebP: true,
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('structured input: avifBrand avis routes to nativeAnimated', () {
      final outcome = ImageRouteDecider.decide(
        avifBrand: 'avis',
      );
      expect(outcome, equals(ImageRouteOutcome.nativeAnimated));
    });

    test('structured input: tall non-avis AVIF routes to convertAvifThenDirect',
        () {
      final outcome = ImageRouteDecider.decide(
        isAvif: true,
        isAvisBrand: false,
        height: 5000,
      );
      expect(outcome, equals(ImageRouteOutcome.convertAvifThenDirect));
    });

    test('static WebP with large fileSize (3MB) routes to flutterDirect', () {
      final outcome = ImageRouteDecider.decide(
        headerBytes: minimalStaticWebP,
        fileSize: 3 * 1024 * 1024,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });

    test('plain webp url without confirmed animated flag routes to flutterDirect', () {
      final outcome = ImageRouteDecider.decide(
        url: 'https://example.com/chapter/page_1.webp',
        isHeavy: false,
      );
      expect(outcome, equals(ImageRouteOutcome.flutterDirect));
    });
  });
}
