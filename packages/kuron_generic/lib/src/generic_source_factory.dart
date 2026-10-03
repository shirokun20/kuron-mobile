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

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import 'generic_http_source.dart';

// Creates [GenericHttpSource] instances for config-driven providers.
///
// Unlike [SourceFactory] implementations that handle a single `sourceId`,
// [GenericSourceFactory] acts as a catch-all factory. The [SourceLoader]
// should prefer this factory when no dedicated factory is found for a
// given source ID.
class GenericSourceFactory implements SourceFactory {
  final Dio _dio;
  final Logger _logger;

  // The catch-all source ID sentinel. In practice [GenericSourceFactory]
  // overrides [create] for any source — not just this specific ID.
  ///
  // [SourceLoader] checks [canHandle] before falling through to this factory.
  @override
  String get sourceId => '__generic__';

  GenericSourceFactory({required Dio dio, required Logger logger})
      : _dio = dio,
        _logger = logger;

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
      dio: _dio,
      logger: _logger,
      rateLimiter: rateLimiter,
    );
  }

  RateLimiter? _createRateLimiter(Map<String, dynamic> config) {
    return RateLimiter.fromNetwork(
      (config['network'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
