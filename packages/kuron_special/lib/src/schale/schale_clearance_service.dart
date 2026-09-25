import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';

class SchaleClearanceService {
  final FlutterSecureStorage _secureStorage;
  final Logger _logger;
  final String _sourceId;
  final String _domainUrl;
  final String _domainHost;

  String get _storageKey => '${_sourceId}_clearance_token';
  String get _userAgentKey => '${_sourceId}_user_agent';
  String get _cookiesKey => '${_sourceId}_cookies';
  String get _logTag => _sourceId;

  String? _cachedToken;
  String? _cachedUserAgent;
  String? _cachedCookies;

  SchaleClearanceService({
    required FlutterSecureStorage secureStorage,
    required Logger logger,
    required String sourceId,
    required String domainUrl,
  })  : _secureStorage = secureStorage,
        _logger = logger,
        _sourceId = sourceId,
        _domainUrl = domainUrl,
        _domainHost = Uri.parse(domainUrl).host;

  Future<void>? _initFuture;

  Future<void> init() {
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    try {
      final storedToken = await _secureStorage.read(key: _storageKey);
      final storedUa = await _secureStorage.read(key: _userAgentKey);
      final storedCookies = await _secureStorage.read(key: _cookiesKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        _cachedToken = storedToken;
        if (storedUa != null && storedUa.isNotEmpty) {
          _cachedUserAgent = storedUa;
        }
        if (storedCookies != null && storedCookies.isNotEmpty) {
          _cachedCookies = storedCookies;
        }
        _logger.i('$_logTag: loaded cached clearance token');
      }
    } catch (e) {
      _logger.e('$_logTag: failed to load cached clearance token', error: e);
    }
  }

  String? get cached => _cachedToken;
  String? get cachedUserAgent => _cachedUserAgent;

  Future<String?> acquire() async {
    await init();
    if (_cachedToken != null) return _cachedToken;

    _logger.i('$_logTag: acquiring clearance via Headless WebView');
    final result = await KuronNative.instance.getHeadlessClearance(
      url: _domainUrl,
    );

    if (result != null) {
      final userAgent = result['userAgent'] as String?;
      final crt = result['token'] as String?;
      final cookies = result['cookies'] as String?;

      if (crt != null && crt.isNotEmpty) {
        _logger.i('$_logTag: acquired clearance token crt (headless)');
        _logger
            .i('$_logTag: cookies extracted (${cookies?.length ?? 0} chars)');

        _cachedToken = crt;
        if (userAgent != null && userAgent.isNotEmpty) {
          _cachedUserAgent = userAgent;
        }
        if (cookies != null && cookies.isNotEmpty) _cachedCookies = cookies;

        await _secureStorage.write(key: _storageKey, value: crt);
        if (userAgent != null && userAgent.isNotEmpty) {
          await _secureStorage.write(key: _userAgentKey, value: userAgent);
        }
        if (cookies != null && cookies.isNotEmpty) {
          await _secureStorage.write(key: _cookiesKey, value: cookies);
        }

        return crt;
      }
    }

    _logger.w(
        '$_logTag: failed to acquire clearance via Headless WebView, falling back to visible WebView');
    final fallbackResult = await KuronNative.instance.showLoginWebView(
      url: _domainUrl,
      pageFinishedScript: "window.localStorage.getItem('clearance')",
    );

    if (fallbackResult != null) {
      final scriptResult =
          fallbackResult['pageFinishedScriptResult'] as String?;
      final userAgent = fallbackResult['userAgent'] as String?;

      String? cookies;
      final cookiesData = fallbackResult['cookies'];
      if (cookiesData is List) {
        cookies = cookiesData.join('; ');
      } else if (cookiesData is String) {
        cookies = cookiesData;
      }

      // the script result might be wrapped in quotes
      final crt = scriptResult?.replaceAll('"', '');
      if (crt != null && crt != 'null' && crt.isNotEmpty) {
        _logger.i('$_logTag: acquired clearance token crt (visible)');
        _logger
            .i('$_logTag: cookies extracted (${cookies?.length ?? 0} chars)');

        _cachedToken = crt;
        if (userAgent != null && userAgent.isNotEmpty) {
          _cachedUserAgent = userAgent;
        }
        if (cookies != null && cookies.isNotEmpty) _cachedCookies = cookies;

        await _secureStorage.write(key: _storageKey, value: crt);
        if (userAgent != null && userAgent.isNotEmpty) {
          await _secureStorage.write(key: _userAgentKey, value: userAgent);
        }
        if (cookies != null && cookies.isNotEmpty) {
          await _secureStorage.write(key: _cookiesKey, value: cookies);
        }
        return crt;
      }
    }

    _logger.w('$_logTag: completely failed to acquire clearance');
    return null;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _secureStorage.write(key: _storageKey, value: token);
  }

  Future<void> clearToken() async {
    await init();
    _cachedToken = null;
    _cachedUserAgent = null;
    _cachedCookies = null;
    await _secureStorage.delete(key: _storageKey);
    await _secureStorage.delete(key: _userAgentKey);
    await _secureStorage.delete(key: _cookiesKey);
  }

  Interceptor createInterceptor() => _SchaleInterceptor(service: this);
}

class _SchaleInterceptor extends Interceptor {
  final SchaleClearanceService _service;
  _SchaleInterceptor({required SchaleClearanceService service})
      : _service = service;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final url = options.uri.toString();
    final isSchaleEndpoint =
        (options.method == 'POST' && url.contains('/books/detail/')) ||
            url.contains('/books/data/');

    if (!isSchaleEndpoint &&
        !url.contains(_service._domainHost) &&
        !url.contains('erocdn.net')) {
      return handler.next(options);
    }
    //  erocdn.net hardcoded — both sources share the same CDN.
    // Extract to config-level CDN domain list when a 3rd source diverges.
    var crt = _service._cachedToken;
    if (crt == null) {
      await _service.init();
      crt = _service._cachedToken;
    }
    if (crt == null && (isSchaleEndpoint || url.contains('erocdn.net'))) {
      crt = await _service.acquire();
    }

    if (isSchaleEndpoint && crt != null) {
      options.queryParameters['crt'] = crt;
      options.headers['Authorization'] = 'Bearer $crt';
    }

    if (_service._cachedUserAgent != null) {
      options.headers['User-Agent'] = _service._cachedUserAgent!;
    }
    if (_service._cachedCookies != null) {
      options.headers['Cookie'] = _service._cachedCookies!;
    }
    options.headers['Referer'] = _service._domainUrl;

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 403 &&
        (err.requestOptions.uri.toString().contains('/books/detail/') ||
            err.requestOptions.uri.toString().contains('/books/data/'))) {
      _service._logger
          .w('${_service._logTag}: clearance token expired, clearing cache');
      await _service.clearToken();
    }
    handler.next(err);
  }
}
