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
  ComixImageHeaderInterceptor({required this._baseUrlHost});

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
    options.headers.remove('Referer');
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
/// bounded server-error retry with `?r=<attempt>&8` (max 3 attempts, 1.5s
/// apart — a 10x storm held the radio awake ~15s per failed image and kept
/// the device warm on image-heavy screens).
class ComixRetryInterceptor extends Interceptor {
  ComixRetryInterceptor(this._dio);

  final Dio _dio;

  static const _fallbacks = ['/i5/', '/si/', '/i/', '/sii/', '/ii/'];

  /// Max server-error retries per failed request (was 10).
  static const int maxServerErrorAttempts = 3;

  static const _retryDelay = Duration(milliseconds: 1500);

  /// Attempt bookkeeping. Retry fetches go back through the interceptor
  /// chain, so each re-entrant [onError] must continue the SAME bounded
  /// chain instead of restarting it — otherwise retries multiply
  /// exponentially (3^depth with delays) and never terminate.
  static const _retryCountKey = 'comix_retry_count';

  /// Set once the 404 CDN fallback sweep has run for a request chain.
  static const _fallbackDoneKey = 'comix_fallback_done';

  /// True when the failed request (or its caller) was already cancelled.
  /// Retrying or even delaying after cancel wastes radio + CPU.
  static bool _isCancelled(RequestOptions options) =>
      options.cancelToken?.isCancelled == true;

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
    // A cancelled request must abort immediately — never delay or refetch.
    if (err.type == DioExceptionType.cancel) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    if (_isCancelled(options)) {
      handler.next(err);
      return;
    }
    final attempts = (options.extra[_retryCountKey] as int?) ?? 0;
    try {
      if (status == 404 && options.extra[_fallbackDoneKey] != true) {
        for (final fallback in _fallbacks) {
          if (_isCancelled(options)) break;
          final candidate =
              options.uri.toString().replaceFirst(_fallbackPathRegex, fallback);
          if (candidate == options.uri.toString()) continue;
          final response = await _dio.fetch(
            options.copyWith(
              path: candidate,
              extra: {
                ...options.extra,
                _fallbackDoneKey: true,
                _retryCountKey: attempts,
              },
            ),
          );
          if (response.statusCode != null && response.statusCode! < 400) {
            handler.resolve(response);
            return;
          }
        }
      } else if (status >= 500 && attempts < maxServerErrorAttempts) {
        await Future<void>.delayed(_retryDelay);
        if (_isCancelled(options)) {
          handler.next(err);
          return;
        }
        final uri = options.uri.replace(
          queryParameters: {
            ...options.uri.queryParameters,
            'r': '${attempts + 1}',
            '8': '',
          },
        );
        final response = await _dio.fetch(
          options.copyWith(
            path: uri.toString(),
            extra: {...options.extra, _retryCountKey: attempts + 1},
          ),
        );
        if (response.statusCode != null && response.statusCode! < 400) {
          handler.resolve(response);
          return;
        }
        // Non-2xx: the re-entrant onError for this fetch continues the
        // bounded chain (count already incremented above).
      }
    } catch (_) {
      // Fall through to the original error.
    }
    handler.next(err);
  }
}
