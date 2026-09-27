// AES-encrypted chapter-protector payload used by the Madara
// `wp-manga-chapter-images-protection` plugin (octopusmanga, cucumbermanga …).
//
// The chapter HTML ships an empty `.theimage > .loader` placeholder per page
// and hides the real URL list in
// `<script id="chapter-protector-data">var chapter_data='{"ct":…,"s":…}';
//  var wpmangaprotectornonce='…';`. The plugin's obfuscated runtime derives
// the key with OpenSSL `EVP_BytesToKey` (MD5, 1 iteration) from the nonce plus
// the per-request salt, then AES-256-CBC decrypts `ct`. Plaintext is a JSON
// *string* wrapping a JSON array of image URLs.
//
// Issue #63.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';
import 'package:pointycastle/export.dart';

class ChapterProtectorDecoder {
  final Logger _logger;
  final String _sourceId;

  ChapterProtectorDecoder({required Logger logger, required String sourceId})
      : _logger = logger,
        _sourceId = sourceId;

  /// Decrypts the protector payload in [htmlContent] and returns the image
  /// URLs, or an empty list when the page carries no (or an undecryptable)
  /// protector payload. Callers fall back to normal scraping on empty.
  List<String> extractImageUrls(String htmlContent) {
    final payload = _parsePayload(htmlContent);
    if (payload == null) return const [];

    final ct = payload['ct'];
    final salt = payload['s'];
    final nonce = _nonce(htmlContent);
    if (ct is! String || ct.isEmpty || salt is! String || salt.isEmpty) {
      _logger.w('$_sourceId chapter-protector: payload missing ct/s');
      return const [];
    }
    if (nonce == null || nonce.isEmpty) {
      _logger.w('$_sourceId chapter-protector: nonce not found');
      return const [];
    }

    final saltBytes = _hexToBytes(salt);
    if (saltBytes == null) {
      _logger.w('$_sourceId chapter-protector: salt is not hex');
      return const [];
    }

    try {
      final cipherBytes = base64.decode(ct);
      final block = _evpBytesToKey(utf8.encode(nonce), saltBytes);
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          false,
          PaddedBlockCipherParameters<ParametersWithIV, CipherParameters>(
            ParametersWithIV<KeyParameter>(
              KeyParameter(Uint8List.fromList(block.sublist(0, 32))),
              Uint8List.fromList(block.sublist(32, 48)),
            ),
            null,
          ),
        );

      final plaintext =
          utf8.decode(cipher.process(Uint8List.fromList(cipherBytes)));

      // Plaintext is a JSON string wrapping a JSON array — decode twice.
      final images = json.decode(json.decode(plaintext) as String) as List;
      final urls = images
          .map((u) => u.toString().trim())
          .where((u) => u.isNotEmpty)
          .toList();
      _logger
          .d('$_sourceId chapter-protector: decrypted ${urls.length} images');
      return urls;
    } catch (e) {
      _logger.w('$_sourceId chapter-protector: decrypt failed', error: e);
      return const [];
    }
  }

  /// `{"ct":"<base64>","s":"<hex salt>"}` from `var chapter_data='…';`
  /// inside `#chapter-protector-data`. The `iv` field is ignored on purpose:
  /// the IV comes out of the key chain, which also covers payloads that omit
  /// it.
  Map<String, dynamic>? _parsePayload(String htmlContent) {
    final script = RegExp(
      r'''<script[^>]*id="chapter-protector-data"[^>]*>(.*?)</script>''',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(htmlContent);
    if (script == null) return null;

    final assignment = RegExp(
      r'''chapter_data\s*=\s*'([^']*)'\s*;''',
      dotAll: true,
    ).firstMatch(script.group(1)!);
    if (assignment == null) return null;

    try {
      final body =
          assignment.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\/', '/');
      final decoded = json.decode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      _logger.w('$_sourceId chapter-protector: payload JSON parse failed',
          error: e);
      return null;
    }
  }

  String? _nonce(String htmlContent) =>
      RegExp(r"wpmangaprotectornonce\s*=\s*'([^']*)'")
          .firstMatch(htmlContent)
          ?.group(1);

  /// OpenSSL `EVP_BytesToKey` with MD5, 1 iteration, no salt:
  /// D1 = MD5(p ‖ s); Dk = MD5(D{k-1} ‖ p ‖ s) — 48 bytes = key ‖ iv.
  static List<int> _evpBytesToKey(List<int> password, List<int> salt) {
    final buffer = BytesBuilder();
    var previous = <int>[];
    while (buffer.length < 48) {
      previous = md5.convert(<int>[...previous, ...password, ...salt]).bytes;
      buffer.add(previous);
    }
    return buffer.toBytes().sublist(0, 48);
  }

  static List<int>? _hexToBytes(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      return null;
    }
    return <int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
}
