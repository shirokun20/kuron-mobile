import '../entities/entities.dart';

// Home "Semua" combined feed: one ranked, interleaved list across the
// user's most-used sources.
//
// Implementations live in the data layer ([CombinedHomeRepositoryImpl]):
// they rank sources by usage signal (reads + weighted downloads), fetch
// page 1 of each top source in parallel, interleave round-robin with
// dedupe, and cache the result for [cacheTtl].
abstract class CombinedHomeRepository {
  /// Default page size / hard cap for one combined list.
  static const int defaultLimit = 50;

  /// Max sources contributing to one combined list.
  static const int maxSources = 5;

  /// Usage-score weight of one completed download relative to one read.
  static const int downloadWeight = 2;

  /// Freshness window for the ranked list + feed cache.
  static const Duration cacheTtl = Duration(minutes: 15);

  /// Ranked + interleaved + deduped contents from the top sources.
  ///
  /// Cold start (no reads and no downloads) returns the default source's
  /// page-1 list flagged with `isFallback = true` instead of an empty
  /// list. Sources that fail or time out are skipped; when every source
  /// fails the result is an empty (non-fallback) feed.
  Future<CombinedHomeFeed> getCombinedFeed({
    int limit = defaultLimit,
    bool forceRefresh = false,
  });
}
