import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compresses a full page image to max 1280px longest side, JPEG 85%,
/// for the no-bubble fallback path. Providers map percentage coordinates
/// back to original pixel space using the ORIGINAL page dimensions.
/// Pure Dart (`package:image`); undecodable input returns bytes unchanged.
class FallbackImageHandler {
  FallbackImageHandler();

  static const int maxDimension = 1280;

  Uint8List compressPage(Uint8List image) {
    final decoded = img.decodeImage(image);
    if (decoded == null) return image;

    img.Image scaled = decoded;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > maxDimension) {
      final ratio = maxDimension / longest;
      scaled = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    return img.encodeJpg(scaled, quality: 85);
  }
}
