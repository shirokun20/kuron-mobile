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
  });
}
