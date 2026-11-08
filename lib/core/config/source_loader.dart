import 'package:logger/logger.dart';
import 'package:kuron_core/kuron_core.dart';

import 'remote_config_service.dart';

// Applies the remote manifest to the [ContentSourceRegistry].
///
// ### Responsibilities
// - After [RemoteConfigService.smartInitialize] completes, call
//   [applyManifest] to reconcile the registry against manifest data.
// - Sources flagged `enabled: false` in the manifest are **unregistered**
//   so they never appear in any UI list.
// - Sources flagged `maintenance.active: true` (but still enabled) remain registered
//   but are tracked in [maintenanceSourceIds] so the UI can show a banner.
///
// ### Usage (in splash / initialization flow)
// ```dart
// await remoteConfigService.smartInitialize();
// sourceLoader.applyManifest(registry);
// ```
class SourceLoader {
  final RemoteConfigService _configService;
  final Logger _logger;

  // Source IDs currently under maintenance (enabled but unavailable).
  final Set<String> _maintenanceSourceIds = {};

  SourceLoader({required this._configService, required this._logger});

  // ── Public API ────────────────────────────────────────────────────────────

  // Reconcile [registry] against the loaded manifest.
  ///
  // Call this **after** [RemoteConfigService.smartInitialize] so manifest
  // data is available. Safe to call multiple times (idempotent).
  void applyManifest(ContentSourceRegistry registry) {
    final manifest = _configService.manifest;

    if (manifest == null) {
      _logger.w('SourceLoader: no manifest loaded — skipping reconciliation');
      return;
    }

    _maintenanceSourceIds.clear();

    for (final entry in manifest.installableSources) {
      final sourceId = entry.id;

      if (!entry.enabled) {
        // Remove from registry entirely — source disabled remotely.
        if (registry.hasSource(sourceId)) {
          registry.unregister(sourceId);
          _logger.i('SourceLoader: unregistered disabled source "$sourceId"');
        }
        continue;
      }

      if (entry.maintenance?.active ?? false) {
        _maintenanceSourceIds.add(sourceId);
        _logger.w('SourceLoader: source "$sourceId" is under maintenance');
      }
    }

    _logger.i(
      'SourceLoader: manifest applied — '
      '${registry.sourceCount} active sources, '
      '${_maintenanceSourceIds.length} under maintenance',
    );
  }

  // Returns `true` if the given source is currently under maintenance.
  bool isUnderMaintenance(String sourceId) =>
      _maintenanceSourceIds.contains(sourceId);

  // Returns the maintenance message for a source, if any.
  ///
  // Returns `null` if the source is not under maintenance or no message
  // is defined in its [SourceConfig].
  String? getMaintenanceMessage(String sourceId) {
    if (!isUnderMaintenance(sourceId)) return null;
    return _configService.getConfig(sourceId)?.maintenanceMessage;
  }

  // All source IDs currently flagged as under maintenance.
  Set<String> get maintenanceSourceIds =>
      Set.unmodifiable(_maintenanceSourceIds);
}
