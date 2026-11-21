import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/repositories/app_lock_repository.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/app_lock/app_lock_cubit.dart';
import 'package:nhasixapp/presentation/widgets/app_lock_gate.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_entry_screen.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_setup_screen.dart';

class MockAppLockRepository extends Mock implements AppLockRepository {}

class MockLogger extends Mock implements Logger {}

Widget buildTestApp(
  AppLockCubit cubit, {
  Widget child = const SizedBox(key: Key('child')),
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<AppLockCubit>.value(
      value: cubit,
      child: const AppLockGate(child: SizedBox(key: Key('child'))),
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
  });

  tearDown(() async {
    await cubit.close();
  });

  group('AppLockGate', () {
    testWidgets('shows PinSetupScreen when no PIN set', (tester) async {
      when(() => repository.getPinEnabled()).thenAnswer((_) async => true);
      when(() => repository.getPinHash()).thenAnswer((_) async => null);
      when(() => repository.getBiometricEnabled())
          .thenAnswer((_) async => false);
      when(() => repository.isBiometricAvailable())
          .thenAnswer((_) async => true);
      when(() => repository.isSessionActive()).thenAnswer((_) async => false);

      cubit = AppLockCubit(appLockRepository: repository, logger: logger);
      await cubit.init();
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      expect(find.byType(PinSetupScreen), findsOneWidget);
    });

    testWidgets('shows PinEntryScreen when PIN set and locked', (tester) async {
      when(() => repository.getPinEnabled()).thenAnswer((_) async => true);
      when(() => repository.getPinHash()).thenAnswer((_) async => 'hash');
      when(() => repository.getBiometricEnabled())
          .thenAnswer((_) async => false);
      when(() => repository.isBiometricAvailable())
          .thenAnswer((_) async => true);
      when(() => repository.isSessionActive()).thenAnswer((_) async => false);

      cubit = AppLockCubit(appLockRepository: repository, logger: logger);
      await cubit.init();
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pumpAndSettle();

      expect(find.byType(PinEntryScreen), findsOneWidget);
    });

    testWidgets('appears in widget tree', (tester) async {
      when(() => repository.getPinEnabled()).thenAnswer((_) async => false);
      when(() => repository.getPinHash()).thenAnswer((_) async => null);
      when(() => repository.getBiometricEnabled())
          .thenAnswer((_) async => false);
      when(() => repository.isBiometricAvailable())
          .thenAnswer((_) async => true);
      when(() => repository.isSessionActive()).thenAnswer((_) async => false);

      cubit = AppLockCubit(appLockRepository: repository, logger: logger);
      await cubit.init();
      await tester.pumpWidget(buildTestApp(cubit));
      await tester.pump();

      expect(find.byType(AppLockGate), findsOneWidget);
    });
  });
}
