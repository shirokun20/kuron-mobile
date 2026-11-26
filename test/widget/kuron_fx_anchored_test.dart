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

/// Anchored sakuga bursts: the effect is drawn around the triggering button,
/// sized to it — never as a fullscreen screen-center explosion, and never
/// with a bitmap overlay on button kinds.
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
  final fireKey = GlobalKey();

  Future<List<dynamic>> pumpAnchoredApp(
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
          theme: themeCubit.state.themeData.copyWith(
            textTheme: ThemeData(
              brightness: themeCubit.state.themeData.brightness,
            ).textTheme,
          ),
          builder: (context, child) =>
              KuronFxHost(child: child ?? const SizedBox.shrink()),
          // Button pinned to a corner: its center must differ from the
          // screen center so anchoring is observable.
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Builder(
                  builder: (buttonContext) => TextButton(
                    key: fireKey,
                    onPressed: () => KuronFx.trigger(buttonContext, kind: kind),
                    child: const Text('fire'),
                  ),
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

  testWidgets('trigger anchors the burst on the button rect', (tester) async {
    final injected = await pumpAnchoredApp(
      tester,
      mode: KuronFxMode.standard.storageValue,
      kind: KuronFxKind.favorite,
    );

    await tester.tap(find.byKey(fireKey));
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 1);

    final painter = painterOf(tester);
    final target = painter.targetRect;
    expect(target, isNotNull);

    // The burst sits on the button, far from the screen center.
    final buttonCenter = tester.getCenter(find.byKey(fireKey));
    expect(target!.center.dx, moreOrLessEquals(buttonCenter.dx, epsilon: 1));
    expect(target.center.dy, moreOrLessEquals(buttonCenter.dy, epsilon: 1));
    final screenCenter = Offset(
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
      tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
    );
    expect((target.center - screenCenter).distance, greaterThan(50));

    // Frames advance without throwing; burst self-cleans inside the TTL.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    expect(KuronFx.activeController!.activeEntryCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    for (final cubit in injected) {
      await (cubit as dynamic).close();
    }
  });

  testWidgets('button bursts never show a bitmap overlay', (tester) async {
    for (final kind in [KuronFxKind.favorite, KuronFxKind.downloadComplete]) {
      final injected = await pumpAnchoredApp(
        tester,
        mode: KuronFxMode.satire.storageValue,
        kind: kind,
      );

      await tester.tap(find.byKey(fireKey));
      await tester.pump();
      expect(KuronFx.activeController!.activeEntryCount, 1);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      for (final cubit in injected) {
        await (cubit as dynamic).close();
      }
    }
  });

  testWidgets('explicit targetRect overrides the context box', (tester) async {
    await pumpAnchoredApp(
      tester,
      mode: KuronFxMode.standard.storageValue,
      kind: KuronFxKind.downloadComplete,
    );
    final overlay = tester.state<OverlayState>(find.byType(Overlay));
    const explicit = Rect.fromLTWH(10, 20, 120, 48);

    KuronFx.activeController!.show(
      overlay: overlay,
      mode: KuronFxMode.standard,
      kind: KuronFxKind.downloadComplete,
      targetRect: explicit,
    );
    await tester.pump();
    expect(painterOf(tester).targetRect, explicit);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
