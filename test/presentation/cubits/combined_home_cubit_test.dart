import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/usecases/combined_home/get_combined_home_usecase.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_cubit.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_state.dart';

class _MockGetCombinedHomeUseCase extends Mock
    implements GetCombinedHomeUseCase {}

class _MockLogger extends Mock implements Logger {}

Content _content(String sourceId, String id) => Content(
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

CombinedHomeFeed _feed() => CombinedHomeFeed(
      contents: [_content('a', 'a1'), _content('b', 'b1')],
      sourceIds: const ['a', 'b'],
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const GetCombinedHomeParams());
  });

  late _MockGetCombinedHomeUseCase useCase;
  late CombinedHomeCubit cubit;

  setUp(() {
    useCase = _MockGetCombinedHomeUseCase();
    cubit = CombinedHomeCubit(
      getCombinedHomeUseCase: useCase,
      logger: _MockLogger(),
    );
  });

  tearDown(() => cubit.close());

  group('CombinedHomeCubit', () {
    test('starts unselected with initial status', () {
      expect(cubit.state.isCombinedSelected, isFalse);
      expect(cubit.state.status, CombinedHomeStatus.initial);
      expect(cubit.state.contents, isEmpty);
    });

    test('load success emits loaded feed', () async {
      when(() => useCase(any())).thenAnswer((_) async => _feed());

      await cubit.load();

      expect(cubit.state.status, CombinedHomeStatus.loaded);
      expect(cubit.state.contents.map((c) => c.id), ['a1', 'b1']);
      expect(cubit.state.sourceIds, ['a', 'b']);
      expect(cubit.state.isFallback, isFalse);
      expect(cubit.state.errorMessage, isNull);
      verify(() => useCase(const GetCombinedHomeParams(
            forceRefresh: false,
          ))).called(1);
    });

    test('refresh bypasses the repository cache', () async {
      when(() => useCase(any())).thenAnswer((_) async => _feed());

      await cubit.refresh();

      verify(() => useCase(const GetCombinedHomeParams(
            forceRefresh: true,
          ))).called(1);
    });

    test('load error with empty cache emits error', () async {
      when(() => useCase(any())).thenThrow(Exception('offline'));

      await cubit.load();

      expect(cubit.state.status, CombinedHomeStatus.error);
      expect(cubit.state.errorMessage, contains('offline'));
    });

    test('load error with cached contents keeps list and records error',
        () async {
      when(() => useCase(any())).thenAnswer((_) async => _feed());
      await cubit.load();

      when(() => useCase(any())).thenThrow(Exception('stale-refresh'));
      await cubit.refresh();

      expect(cubit.state.status, CombinedHomeStatus.loaded);
      expect(cubit.state.contents, hasLength(2));
      expect(cubit.state.errorMessage, contains('stale-refresh'));
    });

    test('second load while loading is a no-op', () async {
      when(() => useCase(any())).thenAnswer((_) async => _feed());

      final first = cubit.load();
      final second = cubit.load();
      await Future.wait([first, second]);

      verify(() => useCase(any())).called(1);
    });

    test('enterCombined selects mode and loads; exitCombined deselects',
        () async {
      when(() => useCase(any())).thenAnswer((_) async => _feed());

      await cubit.enterCombined();

      expect(cubit.state.isCombinedSelected, isTrue);
      expect(cubit.state.status, CombinedHomeStatus.loaded);

      cubit.exitCombined();

      expect(cubit.state.isCombinedSelected, isFalse);
      // Loaded list is kept for instant re-entry.
      expect(cubit.state.contents, hasLength(2));
    });

    test('cold-start fallback feed passes isFallback through', () async {
      const feed = CombinedHomeFeed(
        contents: [],
        sourceIds: ['a'],
        isFallback: true,
        fallbackSourceId: 'a',
      );
      when(() => useCase(any())).thenAnswer((_) async => feed);

      await cubit.enterCombined();

      expect(cubit.state.isFallback, isTrue);
      expect(cubit.state.fallbackSourceId, 'a');
    });
  });
}
