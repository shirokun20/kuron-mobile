import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

/// Real widget-tree test: the same root structure as `main.dart`
/// (`MaterialApp.builder -> KuronFxHost -> Navigator/Overlay`) plus the real
/// [SettingsCubit]/[ThemeCubit]. Verifies the overlay actually gets a
/// non-zero-sized `CustomPaint`, advances frames, coalesces rapid taps,
/// self-cleans within the 800 ms TTL and releases on dispose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // SettingsCubit probes the native disguise mode on load; without a handler
  // the platform call never resolves inside testWidgets' fake-async zone.
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

  Future<List<dynamic>> pumpApp(
    WidgetTester tester, {
    required String mode,
    required KuronFxKind kind,
  }) async {
    SharedPreferences.setMockInitialValues({'kuron_fx_mode': mode});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsCubit(
      preferencesService: PreferencesService(prefs, logger: quietLogger),
      logger: quietLogger,
    );
    await settings.stream.firstWhere((state) => state is SettingsLoaded);
    final themeCubit = ThemeCubit(settingsCubit: settings, logger: quietLogger);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp(
          // Keep the real ThemeCubit colorScheme; swap only GoogleFonts'
          // textTheme so tests don't leave a system-font frame callback behind.
          theme: themeCubit.state.themeData.copyWith(
            textTheme:
                ThemeData(brightness: themeCubit.state.themeData.brightness)
                    .textTheme,
          ),
          builder: (context, child) => KuronFxHost(
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      KuronFx.trigger(context, kind: kind),
                  child: const Text('fire'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return [settings, themeCubit];
  }

  KuronFxOverlayPainter painterOf(WidgetTester tester) {
    final element = tester.element(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is KuronFxOverlayPainter,
      ),
    );
    final renderObject = element.renderObject as RenderCustomPaint;
    return renderObject.painter! as KuronFxOverlayPainter;
  }

  testWidgets('standard mode: non-zero CustomPaint, frames, coalesce, TTL', (
    tester,
  ) async {
    final injected = await pumpApp(
      tester,
      mode: KuronFxMode.standard.storageValue,
      kind: KuronFxKind.favorite,
    );
    final controller = KuronFx.activeController!;

    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(controller.activeEntryCount, 1);
    expect(controller.activeTimerCount, 1);
    expect(controller.particleCount, 14);

    // The Classic zero-sized CustomPaint bug: painter must receive a real size.
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is KuronFxOverlayPainter,
    );
    expect(finder, findsOneWidget);
    final renderObject =
        tester.element(finder).renderObject as RenderCustomPaint;
    expect(renderObject.size, isNot(Size.zero));
    expect(renderObject.size.width, greaterThan(0));
    expect(renderObject.size.height, greaterThan(0));

    // Animation must actually advance.
    final firstProgress = painterOf(tester).progress;
    await tester.pump(const Duration(milliseconds: 120));
    final secondProgress = painterOf(tester).progress;
    expect(secondProgress, greaterThan(firstProgress));

    // Rapid taps coalesce: one overlay/timer, burst counter increments.
    await tester.tap(find.text('fire'));
    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(controller.burstCount, 3);
    expect(controller.activeEntryCount, 1);
    expect(controller.activeTimerCount, 1);

    // Self-cleanup within the bounded TTL.
    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    expect(controller.activeEntryCount, 0);
    expect(controller.activeTimerCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let real engine font messages land, then flush the frame callback they
    // schedule so it isn't mistaken for a leak at test teardown.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(KuronFx.activeController, isNull);
    for (final cubit in injected) {
      await (cubit as dynamic).close();
    }
  });

  testWidgets('satire mode renders the painter only, no sticker Image', (
    tester,
  ) async {
    final injected = await pumpApp(
      tester,
      mode: KuronFxMode.satire.storageValue,
      kind: KuronFxKind.sheetConfirm,
    );
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(find.byType(Image), findsNothing);
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is KuronFxOverlayPainter,
    );
    final renderObject =
        tester.element(finder).renderObject as RenderCustomPaint;
    expect(renderObject.size, isNot(Size.zero));
    expect(KuronFx.activeController!.particleCount, lessThanOrEqualTo(40));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let real engine font messages land, then flush the frame callback they
    // schedule so it isn't mistaken for a leak at test teardown.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    for (final cubit in injected) {
      await (cubit as dynamic).close();
    }
  });

  testWidgets('downloadComplete kind inserts a visible overlay', (
    tester,
  ) async {
    final injected = await pumpApp(
      tester,
      mode: KuronFxMode.standard.storageValue,
      kind: KuronFxKind.downloadComplete,
    );
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(KuronFx.activeController!.activeEntryCount, 1);
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is KuronFxOverlayPainter,
    );
    final renderObject =
        tester.element(finder).renderObject as RenderCustomPaint;
    expect(renderObject.size, isNot(Size.zero));
    expect(painterOf(tester).kind, KuronFxKind.downloadComplete);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    for (final cubit in injected) {
      await (cubit as dynamic).close();
    }
  });

  testWidgets('quiet mode: trigger is a no-op', (tester) async {
    final injected = await pumpApp(
      tester,
      mode: KuronFxMode.quiet.storageValue,
      kind: KuronFxKind.favorite,
    );
    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    // Let real engine font messages land, then flush the frame callback they
    // schedule so it isn't mistaken for a leak at test teardown.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    for (final cubit in injected) {
      await (cubit as dynamic).close();
    }
  });
}
