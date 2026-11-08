import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/utils/source_config_display_utils.dart';
import 'package:nhasixapp/core/utils/source_version_utils.dart';

enum ManifestSortMode { updatesFirst, nameAsc, versionDesc }

class SourcePackageManifest {
  const SourcePackageManifest({
    required this.schemaVersion,
    required this.sourceId,
    required this.version,
    required this.configPath,
    required this.checksumSha256,
    required this.displayName,
  });

  final int schemaVersion;
  final String sourceId;
  final String version;
  final String configPath;
  final String checksumSha256;
  final String? displayName;

  static SourcePackageManifest fromMap(
    Map<String, dynamic> map, {
    String invalidMessage = 'Invalid manifest format',
  }) {
    final rawSchemaVersion = map['schemaVersion'];
    final schemaVersion = rawSchemaVersion is int ? rawSchemaVersion : 1;

    String readAnyString(List<String> keys, {bool required = true}) {
      for (final key in keys) {
        final value = map[key] as String?;
        if (value != null && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      if (!required) return '';
      throw FormatException(invalidMessage);
    }

    String normalizeConfigPath(String rawPath) {
      if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
        final uri = Uri.tryParse(rawPath);
        if (uri != null && uri.path.isNotEmpty) {
          rawPath = uri.path;
        }
      }

      var normalized = rawPath.replaceAll('\\', '/').trim();
      while (normalized.startsWith('/')) {
        normalized = normalized.substring(1);
      }
      if (normalized.startsWith('./')) {
        normalized = normalized.substring(2);
      }
      return normalized;
    }

    final sourceId = readAnyString(const ['sourceId', 'id', 'source']);
    final version = readAnyString(const ['version']);
    final configPathRaw = readAnyString(const ['configPath', 'path', 'url']);
    final checksum = readAnyString(
      const ['checksumSha256', 'checksum'],
      required: false,
    );

    return SourcePackageManifest(
      schemaVersion: schemaVersion,
      sourceId: sourceId,
      version: version,
      configPath: normalizeConfigPath(configPathRaw),
      checksumSha256: checksum,
      displayName: (map['displayName'] as String?)?.trim(),
    );
  }
}

class SourceInstallCandidate {
  const SourceInstallCandidate({
    required this.sourceId,
    required this.version,
    required this.displayName,
    required this.description,
    required this.rawJson,
    required this.isVerified,
  });

  final String sourceId;
  final String version;
  final String? displayName;
  final String? description;
  final String rawJson;
  final bool isVerified;
}

class GlobalManifestEntry {
  const GlobalManifestEntry({
    required this.id,
    required this.version,
    required this.url,
    required this.checksumSha256,
    required this.displayName,
    required this.description,
    required this.iconUrl,
  });

  final String id;
  final String version;
  final String url;
  final String? checksumSha256;
  final String? displayName;
  final String? description;
  final String? iconUrl;

  static GlobalManifestEntry fromMap(
    Map<String, dynamic> map, {
    String invalidMessage = 'Invalid manifest format',
  }) {
    String readRequired(String key) {
      final value = map[key] as String?;
      if (value == null || value.trim().isEmpty) {
        throw FormatException(invalidMessage);
      }
      return value.trim();
    }

    final meta = map['meta'];
    String? displayName;
    String? description;
    String? iconUrl;
    if (meta is Map<String, dynamic>) {
      displayName = (meta['displayName'] as String?)?.trim();
      description = (meta['description'] as String?)?.trim();
      iconUrl = (meta['iconUrl'] as String?)?.trim();
    }

    return GlobalManifestEntry(
      id: readRequired('id'),
      version: readRequired('version'),
      url: readRequired('url'),
      checksumSha256: (map['checksum'] as String?)?.trim(),
      displayName: displayName,
      description: description,
      iconUrl: iconUrl,
    );
  }
}

class SourceInstallResult {
  const SourceInstallResult({
    required this.installed,
    required this.failed,
    required this.failedReasons,
  });

  final List<String> installed;
  final List<String> failed;
  final Map<String, String> failedReasons;

  bool get isAllSuccess => failed.isEmpty;
  bool get hasFailures => failed.isNotEmpty;
}

sealed class SourceInstallPlan {
  const SourceInstallPlan();
}

class SourceInstallDirectPlan extends SourceInstallPlan {
  const SourceInstallDirectPlan(this.candidates);
  final List<SourceInstallCandidate> candidates;
}

class SourceInstallSelectionPlan extends SourceInstallPlan {
  const SourceInstallSelectionPlan({
    required this.entries,
    this.baseLink,
    this.zipBytes,
  });
  final List<GlobalManifestEntry> entries;
  final String? baseLink;
  final List<int>? zipBytes;
}

/// Service owning download, verification (sha256), icon file caching,
/// configuration application, and dynamic ContentSource instantiation.
class SourceInstallerService {
  final Dio _dio;
  final RemoteConfigService _remoteConfig;
  final ContentSourceRegistry _registry;
  final SourceFactoryResolver _resolver;
  final GenericSourceFactory _genericFactory;
  final Logger _logger;

  SourceInstallerService({
    required this._dio,
    required this._remoteConfig,
    required this._registry,
    required this._resolver,
    required this._genericFactory,
    required this._logger,
  });

  // Session-only candidate versions from the last opened manifest (link/ZIP).
  // Powers the Update badge/sort in the installed list. In-memory only by design.
  final Map<String, String> _lastSeenCandidateVersions = <String, String>{};

  void rememberCandidateVersions(Iterable<({String id, String version})> items) {
    for (final item in items) {
      final v = item.version.trim();
      if (v.isNotEmpty && v.toLowerCase() != 'unknown') {
        _lastSeenCandidateVersions[item.id] = v;
      }
    }
  }

  void forgetCandidateVersion(String sourceId) {
    _lastSeenCandidateVersions.remove(sourceId);
  }

  String? getCandidateVersion(String sourceId) =>
      _lastSeenCandidateVersions[sourceId];

  bool isCandidateVersionRemembered(String sourceId) =>
      _lastSeenCandidateVersions.containsKey(sourceId);

  String? getInstalledVersion(String sourceId) =>
      _remoteConfig.getInstalledVersion(sourceId);

  SourceConfigDisplayInfo resolveDisplayInfo(String sourceId) =>
      resolveSourceConfigDisplayInfo(
        remoteConfigService: _remoteConfig,
        sourceId: sourceId,
      );

  SourceVersionStatus getVersionStatus({
    required String sourceId,
    required String candidateVersion,
  }) {
    final installed = _remoteConfig.getInstalledVersion(sourceId);
    return resolveSourceVersionStatus(
      installedVersion: installed,
      candidateVersion: candidateVersion,
    );
  }

  List<({T source, SourceVersionStatus status})> sortSourcesUpdateFirst<T>(
    Iterable<T> sources,
    String Function(T source) idOf,
  ) {
    final ranked = sources.map((source) {
      final id = idOf(source);
      return (
        source: source,
        status: resolveSourceVersionStatus(
          installedVersion: _remoteConfig.getInstalledVersion(id),
          candidateVersion: _lastSeenCandidateVersions[id],
        ),
      );
    }).toList();
    final indexed = ranked.asMap().entries.toList();
    indexed.sort((a, b) {
      final rank = _statusRank(a.value.status).compareTo(
        _statusRank(b.value.status),
      );
      return rank != 0 ? rank : a.key.compareTo(b.key);
    });
    return [for (final entry in indexed) entry.value];
  }

  static int _statusRank(SourceVersionStatus status) =>
      status == SourceVersionStatus.updateAvailable ? 0 : 1;

  List<GlobalManifestEntry> sortEntriesUpdateFirst(
    List<GlobalManifestEntry> entries,
  ) =>
      sortUpdateFirst(
        entries,
        installedVersionOf: (entry) =>
            _remoteConfig.getInstalledVersion(entry.id),
        candidateVersionOf: (entry) => entry.version,
      );

  List<GlobalManifestEntry> applyManifestSort(
    List<GlobalManifestEntry> entries,
    ManifestSortMode mode,
  ) {
    final copy = List<GlobalManifestEntry>.from(entries);
    switch (mode) {
      case ManifestSortMode.updatesFirst:
        return sortEntriesUpdateFirst(copy);
      case ManifestSortMode.nameAsc:
        copy.sort((a, b) {
          final nameA = (a.displayName ?? a.id).toLowerCase();
          final nameB = (b.displayName ?? b.id).toLowerCase();
          return nameA.compareTo(nameB);
        });
        return copy;
      case ManifestSortMode.versionDesc:
        copy.sort((a, b) {
          switch (compareSourceVersions(b.version, a.version)) {
            case SourceVersionComparison.newer:
              return -1;
            case SourceVersionComparison.older:
              return 1;
            case SourceVersionComparison.same:
            case SourceVersionComparison.unknown:
              break;
          }
          return (a.displayName ?? a.id)
              .toLowerCase()
              .compareTo((b.displayName ?? b.id).toLowerCase());
        });
        return copy;
    }
  }

  /// Downloads and inspects a remote manifest link.
  /// Returns a plan which is either direct candidates or a selection plan.
  Future<SourceInstallPlan> inspectLink(String link) async {
    final manifestResponse = await _dio.get<String>(
      link,
      options: Options(
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ),
    );

    final manifestRaw = manifestResponse.data;
    if (manifestRaw == null || manifestRaw.trim().isEmpty) {
      throw const FormatException('Manifest is empty');
    }

    final manifestMap = _decodeJsonObject(
      rawJson: manifestRaw,
      invalidMessage: 'Invalid manifest format',
    );

    if (manifestMap.containsKey('source')) {
      final sourceId = _requiredString(
        manifestMap,
        'source',
        'Missing source field in config',
      );
      final version = (manifestMap['version'] as String?)?.trim() ?? 'unknown';
      final candidates = [
        SourceInstallCandidate(
          sourceId: sourceId,
          version: version,
          displayName: null,
          description: null,
          rawJson: manifestRaw,
          isVerified: false,
        )
      ];
      return SourceInstallDirectPlan(candidates);
    }

    final installableSources = _parseGlobalManifestEntries(manifestMap).toList();
    if (installableSources.isNotEmpty) {
      return SourceInstallSelectionPlan(
        entries: installableSources,
        baseLink: link,
      );
    }

    final manifest = SourcePackageManifest.fromMap(manifestMap);
    final resolvedConfigUrl =
        Uri.parse(link).resolve(manifest.configPath).toString();
    final configResponse = await _dio.get<String>(
      resolvedConfigUrl,
      options: Options(
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ),
    );

    final rawJson = configResponse.data;
    if (rawJson == null || rawJson.trim().isEmpty) {
      throw const FormatException('Source configuration is empty');
    }

    final configBytes = utf8.encode(rawJson);
    if (manifest.checksumSha256.isNotEmpty) {
      _validateChecksum(
        contentBytes: configBytes,
        expectedSha256: manifest.checksumSha256,
        checksumMismatchMessage: 'Checksum mismatch for source config',
      );
    }

    final configMap = _decodeJsonObject(
      rawJson: rawJson,
      invalidMessage: 'Invalid config JSON',
    );
    final sourceIdFromConfig = _requiredString(
      configMap,
      'source',
      'Config source ID does not match package manifest',
    );
    if (sourceIdFromConfig != manifest.sourceId) {
      throw const FormatException(
          'Config source ID does not match package manifest');
    }

    final candidates = [
      SourceInstallCandidate(
        sourceId: manifest.sourceId,
        version: manifest.version,
        displayName: manifest.displayName,
        description: null,
        rawJson: rawJson,
        isVerified: manifest.checksumSha256.isNotEmpty,
      )
    ];
    return SourceInstallDirectPlan(candidates);
  }

  /// Inspects a ZIP archive by decoding it and finding manifest.json.
  Future<SourceInstallPlan> inspectZip(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestFile = archive.files.where((file) {
      if (!file.isFile) return false;
      final segments = file.name.split('/');
      final name = segments.isEmpty ? file.name : segments.last;
      return name.toLowerCase() == 'manifest.json';
    }).firstOrNull;

    if (manifestFile == null) {
      throw const FormatException('manifest.json is required in the ZIP file');
    }

    final manifestBytes = manifestFile.content;
    final manifestRaw = utf8.decode(manifestBytes);
    final manifestMap = _decodeJsonObject(
      rawJson: manifestRaw,
      invalidMessage: 'Invalid manifest format',
    );

    final installableSources = _parseGlobalManifestEntries(manifestMap).toList();
    if (installableSources.isNotEmpty) {
      return SourceInstallSelectionPlan(
        entries: installableSources,
        zipBytes: bytes,
      );
    }

    if (manifestMap.containsKey('source')) {
      final sourceId = _requiredString(
        manifestMap,
        'source',
        'Missing source field in config',
      );
      final version = (manifestMap['version'] as String?)?.trim() ?? 'unknown';
      final candidates = [
        SourceInstallCandidate(
          sourceId: sourceId,
          version: version,
          displayName: null,
          description: null,
          rawJson: manifestRaw,
          isVerified: false,
        ),
      ];
      return SourceInstallDirectPlan(candidates);
    }

    final manifest = SourcePackageManifest.fromMap(manifestMap);
    final configFile = _findConfigFileInArchive(
      archive: archive,
      targetPath: manifest.configPath,
    );

    if (configFile == null) {
      throw const FormatException('Config file not found in ZIP archive');
    }

    final configBytes = configFile.content;
    if (manifest.checksumSha256.isNotEmpty) {
      _validateChecksum(
        contentBytes: configBytes,
        expectedSha256: manifest.checksumSha256,
        checksumMismatchMessage: 'Checksum mismatch for source config',
      );
    }

    final rawJson = utf8.decode(configBytes);
    final configMap = _decodeJsonObject(
      rawJson: rawJson,
      invalidMessage: 'Invalid config JSON',
    );
    final sourceIdFromConfig = _requiredString(
      configMap,
      'source',
      'Config source ID does not match package manifest',
    );
    if (sourceIdFromConfig != manifest.sourceId) {
      throw const FormatException(
          'Config source ID does not match package manifest');
    }

    final candidates = [
      SourceInstallCandidate(
        sourceId: manifest.sourceId,
        version: manifest.version,
        displayName: manifest.displayName,
        description: null,
        rawJson: rawJson,
        isVerified: manifest.checksumSha256.isNotEmpty,
      ),
    ];
    return SourceInstallDirectPlan(candidates);
  }

  /// Downloads candidate configurations and icons for selected global manifest entries.
  Future<List<SourceInstallCandidate>> fetchSelectedLinkCandidates({
    required String baseLink,
    required List<GlobalManifestEntry> selectedEntries,
  }) async {
    return Future.wait(
      selectedEntries.map(
        (entry) => _downloadCandidateFromEntry(
          baseLink: baseLink,
          entry: entry,
        ),
      ),
    );
  }

  Future<SourceInstallCandidate> _downloadCandidateFromEntry({
    required String baseLink,
    required GlobalManifestEntry entry,
  }) async {
    final resolvedConfigUrl = Uri.parse(baseLink).resolve(entry.url).toString();
    final configResponse = await _dio.get<String>(
      resolvedConfigUrl,
      options: Options(
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ),
    );

    final rawJson = configResponse.data;
    if (rawJson == null || rawJson.trim().isEmpty) {
      throw const FormatException('Source configuration is empty');
    }

    var isVerified = false;
    final checksum = entry.checksumSha256;
    if (checksum != null && checksum.isNotEmpty) {
      final configBytes = utf8.encode(rawJson);
      _validateChecksum(
        contentBytes: configBytes,
        expectedSha256: checksum,
        checksumMismatchMessage: 'Checksum mismatch for source config',
      );
      isVerified = true;
    }

    final configMap = _decodeJsonObject(
      rawJson: rawJson,
      invalidMessage: 'Invalid config JSON',
    );
    final sourceIdFromConfig = _requiredString(
      configMap,
      'source',
      'Config source ID does not match entry ID',
    );
    if (sourceIdFromConfig != entry.id) {
      throw const FormatException('Config source ID does not match entry ID');
    }

    _attachManifestMetadata(
      configMap,
      displayName: entry.displayName,
      description: entry.description,
    );
    await _cacheIconForLinkCandidate(
      sourceId: entry.id,
      configMap: configMap,
      entryIconUrl: entry.iconUrl,
      baseLink: baseLink,
    );

    return SourceInstallCandidate(
      sourceId: entry.id,
      version: entry.version,
      displayName: entry.displayName,
      description: entry.description,
      rawJson: jsonEncode(configMap),
      isVerified: isVerified,
    );
  }

  /// Extracts candidate configurations and icons from ZIP archive for selected entries.
  Future<List<SourceInstallCandidate>> extractSelectedZipCandidates({
    required List<int> zipBytes,
    required List<GlobalManifestEntry> selectedEntries,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final candidates = <SourceInstallCandidate>[];

    for (final selectedEntry in selectedEntries) {
      final configFile = _findConfigFileInArchive(
        archive: archive,
        targetPath: selectedEntry.url,
      );
      if (configFile == null) {
        continue;
      }

      final configBytes = configFile.content;
      final checksum = selectedEntry.checksumSha256;
      var isVerified = false;
      if (checksum != null && checksum.isNotEmpty) {
        _validateChecksum(
          contentBytes: configBytes,
          expectedSha256: checksum,
          checksumMismatchMessage: 'Checksum mismatch for source config',
        );
        isVerified = true;
      }

      final rawJson = utf8.decode(configBytes);
      final configMap = _decodeJsonObject(
        rawJson: rawJson,
        invalidMessage: 'Invalid config JSON',
      );
      final sourceIdFromConfig = _requiredString(
        configMap,
        'source',
        'Config source ID does not match entry ID',
      );
      if (sourceIdFromConfig != selectedEntry.id) {
        continue;
      }

      _attachManifestMetadata(
        configMap,
        displayName: selectedEntry.displayName,
        description: selectedEntry.description,
      );
      await _cacheIconForZipCandidate(
        sourceId: selectedEntry.id,
        configMap: configMap,
        archive: archive,
        entryIconUrl: selectedEntry.iconUrl,
      );

      candidates.add(
        SourceInstallCandidate(
          sourceId: selectedEntry.id,
          version: selectedEntry.version,
          displayName: selectedEntry.displayName,
          description: selectedEntry.description,
          rawJson: jsonEncode(configMap),
          isVerified: isVerified,
        ),
      );
    }

    return candidates;
  }

  /// Convenience resolver to execute selected entries on a plan.
  Future<List<SourceInstallCandidate>> resolveSelection(
    SourceInstallSelectionPlan plan,
    List<GlobalManifestEntry> selectedEntries,
  ) async {
    if (plan.baseLink != null) {
      return fetchSelectedLinkCandidates(
        baseLink: plan.baseLink!,
        selectedEntries: selectedEntries,
      );
    } else if (plan.zipBytes != null) {
      return extractSelectedZipCandidates(
        zipBytes: plan.zipBytes!,
        selectedEntries: selectedEntries,
      );
    }
    throw StateError(
      'Invalid SourceInstallSelectionPlan: neither link nor zipBytes provided',
    );
  }

  /// Applies candidate configs, marks installed, and dynamically registers sources.
  Future<SourceInstallResult> installCandidates(
    List<SourceInstallCandidate> candidates, {
    required String sourceLabel,
  }) async {
    final installed = <String>[];
    final failed = <String>[];
    final failedReasons = <String, String>{};

    for (final candidate in candidates) {
      try {
        await _remoteConfig.applySourceConfigFromJson(
          sourceId: candidate.sourceId,
          rawJson: candidate.rawJson,
          sourceLabel: sourceLabel,
        );
        await _remoteConfig.markSourceInstalled(candidate.sourceId);
        await registerSourceInRegistry(candidate.sourceId);
        installed.add(candidate.sourceId);
      } catch (e, stackTrace) {
        _logger.e(
          'Failed installing source from $sourceLabel ${candidate.sourceId}: $e',
          stackTrace: stackTrace,
        );
        failed.add(candidate.sourceId);
        failedReasons[candidate.sourceId] = e.toString();
      }
    }

    return SourceInstallResult(
      installed: installed,
      failed: failed,
      failedReasons: failedReasons,
    );
  }

  /// Instantiates source via resolver / GenericSourceFactory and registers it in ContentSourceRegistry.
  Future<void> registerSourceInRegistry(String sourceId) async {
    final raw = _remoteConfig.getRawConfig(sourceId);

    if (raw == null) {
      throw StateError('$sourceId config missing after apply');
    }

    final wasActive = _registry.currentSourceId == sourceId;
    if (_registry.hasSource(sourceId)) {
      _registry.unregister(sourceId);
    }

    ContentSource instance;
    try {
      instance = _resolver.createSource(raw);
    } catch (e, stackTrace) {
      _logger.w(
        'Specialized source factory failed for $sourceId, falling back to GenericSourceFactory',
        error: e,
        stackTrace: stackTrace,
      );
      instance = _genericFactory.create(raw);
    }

    _registry.register(instance);
    if (wasActive) {
      _registry.switchSource(sourceId);
    }
  }

  /// Uninstalls source configuration, removes from registry, and forgets candidate version.
  Future<({bool wasActive, String? nextActiveSourceId})> uninstallSource(
    String sourceId,
  ) async {
    forgetCandidateVersion(sourceId);
    final wasActive = _registry.currentSourceId == sourceId;
    await _remoteConfig.uninstallSourceConfig(sourceId);
    if (_registry.hasSource(sourceId)) {
      _registry.unregister(sourceId);
    }
    return (
      wasActive: wasActive,
      nextActiveSourceId: _registry.currentSourceId,
    );
  }

  Iterable<GlobalManifestEntry> _parseGlobalManifestEntries(
    Map<String, dynamic> map,
  ) sync* {
    final rawList = map['installableSources'];
    if (rawList is! List<dynamic>) return;

    for (final item in rawList) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      try {
        yield GlobalManifestEntry.fromMap(item);
      } catch (e) {
        _logger.w('Settings manifest parse failed', error: e);
        continue;
      }
    }
  }

  void _attachManifestMetadata(
    Map<String, dynamic> configMap, {
    String? displayName,
    String? description,
  }) {
    final meta = (configMap['meta'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    if (displayName != null && displayName.trim().isNotEmpty) {
      meta['displayName'] = displayName.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      meta['description'] = description.trim();
    }

    if (meta.isNotEmpty) {
      configMap['meta'] = meta;
    }
  }

  Future<void> _cacheIconForZipCandidate({
    required String sourceId,
    required Map<String, dynamic> configMap,
    required Archive archive,
    String? entryIconUrl,
  }) async {
    final configIconPath = _readConfigIconPath(configMap);
    final candidatePath =
        (entryIconUrl != null && entryIconUrl.trim().isNotEmpty)
            ? entryIconUrl.trim()
            : configIconPath;
    if (candidatePath == null || candidatePath.isEmpty) {
      return;
    }

    final iconFile = _findConfigFileInArchive(
      archive: archive,
      targetPath: candidatePath,
    );
    if (iconFile == null) {
      return;
    }

    final iconBytes = iconFile.content;
    final localPath = await _persistSourceIconBytes(
      sourceId: sourceId,
      iconBytes: iconBytes,
      originalPath: candidatePath,
    );
    if (localPath != null) {
      _setConfigIconPath(configMap, localPath);
    }
  }

  Future<void> _cacheIconForLinkCandidate({
    required String sourceId,
    required Map<String, dynamic> configMap,
    required String baseLink,
    String? entryIconUrl,
  }) async {
    final configIconPath = _readConfigIconPath(configMap);
    final candidatePath =
        (entryIconUrl != null && entryIconUrl.trim().isNotEmpty)
            ? entryIconUrl.trim()
            : configIconPath;
    if (candidatePath == null || candidatePath.isEmpty) {
      return;
    }

    final iconUri = Uri.tryParse(candidatePath);
    final isAbsoluteHttp = iconUri != null &&
        (iconUri.scheme == 'http' || iconUri.scheme == 'https');
    final resolvedUrl = isAbsoluteHttp
        ? candidatePath
        : Uri.parse(baseLink).resolve(candidatePath).toString();

    try {
      final response = await _dio.get<List<int>>(
        resolvedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return;
      }

      final localPath = await _persistSourceIconBytes(
        sourceId: sourceId,
        iconBytes: bytes,
        originalPath: candidatePath,
      );
      if (localPath != null) {
        _setConfigIconPath(configMap, localPath);
      }
    } catch (e, stackTrace) {
      _logger.w(
        'Failed to cache icon for $sourceId from $resolvedUrl',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  String? _readConfigIconPath(Map<String, dynamic> configMap) {
    final rawTopLevel = configMap['iconPath'] as String?;
    if (rawTopLevel != null && rawTopLevel.trim().isNotEmpty) {
      return rawTopLevel.trim();
    }

    final uiMap = (configMap['ui'] as Map?)?.cast<String, dynamic>();
    final rawUi = uiMap?['iconPath'] as String?;
    if (rawUi != null && rawUi.trim().isNotEmpty) {
      return rawUi.trim();
    }
    return null;
  }

  void _setConfigIconPath(Map<String, dynamic> configMap, String localPath) {
    configMap['iconPath'] = localPath;

    final uiMap = (configMap['ui'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    uiMap['iconPath'] = localPath;
    configMap['ui'] = uiMap;
  }

  Future<String?> _persistSourceIconBytes({
    required String sourceId,
    required List<int> iconBytes,
    required String originalPath,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final iconDir = Directory(p.join(appDir.path, 'source_icons'));
      if (!await iconDir.exists()) {
        await iconDir.create(recursive: true);
      }

      final extension = _resolveImageExtension(originalPath);
      final filePath = p.join(iconDir.path, '$sourceId$extension');
      final iconFile = File(filePath);
      await iconFile.writeAsBytes(iconBytes, flush: true);
      return filePath;
    } catch (e, stackTrace) {
      _logger.w(
        'Failed to persist local icon for $sourceId',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String _resolveImageExtension(String pathOrUrl) {
    final uri = Uri.tryParse(pathOrUrl);
    final rawPath = (uri?.path.isNotEmpty == true) ? uri!.path : pathOrUrl;
    final ext = p.extension(rawPath).toLowerCase();
    switch (ext) {
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.webp':
      case '.gif':
      case '.svg':
        return ext;
      default:
        return '.png';
    }
  }

  ArchiveFile? _findConfigFileInArchive({
    required Archive archive,
    required String targetPath,
  }) {
    final target = targetPath.replaceAll('\\', '/').toLowerCase();
    return archive.files.where((file) {
      if (!file.isFile) return false;
      final normalized = file.name.replaceAll('\\', '/').toLowerCase();
      return normalized == target || normalized.endsWith('/$target');
    }).firstOrNull;
  }

  Map<String, dynamic> _decodeJsonObject({
    required String rawJson,
    required String invalidMessage,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(invalidMessage);
    }
    return decoded;
  }

  String _requiredString(
    Map<String, dynamic> map,
    String key,
    String errorMessage,
  ) {
    final value = map[key] as String?;
    if (value == null || value.trim().isEmpty) {
      throw FormatException(errorMessage);
    }
    return value.trim();
  }

  void _validateChecksum({
    required List<int> contentBytes,
    required String expectedSha256,
    required String checksumMismatchMessage,
  }) {
    final actual = sha256.convert(contentBytes).toString().toLowerCase();
    if (actual != expectedSha256.toLowerCase()) {
      throw FormatException(checksumMismatchMessage);
    }
  }
}
