import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nhasixapp/core/constants/colors_const.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/theme/theme_cubit.dart';

/// User-facing intensity of transient Kuron effects.
///
/// `quiet` is the default everywhere and is the only mode allowed in the
/// reader: a reading session is never interrupted by particles or stickers.
enum KuronFxMode { quiet, standard, satire }

extension KuronFxModeStorage on KuronFxMode {
  /// Stable value persisted in [UserPreferences.kuronFxMode].
  String get storageValue => name;

  /// Unknown/legacy values degrade to `quiet` (no effects, no surprises).
  static KuronFxMode fromStorage(String? value) =>
      KuronFxMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => KuronFxMode.quiet,
      );
}

/// Single source of truth for motion gating across Kuro loading widgets and
/// the `kuron_fx` burst overlay.
abstract final class KuronMotionPolicy {
  /// OS-level reduced motion (`prefers-reduced-motion` / Android animation
  /// scale). Infinite loops must stop when this is true.
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Note / Note Dark are strict monochrome disguise themes. Detected from
  /// [ThemeCubit] when present (it is mounted at app root), with a color-based
  /// fallback so isolated widgets and widget tests behave the same way.
  static bool isNoteTheme(BuildContext context, {bool listen = true}) {
    try {
      final theme =
          (listen ? context.watch<ThemeCubit>() : context.read<ThemeCubit>())
              .currentTheme;
      if (theme == 'note' || theme == 'note_dark') return true;
    } catch (_) {
      // No ThemeCubit in this subtree (e.g. an isolated widget test).
    }
    final colorScheme = Theme.of(context).colorScheme;
    // Both note themes use dedicated neutral surfaces no other theme uses.
    if (colorScheme.surface == AppColors.noteSurface) return true;
    return colorScheme.surface == const Color(0xFF111111) &&
        colorScheme.onSurface == Colors.white;
  }

  /// The setting selected by the user; defaults to `quiet` when settings are
  /// not loaded or the cubit is unavailable.
  static KuronFxMode configuredMode(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      final state =
          (listen
                  ? context.watch<SettingsCubit>()
                  : context.read<SettingsCubit>())
              .state;
      if (state is SettingsLoaded) {
        return KuronFxModeStorage.fromStorage(state.preferences.kuronFxMode);
      }
    } catch (_) {
      // No SettingsCubit in this subtree.
    }
    return KuronFxMode.quiet;
  }

  /// Resolve the mode that actually drives an effect.
  ///
  /// Effects are hard-off in the reader, under reduced motion, and in note
  /// themes regardless of the stored preference.
  static KuronFxMode effectiveMode(
    BuildContext context, {
    bool isReader = false,
    bool listen = true,
  }) {
    if (isReader ||
        reducedMotion(context) ||
        isNoteTheme(context, listen: listen)) {
      return KuronFxMode.quiet;
    }
    return configuredMode(context, listen: listen);
  }

  /// Whether an ambient infinite animation (mascot idle, thumb shimmer,
  /// splash dots) may run.
  static bool ambientAnimationsEnabled(BuildContext context) =>
      !reducedMotion(context);
}
