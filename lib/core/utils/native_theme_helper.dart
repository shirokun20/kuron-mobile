import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';
import 'package:nhasixapp/core/constants/colors_const.dart';

// Helper to extract current active theme colors as Hex strings
// for passing to native Android activities via MethodChannels.
class NativeThemeHelper {
  static String? get backgroundColorHex {
    try {
      final theme = getIt<ThemeCubit>().state.themeData;
      return _colorToHex(theme.scaffoldBackgroundColor);
    } catch (_) {
      return null;
    }
  }

  static String? get textColorHex {
    try {
      final theme = getIt<ThemeCubit>().state.themeData;
      final color =
          theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
      return _colorToHex(color);
    } catch (_) {
      return null;
    }
  }

  static String? get readerBackgroundColorHex {
    try {
      final theme = getIt<ThemeCubit>().state.themeData;
      final kuronColors = theme.extension<KuronColors>();
      return _colorToHex(
        kuronColors?.readerBg ?? theme.scaffoldBackgroundColor,
      );
    } catch (_) {
      return null;
    }
  }

  static String? get readerTextColorHex {
    try {
      final theme = getIt<ThemeCubit>().state.themeData;
      final kuronColors = theme.extension<KuronColors>();
      final fallbackColor =
          theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
      return _colorToHex(kuronColors?.readerText ?? fallbackColor);
    } catch (_) {
      return null;
    }
  }

  static String _colorToHex(Color color) {
    // toARGB32() returns AARRGGBB
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
