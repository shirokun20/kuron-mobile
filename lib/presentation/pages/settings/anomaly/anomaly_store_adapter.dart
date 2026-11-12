import 'dart:convert';

import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart'
    as store;
import 'anomaly_store_contract.dart' as ui;

/// Group 6 integration: binds W1's sqflite-backed store to W2's UI contract.
///
/// int-ms <-> DateTime mapping lives here so neither side changes.
/// W3's ErrorLog gets the same treatment via [ErrorLogAdapter].
class AnomalyStoreAdapter implements ui.AnomalyStoreContract {
  AnomalyStoreAdapter(this._inner);

  final store.AnomalyStore _inner;

  @override
  Future<List<ui.AnomalyRecord>> records() async {
    final rows = await _inner.records();
    return [
      for (final r in rows)
        ui.AnomalyRecord(
          fingerprint: r.fingerprint,
          sourceId: r.sourceId,
          feature: r.feature,
          kind: r.kind,
          count: r.count,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(r.lastSeen),
          eligible: r.eligible,
          context: _decodeContext(r.contextJson),
          configVersion: r.configVersion,
          firstSeen: DateTime.fromMillisecondsSinceEpoch(r.firstSeen),
        ),
    ];
  }

  @override
  Future<void> deleteRecord(String fingerprint) =>
      _inner.deleteRecord(fingerprint);

  static Map<String, dynamic>? _decodeContext(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
