import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart'
    hide ContentListResult, PopularTimeframe;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/datasources/local/metadata_tag_scanner.dart';
import 'package:nhasixapp/data/repositories/recommendation_repository_impl.dart';
import 'package:nhasixapp/domain/entities/content_tag.dart';
import 'package:nhasixapp/domain/entities/history.dart';
import 'package:nhasixapp/domain/entities/recommendation.dart';
import 'package:nhasixapp/domain/repositories/content_repository.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/value_objects/value_objects.dart';

class _MockContentRepo extends Mock implements ContentRepository {}

class _MockUserData extends Mock implements UserDataRepository {}

Content _content(
  String id, {
  String sourceId = 'nhentai',
  List<String> tagNames = const [],
}) {
  return Content(
    id: id,
    sourceId: sourceId,
    title: 'Title $id',
    coverUrl: 'http://cover/$id',
    tags: [
      for (var i = 0; i < tagNames.length; i++)
        Tag(id: i, name: tagNames[i], type: 'tag', count: 1),
    ],
    artists: const [],
    characters: const [],
    parodies: const [],
    groups: const [],
    language: 'english',
    pageCount: 10,
    imageUrls: const [],
    uploadDate: DateTime(2026, 1, 1),
  );
}

History _history(
  String id, {
  required DateTime lastViewed,
  int lastPage = 10,
  int totalPages = 10,
  String sourceId = 'nhentai',
}) {
  return History(
    contentId: id,
    sourceId: sourceId,
    lastViewed: lastViewed,
    lastPage: lastPage,
    totalPages: totalPages,
    title: 'Hist $id',
  );
}

void main() {
  late _MockContentRepo contentRepo;
  late _MockUserData userData;

  setUpAll(() {
    registerFallbackValue(ContentId.fromString('x'));
    registerFallbackValue(PopularTimeframe.week);
  });

  setUp(() {
    contentRepo = _MockContentRepo();
    userData = _MockUserData();
    when(() => userData.getRecommendationHistoryRows())
        .thenAnswer((_) async => []);
    when(() => userData.getAllFavoritesForExport())
        .thenAnswer((_) async => []);
    when(() => userData.recordRecommendationShown(any(),
            sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async {});
    when(() => userData.recordRecommendationTapped(any(),
            sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async {});
    when(() => userData.recordRecommendationDismissed(any(),
            sourceId: any(named: 'sourceId')))
        .thenAnswer((_) async {});
  });

  RecommendationRepositoryImpl engineForTest({
    List<MetadataSeed> metaSeeds = const [],
  }) {
    return RecommendationRepositoryImpl(
      contentRepository: contentRepo,
      userDataRepository: userData,
      logger: Logger(level: Level.off),
      loadMetadataSeeds: () async => metaSeeds,
    );
  }

  MetadataSeed metaSeedForTest(String id, Set<String> tagNames) {
    return MetadataSeed(
      contentId: id,
      sourceId: 'nhentai',
      downloadedAt: DateTime.now(),
      tags: [
        for (final name in tagNames)
          ContentTag(
            contentId: id,
            sourceId: 'nhentai',
            name: name,
            type: 'tag',
            origin: 'metadata',
          ),
      ],
      title: 'DL $id',
    );
  }

  void stubHistoryForTest(List<History> rows, Map<String, Set<String>> tags) {
    when(() => userData.getHistory(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        )).thenAnswer((inv) async {
      final page = inv.namedArguments[#page] as int? ?? 1;
      return page == 1 ? rows : <History>[];
    });
    when(() => userData.getTagNamesForContent(any(),
            sourceId: any(named: 'sourceId')))
        .thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      return tags[id] ?? <String>{};
    });
  }

  group('pure helpers', () {
    test('9.2 jaccard edge cases', () {
      expect(
          RecommendationRepositoryImpl.jaccardSimilarity({}, {'a'}), 0);
      expect(
          RecommendationRepositoryImpl.jaccardSimilarity({'a'}, {'a'}), 1);
      expect(
          RecommendationRepositoryImpl.jaccardSimilarity(
              {'a', 'b'}, {'c', 'd'}),
          0);
      expect(
          RecommendationRepositoryImpl.jaccardSimilarity(
              {'a', 'b', 'c'}, {'b', 'c', 'd'}),
          0.5);
    });

    test('9.3 recency decay', () {
      expect(RecommendationRepositoryImpl.recencyDecay(Duration.zero), 1);
      expect(
        RecommendationRepositoryImpl.recencyDecay(const Duration(days: 1)),
        closeTo(0.5, 1e-9),
      );
      expect(
        RecommendationRepositoryImpl.recencyDecay(const Duration(days: 7)),
        closeTo(1 / 8, 1e-9),
      );
      expect(
        RecommendationRepositoryImpl.recencyDecay(const Duration(days: 30)),
        closeTo(1 / 31, 1e-9),
      );
      final year =
          RecommendationRepositoryImpl.recencyDecay(const Duration(days: 365));
      expect(year, lessThan(0.01));
      expect(
          RecommendationRepositoryImpl.recencyDecay(const Duration(days: 7)),
          greaterThan(RecommendationRepositoryImpl.recencyDecay(
              const Duration(days: 30))));
    });

    test('completion weight excludes zero, rewards finishers', () {
      expect(RecommendationRepositoryImpl.completionWeight(0), 0);
      expect(RecommendationRepositoryImpl.completionWeight(1.0), 1.0);
      expect(
        RecommendationRepositoryImpl.completionWeight(1.0),
        greaterThan(RecommendationRepositoryImpl.completionWeight(0.1)),
      );
    });
  });

  group('9.1 scoring from similar tags', () {
    test('higher overlap outranks unrelated content', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action', 'fantasy', 'manhwa'},
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('b', tagNames: ['action', 'fantasy', 'romance']),
            _content('c', tagNames: ['horror', 'slice of life']),
          ]);

      final result = await engineForTest().getRecommendations(limit: 10);

      expect(result.map((r) => r.contentId), ['b']);
      expect(result.first.score, greaterThan(0));
      expect(result.first.contributorRelation, 'read');
    });

    test('recent read outranks month-old read (recency decay)', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [
          _history('fresh', lastViewed: now.subtract(const Duration(days: 1))),
          _history('old',
              lastViewed: now.subtract(const Duration(days: 30))),
        ],
        {
          'fresh': {'action'},
          'old': {'romance'},
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((inv) async {
        final id =
            (inv.namedArguments[#contentId] as ContentId).value;
        if (id == 'fresh') {
          return [_content('cand-fresh', tagNames: ['action'])];
        }
        return [_content('cand-old', tagNames: ['romance'])];
      });

      final result = await engineForTest().getRecommendations(limit: 10);

      expect(result.first.contentId, 'cand-fresh');
    });

    test('favorited contributor counts 2x (reason names the favorite)',
        () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('read', lastViewed: now)],
        {
          'read': {'action'},
          'fav': {'action'},
        },
      );
      when(() => userData.getAllFavoritesForExport()).thenAnswer(
        (_) async => [
          {'id': 'fav', 'source_id': 'nhentai', 'title': 'Fav Title'},
        ],
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('cand', tagNames: ['action']),
          ]);

      final result = await engineForTest().getRecommendations(limit: 10);

      expect(result.single.contributorRelation, 'favorite');
      expect(result.single.contributorTitle, 'Fav Title');
      expect(result.single.reason, contains('favorited'));
    });
  });

  group('9.4 deduplication', () {
    test('excludes read, shown, dismissed and caller-supplied ids',
        () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [
          _history('seed', lastViewed: now),
          _history('read-cand', lastViewed: now.subtract(
            const Duration(days: 60),
          )),
        ],
        {
          'seed': {'action'},
        },
      );
      when(() => userData.getRecommendationHistoryRows()).thenAnswer(
        (_) async => [
          {
            'content_id': 'shown-cand',
            'source_id': 'nhentai',
            'shown_at': now.millisecondsSinceEpoch,
            'tapped_at': null,
            'dismissed': 0,
            'dismissed_at': null,
          },
          {
            'content_id': 'dismissed-cand',
            'source_id': 'nhentai',
            'shown_at': null,
            'tapped_at': null,
            'dismissed': 1,
            'dismissed_at': now.millisecondsSinceEpoch,
          },
        ],
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('read-cand', tagNames: ['action']),
            _content('shown-cand', tagNames: ['action']),
            _content('dismissed-cand', tagNames: ['action']),
            _content('home-cand', tagNames: ['action']),
            _content('good', tagNames: ['action']),
          ]);

      final result = await engineForTest()
          .getRecommendations(limit: 10, excludeIds: {'home-cand'});

      expect(result.map((r) => r.contentId), ['good']);
    });
  });

  group('9.5 exploration mix', () {
    test('20% comes unscored from the download pool, no extra fetches',
        () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'},
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            for (var i = 0; i < 8; i++)
              _content('ranked-$i', tagNames: ['action']),
          ]);

      final result = await engineForTest(metaSeeds: [
        metaSeedForTest('dl-1', {'comedy'}),
        metaSeedForTest('dl-2', {'drama'}),
      ]).getRecommendations(limit: 10);

      // 10 slots → 2 explore (20%), 8 ranked.
      expect(result.length, 10);
      final explore =
          result.where((r) => r.contributorRelation == 'similar').toList();
      final ranked =
          result.where((r) => r.contributorRelation != 'similar').toList();
      expect(explore.map((r) => r.contentId), containsAll(['dl-1', 'dl-2']));
      expect(explore.every((r) => r.score == 0), isTrue);
      expect(ranked.length, 8);
      // Related fetches happen only for seeds (history + the 2 downloads)
      // — the exploration items themselves triggered zero extra fetches.
      final requested = verify(() => contentRepo.getRelatedContent(
            contentId: captureAny(named: 'contentId'),
            limit: any(named: 'limit'),
          )).captured;
      expect(
        {for (final c in requested) (c as ContentId).value},
        {'a', 'dl-1', 'dl-2'},
      );
    });
  });

  group('popular fallback fills thin pools', () {
    test('active-source popular completes the list as explore', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'}
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);
      when(() => contentRepo.getPopularContent(
            timeframe: any(named: 'timeframe'),
            page: any(named: 'page'),
          )).thenAnswer((_) async => ContentListResult(
            contents: [
              for (var i = 0; i < 6; i++)
                _content('pop-$i', tagNames: ['comedy']),
            ],
            currentPage: 1,
            totalPages: 1,
            totalCount: 6,
          ));

      final result = await engineForTest().getRecommendations(limit: 10);

      // No ranked candidates → exploration fills every remaining slot.
      expect(
        result.map((r) => r.contentId),
        [for (var i = 0; i < 6; i++) 'pop-$i'],
      );
      expect(result.every((r) => r.score == 0), isTrue);
      expect(
        result.every((r) =>
            r.contributorRelation == RecommendationRelation.similar),
        isTrue,
      );
    });

    test('related fetched per distinct source, not global top seeds', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [
          _history('a', lastViewed: now),
          _history('b', lastViewed: now, sourceId: 'komik'),
          _history('c', lastViewed: now.subtract(const Duration(days: 7))),
        ],
        {
          'a': {'action'},
          'b': {'fantasy'},
          'c': {'action'},
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((inv) async {
        final id =
            (inv.namedArguments[#contentId] as ContentId).value;
        if (id == 'b') {
          return [_content('rel-komik', sourceId: 'komik', tagNames: [
            'fantasy'
          ])];
        }
        return [
          _content('rel-$id', tagNames: ['action'])
        ];
      });

      final result = await engineForTest().getRecommendations(limit: 10);

      // Strongest per source first ('a' for nhentai, 'b' for komik),
      // then the next-strongest overall fills the fetch budget.
      final requested = verify(() => contentRepo.getRelatedContent(
            contentId: captureAny(named: 'contentId'),
            limit: any(named: 'limit'),
          )).captured;
      final requestedIds = {
        for (final c in requested) (c as ContentId).value
      };
      expect(requestedIds, containsAll({'a', 'b'}));
      expect(requestedIds.length, 3);
      // The komik candidate survives scoring → multi-source output.
      expect(result.map((r) => r.contentId), contains('rel-komik'));
    });

    test('popular failure degrades to ranked-only', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'}
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('ranked', tagNames: ['action']),
          ]);
      when(() => contentRepo.getPopularContent(
            timeframe: any(named: 'timeframe'),
            page: any(named: 'page'),
          )).thenThrow(Exception('offline'));

      final result = await engineForTest().getRecommendations(limit: 10);

      expect(result.map((r) => r.contentId), ['ranked']);
    });
  });

  group('backfill tagless rows', () {
    Content detailForTest(String id, List<String> tagNames) =>
        _content(id, tagNames: tagNames);

    void stubDetailForTest(Map<String, Content> details) {
      when(() => contentRepo.getContentDetail(
            any(),
            sourceId: any(named: 'sourceId'),
          )).thenAnswer((inv) async {
        final id = (inv.positionalArguments[0] as ContentId).value;
        final detail = details[id];
        if (detail == null) throw Exception('not found');
        return detail;
      });
    }

    test('fetches detail and writes through for tagless seed', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('old', lastViewed: now)],
        {}, // no stored tags → backfill path
      );
      stubDetailForTest({'old': detailForTest('old', ['action', 'fantasy'])});
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('cand', tagNames: ['action', 'fantasy']),
          ]);

      final result = await engineForTest().getRecommendations(limit: 10);

      expect(result.map((r) => r.contentId), ['cand']);
      verify(() => contentRepo.getContentDetail(
            any(that: isA<ContentId>()),
            sourceId: 'nhentai',
          )).called(1);
      final written =
          verify(() => userData.saveContentTags(captureAny())).captured;
      expect(
        (written.single as List).map((t) => t.origin).toSet(),
        {'history'},
      );
    });

    test('skips detail fetch when tags are stored', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'}
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      await engineForTest().getRecommendations(limit: 10);

      verifyNever(() => contentRepo.getContentDetail(
            any(),
            sourceId: any(named: 'sourceId'),
          ));
    });

    test('backfill failure is tolerated (seed skipped)', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('gone', lastViewed: now)],
        {},
      );
      stubDetailForTest({}); // everything throws
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      expect(await engineForTest().getRecommendations(limit: 10), isEmpty);
    });

    test('backfill capped at 8 detail fetches per recompute', () async {
      final now = DateTime.now();
      final rows = [
        for (var i = 0; i < 12; i++)
          _history('h$i', lastViewed: now),
      ];
      stubHistoryForTest(rows, {});
      stubDetailForTest({
        for (var i = 0; i < 12; i++) 'h$i': detailForTest('h$i', ['tag$i']),
      });
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      await engineForTest().getRecommendations(limit: 10);

      verify(() => contentRepo.getContentDetail(
            any(),
            sourceId: any(named: 'sourceId'),
          )).called(8);
    });
  });

  group('9.6 cold start', () {
    test('no seeds returns empty list', () async {
      stubHistoryForTest([], {});

      expect(await engineForTest().getRecommendations(), isEmpty);
      verifyNever(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          ));
    });
  });

  group('9.7 cache TTL', () {
    test('second call within TTL does not refetch related', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'}
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('b', tagNames: ['action']),
          ]);

      final engine = engineForTest();
      await engine.getRecommendations();
      await engine.getRecommendations();

      verify(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).called(1);
    });

    test('dismiss invalidates the cache', () async {
      final now = DateTime.now();
      stubHistoryForTest(
        [_history('a', lastViewed: now)],
        {
          'a': {'action'}
        },
      );
      when(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            _content('b', tagNames: ['action']),
          ]);

      final engine = engineForTest();
      await engine.getRecommendations();
      await engine.recordDismissed('b');
      await engine.getRecommendations();

      verify(() => contentRepo.getRelatedContent(
            contentId: any(named: 'contentId'),
            limit: any(named: 'limit'),
          )).called(2);
      verify(() => userData.recordRecommendationDismissed('b',
          sourceId: any(named: 'sourceId'))).called(1);
    });
  });
}
