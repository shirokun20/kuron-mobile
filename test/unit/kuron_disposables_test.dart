import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhasixapp/presentation/utils/kuron_disposables.dart';

void main() {
  test('connectivity listener cancels its subscription on dispose', () async {
    final controller = StreamController<List<String>>.broadcast();
    var calls = 0;
    final listener = KuronConnectivityListener<List<String>>(
      controller.stream,
      () => calls++,
    );

    expect(listener.isListening, isTrue);
    controller.add(const ['wifi']);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    listener.dispose();
    expect(listener.isListening, isFalse);
    controller.add(const ['none']);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1, reason: 'no callback after dispose');
    controller.close();
  });

  test('navigation timers coalesce and leave zero pending timers', () {
    fakeAsync((async) {
      final timers = KuronTimerGroup();
      var fired = 0;

      timers.scheduleSingle(const Duration(seconds: 2), () => fired++);
      timers.scheduleSingle(const Duration(seconds: 2), () => fired++);
      expect(timers.activeCount, 1);

      timers.dispose();
      expect(timers.activeCount, 0);
      async.elapse(const Duration(seconds: 10));
      expect(fired, 0, reason: 'disposed timers must never fire');
    });
  });
}
