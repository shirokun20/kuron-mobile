import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:kuron_core/kuron_core.dart' show ValidationReport;
import 'package:kuron_generic/kuron_generic.dart'
    show DynamicSearchFormContract, SourceConfigParser;
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Service responsible for loading, caching and refreshing source configs.
///
// ### Storage layers (highest priority first)
// 1. **AppDocDir/configs/** — Downloaded/cached configs (writable, override bundled)
// 2. **assets/configs/** — Bundled defaults (read-only, always present)
// 3. **Hardcoded defaults** — Last-resort constants
///
// ### Startup sync strategy
// On [smartInitialize] the service:
// 1. Loads bundled defaults (`nhentai`, `app`, `tags`).
// 2. Restores manually installed sources from local cache.
// 3. Trusts installed/cached source configs as the source of truth.
///
// Config is intentionally **not time-expiring** — invalidation is purely
// version-driven (bumping version in manifest triggers re-download).
class RemoteConfigService {
  final Dio _dio;
  final Logger _logger;

  // Legacy tags URLs (kept for backward compatibility)
  // static const String _tagsBaseUrl =
  //     'https://raw.githubusercontent.com/shirokun20/nhasixapp/refs/heads/configs/configs/tags';
  // static const String _nhentaiTagsUrl = '$_tagsBaseUrl/tags_nhentai.json';
  // static const String _crotpediaTagsUrl = '$_tagsBaseUrl/tags_crotpedia.json';

  // ── Asset paths ──────────────────────────────────────────────────────────────

  static const String _assetConfigBase = 'assets/configs';
  static const String _tagsAssetPath = '$_assetConfigBase/tags-config.json';

  // Bundled asset path for each **bundled** source.
  ///
  // Only `nhentai` is bundled into the APK as a permanent default — it is
  // always available without network. Other sources load via CDN/remote.
  static const Map<String, String> _bundledAssetPaths = {
    'nhentai': '$_assetConfigBase/nhentai-config.json',
    'app': '$_assetConfigBase/app-config.json',
    'tags': _tagsAssetPath
  };

  // Source IDs that are bundled into the APK and always available.
  static const Set<String> _bundledSourceIds = {'nhentai'};

  // ── SharedPreferences keys ───────────────────────────────────────────────────

  static const String _prefLastSyncMs = 'config_last_sync_timestamp';
  static const String _prefInstalledSourceIds = 'installed_source_ids';

  // Cached version for a specific source: "config_version_{sourceId}"
  static String _prefSourceVersion(String sourceId) =>
      'config_version_$sourceId';

  // Legacy tag cache keys
  // static const String _nhentaiTagsCacheKey = 'tags_cache_nhentai';
  // static const String _crotpediaTagsCacheKey = 'tags_cache_crotpedia';

  // ── In-memory state ──────────────────────────────────────────────────────────

  AppConfig? _appConfig;
  TagsManifest? _tagsManifest;
  SourceManifest? _manifest;
  final Map<String, SourceConfig> _sourceConfigs = {};
  final Map<String, Map<String, dynamic>> _rawSourceConfigs = {};
  // §8.1 — static compatibility reports computed on config load.
  final Map<String, ValidationReport> _validationReports = {};

  // ── Constructor ──────────────────────────────────────────────────────────────

  RemoteConfigService({required Dio dio, required Logger logger})
      : _dio = dio,
        _logger = logger;

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  // Initialise config using the Smart Sync strategy.
  ///
  // [isFirstRun] — when true, a critical failure rethrows the exception.
  // [onProgress] — optional 0.0–1.0 progress callback. `message` is an
  //   **l10n key**, never display text: the splash resolver looks it up and
  //   anything it cannot map would otherwise be painted on screen raw.
  Future<void> smartInitialize({
    bool isFirstRun = false,
    void Function(double progress, String message)? onProgress,
  }) async {
    _logger.i('RemoteConfigService: starting smartInitialize…');

    try {
      final configDir = await _getConfigDirectory();
      onProgress?.call(0.05, 'loadingBundledDefaults');

      // Preload guaranteed bundled defaults first so critical sources like
      // nhentai are always available.
      await _loadSourceFromBundledFallback('nhentai');
      await _loadSourceFromBundledFallback('app');

      // Manifest CDN mode is disabled. Keep in-memory manifest empty.
      _manifest = null;

      onProgress?.call(0.25, 'restoringLocalSources');
      await _restoreInstalledSourcesFromCache(configDir);

      // Safety net: bundled sources must always be available.
      for (final bundledId in _bundledSourceIds) {
        await _loadSourceFromBundledFallback(bundledId);
      }

      if (_appConfig == null && !_rawSourceConfigs.containsKey('app')) {
        await _loadSourceFromBundledFallback('app');
      }

      // Tags manifest is always loaded from asset (it's metadata, not config)
      onProgress?.call(0.55, 'loadingTagsConfig');
      await _loadTagsManifest();

      onProgress?.call(0.85, 'sourceConfigsReady');

      // Persist sync timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _prefLastSyncMs,
        DateTime.now().millisecondsSinceEpoch,
      );

      onProgress?.call(1.0, 'configReady');
      _logger.i(
        '✅ RemoteConfigService ready — ${_sourceConfigs.length} sources loaded',
      );
    } catch (e) {
      _logger.e('RemoteConfigService initialisation failed', error: e);
      if (isFirstRun) rethrow;
    }
  }

  // Getters ──────────────────────────────────────────────────────────────────

  SourceConfig? getConfig(String source) => _sourceConfigs[source];

  // Returns the cached static [ValidationReport] for [source], or `null`
  // when the source is not loaded or is a non-source config (app, tags).
  ValidationReport? getValidationReport(String source) =>
      _validationReports[source];

  // Returns search config for [source], preferring typed config and falling
  // back to raw JSON when typed parsing was skipped/failed.
  SearchConfig? getSearchConfig(String source) {
    final typed = _sourceConfigs[source]?.searchConfig;
    if (typed != null) return typed;

    final dynamic rawSearchConfig = _rawSourceConfigs[source]?['searchConfig'];
    if (rawSearchConfig is Map<String, dynamic>) {
      try {
        return SearchConfig.fromJson(rawSearchConfig);
      } catch (e, stackTrace) {
        _logger.w(
          'Failed to parse raw searchConfig for $source',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    return null;
  }

  // Returns search form config for [source], preferring typed config and
  // falling back to raw JSON when typed parsing was skipped/failed.
  SearchFormConfig? getSearchFormConfig(String source) {
    final typed = _sourceConfigs[source]?.searchForm;
    if (typed != null) return typed;

    final dynamic rawSearchForm = _rawSourceConfigs[source]?['searchForm'];
    if (rawSearchForm is Map<String, dynamic>) {
      try {
        return SearchFormConfig.fromJson(rawSearchForm);
      } catch (e, stackTrace) {
        _logger.w(
          'Failed to parse raw searchForm for $source',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    return null;
  }

  // Returns the canonical package-side search contract for [source].
  ///
  // This is the preferred app-facing search representation. Legacy
  // [SearchConfig] and [SearchFormConfig] remain compatibility inputs and are
  // normalized by `kuron_generic` before rendering.
  DynamicSearchFormContract? getCanonicalSearchForm(String source) {
    final raw = _rawSourceConfigs[source];
    if (raw == null) return null;

    try {
      final parsed = const SourceConfigParser().parse(
        raw.cast<String, Object?>(),
      );
      final contract = parsed.searchForm;
      if (contract == null || contract.fields.isEmpty) return null;
      return contract;
    } catch (e, stackTrace) {
      _logger.w(
        'Failed to build canonical search form for $source',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  List<SourceConfig> getAllSourceConfigs() =>
      _sourceConfigs.values.where((c) => c.enabled).toList();

  // All source configs including disabled ones (used by admin UI).
  List<SourceConfig> getAllSourceConfigsRaw() => _sourceConfigs.values.toList();

  AppConfig? get appConfig => _appConfig;
  TagsManifest? get tagsManifest => _tagsManifest;
  SourceManifest? get manifest => _manifest;

  Map<String, dynamic>? getRawConfig(String source) =>
      _rawSourceConfigs[source];

  // Manually register a source config (used for testing/generic sources)
  void registerSourceConfig(String sourceId, Map<String, dynamic> rawConfig) {
    try {
      _rawSourceConfigs[sourceId] = rawConfig;
      _sourceConfigs[sourceId] = SourceConfig.fromJson(rawConfig);
      _logger.d('Manually registered config for $sourceId');
    } catch (e) {
      _logger.e('Failed to register config for $sourceId', error: e);
      rethrow;
    }
  }

  RateLimitConfig getRateLimitConfig(String source) =>
      getConfig(source)?.network?.rateLimit ??
      RateLimitConfig(requestsPerMinute: 30, minDelayMs: 1500);

  bool isFeatureEnabled(String source, bool Function(FeatureConfig) selector) {
    final config = getConfig(source);
    if (config?.features == null) {
      final raw = _rawSourceConfigs[source];
      if (raw != null && raw['features'] != null) {
        try {
          final featureConfig = FeatureConfig.fromJson(
            raw['features'] as Map<String, dynamic>,
          );
          return selector(featureConfig);
        } catch (e) {
          _logger.e('Feature config parse failed', error: e);
        }
      }
      return false;
    }
    return selector(config!.features!);
  }

  // Returns `true` when [featureName] is enabled and **not** under maintenance.
  bool isFeatureAvailable(String source, String featureName) {
    final features = getConfig(source)?.features;
    if (features == null) return false;
    final maintenance = features.maintenanceFeatures?[featureName];
    if (maintenance?.active == true) return false;
    return switch (featureName) {
      'comments' => features.comments,
      'related' => features.related,
      'download' => features.download,
      'favorite' => features.favorite,
      'chapters' => features.chapters,
      'bookmark' => features.bookmark,
      'search' => features.search,
      'generatePdf' => features.generatePdf,
      'offlineMode' => features.offlineMode,
      _ => false,
    };
  }

  // Returns the [MaintenanceInfo] for [featureName] if it is currently under
  // maintenance, otherwise `null`.
  MaintenanceInfo? getFeatureMaintenance(String source, String featureName) {
    final info = getConfig(source)?.features?.maintenanceFeatures?[featureName];
    return (info?.active == true) ? info : null;
  }

  bool supportsTagExclusion(String source) =>
      isFeatureEnabled(source, (f) => f.supportsTagExclusion);

  bool supportsAdvancedSearch(String source) =>
      isFeatureEnabled(source, (f) => f.supportsAdvancedSearch);

  Future<bool> hasValidCache(String source) async =>
      _sourceConfigs.containsKey(source);

  // `configUrl` refresh is disabled.
  ///
  // Installed source configs are the single source of truth. The runtime no
  // longer reaches out to the source's embedded `configUrl`, because that can
  // overwrite the locally installed config with stale remote data.
  ///
  // Returns `false` to indicate no refresh happened.
  Future<bool> refreshSourceFromConfigUrl(
    String sourceId, {
    bool forceRefresh = false,
  }) async {
    _logger.d(
      '$sourceId: configUrl refresh disabled (forceRefresh=$forceRefresh) — '
      'using installed cache only',
    );
    return false;
  }

  // Downloads a source config from an explicit URL and applies it instantly.
  ///
  // This is intended for developer/admin flows (for example from Settings)
  // when testing a raw GitHub URL before the config is published to CDN.
  ///
  // The downloaded JSON is validated and then:
  // - saved into `AppDocDir/configs/{sourceId}-config.json`
  // - loaded into in-memory maps (`_rawSourceConfigs`, `_sourceConfigs`)
  // - version is persisted to SharedPreferences when available
  Future<SourceConfig> downloadAndApplySourceConfig({
    required String sourceId,
    required String url,
  }) async {
    _logger.i(
      'Downloading source config for $sourceId from explicit URL: $url',
    );

    final response = await _dio.get<String>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 12),
        responseType: ResponseType.plain,
      ),
    );

    final rawJson = response.data;
    if (rawJson == null || rawJson.trim().isEmpty) {
      throw const FormatException('Downloaded config is empty');
    }

    return applySourceConfigFromJson(
      sourceId: sourceId,
      rawJson: rawJson,
      sourceLabel: 'URL',
    );
  }

  // Applies a source config from raw JSON string, persists it to cache,
  // updates in-memory maps, and stores version metadata when available.
  Future<SourceConfig> applySourceConfigFromJson({
    required String sourceId,
    required String rawJson,
    String sourceLabel = 'raw',
  }) async {
    if (rawJson.trim().isEmpty) {
      throw const FormatException('Source config JSON is empty');
    }

    final decoded = _normalizeSourceConfigForCompatibility(
      jsonDecode(rawJson) as Map<String, dynamic>,
    );

    final declaredSource = decoded['source'] as String?;
    if (declaredSource == null || declaredSource.isEmpty) {
      throw const FormatException('Config is missing required "source" field');
    }
    if (declaredSource != sourceId) {
      throw FormatException(
        'Source mismatch: expected "$sourceId" but got "$declaredSource"',
      );
    }

    final parsed = SourceConfig.fromJson(decoded);

    final configDir = await _getConfigDirectory();
    final cachedFile = File(p.join(configDir.path, '$sourceId-config.json'));
    await cachedFile.writeAsString(jsonEncode(decoded));

    final version = decoded['version'] as String?;
    if (version != null && version.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSourceVersion(sourceId), version);
    }

    _rawSourceConfigs[sourceId] = decoded;
    _sourceConfigs[sourceId] = parsed;
    _cacheValidationReport(
      sourceId: sourceId,
      raw: decoded,
      sourceLabel: sourceLabel,
    );

    _logger.i(
      '✅ Applied source config from $sourceLabel for $sourceId (v${version ?? 'unknown'})',
    );
    return parsed;
  }

  // Persist install state for an installable source.
  Future<void> markSourceInstalled(String sourceId) async {
    if (_bundledSourceIds.contains(sourceId)) return;

    final prefs = await SharedPreferences.getInstance();
    final ids =
        (prefs.getStringList(_prefInstalledSourceIds) ?? <String>[]).toSet();
    ids.add(sourceId);
    await prefs.setStringList(_prefInstalledSourceIds, ids.toList());
  }

  // Remove persisted install state for an installable source.
  Future<void> markSourceUninstalled(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids =
        (prefs.getStringList(_prefInstalledSourceIds) ?? <String>[]).toSet();
    if (ids.remove(sourceId)) {
      await prefs.setStringList(_prefInstalledSourceIds, ids.toList());
    }
  }

  // Fully removes an installable source from local cache + in-memory maps.
  ///
  // Bundled sources (e.g. nhentai) are protected and cannot be uninstalled.
  Future<void> uninstallSourceConfig(String sourceId) async {
    if (_bundledSourceIds.contains(sourceId)) {
      _logger.w('Skip uninstall for bundled source: $sourceId');
      return;
    }

    final configDir = await _getConfigDirectory();
    final cachedFile = File(p.join(configDir.path, '$sourceId-config.json'));
    if (cachedFile.existsSync()) {
      await cachedFile.delete();
    }

    _rawSourceConfigs.remove(sourceId);
    _sourceConfigs.remove(sourceId);
    _validationReports.remove(sourceId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSourceVersion(sourceId));
    await markSourceUninstalled(sourceId);

    _logger.i('✅ Source uninstalled locally: $sourceId');
  }

  // Returns IDs for installable sources that user has installed.
  Future<Set<String>> getInstalledSourceIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_prefInstalledSourceIds) ?? <String>[];
    return ids.toSet();
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefLastSyncMs);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  // ─── Tags (legacy) ──────────────────────────────────────────────────────────

  Future<void> downloadTagsForSource(String source) async {
    // if (source != 'nhentai' && source != 'crotpedia') {
    _logger.w('Tags download not supported for source: $source');
    return;
    // }

    // const url = null;
    // final cacheKey =
    // source == 'nhentai' ? _nhentaiTagsCacheKey : _crotpediaTagsCacheKey;

    // if (url == null) {
    //   _logger.w('Tags download URL is null for source: $source');
    //   return;
    // }

    // try {
    //   _logger.i('Downloading tags for $source from: $url');
    //   final response = await _dio.get(url);

    //   if (response.statusCode == 200 && response.data != null) {
    //     final String jsonString = response.data is String
    //         ? response.data as String
    //         : jsonEncode(response.data);

    //     final prefs = await SharedPreferences.getInstance();
    //     await prefs.setString(cacheKey, jsonString);
    //     await prefs.setInt(
    //       '${cacheKey}_timestamp',
    //       DateTime.now().millisecondsSinceEpoch,
    //     );
    //     _logger.i('✅ Tags downloaded and cached for $source');
    //   }
    // } catch (e) {
    //   _logger.e('Error downloading tags for $source', error: e);
    // }
  }

  Future<List<Map<String, dynamic>>?> getCachedTags(String source) async {
    if (source != 'nhentai' && source != 'crotpedia') return null;
    // final cacheKey =
    //     source == 'nhentai' ? _nhentaiTagsCacheKey : _crotpediaTagsCacheKey;
    // try {
    //   final prefs = await SharedPreferences.getInstance();
    //   final raw = prefs.getString(cacheKey);
    //   if (raw != null) {
    //     final list = jsonDecode(raw) as List<dynamic>;
    //     return list.cast<Map<String, dynamic>>();
    //   }
    // } catch (e) {
    //   _logger.w('Failed to load cached tags for $source', error: e);
    // }
    return null;
  }

  Future<bool> hasTagsCache(String source) async {
    // if (source != 'nhentai' && source != 'crotpedia') return false;
    // final cacheKey =
    //     source == 'nhentai' ? _nhentaiTagsCacheKey : _crotpediaTagsCacheKey;
    // final prefs = await SharedPreferences.getInstance();
    // return prefs.containsKey(cacheKey);
    return false;
  }

  Future<int?> getTagsCacheAge(String source) async {
    // if (source != 'nhentai' && source != 'crotpedia') return null;
    // final cacheKey =
    //     source == 'nhentai' ? _nhentaiTagsCacheKey : _crotpediaTagsCacheKey;
    // try {
    //   final prefs = await SharedPreferences.getInstance();
    //   final ts = prefs.getInt('${cacheKey}_timestamp');
    //   if (ts != null) {
    //     return DateTime.now()
    //         .difference(DateTime.fromMillisecondsSinceEpoch(ts))
    //         .inDays;
    //   }
    // } catch (e) {
    //   _logger.w('Failed to get cache age for $source', error: e);
    // }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ═══════════════════════════════════════════════════════════════════════════

  // Returns (or creates) the writable config directory in AppDocDir.
  Future<Directory> _getConfigDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final configDir = Directory(p.join(docDir.path, 'configs'));
    if (!configDir.existsSync()) {
      await configDir.create(recursive: true);
    }
    return configDir;
  }

  // Restore manually installed source configs from local cache.
  Future<void> _restoreInstalledSourcesFromCache(Directory configDir) async {
    final prefs = await SharedPreferences.getInstance();
    final installedIds =
        (prefs.getStringList(_prefInstalledSourceIds) ?? const <String>[])
            .toSet();

    if (installedIds.isEmpty) return;

    _logger.i(
      'Restoring ${installedIds.length} local installed source(s): ${installedIds.join(', ')}',
    );

    for (final sourceId in installedIds) {
      final cachedFile = File(p.join(configDir.path, '$sourceId-config.json'));
      if (!cachedFile.existsSync()) {
        _logger.w('Cached config not found for installed source: $sourceId');
        continue;
      }

      try {
        await _loadFromFile(sourceId, cachedFile);
      } catch (e) {
        _logger.w('Failed to restore installed source: $sourceId', error: e);
      }
    }
  }

  // Load a source config JSON file from disk into memory.
  Future<void> _loadFromFile(String sourceId, File file) async {
    final rawString = await file.readAsString();
    final raw = jsonDecode(rawString) as Map<String, dynamic>;
    _rawSourceConfigs[sourceId] = raw;

    if (sourceId == 'app') {
      _appConfig = AppConfig.fromJson(raw);
      return;
    }

    if (sourceId == 'tags') {
      return;
    }

    try {
      _sourceConfigs[sourceId] = SourceConfig.fromJson(raw);
    } catch (e) {
      _logger.w(
        'Typed SourceConfig parse failed for cached source $sourceId; raw config kept '
        '(version=${raw['version']}, hasSearchConfig=${raw['searchConfig'] != null}, '
        'hasSearchForm=${raw['searchForm'] != null})',
        error: e,
      );
    }

    _cacheValidationReport(sourceId: sourceId, raw: raw, sourceLabel: 'cache');
  }

  // Load a config from bundled assets (last resort).
  Future<void> _loadSourceFromBundledFallback(String sourceId) async {
    final assetPath = _bundledAssetPaths[sourceId];
    if (assetPath == null) {
      _logger.w('No bundled asset for source: $sourceId');
      return;
    }
    try {
      final assetString = await rootBundle.loadString(assetPath);
      final raw = jsonDecode(assetString) as Map<String, dynamic>;
      _rawSourceConfigs[sourceId] = raw;
      if (sourceId == 'app') {
        _appConfig = AppConfig.fromJson(raw);
      } else if (sourceId != 'tags') {
        try {
          _sourceConfigs[sourceId] = SourceConfig.fromJson(raw);
        } catch (e) {
          _logger.w(
            'Typed SourceConfig parse failed for bundled source $sourceId; raw config kept '
            '(version=${raw['version']}, hasSearchConfig=${raw['searchConfig'] != null}, '
            'hasSearchForm=${raw['searchForm'] != null})',
            error: e,
          );
        }
      }
      _logger.d('Loaded bundled config for $sourceId');
      _cacheValidationReport(
        sourceId: sourceId,
        raw: raw,
        sourceLabel: 'bundled',
      );
    } catch (e) {
      _logger.w('Bundled asset load failed for $sourceId', error: e);
    }
  }

  void _cacheValidationReport({
    required String sourceId,
    required Map<String, dynamic> raw,
    required String sourceLabel,
  }) {
    if (sourceId == 'app' || sourceId == 'tags') {
      _validationReports.remove(sourceId);
      return;
    }

    try {
      final result = const SourceConfigParser().parse(
        raw.cast<String, Object?>(),
      );
      _validationReports[sourceId] = result.report;
      _logger.d(
        'SourceConfigParser ($sourceLabel): $sourceId → '
        '${result.report.overallStatus.name} '
        '(${result.report.diagnostics.length} diagnostics)',
      );
    } catch (e) {
      _validationReports.remove(sourceId);
      _logger.w(
        'ValidationReport generation failed for $sourceLabel source $sourceId',
        error: e,
      );
    }
  }

  Future<void> _loadTagsManifest() async {
    try {
      final assetString = await rootBundle.loadString(_tagsAssetPath);
      _tagsManifest = TagsManifest.fromJson(
        jsonDecode(assetString) as Map<String, dynamic>,
      );
    } catch (e) {
      _logger.w('Tags manifest load failed', error: e);
    }
  }

  // Normalize older source config schemas into the typed model expected by
  // current app parsers.
  ///
  // Current compatibility fix:
  // - `network.rateLimit.requestsPerSecond` -> `requestsPerMinute`
  // - fills missing `minDelayMs` with derived/default value
  Map<String, dynamic> _normalizeSourceConfigForCompatibility(
    Map<String, dynamic> raw,
  ) {
    final normalized = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;

    final network = normalized['network'];
    if (network is! Map) {
      return normalized;
    }

    final networkMap = network.cast<String, dynamic>();
    final rateLimit = networkMap['rateLimit'];
    if (rateLimit is! Map) {
      return normalized;
    }

    final rateMap = rateLimit.cast<String, dynamic>();

    final requestsPerSecondRaw = rateMap['requestsPerSecond'];
    int? requestsPerSecond;
    if (requestsPerSecondRaw is num) {
      requestsPerSecond = requestsPerSecondRaw.toInt();
    }

    if (rateMap['requestsPerMinute'] == null) {
      if (requestsPerSecond != null && requestsPerSecond > 0) {
        rateMap['requestsPerMinute'] = requestsPerSecond * 60;
      } else {
        rateMap['requestsPerMinute'] = 30;
      }
    }

    if (rateMap['minDelayMs'] == null) {
      if (requestsPerSecond != null && requestsPerSecond > 0) {
        rateMap['minDelayMs'] = (1000 / requestsPerSecond).ceil();
      } else {
        rateMap['minDelayMs'] = 1500;
      }
    }

    networkMap['rateLimit'] = rateMap;
    normalized['network'] = networkMap;
    return normalized;
  }
}
