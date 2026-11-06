import 'package:kuron_core/src/network/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter.fromNetwork (conformance-loop 4.3)', () {
    test('null without rateLimit block', () {
      expect(RateLimiter.fromNetwork(null), isNull);
      expect(RateLimiter.fromNetwork({}), isNull);
      expect(RateLimiter.fromNetwork({'rateLimit': null}), isNull);
    });

    test('null when disabled', () {
      expect(
        RateLimiter.fromNetwork({
          'rateLimit': {'enabled': false, 'minDelayMs': 100}
        }),
        isNull,
      );
    });

    test('minDelayMs wins over rates', () {
      final limiter = RateLimiter.fromNetwork({
        'rateLimit': {
          'minDelayMs': 250,
          'requestsPerSecond': 100,
          'maxConcurrentRequests': 3,
        }
      })!;
      expect(limiter.delay, const Duration(milliseconds: 250));
    });

    test('requestsPerSecond converts to delay', () {
      final limiter = RateLimiter.fromNetwork({
        'rateLimit': {'requestsPerSecond': 2}
      })!;
      expect(limiter.delay, const Duration(milliseconds: 500));
    });

    test('requestsPerMinute converts to delay', () {
      final limiter = RateLimiter.fromNetwork({
        'rateLimit': {'requestsPerMinute': 60}
      })!;
      expect(limiter.delay, const Duration(milliseconds: 1000));
    });

    test('throttle paces consecutive calls', () async {
      final limiter = RateLimiter(
        delay: const Duration(milliseconds: 60),
      );
      final sw = Stopwatch()..start();
      await limiter.throttle();
      await limiter.throttle();
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50));
    });

    test('throttle is a no-op spinner on first call', () async {
      final limiter = RateLimiter(
        delay: const Duration(milliseconds: 5000),
      );
      final sw = Stopwatch()..start();
      await limiter.throttle();
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('3 parallel requests with maxConcurrent 3 and minDelay 100ms space sequentially without bursting', () async {
      final limiter = RateLimiter(
        delay: const Duration(milliseconds: 100),
        maxConcurrent: 3,
      );
      final timestamps = <int>[];
      final sw = Stopwatch()..start();

      await Future.wait([
        limiter.execute(() async {
          timestamps.add(sw.elapsedMilliseconds);
        }),
        limiter.execute(() async {
          timestamps.add(sw.elapsedMilliseconds);
        }),
        limiter.execute(() async {
          timestamps.add(sw.elapsedMilliseconds);
        }),
      ]);

      expect(timestamps.length, 3);
      timestamps.sort();
      // Difference between consecutive requests should be >= 90ms (tolerance for timers)
      final diff1 = timestamps[1] - timestamps[0];
      final diff2 = timestamps[2] - timestamps[1];
      expect(diff1, greaterThanOrEqualTo(90), reason: 'First gap should be >= 90ms');
      expect(diff2, greaterThanOrEqualTo(90), reason: 'Second gap should be >= 90ms');
    });

    test('Semaphore clamps maxCount >= 1', () async {
      final sem = Semaphore(0);
      bool acquired = false;
      await sem.acquire();
      acquired = true;
      expect(acquired, isTrue);
      sem.release();
    });
  });
}
