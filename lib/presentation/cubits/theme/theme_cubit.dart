import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors_const.dart' show AppColors, KuronColors;
import '../../../core/constants/design_tokens.dart';
import '../settings/settings_cubit.dart';

part 'theme_state.dart';

// Cubit for managing app theme changes
// Listens to SettingsCubit and provides reactive ThemeData
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit({
    required this._settingsCubit,
    required this._logger,
  })  : super(ThemeState.initial()) {
    // Listen to settings changes
    _settingsSubscription = _settingsCubit.stream.listen(_onSettingsChanged);

    // Initialize with current settings
    _updateThemeFromSettings(_settingsCubit.state);
  }

  final SettingsCubit _settingsCubit;
  final Logger _logger;
  late final StreamSubscription _settingsSubscription;

  // Update theme when settings change
  void _onSettingsChanged(SettingsState settingsState) {
    _updateThemeFromSettings(settingsState);
  }

  // Update theme data based on settings
  void _updateThemeFromSettings(SettingsState settingsState) {
    if (settingsState is SettingsLoaded) {
      final preferences = settingsState.preferences;
      final themeData = _createThemeData(preferences.theme);

      emit(ThemeState(
        themeData: themeData,
        themeMode: _getThemeMode(preferences.theme),
        currentTheme: preferences.theme,
        lastUpdated: DateTime.now(),
      ));

      _logger.i('Theme updated to: ${preferences.theme}');
    }
  }

  // Create ThemeData based on theme setting
  ThemeData _createThemeData(String theme) {
    switch (theme) {
      case 'light':
        return _createLightTheme();
      case 'dark':
        return _createDarkTheme();
      case 'amoled':
        return _createAmoledTheme();
      case 'note':
        return _createNoteTheme();
      case 'note_dark':
        return _createNoteDarkTheme();
      default:
        return _createDarkTheme();
    }
  }

  // Get ThemeMode for MaterialApp
  ThemeMode _getThemeMode(String theme) {
    switch (theme) {
      case 'light':
      case 'note':
        return ThemeMode.light;
      case 'dark':
      case 'amoled':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  // Text theme using Playfair Display (headings) + Inter (body).
  // NOTE (google_fonts 9): `*TextTheme()` helpers now use material_ui's
  // TextTheme (distinct type from flutter's), so fonts are applied per
  // TextStyle instead — TextStyle is shared via package:flutter/widgets.
  TextTheme _googleFontsTextTheme([TextTheme? base]) {
    final b = base ?? ThemeData.light().textTheme;
    TextStyle? playfair(TextStyle? s) =>
        s == null ? null : GoogleFonts.playfairDisplay(textStyle: s);
    return b.copyWith(
      displayLarge: playfair(b.displayLarge),
      displayMedium: playfair(b.displayMedium),
      displaySmall: playfair(b.displaySmall),
      headlineLarge: playfair(b.headlineLarge),
      headlineMedium: playfair(b.headlineMedium),
      headlineSmall: playfair(b.headlineSmall),
      titleLarge: GoogleFonts.inter(textStyle: b.titleLarge),
      titleMedium: GoogleFonts.inter(textStyle: b.titleMedium),
      titleSmall: GoogleFonts.inter(textStyle: b.titleSmall),
      bodyLarge: GoogleFonts.inter(textStyle: b.bodyLarge),
      bodyMedium: GoogleFonts.inter(textStyle: b.bodyMedium),
      bodySmall: GoogleFonts.inter(textStyle: b.bodySmall),
      labelLarge: GoogleFonts.inter(textStyle: b.labelLarge),
      labelMedium: GoogleFonts.inter(textStyle: b.labelMedium),
      labelSmall: GoogleFonts.inter(textStyle: b.labelSmall),
    );
  }

  // Create light theme — warm cream, aged paper feel
  ThemeData _createLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      textTheme: _googleFontsTextTheme(),
      extensions: const [KuronColors.light],
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightCoral,
        onPrimary: Colors.white,
        primaryContainer: AppColors.warmMuted,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.warmMuted,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFF0E4DE),
        onSecondaryContainer: AppColors.warm,
        tertiary: AppColors.warmMuted,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFEDE0DF),
        onTertiaryContainer: AppColors.warm,
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightText,
        onSurfaceVariant: AppColors.lightTextSub,
        surfaceContainerHighest: AppColors.lightCard,
        outline: AppColors.lightBorder,
        outlineVariant: Color(0xFFE0D4CA),
        shadow: Color(0x1A000000),
        scrim: Colors.black54,
        inverseSurface: AppColors.brandDark,
        onInverseSurface: AppColors.lightBg,
        inversePrimary: AppColors.lightCoral,
      ),
      scaffoldBackgroundColor: AppColors.lightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.lightText,
        elevation: DesignTokens.elevationNone,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: DesignTokens.elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.lightSurface,
        textColor: AppColors.lightText,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightCard,
        indicatorColor: AppColors.lightNavIndicator,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.lightCoral,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColors.lightTextSub,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.lightCoral);
          }
          return const IconThemeData(color: AppColors.lightTextSub);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lightCoral,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationMd,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.lightCoral, width: 2),
        ),
      ),
    );
  }

  // Create dark theme — warm library night feel
  ThemeData _createDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      textTheme: _googleFontsTextTheme(ThemeData.dark().textTheme),
      extensions: const [KuronColors.dark],
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandCoral,
        onPrimary: Colors.white,
        primaryContainer: AppColors.warmMuted,
        onPrimaryContainer: Color(0xFFFFD8D4),
        secondary: AppColors.warm,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFF3A2824),
        onSecondaryContainer: Color(0xFFFFD8D4),
        tertiary: AppColors.warmMuted,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFF31201E),
        onTertiaryContainer: Color(0xFFFFD8D4),
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFF3A1A1A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkText,
        onSurfaceVariant: AppColors.darkTextSub,
        surfaceContainerHighest: AppColors.darkCard,
        outline: AppColors.darkBorder,
        outlineVariant: Color(0xFF38322E),
        shadow: Color(0x30000000),
        scrim: Colors.black87,
        inverseSurface: AppColors.lightBg,
        onInverseSurface: AppColors.brandDark,
        inversePrimary: AppColors.brandCoral,
      ),
      scaffoldBackgroundColor: AppColors.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.darkText,
        elevation: DesignTokens.elevationNone,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: DesignTokens.elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.darkSurface,
        textColor: AppColors.darkText,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.darkCard,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.brandCoral,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColors.darkTextSub,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.brandCoral);
          }
          return const IconThemeData(color: AppColors.darkTextSub);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandCoral,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationMd,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.brandCoral, width: 2),
        ),
      ),
    );
  }

  // Create AMOLED theme — pure black, warm off-white text
  ThemeData _createAmoledTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      textTheme: _googleFontsTextTheme(ThemeData.dark().textTheme),
      extensions: const [KuronColors.amoled],
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandCoral,
        onPrimary: Colors.white,
        primaryContainer: AppColors.warmMuted,
        onPrimaryContainer: Color(0xFFFFD8D4),
        secondary: AppColors.warm,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFF2A1518),
        onSecondaryContainer: Color(0xFFFFD8D4),
        tertiary: AppColors.warmMuted,
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFF251214),
        onTertiaryContainer: Color(0xFFFFD8D4),
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFF2A0A0A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: AppColors.amoledSurface,
        onSurface: AppColors.amoledText,
        onSurfaceVariant: AppColors.amoledTextSub,
        surfaceContainerHighest: AppColors.amoledCard,
        outline: AppColors.amoledBorder,
        outlineVariant: Color(0xFF1E1A18),
        shadow: Color(0x40000000),
        scrim: Colors.black,
        inverseSurface: AppColors.lightBg,
        onInverseSurface: AppColors.brandDark,
        inversePrimary: AppColors.brandCoral,
      ),
      scaffoldBackgroundColor: AppColors.amoledBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.amoledBg,
        foregroundColor: AppColors.amoledText,
        elevation: DesignTokens.elevationNone,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.amoledCard,
        elevation: DesignTokens.elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: AppColors.amoledBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.amoledSurface,
        textColor: AppColors.amoledText,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.amoledBorder,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.amoledBg,
        indicatorColor: AppColors.amoledCard,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.brandCoral,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColors.amoledTextSub,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.brandCoral);
          }
          return const IconThemeData(color: AppColors.amoledTextSub);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandCoral,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationSm,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.amoledSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.amoledBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.amoledBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.brandCoral, width: 2),
        ),
      ),
    );
  }

  // Create Dark Note theme — pure monochrome B&W inverted
  ThemeData _createNoteDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      textTheme: _googleFontsTextTheme(ThemeData.dark().textTheme),
      extensions: const [KuronColors.noteDark],
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        onPrimary: Colors.black,
        primaryContainer: Color(0xFF222222),
        onPrimaryContainer: Colors.white,
        secondary: Colors.white,
        onSecondary: Colors.black,
        secondaryContainer: Color(0xFF222222),
        onSecondaryContainer: Colors.white,
        tertiary: Color(0xFF888888),
        onTertiary: Colors.black,
        tertiaryContainer: Color(0xFF222222),
        onTertiaryContainer: Colors.white,
        error: Colors.white,
        onError: Colors.black,
        errorContainer: Colors.white,
        onErrorContainer: Colors.black,
        surface: Color(0xFF111111),
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFF888888),
        surfaceContainerHighest: Color(0xFF222222),
        outline: Color(0xFF444444),
        outlineVariant: Color(0xFF222222),
        shadow: Colors.transparent,
        scrim: Colors.black87,
        inverseSurface: Colors.white,
        onInverseSurface: Colors.black,
        inversePrimary: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationNone,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF111111),
        elevation: DesignTokens.elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: Color(0xFF444444), width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Color(0xFF111111),
        textColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF444444),
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF111111),
        indicatorColor: const Color(0xFF333333),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: Color(0xFF888888),
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: Color(0xFF888888));
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: DesignTokens.elevationMd,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111111),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: Color(0xFF444444)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: Color(0xFF444444)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  // Create Note theme — pure monochrome B&W
  ThemeData _createNoteTheme() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      textTheme: _googleFontsTextTheme(ThemeData.light().textTheme),
      extensions: const [KuronColors.note],
      colorScheme: const ColorScheme.light(
        primary: AppColors.noteText,
        onPrimary: Colors.white,
        primaryContainer: AppColors.noteCardAlt,
        onPrimaryContainer: Colors.black,
        secondary: AppColors.noteText,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.noteCardAlt,
        onSecondaryContainer: Colors.black,
        tertiary: AppColors.noteTextSub,
        onTertiary: Colors.white,
        tertiaryContainer: AppColors.noteCardAlt,
        onTertiaryContainer: Colors.black,
        error: Colors.black, // No colors allowed
        onError: Colors.white,
        errorContainer: Colors.black,
        onErrorContainer: Colors.white,
        surface: AppColors.noteSurface,
        onSurface: AppColors.noteText,
        onSurfaceVariant: AppColors.noteTextSub,
        surfaceContainerHighest: AppColors.noteCard,
        outline: AppColors.noteBorder,
        outlineVariant: AppColors.noteCardAlt,
        shadow: Color(0x40000000),
        scrim: Colors.black,
        inverseSurface: AppColors.noteText,
        onInverseSurface: AppColors.noteBg,
        inversePrimary: AppColors.noteText,
      ),
      scaffoldBackgroundColor: AppColors.noteBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.noteBg,
        foregroundColor: AppColors.noteText,
        elevation: DesignTokens.elevationNone,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.noteCard,
        elevation: DesignTokens.elevationNone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: AppColors.noteBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.noteSurface,
        textColor: AppColors.noteText,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.noteBorder,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.noteBg,
        indicatorColor: AppColors.noteCard,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.noteText,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return const TextStyle(
            color: AppColors.noteTextSub,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.noteText);
          }
          return const IconThemeData(color: AppColors.noteTextSub);
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.noteText,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationSm,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.noteSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.noteBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.noteBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          borderSide: const BorderSide(color: AppColors.noteText, width: 2),
        ),
      ),
    );
  }

  // Force theme update
  void updateTheme() {
    _updateThemeFromSettings(_settingsCubit.state);
  }

  // Get current theme name
  String? get currentTheme {
    final currentState = state;
    return currentState.currentTheme;
  }

  // Check if current theme is dark
  bool get isDark {
    final theme = currentTheme;
    return theme == 'dark' || theme == 'amoled';
  }

  // Check if current theme is AMOLED
  bool get isAmoled {
    return currentTheme == 'amoled';
  }

  @override
  Future<void> close() {
    _settingsSubscription.cancel();
    return super.close();
  }
}
