import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/reading_statistics.dart';
import 'package:nhasixapp/domain/usecases/reader_identity/get_reading_streak_usecase.dart';
import 'package:nhasixapp/presentation/cubits/streak/streak_cubit.dart';

class MockGetReadingStreakUseCase extends Mock
    implements GetReadingStreakUseCase {}

class MockLogger extends Mock implements Logger {}

void main() {
  late MockGetReadingStreakUseCase useCase;
  late MockLogger logger;

  setUp(() {
    useCase = MockGetReadingStreakUseCase();
    logger = MockLogger();
    when(() => logger.t(any())).thenAnswer((_) {});
    when(() => logger.d(any())).thenAnswer((_) {});
    when(() => logger.i(any())).thenAnswer((_) {});
    when(() => logger.w(any())).thenAnswer((_) {});
    when(() => logger.e(any(),
        error: any(named: 'error'),
        stackTrace: any(named: 'stackTrace'))).thenAnswer((_) {});
  });

  ReadingStatistics stats() => ReadingStatistics.streak(
        readingStreak: 5,
        lastReadDate: DateTime(2026, 11, 10),
        readDays: const [],
      );

  group('StreakCubit.loadStreak close race', () {
    test('does not emit after close (navigation away mid-load)', () async {
      final gate = Completer<ReadingStatistics>();
      when(() => useCase.forDate(any())).thenAnswer((_) => gate.future);
      when(() => useCase.getLastReadContentId())
          .thenAnswer((_) async => 'c1');

      final cubit = StreakCubit(
        getReadingStreakUseCase: useCase,
        logger: logger,
      );
      final future = cubit.loadStreak(now: DateTime(2026, 11, 11));
      await cubit.close();
      gate.complete(stats());

      // Pre-fix this throws "Bad state: Cannot emit new states after
      // calling close". Post-fix it resolves quietly.
      await future;
      expect(cubit.state.isLoading, isTrue);
    });

    test('happy path still emits loaded state', () async {
      when(() => useCase.forDate(any())).thenAnswer((_) async => stats());
      when(() => useCase.getLastReadContentId())
          .thenAnswer((_) async => 'c1');

      final cubit = StreakCubit(
        getReadingStreakUseCase: useCase,
        logger: logger,
      );
      addTearDown(cubit.close);

      await cubit.loadStreak(now: DateTime(2026, 11, 11));

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.readingStreak, 5);
      expect(cubit.state.lastContentId, 'c1');
    });
  });
}
