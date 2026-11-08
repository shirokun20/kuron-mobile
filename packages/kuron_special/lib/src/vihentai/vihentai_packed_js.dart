// Decoder for ViHentai packed JavaScript eval-based image URL extraction.
///
// Ported from Tachiyomi's ViHentaiPacker.kt.
// Chapter pages embed images in an obfuscated
// eval(function(h,u,n,t,e,r){...}(...)) script.
// Args: h=encoded data, n=charset, t=offset, e=base & delimiter index (n[e]).
// Decoded output: KuroReader('#chapter-content', ["url1","url2",...], 0)
library;

// Thrown when packed JS parameters are inconsistent or extraction fails.

class ViHentaiPackedJsException implements Exception {
  final String message;
  const ViHentaiPackedJsException(this.message);

  @override
  String toString() => 'ViHentaiPackedJsException: $message';
}

// Static utility for extracting image URLs from ViHentai packed JS.
class ViHentaiPackedJs {
  // Regex to extract image URLs from decoded KuroReader output.
  static final _imageUrlRegex = RegExp(
    r'"(https?://[^"]+\.\w{3,4})"',
  );
  static const _baseCharset =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/';

  // Regex to extract eval params: `}("h",u,"n",t,e,r)`
  static final _packedArgsRegex = RegExp(
    r'\}\("(.+)",\s*(\d+),\s*"([^"]+)",\s*(\d+),\s*(\d+),\s*(\d+)\)',
  );

  // Main entry: extract image URLs from the packed JavaScript.
  // Falls back to `<img>` tag extraction if no packed script found.
  static List<String> extractImageUrls(String scriptData) {
    if (scriptData.isEmpty) return [];

    try {
      final decoded = _unpack(scriptData).replaceAll(r'\/', '/');
      final urls =
          _imageUrlRegex.allMatches(decoded).map((m) => m.group(1)!).toList();
      if (urls.isNotEmpty) return urls;
    } on ViHentaiPackedJsException {
      // Fall through to img tag extraction
    }

    // Fallback: direct <img> tags
    final imgUrls = _extractDirectImgUrls(scriptData);
    if (imgUrls.isNotEmpty) return imgUrls;
    return [];
  }

  // Extract URLs from `<img>` tags.
  static List<String> _extractDirectImgUrls(String html) {
    return RegExp(
      r'<img\s[^>]*src="([^"]+\.(?:png|jpg|webp|jpeg))"',
      caseSensitive: false,
    ).allMatches(html).map((m) => m.group(1)!).toList();
  }

  // Decode packed JS: extract params, un-obfuscate, return plain text.
  // Pure Dart (sole implementation — restored verified fallback, ported
  // from Tachiyomi's ViHentaiPacker.kt).
  static String _unpack(String script) {
    final argsMatch = _packedArgsRegex.firstMatch(script);
    if (argsMatch == null) {
      throw ViHentaiPackedJsException(
        'Could not parse packed script arguments',
      );
    }

    final h = argsMatch.group(1)!;
    final n = argsMatch.group(3)!;
    final t = int.parse(argsMatch.group(4)!);
    final e = int.parse(argsMatch.group(5)!);

    final delimiter = n[e];
    final result = StringBuffer();
    var i = 0;

    while (i < h.length) {
      final s = StringBuffer();
      while (i < h.length && h[i] != delimiter) {
        s.write(h[i]);
        i++;
      }
      i++; // skip delimiter

      var segment = s.toString();
      // Replace each char with its index in charset
      for (var j = 0; j < n.length; j++) {
        segment = segment.replaceAll(n[j], j.toString());
      }

      final code = _baseConvert(segment, e) - t;
      if (code >= 0 && code <= 0x10FFFF) {
        result.writeCharCode(code);
      }
    }

    return result.toString();
  }

  // Convert a custom-base number string to int.
  static int _baseConvert(String d, int fromBase) {
    final chars = _baseCharset.substring(0, fromBase);
    var result = 0;
    for (var i = 0; i < d.length; i++) {
      final c = d[d.length - 1 - i];
      final pos = chars.indexOf(c);
      if (pos >= 0) {
        result += pos * _pow(fromBase, i);
      }
    }
    return result;
  }

  static int _pow(int base, int exp) {
    var result = 1;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }
}
