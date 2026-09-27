import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/reader_avatar.dart';

void main() {
  test('assetFor maps every tier to its bundled png', () {
    expect(ReaderAvatar.assetFor(ReaderTier.santai),
        'assets/avatars/tier-santai.png');
    expect(ReaderAvatar.assetFor(ReaderTier.kutubuku),
        'assets/avatars/tier-kutubuku.png');
    expect(ReaderAvatar.assetFor(ReaderTier.otaku),
        'assets/avatars/tier-otaku.png');
    expect(ReaderAvatar.assetFor(ReaderTier.resi),
        'assets/avatars/tier-resi.png');
    expect(ReaderAvatar.assetFor(ReaderTier.shaker),
        'assets/avatars/tier-shaker.png');
  });

  testWidgets('avatar renders the tier image at the right size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderAvatar(tier: ReaderTier.shaker, radius: 20),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/avatars/tier-shaker.png');
    expect(image.width, 40);
    expect(image.height, 40);
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
