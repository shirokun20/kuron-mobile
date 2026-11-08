import 'dart:convert';

class HentaiNexusDecryptor {
  static const List<int> _primeNumbers = <int>[2, 3, 5, 7, 11, 13, 17, 19];
  static final RegExp _imageUrlPattern = RegExp(
    r'https?://images\.hentainexus\.com/[^"\s<>()]+?\.(?:jpg|jpeg|png|webp|avif)(?:\.thumb\.jpg)?',
    caseSensitive: false,
  );

  static List<int> _firstPrimes(int count) {
    final primes = <int>[];
    var n = 2;

    while (primes.length < count) {
      var isPrime = true;
      for (var i = 2; i * i <= n; i++) {
        if (n % i == 0) {
          isPrime = false;
          break;
        }
      }
      if (isPrime) {
        primes.add(n);
      }
      n++;
    }

    return primes;
  }

  // Mirrors the site reader algorithm from `reader.min.js` initReader().
  static String decrypt({
    required String encrypted,
    String hostname = 'hentainexus.com',
  }) {
    final data = base64Decode(encrypted);
    if (data.length <= 64) {
      throw const FormatException('HentaiNexus seed payload is too short');
    }

    // Pure Dart (sole implementation — restored verified fallback, mirrors
    // the site reader algorithm from `reader.min.js` initReader()).
    final hostCodes = hostname.codeUnits;
    final xorLen =
        hostCodes.length < data.length ? hostCodes.length : data.length;
    for (var i = 0; i < xorLen; i++) {
      data[i] = data[i] ^ hostCodes[i];
    }

    final keyStream = data.sublist(0, 64);
    final ciphertext = data.sublist(64);
    final digest = List<int>.generate(256, (i) => i);

    var primeIdx = 0;
    for (var i = 0; i < 64; i++) {
      primeIdx ^= keyStream[i];
      for (var j = 0; j < 8; j++) {
        if ((primeIdx & 1) != 0) {
          primeIdx = (primeIdx >> 1) ^ 12;
        } else {
          primeIdx = primeIdx >> 1;
        }
      }
    }
    primeIdx &= 7;

    var key = 0;
    for (var i = 0; i < 256; i++) {
      key = (key + digest[i] + keyStream[i % 64]) % 256;
      final temp = digest[i];
      digest[i] = digest[key];
      digest[key] = temp;
    }

    final q = _primeNumbers[primeIdx];
    var k = 0;
    var n = 0;
    var p = 0;
    var xorKey = 0;

    final outCodes = <int>[];
    for (var i = 0; i < ciphertext.length; i++) {
      k = (k + q) % 256;
      n = (p + digest[(n + digest[k]) % 256]) % 256;
      p = (p + k + digest[k]) % 256;

      final temp = digest[k];
      digest[k] = digest[n];
      digest[n] = temp;

      xorKey =
          digest[(n + digest[(k + digest[(xorKey + p) % 256]) % 256]) % 256];
      outCodes.add(ciphertext[i] ^ xorKey);
    }

    return String.fromCharCodes(outCodes);
  }

  // Kept for future experiments with alternative server variants.
  static List<int> firstPrimesForDebug(int count) {
    return _firstPrimes(count);
  }

  static List<String> extractImageUrls(String decryptedJson) {
    final decoded = jsonDecode(decryptedJson);
    final urls = _extractImageUrlsFromDecoded(decoded);
    if (urls.isNotEmpty) {
      return urls;
    }

    return _extractImageUrlsFromText(decryptedJson);
  }

  static List<String> extractImageUrlsFromHtml(String html) {
    return _extractImageUrlsFromText(html);
  }

  static List<String> _extractImageUrlsFromDecoded(dynamic decoded) {
    if (decoded is List) {
      final urls = <String>[];
      for (final item in decoded) {
        urls.addAll(_extractImageUrlsFromDecoded(item));
      }
      return _dedupe(urls);
    }

    if (decoded is! Map) {
      return const [];
    }

    final urls = <String>[];
    final normalized = decoded.cast<Object?, Object?>();
    final type = normalized['type']?.toString();

    if (type == 'image') {
      final image = normalized['image']?.toString();
      if (image != null && image.isNotEmpty) {
        urls.add(_normalizeImageUrl(image));
      }
    } else if (type == 'url') {
      final url = normalized['url']?.toString();
      if (url != null && url.isNotEmpty) {
        urls.add(_normalizeImageUrl(url));
      }
    } else if (type == 'spread') {
      final left = normalized['url']?.toString();
      final right = normalized['nextLink']?.toString();
      if (left != null && left.isNotEmpty) {
        urls.add(_normalizeImageUrl(left));
      }
      if (right != null && right.isNotEmpty) {
        urls.add(_normalizeImageUrl(right));
      }
    }

    for (final value in normalized.values) {
      if (value is String) {
        urls.addAll(_extractImageUrlsFromText(value));
      } else if (value is List || value is Map) {
        urls.addAll(_extractImageUrlsFromDecoded(value));
      }
    }

    return _dedupe(urls);
  }

  static List<String> _extractImageUrlsFromText(String text) {
    final urls = <String>[];
    for (final match in _imageUrlPattern.allMatches(text)) {
      final raw = match.group(0);
      if (raw == null || raw.isEmpty) continue;
      urls.add(_normalizeImageUrl(raw));
    }
    return _dedupe(urls);
  }

  static String _normalizeImageUrl(String url) {
    return url.replaceFirst(RegExp(r'\.thumb\.jpg$', caseSensitive: false), '');
  }

  static List<String> _dedupe(List<String> urls) {
    final bestByPage = <String, String>{};
    final orderedKeys = <String>[];

    for (final rawUrl in urls) {
      if (rawUrl.isEmpty) continue;

      final url = _normalizeImageUrl(rawUrl);
      final pageKey = _pageKey(url);
      final current = bestByPage[pageKey];

      if (current == null) {
        bestByPage[pageKey] = url;
        orderedKeys.add(pageKey);
        continue;
      }

      if (_formatPriority(url) < _formatPriority(current)) {
        bestByPage[pageKey] = url;
      }
    }

    return orderedKeys.map((key) => bestByPage[key]!).toList(growable: false);
  }

  static String _pageKey(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final lastSegment =
        path.split('/').where((segment) => segment.isNotEmpty).last;
    return lastSegment.replaceFirst(
      RegExp(r'\.(?:avif|webp|png|jpe?g)$', caseSensitive: false),
      '',
    );
  }

  static int _formatPriority(String url) {
    final lowered = url.toLowerCase();
    if (lowered.endsWith('.webp')) return 0;
    if (lowered.endsWith('.png')) return 1;
    if (lowered.endsWith('.jpg') || lowered.endsWith('.jpeg')) return 2;
    if (lowered.endsWith('.avif')) return 3;
    return 4;
  }
}
