import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/constants/colors_const.dart';
import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_sfx_words.dart';

/// P3 bake-cache: path parsing, palette mapping, raster bake, eviction —
/// plus the kind→word wiring that replaced the per-frame `TextPainter`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('all six canonical words parse to non-empty paths', (
    tester,
  ) async {
    // Real asset I/O must run outside fake async: awaiting a platform
    // channel without pumping deadlocks the test.
    final words = (await tester.runAsync(KuronSfxBakeCache.loadWords))!;
    expect(words.keys.toSet(), {
      'JEDER!',
      'MANTAP!',
      'KLIK!',
      'SAH!',
      'CAIR!',
      'BYAR!',
    });
    for (final entry in KuronSfxWord.all) {
      final raw = words[entry.name]!;
      expect(raw.length, 3);
      expect(raw[0], 520);
      final path = parseSfxPathData(raw[2] as String);
      final bounds = path.getBounds();
      // Glyph outlines fill the nominal 520-wide artboard.
      expect(bounds.width, greaterThan(400));
      expect(bounds.height, greaterThan(200));
    }
  });

  test('word table carries the Designer-assigned styles', () {
    expect(KuronSfxWord.byName('JEDER!')?.style, KuronSfxStyle.solid);
    expect(KuronSfxWord.byName('MANTAP!')?.style, KuronSfxStyle.solid);
    expect(KuronSfxWord.byName('CAIR!')?.style, KuronSfxStyle.solid);
    expect(KuronSfxWord.byName('KLIK!')?.style, KuronSfxStyle.hollow);
    expect(KuronSfxWord.byName('SAH!')?.style, KuronSfxStyle.hollow);
    expect(KuronSfxWord.byName('BYAR!')?.style, KuronSfxStyle.dotted);
    expect(KuronSfxWord.byName('NOPE!'), isNull);
  });

  test('corrupt path data throws instead of silently rendering', () {
    expect(() => parseSfxPathData('M 0 0 Q 1 1 2 2'), throwsFormatException);
    expect(() => parseSfxPathData('M 0'), throwsFormatException);
  });

  test('palette maps gallery tones to Kuron theme (P0)', () {
    // Light solid: ink fill, white edge (gallery default).
    final light = KuronSfxPalette.resolve(
      KuronSfxStyle.solid,
      dark: false,
      monochrome: false,
    );
    expect(light.fill, AppColors.sfxInk);
    // Dark solid: paper fill, ink edge.
    final dark = KuronSfxPalette.resolve(
      KuronSfxStyle.solid,
      dark: true,
      monochrome: false,
    );
    expect(dark.fill, AppColors.sfxPaper);
    expect(dark.edge, AppColors.sfxInk);
    // Note themes collapse to a black/white pair.
    final mono = KuronSfxPalette.resolve(
      KuronSfxStyle.solid,
      dark: false,
      monochrome: true,
    );
    expect(mono.fill, const Color(0xFFFFFFFF));
    expect(mono.edge, const Color(0xFF000000));
    // Dotted keeps ink-on-paper on both brightnesses.
    final dots = KuronSfxPalette.resolve(
      KuronSfxStyle.dotted,
      dark: true,
      monochrome: false,
    );
    expect(dots.base, const Color(0xFFFFFFFF));
    expect(dots.fill, AppColors.sfxInk);
  });

  test('word spring overshoots then settles (gallery 0.2/520/17)', () {
    expect(KuronSfxMotion.spring.x(0.148), greaterThan(1.0));
    expect(KuronSfxMotion.spring.x(2.0), moreOrLessEquals(1.0, epsilon: 0.05));
  });

  testWidgets('bake caches one raster per key and evicts on dispose', (
    tester,
  ) async {
    final cache = KuronSfxBakeCache();
    final palette = KuronSfxPalette.resolve(
      KuronSfxStyle.solid,
      dark: false,
      monochrome: false,
    );
    final first = await tester.runAsync(
      () => cache.bake(
        word: 'JEDER!',
        style: KuronSfxStyle.solid,
        palette: palette,
      ),
    );
    expect(first, isNotNull);
    // Fixed 2× nominal raster: (520 + 2×24) × 2.
    expect(first!.width, (520 + 48) * 2);
    expect(first.height, greaterThan(600));

    final second = await tester.runAsync(
      () => cache.bake(
        word: 'JEDER!',
        style: KuronSfxStyle.solid,
        palette: palette,
      ),
    );
    expect(identical(first, second), isTrue);
    expect(cache.size, 1);

    // Dotted style bakes through the dot-tile path.
    final dotted = await tester.runAsync(
      () => cache.bake(
        word: 'BYAR!',
        style: KuronSfxStyle.dotted,
        palette: KuronSfxPalette.resolve(
          KuronSfxStyle.dotted,
          dark: false,
          monochrome: false,
        ),
      ),
    );
    expect(dotted, isNotNull);
    expect(cache.size, 2);

    cache.evict();
    expect(cache.size, 0);
    cache.dispose(); // idempotent, no throw
  });

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

  testWidgets('monochrome flag reaches the painter (P0 wiring)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KuronFxHost(child: Scaffold(body: SizedBox.expand())),
      ),
    );
    final controller = KuronFx.activeController!;
    final overlay = tester.state<OverlayState>(find.byType(Overlay));
    controller.show(
      overlay: overlay,
      mode: KuronFxMode.standard,
      kind: KuronFxKind.favorite,
      monochrome: true,
      dark: true,
    );
    await tester.pump();
    expect(painterOf(tester).monochrome, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('favorite burst bakes JEDER! into the painter (P3 wiring)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'kuron_fx_mode': KuronFxMode.standard.storageValue,
    });
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
          builder: (context, child) =>
              KuronFxHost(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () =>
                    KuronFx.trigger(buttonContext, kind: KuronFxKind.favorite),
                child: const Text('fire'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('fire'));
    await tester.pump();
    // Let the off-loop bake land (real async work outside fake async).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.wordSpec?.word.name, 'JEDER!');
    expect(painter.wordImage, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await settings.close();
    await themeCubit.close();
  });
}
