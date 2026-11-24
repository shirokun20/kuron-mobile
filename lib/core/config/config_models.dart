import 'package:freezed_annotation/freezed_annotation.dart';

part 'config_models.freezed.dart';
part 'config_models.g.dart';

/// Parses a manifest `schemaVersion` flexibly across the v2/v3 family.
///
/// Accepts `int` (2, 3), `num`, version strings (`"2"`, `"2.0"`, `"3.0"`,
/// `"3"`), and legacy absence/null (defaults to 1 — the pre-family
/// convention also used by `SourcePackageManifest`). Never throws, so
/// forward-compatible manifests (v3+) and unversioned legacy manifests both
/// parse without crashing.
int parseManifestSchemaVersion(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final text = raw.trim();
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final dotted = RegExp(r'^(\d+)(?:\.\d+)*$').firstMatch(text);
    if (dotted != null) return int.parse(dotted.group(1)!);
  }
  return 1;
}

int _manifestSchemaVersionToJson(int value) => value;

@JsonSerializable(explicitToJson: true)
class RemoteConfig {
  final SourceConfig? nhentai;
  final SourceConfig? crotpedia;
  final SourceConfig? ehentai;

  RemoteConfig({this.nhentai, this.crotpedia, this.ehentai});

  factory RemoteConfig.fromJson(Map<String, dynamic> json) =>
      _$RemoteConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RemoteConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class SourceConfig {
  final String source;
  final String version;
  final String? lastUpdated;
  final String? baseUrl;

  // Whether this source is enabled. Controlled by the remote manifest.
  // Defaults to true so bundled configs (which lack this field) remain active.
  @JsonKey(defaultValue: true)
  final bool enabled;

  // Whether this source is under maintenance (temporary unavailability).
  @JsonKey(defaultValue: false)
  final bool maintenance;

  // Human-readable maintenance message shown to users when [maintenance] is true.
  final String? maintenanceMessage;

  final ApiConfig? api;
  final ScraperConfig? scraper;
  final NetworkConfig? network;
  final FeatureConfig? features;
  final UiConfig? ui;
  final AuthConfig? auth;
  final Map<String, String>? typeMapping; // Map type code to display name
  final SearchConfig? searchConfig;

  // Dynamic search form definition (used by scraper-based sources like
  // KomikTap). Parsed from the top-level `searchForm` block in the source
  // config JSON.
  final SearchFormConfig? searchForm;

  SourceConfig({
    required this.source,
    required this.version,
    this.lastUpdated,
    this.baseUrl,
    this.enabled = true,
    this.maintenance = false,
    this.maintenanceMessage,
    this.api,
    this.scraper,
    this.network,
    this.features,
    this.ui,
    this.auth,
    this.typeMapping,
    this.searchConfig,
    this.searchForm,
  });

  factory SourceConfig.fromJson(Map<String, dynamic> json) =>
      _$SourceConfigFromJson(json);
  Map<String, dynamic> toJson() => _$SourceConfigToJson(this);
}

// ... existing classes ...

enum SearchMode {
  @JsonValue('query-string')
  queryString,

  @JsonValue('form-based')
  formBased,
}

enum SortWidgetType {
  @JsonValue('dropdown')
  dropdown,

  @JsonValue('chips')
  chips,

  @JsonValue('readonly')
  readonly,
}

@freezed
sealed class SearchConfig with _$SearchConfig {
  const factory SearchConfig({
    @Default(SearchMode.queryString) SearchMode searchMode,
    @Default('') String endpoint,
    SortingConfig? sortingConfig,
    String? queryParam,
    FilterSupportConfig? filterSupport,
    List<TextFieldConfig>? textFields,
    List<RadioGroupConfig>? radioGroups,
    List<CheckboxGroupConfig>? checkboxGroups,
    PaginationConfig? pagination,
  }) = _SearchConfig;

  factory SearchConfig.fromJson(Map<String, dynamic> json) =>
      _$SearchConfigFromJson(json);
}

@freezed
sealed class FilterSupportConfig with _$FilterSupportConfig {
  const factory FilterSupportConfig({
    required List<String> singleSelect,
    required List<String> multiSelect,
    required bool supportsExclude,
  }) = _FilterSupportConfig;

  factory FilterSupportConfig.fromJson(Map<String, dynamic> json) =>
      _$FilterSupportConfigFromJson(json);
}

@freezed
sealed class TextFieldConfig with _$TextFieldConfig {
  const factory TextFieldConfig({
    required String name,
    required String label,
    required String type,
    String? placeholder,
    int? maxLength,
    int? min,
    int? max,
  }) = _TextFieldConfig;

  factory TextFieldConfig.fromJson(Map<String, dynamic> json) =>
      _$TextFieldConfigFromJson(json);
}

@freezed
sealed class RadioGroupConfig with _$RadioGroupConfig {
  const factory RadioGroupConfig({
    required String name,
    required String label,
    required List<RadioOptionConfig> options,
  }) = _RadioGroupConfig;

  factory RadioGroupConfig.fromJson(Map<String, dynamic> json) =>
      _$RadioGroupConfigFromJson(json);
}

@freezed
sealed class RadioOptionConfig with _$RadioOptionConfig {
  const factory RadioOptionConfig({
    required String value,
    required String label,
    @Default(false) bool isDefault,
  }) = _RadioOptionConfig;

  factory RadioOptionConfig.fromJson(Map<String, dynamic> json) =>
      _$RadioOptionConfigFromJson(json);
}

@freezed
sealed class CheckboxGroupConfig with _$CheckboxGroupConfig {
  const factory CheckboxGroupConfig({
    required String name,
    required String label,
    required String paramName,
    @Default('expandable') String displayMode,
    @Default(3) int columns,
    @Default(false) bool loadFromTags,
    String? tagType,
    String? tagSourceUrl,
  }) = _CheckboxGroupConfig;

  factory CheckboxGroupConfig.fromJson(Map<String, dynamic> json) =>
      _$CheckboxGroupConfigFromJson(json);
}

@freezed
sealed class SortingConfig with _$SortingConfig {
  const factory SortingConfig({
    required bool allowDynamicReSort,
    required String defaultSort,
    required SortWidgetType widgetType,
    required List<SortOptionConfig> options,
    required SortingMessages messages,
  }) = _SortingConfig;

  factory SortingConfig.fromJson(Map<String, dynamic> json) =>
      _$SortingConfigFromJson(json);
}

@freezed
sealed class SortOptionConfig with _$SortOptionConfig {
  const factory SortOptionConfig({
    required String value,
    required String apiValue,
    required String label,
    required String displayLabel,
    String? icon,
    @Default(false) bool isDefault,
  }) = _SortOptionConfig;

  factory SortOptionConfig.fromJson(Map<String, dynamic> json) =>
      _$SortOptionConfigFromJson(json);
}

@freezed
sealed class SortingMessages with _$SortingMessages {
  const factory SortingMessages({
    String? dropdownLabel,
    String? noOptionsAvailable,
    String? readOnlyPrefix,
    String? readOnlySuffix,
    String? tapToModifyHint,
    String? returnToSearchButton,
  }) = _SortingMessages;

  factory SortingMessages.fromJson(Map<String, dynamic> json) =>
      _$SortingMessagesFromJson(json);
}

@freezed
sealed class PaginationConfig with _$PaginationConfig {
  const factory PaginationConfig({
    required String urlPattern,
    @Default('page') String paramName,
  }) = _PaginationConfig;

  factory PaginationConfig.fromJson(Map<String, dynamic> json) =>
      _$PaginationConfigFromJson(json);
}

@JsonSerializable(explicitToJson: true)
class ApiConfig {
  final bool enabled;
  final String? baseUrl;
  final String? apiBase;
  final int? timeout;
  final Map<String, dynamic>? endpoints;

  // Images config can have nested structure (mode, items, proxyPatterns, etc.)
  // so it must be `Map<String, dynamic>`, not `Map<String, String>`.
  final Map<String, dynamic>? images;

  final Map<String, dynamic>? extensionMapping;
  final List<String>? mirrors;
  final bool? useMirrors;

  ApiConfig({
    required this.enabled,
    this.baseUrl,
    this.apiBase,
    this.timeout,
    this.endpoints,
    this.images,
    this.extensionMapping,
    this.mirrors,
    this.useMirrors,
  });

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ApiConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ScraperConfig {
  final bool enabled;
  // Selectors are nested generic maps because they vary wildly by source
  final Map<String, dynamic>? selectors;
  final Map<String, dynamic>? urlPatterns;

  ScraperConfig({
    required this.enabled,
    this.selectors,
    this.urlPatterns,
  });

  factory ScraperConfig.fromJson(Map<String, dynamic> json) =>
      _$ScraperConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ScraperConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class NetworkConfig {
  final RateLimitConfig? rateLimit;
  final RetryConfig? retry;
  final CloudflareConfig? cloudflare;
  final int? timeout; // For simple network configs

  NetworkConfig({
    this.rateLimit,
    this.retry,
    this.cloudflare,
    this.timeout,
  });

  factory NetworkConfig.fromJson(Map<String, dynamic> json) =>
      _$NetworkConfigFromJson(json);
  Map<String, dynamic> toJson() => _$NetworkConfigToJson(this);
}

@JsonSerializable()
class RateLimitConfig {
  final bool enabled;
  final int requestsPerMinute;
  final int minDelayMs;
  final int? cooldownDurationMs;

  RateLimitConfig({
    this.enabled = true,
    required this.requestsPerMinute,
    required this.minDelayMs,
    this.cooldownDurationMs,
  });

  factory RateLimitConfig.fromJson(Map<String, dynamic> json) =>
      _$RateLimitConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RateLimitConfigToJson(this);
}

@JsonSerializable()
class RetryConfig {
  final int maxAttempts;
  final int? delayMs;
  final bool exponentialBackoff;

  RetryConfig({
    required this.maxAttempts,
    this.delayMs,
    this.exponentialBackoff = true,
  });

  factory RetryConfig.fromJson(Map<String, dynamic> json) =>
      _$RetryConfigFromJson(json);
  Map<String, dynamic> toJson() => _$RetryConfigToJson(this);
}

@JsonSerializable()
class CloudflareConfig {
  final bool bypassEnabled;
  final bool antiDetection;

  CloudflareConfig({
    required this.bypassEnabled,
    required this.antiDetection,
  });

  factory CloudflareConfig.fromJson(Map<String, dynamic> json) =>
      _$CloudflareConfigFromJson(json);
  Map<String, dynamic> toJson() => _$CloudflareConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class FeatureConfig {
  final bool search;
  final bool related;
  final bool download;
  final bool favorite;
  final bool chapters;
  final bool bookmark;
  final bool comments;
  final bool supportsTagExclusion;
  final bool supportsAdvancedSearch;
  final bool generatePdf;
  final bool offlineMode;

  // Per-feature maintenance info keyed by feature name (e.g. `"comments"`).
  // When a key is present and its `active` flag is `true`, the feature is
  // shown as under maintenance instead of being fully hidden.
  final Map<String, MaintenanceInfo>? maintenanceFeatures;

  FeatureConfig({
    this.search = false,
    this.related = false,
    this.download = false,
    this.favorite = false,
    this.chapters = false,
    this.bookmark = false,
    this.comments = false,
    this.supportsTagExclusion = false,
    this.supportsAdvancedSearch = false,
    this.generatePdf = false,
    this.offlineMode = false,
    this.maintenanceFeatures,
  });

  factory FeatureConfig.fromJson(Map<String, dynamic> json) =>
      _$FeatureConfigFromJson(json);
  Map<String, dynamic> toJson() => _$FeatureConfigToJson(this);
}

@JsonSerializable()
class UiConfig {
  final String displayName;
  final String iconPath;
  final String? themeColor;
  final String? brandColor;
  final String? cardStyle;

  UiConfig({
    required this.displayName,
    required this.iconPath,
    this.themeColor,
    this.brandColor,
    this.cardStyle,
  });

  String get activeColor => themeColor ?? brandColor ?? '#000000';

  factory UiConfig.fromJson(Map<String, dynamic> json) =>
      _$UiConfigFromJson(json);
  Map<String, dynamic> toJson() => _$UiConfigToJson(this);
}

@JsonSerializable()
class AuthConfig {
  final bool enabled;
  final String? loginEndpoint;
  final String? registerEndpoint;
  final List<String>? sessionCookies;
  final int? sessionDurationSeconds;

  AuthConfig({
    this.enabled = false,
    this.loginEndpoint,
    this.registerEndpoint,
    this.sessionCookies,
    this.sessionDurationSeconds,
  });

  factory AuthConfig.fromJson(Map<String, dynamic> json) => AuthConfig(
        enabled: json['enabled'] as bool? ?? false,
        loginEndpoint: json['loginEndpoint'] as String?,
        registerEndpoint: json['registerEndpoint'] as String?,
        sessionCookies: (json['sessionCookies'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        sessionDurationSeconds:
            (json['sessionDurationSeconds'] as num?)?.toInt(),
      );
  Map<String, dynamic> toJson() => _$AuthConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class TagsManifest {
  final String version;
  final String? lastUpdated;
  final Map<String, TagSourceConfig> sources;

  TagsManifest({
    required this.version,
    this.lastUpdated,
    required this.sources,
  });

  factory TagsManifest.fromJson(Map<String, dynamic> json) =>
      _$TagsManifestFromJson(json);
  Map<String, dynamic> toJson() => _$TagsManifestToJson(this);
}

@JsonSerializable(explicitToJson: true)
class TagSourceConfig {
  final String type;
  final String? assetPath;
  final String? format;
  final List<String>? structure;
  final TagMigrationConfig? migration;
  final Map<String, bool>? multiSelectSupport;
  final Map<String, String>? mappings;

  // If set, this source is an alias/variant of another source and shares its
  // tag data. The value is the source ID to inherit tags from.
  // Example: `nhentai_test` sets `parentSource: "nhentai"` to reuse nhentai tags.
  final String? parentSource;

  TagSourceConfig({
    required this.type,
    this.assetPath,
    this.format,
    this.structure,
    this.migration,
    this.multiSelectSupport,
    this.mappings,
    this.parentSource,
  });

  factory TagSourceConfig.fromJson(Map<String, dynamic> json) =>
      _$TagSourceConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TagSourceConfigToJson(this);
}

@JsonSerializable()
class TagMigrationConfig {
  final bool enabled;
  final String? remoteUrl;
  final String? fallbackUrl;
  final int? cacheTtlSeconds;

  TagMigrationConfig({
    required this.enabled,
    this.remoteUrl,
    this.fallbackUrl,
    this.cacheTtlSeconds,
  });

  factory TagMigrationConfig.fromJson(Map<String, dynamic> json) =>
      _$TagMigrationConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TagMigrationConfigToJson(this);
}

@JsonSerializable()
class ConfigVersion {
  final String version;
  @JsonKey(name: 'minimumAppVersion')
  final String? minAppVersion;
  final Map<String, ConfigManifest> configs;

  ConfigVersion({
    required this.version,
    this.minAppVersion,
    required this.configs,
  });

  factory ConfigVersion.fromJson(Map<String, dynamic> json) =>
      _$ConfigVersionFromJson(json);
  Map<String, dynamic> toJson() => _$ConfigVersionToJson(this);
}

@JsonSerializable()
class ConfigManifest {
  final String version;
  @JsonKey(name: 'url')
  final String file;

  ConfigManifest({
    required this.version,
    required this.file,
  });

  factory ConfigManifest.fromJson(Map<String, dynamic> json) =>
      _$ConfigManifestFromJson(json);
  Map<String, dynamic> toJson() => _$ConfigManifestToJson(this);
}

@JsonSerializable(explicitToJson: true)
class AppConfig {
  final AppLimits? limits;
  final AppDurations? durations;
  final AppUiConfig? ui;
  final AppStorage? storage;
  final AppReader? reader;
  final AppPrivacy? privacy;
  final Map<String, dynamic>? featureFlags;

  AppConfig({
    this.limits,
    this.durations,
    this.ui,
    this.storage,
    this.reader,
    this.privacy,
    this.featureFlags,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}

// Sub-models for AppConfig (Simplified for now, can be expanded)
@JsonSerializable()
class AppLimits {
  final int defaultPageSize;
  final int maxBatchSize;
  final int maxConcurrentDownloads;
  final int searchHistoryLimit;
  final int imagePreloadBuffer;

  AppLimits({
    this.defaultPageSize = 20,
    this.maxBatchSize = 1000,
    this.maxConcurrentDownloads = 3,
    this.searchHistoryLimit = 50,
    this.imagePreloadBuffer = 5,
  });

  factory AppLimits.fromJson(Map<String, dynamic> json) =>
      _$AppLimitsFromJson(json);
  Map<String, dynamic> toJson() => _$AppLimitsToJson(this);
}

@JsonSerializable()
class AppDurations {
  final int splashDelayMs;
  final int snackbarShortMs;
  final int snackbarLongMs;
  final int pageTransitionMs;
  final int searchDebounceMs;
  final int networkTimeoutMs;
  final int cacheExpirationHours;
  final int readerAutoHideDelaySeconds;
  final int progressUpdateIntervalMs;

  AppDurations({
    this.splashDelayMs = 1000,
    this.snackbarShortMs = 2000,
    this.snackbarLongMs = 4000,
    this.pageTransitionMs = 300,
    this.searchDebounceMs = 300,
    this.networkTimeoutMs = 30000,
    this.cacheExpirationHours = 24,
    this.readerAutoHideDelaySeconds = 3,
    this.progressUpdateIntervalMs = 100,
  });

  factory AppDurations.fromJson(Map<String, dynamic> json) =>
      _$AppDurationsFromJson(json);
  Map<String, dynamic> toJson() => _$AppDurationsToJson(this);
}

@JsonSerializable()
class AppUiConfig {
  final int gridColumnsPortrait;
  final int gridColumnsLandscape;
  final double minCardWidth;
  final double cardAspectRatio;
  final double cardBorderRadius;
  final double defaultPadding;
  final int titleMaxLength;

  AppUiConfig({
    this.gridColumnsPortrait = 2,
    this.gridColumnsLandscape = 3,
    this.minCardWidth = 150.0,
    this.cardAspectRatio = 0.65,
    this.cardBorderRadius = 12.0,
    this.defaultPadding = 16.0,
    this.titleMaxLength = 40,
  });

  factory AppUiConfig.fromJson(Map<String, dynamic> json) =>
      _$AppUiConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppUiConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class AppStorage {
  final StorageFolders? folders;
  final StorageFiles? files;
  final StorageLimits? limits;

  AppStorage({
    this.folders,
    this.files,
    this.limits,
  });

  factory AppStorage.fromJson(Map<String, dynamic> json) =>
      _$AppStorageFromJson(json);
  Map<String, dynamic> toJson() => _$AppStorageToJson(this);
}

@JsonSerializable()
class StorageFolders {
  final String backup;
  final String images;
  final String pdf;

  StorageFolders({
    this.backup = 'nhasix',
    this.images = 'images',
    this.pdf = 'pdf',
  });

  factory StorageFolders.fromJson(Map<String, dynamic> json) =>
      _$StorageFoldersFromJson(json);
  Map<String, dynamic> toJson() => _$StorageFoldersToJson(this);
}

@JsonSerializable()
class StorageFiles {
  final String metadata;
  final String config;

  StorageFiles({
    this.metadata = 'metadata.json',
    this.config = 'config.json',
  });

  factory StorageFiles.fromJson(Map<String, dynamic> json) =>
      _$StorageFilesFromJson(json);
  Map<String, dynamic> toJson() => _$StorageFilesToJson(this);
}

@JsonSerializable()
class StorageLimits {
  final int maxImageSizeKb;
  final int pdfPartsSizePages;

  StorageLimits({
    this.maxImageSizeKb = 200,
    this.pdfPartsSizePages = 100,
  });

  factory StorageLimits.fromJson(Map<String, dynamic> json) =>
      _$StorageLimitsFromJson(json);
  Map<String, dynamic> toJson() => _$StorageLimitsToJson(this);
}

@JsonSerializable()
class AppReader {
  final bool preloadNextChapter;

  AppReader({this.preloadNextChapter = true});

  factory AppReader.fromJson(Map<String, dynamic> json) =>
      _$AppReaderFromJson(json);
  Map<String, dynamic> toJson() => _$AppReaderToJson(this);
}

@JsonSerializable()
class AppPrivacy {
  final bool enableAnalytics;

  AppPrivacy({this.enableAnalytics = true});

  factory AppPrivacy.fromJson(Map<String, dynamic> json) =>
      _$AppPrivacyFromJson(json);
  Map<String, dynamic> toJson() => _$AppPrivacyToJson(this);
}

// ─────────────────────────────────────────────────────────────────────────────
// Manifest Models (remote manifest.json entry point)
// ─────────────────────────────────────────────────────────────────────────────

// Top-level manifest downloaded from the CDN. Describes all available source
// configs and their current versions.
@JsonSerializable(explicitToJson: true)
class SourceManifest {
  // Bump this when the manifest JSON schema changes incompatibly. Parsed
  // flexibly (int, "2.0"-style strings, v3+, or absent) — never crashes.
  @JsonKey(
    fromJson: parseManifestSchemaVersion,
    toJson: _manifestSchemaVersionToJson,
  )
  final int schemaVersion;
  final String lastUpdated;

  // Minimum app version required to use these configs.
  final String? minimumAppVersion;

  // Opaque extensions-compatibility payload, when the manifest ships one.
  // Kept as [Object] so unknown future shapes pass through untouched.
  final Object? extensionsCompat;

  // Metadata for the global app-config.json.
  final SourceManifestAppEntry? appConfig;

  // List of installable (non-bundled) source entries available for download.
  // Bundled sources like `nhentai` are not included here.
  @JsonKey(defaultValue: [])
  final List<SourceManifestEntry> installableSources;

  SourceManifest({
    required this.schemaVersion,
    required this.lastUpdated,
    this.minimumAppVersion,
    this.extensionsCompat,
    this.appConfig,
    required this.installableSources,
  });

  factory SourceManifest.fromJson(Map<String, dynamic> json) =>
      _$SourceManifestFromJson(json);
  Map<String, dynamic> toJson() => _$SourceManifestToJson(this);
}

// Manifest entry for the global app-config.
@JsonSerializable()
class SourceManifestAppEntry {
  final String version;

  // Relative URL to the config file (resolved against the CDN base URL).
  final String url;
  final String? checksum;

  SourceManifestAppEntry({
    required this.version,
    required this.url,
    this.checksum,
  });

  factory SourceManifestAppEntry.fromJson(Map<String, dynamic> json) =>
      _$SourceManifestAppEntryFromJson(json);
  Map<String, dynamic> toJson() => _$SourceManifestAppEntryToJson(this);
}

// One source entry inside the manifest.
@JsonSerializable(explicitToJson: true)
class SourceManifestEntry {
  // Unique source identifier (e.g. "nhentai", "mangadex").
  final String id;

  // Whether this source is bundled into the APK.
  // `true` only for nhentai — it is always available and cannot be uninstalled.
  // All other sources are installable: user downloads the config via Settings.
  @JsonKey(defaultValue: false)
  final bool bundled;

  // Whether this source should be loaded by the app.
  @JsonKey(defaultValue: true)
  final bool enabled;

  // Maintenance status for this source (fast gate from manifest level).
  // Legacy shape: entry-level object. Current manifests (schema v2) carry
  // the flag in `meta` instead — see [effectiveMaintenance].
  final MaintenanceInfo? maintenance;

  // Version string — used for cache invalidation against locally stored config.
  final String version;

  // Relative URL to the source config file.
  final String url;

  // Optional SHA-256 checksum for integrity validation.
  final String? checksum;

  // Metadata used by the Source Manager UI before the full config is downloaded.
  final SourceManifestMeta? meta;

  SourceManifestEntry({
    required this.id,
    this.bundled = false,
    this.enabled = true,
    this.maintenance,
    required this.version,
    required this.url,
    this.checksum,
    this.meta,
  });

  factory SourceManifestEntry.fromJson(Map<String, dynamic> json) =>
      _$SourceManifestEntryFromJson(json);
  Map<String, dynamic> toJson() => _$SourceManifestEntryToJson(this);

  /// Effective maintenance status: entry-level [maintenance] wins; falls
  /// back to the manifest `meta` flag (`maintenance: true` +
  /// `maintenanceMessage`) that schema-v2 manifests sync from the config.
  MaintenanceInfo? get effectiveMaintenance {
    if (maintenance != null) return maintenance;
    if (meta?.maintenance == true) {
      return MaintenanceInfo(
        active: true,
        reason: meta?.maintenanceMessage,
      );
    }
    return null;
  }
}

// Display metadata for a source shown in the Source Manager UI.
// Available from the manifest before the full per-source config is downloaded.
@JsonSerializable()
class SourceManifestMeta {
  final String displayName;
  final String? description;

  // For bundled sources (nhentai): local asset path.
  // For installable sources: CDN URL.
  final String? iconUrl;

  // E.g. "manga", "doujinshi", "all"
  final String? contentType;

  // Dominant language of the content, e.g. "id", "en", "all"
  final String? language;

  // Whether the user must log in to use this source.
  @JsonKey(defaultValue: false)
  final bool requiresAuth;

  // Whether this source needs a special adapter (CF bypass, decryption, etc.)
  @JsonKey(defaultValue: false)
  final bool requiresSpecialAdapter;

  // Estimated config file size in KB.
  final int? sizeKb;

  /// Bypass posture mirrored from the source config (`network` block).
  /// `"none"` (default/absent), `"lazy"`, or `"turnstile"`. Kept as a raw
  /// string so future statuses parse without crashing; see [bypassShield]
  /// for the normalized read.
  final String? bypassStatus;

  /// Mirrors `network.requiresBypass` — forwarded into the per-source
  /// Dio/bypass scope (#86) when the installed config lacks the flag.
  @JsonKey(defaultValue: false)
  final bool requiresBypass;

  /// Schema-v2 maintenance flag (lives in `meta`, synced from the config).
  /// Prefer [SourceManifestEntry.effectiveMaintenance] over reading this
  /// directly.
  @JsonKey(defaultValue: false)
  final bool maintenance;

  /// Human-readable maintenance message synced from the config.
  final String? maintenanceMessage;

  SourceManifestMeta({
    required this.displayName,
    this.description,
    this.iconUrl,
    this.contentType,
    this.language,
    this.requiresAuth = false,
    this.requiresSpecialAdapter = false,
    this.sizeKb,
    this.bypassStatus,
    this.requiresBypass = false,
    this.maintenance = false,
    this.maintenanceMessage,
  });

  factory SourceManifestMeta.fromJson(Map<String, dynamic> json) =>
      _$SourceManifestMetaFromJson(json);
  Map<String, dynamic> toJson() => _$SourceManifestMetaToJson(this);

  /// Normalized bypass posture: `'lazy'` or `'turnstile'` when the manifest
  /// declares a shield, null for `'none'`/absent/unknown values.
  String? get bypassShield {
    switch (bypassStatus?.trim().toLowerCase()) {
      case 'lazy':
      case 'turnstile':
        return bypassStatus!.trim().toLowerCase();
      default:
        return null;
    }
  }
}

// Maintenance status at the manifest level (fast gate, no full config needed).
@JsonSerializable()
class MaintenanceInfo {
  @JsonKey(defaultValue: false)
  final bool active;
  final String? reason;
  final String? estimatedRecovery;
  final String? contactUrl;

  MaintenanceInfo({
    this.active = false,
    this.reason,
    this.estimatedRecovery,
    this.contactUrl,
  });

  factory MaintenanceInfo.fromJson(Map<String, dynamic> json) =>
      _$MaintenanceInfoFromJson(json);
  Map<String, dynamic> toJson() => _$MaintenanceInfoToJson(this);
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic Search Form — used by scraper-based sources (e.g. KomikTap)
// ─────────────────────────────────────────────────────────────────────────────

// Top-level `searchForm` block in a source config JSON.
///
// Describes which URL pattern to use for search and what form fields are
// available so [DynamicFormSearchUI] can render them generically.
@JsonSerializable(explicitToJson: true)
class SearchFormConfig {
  // Key in `scraper.urlPatterns` to use for the search request.
  final String urlPattern;

  // Map of logical field name → field definition.
  // Field names are arbitrary (e.g. "query", "status", "order", "genre").
  final Map<String, SearchFormFieldConfig> params;

  SearchFormConfig({required this.urlPattern, required this.params});

  factory SearchFormConfig.fromJson(Map<String, dynamic> json) =>
      _$SearchFormConfigFromJson(json);
  Map<String, dynamic> toJson() => _$SearchFormConfigToJson(this);
}

// A single option entry for [SearchFormFieldConfig.options].
///
// Supports both plain-string and object-form in JSON:
// ```json
// "options": ["update"]
// "options": [{"name": "Update", "value": "update"}]
// ```
@JsonSerializable()
class SearchFormOptionConfig {
  final String value;
  @JsonKey(name: 'name')
  final String? name;
  final String? label;

  const SearchFormOptionConfig({required this.value, this.name, this.label});

  // Accepts both `{"value": "...", "name": "..."}` and plain `"..."` strings.
  factory SearchFormOptionConfig.fromJson(dynamic json) {
    if (json is String) {
      return SearchFormOptionConfig(value: json, label: json, name: json);
    }
    return _$SearchFormOptionConfigFromJson(Map<String, dynamic>.from(json));
  }
  Map<String, dynamic> toJson() => _$SearchFormOptionConfigToJson(this);
}

// Single field definition inside [SearchFormConfig.params].
@JsonSerializable(explicitToJson: true)
class SearchFormFieldConfig {
  // Field type: `"text"`, `"select"`, `"tag"`, or `"page"`.
  final String type;

  // The actual HTTP query-parameter name sent to the server (e.g. `"s"`,
  // `"status"`, `"order"`, `"genre"`).
  final String? queryParam;

  // Placeholder text (for `text` fields).
  final String? placeholder;

  // Allowed option values (for `select` fields).
  final List<SearchFormOptionConfig>? options;

  // Which URL pattern to use when this field drives navigation
  // (for `tag`/genre fields, e.g. `"genreSearch"`).
  final String? urlPattern;

  SearchFormFieldConfig({
    required this.type,
    this.queryParam,
    this.placeholder,
    this.options,
    this.urlPattern,
  });

  factory SearchFormFieldConfig.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<SearchFormOptionConfig>? parsedOptions;
    if (rawOptions is List) {
      parsedOptions = rawOptions
          .map((e) => SearchFormOptionConfig.fromJson(e))
          .toList(growable: false);
    }
    return SearchFormFieldConfig(
      type: json['type'] as String,
      queryParam: json['queryParam'] as String?,
      placeholder: json['placeholder'] as String?,
      options: parsedOptions,
      urlPattern: json['urlPattern'] as String?,
    );
  }
  Map<String, dynamic> toJson() => _$SearchFormFieldConfigToJson(this);
}
