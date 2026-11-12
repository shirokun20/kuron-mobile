/// Shared fire-and-forget channel for fetch failures that adapters
/// convert into empty results (UI keeps showing empty instead of
/// crashing): list, detail, and reader fetches across scraper and REST
/// adapters.
///
/// The app registers its error log here once at startup; kuron_generic
/// never imports app code, so the app decides what (not) to record —
/// e.g. challenge/403/login exclusions stay app-side. Invocation is
/// guarded and never throws into any fetch path.
typedef FetchErrorHook = void Function(
  Object error, {
  String? sourceId,
  String? feature,
  String? url,
  int? statusCode,
});

abstract final class FetchErrorReporter {
  static FetchErrorHook? onError;

  static void notify(
    Object error, {
    required String sourceId,
    required String feature,
    String? url,
    int? statusCode,
  }) {
    final hook = onError;
    if (hook == null) return;
    try {
      hook(
        error,
        sourceId: sourceId,
        feature: feature,
        url: url,
        statusCode: statusCode,
      );
    } catch (_) {}
  }
}
