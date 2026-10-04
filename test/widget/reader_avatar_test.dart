import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/kuro_tier_avatar.dart';
import 'package:nhasixapp/presentation/widgets/reader_avatar.dart';

void main() {
  test('backgroundFor keeps one pastel disc per tier', () {
    expect(
        ReaderAvatar.backgroundFor(ReaderTier.santai), const Color(0xFFFFDFBF));
    expect(ReaderAvatar.backgroundFor(ReaderTier.kutubuku),
        const Color(0xFFC0AEDE));
    expect(
        ReaderAvatar.backgroundFor(ReaderTier.otaku), const Color(0xFFB6E3F4));
    expect(
        ReaderAvatar.backgroundFor(ReaderTier.resi), const Color(0xFFFFD5DC));
    expect(
        ReaderAvatar.backgroundFor(ReaderTier.shaker), const Color(0xFFD1D4F9));
  });

  testWidgets('every tier renders its dedicated avatar at the right size',
      (tester) async {
    for (final tier in ReaderTier.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReaderAvatar(tier: tier, radius: 20)),
        ),
      );

      final avatar = tester.widget<KuroTierAvatar>(find.byType(KuroTierAvatar));
      expect(avatar.tier, tier);
      expect(avatar.size, 40);
    }
  });

  testWidgets('tier names localize per app locale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: Scaffold(body: _TierNameProbe()),
      ),
    );
    await tester.pump();

    expect(find.text('Certified Shaker'), findsOneWidget);
    expect(find.text('Manga Sage'), findsOneWidget);
  });
}

class _TierNameProbe extends StatelessWidget {
  const _TierNameProbe();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(readerTierName(l10n, ReaderTier.shaker)),
        Text(readerTierName(l10n, ReaderTier.resi)),
      ],
    );
  }
}
