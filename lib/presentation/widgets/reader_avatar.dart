import 'package:flutter/material.dart';
import 'package:nhasixapp/domain/entities/reader_badge.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';

// Tier avatar from bundled CC0 assets (see assets/avatars/README.md).
// API is tier-based so the render can change without touching callers.
class ReaderAvatar extends StatelessWidget {
  const ReaderAvatar({
    super.key,
    required this.tier,
    this.radius = 20,
  });

  final ReaderTier tier;
  final double radius;

  static String assetFor(ReaderTier tier) {
    return 'assets/avatars/tier-${tier.name}.png';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = radius * 2;
    return ClipOval(
      child: Image.asset(
        assetFor(tier),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => Container(
          width: size,
          height: size,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outlined,
            size: radius,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
