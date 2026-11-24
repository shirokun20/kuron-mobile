// Single, shared bridge from the pure-Dart [OnCancelRegister] hook to a
// Dio [CancelToken].
//
// Previously every source boundary allocated its own token from the same hook
// (`ContentRepositoryImpl._bridgeOnCancel` for the request-deduplication
// waiter *and* `GenericHttpSource._bridgeCancelToken` for the adapter call),
// doubling allocations and listeners per fetch. All boundaries must use this
// single helper instead so one hook registration yields exactly one token
// per fetch — invoking the hook cancels every token bridged from it.
library;

import 'package:dio/dio.dart';
import 'package:kuron_core/kuron_core.dart';

/// Bridges [onCancel] to a Dio [CancelToken].
///
/// Returns null when no hook is registered, so adapter calls stay token-free.
/// When the caller later invokes the registered callback, the token is
/// cancelled exactly once.
CancelToken? bridgeOnCancel(
  OnCancelRegister? onCancel, {
  String reason = 'Cancelled by caller',
}) {
  if (onCancel == null) return null;
  final token = CancelToken();
  onCancel(() {
    if (!token.isCancelled) token.cancel(reason);
  });
  return token;
}
