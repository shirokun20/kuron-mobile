import 'package:logger/logger.dart';

import '../../domain/entities/content_tag.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/repositories/content_repository.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../../domain/repositories/user_data_repository.dart';
import '../../domain/value_objects/value_objects.dart';
import '../datasources/local/metadata_tag_scanner.dart';
import 'package:kuron_core/kuron_core.dart'
    hide ContentListResult, PopularTimeframe;

// Content-based recommendation engine. Scoring is fully local (SQLite +
// download library); only candidate *discovery* may hit the network via the
// same related-content API the detail screen already uses.
class RecommendationRepositoryImpl implements RecommendationRepository {
  RecommendationRepositoryImpl({
    required ContentRepository contentRepository,
    required UserDataRepository userDataRepository,
    required Logger logger,
    Future<List<MetadataSeed>> Function()? loadMetadataSeeds,
  })  : _content = contentRepository,
        _userData = userDataRepository,
        _logger = logger,
        _loadMetadataSeeds = loadMetadataSeeds ?? _defaultMetadataSeeds;

  final ContentRepository _content;
  final UserDataRepository _userData;
  final Logger _logger;
  final Future<List<MetadataSeed>> Function() _loadMetadataSeeds;

  static const seedWindow = Duration(days: 30);
  static const shownWindow = Duration(hours: 24);
  static const dismissedWindow = Duration(days: 30);
  static const cacheTtl = Duration(hours: 1);
  static const maxSeeds = 200;
  static const relatedSeeds = 3;
  static const relatedPerSeed = 10;
  static const favoriteBoostValue = 2.0;
  static const sourceBoostValue = 1.2;
  static const downloadCompletionWeight = 0.7;
  static const explorationFraction = 0.2;

  /// Max detail fetches per recompute for tag backfill (old rows saved
  /// before tag seeding existed). Bounded so a cold engine never stalls
  /// home on network.
  static const backfillMaxDetails = 8;

  List<Recommendation>? _cached;
  DateTime? _cachedAt;

  static Future<List<MetadataSeed>> _defaultMetadataSeeds() async {
    final root = await MetadataTagScanner.resolveLibraryRoot();
    if (root == null) return [];
    return MetadataTagScanner(libraryRoot: root).scan();
  }

  // ---------- public API ----------

  @override
  Future<List<Recommendation>> getRecommendations({
    int limit = 20,
    Set<String> excludeIds = const {},
    bool forceRefresh = false,
  }) async {
    try {
      final now = DateTime.now();
      if (!forceRefresh &&
          _cached != null &&
          _cachedAt != null &&
          now.difference(_cachedAt!) < cacheTtl) {
        return _cached!.take(limit).toList();
      }

      final seeds = await _gatherSeeds(now);
      if (seeds.isEmpty) return []; // cold start → UI placeholder

      final blocked = await _blockedIds(now, excludeIds);
      final readIds = await _readIds();

      // Discovery pool: related content of the strongest seeds (scored).
      // Strongest seed of EACH source first (multi-source readers keep
      // multi-source candidates), then the next-strongest overall so
      // same-source seeds with different tastes still get a fetch.
      final pool = <String, Content>{};
      final rankedSeeds = [...seeds]
        ..sort((a, b) => b.priorWeight.compareTo(a.priorWeight));
      final fetchSeeds = <_Seed>[];
      final seenSources = <String>{};
      for (final seed in rankedSeeds) {
        if (fetchSeeds.length >= relatedSeeds) break;
        if (seenSources.add(seed.sourceId)) fetchSeeds.add(seed);
      }
      for (final seed in rankedSeeds) {
        if (fetchSeeds.length >= relatedSeeds) break;
        if (!fetchSeeds.contains(seed)) fetchSeeds.add(seed);
      }
      for (final seed in fetchSeeds) {
        try {
          final related = await _content.getRelatedContent(
            contentId: ContentId.fromString(seed.id),
            limit: relatedPerSeed,
          );
          for (final c in related) {
            pool.putIfAbsent(_key(c.sourceId, c.id), () => c);
          }
        } catch (e) {
          // Sources without a related implementation throw — skip the seed.
          _logger.d('Recommendations: no related for ${seed.id}: $e');
        }
      }

      // Exploration pool (never scored): owned-but-unread downloads first,
      // then related items beyond the top seeds.
      final explorePool = <String, Content>{};
      final metaSeeds = await _loadMetadataSeeds();
      for (final m in metaSeeds) {
        if (readIds.contains(m.contentId)) continue;
        explorePool.putIfAbsent(
            _key(m.sourceId, m.contentId), () => _contentFromSeed(m));
      }
      for (final seed in rankedSeeds.skip(relatedSeeds)) {
        try {
          final related = await _content.getRelatedContent(
            contentId: ContentId.fromString(seed.id),
            limit: relatedPerSeed,
          );
          for (final c in related) {
            final k = _key(c.sourceId, c.id);
            if (!pool.containsKey(k)) explorePool.putIfAbsent(k, () => c);
          }
        } catch (_) {
          // Same skip rationale as above.
        }
      }

      // Last resort: popular from the active source (affinity-based, not
      // random). Only fills what related + downloads could not.
      if (pool.length + explorePool.length < limit) {
        try {
          final popular = await _content.getPopularContent(
            timeframe: PopularTimeframe.week,
            page: 1,
          );
          for (final c in popular.contents) {
            if (pool.length + explorePool.length >= limit * 2) break;
            final k = _key(c.sourceId, c.id);
            if (!pool.containsKey(k)) explorePool.putIfAbsent(k, () => c);
          }
        } catch (e) {
          _logger.d('Recommendations: popular fallback failed: $e');
        }
      }

      for (final k in [...pool.keys]) {
        final c = pool[k]!;
        if (blocked.contains(c.id) || readIds.contains(c.id)) {
          pool.remove(k);
        }
      }
      for (final k in [...explorePool.keys]) {
        final c = explorePool[k]!;
        if (blocked.contains(c.id) ||
            readIds.contains(c.id) ||
            pool.containsKey(k)) {
          explorePool.remove(k);
        }
      }

      final exploreQuota =
          (limit * explorationFraction).ceil().clamp(0, limit);
      final rankedCount = (limit - exploreQuota).clamp(0, limit);

      final scored = <_Scored>[];
      for (final candidate in pool.values) {
        final tags = _namesOf(candidate);
        if (tags.isEmpty) continue;
        double best = 0;
        _Seed? contributor;
        for (final seed in seeds) {
          final j = jaccardSimilarity(seed.tags, tags);
          if (j <= 0) continue;
          final w = j *
              seed.priorWeight *
              (seed.sourceId == candidate.sourceId ? sourceBoostValue : 1.0);
          if (w > best) {
            best = w;
            contributor = seed;
          }
        }
        if (contributor != null) {
          scored.add(_Scored(candidate, best, contributor));
        }
      }
      scored.sort((a, b) => b.score.compareTo(a.score));

      final result = <Recommendation>[];
      for (final s in scored.take(rankedCount)) {
        result.add(_toRecommendation(s.candidate, s.score, s.contributor));
      }
      // Exploration fills its 20% quota, PLUS any slots the ranked pool
      // could not fill — a thin ranked pool must never mean a thin list.
      final remaining = limit - result.length;
      for (final c in explorePool.values.take(remaining)) {
        result.add(Recommendation(
          contentId: c.id,
          sourceId: c.sourceId,
          score: 0,
          reason: 'Explore: ${c.title}',
          contributorTitle: c.title,
          contributorRelation: RecommendationRelation.similar,
          content: c,
        ));
      }

      _cached = result;
      _cachedAt = now;
      return result;
    } catch (e, stackTrace) {
      _logger.e('Recommendations failed', error: e, stackTrace: stackTrace);
      return _cached ?? [];
    }
  }

  @override
  Future<List<Recommendation>> getSimilarContent({
    required String contentId,
    String? sourceId,
    int limit = 6,
  }) async {
    try {
      final seedTags =
          await _userData.getTagNamesForContent(contentId, sourceId: sourceId);
      List<Content> related = [];
      try {
        related = await _content.getRelatedContent(
          contentId: ContentId.fromString(contentId),
          limit: 10,
        );
      } catch (e) {
        _logger.d('Similar: no related for $contentId: $e');
      }
      if (related.isEmpty) return [];

      final now = DateTime.now();
      final blocked = await _blockedIds(now, {});
      final readIds = await _readIds();

      final scored = <_Scored>[];
      for (final c in related) {
        if (c.id == contentId ||
            blocked.contains(c.id) ||
            readIds.contains(c.id)) {
          continue;
        }
        final tags = _namesOf(c);
        final score = seedTags.isEmpty
            ? 0.0
            : jaccardSimilarity(seedTags, tags) *
                (sourceId != null && c.sourceId == sourceId
                    ? sourceBoostValue
                    : 1.0);
        scored.add(_Scored(
            c,
            score,
            _Seed(
              id: contentId,
              sourceId: sourceId ?? c.sourceId,
              title: '',
              tags: seedTags,
              priorWeight: 1,
              relation: RecommendationRelation.similar,
            )));
      }
      // Stable order when untagged: keep server order instead of zeros ties.
      if (seedTags.isNotEmpty) {
        scored.sort((a, b) => b.score.compareTo(a.score));
      }
      return scored.take(limit).map((s) => Recommendation(
            contentId: s.candidate.id,
            sourceId: s.candidate.sourceId,
            score: s.score,
            reason: 'Similar to this',
            contributorTitle: '',
            contributorRelation: RecommendationRelation.similar,
            content: s.candidate,
          )).toList();
    } catch (e, stackTrace) {
      _logger.e('Similar content failed', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<void> recordShown(String contentId, {String? sourceId}) =>
      _userData.recordRecommendationShown(contentId, sourceId: sourceId);

  @override
  Future<void> recordTapped(String contentId, {String? sourceId}) =>
      _userData.recordRecommendationTapped(contentId, sourceId: sourceId);

  @override
  Future<void> recordDismissed(String contentId, {String? sourceId}) async {
    _cached = null; // dismissed items must vanish immediately
    await _userData.recordRecommendationDismissed(contentId,
        sourceId: sourceId);
  }

  // ---------- seeds ----------

  /// Lazy tag backfill for rows saved before tag seeding existed.
  /// Fetches the detail once, writes the tags through (so the next
  /// recompute is local), and returns the tag names. Bounded by
  /// [backfillMaxDetails] per recompute; failures yield an empty set.
  int _backfillUsed = 0;

  Future<Set<String>> _tagsWithBackfill({
    required String id,
    required String sourceId,
    required String origin,
  }) async {
    final stored =
        await _userData.getTagNamesForContent(id, sourceId: sourceId);
    if (stored.isNotEmpty) return stored;
    if (_backfillUsed >= backfillMaxDetails) return {};
    _backfillUsed++;
    try {
      final detail = await _content.getContentDetail(
        ContentId.fromString(id),
        sourceId: sourceId,
      );
      final seeds = ContentTag.seedsFromContent(
        content: detail,
        contentId: id,
        sourceId: sourceId,
        origin: origin,
      );
      if (seeds.isEmpty) return {};
      try {
        await _userData.saveContentTags(seeds);
      } catch (e) {
        _logger.d('Recommendations: backfill write failed for $id: $e');
      }
      return {for (final s in seeds) s.name};
    } catch (e) {
      _logger.d('Recommendations: backfill fetch failed for $id: $e');
      return {};
    }
  }

  Future<List<_Seed>> _gatherSeeds(DateTime now) async {
    final seeds = <_Seed>[];
    final cutoff = now.subtract(seedWindow);
    _backfillUsed = 0;

    // Recent reads (paged until rows get older than the window).
    var page = 1;
    outer:
    while (seeds.length < maxSeeds) {
      final rows = await _userData.getHistory(page: page, limit: 50);
      if (rows.isEmpty) break;
      for (final h in rows) {
        if (h.lastViewed.isBefore(cutoff)) break outer;
        if (h.progress <= 0) continue; // opened but unread → not a signal
        final tags = await _tagsWithBackfill(
          id: h.contentId,
          sourceId: h.sourceId,
          origin: 'history',
        );
        if (tags.isEmpty) continue;
        seeds.add(_Seed(
          id: h.contentId,
          sourceId: h.sourceId,
          title: h.title ?? h.contentId,
          tags: tags,
          priorWeight: completionWeight(h.progress) *
              recencyDecay(now.difference(h.lastViewed)),
          relation: RecommendationRelation.read,
        ));
        if (seeds.length >= maxSeeds) break;
      }
      page++;
    }

    // Favorites: timeless long-term signal (no recency decay).
    try {
      final favs = await _userData.getAllFavoritesForExport();
      for (final f in favs) {
        if (seeds.length >= maxSeeds) break;
        final id = f['id']?.toString() ?? '';
        final sid = f['source_id']?.toString() ?? 'nhentai';
        if (id.isEmpty) continue;
        if (seeds.any((s) => s.id == id && s.sourceId == sid)) continue;
        final tags = await _tagsWithBackfill(
          id: id,
          sourceId: sid,
          origin: 'favorite',
        );
        if (tags.isEmpty) continue;
        seeds.add(_Seed(
          id: id,
          sourceId: sid,
          title: f['title']?.toString() ?? id,
          tags: tags,
          priorWeight: 1.0 * favoriteBoostValue,
          relation: RecommendationRelation.favorite,
        ));
      }
    } catch (e) {
      _logger.d('Recommendations: favorites unavailable: $e');
    }

    // Tagged downloads: ownership interest with fixed completion weight.
    try {
      final meta = await _loadMetadataSeeds();
      meta.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      for (final m in meta) {
        if (seeds.length >= maxSeeds) break;
        if (m.downloadedAt.isBefore(cutoff)) continue;
        if (seeds.any((s) => s.id == m.contentId && s.sourceId == m.sourceId)) {
          continue;
        }
        final tags = {for (final t in m.tags) t.name};
        if (tags.isEmpty) continue;
        seeds.add(_Seed(
          id: m.contentId,
          sourceId: m.sourceId,
          title: m.title ?? m.contentId,
          tags: tags,
          priorWeight:
              downloadCompletionWeight * recencyDecay(now.difference(m.downloadedAt)),
          relation: RecommendationRelation.download,
        ));
      }
    } catch (e) {
      _logger.d('Recommendations: metadata seeds unavailable: $e');
    }

    return seeds;
  }

  /// Ids of everything ever read (any progress > 0), for exclusion.
  Future<Set<String>> _readIds() async {
    final ids = <String>{};
    var page = 1;
    while (true) {
      final rows = await _userData.getHistory(page: page, limit: 200);
      if (rows.isEmpty) break;
      for (final h in rows) {
        if (h.progress > 0) ids.add(h.contentId);
      }
      page++;
    }
    return ids;
  }

  /// Shown (24h) + dismissed (30d) ids, plus caller-supplied excludes.
  Future<Set<String>> _blockedIds(DateTime now, Set<String> extra) async {
    final blocked = {...extra};
    try {
      final rows = await _userData.getRecommendationHistoryRows();
      for (final r in rows) {
        final id = r['content_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final shownAt = r['shown_at'] as int?;
        if (shownAt != null &&
            now.millisecondsSinceEpoch - shownAt <
                shownWindow.inMilliseconds) {
          blocked.add(id);
        }
        if ((r['dismissed'] as int? ?? 0) == 1) {
          final dismissedAt = r['dismissed_at'] as int?;
          if (dismissedAt != null &&
              now.millisecondsSinceEpoch - dismissedAt <
                  dismissedWindow.inMilliseconds) {
            blocked.add(id);
          }
        }
      }
    } catch (e) {
      _logger.d('Recommendations: history rows unavailable: $e');
    }
    return blocked;
  }

  // ---------- pure helpers (unit-tested) ----------

  static double jaccardSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    if (inter == 0) return 0;
    return inter / a.union(b).length;
  }

  static double completionWeight(double progress) {
    if (progress <= 0) return 0;
    return (0.3 + 0.7 * progress.clamp(0.0, 1.0));
  }

  static double recencyDecay(Duration age) {
    final days = age.inHours / 24.0;
    return 1.0 / (1.0 + (days < 0 ? 0 : days));
  }

  static String _key(String sourceId, String id) => '$sourceId|$id';

  static Set<String> _namesOf(Content c) => {
        for (final t in c.tags) t.name.trim().toLowerCase(),
      }..remove('');

  Recommendation _toRecommendation(
      Content candidate, double score, _Seed contributor) {
    final prefix = switch (contributor.relation) {
      RecommendationRelation.favorite => 'Because you favorited',
      RecommendationRelation.download => 'From your downloads',
      _ => 'Because you read',
    };
    return Recommendation(
      contentId: candidate.id,
      sourceId: candidate.sourceId,
      score: score,
      reason: '$prefix ${contributor.title}',
      contributorTitle: contributor.title,
      contributorRelation: contributor.relation,
      content: candidate,
    );
  }

  static Content _contentFromSeed(MetadataSeed m) {
    final tags = <Tag>[];
    final artists = <String>[];
    final characters = <String>[];
    final parodies = <String>[];
    final groups = <String>[];
    String language = '';
    for (final t in m.tags) {
      tags.add(Tag(id: 0, name: t.name, type: t.type, count: 0));
      switch (t.type) {
        case 'artist':
          artists.add(t.name);
        case 'character':
          characters.add(t.name);
        case 'parody':
          parodies.add(t.name);
        case 'group':
          groups.add(t.name);
        case 'language':
          if (language.isEmpty) language = t.name;
      }
    }
    return Content(
      id: m.contentId,
      sourceId: m.sourceId,
      title: m.title ?? m.contentId,
      coverUrl: m.coverUrl ?? '',
      tags: tags,
      artists: artists,
      characters: characters,
      parodies: parodies,
      groups: groups,
      language: language,
      pageCount: 0,
      imageUrls: const [],
      uploadDate: m.downloadedAt,
    );
  }
}

class _Seed {
  _Seed({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.tags,
    required this.priorWeight,
    required this.relation,
  });

  final String id;
  final String sourceId;
  final String title;
  final Set<String> tags;
  final double priorWeight;
  final String relation;
}

class _Scored {
  _Scored(this.candidate, this.score, this.contributor);

  final Content candidate;
  final double score;
  final _Seed contributor;
}
