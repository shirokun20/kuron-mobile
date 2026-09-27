import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:logger/logger.dart';

// Exact port of keiyoushi `src/en/comix` Descrambler.kt (dio variant).
//
// Two scrambling types, detected from case-insensitive `x-*` headers:
// - XOR byte encoding (`X-Enc-Seed`/`X-Enc-Algo`/`X-Enc-Len`)
// - Grid 5x5 tile shuffle (`X-Scramble-Seed`/`X-Scramble-Grid`/
//   `X-Scramble-Algo`/`X-Scramble-Hash`)
//
// All 32-bit arithmetic emulates Kotlin Int wrapping explicitly because
// Dart ints are 64-bit.

const int _encMultiplier = 1000005;
const int _encIncrement = 1234567891;
const int _lcgMultiplier = 1664525;
const int _lcgIncrement = 1013904223;

const int _gridCols = 5;
const int _gridRows = 5;
const int _numTiles = _gridCols * _gridRows;

const _mask32 = 0xFFFFFFFF;

/// Wrap to signed 32-bit (Kotlin Int semantics).
int _i32(int v) {
  v &= _mask32;
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

/// Unsigned 32-bit value of [v].
int _u32(int v) => v & _mask32;

/// Kotlin `state ushr 24` for a wrapped 32-bit state.
int _topByte(int state) => _u32(state) >>> 24;

int _nextXorshiftState(int state) {
  var next = state;
  next = _i32(next ^ (next << 13));
  next = _i32(next ^ (_u32(next) >>> 17));
  return _i32(next ^ (next << 5));
}

/// Pure decoding primitives (unit-testable without Dio).
class ComixDescrambler {
  const ComixDescrambler();

  static int decodeScrambleHash(String? hash) => switch (hash?.trim()) {
        '03632' => 58414,
        '02900' => 117532,
        _ => 0,
      };

  static bool hasImageSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final riff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final png = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    return riff || jpeg || png;
  }

  static Uint8List decodeWithLcg(Uint8List bytes, int seed, int length) {
    final result = Uint8List.fromList(bytes);
    var state = _i32(seed);
    final limit = result.length < length ? result.length : length;
    for (var i = 0; i < limit; i++) {
      state = _i32(state * _encMultiplier + _encIncrement);
      result[i] = result[i] ^ _topByte(state);
    }
    return result;
  }

  static Uint8List decodeWithXorshift(
      Uint8List bytes, int initialState, int length, bool highByte) {
    final result = Uint8List.fromList(bytes);
    var state = _i32(initialState);
    final limit = result.length < length ? result.length : length;
    for (var i = 0; i < limit; i++) {
      state = _nextXorshiftState(state);
      final key = highByte ? _topByte(state) : _u32(state) & 0xFF;
      result[i] = result[i] ^ key;
    }
    return result;
  }

  static Uint8List decodeEncodedBytes(
      Uint8List bytes, int seed, int length, String? algo) {
    if (algo != '2') return decodeWithLcg(bytes, seed, length);
    final candidates = [
      decodeWithXorshift(bytes, _i32(seed | 1), length, false),
      decodeWithXorshift(bytes, seed, length, false),
      decodeWithXorshift(bytes, _i32(seed | 1), length, true),
      decodeWithLcg(bytes, seed, length),
    ];
    return candidates.firstWhere(
      hasImageSignature,
      orElse: () => candidates.first,
    );
  }

  /// Inverse permutation for the 5x5 grid (algo "3" = Xorshift, else LCG).
  static List<int> buildOrder(int seed, int n, {required bool xorshift}) {
    final arr = List<int>.generate(n, (i) => i);
    var state = xorshift ? _i32(seed | 1) : _i32(seed);
    for (var i = n - 1; i >= 1; i--) {
      state = xorshift
          ? _nextXorshiftState(state)
          : _i32(state * _lcgMultiplier + _lcgIncrement);
      final j = _u32(state) % (i + 1);
      final tmp = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
    final inverse = List<int>.filled(n, 0);
    for (var i = 0; i < arr.length; i++) {
      inverse[arr[i]] = i;
    }
    return inverse;
  }

  /// Grid 5x5 descramble; returns JPEG bytes (quality 90) or null when the
  /// input does not decode to an image (caller must 500 like upstream).
  static Uint8List? descrambleGrid(Uint8List bytes, int seed, String? algo) {
    final bitmap = img.decodeImage(bytes);
    if (bitmap == null) return null;
    final width = bitmap.width;
    final height = bitmap.height;
    final tileW = width ~/ _gridCols;
    final tileH = height ~/ _gridRows;
    final order = buildOrder(seed, _numTiles, xorshift: algo == '3');
    final output = img.Image(width: width, height: height);
    for (var dstIdx = 0; dstIdx < _numTiles; dstIdx++) {
      final srcIdx = order[dstIdx];
      final tile = img.copyCrop(
        bitmap,
        x: (srcIdx % _gridCols) * tileW,
        y: (srcIdx ~/ _gridCols) * tileH,
        width: tileW,
        height: tileH,
      );
      img.compositeImage(
        output,
        tile,
        dstX: (dstIdx % _gridCols) * tileW,
        dstY: (dstIdx ~/ _gridCols) * tileH,
      );
    }
    return Uint8List.fromList(img.encodeJpg(output, quality: 90));
  }

  /// XOR-only path: JPEG-95 when decodable, else raw bytes.
  static ({Uint8List bytes, bool jpeg}) decodeXorOnly(Uint8List bytes) {
    final bitmap = img.decodeImage(bytes);
    if (bitmap != null) {
      return (
        bytes: Uint8List.fromList(img.encodeJpg(bitmap, quality: 95)),
        jpeg: true,
      );
    }
    return (bytes: bytes, jpeg: false);
  }
}

/// Dio response interceptor implementing Descrambler.kt `interceptor`.
class ComixDescramblerInterceptor extends Interceptor {
  ComixDescramblerInterceptor({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  String? _header(Map<String, List<String>> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name && e.value.isNotEmpty) {
        return e.value.first;
      }
    }
    return null;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final headers = response.headers.map;
      final encSeed = int.tryParse(_header(headers, 'x-enc-seed') ?? '');
      final encLen = int.tryParse(_header(headers, 'x-enc-len') ?? '');
      final encAlgo = _header(headers, 'x-enc-algo');
      final grid = _header(headers, 'x-scramble-grid');
      final gridAlgo = _header(headers, 'x-scramble-algo');
      final scrambleSeed =
          int.tryParse(_header(headers, 'x-scramble-seed') ?? '');
      final scrambleHash = ComixDescrambler.decodeScrambleHash(
        _header(headers, 'x-scramble-hash'),
      );

      final xorSeed = encSeed;
      final xorLen = encLen;
      final gridSeed = scrambleSeed;
      final needsXor = xorSeed != null && xorSeed != 0 && xorLen != null;
      final shouldDescrambleGrid = grid == '5x5' &&
          (gridAlgo == null ||
              gridAlgo == '1' ||
              gridAlgo == '2' ||
              gridAlgo == '3') &&
          gridSeed != null &&
          gridSeed != 0;

      if (!needsXor && !shouldDescrambleGrid) {
        handler.next(response);
        return;
      }

      final original = response.data is Uint8List
          ? response.data as Uint8List
          : Uint8List.fromList(
              List<int>.from(response.data as List<int>),
            );
      final bytes = needsXor
          ? ComixDescrambler.decodeEncodedBytes(
              original, xorSeed, xorLen, encAlgo)
          : original;

      if (shouldDescrambleGrid) {
        final out = ComixDescrambler.descrambleGrid(
          bytes,
          _i32(gridSeed ^ scrambleHash),
          gridAlgo,
        );
        if (out == null) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: 'Failed to decode image',
              type: DioExceptionType.badResponse,
            ),
          );
          return;
        }
        response.headers.removeAll('Content-Length');
        response.headers.removeAll('Content-Type');
        response.headers.set('Content-Type', 'image/jpeg');
        handler.resolve(response..data = out);
        return;
      }

      final decoded = ComixDescrambler.decodeXorOnly(bytes);
      if (decoded.jpeg) {
        response.headers.removeAll('Content-Encoding');
        response.headers.set('Content-Type', 'image/jpeg');
        response.headers.set('Content-Length', decoded.bytes.length.toString());
        handler.resolve(response..data = decoded.bytes);
      } else {
        response.headers.removeAll('Content-Encoding');
        response.headers.removeAll('Content-Length');
        response.headers.removeAll('Content-Type');
        handler.resolve(response..data = decoded.bytes);
      }
    } catch (e) {
      _logger.w('comix: descrambler passthrough on error: $e');
      handler.next(response);
    }
  }
}
