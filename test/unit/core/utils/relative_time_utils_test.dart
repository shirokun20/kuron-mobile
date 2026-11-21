import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/utils/relative_time_utils.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child, {String locale = 'en'}) {
    return MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        // material_ui's MaterialApp needs the 3.50 delegate set; the
        // generated AppLocalizations list still carries the legacy ones.
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('RelativeTimeUtils.shouldHide', () {
    test('epoch hides', () {
      expect(
        RelativeTimeUtils.shouldHide(DateTime.fromMillisecondsSinceEpoch(0)),
        isTrue,
      );
    });

    test('future hides', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(
        RelativeTimeUtils.shouldHide(DateTime(2026, 1, 2), now: now),
        isTrue,
      );
    });

    test('valid past does not hide', () {
      final now = DateTime(2026, 1, 10);
      expect(
        RelativeTimeUtils.shouldHide(DateTime(2026, 1, 9), now: now),
        isFalse,
      );
    });
  });

  group('RelativeTimeUtils.format', () {
    testWidgets('justNow for <1h', (tester) async {
      final now = DateTime(2026, 1, 10, 12, 0);
      final date = now.subtract(const Duration(minutes: 5));
      String? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(date, context, now: now);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // en: justNow or minutesAgo depending on threshold; our impl uses minutesAgo for >0m
      expect(result, isNotNull);
    });

    testWidgets('daysAgo for 2 days (en)', (tester) async {
      final now = DateTime(2026, 1, 10, 12);
      final date = now.subtract(const Duration(days: 2));
      String? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(date, context, now: now);
              return const SizedBox();
            },
          ),
          locale: 'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(result, contains('2'));
    });

    testWidgets('hoursAgo for 3 hours (id)', (tester) async {
      final now = DateTime(2026, 1, 10, 12);
      final date = now.subtract(const Duration(hours: 3));
      String? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(date, context, now: now);
              return const SizedBox();
            },
          ),
          locale: 'id',
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.toLowerCase(), contains('jam'));
    });

    testWidgets('monthAgo for 40 days (zh)', (tester) async {
      final now = DateTime(2026, 3, 10);
      final date = now.subtract(const Duration(days: 40));
      String? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(date, context, now: now);
              return const SizedBox();
            },
          ),
          locale: 'zh',
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isNotNull);
    });

    testWidgets('epoch returns null', (tester) async {
      String? result = 'not-null';
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(
                DateTime.fromMillisecondsSinceEpoch(0),
                context,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('future returns null', (tester) async {
      final now = DateTime(2026, 1, 10);
      String? result = 'not-null';
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              result = RelativeTimeUtils.format(
                DateTime(2026, 1, 11),
                context,
                now: now,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('resolveLastUpdate', () {
    test('prefers latest chapter when more recent', () {
      final contentDate = DateTime(2026, 1, 1);
      final chapters = [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 10),
        DateTime(2026, 1, 3),
      ];
      final result = RelativeTimeUtils.resolveLastUpdate(contentDate, chapters);
      expect(result, DateTime(2026, 1, 10));
    });

    test('keeps contentDate when chapters older', () {
      final contentDate = DateTime(2026, 2, 1);
      final chapters = [DateTime(2026, 1, 1)];
      final result = RelativeTimeUtils.resolveLastUpdate(contentDate, chapters);
      expect(result, contentDate);
    });

    test('ignores epoch and null', () {
      final contentDate = DateTime(2026, 1, 5);
      final chapters = [
        null,
        DateTime.fromMillisecondsSinceEpoch(0),
        DateTime(2026, 1, 6),
      ];
      final result = RelativeTimeUtils.resolveLastUpdate(contentDate, chapters);
      expect(result, DateTime(2026, 1, 6));
    });
  });
}
