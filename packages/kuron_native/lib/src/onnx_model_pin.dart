import 'dart:convert';

import 'package:flutter/services.dart';

/// Pinned ONNX model identity — the single source of truth for the runtime
/// model download (`assets/model.pin.json`, ~1KB, bundled as asset text).
///
/// Deliberately NOT mirrored as Dart constants: the loader reads the same
/// file Gradle pins, so a pin-shape change breaks the loader test instead of
/// silently drifting.
class OnnxModelPin {
  const OnnxModelPin({
    required this.file,
    required this.version,
    required this.url,
    required this.sha256,
  });

  static const String assetKey = 'model.pin.json';

  final String file;
  final String version;
  final String url;
  final String sha256;

  static Future<OnnxModelPin> load({AssetBundle? bundle}) async {
    final raw =
        await (bundle ?? rootBundle).loadString(assetKey, cache: false);
    return parse(raw);
  }

  /// Throws [FormatException] when the pin is missing fields or malformed —
  /// a pin-shape change without a loader update fails loudly, not silently.
  static OnnxModelPin parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('model.pin.json must be a JSON object');
    }
    String field(String name) {
      final value = decoded[name];
      if (value is! String || value.isEmpty) {
        throw FormatException('model.pin.json field "$name" missing or empty');
      }
      return value;
    }

    final pin = OnnxModelPin(
      file: field('file'),
      version: field('version'),
      url: field('url'),
      sha256: field('sha256'),
    );
    if (!pin.url.startsWith('https://') && !pin.url.startsWith('file://')) {
      throw FormatException('model.pin.json "url" must be https/file: ${pin.url}');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pin.sha256)) {
      throw const FormatException('model.pin.json "sha256" must be 64 hex chars');
    }
    if (!pin.file.endsWith('.onnx')) {
      throw FormatException('model.pin.json "file" must be .onnx: ${pin.file}');
    }
    return pin;
  }
}
