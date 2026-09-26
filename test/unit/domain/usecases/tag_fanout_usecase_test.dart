import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/content_tag.dart';
import 'package:nhasixapp/domain/entities/history.dart';
import 'package:nhasixapp/domain/repositories/user_data_repository.dart';
import 'package:nhasixapp/domain/usecases/favorites/add_to_favorites_usecase.dart';
import 'package:nhasixapp/domain/usecases/history/add_to_history_usecase.dart';

class _MockUserData extends Mock implements UserDataRepository {}

Content _content() => Content(
      id: 'c1',
      sourceId: 'nhentai',
      title: 'T',
      coverUrl: 'http://cover',
      tags: const [Tag(id: 1, name: 'Action', type: 'tag', count: 1)],
      artists: const ['Some Artist'],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: 10,
      imageUrls: const [],
      uploadDate: DateTime(2026, 1, 1),
    );

void main() {
  late _MockUserData repo;

  setUpAll(() {
    registerFallbackValue(
      History(contentId: 'x', lastViewed: DateTime(2026, 1, 1)),
    );
    registerFallbackValue(<ContentTag>[]);
    registerFallbackValue(_content());
  });

  setUp(() {
    repo = _MockUserData();
    when(() => repo.saveHistory(any())).thenAnswer((_) async {});
    when(() => repo.saveContentTags(any())).thenAnswer((_) async {});
    when(() => repo.addToFavorites(
          id: any(named: 'id'),
          sourceId: any(named: 'sourceId'),
          coverUrl: any(named: 'coverUrl'),
          title: any(named: 'title'),
        )).thenAnswer((_) async {});
  });

  group('history tag fan-out (0.2)', () {
    test('saves history-origin seeds when content is provided', () async {
      await AddToHistoryUseCase(repo)(
        AddToHistoryParams.fromString('c1', 3, 10, content: _content()),
      );

      verify(() => repo.saveHistory(any())).called(1);
      final seeds = verify(() => repo.saveContentTags(captureAny())).captured;
      expect(seeds.single.length, greaterThan(0));
      expect(seeds.single.first.origin, 'history');
      expect(seeds.single.first.contentId, 'c1');
    });

    test('skips tag write when content is absent', () async {
      await AddToHistoryUseCase(repo)(
        AddToHistoryParams.fromString('c1', 3, 10),
      );

      verify(() => repo.saveHistory(any())).called(1);
      verifyNever(() => repo.saveContentTags(any()));
    });

    test('history write still succeeds when tag write throws', () async {
      when(() => repo.saveContentTags(any()))
          .thenThrow(Exception('disk full'));

      await AddToHistoryUseCase(repo)(
        AddToHistoryParams.fromString('c1', 3, 10, content: _content()),
      );

      verify(() => repo.saveHistory(any())).called(1);
    });

    test('re-save does not duplicate (delete+reinsert is repo concern)', () async {
      // Contract: usecase passes the full fresh seed set every save, so the
      // repository replace (not append) keeps one row per tag.
      final params =
          AddToHistoryParams.fromString('c1', 3, 10, content: _content());
      await AddToHistoryUseCase(repo)(params);
      await AddToHistoryUseCase(repo)(params);

      verify(() => repo.saveContentTags(any())).called(2);
    });
  });

  group('favorite tag fan-out (0.3)', () {
    test('saves favorite-origin seeds from params content', () async {
      await AddToFavoritesUseCase(repo)(
        AddToFavoritesParams.force(_content()),
      );

      verify(() => repo.addToFavorites(
            id: 'c1',
            sourceId: 'nhentai',
            coverUrl: 'http://cover',
            title: 'T',
          )).called(1);
      final seeds = verify(() => repo.saveContentTags(captureAny())).captured;
      expect(
        seeds.single.map((s) => s.origin).toSet(),
        {'favorite'},
      );
    });

    test('favorite write still succeeds when tag write throws', () async {
      when(() => repo.saveContentTags(any()))
          .thenThrow(Exception('disk full'));

      await AddToFavoritesUseCase(repo)(
        AddToFavoritesParams.force(_content()),
      );

      verify(() => repo.addToFavorites(
            id: any(named: 'id'),
            sourceId: any(named: 'sourceId'),
            coverUrl: any(named: 'coverUrl'),
            title: any(named: 'title'),
          )).called(1);
    });
  });
}
