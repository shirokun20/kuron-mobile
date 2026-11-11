import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:kuron_special/kuron_special.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';

// Mutates the registry-owned deep copy of a source's raw config before the
// session is built (e.g. legacy per-source overrides that stay inline in
// service_locator aliases). Must return the map to use; the stored raw
// config in [RemoteConfigService] is never touched.
typedef WebViewSessionConfigMutator = Map<String, dynamic> Function(
  Map<String, dynamic> rawCopy,
);

// Config-driven per-source WebView bypass sessions.
//
// Spec: `source-bypass-session` — any installed source whose raw config
// declares `network.requiresBypass == true` (or legacy
// `network.cloudflare.bypassEnabled`) gets an isolated bypass session
// on demand, without a per-source code registration.
//
// Sessions are cached per [cookieJarKey] (defaults to the source ID) and
// each session owns its cookie jar, so cookies never leak across sources.
// Sources without bypass flags get `null` — no session is created and no
// jar factory is invoked.
class WebViewSessionRegistry {
  WebViewSessionRegistry({
    required this._configService,
    required this._dio,
    required this._logger,
    required this._cookieJarFactory,
  });

  final RemoteConfigService _configService;
  final Dio _dio;
  final Logger _logger;
  final PersistCookieJar Function(String jarKey) _cookieJarFactory;

  final Map<String, WebViewSessionAdapter> _sessions = {};

  // Returns the cached session for [sourceId], provisioning it on first
  // use. Returns `null` when the source has no registered raw config or
  // declares no bypass — callers must handle the null (legacy aliases
  // throw a descriptive [StateError], generic callers skip bypass).
  WebViewSessionAdapter? get(
    String sourceId, {
    String? cookieJarKey,
    String? baseUrlFallback,
    WebViewSessionConfigMutator? mutateRawConfig,
    WebViewBypassOptionsBuilder? bypassOptionsBuilder,
  }) {
    final key = cookieJarKey ?? sourceId;
    final cached = _sessions[key];
    if (cached != null) {
      return cached;
    }

    final raw = _configService.getRawConfig(sourceId);
    if (raw == null || raw.isEmpty) {
      _logger.d('WebViewSessionRegistry: no raw config for $sourceId.');
      return null;
    }

    // Deep copy: adapters and mutators must never mutate the shared stored
    // config (same pattern as GenericHttpSource DI registration).
    var copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    if (mutateRawConfig != null) {
      copy = mutateRawConfig(copy);
    }

    final config = WebViewSessionConfig.fromJson(copy);
    if (!config.bypassEnabled) {
      _logger.d('WebViewSessionRegistry: $sourceId declares no bypass.');
      return null;
    }

    final baseUrl =
        copy['baseUrl']?.toString() ?? baseUrlFallback ?? 'https://$sourceId';
    final adapter = WebViewSessionAdapter(
      dio: _dio,
      cookieJar: _cookieJarFactory(key),
      config: config,
      baseUrl: baseUrl,
      logger: _logger,
      bypassOptionsBuilder: bypassOptionsBuilder,
    );
    _sessions[key] = adapter;
    _logger.d('WebViewSessionRegistry: provisioned bypass session for $key.');
    return adapter;
  }
}
