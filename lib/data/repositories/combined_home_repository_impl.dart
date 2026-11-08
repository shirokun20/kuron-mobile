import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/combined_home_repository.dart';
import '../../domain/repositories/user_data_repository.dart';

// Home "Semua" aggregation: usage-ranked round-robin interleave + TTL cache.
//
// Mirrors the [RecommendationRepositoryImpl] pattern (single recompute,
// `_cached`/`_cachedAt` invalidation) but ranks *sources* by usage signal
// instead of scoring *content*:
//   score(source) = reads(source) + downloadWeight x downloads(source)
//
// Only sources currently registered in [ContentSourceRegistry] can rank —
// a disabled (unregistered) source never contributes, even with history.
class CombinedHomeRepositoryImpl implements CombinedHomeRepository {
  CombinedHomeRepositoryImpl({
    required UserDataRepository userDataRepository,
    required ContentSourceRegistry contentSourceRegistry,
    required this._logger,
    DateTime Function()? clock,
  })  : _userData = userDataRepository,
        _registry = contentSourceRegistry,
        _clock = clock ?? DateTime.now;

  final UserDataRepository _userData;
  final ContentSourceRegistry _registry;
  final Logger _logger;
  final DateTime Function() _clock;

  /// Per-source fetch budget: one slow source must not stall the feed.
  static const fetchTimeout = Duration(seconds: 20);

  CombinedHomeFeed? _cached;
  DateTime? _cachedAt;

  @override
  Future<CombinedHomeFeed> getCombinedFeed({
    int limit = CombinedHomeRepository.defaultLimit,
    bool forceRefresh = false,
  }) async {
    final now = _clock();
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < CombinedHomeRepository.cacheTtl) {
      return _slice(_cached!, limit);
    }

    final feed = await _buildFeed(now);
    _cached = feed;
    _cachedAt = now;
    return _slice(feed, limit);
  }

  CombinedHomeFeed _slice(CombinedHomeFeed feed, int limit) {
    final effective = limit.clamp(1, CombinedHomeRepository.defaultLimit);
    if (feed.contents.length <= effective) return feed;
    return feed.copyWith(contents: feed.contents.take(effective).toList());
  }

  Future<CombinedHomeFeed> _buildFeed(DateTime now) async {
    final installed = _registry.sourceIds.toSet();
    final reads = await _counts(_userData.getReadCountsBySource, 'reads');
    final downloads =
        await _counts(_userData.getDownloadCountsBySource, 'downloads');

    final scores = <String, int>{};
    for (final entry in {...reads, ...downloads}.keys) {
      if (!installed.contains(entry)) continue; // disabled source: no rank
      final score = (reads[entry] ?? 0) +
          CombinedHomeRepository.downloadWeight * (downloads[entry] ?? 0);
      if (score > 0) scores[entry] = score;
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    final topIds =
        ranked.take(CombinedHomeRepository.maxSources).map((e) => e.key);

    if (topIds.isEmpty) return _coldStartFeed();

    final lists = await Future.wait(
      topIds.map((id) => _fetchPage(id)),
      eagerError: false,
    );

    final perSource = <String, List<Content>>{};
    for (var i = 0; i < topIds.length; i++) {
      if (lists[i].isNotEmpty) perSource[topIds.elementAt(i)] = lists[i];
    }
    if (perSource.isEmpty) {
      _logger.w('CombinedHome: every ranked source failed; empty feed');
      return CombinedHomeFeed.empty();
    }

    final orderedIds = topIds.where(perSource.containsKey).toList();
    final contents = _interleave(
      orderedIds.map((id) => perSource[id]!).toList(),
      CombinedHomeRepository.defaultLimit,
    );
    _logger.i('CombinedHome: ranked=$ranked '
        'contributors=$orderedIds items=${contents.length}');
    return CombinedHomeFeed(contents: contents, sourceIds: orderedIds);
  }

  /// Cold start: no usage signals — page 1 of the default (current, else
  /// first registered) source, flagged so the UI can hint accordingly.
  Future<CombinedHomeFeed> _coldStartFeed() async {
    final defaultId =
        _registry.currentSource?.id ?? _registry.sourceIds.firstOrNull;
    if (defaultId == null) {
      _logger.i('CombinedHome: cold start with no registered source');
      return CombinedHomeFeed.empty();
    }
    final items = await _fetchPage(defaultId);
    _logger.i('CombinedHome: cold start fallback to $defaultId '
        '(${items.length} items)');
    return CombinedHomeFeed(
      contents: items
          .take(CombinedHomeRepository.defaultLimit)
          .toList(growable: false),
      sourceIds: items.isEmpty ? const [] : [defaultId],
      isFallback: true,
      fallbackSourceId: defaultId,
    );
  }

  Future<Map<String, int>> _counts(
    Future<Map<String, int>> Function() read,
    String label,
  ) async {
    try {
      return await read();
    } catch (e) {
      // One broken signal must not kill the whole feed — fall back to the
      // other signal (or cold start when both are broken).
      _logger.w('CombinedHome: $label counts unavailable: $e');
      return const {};
    }
  }

  Future<List<Content>> _fetchPage(String sourceId) async {
    final source = _registry.getSource(sourceId);
    if (source == null) return const []; // unregistered mid-flight
    try {
      final result =
          await source.getList(page: 1).timeout(fetchTimeout);
      return result.contents;
    } catch (e) {
      // Skip failing sources; the remaining mix still renders.
      _logger.w('CombinedHome: skipped failing source $sourceId: $e');
      return const [];
    }
  }

  /// Round-robin across per-source page-1 lists in rank order (one item per
  /// source per turn), dropping duplicate content ids (first wins).
  static List<Content> _interleave(
    List<List<Content>> perSource,
    int cap,
  ) {
    final out = <Content>[];
    final seenIds = <String>{};
    var index = 0;
    var progressed = true;
    while (out.length < cap && progressed) {
      progressed = false;
      for (final list in perSource) {
        if (out.length >= cap) break;
        if (index >= list.length) continue;
        progressed = true;
        final content = list[index];
        if (seenIds.add(content.id)) out.add(content);
      }
      index++;
    }
    return out;
  }
}
