import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/repositories/app_lock_repository.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_cubit.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_setup_screen.dart';

class MockAppLockRepository extends Mock implements AppLockRepository {}

class MockLogger extends Mock implements Logger {}

Widget buildTestApp(AppLockCubit cubit) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<AppLockCubit>.value(
      value: cubit,
      child: const PinSetupScreen(),
    ),
  );
}

void main() {
  late AppLockCubit cubit;
  late MockAppLockRepository repository;
  late MockLogger logger;

  setUp(() {
    repository = MockAppLockRepository();
    logger = MockLogger();
    when(() => logger.i(any())).thenAnswer((_) {});
    when(() => logger.d(any())).thenAnswer((_) {});
    when(() => logger.w(any())).thenAnswer((_) {});
    when(
      () => logger.e(
        any(),
        error: any(named: 'error'),
        stackTrace: any(named: 'stackTrace'),
      ),
    ).thenAnswer((_) {});
    when(() => repository.getPinEnabled()).thenAnswer((_) async => false);
    when(() => repository.getPinHash()).thenAnswer((_) async => null);
    when(() => repository.getBiometricEnabled()).thenAnswer((_) async => false);
    when(() => repository.isBiometricAvailable())
        .thenAnswer((_) async => false);

    cubit = AppLockCubit(appLockRepository: repository, logger: logger);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('PinSetupScreen', () {
    testWidgets('renders setup title', (tester) async {
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      expect(find.text('Set Up PIN'), findsOneWidget);
    });

    testWidgets('switches to confirm phase after 6 digits', (tester) async {
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('Confirm PIN'), findsOneWidget);
    });

    testWidgets('calls setupPin when confirm matches', (tester) async {
      when(() => repository.savePinHash(any())).thenAnswer((_) async {});
      when(() => repository.setPinEnabled(true)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      verify(() => repository.savePinHash(any())).called(1);
      verify(() => repository.setPinEnabled(true)).called(1);
    });

    testWidgets('shows error and resets on mismatch', (tester) async {
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump();

      for (final d in ['6', '5', '4', '3', '2', '1']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('PINs do not match'), findsOneWidget);
    });
  });
}
