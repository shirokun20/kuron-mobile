import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/services/preferences_service.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// P4 quiet parity: for all eleven [KuronFxKind] values, [KuronFx.trigger]
/// and [KuronFx.triggerOn] must be decoration-only no-ops when gated by quiet
/// mode, reduced motion, a note theme, or the reader: no overlay entry, no
/// timer, no painter — while the caller's own state change still lands.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  /// Pumps a themed app with a live [KuronFxHost]. [theme] drives the note
  /// gate through [ThemeCubit]; [reducedMotion] injects `disableAnimations`.
  Future<List<dynamic>> pumpGated(
    WidgetTester tester, {
    required KuronFxMode mode,
    String theme = 'dark',
    bool reducedMotion = false,
    required Widget home,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kuron_fx_mode': mode.storageValue,
      'theme': theme,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsCubit(
      preferencesService: PreferencesService(prefs, logger: p2Logger),
      logger: p2Logger,
    );
    await settings.stream.firstWhere((s) => s is SettingsLoaded);
    final themeCubit = ThemeCubit(settingsCubit: settings, logger: p2Logger);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp(
          builder: (context, child) => KuronFxHost(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: home,
        ),
      ),
    );
    return <dynamic>[settings, themeCubit];
  }

  /// Tears the host down and closes the injected cubits. No word bake is
  /// pending in a gated context, so a plain pump is enough (anti-leak).
  Future<void> closeGate(WidgetTester tester, List<dynamic> cubits) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final cubit in cubits) {
      await (cubit as dynamic).close();
    }
  }

  Future<void> expectNoFx(WidgetTester tester, String label) async {
    final controller = KuronFx.activeController!;
    expect(
      controller.activeEntryCount,
      0,
      reason: '$label: overlay entry mounted',
    );
    expect(controller.activeTimerCount, 0, reason: '$label: timer pending');
    expect(maybePainterOf(tester), isNull, reason: '$label: painter present');
    expect(tester.takeException(), isNull, reason: '$label: exception thrown');
  }

  /// One tap increments the probe's own state and fires BOTH public trigger
  /// paths for [kind] inside the same gated context. Asserts that decoration
  /// is fully suppressed while the state increment is not.
  Future<void> checkGate(
    WidgetTester tester, {
    required String label,
    required KuronFxMode mode,
    String theme = 'dark',
    bool reducedMotion = false,
    bool reader = false,
  }) async {
    for (final kind in KuronFxKind.values) {
      final injected = await pumpGated(
        tester,
        mode: mode,
        theme: theme,
        reducedMotion: reducedMotion,
        home: _FxProbe(
          fire: (ctx) {
            KuronFx.trigger(ctx, kind: kind, isReader: reader);
            KuronFx.triggerOn(
              ctx,
              rect: const Rect.fromLTWH(20, 20, 48, 48),
              kind: kind,
              isReader: reader,
            );
          },
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(
        find.text('taps: 1'),
        findsOneWidget,
        reason: '$label/$kind: underlying state change lost',
      );
      await expectNoFx(tester, '$label/$kind');
      await closeGate(tester, injected);
    }
  }

  testWidgets('positive control: an ungated trigger still mounts one burst', (
    tester,
  ) async {
    final injected = await pumpGated(
      tester,
      mode: KuronFxMode.standard,
      home: _FxProbe(
        fire: (ctx) => KuronFx.trigger(ctx, kind: KuronFxKind.favorite),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(find.text('taps: 1'), findsOneWidget);
    expect(KuronFx.activeController!.activeEntryCount, 1);
    expect(maybePainterOf(tester), isNotNull);
    // Drain the running burst before teardown so no frame callback lingers.
    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    await settleAndClose(tester, injected);
  });

  testWidgets('quiet mode is a decoration no-op for every kind', (
    tester,
  ) async {
    await checkGate(tester, label: 'quiet', mode: KuronFxMode.quiet);
  });

  testWidgets('reduced motion is a decoration no-op for every kind', (
    tester,
  ) async {
    await checkGate(
      tester,
      label: 'reduced-motion',
      mode: KuronFxMode.standard,
      reducedMotion: true,
    );
  });

  testWidgets('note theme is a decoration no-op for every kind', (
    tester,
  ) async {
    await checkGate(
      tester,
      label: 'note-theme',
      mode: KuronFxMode.standard,
      theme: 'note',
    );
  });

  testWidgets('reader is a decoration no-op for every kind', (tester) async {
    await checkGate(
      tester,
      label: 'reader',
      mode: KuronFxMode.standard,
      reader: true,
    );
  });
}

/// Minimal stateful surface whose tap changes local state and then fires the
/// decoration. Kept widget-only so the test proves state and decoration are
/// independent: the state text updates even when the FX gate blocks the burst.
class _FxProbe extends StatefulWidget {
  const _FxProbe({required this.fire});

  final void Function(BuildContext context) fire;

  @override
  State<_FxProbe> createState() => _FxProbeState();
}

class _FxProbeState extends State<_FxProbe> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('taps: $_taps'),
          ElevatedButton(
            onPressed: () {
              setState(() => _taps++);
              widget.fire(context);
            },
            child: const Text('fire'),
          ),
        ],
      ),
    ),
  );
}
