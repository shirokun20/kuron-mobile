// Bounds + cancellation coverage for [ComixRetryInterceptor] (thermal fix).
//
// A 5xx used to retry up to 10x @1.5s (~15s of radio per failed image);
// cancelled requests retried and delayed anyway. Both kept the device warm
// on image-heavy screens.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_special/src/comix/comix_network.dart';

/// Counts outbound attempts and answers every one with [status].
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.status);

  final int status;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString('boom', status);
  }

  @override
  void close({bool force = false}) {}
}

/// Cancels [token] on the first outbound attempt, then answers 500.
class _CancelOnFirstAdapter implements HttpClientAdapter {
  _CancelOnFirstAdapter(this.token);

  final CancelToken token;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    token.cancel('test-cancel');
    return ResponseBody.fromString('boom', 500);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(responseType: ResponseType.plain));
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(ComixRetryInterceptor(dio));
  return dio;
}

void main() {
  test('5xx retries are capped at maxServerErrorAttempts', () async {
    final adapter = _CountingAdapter(500);
    final dio = _dioWith(adapter);

    await expectLater(
      dio.get('https://img.test/i/1.jpg'),
      throwsA(isA<DioException>()),
    );

    // 1 initial attempt + bounded retries (was 1 + 10).
    expect(
      adapter.calls,
      1 + ComixRetryInterceptor.maxServerErrorAttempts,
    );
    expect(ComixRetryInterceptor.maxServerErrorAttempts, lessThanOrEqualTo(3));
  });

  test('pre-cancelled request performs zero retries', () async {
    final adapter = _CountingAdapter(500);
    final dio = _dioWith(adapter);
    final token = CancelToken()..cancel('gone');

    await expectLater(
      dio.get('https://img.test/i/1.jpg', cancelToken: token),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );

    // Cancelled before send: no network attempt, no retry storm.
    expect(adapter.calls, 0);
  });

  test('mid-flight cancel stops further retries', () async {
    final token = CancelToken();
    final adapter = _CancelOnFirstAdapter(token);
    final dio = _dioWith(adapter);

    await expectLater(
      dio.get('https://img.test/i/1.jpg', cancelToken: token),
      throwsA(isA<DioException>()),
    );

    // Exactly the initial attempt: the 500 that arrived with a cancelled
    // token must not schedule retry delays or refetches.
    expect(adapter.calls, 1);
  });
}
