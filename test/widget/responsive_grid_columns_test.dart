import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/utils/responsive_grid_delegate.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

Widget _harness(_MockSettingsCubit cubit, Size size) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          final count = ResponsiveGridDelegate.getColumnCount(
            context,
            cubit,
          );
          return Text('cols:$count', textDirection: TextDirection.ltr);
        },
      ),
    ),
  );
}

void main() {
  late _MockSettingsCubit cubit;

  setUp(() {
    cubit = _MockSettingsCubit();
    when(
      () => cubit.getColumnsForOrientation(any()),
    ).thenReturn(2);
  });

  group('ResponsiveGridDelegate wide screens', () {
    testWidgets('1200dp uses density columns, not the user setting',
        (tester) async {
      await tester.pumpWidget(_harness(cubit, const Size(1200, 800)));

      // (1200 - 32) / 180 = 6.48 -> 6 columns of ~180dp cards.
      expect(find.text('cols:6'), findsOneWidget);
    });

    testWidgets('narrow screens keep the user setting', (tester) async {
      await tester.pumpWidget(_harness(cubit, const Size(390, 844)));

      expect(find.text('cols:2'), findsOneWidget);
    });
  });
}
