import '../entities/recommendation.dart';

// Local content-based recommendation source. All data comes from the
// on-device database and download library — zero network requests.
abstract class RecommendationRepository {
  /// Top-N ranked recommendations, excluding [excludeIds].
  Future<List<Recommendation>> getRecommendations({
    int limit = 20,
    Set<String> excludeIds = const {},
    bool forceRefresh = false,
  });

  /// Content most similar to the given one (detail-screen fallback and
  /// reorder source). Empty list when the content has no stored tags.
  Future<List<Recommendation>> getSimilarContent({
    required String contentId,
    String? sourceId,
    int limit = 6,
  });

  /// Dedup bookkeeping: shown (24h window), tapped, dismissed (30 days).
  Future<void> recordShown(String contentId, {String? sourceId});
  Future<void> recordTapped(String contentId, {String? sourceId});
  Future<void> recordDismissed(String contentId, {String? sourceId});
}
