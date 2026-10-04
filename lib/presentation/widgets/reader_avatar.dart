import 'package:flutter/material.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/kuro_tier_avatar.dart';

// Tier avatar rendered from the dedicated Kuro tier painter — zero bundled
// PNGs (see assets/avatars/README.md). API is tier-based so the render
// can change without touching callers.
class ReaderAvatar extends StatelessWidget {
  const ReaderAvatar({
    super.key,
    required this.tier,
    this.radius = 20,
  });

  final ReaderTier tier;
  final double radius;

  // Pastel disc behind the black cat — readable on light/dark/amoled.
  static Color backgroundFor(ReaderTier tier) {
    return switch (tier) {
      ReaderTier.santai => const Color(0xFFFFDFBF),
      ReaderTier.kutubuku => const Color(0xFFC0AEDE),
      ReaderTier.otaku => const Color(0xFFB6E3F4),
      ReaderTier.resi => const Color(0xFFFFD5DC),
      ReaderTier.shaker => const Color(0xFFD1D4F9),
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundFor(tier),
        child: KuroTierAvatar(tier: tier, size: size),
      ),
    );
  }
}

/// Localized tier display name. Kept next to the widget so drawer and any
/// future caller share one mapping.
String readerTierName(AppLocalizations l10n, ReaderTier tier) {
  return switch (tier) {
    ReaderTier.santai => l10n.readerTierSantai,
    ReaderTier.kutubuku => l10n.readerTierKutubuku,
    ReaderTier.otaku => l10n.readerTierOtaku,
    ReaderTier.resi => l10n.readerTierResi,
    ReaderTier.shaker => l10n.readerTierShaker,
  };
}
