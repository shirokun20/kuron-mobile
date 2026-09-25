import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/pages/search/dynamic_form_search_ui.dart';

// Inverse of the doujin.desu.xxx `_enc_resp_` envelope so the picker decrypt
// hook can be exercised without a live request.
const _salt = 'doujindesu-scrapers-cannot-read-this-super-secret-salt-2026-v2';

int _slot() => DateTime.now().millisecondsSinceEpoch ~/ 3600000;

String _key(int slot) {
  final seed = '${_salt}_$slot';
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = (((hash << 5) - hash + c) & 0xFFFFFFFF).toSigned(32);
  }
  var m = hash.abs() == 0 ? 123456789 : hash.abs();
  final out = StringBuffer();
  for (var i = 0; i < 32; i++) {
    m = (m * 1664525 + 1013904223) % 4294967296;
    out.writeCharCode(33 + m % 93);
  }
  return out.toString();
}

String _encrypt(String plainAscii, String key) {
  final bytes = latin1.encode(plainAscii);
  final out = StringBuffer();
  var n = 42;
  for (var c = 0; c < bytes.length; c++) {
    final cipher =
        (bytes[c] ^ key.codeUnitAt(c % key.length) ^ (c * 13) ^ n) & 0xFF;
    out.write(cipher.toRadixString(16).padLeft(2, '0'));
    n = (n + cipher) & 0xFF;
  }
  return out.toString();
}

String _envelope(Object payload) =>
    _encrypt(Uri.encodeComponent(jsonEncode(payload)), _key(_slot()));

void main() {
  group('decodeDataSourcePayload', () {
    test('decrypts the doujindesuxxx envelope into a top-level list', () {
      final genres = [
        {'id': 452, 'name': 'Sole Male', 'slug': 'sole-male'},
        {'id': 69, 'name': 'Paizuri', 'slug': 'paizuri'},
      ];
      final decoded = decodeDataSourcePayload(
        {'_enc_resp_': _envelope(genres)},
        'doujindesuxxx',
      );

      expect(decoded, isA<List>());
      expect((decoded as List).length, 2);
      expect(decoded.first['slug'], 'sole-male');
    });

    test('passes through plain payloads untouched', () {
      final payload = {'data': <Object?>[]};
      expect(decodeDataSourcePayload(payload, null), same(payload));
      expect(decodeDataSourcePayload(payload, 'doujindesuxxx'), same(payload));
    });

    test('leaves other decryptors alone', () {
      final payload = {'_enc_resp_': 'deadbeef'};
      expect(decodeDataSourcePayload(payload, 'other'), same(payload));
    });

    test('throws a readable error when the envelope cannot be decrypted', () {
      expect(
        () => decodeDataSourcePayload({'_enc_resp_': 'zzzz'}, 'doujindesuxxx'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
