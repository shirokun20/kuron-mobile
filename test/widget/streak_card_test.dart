import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/reading_statistics.dart';
import 'package:nhasixapp/domain/usecases/reader_identity/get_reading_streak_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/streak/streak_cubit.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';
import 'package:nhasixapp/presentation/widgets/streak_card.dart';

class _MockGetReadingStreakUseCase extends Mock
    implements GetReadingStreakUseCase {}

// Sunday 2026-10-11.
final _now = DateTime(2026, 10, 11, 20, 30);

StreakCubit _cubitFor(ReadingStatistics stats, String? lastContentId) {
  final useCase = _MockGetReadingStreakUseCase();
  when(() => useCase.forDate(any())).thenAnswer((_) async => stats);
  when(() => useCase.getLastReadContentId())
      .thenAnswer((_) async => lastContentId);
  final cubit = StreakCubit(
    getReadingStreakUseCase: useCase,
    logger: Logger(),
    clock: () => _now,
  );
  return cubit;
}

Future<void> _pump(WidgetTester tester, StreakCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StreakCard(cubit: cubit)),
    ),
  );
  await cubit.loadStreak();
  await tester.pump();
}

KuroMood _moodOf(WidgetTester tester) =>
    tester.widget<KuroMascot>(find.byType(KuroMascot)).mood;

void main() {
  group('StreakCard', () {
    testWidgets('read today: shows streak and ceria mascot, no checklist', (
      tester,
    ) async {
      final cubit = _cubitFor(
        ReadingStatistics.streak(
          readingStreak: 4,
          lastReadDate: DateTime(2026, 10, 11),
          readDays: [
            DateTime(2026, 10, 9),
            DateTime(2026, 10, 10),
            DateTime(2026, 10, 11),
          ],
          totalContentRead: 12,
        ),
        'content-1',
      );
      addTearDown(cubit.close);

      await _pump(tester, cubit);

      expect(find.text('4'), findsOneWidget);
      expect(find.text('hari beruntun'), findsOneWidget);
      expect(isCeriaMood(_moodOf(tester)), isTrue);
      // Slim card: no weekly dots and no CTA button.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('absent 3 days: cry mascot', (tester) async {
      final cubit = _cubitFor(
        ReadingStatistics.streak(
          readingStreak: 0,
          lastReadDate: DateTime(2026, 10, 8),
        ),
        'content-1',
      );
      addTearDown(cubit.close);

      await _pump(tester, cubit);

      expect(_moodOf(tester), KuroMood.cry);
    });

    testWidgets('absent 10 days: tsundere mascot, streak 0', (tester) async {
      final cubit = _cubitFor(
        ReadingStatistics.streak(
          readingStreak: 0,
          lastReadDate: DateTime(2026, 10, 1),
        ),
        'content-1',
      );
      addTearDown(cubit.close);

      await _pump(tester, cubit);

      expect(_moodOf(tester), KuroMood.tsundere);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('renders localized strings via AppLocalizations (en)', (
      tester,
    ) async {
      final cubit = _cubitFor(
        ReadingStatistics.streak(
          readingStreak: 5,
          lastReadDate: DateTime(2026, 10, 11),
          readDays: [DateTime(2026, 10, 10), DateTime(2026, 10, 11)],
        ),
        'content-99',
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StreakCard(cubit: cubit)),
        ),
      );
      await cubit.loadStreak();
      await tester.pump();

      expect(find.text('day streak'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
