import 'package:dio/dio.dart';

// Image request policy + retry plumbing for comix-family sources
// (keiyoushi Comix.kt `imageRequest`, 404 fallbacks, server-error retry).

final _fallbackPathRegex = RegExp(r'/(?:i5|s?i+)/');

/// V3 grid-scramble pages must NOT send Origin — the server withholds
/// `X-Scramble-Seed` when Origin is present. Legacy byte-XOR pages need
/// Origin to receive `X-Enc-Seed` (Comix.kt `imageRequest`).
class ComixImagePolicy {
  const ComixImagePolicy._();

  static bool isLegacyScramble(String imageUrl) =>
      imageUrl.contains('#scrambled') && !isV3(imageUrl);

  static bool isV3(String imageUrl) {
    final withoutFragment = imageUrl.split('#').first;
    final uri = Uri.tryParse(withoutFragment);
    return uri != null && uri.queryParameters.containsKey('v3');
  }

  /// Request URL with the `#scrambled` marker stripped.
  static String requestUrl(String imageUrl) => imageUrl.split('#').first;

  static bool shouldRemoveOrigin(String imageUrl, String baseUrlHost) {
    final uri = Uri.tryParse(requestUrl(imageUrl));
    if (uri == null || uri.host.isEmpty) return false;
    return !uri.host.endsWith(baseUrlHost) && !isLegacyScramble(imageUrl);
  }
}

/// Strips `#scrambled` fragments and drops Origin for V3 cross-host images.
class ComixImageHeaderInterceptor extends Interceptor {
  ComixImageHeaderInterceptor({required String baseUrlHost})
      : _baseUrlHost = baseUrlHost;

  final String _baseUrlHost;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    var path = options.path;
    if (path.contains('#')) {
      path = ComixImagePolicy.requestUrl(path);
      options.path = path;
    }
    if (ComixImagePolicy.shouldRemoveOrigin(
      options.uri.toString(),
      _baseUrlHost,
    )) {
      options.headers.remove('Origin');
    }
    handler.next(options);
  }
}

/// 404 CDN fallbacks (`/i5/`, `/si/`, `/i/`, `/sii/`, `/ii/`) plus
/// server-error retry with `?r=<attempt>&8` (up to 10 attempts, 1.5s apart).
class ComixRetryInterceptor extends Interceptor {
  ComixRetryInterceptor(this._dio);

  final Dio _dio;

  static const _fallbacks = ['/i5/', '/si/', '/i/', '/sii/', '/ii/'];

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    if (status == null) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    try {
      if (status == 404) {
        for (final fallback in _fallbacks) {
          final candidate =
              options.uri.toString().replaceFirst(_fallbackPathRegex, fallback);
          if (candidate == options.uri.toString()) continue;
          final response = await _dio.fetch(
            options.copyWith(path: candidate),
          );
          if (response.statusCode != null && response.statusCode! < 400) {
            handler.resolve(response);
            return;
          }
        }
      } else if (status >= 500) {
        for (var attempt = 1; attempt <= 10; attempt++) {
          await Future<void>.delayed(
            const Duration(milliseconds: 1500),
          );
          final uri = options.uri.replace(
            queryParameters: {
              ...options.uri.queryParameters,
              'r': '$attempt',
              '8': '',
            },
          );
          final response = await _dio.fetch(
            options.copyWith(path: uri.toString()),
          );
          if (response.statusCode != null && response.statusCode! < 400) {
            handler.resolve(response);
            return;
          }
        }
      }
    } catch (_) {
      // Fall through to the original error.
    }
    handler.next(err);
  }
}
