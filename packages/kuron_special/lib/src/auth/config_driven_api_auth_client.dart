import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import 'config_driven_api_auth_models.dart';

// Config-driven auth client for token-based providers (e.g. NHentai API v2).
///
// Reads endpoint and payload field names from source config, so no source
// identifiers are hardcoded in app main lib.
class ConfigDrivenApiAuthClient {
  final Dio _dio;
  final ApiAuthConfig _config;
  final Logger _logger;
  final FlutterSecureStorage _secureStorage;

  ConfigDrivenApiAuthClient({
    required this._dio,
    required this._config,
    required this._logger,
    FlutterSecureStorage? secureStorage,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _resolveUrl(String endpoint) {
    return Uri.parse(_config.apiBase).resolve(endpoint).toString();
  }

  String _resolveGalleryFavoriteUrl(int galleryId) {
    final endpointTemplate = _config.galleryFavoriteEndpoint;
    if (endpointTemplate == null || endpointTemplate.isEmpty) {
      throw StateError('gallery favorite endpoint is not configured');
    }

    final endpoint = endpointTemplate
        .replaceAll('{gallery_id}', galleryId.toString())
        .replaceAll('{id}', galleryId.toString());
    return _resolveUrl(endpoint);
  }

  String _resolveGalleryCommentsUrl(int galleryId) {
    final endpointTemplate = _config.galleryCommentsEndpoint;
    if (endpointTemplate == null || endpointTemplate.isEmpty) {
      throw StateError('gallery comments endpoint is not configured');
    }

    final endpoint = endpointTemplate
        .replaceAll('{gallery_id}', galleryId.toString())
        .replaceAll('{id}', galleryId.toString());
    return _resolveUrl(endpoint);
  }

  Map<String, dynamic> _toJsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;

    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    throw StateError('Expected JSON object response, got ${raw.runtimeType}');
  }

  List<Map<String, dynamic>> _toJsonMapList(dynamic raw) {
    final payload = raw is String ? jsonDecode(raw) : raw;

    if (payload is List) {
      return payload.map((item) => _toJsonMap(item)).toList();
    }

    if (payload is Map<String, dynamic>) {
      final result = payload['result'];
      if (result is List) {
        return result.map((item) => _toJsonMap(item)).toList();
      }
    }

    return const [];
  }

  Future<ApiPowChallenge> getPowChallenge({String? action}) async {
    final endpoint = _config.powEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('pow endpoint is not configured');
    }

    final normalizedAction = (action ?? _config.powAction)?.trim();

    final response = await _dio.get<dynamic>(
      _resolveUrl(endpoint),
      queryParameters: normalizedAction == null || normalizedAction.isEmpty
          ? null
          : <String, dynamic>{'action': normalizedAction},
    );
    final data = _toJsonMap(response.data);
    return ApiPowChallenge(
      challenge: data['challenge']?.toString() ?? '',
      difficulty: int.tryParse(data['difficulty']?.toString() ?? '') ?? 0,
    );
  }

  Future<ApiCaptchaConfig> getCaptchaConfig() async {
    final endpoint = _config.captchaEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('captcha endpoint is not configured');
    }

    final response = await _dio.get<dynamic>(_resolveUrl(endpoint));
    final data = _toJsonMap(response.data);
    return ApiCaptchaConfig(
      provider: data['provider']?.toString() ?? '',
      siteKey: data['site_key']?.toString() ?? '',
    );
  }

  // Solves PoW using the same formula as the frontend worker:
  // sha256(challenge + nonce).
  Future<String> solvePowNonceInIsolate({
    required String challenge,
    required int difficulty,
    String? action,
    int maxIterations = 3000000,
  }) async {
    final nonce = await Isolate.run<String>(
      () => _solvePowNonceJob(
        _PowNonceJob(
          challenge: challenge,
          difficulty: difficulty,
          maxIterations: maxIterations,
        ),
      ),
    );

    _logger.d('PoW solved in isolate with input pattern: challenge+nonce');
    return nonce;
  }

  String solvePowNonce({
    required String challenge,
    required int difficulty,
    String? action,
    int maxIterations = 3000000,
  }) {
    for (var nonce = 0; nonce < maxIterations; nonce++) {
      final nonceText = nonce.toString();
      final input = '$challenge$nonceText';
      final digest = sha256.convert(utf8.encode(input)).bytes;
      if (_hasLeadingZeroBits(digest, difficulty)) {
        _logger.d('PoW solved with input pattern: challenge+nonce');
        return nonceText;
      }
    }
    throw StateError('PoW nonce not found within $maxIterations iterations');
  }

  bool _hasLeadingZeroBits(List<int> bytes, int bits) {
    if (bits <= 0) return true;

    var remaining = bits;
    for (final byte in bytes) {
      if (remaining <= 0) return true;

      if (remaining >= 8) {
        if (byte != 0) return false;
        remaining -= 8;
        continue;
      }

      final mask = 0xFF << (8 - remaining) & 0xFF;
      return (byte & mask) == 0;
    }

    return remaining <= 0;
  }

  Future<ApiAuthSession> login({
    required String username,
    required String password,
    required String captchaResponse,
    required String powChallenge,
    required String powNonce,
    bool persist = true,
  }) async {
    final payload = <String, dynamic>{
      _config.usernameField: username,
      _config.passwordField: password,
      _config.captchaField: captchaResponse,
      _config.challengeField: powChallenge,
      _config.nonceField: powNonce,
      if (_config.powAction != null && _config.powAction!.isNotEmpty)
        _config.actionField: _config.powAction,
    };

    _logger.d('Login payload fields: ${payload.keys.toList()}');
    _logger.d('Login payload summary: ${_summarizePayload(payload)}');

    Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        _resolveUrl(_config.loginEndpoint),
        data: payload,
      );
    } on DioException catch (e) {
      final reason = _extractErrorReason(e.response?.data);
      if (reason != null && reason.isNotEmpty) {
        throw StateError('Login failed: $reason');
      }
      rethrow;
    }

    final data = _toJsonMap(response.data);
    final accessToken = data[_config.accessTokenField]?.toString() ?? '';
    if (accessToken.isEmpty) {
      throw StateError('Access token missing from login response');
    }

    String? usernameFromResponse;
    final userRaw = data['user'];
    if (userRaw is Map) {
      usernameFromResponse = userRaw['username']?.toString();
    }

    final session = ApiAuthSession(
      accessToken: accessToken,
      refreshToken: data[_config.refreshTokenField]?.toString(),
      expiresIn: int.tryParse(data[_config.expiresInField]?.toString() ?? ''),
      tokenType: data[_config.tokenTypeField]?.toString(),
      username:
          (usernameFromResponse != null && usernameFromResponse.isNotEmpty)
              ? usernameFromResponse
              : username,
    );

    if (persist) {
      await _saveSession(session);
    }

    _logger.i('Config-driven login successful');
    return session;
  }

  String? _extractErrorReason(dynamic raw) {
    if (raw == null) return null;

    try {
      final map = _toJsonMap(raw);
      final candidates = <String?>[
        map['detail']?.toString(),
        map['message']?.toString(),
        map['error']?.toString(),
      ];

      for (final item in candidates) {
        final text = (item ?? '').trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    } catch (_) {
      final text = raw.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }

  Map<String, dynamic> _summarizePayload(Map<String, dynamic> payload) {
    final summary = <String, dynamic>{};

    payload.forEach((key, value) {
      final keyText = key.toString();
      if (keyText == _config.passwordField) {
        summary[keyText] = '<hidden:${value.toString().length}>';
      } else if (keyText == _config.captchaField) {
        final text = value.toString();
        summary[keyText] = '<captcha:${text.length} chars>';
      } else if (keyText == _config.challengeField) {
        final text = value.toString();
        summary[keyText] = text.length > 8 ? '${text.substring(0, 8)}…' : text;
      } else if (keyText == _config.nonceField) {
        summary[keyText] = value.toString();
      } else {
        summary[keyText] = value;
      }
    });

    return summary;
  }

  Future<ApiAuthSession?> readSession() async {
    final jsonValue = await _secureStorage.read(key: _sessionKey);
    if (jsonValue == null || jsonValue.isEmpty) return null;

    final map = jsonDecode(jsonValue) as Map<String, dynamic>;
    final accessToken = map['accessToken']?.toString() ?? '';
    if (accessToken.isEmpty) return null;

    return ApiAuthSession(
      accessToken: accessToken,
      refreshToken: map['refreshToken']?.toString(),
      expiresIn: int.tryParse(map['expiresIn']?.toString() ?? ''),
      tokenType: map['tokenType']?.toString(),
      username: map['username']?.toString(),
    );
  }

  Future<void> attachSessionHeaderFromStorage() async {
    final session = await readSession();
    if (session == null) {
      _clearAuthorizationHeader();
      return;
    }
    _dio.options.headers['Authorization'] =
        _authorizationHeaderValue(session.accessToken);
  }

  Future<void> logout({bool clearStorage = true}) async {
    try {
      final endpoint = _config.logoutEndpoint;
      if (endpoint != null && endpoint.isNotEmpty) {
        final session = await readSession();
        final refreshToken = session?.refreshToken;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _dio.post<dynamic>(
            _resolveUrl(endpoint),
            data: <String, dynamic>{
              _config.refreshTokenField: refreshToken,
            },
          );
        } else {
          await _dio.post<dynamic>(_resolveUrl(endpoint));
        }
      }
    } finally {
      if (clearStorage) {
        await _secureStorage.delete(key: _sessionKey);
      }
      _clearAuthorizationHeader();
    }
  }

  Future<List<Map<String, dynamic>>> getFavorites({
    String? query,
    int page = 1,
  }) async {
    final endpoint = _config.favoritesEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('favorites endpoint is not configured');
    }

    final normalizedQuery = query?.trim();
    final queryParams = <String, dynamic>{
      'page': page < 1 ? 1 : page,
      if (normalizedQuery != null && normalizedQuery.isNotEmpty)
        'q': normalizedQuery,
    };

    try {
      final response = await _dio.get<dynamic>(
        _resolveUrl(endpoint),
        queryParameters: queryParams,
      );
      return _toJsonMapList(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  Future<ApiFavoriteStatus> checkFavorite(int galleryId) async {
    try {
      final response =
          await _dio.get<dynamic>(_resolveGalleryFavoriteUrl(galleryId));
      return _parseFavoriteStatus(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  Future<ApiFavoriteStatus> addFavorite(int galleryId) async {
    try {
      final response =
          await _dio.post<dynamic>(_resolveGalleryFavoriteUrl(galleryId));
      return _parseFavoriteStatus(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  Future<ApiFavoriteStatus> removeFavorite(int galleryId) async {
    try {
      final response =
          await _dio.delete<dynamic>(_resolveGalleryFavoriteUrl(galleryId));
      return _parseFavoriteStatus(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createComment({
    required int galleryId,
    required String body,
    String? captchaResponse,
    String? powAction,
  }) async {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      throw StateError('Comment body cannot be empty');
    }

    final pow = await getPowChallenge(action: powAction);
    final nonce = await solvePowNonceInIsolate(
      challenge: pow.challenge,
      difficulty: pow.difficulty,
      action: powAction,
    );

    final normalizedCaptcha = captchaResponse?.trim();
    final payload = <String, dynamic>{
      _config.commentBodyField: normalizedBody,
      _config.challengeField: pow.challenge,
      _config.nonceField: nonce,
      if (normalizedCaptcha != null && normalizedCaptcha.isNotEmpty)
        _config.captchaField: normalizedCaptcha,
    };

    try {
      final response = await _dio.post<dynamic>(
        _resolveGalleryCommentsUrl(galleryId),
        data: payload,
      );
      return _toJsonMap(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }

      final reason = _extractErrorReason(e.response?.data);
      if (reason != null && reason.isNotEmpty) {
        throw StateError('Comment failed: $reason');
      }

      rethrow;
    }
  }

  Future<List<String>> getBlacklistIds() async {
    final endpoint = _config.blacklistIdsEndpoint ?? _config.blacklistEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('blacklist ids endpoint is not configured');
    }

    try {
      final response = await _dio.get<dynamic>(_resolveUrl(endpoint));
      return _parseBlacklistIds(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getBlacklistRules() async {
    final endpoint = _config.blacklistEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('blacklist endpoint is not configured');
    }

    try {
      final response = await _dio.get<dynamic>(_resolveUrl(endpoint));
      return _parseBlacklistRules(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
      }
      rethrow;
    }
  }

  ApiFavoriteStatus _parseFavoriteStatus(dynamic raw) {
    final data = _toJsonMap(raw);
    final favorited = data['favorited'] == true;
    final numFavorites = int.tryParse(data['num_favorites']?.toString() ?? '');
    return ApiFavoriteStatus(
      favorited: favorited,
      numFavorites: numFavorites,
    );
  }

  List<String> _parseBlacklistIds(dynamic raw) {
    final values = _extractBlacklistValues(raw);

    return values
        .map((value) {
          if (value is Map) {
            final nestedTag = value['tag'];
            final nestedRule = value['rule'];
            return value['id'] ??
                value['tag_id'] ??
                value['tagId'] ??
                (nestedTag is Map ? nestedTag['id'] : null) ??
                (nestedRule is Map ? nestedRule['id'] : null) ??
                value['value'];
          }
          return value;
        })
        .where((value) => value != null)
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _parseBlacklistRules(dynamic raw) {
    final values = _extractBlacklistValues(raw);
    return values.map<Map<String, dynamic>>((value) {
      if (value is Map) {
        final map = value.map(
          (key, item) => MapEntry(key.toString(), item),
        );

        final nestedTag = map['tag'];
        if (nestedTag is Map) {
          final tagMap = nestedTag.map(
            (key, item) => MapEntry(key.toString(), item),
          );
          map.putIfAbsent('id', () => tagMap['id']);
          map.putIfAbsent('type', () => tagMap['type']);
          map.putIfAbsent('name', () => tagMap['name']);
          map.putIfAbsent('slug', () => tagMap['slug']);
        }

        final nestedRule = map['rule'];
        if (nestedRule is Map) {
          final ruleMap = nestedRule.map(
            (key, item) => MapEntry(key.toString(), item),
          );
          map.putIfAbsent('id', () => ruleMap['id']);
          map.putIfAbsent('type', () => ruleMap['type']);
          map.putIfAbsent('name', () => ruleMap['name']);
          map.putIfAbsent('slug', () => ruleMap['slug']);
        }

        return map;
      }

      return <String, dynamic>{'id': value};
    }).toList(growable: false);
  }

  List<dynamic> _extractBlacklistValues(dynamic raw) {
    final values = <dynamic>[];
    final payload = raw is String ? jsonDecode(raw) : raw;

    if (payload is List) {
      values.addAll(payload);
    } else if (payload is Map) {
      final data = Map<String, dynamic>.from(payload);
      List<dynamic>? resolveList(dynamic candidate) {
        if (candidate is List) {
          return candidate;
        }
        if (candidate is Map) {
          final nested = Map<String, dynamic>.from(candidate);
          for (final key in const [
            'result',
            'data',
            'items',
            'rules',
            'entries',
            'tags',
            'blacklist',
            'ids'
          ]) {
            final nestedCandidate = nested[key];
            if (nestedCandidate is List) {
              return nestedCandidate;
            }
          }

          for (final nestedCandidate in nested.values) {
            if (nestedCandidate is List) {
              return nestedCandidate;
            }
          }
        }

        return null;
      }

      for (final candidate in [
        data['ids'],
        data['blacklist'],
        data['rules'],
        data['entries'],
        data['items'],
        data['tags'],
        data['result'],
        data['data'],
      ]) {
        final resolved = resolveList(candidate);
        if (resolved != null) {
          values.addAll(resolved);
          break;
        }
      }

      if (values.isEmpty) {
        for (final candidate in data.values) {
          final resolved = resolveList(candidate);
          if (resolved != null) {
            values.addAll(resolved);
            break;
          }
        }
      }
    }

    return values;
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final endpoint = _config.userEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('user endpoint is not configured');
    }

    try {
      final response = await _dio.get<dynamic>(_resolveUrl(endpoint));
      return _toJsonMap(response.data);
    } on DioException catch (e) {
      if (_isUnauthorized(e)) {
        await _clearSessionLocally();
        throw StateError('Session expired, please login again');
      }
      rethrow;
    }
  }

  Future<void> _saveSession(ApiAuthSession session) async {
    final map = <String, dynamic>{
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'expiresIn': session.expiresIn,
      'tokenType': session.tokenType,
      'username': session.username,
    };
    await _secureStorage.write(key: _sessionKey, value: jsonEncode(map));
    _dio.options.headers['Authorization'] =
        _authorizationHeaderValue(session.accessToken);
  }

  bool _isUnauthorized(DioException error) {
    final code = error.response?.statusCode;
    return code == 401 || code == 403;
  }

  Future<void> _clearSessionLocally() async {
    await _secureStorage.delete(key: _sessionKey);
    _clearAuthorizationHeader();
  }

  void _clearAuthorizationHeader() {
    _dio.options.headers.remove('Authorization');
    _dio.options.headers.remove('authorization');
  }

  String _authorizationHeaderValue(String token) {
    final scheme = _config.authorizationScheme.trim();
    if (scheme.isEmpty) {
      return token;
    }

    return '$scheme $token';
  }

  String get _sessionKey {
    final keySeed = '${_config.apiBase}|${_config.loginEndpoint}';
    return 'kuron_special_api_auth_${keySeed.hashCode}';
  }
}

class _PowNonceJob {
  final String challenge;
  final int difficulty;
  final int maxIterations;

  const _PowNonceJob({
    required this.challenge,
    required this.difficulty,
    required this.maxIterations,
  });
}

String _solvePowNonceJob(_PowNonceJob job) {
  for (var nonce = 0; nonce < job.maxIterations; nonce++) {
    final nonceText = nonce.toString();
    final input = '${job.challenge}$nonceText';
    final digest = sha256.convert(utf8.encode(input)).bytes;
    if (_hasLeadingZeroBitsIsolate(digest, job.difficulty)) {
      return nonceText;
    }
  }

  throw StateError(
      'PoW nonce not found within ${job.maxIterations} iterations');
}

bool _hasLeadingZeroBitsIsolate(List<int> bytes, int bits) {
  if (bits <= 0) return true;

  var remaining = bits;
  for (final byte in bytes) {
    if (remaining <= 0) return true;

    if (remaining >= 8) {
      if (byte != 0) return false;
      remaining -= 8;
      continue;
    }

    final mask = 0xFF << (8 - remaining) & 0xFF;
    return (byte & mask) == 0;
  }

  return remaining <= 0;
}
