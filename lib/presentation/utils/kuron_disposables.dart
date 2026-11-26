import 'dart:async';

/// Owns a single connectivity subscription and makes its disposal explicit
/// and testable. Re-listening cancels the previous subscription first.
class KuronConnectivityListener<T> {
  KuronConnectivityListener(this._stream, this._onChanged) {
    _subscribe();
  }

  final Stream<T> _stream;
  final void Function() _onChanged;
  StreamSubscription<T>? _subscription;

  bool get isListening => _subscription != null;

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _stream.listen((_) => _onChanged());
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Coalescing timer holder: at most one pending timer, always cancellable.
class KuronTimerGroup {
  final List<Timer> _timers = <Timer>[];

  int get activeCount => _timers.length;

  /// Cancels any previous timer and schedules [callback] once.
  Timer scheduleSingle(Duration duration, void Function() callback) {
    clear();
    late final Timer timer;
    timer = Timer(duration, () {
      _timers.remove(timer);
      callback();
    });
    _timers.add(timer);
    return timer;
  }

  void clear() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void dispose() => clear();
}
