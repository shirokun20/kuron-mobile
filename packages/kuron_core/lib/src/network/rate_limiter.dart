import 'dart:async';

// Asynchronous semaphore for controlling concurrent access.
///
// Used by [RateLimiter] to limit the number of concurrent requests.
class Semaphore {
  Semaphore(int maxCount) : _currentCount = maxCount;

  int _currentCount;
  final _waitQueue = <Completer<void>>[];

  // Acquire a permit. Waits if all permits are taken.
  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  // Release a permit, allowing the next waiting task to proceed.
  void release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _currentCount++;
    }
  }
}

// Rate limiter for source HTTP requests.
///
// Enforces a minimum delay between requests and limits concurrent requests.
// This is a pure Dart utility (no Dio dependency) that can be used by
// any source implementation.
///
// ## Usage
// ```dart
// final rateLimiter = RateLimiter(
//   delay: Duration(milliseconds: 500),
//   maxConcurrent: 1,
// );
///
// // Wrap each request
// final result = await rateLimiter.execute(() => dio.get('/api/data'));
// ```
class RateLimiter {
  RateLimiter({
    this.delay = const Duration(milliseconds: 500),
    int maxConcurrent = 1,
  }) : _semaphore = Semaphore(maxConcurrent);

  // Minimum delay between consecutive requests
  final Duration delay;

  final Semaphore _semaphore;
  DateTime? _lastRequest;

  // Execute [request] with rate limiting applied.
  ///
  // Ensures:
  // 1. Only [maxConcurrent] requests run simultaneously
  // 2. At least [delay] milliseconds between consecutive requests
  Future<T> execute<T>(Future<T> Function() request) async {
    await _semaphore.acquire();
    try {
      await _waitTurn();
      return await request();
    } finally {
      _semaphore.release();
    }
  }

  /// Wait for the minimum delay without holding a permit afterwards. Use
  /// when the request itself runs elsewhere and only pacing is needed.
  Future<void> throttle() async {
    await _semaphore.acquire();
    try {
      await _waitTurn();
    } finally {
      _semaphore.release();
    }
  }

  Future<void> _waitTurn() async {
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed < delay) {
        await Future<void>.delayed(delay - elapsed);
      }
    }
    _lastRequest = DateTime.now();
  }

  /// Build a limiter from a config `network` block, or null when the
  /// config declares no usable limit. Mirrors the keys generic sources use:
  /// `rateLimit: {enabled, minDelayMs, requestsPerSecond, requestsPerMinute,
  /// maxConcurrentRequests}`.
  static RateLimiter? fromNetwork(Map<String, dynamic>? network) {
    final rateLimit =
        (network?['rateLimit'] as Map?)?.cast<String, dynamic>();
    if (rateLimit == null) return null;
    final enabled = rateLimit['enabled'];
    if (enabled is bool && !enabled) return null;

    final minDelayMs = _resolveMinDelayMs(rateLimit);
    if (minDelayMs == null || minDelayMs <= 0) return null;

    return RateLimiter(
      delay: Duration(milliseconds: minDelayMs),
      maxConcurrent: _readPositiveInt(rateLimit['maxConcurrentRequests']) ?? 1,
    );
  }

  static int? _resolveMinDelayMs(Map<String, dynamic> rateLimit) {
    final configuredDelay = _readPositiveInt(rateLimit['minDelayMs']);
    if (configuredDelay != null) return configuredDelay;

    final requestsPerSecond =
        _readPositiveDouble(rateLimit['requestsPerSecond']);
    if (requestsPerSecond != null) return (1000 / requestsPerSecond).ceil();

    final requestsPerMinute =
        _readPositiveDouble(rateLimit['requestsPerMinute']);
    if (requestsPerMinute != null) return (60000 / requestsPerMinute).ceil();

    return null;
  }

  static int? _readPositiveInt(Object? value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    return null;
  }

  static double? _readPositiveDouble(Object? value) {
    if (value is num && value > 0) return value.toDouble();
    return null;
  }
}
