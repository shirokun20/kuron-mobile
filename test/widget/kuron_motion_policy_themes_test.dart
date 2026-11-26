import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';

/// Exercises [KuronMotionPolicy] with the *real* [ThemeCubit]-produced
/// ThemeData for every supported theme, not hand-built lookalikes. The
/// regression this guards: the note-theme fallback must not false-positive on
/// Warm Dark, AMOLED or Light, and reduced motion must always force `quiet`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('app_disguise'),
      (call) async => 'default',
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app_disguise'), null);
  });

  final quietLogger = Logger(level: Level.off);

  Future<void> check({
    required WidgetTester tester,
    required String theme,
    required bool disableAnimations,
    required KuronFxMode expected,
  }) async {
    SharedPreferences.setMockInitialValues({
      'theme': theme,
      'kuron_fx_mode': KuronFxMode.satire.storageValue,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsCubit(
      preferencesService: PreferencesService(prefs, logger: quietLogger),
      logger: quietLogger,
    );
    await settings.stream.firstWhere((state) => state is SettingsLoaded);
    final themeCubit = ThemeCubit(settingsCubit: settings, logger: quietLogger);

    late KuronFxMode resolved;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: MaterialApp(
            // Keep the real ThemeCubit colorScheme; swap only GoogleFonts'
            // textTheme so tests don't leave a system-font frame callback behind.
            theme: themeCubit.state.themeData.copyWith(
              textTheme:
                  ThemeData(brightness: themeCubit.state.themeData.brightness)
                      .textTheme,
            ),
            home: Builder(
              builder: (context) {
                resolved = KuronMotionPolicy.effectiveMode(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(themeCubit.state.currentTheme, theme);
    expect(
      resolved,
      expected,
      reason: 'theme=$theme disableAnimations=$disableAnimations',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let real engine font messages land, then flush the frame callback they
    // schedule so it isn't mistaken for a leak at test teardown.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await settings.close();
    await themeCubit.close();
  }

  for (final theme in ['light', 'dark', 'amoled']) {
    testWidgets('$theme allows satire when FX mode is satire', (
      tester,
    ) async {
      await check(
        tester: tester,
        theme: theme,
        disableAnimations: false,
        expected: KuronFxMode.satire,
      );
    });

    testWidgets('$theme is forced quiet when animations are disabled', (
      tester,
    ) async {
      await check(
        tester: tester,
        theme: theme,
        disableAnimations: true,
        expected: KuronFxMode.quiet,
      );
    });
  }

  for (final theme in ['note', 'note_dark']) {
    testWidgets('$theme forces quiet regardless of stored satire mode', (
      tester,
    ) async {
      await check(
        tester: tester,
        theme: theme,
        disableAnimations: false,
        expected: KuronFxMode.quiet,
      );
    });
  }
}
