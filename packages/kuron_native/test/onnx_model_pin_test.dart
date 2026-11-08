import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnnxModelPin.parse', () {
    const valid = '''
{"file": "bubble_detector.onnx", "version": "1",
 "url": "https://example.com/m.onnx",
 "sha256": "4f5fa56ff1c84527ad8417e1c02b0862392f6f259acc95ed97813861cd50a034"}''';

    test('parses a valid pin', () {
      final pin = OnnxModelPin.parse(valid);
      expect(pin.file, 'bubble_detector.onnx');
      expect(pin.version, '1');
      expect(pin.url, startsWith('https://'));
      expect(pin.sha256, hasLength(64));
    });

    test('rejects missing fields', () {
      expect(
        () => OnnxModelPin.parse('{"file": "a.onnx"}'),
        throwsFormatException,
      );
    });

    test('rejects malformed sha256 (integrity core)', () {
      expect(
        () => OnnxModelPin.parse(
          '{"file": "m.onnx", "version": "1", "url": "https://x/y", "sha256": "zzz"}',
        ),
        throwsFormatException,
      );
    });
  });

  group('OnnxModelPin.load (real pin file)', () {
    test('loads the real pin file with expected shape', () async {
      // Reads the same single-source file the app bundles
      // (assets/model.pin.json) through an injected bundle — fails when the
      // pin changes shape without a loader update. No mirrored constants.
      // CWD differs: package root when run via `flutter test` inside the
      // package, repo root when run via path from the repo root.
      String? raw;
      for (final candidate in [
        '../../assets/model.pin.json',
        'assets/model.pin.json',
      ]) {
        final file = File(candidate);
        if (await file.exists()) {
          raw = await file.readAsString();
          break;
        }
      }
      if (raw == null) {
        fail('real model.pin.json not found from ${Directory.current.path}');
      }
      final pin = await OnnxModelPin.load(
        bundle: _MapBundle({OnnxModelPin.assetKey: raw}),
      );
      expect(pin.file, 'bubble_detector.onnx');
      expect(pin.version, isNotEmpty);
      expect(pin.url, startsWith('https://'));
      expect(pin.sha256, matches(RegExp(r'^[0-9a-fA-F]{64}$')));
    });
  });
}

/// Minimal in-memory [AssetBundle] for loader tests.
class _MapBundle extends AssetBundle {
  _MapBundle(this._strings);

  final Map<String, String> _strings;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _strings[key];
    if (value == null) throw FlutterError('Missing stub asset: $key');
    return value;
  }

  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Not stubbed: $key');
}
