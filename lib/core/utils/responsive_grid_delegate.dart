import 'package:flutter/material.dart';
import '../../presentation/cubits/settings/settings_cubit.dart';

// Helper class for creating responsive grid delegates based on user settings
///
// This class provides a centralized way to create grid delegates that respect
// user preferences for column counts in different orientations.
class ResponsiveGridDelegate {
  /// Breakpoint shared with the persistent sidebar and detail panes.
  static const double wideBreakpoint = 900;

  /// Column count for wide screens: a dense card grid sized by target card
  /// width instead of the phone-oriented user setting (which would leave
  /// 2-3 giant stretched columns on desktop).
  static int _wideColumnCount(double effectiveWidth) {
    const double targetCardWidth = 180.0;
    final int raw = (effectiveWidth / targetCardWidth).floor();
    if (raw < 4) return 4;
    if (raw > 8) return 8;
    return raw;
  }

  // Creates a grid delegate with column count based on orientation and user
  // settings. On wide screens the user setting is bypassed (see below).
  static SliverGridDelegate createGridDelegate(
    BuildContext context,
    SettingsCubit settingsCubit, {
    double childAspectRatio = 0.7,
    double crossAxisSpacing = 8.0,
    double mainAxisSpacing = 8.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final int userColumns = settingsCubit.getColumnsForOrientation(isPortrait);

    // Adaptive safeguards for small screens (floating windows)
    // Ensure we don't try to squeeze too many columns into a tiny width
    const double minItemWidth = 120.0;
    final double screenWidth = mediaQuery.size.width;

    // Calculate max possible columns that fit with minItemWidth
    // Account for padding (approx 32dp total horizontal padding)
    final double effectiveWidth = screenWidth - 32.0;

    // Wide screens: dense card grid instead of the phone-oriented setting.
    if (screenWidth > wideBreakpoint) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _wideColumnCount(effectiveWidth),
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      );
    }
    final int maxColumnsByWidth = (effectiveWidth / minItemWidth).floor();

    // Clamp columns: must be at least 1, and no more than what fits physically
    // But prioritize user setting if it's reasonable (<= maxColumnsByWidth)
    final int columns =
        maxColumnsByWidth > 0 ? userColumns.clamp(1, maxColumnsByWidth) : 1;

    // Use minimum 1 column even if width is tiny (to avoid 0 columns error)
    final int finalColumns = columns > 0 ? columns : 1;

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: finalColumns,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  // Creates a standard grid delegate for use with GridView.builder
  ///
  // [context] - BuildContext for accessing MediaQuery
  // [settingsCubit] - SettingsCubit for accessing user column preferences
  // [childAspectRatio] - Optional override for child aspect ratio (defaults to 0.7)
  // [crossAxisSpacing] - Optional override for cross axis spacing (defaults to 8)
  // [mainAxisSpacing] - Optional override for main axis spacing (defaults to 8)
  static SliverGridDelegateWithFixedCrossAxisCount createStandardGridDelegate(
    BuildContext context,
    SettingsCubit settingsCubit, {
    double childAspectRatio = 0.7,
    double crossAxisSpacing = 8.0,
    double mainAxisSpacing = 8.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final int userColumns = settingsCubit.getColumnsForOrientation(isPortrait);

    // Adaptive safeguards for small screens
    const double minItemWidth = 120.0;
    final double screenWidth = mediaQuery.size.width;
    final double effectiveWidth = screenWidth - 32.0;

    // Wide screens: dense card grid instead of the phone-oriented setting.
    if (screenWidth > wideBreakpoint) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _wideColumnCount(effectiveWidth),
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      );
    }

    final int maxColumnsByWidth = (effectiveWidth / minItemWidth).floor();
    final int columns =
        maxColumnsByWidth > 0 ? userColumns.clamp(1, maxColumnsByWidth) : 1;

    final int finalColumns = columns > 0 ? columns : 1;

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: finalColumns,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  // Get column count directly without creating delegate
  ///
  // [context] - BuildContext for accessing MediaQuery
  // [settingsCubit] - SettingsCubit for accessing user column preferences
  static int getColumnCount(
    BuildContext context,
    SettingsCubit settingsCubit,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final int userColumns = settingsCubit.getColumnsForOrientation(isPortrait);

    // Apply same safeguarding logic
    const double minItemWidth = 120.0;
    final double screenWidth = mediaQuery.size.width;
    final double effectiveWidth = screenWidth - 32.0;

    // Wide screens: dense card grid instead of the phone-oriented setting.
    if (screenWidth > wideBreakpoint) {
      return _wideColumnCount(effectiveWidth);
    }

    final int maxColumnsByWidth = (effectiveWidth / minItemWidth).floor();

    final int columns =
        maxColumnsByWidth > 0 ? userColumns.clamp(1, maxColumnsByWidth) : 1;

    return columns > 0 ? columns : 1;
  }
}
