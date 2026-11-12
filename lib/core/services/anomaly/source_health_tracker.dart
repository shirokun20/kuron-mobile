import 'package:logger/logger.dart';

/// In-memory per-session health signal for source-anomaly detection.
///
/// A source is "healthy" when at least one feature (list, detail, reader,
/// tag-list, search) succeeded during this app session. Every anomaly
/// detector MUST consult [isHealthy] first: when all features fail it is a
/// network outage, not a config bug, and zero records may be written.
class SourceHealthTracker {
  SourceHealthTracker({Logger? logger}) : _logger = logger ?? Logger();

  /// Global singleton used by the repository detectors.
  static final SourceHealthTracker instance = SourceHealthTracker();

  final Logger _logger;
  final Map<String, Set<String>> _healthyFeatures = {};

  static String _normalize(String sourceId) =>
      sourceId.trim().toLowerCase();

  /// Records that [feature] succeeded for [sourceId] in this session.
  void markSuccess(String sourceId, String feature) {
    final key = _normalize(sourceId);
    if (key.isEmpty) return;
    _healthyFeatures.putIfAbsent(key, () => <String>{}).add(feature);
    _logger.d('Health signal: $key/$feature OK');
  }

  /// Whether any feature succeeded for [sourceId] in this session.
  bool isHealthy(String sourceId) =>
      _healthyFeatures[_normalize(sourceId)]?.isNotEmpty ?? false;

  /// Features with a success signal for [sourceId] (read-only view).
  Set<String> featuresOf(String sourceId) =>
      Set.unmodifiable(_healthyFeatures[_normalize(sourceId)] ?? const {});

  /// Clears all signals (new session / tests).
  void reset() => _healthyFeatures.clear();
}
