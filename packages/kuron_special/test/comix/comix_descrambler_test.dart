import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kuron_special/src/comix/comix_descrambler.dart';

// Vectors generated from an independent Python mirror of Descrambler.kt
// (see session log): LCG / Xorshift / buildOrder known-answer hex.
void main() {
  Uint8List input() => Uint8List.fromList(List<int>.generate(64, (i) => i));

  String hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  test('decodeWithLcg matches reference', () {
    expect(
      hex(ComixDescrambler.decodeWithLcg(input(), 123456789, 64))
          .substring(0, 64),
      'f438c7817b346df5fa7bdfa253f4c8774ebab3c4442e12c74e5548b60850092f',
    );
  });

  test('decodeWithXorshift matches reference (low + high byte)', () {
    expect(
      hex(ComixDescrambler.decodeWithXorshift(input(), 987654321, 64, false))
          .substring(0, 64),
      'f5ac34086b7271f18e718c337173f9db3b85795b3ba622bdae2713e636eaa165',
    );
    expect(
      hex(ComixDescrambler.decodeWithXorshift(input(), 987654321, 64, true))
          .substring(0, 64),
      '0e7a906e16a22db765433d7340d87466847ad4d94ea17185aaff4b2462d8a1e9',
    );
  });

  test('decode is its own inverse (round-trip)', () {
    final encoded = ComixDescrambler.decodeWithLcg(input(), 424242, 64);
    expect(ComixDescrambler.decodeWithLcg(encoded, 424242, 64), input());
    final xencoded =
        ComixDescrambler.decodeWithXorshift(input(), 777, 64, false);
    expect(
      ComixDescrambler.decodeWithXorshift(xencoded, 777, 64, false),
      input(),
    );
  });

  test('decodeEncodedBytes algo routing', () {
    final lcg = ComixDescrambler.decodeEncodedBytes(input(), 99, 64, '1');
    expect(lcg, ComixDescrambler.decodeWithLcg(input(), 99, 64));
    final jpegLike =
        Uint8List.fromList([0xFF, 0xD8, ...List<int>.generate(62, (i) => i)]);
    final routed = ComixDescrambler.decodeEncodedBytes(jpegLike, 99, 64, '2');
    expect(routed.length, 64);
  });

  test('hasImageSignature detects JPEG/PNG/WEBP', () {
    expect(
      ComixDescrambler.hasImageSignature(
        Uint8List.fromList([0xFF, 0xD8, ...List.filled(10, 0)]),
      ),
      isTrue,
    );
    expect(
      ComixDescrambler.hasImageSignature(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(8, 0)]),
      ),
      isTrue,
    );
    expect(
      ComixDescrambler.hasImageSignature(
        Uint8List.fromList('RIFFxxxxWEBP'.codeUnits + List.filled(4, 0)),
      ),
      isTrue,
    );
    expect(
      ComixDescrambler.hasImageSignature(
          Uint8List.fromList(List.filled(12, 0))),
      isFalse,
    );
    expect(
      ComixDescrambler.hasImageSignature(Uint8List.fromList([1, 2, 3])),
      isFalse,
    );
  });

  test('decodeScrambleHash matches mapping', () {
    expect(ComixDescrambler.decodeScrambleHash('03632'), 58414);
    expect(ComixDescrambler.decodeScrambleHash('02900'), 117532);
    expect(ComixDescrambler.decodeScrambleHash('zzz'), 0);
    expect(ComixDescrambler.decodeScrambleHash(null), 0);
  });

  test('buildOrder matches reference permutations', () {
    expect(
      ComixDescrambler.buildOrder(58414, 25, xorshift: true),
      [
        13,
        15,
        17,
        11,
        0,
        12,
        16,
        5,
        6,
        20,
        10,
        9,
        3,
        4,
        22,
        7,
        18,
        24,
        2,
        23,
        1,
        21,
        14,
        8,
        19
      ],
    );
    expect(
      ComixDescrambler.buildOrder(117532, 25, xorshift: false),
      [
        22,
        0,
        10,
        24,
        21,
        8,
        15,
        6,
        9,
        18,
        20,
        16,
        5,
        4,
        23,
        14,
        7,
        11,
        3,
        17,
        12,
        13,
        1,
        19,
        2
      ],
    );
  });

  test('grid descramble inverts grid scramble (round-trip)', () {
    // Build a 10x10 marker image (5x5 tiles of 2x2).
    final original = img.Image(width: 10, height: 10);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        original.setPixelRgb(x, y, x * 25, y * 25, (x + y) * 12);
      }
    }
    const seed = 58414;
    final order = ComixDescrambler.buildOrder(seed, 25, xorshift: false);
    // The server scrambles with the FORWARD shuffle; buildOrder returns its
    // inverse (what descramble applies). Recover forward: fwd[order[i]] = i.
    final forward = List<int>.filled(25, 0);
    for (var i = 0; i < 25; i++) {
      forward[order[i]] = i;
    }
    final scrambled = img.Image(width: 10, height: 10);
    for (var dstIdx = 0; dstIdx < 25; dstIdx++) {
      final srcIdx = forward[dstIdx];
      final tile = img.copyCrop(
        original,
        x: (srcIdx % 5) * 2,
        y: (srcIdx ~/ 5) * 2,
        width: 2,
        height: 2,
      );
      img.compositeImage(
        scrambled,
        tile,
        dstX: (dstIdx % 5) * 2,
        dstY: (dstIdx ~/ 5) * 2,
      );
    }
    final scrambledBytes = Uint8List.fromList(img.encodePng(scrambled));
    final outBytes = ComixDescrambler.descrambleGrid(scrambledBytes, seed, '1');
    expect(outBytes, isNotNull);
    final restored = img.decodeImage(outBytes!)!;
    // JPEG-90 round-trip: allow small per-channel drift.
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        final a = original.getPixel(x, y);
        final b = restored.getPixel(x, y);
        expect((a.r - b.r).abs(), lessThan(30), reason: 'r at $x,$y');
        expect((a.g - b.g).abs(), lessThan(30), reason: 'g at $x,$y');
        expect((a.b - b.b).abs(), lessThan(30), reason: 'b at $x,$y');
      }
    }
  });

  test('descrambleGrid returns null for non-image bytes', () {
    expect(
      ComixDescrambler.descrambleGrid(
        Uint8List.fromList(List.filled(64, 7)),
        1,
        '1',
      ),
      isNull,
    );
  });
}
