import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nhasixapp/core/constants/colors_const.dart';
import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

void main() {
  testWidgets('kuron_fx bounds: one overlay, 40 particles, 800ms TTL', (
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
      mode: KuronFxMode.satire,
      kind: KuronFxKind.favorite,
      sticker: KuronSticker.acc,
    );
    await tester.pump();
    expect(controller.activeEntryCount, 1);
    expect(controller.particleCount, lessThanOrEqualTo(40));
    expect(controller.activeTimerCount, 1);

    // Rapid second trigger replaces the burst instead of stacking overlays.
    controller.show(
      overlay: overlay,
      mode: KuronFxMode.satire,
      kind: KuronFxKind.downloadComplete,
      sticker: KuronSticker.cair,
    );
    await tester.pump();
    expect(controller.burstCount, 2);
    expect(controller.activeEntryCount, 1);
    expect(controller.activeTimerCount, 1);

    await tester.pump(
      KuronFxController.maxDuration + const Duration(milliseconds: 50),
    );
    expect(controller.activeEntryCount, 0);
    expect(controller.activeTimerCount, 0);

    // Host disposal releases the shared controller.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(KuronFx.activeController, isNull);
  });

  testWidgets('kuron_fx is quiet under reduced motion and note themes', (
    tester,
  ) async {
    late KuronFxMode reducedMode;
    late KuronFxMode noteMode;
    late KuronFxMode noteDarkMode;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              reducedMode = KuronMotionPolicy.effectiveMode(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(reducedMode, KuronFxMode.quiet);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(
            surface: AppColors.noteSurface,
            onSurface: Colors.black,
          ),
        ),
        home: Builder(
          builder: (context) {
            noteMode = KuronMotionPolicy.effectiveMode(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(noteMode, KuronFxMode.quiet);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            surface: Color(0xFF111111),
            onSurface: Colors.white,
          ),
        ),
        home: Builder(
          builder: (context) {
            noteDarkMode = KuronMotionPolicy.effectiveMode(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(noteDarkMode, KuronFxMode.quiet);
  });

  testWidgets('trigger produces no overlay when reduced motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const MaterialApp(
          home: KuronFxHost(
            child: Scaffold(body: Center(child: _FxTriggerButton())),
          ),
        ),
      ),
    );

    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(KuronFx.activeController!.activeTimerCount, 0);
  });
}

class _FxTriggerButton extends StatelessWidget {
  const _FxTriggerButton();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => KuronFx.trigger(context, kind: KuronFxKind.sheetConfirm),
      child: const Text('fire'),
    );
  }
}
