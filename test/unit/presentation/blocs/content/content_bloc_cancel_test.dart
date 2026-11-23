import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart' show Content;
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/repositories/content_repository.dart';
import 'package:nhasixapp/domain/usecases/base_usecase.dart';
import 'package:nhasixapp/domain/usecases/content/content_usecases.dart';
import 'package:nhasixapp/presentation/blocs/content/content_bloc.dart';

// Restartable-style cancellation for ContentBloc (thermal fix):
// starting a new fetch aborts the in-flight Dio request, superseded
// results never emit, and cancellation never surfaces as error UI.
class MockGetContentListUseCase extends Mock implements GetContentListUseCase {}

class MockSearchContentUseCase extends Mock implements SearchContentUseCase {}

class MockGetContentByTagUseCase extends Mock
    implements GetContentByTagUseCase {}

class MockGetPopularContentUseCase extends Mock
    implements GetPopularContentUseCase {}

class MockLogger extends Mock implements Logger {}

Content _content(String id) => Content(
      id: id,
      sourceId: 'nhentai',
      title: 'Title $id',
      coverUrl: 'http://cover/$id',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: 10,
      imageUrls: const [],
      uploadDate: DateTime(2026, 1, 1),
    );

ContentListResult _result(String id) => ContentListResult(
      contents: [_content(id)],
      currentPage: 1,
      totalPages: 5,
      totalCount: 5,
      hasNext: true,
      hasPrevious: false,
    );

void main() {
  late ContentBloc bloc;
  late MockGetContentListUseCase listUseCase;
  late MockLogger logger;

  setUp(() {
    listUseCase = MockGetContentListUseCase();
    logger = MockLogger();
    bloc = ContentBloc(
      getContentListUseCase: listUseCase,
      searchContentUseCase: MockSearchContentUseCase(),
      getContentByTagUseCase: MockGetContentByTagUseCase(),
      getPopularContentUseCase: MockGetPopularContentUseCase(),
      logger: logger,
    );
    registerFallbackValue(const GetContentListParams());
  });

  tearDown(() => bloc.close());

  test('superseded fetch is cancelled and stays silent', () async {
    final pending = Completer<ContentListResult>();
    var calls = 0;
    when(() => listUseCase(any())).thenAnswer((invocation) {
      calls++;
      final params =
          invocation.positionalArguments[0] as GetContentListParams;
      if (calls == 1) {
        // First fetch: register an abort hook that fails the pending fetch,
        // mirroring the adapter bridging OnCancelRegister to a Dio token.
        params.onCancel?.call(() {
          if (!pending.isCompleted) {
            pending.completeError(const OperationCancelledException());
          }
        });
        return pending.future;
      }
      return Future.value(_result('b'));
    });

    final states = <ContentState>[];
    final sub = bloc.stream.listen(states.add);

    bloc.add(const ContentLoadEvent(page: 1));
    // Let the first fetch start and register its abort hook.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    bloc.add(const ContentLoadEvent(page: 1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    // Only the newest fetch emits; the cancelled one stays silent.
    final loaded = states.whereType<ContentLoaded>().toList();
    expect(loaded, hasLength(1));
    expect(loaded.single.contents.map((c) => c.id), ['b']);
    expect(states.whereType<ContentError>(), isEmpty);
    expect(calls, 2);
  });

  test('inherited shared-request cancel retries once while newest', () async {
    var calls = 0;
    when(() => listUseCase(any())).thenAnswer((_) {
      calls++;
      // First attempt inherits a cancellation from a superseded shared
      // (deduplicated) request, like RequestDeduplicationService delivers.
      if (calls == 1) throw const OperationCancelledException();
      return Future.value(_result('a'));
    });

    final states = <ContentState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const ContentLoadEvent(page: 1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    expect(calls, 2);
    final loaded = states.whereType<ContentLoaded>().toList();
    expect(loaded, hasLength(1));
    expect(loaded.single.contents.map((c) => c.id), ['a']);
    expect(states.whereType<ContentError>(), isEmpty);
  });

  test('close() cancels the in-flight fetch without emitting', () async {
    final pending = Completer<ContentListResult>();
    when(() => listUseCase(any())).thenAnswer((invocation) {
      final params =
          invocation.positionalArguments[0] as GetContentListParams;
      params.onCancel?.call(() {
        if (!pending.isCompleted) {
          pending.completeError(const OperationCancelledException());
        }
      });
      return pending.future;
    });

    final states = <ContentState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const ContentLoadEvent(page: 1));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await bloc.close();
    await sub.cancel();

    // Loading was emitted, but the cancelled fetch never resolves to
    // content or an error — and emitting after close never throws.
    expect(states.whereType<ContentLoaded>(), isEmpty);
    expect(states.whereType<ContentError>(), isEmpty);
  });
}
