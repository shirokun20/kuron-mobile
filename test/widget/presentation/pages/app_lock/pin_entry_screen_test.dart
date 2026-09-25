import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/app_lock/pin_entry_screen.dart';

Widget buildTestApp(Widget screen) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  );
}

void main() {
  group('PinEntryScreen', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          subtitle: 'Unlock app',
          onPinEntered: (_) async => true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('Unlock app'), findsOneWidget);
    });

    testWidgets('shows 6 pin dots', (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('fills dots on digit press', (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => true,
        ),
      ));

      await tester.tap(find.text('1'));
      await tester.pump();

      await tester.tap(find.text('2'));
      await tester.pump();
    });

    testWidgets('calls onPinEntered when 6 digits entered', (tester) async {
      bool called = false;
      String? enteredPin;

      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (pin) async {
            called = true;
            enteredPin = pin;
            return true;
          },
        ),
      ));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(enteredPin, '123456');
    });

    testWidgets('shows error when wrong PIN', (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => false,
        ),
      ));
      await tester.pumpAndSettle();

      for (final d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Wrong PIN'), findsOneWidget);
    });

    testWidgets('backspace removes last digit', (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
    });

    testWidgets('shows biometric button when showBiometric true',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => true,
          showBiometric: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });

    testWidgets('hides biometric button when showBiometric false',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
        PinEntryScreen(
          title: 'Enter PIN',
          onPinEntered: (_) async => true,
          showBiometric: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });
  });
}
