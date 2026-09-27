import 'dart:convert';
import 'dart:typed_data';

// Exact port of keiyoushi `src/en/comix` Cipher.kt.
//
// Comix.to API signing uses a 3-round sbox substitution cipher. The cipher
// material (sboxes 3x256 + keys 3x24/32) is captured at runtime by hijacking
// `window.atob` inside the per-request WebView (see WebViewProxyEngine).
// Once valid material is cached, Tier-1 native signed API calls work until
// the server rotates keys (failure resets the cache).

/// Cipher material captured from the WebView `atob` hijack.
class CipherMaterial {
  const CipherMaterial({required this.sboxes, required this.keys});

  final List<List<int>> sboxes;
  final List<List<int>> keys;

  bool get isValid =>
      sboxes.length == 3 &&
      sboxes.every((s) => s.length == 256) &&
      keys.length == 3 &&
      keys.every((k) => k.isNotEmpty);

  factory CipherMaterial.fromJson(Map<String, dynamic> json) => CipherMaterial(
        sboxes: (json['sboxes'] as List)
            .map((s) => (s as List).map((v) => (v as num).toInt()).toList())
            .toList(),
        keys: (json['keys'] as List)
            .map((k) => (k as List).map((v) => (v as num).toInt()).toList())
            .toList(),
      );

  Map<String, dynamic> toJson() => {'sboxes': sboxes, 'keys': keys};
}

/// Encrypted API envelope `{"e":"..."}` returned for signed requests.
class EncryptedResponse {
  const EncryptedResponse(this.e);

  final String e;

  factory EncryptedResponse.fromJson(Map<String, dynamic> json) =>
      EncryptedResponse(json['e'] as String);
}

/// Raw WebView result: captured payload plus optional fresh cipher material.
class WebViewCapture {
  const WebViewCapture({required this.payload, this.material});

  final String payload;
  final CipherMaterial? material;

  factory WebViewCapture.fromJson(Map<String, dynamic> json) => WebViewCapture(
        payload: json['payload'] as String,
        material: json['material'] == null
            ? null
            : CipherMaterial.fromJson(json['material'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() =>
      {'payload': payload, 'material': material?.toJson()};
}

/// 3-round sbox substitution cipher (Cipher.kt `ComixCipher`).
class ComixCipher {
  ComixCipher(CipherMaterial material)
      : sboxes = material.sboxes.map((s) => List<int>.of(s)).toList(),
        keys = material.keys.map((k) => List<int>.of(k)).toList() {
    if (!material.isValid) {
      throw ArgumentError('Invalid Comix cipher material');
    }
  }

  final List<List<int>> sboxes;
  final List<List<int>> keys;

  static const List<int> previous = [189, 133, 32];

  /// Signs [path] + [query] into the `_` query token.
  String sign(String path, String query) {
    final stripped =
        path.startsWith('/api/v1') ? path.substring('/api/v1'.length) : path;
    var raw = Uint8List.fromList(
        utf8.encode(stripped + (query.isNotEmpty ? '?$query' : '')));
    for (var round = 0; round < 3; round++) {
      raw = _substitute(raw, sboxes[round], keys[round], previous[round]);
    }
    return base64Url.encode(raw).replaceAll('=', '');
  }

  /// Decrypts an `{"e": ...}` envelope value.
  String decrypt(String value) {
    var data = base64Url.decode(_pad(value));
    for (var round = 2; round >= 0; round--) {
      data =
          _substituteInverse(data, sboxes[round], keys[round], previous[round]);
    }
    return utf8.decode(data);
  }

  static String _pad(String value) {
    final mod = value.length % 4;
    if (mod == 0) return value;
    return value + '=' * (4 - mod);
  }

  static Uint8List _substitute(
      List<int> data, List<int> sbox, List<int> key, int prevStart) {
    final output = Uint8List(data.length);
    var prev = prevStart;
    for (var i = 0; i < data.length; i++) {
      final substituted =
          sbox[((data[i] & 0xff) ^ key[i % key.length] ^ prev) & 0xff];
      output[i] = substituted;
      prev = substituted;
    }
    return output;
  }

  static Uint8List _substituteInverse(
      List<int> data, List<int> sbox, List<int> key, int prevStart) {
    final inverse = List<int>.filled(256, 0);
    for (var i = 0; i < sbox.length; i++) {
      inverse[sbox[i] & 0xff] = i;
    }
    final output = Uint8List(data.length);
    var prev = prevStart;
    for (var i = 0; i < data.length; i++) {
      final value = data[i] & 0xff;
      output[i] = inverse[value] ^ key[i % key.length] ^ prev;
      prev = value;
    }
    return output;
  }

  /// Canonical query entries for signing (Cipher.kt `canonicalEntries`):
  /// sorted keys, `[]` suffix stripped, multi-values expanded as name[index].
  static List<MapEntry<String, String>> canonicalEntries(
      Map<String, List<String>> params) {
    final out = <MapEntry<String, String>>[];
    final names = params.keys.toList()..sort();
    for (final rawName in names) {
      final values = params[rawName]!;
      final name = rawName.endsWith('[]')
          ? rawName.substring(0, rawName.length - 2)
          : rawName;
      if (values.length == 1 && !rawName.endsWith('[]')) {
        out.add(MapEntry(name, values.single));
      } else {
        for (var i = 0; i < values.length; i++) {
          out.add(MapEntry('$name[$i]', values[i]));
        }
      }
    }
    return out;
  }
}
