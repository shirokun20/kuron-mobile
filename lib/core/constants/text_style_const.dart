import 'package:material_ui/material_ui.dart';

// Text style constants for consistent typography throughout the app
// NOTE: Text colors are intentionally NOT specified here - they should be
// provided via .copyWith(color: ...) or inherited from the Theme.
// This ensures proper light/dark theme support.
class TextStyleConst {
  // ===== WEIGHT-BASED STYLES =====

  static TextStyle styleLight({double size = 14}) {
    return TextStyle(fontSize: size, fontWeight: FontWeight.w300, height: 1.4);
  }

  static TextStyle styleRegular({double size = 14}) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.normal,
      height: 1.4,
    );
  }

  static TextStyle styleMedium({double size = 14}) {
    return TextStyle(fontSize: size, fontWeight: FontWeight.w500, height: 1.4);
  }

  static TextStyle styleSemiBold({double size = 14}) {
    return TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: 1.4);
  }

  static TextStyle styleBold({double size = 14}) {
    return TextStyle(fontSize: size, fontWeight: FontWeight.w700, height: 1.4);
  }

  static TextStyle styleExtraBold({double size = 14}) {
    return TextStyle(fontSize: size, fontWeight: FontWeight.w800, height: 1.4);
  }

  // ===== SEMANTIC STYLES (inherit color from theme) =====

  // Heading styles for titles and headers
  static TextStyle get headingLarge => styleBold(size: 24);
  static TextStyle get headingMedium => styleSemiBold(size: 20);
  static TextStyle get headingSmall => styleMedium(size: 18);

  // Body text styles for content
  static TextStyle get bodyLarge => styleRegular(size: 16);
  static TextStyle get bodyMedium => styleRegular(size: 14);
  static TextStyle get bodySmall => styleRegular(size: 12);

  // Caption and label styles
  static TextStyle get caption => styleLight(size: 12);
  static TextStyle get label => styleMedium(size: 12);
  static TextStyle get overline => styleRegular(size: 10);

  // ===== COMPONENT-SPECIFIC STYLES =====

  // Content card styles
  static TextStyle get contentTitle => styleSemiBold(size: 16);
  static TextStyle get contentSubtitle => styleLight(size: 12);
  static TextStyle get contentTag => styleRegular(size: 11);

  // Button styles
  static TextStyle get buttonLarge => styleMedium(size: 16);
  static TextStyle get buttonMedium => styleMedium(size: 14);
  static TextStyle get buttonSmall => styleMedium(size: 12);

  // Navigation styles
  static TextStyle get navigationLabel => styleMedium(size: 14);
  static TextStyle get navigationActive => styleSemiBold(size: 14);

  // Loading and placeholder styles
  static TextStyle get loadingText => styleRegular(size: 14);
  static TextStyle get placeholderText => styleLight(size: 14);

  // Status styles (use with appropriate theme colors)
  static TextStyle get statusSuccess => styleMedium(size: 14);
  static TextStyle get statusWarning => styleMedium(size: 14);
  static TextStyle get statusError => styleMedium(size: 14);

  // ===== UTILITY METHODS =====

  // Get text style with custom color while maintaining other properties
  static TextStyle withColor(TextStyle baseStyle, Color color) {
    return baseStyle.copyWith(color: color);
  }

  // Get text style with custom size while maintaining other properties
  static TextStyle withSize(TextStyle baseStyle, double size) {
    return baseStyle.copyWith(fontSize: size);
  }

  // Get text style with opacity
  static TextStyle withOpacity(TextStyle baseStyle, double opacity) {
    return baseStyle.copyWith(
      color: baseStyle.color?.withValues(alpha: opacity),
    );
  }

  // ===== MATERIAL DESIGN 3 TEXT STYLES =====

  // Display text styles (largest)
  static TextStyle get displayLarge => styleBold(size: 57);
  static TextStyle get displayMedium => styleBold(size: 45);
  static TextStyle get displaySmall => styleBold(size: 36);

  // Headline text styles
  static TextStyle get headlineLarge => styleBold(size: 32);
  static TextStyle get headlineMedium => styleSemiBold(size: 28);
  static TextStyle get headlineSmall => styleSemiBold(size: 24);

  // Title text styles
  static TextStyle get titleLarge => styleSemiBold(size: 22);
  static TextStyle get titleMedium => styleMedium(size: 16);
  static TextStyle get titleSmall => styleMedium(size: 14);

  // Label text styles
  static TextStyle get labelLarge => styleMedium(size: 14);
  static TextStyle get labelMedium => styleMedium(size: 12);
  static TextStyle get labelSmall => styleMedium(size: 11);
}
