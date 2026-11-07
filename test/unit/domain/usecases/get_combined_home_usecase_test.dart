import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/repositories/combined_home_repository.dart';
import 'package:nhasixapp/domain/usecases/base_usecase.dart';
import 'package:nhasixapp/domain/usecases/combined_home/get_combined_home_usecase.dart';

class MockCombinedHomeRepository extends Mock
    implements CombinedHomeRepository {}

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

void main() {
  late MockCombinedHomeRepository repository;
  late GetCombinedHomeUseCase useCase;

  setUp(() {
    repository = MockCombinedHomeRepository();
    useCase = GetCombinedHomeUseCase(repository);
  });

  test('returns the ranked feed on the happy path', () async {
    const feed = CombinedHomeFeed(
      contents: [],
      sourceIds: ['a', 'b'],
    );
    when(() => repository.getCombinedFeed(
          limit: any(named: 'limit'),
          forceRefresh: any(named: 'forceRefresh'),
        )).thenAnswer((_) async => feed);

    final result =
        await useCase(const GetCombinedHomeParams(limit: 10));

    expect(result.sourceIds, ['a', 'b']);
    expect(result.isFallback, isFalse);
    verify(() => repository.getCombinedFeed(limit: 10, forceRefresh: false))
        .called(1);
  });

  test('passes the cold-start fallback marker through', () async {
    final feed = CombinedHomeFeed(
      contents: [makeContent('a', 'a1')],
      sourceIds: const ['a'],
      isFallback: true,
      fallbackSourceId: 'a',
    );
    when(() => repository.getCombinedFeed(
          limit: any(named: 'limit'),
          forceRefresh: any(named: 'forceRefresh'),
        )).thenAnswer((_) async => feed);

    final result = await useCase(const GetCombinedHomeParams());

    expect(result.isFallback, isTrue);
    expect(result.fallbackSourceId, 'a');
    expect(result.contents, hasLength(1));
  });

  test('rejects limit below 1 with ValidationException', () async {
    await expectLater(
      useCase(const GetCombinedHomeParams(limit: 0)),
      throwsA(isA<ValidationException>()),
    );
    verifyNever(() => repository.getCombinedFeed(
          limit: any(named: 'limit'),
          forceRefresh: any(named: 'forceRefresh'),
        ));
  });

  test('wraps repository failure in CacheException', () async {
    when(() => repository.getCombinedFeed(
          limit: any(named: 'limit'),
          forceRefresh: any(named: 'forceRefresh'),
        )).thenThrow(Exception('db down'));

    await expectLater(
      useCase(const GetCombinedHomeParams()),
      throwsA(isA<CacheException>()),
    );
  });
}
