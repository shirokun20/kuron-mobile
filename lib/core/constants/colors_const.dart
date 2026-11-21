import 'package:material_ui/material_ui.dart';

// Brand colors extracted from Frame.svg
// Updated 2026-06-24: Warm human palette (physical-object inspired)
class AppColors {
  // Core brand — UNCHANGED (logo identity)
  static const Color brandCoral = Color(0xFFF1958E);
  static const Color brandMuted = Color(0xFFE0827E);
  static const Color brandDusty = Color(0xFF9D555B);
  static const Color brandDark = Color(0xFF1A1A1F);

  // Light theme — warm cream (like aged paper)
  static const Color lightBg = Color(0xFFEFE6DC);
  static const Color lightSurface = Color(0xFFF5EDE4);
  static const Color lightCard = Color(0xFFFCF7F0);
  static const Color lightCardAlt = Color(0xFFFAF3EC);
  static const Color lightBorder = Color(0xFFD6C8BC);
  static const Color lightText = Color(0xFF2E2722);
  static const Color lightTextSub = Color(0xFF7A6E66);
  static const Color lightCoral = Color(0xFFC76A62); // deeper for AA
  static const Color lightNavIndicator = Color(0xFFF0E4DE); // nav pill bg

  // Dark theme — warm dark (library at night)
  static const Color darkBg = Color(0xFF1C1816);
  static const Color darkSurface = Color(0xFF221E1C);
  static const Color darkCard = Color(0xFF2A2522);
  static const Color darkCardAlt = Color(0xFF2E2926);
  static const Color darkBorder = Color(0xFF4A3D36);
  static const Color darkText = Color(0xFFD4CCC4);
  static const Color darkTextSub = Color(0xFF9E948C);

  // AMOLED — pure black, warm text
  static const Color amoledBg = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0C0A08);
  static const Color amoledCard = Color(0xFF12100E);
  static const Color amoledCardAlt = Color(0xFF161412);
  static const Color amoledBorder = Color(0xFF362C28);
  static const Color amoledText = Color(0xFFCCC4BC);
  static const Color amoledTextSub = Color(0xFF8E847C);

  // Note mode — pure monochrome
  static const Color noteBg = Color(0xFFFFFFFF);
  static const Color noteSurface = Color(0xFFF5F5F5);
  static const Color noteCard = Color(0xFFEEEEEE);
  static const Color noteCardAlt = Color(0xFFE0E0E0);
  static const Color noteBorder = Color(0xFFBDBDBD);
  static const Color noteText = Color(0xFF000000);
  static const Color noteTextSub = Color(0xFF757575);

  // New tokens — warm secondary accent
  static const Color warm = Color(0xFFD48A6A);
  static const Color warmMuted = Color(0xFFB87054);

  // Read/completed gold — like vintage bookstore stamp
  static const Color readGold = Color(0xFFC8A06A);
  static const Color readGoldLight = Color(0xFFB89060);

  // Reader backgrounds
  static const Color readerBgDark = Color(0xFF1A1614);
  static const Color readerTextDark = Color(0xFFD0C8C0);
  static const Color readerBgLight = Color(0xFFF5EDE4);
  static const Color readerTextLight = Color(0xFF2E2722);
  static const Color readerBgAmoled = Color(0xFF000000);
  static const Color readerTextAmoled = Color(0xFFCCC4BC);
  static const Color readerBgNote = Color(0xFFFFFFFF);
  static const Color readerTextNote = Color(0xFF000000);

  // Card gradient anchors
  static const Color darkGradientStart = Color(0xFF2A2522);
  static const Color darkGradientEnd = Color(0xFF221E1C);
  static const Color lightGradientStart = Color(0xFFFCF7F0);
  static const Color lightGradientEnd = Color(0xFFF5EDE4);
  static const Color amoledGradientStart = Color(0xFF12100E);
  static const Color amoledGradientEnd = Color(0xFF0C0A08);
  static const Color noteGradientStart = Color(0xFFEEEEEE);
  static const Color noteGradientEnd = Color(0xFFF5F5F5);

  // Semantic — derived from brand
  static const Color primary = brandCoral;
  static const Color primaryContainer = Color(0xFF4A2A28);
  static const Color onPrimaryContainer = Color(0xFFFFD8D4);
  static const Color secondary = warm;
  static const Color secondaryContainer = Color(0xFF3D2022);
  static const Color onSecondaryContainer = Color(0xFFFFD8D4);
  static const Color tertiary = brandMuted;
  static const Color tertiaryContainer = Color(0xFF3A1E20);
  static const Color onTertiaryContainer = Color(0xFFFFD8D4);

  // Status
  static const Color error = Color(0xFFC86858); // muted brick
  static const Color errorContainer = Color(0xFF4A1A1A);
  static const Color success = Color(0xFF8AB87A); // muted leaf green
  static const Color warning = Color(0xFFD4A060);
  static const Color info = Color(0xFF7BB8FF);
}

// Theme extension exposing Kuron-specific colors.
// Access via: `Theme.of(context).extension<KuronColors>()`
class KuronColors extends ThemeExtension<KuronColors> {
  const KuronColors({
    required this.cardGradientStart,
    required this.cardGradientEnd,
    required this.cardBorder,
    required this.readGold,
    required this.readerBg,
    required this.readerText,
  });

  final Color cardGradientStart;
  final Color cardGradientEnd;
  final Color cardBorder;
  final Color readGold;
  final Color readerBg;
  final Color readerText;

  @override
  KuronColors copyWith({
    Color? cardGradientStart,
    Color? cardGradientEnd,
    Color? cardBorder,
    Color? readGold,
    Color? readerBg,
    Color? readerText,
  }) {
    return KuronColors(
      cardGradientStart: cardGradientStart ?? this.cardGradientStart,
      cardGradientEnd: cardGradientEnd ?? this.cardGradientEnd,
      cardBorder: cardBorder ?? this.cardBorder,
      readGold: readGold ?? this.readGold,
      readerBg: readerBg ?? this.readerBg,
      readerText: readerText ?? this.readerText,
    );
  }

  @override
  KuronColors lerp(ThemeExtension<KuronColors>? other, double t) {
    if (other is! KuronColors) return this;
    return KuronColors(
      cardGradientStart: Color.lerp(
        cardGradientStart,
        other.cardGradientStart,
        t,
      )!,
      cardGradientEnd: Color.lerp(cardGradientEnd, other.cardGradientEnd, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      readGold: Color.lerp(readGold, other.readGold, t)!,
      readerBg: Color.lerp(readerBg, other.readerBg, t)!,
      readerText: Color.lerp(readerText, other.readerText, t)!,
    );
  }

  static const dark = KuronColors(
    cardGradientStart: AppColors.darkGradientStart,
    cardGradientEnd: AppColors.darkGradientEnd,
    cardBorder: AppColors.darkBorder,
    readGold: AppColors.readGold,
    readerBg: AppColors.readerBgDark,
    readerText: AppColors.readerTextDark,
  );

  static const light = KuronColors(
    cardGradientStart: AppColors.lightGradientStart,
    cardGradientEnd: AppColors.lightGradientEnd,
    cardBorder: AppColors.lightBorder,
    readGold: AppColors.readGoldLight,
    readerBg: AppColors.readerBgLight,
    readerText: AppColors.readerTextLight,
  );

  static const amoled = KuronColors(
    cardGradientStart: AppColors.amoledGradientStart,
    cardGradientEnd: AppColors.amoledGradientEnd,
    cardBorder: AppColors.amoledBorder,
    readGold: AppColors.readGold,
    readerBg: AppColors.readerBgAmoled,
    readerText: AppColors.readerTextAmoled,
  );

  static const note = KuronColors(
    cardGradientStart: AppColors.noteGradientStart,
    cardGradientEnd: AppColors.noteGradientEnd,
    cardBorder: AppColors.noteBorder,
    readGold: Color(0xFF9E9E9E), // readGoldNote equivalent
    readerBg: AppColors.readerBgNote,
    readerText: AppColors.readerTextNote,
  );

  static const noteDark = KuronColors(
    cardGradientStart: Color(0xFF111111),
    cardGradientEnd: Color(0xFF222222),
    cardBorder: Color(0xFF444444),
    readGold: Color(0xFF666666),
    readerBg: Colors.black,
    readerText: Colors.white,
  );
}
