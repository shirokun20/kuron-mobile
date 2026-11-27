import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_checkbox.dart';
import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';

import 'kuron_fx_p2_support.dart';

/// Checkbox beat: checking fires a checkbox-anchored `checkboxTick` burst,
/// unchecking and quiet mode mount nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  testWidgets('checking fires checkboxTick anchored on the checkbox', (
    tester,
  ) async {
    var value = false;
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => KuronCheckbox(
              value: value,
              onChanged: (next) => setState(() => value = next ?? false),
            ),
          ),
        ),
      ),
    );
    expect(value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(value, isTrue);
    final controller = KuronFx.activeController!;
    expect(controller.activeEntryCount, 1);
    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.checkboxTick);
    expect(painter.targetRect, isNotNull);
    expect(painter.wordSpec, isNull);
    expect(painter.wordImage, isNull);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('unchecking mounts no burst', (tester) async {
    var value = true;
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => KuronCheckbox(
              value: value,
              onChanged: (next) => setState(() => value = next ?? false),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(value, isFalse);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(maybePainterOf(tester), isNull);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('checking in quiet mode mounts no burst', (tester) async {
    var value = false;
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.quiet,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => KuronCheckbox(
              value: value,
              onChanged: (next) => setState(() => value = next ?? false),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    // The state change still happens; only the decoration is suppressed.
    expect(value, isTrue);
    expect(KuronFx.activeController!.activeEntryCount, 0);
    expect(maybePainterOf(tester), isNull);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });

  testWidgets('tapping the list tile toggles with the same anchored burst', (
    tester,
  ) async {
    var value = false;
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => KuronCheckboxListTile(
              title: const Text('Notify me'),
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(KuronCheckboxListTile));
    await tester.pump();

    expect(value, isTrue);
    expect(KuronFx.activeController!.activeEntryCount, 1);
    final painter = painterOf(tester);
    expect(painter.kind, KuronFxKind.checkboxTick);
    expect(painter.targetRect, isNotNull);
    expect(tester.takeException(), isNull);

    await settleAndClose(tester, injected);
  });
}
