import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' as core;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/data/repositories/combined_home_repository_impl.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';

class MockUserDataRepository extends Mock implements UserDataRepository {}

class MockContentSource extends Mock implements core.ContentSource {}

Content makeContent(String sourceId, String id) => Content(
      id: id,
      sourceId: sourceId,
      title: 'title-$id',
      coverUrl: 'https://cdn.example.com/$id.jpg',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'en',
      pageCount: 10,
      imageUrls: const [],
      uploadDate: DateTime(2026, 1, 1),
    );

core.ContentListResult pageOf(List<Content> items) => core.ContentListResult(
      contents: items,
      currentPage: 1,
      totalPages: 1,
      totalCount: items.length,
    );

void main() {
  late core.ContentSourceRegistry registry;
  late MockUserDataRepository userData;
  late DateTime now;
  late CombinedHomeRepositoryImpl repository;
  final sources = <String, MockContentSource>{};

  MockContentSource addSource(String id, List<Content> items) {
    final source = MockContentSource();
    when(() => source.id).thenReturn(id);
    when(() => source.getList(page: any(named: 'page')))
        .thenAnswer((_) async => pageOf(items));
    registry.register(source);
    sources[id] = source;
    return source;
  }

  void stubCounts({
    Map<String, int> reads = const {},
    Map<String, int> downloads = const {},
  }) {
    when(() => userData.getReadCountsBySource())
        .thenAnswer((_) async => reads);
    when(() => userData.getDownloadCountsBySource())
        .thenAnswer((_) async => downloads);
  }

  setUp(() {
    registry = core.ContentSourceRegistry();
    userData = MockUserDataRepository();
    sources.clear();
    now = DateTime(2026, 11, 6, 12);
    repository = CombinedHomeRepositoryImpl(
      userDataRepository: userData,
      contentSourceRegistry: registry,
      logger: Logger(level: Level.off),
      clock: () => now,
    );
  });

  group('source ranking', () {
    test('ranks sources by reads first, highest first', () async {
      addSource('a', [makeContent('a', 'a1')]);
      addSource('b', [makeContent('b', 'b1')]);
      stubCounts(reads: {'a': 10, 'b': 1});

      final feed = await repository.getCombinedFeed();

      expect(feed.isFallback, isFalse);
      expect(feed.sourceIds, ['a', 'b']);
      expect(feed.contents.first.sourceId, 'a');
    });

    test('weights one download as two reads', () async {
      addSource('a', [makeContent('a', 'a1')]);
      addSource('b', [makeContent('b', 'b1')]);
      // a: 3 reads = 3 pts; b: 2 downloads = 4 pts → b wins.
      stubCounts(reads: {'a': 3}, downloads: {'b': 2});

      final feed = await repository.getCombinedFeed();

      expect(feed.sourceIds, ['b', 'a']);
      expect(feed.contents.first.sourceId, 'b');
    });

    test('falls back to downloads when reads are empty', () async {
      addSource('b', [makeContent('b', 'b1')]);
      addSource('c', [makeContent('c', 'c1')]);
      stubCounts(downloads: {'b': 3, 'c': 1});

      final feed = await repository.getCombinedFeed();

      expect(feed.isFallback, isFalse);
      expect(feed.sourceIds, ['b', 'c']);
    });

    test('caps contributors at five sources', () async {
      for (var i = 0; i < 7; i++) {
        addSource('s$i', [makeContent('s$i', 'c$i')]);
      }
      stubCounts(reads: {
        for (var i = 0; i < 7; i++) 's$i': 10 - i,
      });

      final feed = await repository.getCombinedFeed();

      expect(feed.sourceIds, hasLength(5));
      expect(feed.sourceIds, ['s0', 's1', 's2', 's3', 's4']);
      verifyNever(() => sources['s5']!.getList(page: any(named: 'page')));
      verifyNever(() => sources['s6']!.getList(page: any(named: 'page')));
    });

    test('excludes unregistered (disabled) sources despite history', () async {
      addSource('a', [makeContent('a', 'a1')]);
      stubCounts(reads: {'ghost': 100, 'a': 1});

      final feed = await repository.getCombinedFeed();

      expect(feed.sourceIds, ['a']);
      expect(feed.contents, hasLength(1));
    });

    test('skips failing sources and returns the partial mix', () async {
      final failing = addSource('a', [makeContent('a', 'a1')]);
      when(() => failing.getList(page: any(named: 'page')))
          .thenThrow(Exception('boom'));
      addSource('b', [makeContent('b', 'b1')]);
      stubCounts(reads: {'a': 10, 'b': 5});

      final feed = await repository.getCombinedFeed();

      expect(feed.sourceIds, ['b']);
      expect(feed.contents.map((c) => c.id), ['b1']);
    });
  });

  group('interleave + dedupe', () {
    test('round-robins one item per source in rank order', () async {
      addSource('a', [
        makeContent('a', 'a1'),
        makeContent('a', 'a2'),
        makeContent('a', 'a3'),
      ]);
      addSource('b', [makeContent('b', 'b1'), makeContent('b', 'b2')]);
      stubCounts(reads: {'a': 10, 'b': 5});

      final feed = await repository.getCombinedFeed();

      expect(feed.contents.map((c) => c.id), ['a1', 'b1', 'a2', 'b2', 'a3']);
    });

    test('drops duplicate content ids (first in rank order wins)', () async {
      addSource('a', [makeContent('a', 'dup'), makeContent('a', 'a2')]);
      addSource('b', [makeContent('b', 'dup'), makeContent('b', 'b2')]);
      stubCounts(reads: {'a': 10, 'b': 5});

      final feed = await repository.getCombinedFeed();

      expect(feed.contents.map((c) => c.id), ['dup', 'a2', 'b2']);
      expect(feed.contents.first.sourceId, 'a');
    });
  });

  group('cache TTL', () {
    test('serves the second call from cache without network', () async {
      addSource('a', [makeContent('a', 'a1')]);
      stubCounts(reads: {'a': 4});

      await repository.getCombinedFeed();
      await repository.getCombinedFeed();

      verify(() => sources['a']!.getList(page: any(named: 'page'))).called(1);
    });

    test('forceRefresh bypasses the cache', () async {
      addSource('a', [makeContent('a', 'a1')]);
      stubCounts(reads: {'a': 4});

      await repository.getCombinedFeed();
      await repository.getCombinedFeed(forceRefresh: true);

      verify(() => sources['a']!.getList(page: any(named: 'page'))).called(2);
    });

    test('refetches after the 15-minute TTL expires', () async {
      addSource('a', [makeContent('a', 'a1')]);
      stubCounts(reads: {'a': 4});

      await repository.getCombinedFeed();
      now = now.add(const Duration(minutes: 16));
      await repository.getCombinedFeed();

      verify(() => sources['a']!.getList(page: any(named: 'page'))).called(2);
    });
  });

  group('cold start', () {
    test('returns the default source list flagged as fallback', () async {
      addSource('a', [makeContent('a', 'a1'), makeContent('a', 'a2')]);
      addSource('b', [makeContent('b', 'b1')]);
      stubCounts();

      final feed = await repository.getCombinedFeed();

      expect(feed.isFallback, isTrue);
      expect(feed.fallbackSourceId, 'a'); // first registered = current
      expect(feed.contents.map((c) => c.id), ['a1', 'a2']);
    });

    test('returns an empty feed when no source is registered', () async {
      stubCounts();

      final feed = await repository.getCombinedFeed();

      expect(feed.contents, isEmpty);
      expect(feed.isFallback, isFalse);
    });
  });
}
