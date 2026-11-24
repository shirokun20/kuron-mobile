// Factory that creates [GenericHttpSource] instances from raw JSON config.
///
// [GenericSourceFactory] is a special factory: unlike source-specific
// factories (e.g., `NhentaiSourceFactory`), it handles ANY source whose
// config is a plain JSON map — no custom Dart adapter needed.
///
// Registration: register a single [GenericSourceFactory] instance in DI.
// The [SourceLoader] will route any config without a dedicated factory to
// this generic factory.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import 'generic_http_source.dart';

/// Terminal adapter installed on a disposed scoped client so [Dio.close]
/// never reaches the shared underlying adapter.
class _DisposedScopedAdapter implements HttpClientAdapter {
  const _DisposedScopedAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Future<ResponseBody>.error(
      DioException.requestCancelled(
        requestOptions: options,
        reason: 'Scoped HTTP client disposed',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

// Creates [GenericHttpSource] instances for config-driven providers.
///
// Unlike [SourceFactory] implementations that handle a single `sourceId`,
// [GenericSourceFactory] acts as a catch-all factory. The [SourceLoader]
// should prefer this factory when no dedicated factory is found for a
// given source ID.
class GenericSourceFactory implements SourceFactory {
  final Dio _dio;
  final Logger _logger;
  final Dio Function(String sourceId)? scopedClientProvider;

  /// Per-source scoped [Dio] clones, keyed by source ID (used when no external
  /// [scopedClientProvider] is supplied).
  ///
  /// Each entry owns its own [BaseOptions] copy and interceptor list cloned
  /// from [_dio] at creation time, so per-source header/timeout/interceptor
  /// mutations (e.g. bypass or rate-limit behaviour) never leak into other
  /// sources sharing the global client. The HTTP adapter is shared.
  final Map<String, Dio> _scopedDio = {};

  static const HttpClientAdapter _disposedAdapter = _DisposedScopedAdapter();

  // The catch-all source ID sentinel. In practice [GenericSourceFactory]
  // overrides [create] for any source — not just this specific ID.
  ///
  // [SourceLoader] checks [canHandle] before falling through to this factory.
  @override
  String get sourceId => '__generic__';

  GenericSourceFactory({
    required this._dio,
    required this._logger,
    this.scopedClientProvider,
  });

  // Returns true for any source that does NOT require a custom Dart adapter
  // (i.e., any source whose config is a plain JSON map).
  ///
  // Dedicated factories (nhentai, crotpedia) will be checked first by
  // [SourceLoader]; this factory serves as the fallback.
  bool canHandle(Map<String, dynamic> config) {
    // We can handle any config that has either an `api` or `scraper` block.
    return config.containsKey('api') || config.containsKey('scraper');
  }

  @override
  ContentSource create(Map<String, dynamic> config) {
    final sourceId = config['source'] as String? ?? 'unknown';
    _logger.d('GenericSourceFactory: creating GenericHttpSource for $sourceId');
    final rateLimiter = _createRateLimiter(config);
    if (rateLimiter != null) {
      _logger.d('GenericSourceFactory: rate limiter enabled for $sourceId');
    }

    return GenericHttpSource(
      rawConfig: config,
      dio: _scopedDioFor(sourceId),
      logger: _logger,
      rateLimiter: rateLimiter,
    );
  }

  /// Returns the scoped [Dio] clone for [sourceId], delegating to
  /// [scopedClientProvider] when provided, or creating/caching a local clone
  /// of [_dio]'s options and interceptors.
  Dio _scopedDioFor(String sourceId) {
    final provider = scopedClientProvider;
    if (provider != null) return provider(sourceId);

    return _scopedDio.putIfAbsent(sourceId, () {
      final base = _dio.options;
      final clone = Dio(
        base.copyWith(headers: <String, dynamic>{...base.headers}),
      )..httpClientAdapter = _dio.httpClientAdapter;
      // Clear Dio's auto-added ImplyContentTypeInterceptor before copying
      // `_dio.interceptors` so built-in interceptors are never duplicated.
      clone.interceptors
        ..clear()
        ..addAll(_dio.interceptors);
      return clone;
    });
  }

  /// Disposes and drops any factory-owned scoped [Dio] for [sourceId].
  ///
  /// Swaps the adapter to a terminal stub before closing so the shared
  /// [_dio.httpClientAdapter] is never closed per-source.
  void disposeScopedClient(String sourceId) {
    final client = _scopedDio.remove(sourceId);
    if (client == null) return;
    client.httpClientAdapter = _disposedAdapter;
    client.interceptors.clear();
    client.close(force: true);
  }

  /// Disposes and drops all factory-owned scoped [Dio] clients without
  /// closing the shared [_dio.httpClientAdapter].
  void disposeAll() {
    for (final sourceId in _scopedDio.keys.toList(growable: false)) {
      disposeScopedClient(sourceId);
    }
  }

  RateLimiter? _createRateLimiter(Map<String, dynamic> config) {
    return RateLimiter.fromNetwork(
      (config['network'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
