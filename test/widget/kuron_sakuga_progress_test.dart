import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/utils/kuron_motion_policy.dart';
import 'package:nhasixapp/presentation/widgets/kuron_sakuga_progress.dart';

import 'kuron_fx_p2_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpFxChannel);
  tearDown(tearDownFxChannel);

  testWidgets('renders eased sakuga progress and storm cloud when active', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.standard,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: KuronSakugaProgressBar(
              progress: 0.45,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              color: Colors.pink,
              backgroundColor: Colors.black12,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(KuronSakugaProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });

  testWidgets('quiet mode renders static bar without repeating ticker', (
    tester,
  ) async {
    final injected = await pumpFxApp(
      tester,
      mode: KuronFxMode.quiet,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: KuronSakugaProgressBar(
              progress: 0.6,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              color: Colors.pink,
              backgroundColor: Colors.black12,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KuronSakugaProgressBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleAndClose(tester, injected);
  });
}
