import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:logger/logger.dart';
import '../di/service_locator.dart';
import 'dns_resolver.dart';
import 'dns_interceptor.dart';

// Singleton HTTP client manager to ensure proper lifecycle management
// and prevent disposal issues across the application
class HttpClientManager {
  static HttpClientManager? _instance;
  static Dio? _httpClient;
  static Logger? _logger;

  HttpClientManager._internal();

  // Get the singleton instance
  static HttpClientManager get instance {
    _instance ??= HttpClientManager._internal();
    return _instance!;
  }

  // Initialize the HTTP client with proper configuration
  // Optional dnsResolver enables DNS-over-HTTPS for all requests via interceptor
  // Optional timeout parameter (defaults to 30 seconds if not specified)
  static Dio initializeHttpClient({
    Logger? logger,
    DnsResolver? dnsResolver,
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

    // Add DNS-over-HTTPS interceptor if DnsResolver provided
    if (dnsResolver != null) {
      _logger?.i('Adding DNS-over-HTTPS interceptor');
      _httpClient!.interceptors.add(
        DnsInterceptor(
          dnsResolver: dnsResolver,
          logger: _logger!,
        ),
      );
    }

    // Add error handling interceptor
    _httpClient!.interceptors.add(
      InterceptorsWrapper(
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
      ),
    );

    _logger?.i('HTTP client singleton initialized successfully');
    return _httpClient!;
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

  // Clear all interceptors except the default ones
  static void clearInterceptors() {
    if (_httpClient == null) {
      _logger?.w('Cannot clear interceptors: HTTP client not initialized');
      return;
    }

    _httpClient!.interceptors.clear();
    _logger?.d('All interceptors cleared from HTTP client');
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
    };
  }

  // Reset the HTTP client (for testing purposes only)
  // WARNING: This should only be used in tests
  static void resetForTesting() {
    _logger?.w(
        'Resetting HTTP client for testing - this should only be used in tests!');
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
