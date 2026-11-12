import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/services/anomaly/anomaly_store.dart';

void main() {
  group('fingerprintFor', () {
    test('same input produces the same fingerprint', () {
      final a = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: 'chapter',
      );
      final b = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: 'chapter',
      );
      expect(a, equals(b));
      expect(a, isNotEmpty);
    });

    test('different source produces different fingerprint', () {
      final a = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: 'chapter',
      );
      final b = AnomalyStore.fingerprintFor(
        sourceId: 'manhwaden',
        feature: 'reader-empty',
        kind: 'empty',
        template: 'chapter',
      );
      expect(a, isNot(equals(b)));
    });

    test('different feature, kind, or template changes fingerprint', () {
      const base = {
        'sourceId': 'komiktap',
        'feature': 'reader-empty',
        'kind': 'empty',
        'template': 'chapter',
      };
      String fp(Map<String, String> m) => AnomalyStore.fingerprintFor(
            sourceId: m['sourceId']!,
            feature: m['feature']!,
            kind: m['kind']!,
            template: m['template']!,
          );
      final expected = fp(base);
      expect(fp({...base, 'feature': 'detail-parse'}), isNot(expected));
      expect(fp({...base, 'kind': 'mapping-failed'}), isNot(expected));
      expect(fp({...base, 'template': 'other'}), isNot(expected));
    });

    test('fingerprint is a stable lowercase hex digest', () {
      final fp = AnomalyStore.fingerprintFor(
        sourceId: 'komiktap',
        feature: 'reader-empty',
        kind: 'empty',
        template: 'chapter',
      );
      expect(fp, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('isExcludedAnomalyChapter', () {
    test('externalUrl set means excluded', () {
      expect(
        isExcludedAnomalyChapter(externalUrl: 'https://comikey.com/x'),
        isTrue,
      );
    });

    test('blank externalUrl is not excluded', () {
      expect(isExcludedAnomalyChapter(externalUrl: '   '), isFalse);
      expect(isExcludedAnomalyChapter(), isFalse);
    });

    test('isUnavailable means excluded', () {
      expect(isExcludedAnomalyChapter(isUnavailable: true), isTrue);
    });
  });
}
