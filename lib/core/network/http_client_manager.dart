import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:logger/logger.dart';
import '../di/service_locator.dart';

// Singleton HTTP client manager to ensure proper lifecycle management
// and prevent disposal issues across the application
class HttpClientManager {
  static HttpClientManager? _instance;
  static Dio? _httpClient;
  static Logger? _logger;

  /// Default error/logging interceptor shared by the global client and every
  /// per-source scoped client. Kept by reference so [clearInterceptors] (now
  /// deprecated) can preserve it instead of stripping the client bare.
  static Interceptor? _defaultInterceptor;

  /// Per-source scoped clients (see [scopedClientForSource]). Each entry
  /// owns its own [BaseOptions] copy and interceptor list, so per-source
  /// header/adapter changes never leak into other sources.
  static final Map<String, Dio> _scopedClients = {};

  HttpClientManager._internal();

  // Get the singleton instance
  static HttpClientManager get instance {
    _instance ??= HttpClientManager._internal();
    return _instance!;
  }

  // Initialize the HTTP client with proper configuration
  // Optional timeout parameter (defaults to 30 seconds if not specified)
  static Dio initializeHttpClient({
    Logger? logger,
    Duration? timeout,
    String? userAgent,
  }) {
    _logger = logger ??
        (() {
          try {
            return getIt<Logger>();
          } catch (_) {
            return Logger();
          }
        })();

    if (_httpClient != null) {
      _logger
          ?.d('HTTP client already initialized, returning existing instance');
      return _httpClient!;
    }

    _logger?.i('Initializing HTTP client singleton...');

    _httpClient = Dio()..httpClientAdapter = NativeAdapter();

    // Configure default options
    _httpClient!.options.headers = {
      'User-Agent': userAgent ??
          'Kuron/unknown (+https://github.com/shirokun20/nhasixapp)',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'DNT': '1',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      // 'Cookie': 'csrftoken=8FfRKO5iEnVwVfO3zzR2B7IDxHZUw674; session-affinity=1754401765.457.1635.890657|5438e073fbb56fb7666a0126dc9d5e81'
    };

    // Set default timeouts
    final defaultTimeout = timeout ?? const Duration(seconds: 30);
    _httpClient!.options.connectTimeout = defaultTimeout;
    _httpClient!.options.receiveTimeout = defaultTimeout;
    _httpClient!.options.sendTimeout = defaultTimeout;
    _httpClient!.options.followRedirects = true;
    _httpClient!.options.maxRedirects = 5;
    _httpClient!.options.responseType = ResponseType.plain;

    // Default error/logging interceptor, shared by reference with per-source
    // scoped clients (see [scopedClientForSource]).
    _defaultInterceptor ??= _buildDefaultInterceptor();
    _httpClient!.interceptors.add(_defaultInterceptor!);

    _logger?.i('HTTP client singleton initialized successfully');
    return _httpClient!;
  }

  /// Builds the default error-handling + debug-logging interceptor.
  ///
  /// Extracted so per-source scoped clients reuse the exact same behaviour
  /// without sharing interceptor-list identity with the global client.
  static InterceptorsWrapper _buildDefaultInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) {
        final uri = error.requestOptions.uri;
        final target = _redactedTarget(uri);
        final rawError = error.error?.toString() ?? '';

        // Some sites return malformed Set-Cookie headers (e.g. invalid date),
        // which can fail cookie persistence even when HTTP status is 2xx.
        if (rawError.contains('CookieManagerSaveException') &&
            error.response != null) {
          _logger?.w(
            'Ignoring malformed Set-Cookie and continuing with response ($target)',
          );
          handler.resolve(error.response!);
          return;
        }

        // Request cancellation is expected when widgets dispose or navigation happens
        if (error.type == DioExceptionType.cancel) {
          if (kDebugMode) {
            _logger?.d('HTTP Request Cancelled: ($target)');
          }
          handler.next(error);
          return;
        }

        final message = (error.message?.trim().isNotEmpty ?? false)
            ? error.message
            : error.error?.toString() ?? 'Unknown Dio error';
        _logger?.e('HTTP Error: $message ($target)');
        handler.next(error);
      },
      onRequest: (options, handler) {
        // Per-request log: debug-gated, stripped in release (hot path).
        if (kDebugMode) {
          _logger?.d(
            'HTTP Request: ${options.method} ${_redactedTarget(options.uri)}',
          );
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        // Per-response log: debug-gated, stripped in release (hot path).
        if (kDebugMode) {
          _logger?.d(
            'HTTP Response: ${response.statusCode} ${_redactedTarget(response.requestOptions.uri)}',
          );
        }
        handler.next(response);
      },
    );
  }

  /// Returns a per-source scoped [Dio] client for [sourceId].
  ///
  /// The scoped client clones the global client's [BaseOptions] (headers and
  /// timeouts included) and starts with a fresh interceptor list containing
  /// only the shared default error/logging interceptor plus
  /// [extraInterceptors]. Mutating the scoped client's options or
  /// interceptors (per-source `rateLimit` / `requiresBypass` behaviour) never
  /// affects the global client or any other source's client.
  ///
  /// The underlying HTTP adapter is shared with the global client (single
  /// Cronet engine). Call [disposeScopedClient] when a source is
  /// unregistered to close its client.
  static Dio scopedClientForSource(
    String sourceId, {
    Duration? timeout,
    Map<String, dynamic>? extraHeaders,
    List<Interceptor>? extraInterceptors,
  }) {
    final existing = _scopedClients[sourceId];
    if (existing != null) return existing;

    if (_httpClient == null) {
      throw StateError(
        'HTTP client not initialized. Call HttpClientManager.initializeHttpClient() first.',
      );
    }

    final base = _httpClient!.options;
    final options = base.copyWith(
      connectTimeout: timeout ?? base.connectTimeout,
      receiveTimeout: timeout ?? base.receiveTimeout,
      sendTimeout: timeout ?? base.sendTimeout,
      headers: <String, dynamic>{
        ...base.headers,
        ...?extraHeaders,
      },
    );
    final scoped = Dio(options)
      ..httpClientAdapter = _httpClient!.httpClientAdapter;
    _defaultInterceptor ??= _buildDefaultInterceptor();
    scoped.interceptors.add(_defaultInterceptor!);
    if (extraInterceptors != null && extraInterceptors.isNotEmpty) {
      scoped.interceptors.addAll(extraInterceptors);
    }
    _scopedClients[sourceId] = scoped;
    _logger?.d('Created scoped HTTP client for source "$sourceId"');
    return scoped;
  }

  /// Disposes and drops the scoped client for [sourceId], if any.
  static void disposeScopedClient(String sourceId) {
    final client = _scopedClients.remove(sourceId);
    client?.close(force: true);
    _logger?.d('Disposed scoped HTTP client for source "$sourceId"');
  }

  // Get the HTTP client instance
  // Throws an exception if not initialized
  static Dio get httpClient {
    if (_httpClient == null) {
      throw StateError(
        'HTTP client not initialized. Call HttpClientManager.initializeHttpClient() first.',
      );
    }
    return _httpClient!;
  }

  // Check if HTTP client is initialized
  static bool get isInitialized => _httpClient != null;

  // Update HTTP client configuration
  static void updateConfiguration({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? headers,
  }) {
    if (_httpClient == null) {
      _logger?.w('Cannot update configuration: HTTP client not initialized');
      return;
    }

    _logger?.d('Updating HTTP client configuration...');

    if (connectTimeout != null) {
      _httpClient!.options.connectTimeout = connectTimeout;
    }
    if (receiveTimeout != null) {
      _httpClient!.options.receiveTimeout = receiveTimeout;
    }
    if (sendTimeout != null) {
      _httpClient!.options.sendTimeout = sendTimeout;
    }
    if (headers != null) {
      _httpClient!.options.headers.addAll(headers);
    }

    _logger?.d('HTTP client configuration updated');
  }

  // Add an interceptor to the HTTP client
  static void addInterceptor(Interceptor interceptor) {
    if (_httpClient == null) {
      _logger?.w('Cannot add interceptor: HTTP client not initialized');
      return;
    }

    _httpClient!.interceptors.add(interceptor);
    _logger?.d('Interceptor added to HTTP client');
  }

  // Remove an interceptor from the HTTP client
  static void removeInterceptor(Interceptor interceptor) {
    if (_httpClient == null) {
      _logger?.w('Cannot remove interceptor: HTTP client not initialized');
      return;
    }

    _httpClient!.interceptors.remove(interceptor);
    _logger?.d('Interceptor removed from HTTP client');
  }

  /// Previously cleared the global interceptor list (which affected every
  /// source sharing the singleton).
  ///
  /// Deprecated: mutating the global interceptor list affected every source.
  /// Prefer per-source scoped clients ([scopedClientForSource]) and dispose
  /// them with [disposeScopedClient] instead. This method is now a no-op: it
  /// intentionally leaves all interceptors (including Dio built-ins and the
  /// default error/logging wrapper) untouched.
  @Deprecated(
    'Use scopedClientForSource/disposeScopedClient for per-source isolation. '
    'This method no longer mutates the interceptor list.',
  )
  static void clearInterceptors() {
    if (_httpClient == null) {
      _logger?.w('Cannot clear interceptors: HTTP client not initialized');
      return;
    }

    _logger?.w(
      'clearInterceptors() is deprecated and no longer clears anything; '
      'use scopedClientForSource/disposeScopedClient instead.',
    );
  }

  // Get HTTP client statistics
  static Map<String, dynamic> getStatistics() {
    if (_httpClient == null) {
      return {'initialized': false};
    }

    return {
      'initialized': true,
      'interceptors_count': _httpClient!.interceptors.length,
      'connect_timeout': _httpClient!.options.connectTimeout?.inMilliseconds,
      'receive_timeout': _httpClient!.options.receiveTimeout?.inMilliseconds,
      'send_timeout': _httpClient!.options.sendTimeout?.inMilliseconds,
      'base_url': _httpClient!.options.baseUrl,
      'headers_count': _httpClient!.options.headers.length,
      'scoped_clients': _scopedClients.keys.toList(growable: false),
    };
  }

  // Reset the HTTP client (for testing purposes only)
  // WARNING: This should only be used in tests
  static void resetForTesting() {
    _logger?.w(
        'Resetting HTTP client for testing - this should only be used in tests!');
    for (final client in _scopedClients.values) {
      client.close(force: true);
    }
    _scopedClients.clear();
    _defaultInterceptor = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    _instance = null;
  }

  static String _redactedTarget(Uri uri) {
    final path = uri.path;
    if (_isSensitivePath(path)) {
      return '[redacted-sensitive-endpoint]';
    }

    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.origin}$path$query';
  }

  static bool _isSensitivePath(String path) {
    final normalized = path.toLowerCase();
    return normalized.contains('/auth/') ||
        normalized.endsWith('/captcha') ||
        normalized.endsWith('/pow') ||
        normalized.endsWith('/user') ||
        normalized.contains('/refresh');
  }
}
