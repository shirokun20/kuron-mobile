// Single CancelToken bridge shared by every source boundary.
//
// Guards issue #86: repository and adapter must build their tokens from the
// same helper so one [OnCancelRegister] hook yields exactly one token per
// fetch, and invoking the hook cancels every token bridged from it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kuron_generic/kuron_generic.dart';
import 'package:test/test.dart';

void main() {
  group('bridgeOnCancel', () {
    test('returns null without a hook so calls stay token-free', () {
      expect(bridgeOnCancel(null), isNull);
    });

    test('invoking the hook cancels the bridged token', () {
      void Function()? abort;
      final token = bridgeOnCancel((cb) => abort = cb);

      expect(token, isNotNull);
      expect(token!.isCancelled, isFalse);

      abort!();
      expect(token.isCancelled, isTrue);
    });

    test('repeat hook invocation is a safe no-op', () {
      void Function()? abort;
      final token = bridgeOnCancel((cb) => abort = cb)!;

      abort!();
      expect(token.isCancelled, isTrue);
      abort!();
      expect(token.isCancelled, isTrue);
    });

    test('one hook cancels tokens bridged for repository and adapter', () {
      final callbacks = <void Function()>[];
      void onCancel(void Function() cb) => callbacks.add(cb);

      // Mirrors ContentRepositoryImpl (dedup waiter) + GenericHttpSource
      // (adapter call) bridging the same hook via the single helper.
      final repositoryToken = bridgeOnCancel(onCancel);
      final adapterToken = bridgeOnCancel(onCancel);

      expect(repositoryToken, isNotNull);
      expect(adapterToken, isNotNull);
      expect(identical(repositoryToken, adapterToken), isFalse);

      for (final cb in callbacks) {
        cb();
      }

      expect(repositoryToken!.isCancelled, isTrue);
      expect(adapterToken!.isCancelled, isTrue);
    });

    test('bridged token aborts an in-flight Dio request as cancel', () async {
      void Function()? abort;
      final token = bridgeOnCancel((cb) => abort = cb)!;
      final dio = Dio(
        BaseOptions(baseUrl: 'https://bridge.test'),
      )..httpClientAdapter = _NeverAdapter();

      final future = dio.get<String>(
        '/slow',
        cancelToken: token,
      );
      abort!();

      await expectLater(
        future,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
    });
  });
}

class _NeverAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Parks until the caller cancels; the CancelToken wires into
    // Dio's cancellation future automatically.
    final completer = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'Cancelled by caller',
          ),
        );
      }
    });
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}
