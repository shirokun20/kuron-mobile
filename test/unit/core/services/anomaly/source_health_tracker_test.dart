import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/anomaly/source_health_tracker.dart';

void main() {
  group('SourceHealthTracker', () {
    late SourceHealthTracker tracker;

    setUp(() {
      tracker = SourceHealthTracker();
    });

    test('fresh tracker reports no source as healthy', () {
      expect(tracker.isHealthy('komiktap'), isFalse);
    });

    test('markSuccess makes the source healthy', () {
      tracker.markSuccess('komiktap', 'list');
      expect(tracker.isHealthy('komiktap'), isTrue);
    });

    test('health is scoped per source', () {
      tracker.markSuccess('komiktap', 'list');
      expect(tracker.isHealthy('komiktap'), isTrue);
      expect(tracker.isHealthy('manhwaden'), isFalse);
    });

    test('source ids are normalized (case and whitespace)', () {
      tracker.markSuccess('  KomikTap ', 'list');
      expect(tracker.isHealthy('komiktap'), isTrue);
      expect(tracker.isHealthy('KOMIKTAP'), isTrue);
    });

    test('any feature success marks the source healthy', () {
      tracker.markSuccess('komiktap', 'reader');
      expect(tracker.isHealthy('komiktap'), isTrue);
    });

    test('reset clears all health signals', () {
      tracker.markSuccess('komiktap', 'list');
      tracker.markSuccess('manhwaden', 'detail');
      tracker.reset();
      expect(tracker.isHealthy('komiktap'), isFalse);
      expect(tracker.isHealthy('manhwaden'), isFalse);
    });
  });
}
