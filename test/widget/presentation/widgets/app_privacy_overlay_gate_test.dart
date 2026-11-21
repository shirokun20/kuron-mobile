import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/widgets/app_privacy_overlay_gate.dart';
import 'package:nhasixapp/core/services/app_privacy_overlay_service.dart';

void main() {
  group('AppPrivacyOverlayGate', () {
    testWidgets('shows privacy blur when service is obscured', (
      WidgetTester tester,
    ) async {
      final service = AppPrivacyOverlayService();

      await tester.pumpWidget(
        MaterialApp(
          home: AppPrivacyOverlayGate(
            service: service,
            child: const Scaffold(body: ColoredBox(color: Colors.blue)),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);

      service.markBackgroundObscured();
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);

      service.clearObscured();
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}
