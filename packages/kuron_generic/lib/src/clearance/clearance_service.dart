import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

// Token-cache + persistence orchestration for challenge clearance.
//
// Pure Dart: platform solving goes through [ClearanceDriver] (native WebView
// in production, fakes in tests), persistence through [SecureValueStore].
// Endpoint matchers default to the schale-family shape
// (`/books/detail/`, `/books/data/`, shared `erocdn.net` CDN); pass explicit
// values when a third source diverges instead of hardcoding new hosts here.
class ClearanceService {
  final SecureValueStore _store;
  final ClearanceDriver _driver;
  final Logger _logger;
  final String _sourceId;
  final String _domainUrl;
  final String _domainHost;
  final List<String> _postOnlyPaths;
  final List<String> _anyMethodPaths;
  final List<String> _sharedCdnHosts;
  final String _tokenQueryParam;

  String get _storageKey => '${_sourceId}_clearance_token';
  String get _userAgentKey => '${_sourceId}_user_agent';
  String get _cookiesKey => '${_sourceId}_cookies';
  String get _logTag => _sourceId;

  String? _cachedToken;
  String? _cachedUserAgent;
  String? _cachedCookies;

  ClearanceService({
    required SecureValueStore store,
    required ClearanceDriver driver,
    required Logger logger,
    required String sourceId,
    required String domainUrl,
    List<String> postOnlyPaths = const ['/books/detail/'],
    List<String> anyMethodPaths = const ['/books/data/'],
    List<String> sharedCdnHosts = const ['erocdn.net'],
    String tokenQueryParam = 'crt',
  })  : _store = store,
        _driver = driver,
        _logger = logger,
        _sourceId = sourceId,
        _domainUrl = domainUrl,
        _domainHost = Uri.parse(domainUrl).host,
        _postOnlyPaths = postOnlyPaths,
        _anyMethodPaths = anyMethodPaths,
        _sharedCdnHosts = sharedCdnHosts,
        _tokenQueryParam = tokenQueryParam;

  Future<void>? _initFuture;

  Future<void> init() {
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    try {
      final storedToken = await _store.read(_storageKey);
      final storedUa = await _store.read(_userAgentKey);
      final storedCookies = await _store.read(_cookiesKey);
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

  bool _isEndpoint(String method, String url) =>
      (method == 'POST' && _postOnlyPaths.any(url.contains)) ||
      _anyMethodPaths.any(url.contains);

  bool _needsAcquire(String method, String url) =>
      _isEndpoint(method, url) || _sharedCdnHosts.any(url.contains);

  Future<String?> acquire() async {
    await init();
    if (_cachedToken != null) return _cachedToken;

    _logger.i('$_logTag: acquiring clearance via driver');
    final result = await _driver.solve(_domainUrl);

    if (result != null && result.token.isNotEmpty) {
      _logger.i('$_logTag: acquired clearance token');
      _logger.i(
          '$_logTag: cookies extracted (${result.cookies?.length ?? 0} chars)');

      _cachedToken = result.token;
      if (result.userAgent != null && result.userAgent!.isNotEmpty) {
        _cachedUserAgent = result.userAgent;
      }
      if (result.cookies != null && result.cookies!.isNotEmpty) {
        _cachedCookies = result.cookies;
      }

      await _store.write(_storageKey, result.token);
      if (result.userAgent != null && result.userAgent!.isNotEmpty) {
        await _store.write(_userAgentKey, result.userAgent!);
      }
      if (result.cookies != null && result.cookies!.isNotEmpty) {
        await _store.write(_cookiesKey, result.cookies!);
      }

      return result.token;
    }

    _logger.w('$_logTag: completely failed to acquire clearance');
    return null;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _store.write(_storageKey, token);
  }

  Future<void> clearToken() async {
    await init();
    _cachedToken = null;
    _cachedUserAgent = null;
    _cachedCookies = null;
    await _store.delete(_storageKey);
    await _store.delete(_userAgentKey);
    await _store.delete(_cookiesKey);
  }

  Interceptor createInterceptor() => _ClearanceInterceptor(service: this);
}

class _ClearanceInterceptor extends Interceptor {
  final ClearanceService _service;
  _ClearanceInterceptor({required ClearanceService service})
      : _service = service;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final url = options.uri.toString();
    final isEndpoint = _service._isEndpoint(options.method, url);

    if (!isEndpoint &&
        !url.contains(_service._domainHost) &&
        !_service._sharedCdnHosts.any(url.contains)) {
      return handler.next(options);
    }
    var crt = _service._cachedToken;
    if (crt == null) {
      await _service.init();
      crt = _service._cachedToken;
    }
    if (crt == null && _service._needsAcquire(options.method, url)) {
      crt = await _service.acquire();
    }

    if (isEndpoint && crt != null) {
      options.queryParameters[_service._tokenQueryParam] = crt;
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
        (_service._postOnlyPaths.any(
                err.requestOptions.uri.toString().contains) ||
            _service._anyMethodPaths.any(
                err.requestOptions.uri.toString().contains))) {
      _service._logger
          .w('${_service._logTag}: clearance token expired, clearing cache');
      await _service.clearToken();
    }
    handler.next(err);
  }
}
