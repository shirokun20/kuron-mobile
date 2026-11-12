/// Model representing an anomaly detected at runtime.
class AnomalyRecord {
  const AnomalyRecord({
    required this.fingerprint,
    required this.sourceId,
    required this.feature,
    required this.kind,
    required this.count,
    required this.lastSeen,
    required this.eligible,
    this.context,
    this.configVersion,
    this.firstSeen,
  });

  final String fingerprint;
  final String sourceId;
  final String feature;
  final String kind;
  final int count;
  final DateTime lastSeen;
  final bool eligible;
  final Map<String, dynamic>? context;
  final String? configVersion;
  final DateTime? firstSeen;
}

/// Abstract contract for AnomalyStore.
/// Implemented by AnomalyStore (W1) during integration, or fake in widget tests.
abstract class AnomalyStoreContract {
  Future<List<AnomalyRecord>> records();
  Future<void> deleteRecord(String fingerprint);
}
