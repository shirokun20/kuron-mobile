import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/domain/entities/entities.dart';

class SourceAuthBootstrap {
  final String sourceId;
  final String? powChallenge;
  final int? powDifficulty;
  final String? captchaProvider;
  final String? captchaSiteKey;
  final String? captchaBaseUrl;

  const SourceAuthBootstrap({
    required this.sourceId,
    this.powChallenge,
    this.powDifficulty,
    this.captchaProvider,
    this.captchaSiteKey,
    this.captchaBaseUrl,
  });
}

class SourceAuthService {
  final RemoteConfigService _configService;
  final Dio _dio;
  final Logger _logger;

  SourceAuthService({
    required this._configService,
    required this._dio,
    required this._logger,
  });

  bool supportsTokenApiAuth(String sourceId) {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final auth = raw['auth'] as Map<String, dynamic>?;
    if (auth == null) return false;

    return auth['enabled'] == true &&
        (auth['mode']?.toString().trim() ?? '') == 'tokenApi';
  }

  bool supportsOnlineFavoritesRead(String sourceId) {
    if (!supportsTokenApiAuth(sourceId)) return false;

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final features = raw['features'] as Map<String, dynamic>?;
    if (features?['favorite'] != true) return false;

    final endpoints = (raw['auth'] as Map<String, dynamic>?)?['endpoints']
        as Map<String, dynamic>?;
    final favoritesEndpoint = endpoints?['favorites']?.toString().trim() ?? '';
    return favoritesEndpoint.isNotEmpty;
  }

  bool supportsOnlineFavoritesWrite(String sourceId) {
    if (!supportsOnlineFavoritesRead(sourceId)) return false;

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final endpoints = (raw['auth'] as Map<String, dynamic>?)?['endpoints']
        as Map<String, dynamic>?;
    final galleryFavoriteEndpoint =
        endpoints?['galleryFavorite']?.toString().trim() ?? '';
    return galleryFavoriteEndpoint.isNotEmpty;
  }

  bool supportsCommentSubmission(String sourceId) {
    if (!supportsTokenApiAuth(sourceId)) return false;

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final features = raw['features'] as Map<String, dynamic>?;
    if (features?['comments'] != true) return false;

    final endpoints = (raw['auth'] as Map<String, dynamic>?)?['endpoints']
        as Map<String, dynamic>?;
    final galleryCommentsEndpoint =
        endpoints?['galleryComments']?.toString().trim() ?? '';
    final powEndpoint = endpoints?['pow']?.toString().trim() ?? '';
    final captchaEndpoint = endpoints?['captcha']?.toString().trim() ?? '';
    final commentPowAction =
        (raw['auth'] as Map<String, dynamic>?)?['commentPowAction']
                ?.toString()
                .trim() ??
            '';

    return galleryCommentsEndpoint.isNotEmpty &&
        powEndpoint.isNotEmpty &&
        captchaEndpoint.isNotEmpty &&
        commentPowAction.isNotEmpty;
  }

  bool supportsOnlineBlacklistRead(String sourceId) {
    if (!supportsTokenApiAuth(sourceId)) return false;

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final features = raw['features'] as Map<String, dynamic>?;
    if (features?['blacklist'] != true) return false;

    final endpoints = (raw['auth'] as Map<String, dynamic>?)?['endpoints']
        as Map<String, dynamic>?;
    final blacklistIdsEndpoint =
        endpoints?['blacklistIds']?.toString().trim() ?? '';
    return blacklistIdsEndpoint.isNotEmpty;
  }

  bool supportsOnlineBlacklistRulesRead(String sourceId) {
    if (!supportsTokenApiAuth(sourceId)) return false;

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return false;

    final features = raw['features'] as Map<String, dynamic>?;
    if (features?['blacklist'] != true) return false;

    final endpoints = (raw['auth'] as Map<String, dynamic>?)?['endpoints']
        as Map<String, dynamic>?;
    final blacklistEndpoint = endpoints?['blacklist']?.toString().trim() ?? '';
    return blacklistEndpoint.isNotEmpty;
  }

  List<String> getSourcesSupportingOnlineFavorites({
    bool requireWrite = false,
  }) {
    return _configService
        .getAllSourceConfigs()
        .map((config) => config.source)
        .where(
          (sourceId) => requireWrite
              ? supportsOnlineFavoritesWrite(sourceId)
              : supportsOnlineFavoritesRead(sourceId),
        )
        .toList(growable: false);
  }

  List<String> getSourcesSupportingOnlineBlacklist() {
    return _configService
        .getAllSourceConfigs()
        .map((config) => config.source)
        .where(supportsOnlineBlacklistRead)
        .toList(growable: false);
  }

  Future<SourceAuthBootstrap> bootstrap(String sourceId) async {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) {
      throw StateError('Missing config for source: $sourceId');
    }

    final config = ApiAuthConfig.fromSourceConfig(raw);
    final client = ConfigDrivenApiAuthClient(
      dio: _dio,
      config: config,
      logger: _logger,
    );

    String? powChallenge;
    int? powDifficulty;
    String? captchaProvider;
    String? captchaSiteKey;
    final captchaBaseUrl = _resolveCaptchaBaseUrl(
      rawConfig: raw,
      apiBase: config.apiBase,
    );

    try {
      final pow = await client.getPowChallenge();
      powChallenge = pow.challenge;
      powDifficulty = pow.difficulty;
    } catch (e) {
      _logger.w('PoW bootstrap unavailable for $sourceId: $e');
    }

    try {
      final captcha = await client.getCaptchaConfig();
      captchaProvider = captcha.provider;
      captchaSiteKey = captcha.siteKey;
    } catch (e) {
      _logger.w('Captcha bootstrap unavailable for $sourceId: $e');
    }

    return SourceAuthBootstrap(
      sourceId: sourceId,
      powChallenge: powChallenge,
      powDifficulty: powDifficulty,
      captchaProvider: captchaProvider,
      captchaSiteKey: captchaSiteKey,
      captchaBaseUrl: captchaBaseUrl,
    );
  }

  Future<SourceAuthBootstrap> getCaptchaBootstrap(String sourceId) async {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) {
      throw StateError('Missing config for source: $sourceId');
    }

    final config = ApiAuthConfig.fromSourceConfig(raw);
    final client = ConfigDrivenApiAuthClient(
      dio: _dio,
      config: config,
      logger: _logger,
    );

    final captcha = await client.getCaptchaConfig();

    return SourceAuthBootstrap(
      sourceId: sourceId,
      captchaProvider: captcha.provider,
      captchaSiteKey: captcha.siteKey,
      captchaBaseUrl: _resolveCaptchaBaseUrl(
        rawConfig: raw,
        apiBase: config.apiBase,
      ),
    );
  }

  Future<void> login({
    required String sourceId,
    required String username,
    required String password,
    required String captchaResponse,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedCaptchaResponse = captchaResponse.replaceAll(
      RegExp(r'\s+'),
      '',
    );

    final client = _buildClient(sourceId);
    final powAction = _getPowAction(sourceId);
    final pow = await client.getPowChallenge(action: powAction);
    final nonce = await client.solvePowNonceInIsolate(
      challenge: pow.challenge,
      difficulty: pow.difficulty,
      action: powAction,
    );

    await client.login(
      username: normalizedUsername,
      password: password,
      captchaResponse: normalizedCaptchaResponse,
      powChallenge: pow.challenge,
      powNonce: nonce,
      persist: true,
    );
  }

  Future<bool> hasSession(String sourceId) async {
    final client = _buildClient(sourceId);
    final session = await client.readSession();
    return session != null && session.accessToken.isNotEmpty;
  }

  Future<String?> getSessionDisplayName(String sourceId) async {
    final client = _buildClient(sourceId);
    final session = await client.readSession();
    final username = session?.username?.trim();
    if (username == null || username.isEmpty) {
      return null;
    }

    return username;
  }

  Future<void> logout(String sourceId) async {
    final client = _buildClient(sourceId);
    await client.logout(clearStorage: true);
  }

  Future<List<Map<String, dynamic>>> getFavorites(
    String sourceId, {
    String? query,
    int page = 1,
  }) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.getFavorites(
      query: query,
      page: page,
    );
  }

  Future<ApiFavoriteStatus> checkFavorite({
    required String sourceId,
    required int galleryId,
  }) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.checkFavorite(galleryId);
  }

  Future<ApiFavoriteStatus> addFavorite({
    required String sourceId,
    required int galleryId,
  }) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.addFavorite(galleryId);
  }

  Future<ApiFavoriteStatus> removeFavorite({
    required String sourceId,
    required int galleryId,
  }) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.removeFavorite(galleryId);
  }

  Future<Comment> createComment({
    required String sourceId,
    required int galleryId,
    required String body,
    required String captchaResponse,
  }) async {
    final commentPowAction = _getCommentPowAction(sourceId);
    if (commentPowAction == null || commentPowAction.isEmpty) {
      throw StateError('Comment PoW action is not configured');
    }

    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();

    final raw = await client.createComment(
      galleryId: galleryId,
      body: body,
      captchaResponse: captchaResponse,
      powAction: commentPowAction,
    );

    return _mapComment(
      sourceId: sourceId,
      rawComment: raw,
    );
  }

  Future<Map<String, dynamic>> getUserProfile(String sourceId) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.getUserProfile();
  }

  Future<List<String>> getBlacklistIds(String sourceId) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.getBlacklistIds();
  }

  Future<List<Map<String, dynamic>>> getBlacklistRules(String sourceId) async {
    final client = _buildClient(sourceId);
    await client.attachSessionHeaderFromStorage();
    return client.getBlacklistRules();
  }

  ConfigDrivenApiAuthClient _buildClient(String sourceId) {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) {
      throw StateError('Missing config for source: $sourceId');
    }

    final config = ApiAuthConfig.fromSourceConfig(raw);
    return ConfigDrivenApiAuthClient(
      dio: _dio,
      config: config,
      logger: _logger,
    );
  }

  String? _getPowAction(String sourceId) {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return null;

    final auth = raw['auth'] as Map<String, dynamic>?;
    return auth?['powAction']?.toString().trim();
  }

  String? _getCommentPowAction(String sourceId) {
    final raw = _configService.getRawConfig(sourceId);
    if (raw == null) return null;

    final auth = raw['auth'] as Map<String, dynamic>?;
    return auth?['commentPowAction']?.toString().trim();
  }

  String? _resolveCaptchaBaseUrl({
    required Map<String, dynamic> rawConfig,
    required String apiBase,
  }) {
    final auth = rawConfig['auth'] as Map<String, dynamic>?;
    final configuredBaseUrl = auth?['captchaBaseUrl']?.toString().trim();
    final rawValue = (configuredBaseUrl != null && configuredBaseUrl.isNotEmpty)
        ? configuredBaseUrl
        : apiBase.trim();

    if (rawValue.isEmpty) return null;

    final uri = Uri.tryParse(rawValue);
    if (uri == null || (!uri.hasScheme || !uri.hasAuthority)) {
      _logger.w('Invalid captcha base URL in config: $rawValue');
      return null;
    }

    return uri.origin;
  }

  Comment _mapComment({
    required String sourceId,
    required Map<String, dynamic> rawComment,
  }) {
    final rawPoster = rawComment['poster'];
    final poster = rawPoster is Map
        ? rawPoster.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};
    final sourceConfig = _configService.getRawConfig(sourceId);
    final avatarBaseUrl = sourceConfig?['avatarBaseUrl']?.toString();
    final username = poster['username']?.toString().trim();

    return Comment(
      id: rawComment['id']?.toString() ?? '',
      username: (username == null || username.isEmpty) ? 'Anonymous' : username,
      body: rawComment['body']?.toString() ?? '',
      avatarUrl: _resolveAvatarUrl(
        poster['avatar_url']?.toString(),
        avatarBaseUrl,
      ),
      postDate: _parseUnixSeconds(rawComment['post_date']),
    );
  }

  String? _resolveAvatarUrl(String? rawAvatarUrl, String? avatarBaseUrl) {
    final value = rawAvatarUrl?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('https://') || value.startsWith('http://')) {
      return value;
    }
    if (value.startsWith('//')) return 'https:$value';

    final base = (avatarBaseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    if (value.startsWith('/')) {
      return base.isNotEmpty ? '$base$value' : 'https:/$value';
    }

    return base.isNotEmpty ? '$base/$value' : value;
  }
  Future<void> saveWebViewSession({
    required String sourceId,
    required List<String> cookies,
    required String? cookieName,
  }) async {
    if (cookieName == null) return;
    String? accessToken;
    for (final c in cookies) {
      try {
        final parsed = Cookie.fromSetCookieValue(c);
        if (parsed.name == cookieName) {
          accessToken = parsed.value;
          break;
        }
      } catch (e) {
        _logger.w('Access token parse failed', error: e);
      }
    }
    if (accessToken == null || accessToken.isEmpty) return;
    final cfg = _configService.getRawConfig(sourceId);
    if (cfg == null) return;
    final api = cfg['api'] is Map<String, dynamic>
        ? cfg['api'] as Map<String, dynamic>
        : null;
    final apiBase = api?['apiBase']?.toString() ?? '';
    final auth = cfg['auth'] is Map<String, dynamic>
        ? cfg['auth'] as Map<String, dynamic>
        : null;
    final ep = auth?['endpoints'] is Map<String, dynamic>
        ? auth!['endpoints'] as Map<String, dynamic>
        : null;
    final loginEndpoint = ep?['login']?.toString() ?? '';
    if (apiBase.isEmpty || loginEndpoint.isEmpty) return;
    // NOTE: key intentionally shared across sources with the same
    // apiBase|loginEndpoint (same backend account), NOT per sourceId.
    final keySeed = '$apiBase|$loginEndpoint';
    final sessionKey = 'kuron_special_api_auth_${keySeed.hashCode}';
    const storage = FlutterSecureStorage();
    await storage.write(
        key: sessionKey, value: jsonEncode({'accessToken': accessToken}));
  }

  ({String url, String? autoCloseCookie, List<String>? successFilters})?
      getLoginUrls(String sourceId) {
    final config = _configService.getRawConfig(sourceId);
    if (config == null) return null;
    final auth = config['auth'] is Map<String, dynamic>
        ? config['auth'] as Map<String, dynamic>
        : null;
    final webview = auth?['webviewLogin'] is Map<String, dynamic>
        ? auth!['webviewLogin'] as Map<String, dynamic>
        : null;
    if (webview == null) return null;
    final url = webview['url']?.toString().trim();
    final cookieName = webview['autoCloseCookie']?.toString().trim();
    final rawFilters = webview['successFilters'];
    final filters = rawFilters is List ? rawFilters.cast<String>() : null;
    if (url == null || url.isEmpty) return null;
    return (url: url, autoCloseCookie: cookieName, successFilters: filters);
  }

  DateTime? _parseUnixSeconds(dynamic rawValue) {
    final seconds = int.tryParse(rawValue?.toString() ?? '');
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}
