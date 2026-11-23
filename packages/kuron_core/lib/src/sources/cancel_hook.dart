/// Pure-Dart cancellation hook used across content-source boundaries.
///
/// A caller that can supersede an in-flight fetch passes a registration
/// function; the fetching side creates its own cancellation primitive and
/// hands the abort callback back:
///
/// ```dart
/// source.search(filter, onCancel: (abort) => _abortPrevious = abort);
/// // later, when a newer fetch starts:
/// _abortPrevious?.call();
/// ```
///
/// Bridges to Dio `CancelToken` in adapter packages without leaking
/// `package:dio` into `kuron_core`.
typedef OnCancelRegister = void Function(void Function() onCancel);
