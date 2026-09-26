import 'dart:async';

import 'package:nhasixapp/core/di/service_locator.dart';

// Fire-and-forget refresh signal for recommendation sections.
// Producers (reader completion, favorite toggle, download completion,
// dismiss) never await and never fail: a closed/missing bus is a no-op.
// Consumers (RecommendedSection, SimilarContentSection) subscribe and call
// their own cubit's refresh. This keeps trigger sites decoupled from the
// home/detail cubit instances (which are per-screen factories).
class RecommendationRefreshBus {
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void requestRefresh() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }

  /// One-line trigger for producers. Never throws: an unregistered bus
  /// (unit tests, partial DI) degrades to a no-op — refresh is best-effort.
  static void requestGlobalRefresh() {
    try {
      getIt<RecommendationRefreshBus>().requestRefresh();
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }
}
