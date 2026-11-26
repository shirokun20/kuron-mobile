import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// Shared harness for the four P2 per-MR widget tests. SettingsCubit probes
/// the native disguise channel on load, so the channel must be mocked or the
/// fake-async zone never resolves.
final Logger p2Logger = Logger(level: Level.off);

void setUpFxChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('app_disguise'),
        (call) async => 'default',
      );
}

void tearDownFxChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('app_disguise'), null);
}

/// Pumps a themed app with a live [KuronFxHost] and the requested fx mode.
/// [reducedMotion] injects `disableAnimations` below the app's MediaQuery.
Future<List<dynamic>> pumpFxApp(
  WidgetTester tester, {
  required KuronFxMode mode,
  Widget? home,
  bool reducedMotion = false,
  Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
  List<Locale>? supportedLocales,
}) async {
  SharedPreferences.setMockInitialValues({'kuron_fx_mode': mode.storageValue});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsCubit(
    preferencesService: PreferencesService(prefs, logger: p2Logger),
    logger: p2Logger,
  );
  await settings.stream.firstWhere((state) => state is SettingsLoaded);
  final theme = ThemeCubit(settingsCubit: settings, logger: p2Logger);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settings),
        BlocProvider<ThemeCubit>.value(value: theme),
      ],
      child: MaterialApp(
        localizationsDelegates: localizationsDelegates,
        supportedLocales:
            supportedLocales ?? const <Locale>[Locale('en', 'US')],
        builder: (context, child) => KuronFxHost(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reducedMotion),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: home ?? const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  return <dynamic>[settings, theme];
}

/// The single active overlay painter, or null when no burst is mounted.
KuronFxOverlayPainter? maybePainterOf(WidgetTester tester) {
  final found = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is KuronFxOverlayPainter,
  );
  if (found.evaluate().isEmpty) return null;
  final element = tester.element(found);
  return (element.renderObject as RenderCustomPaint).painter!
      as KuronFxOverlayPainter;
}

KuronFxOverlayPainter painterOf(WidgetTester tester) => maybePainterOf(tester)!;

/// Lets any off-loop word bake land without advancing the overlay TTL, then
/// tears the harness down and closes the injected cubits.
Future<void> settleAndClose(WidgetTester tester, List<dynamic> cubits) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  for (final cubit in cubits) {
    await (cubit as dynamic).close();
  }
}
