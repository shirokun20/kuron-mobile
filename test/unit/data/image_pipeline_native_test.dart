import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nhasixapp/data/repositories/ai/fallback_image_handler.dart';
import 'package:nhasixapp/data/repositories/ai/mosaic_builder.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';

/// Dart-only image pipeline (Rust removed): these tests pin the semantics
/// that keep the pipeline alive (chunk ≤1280px, mosaic cap 2MB,
/// compress 1280px, undecodable → bytes asli).
void main() {
  Uint8List makePage(int w, int h) => Uint8List.fromList(
      img.encodeJpg(img.Image(width: w, height: h), quality: 90));

  test('compressPage keeps constraints when already small', () {
    final page = makePage(800, 600);
    final out = FallbackImageHandler().compressPage(page);
    // Dart fallback re-encodes (JPEG85) — dimensions preserved, still valid.
    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, 800);
    expect(decoded.height, 600);
  });

  test('compressPage resizes longest side to 1280', () {
    final page = makePage(900, 1800);
    final out = FallbackImageHandler().compressPage(page);
    final decoded = img.decodeImage(out);
    expect(decoded, isNotNull);
    expect(decoded!.height, lessThanOrEqualTo(1280));
    expect(decoded.width, 900 * 1280 ~/ 1800);
  });

  test('compressPage returns original bytes for undecodable input', () {
    // Pathological input (not an image): no crash/OOM, bytes pass through.
    final garbage = Uint8List.fromList(List.generate(4096, (i) => i % 251));
    expect(FallbackImageHandler().compressPage(garbage), garbage);
  });

  group('real webtoon strip fixture (test/fixtures/image-webtoon.jpeg)', () {
    // Pure Dart path on host.
    Uint8List readFixture() {
      final file = File('test/fixtures/image-webtoon.jpeg');
      expect(file.existsSync(), isTrue, reason: 'fixture missing');
      return file.readAsBytesSync();
    }

    test('compressPage squeezes 7858px strip to <=1280 longest side', () {
      final out = FallbackImageHandler().compressPage(readFixture());
      final decoded = img.decodeImage(out);
      expect(decoded, isNotNull);
      expect(decoded!.height, lessThanOrEqualTo(1280));
      expect(decoded.width, lessThanOrEqualTo(1280));
    });

    test('buildMosaic produces a valid labelled mosaic under 2MB', () {
      final page = readFixture();
      final mosaic = MosaicBuilder().buildMosaic(page, const [
        BubbleBoxLike(50, 100, 300, 120),
        BubbleBoxLike(400, 900, 250, 100),
        BubbleBoxLike(100, 2000, 320, 140),
        BubbleBoxLike(350, 3200, 200, 90),
        BubbleBoxLike(60, 4500, 280, 110),
      ]);
      expect(mosaic.length, lessThan(2 * 1024 * 1024));
      final decoded = img.decodeImage(mosaic);
      expect(decoded, isNotNull);
      expect(decoded!.height, greaterThan(0));
      expect(decoded.width, greaterThan(56));
    });
  });
}
