import 'dart:async';

import '../../../core/services/streak_widget_sync_service.dart';
import '../../../domain/entities/kuro_mood.dart';
import '../../../domain/usecases/reader_identity/get_reading_streak_usecase.dart';
import '../base/base_cubit.dart';

// One immutable snapshot of everything the streak card renders. `mood` is
// resolved here (not in the widget) so the card and the launcher widget can
// never disagree about which face the streak earns.
class StreakState extends BaseCubitState {
  const StreakState({
    this.isLoading = false,
    this.readingStreak = 0,
    this.lastReadDate,
    this.readDays = const [],
    this.mood = KuroMood.waiting,
    this.lastContentId,
    this.totalContentRead = 0,
    required this.referenceDate,
  });

  final bool isLoading;
  final int readingStreak;
  final DateTime? lastReadDate;
  final List<DateTime> readDays;
  final KuroMood mood;
  final String? lastContentId;
  final int totalContentRead;

  // The day this snapshot describes; the checklist is built around its week.
  final DateTime referenceDate;

  // Monday-first flags, index 0 = Senin. Matched by calendar day so a
  // midnight-parked DateTime still counts as that day.
  List<bool> get weeklyChecklist {
    final monday = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day - (referenceDate.weekday - 1),
    );
    return List<bool>.generate(7, (index) {
      final day = DateTime(monday.year, monday.month, monday.day + index);
      return readDays.any((d) =>
          d.year == day.year && d.month == day.month && d.day == day.day);
    });
  }

  @override
  List<Object?> get props => [
        isLoading,
        readingStreak,
        lastReadDate,
        readDays,
        mood,
        lastContentId,
        totalContentRead,
        referenceDate,
      ];
}

class StreakCubit extends BaseCubit<StreakState> {
  StreakCubit({
    required this.getReadingStreakUseCase,
    required super.logger,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(
          initialState: StreakState(
            isLoading: true,
            referenceDate: _referenceOf(clock),
          ),
        ) {
    _changes = StreakWidgetSyncService.changes.listen((_) => refresh());
  }

  final GetReadingStreakUseCase getReadingStreakUseCase;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;

  static DateTime _referenceOf(DateTime Function()? clock) =>
      (clock ?? DateTime.now)();

  Future<void> loadStreak({DateTime? now}) async {
    final ref = now ?? _clock();
    try {
      final stats = await getReadingStreakUseCase.forDate(ref);
      final lastContentId =
          await getReadingStreakUseCase.getLastReadContentId();
      if (isClosed) return;
      emit(StreakState(
        readingStreak: stats.readingStreak,
        lastReadDate: stats.lastReadDate,
        readDays: stats.readDays ?? const [],
        mood: resolveKuroMood(stats.lastReadDate, ref, rotateCeria: true),
        lastContentId: lastContentId,
        totalContentRead: stats.totalContentRead,
        referenceDate: ref,
      ));
      unawaited(StreakWidgetSyncService.syncWidget(stats, now: ref));
    } catch (error, stackTrace) {
      handleError(error, stackTrace, 'loadStreak');
      // First load failed: show the empty snapshot instead of waiting forever.
      if (isClosed) return;
      if (state.isLoading) emit(StreakState(referenceDate: ref));
    }
  }

  Future<void> refresh({DateTime? now}) => loadStreak(now: now);

  @override
  Future<void> close() {
    _changes.cancel();
    return super.close();
  }
}
