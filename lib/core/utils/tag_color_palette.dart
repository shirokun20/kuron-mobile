import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/core/constants/colors_const.dart';

// Resolves theme-aware tag colors for UI chips and labels.
///
// Light mode uses warm accent tones that fit the app theme.
// Dark mode keeps muted, theme-aligned tones for readability.
// Unknown tag types are mapped deterministically so they stay distinct.
class TagColorPalette {
  static const Map<String, Color> _lightColors = <String, Color>{
    'artist': Color(0xFFB8655E),
    'character': Color(0xFF4F7FB8),
    'parody': Color(0xFFAE6D67),
    'group': Color(0xFFA85A5A),
    'language': Color(0xFFB8873B),
    'category': Color(0xFF7D7269),
    'uploader': Color(0xFF5FA383),
    'female': Color(0xFFB85F87),
    'male': Color(0xFF5A86C2),
    'other': Color(0xFF8A6B5C),
    'misc': Color(0xFF8B7C57),
    'tag': Color(0xFFBF6C63),
  };

  static const Map<String, Color> _darkColors = <String, Color>{
    'artist': AppColors.brandCoral,
    'character': AppColors.brandMuted,
    'parody': AppColors.brandDusty,
    'group': Color(0xFFB77A74),
    'language': Color(0xFFC2A46E),
    'category': Color(0xFF8A847E),
    'uploader': Color(0xFF6F9F87),
    'female': Color(0xFFC98A9B),
    'male': Color(0xFF7FA5C9),
    'other': Color(0xFF7E726D),
    'misc': Color(0xFF9B8F67),
    'tag': Color(0xFFB8776D),
  };

  static const List<Color> _lightFallbackColors = <Color>[
    Color(0xFFBF6C63),
    Color(0xFF5A86C2),
    Color(0xFFAE6D67),
    Color(0xFFB55A5A),
    Color(0xFFB8873B),
    Color(0xFF5FA383),
    Color(0xFF8A6B5C),
    Color(0xFF7D7269),
  ];

  static const List<Color> _darkFallbackColors = <Color>[
    AppColors.brandCoral,
    AppColors.brandMuted,
    AppColors.brandDusty,
    Color(0xFFC2A46E),
    Color(0xFF6F9F87),
    Color(0xFF7FA5C9),
    Color(0xFF9B8F67),
    Color(0xFFB8776D),
  ];

  static Color resolve(String tagType, {required Brightness brightness}) {
    final normalized = tagType.trim().toLowerCase();
    if (normalized.isEmpty) {
      return brightness == Brightness.dark
          ? _darkFallbackColors.first
          : _lightFallbackColors.first;
    }

    final fixed = brightness == Brightness.dark
        ? _darkColors[normalized]
        : _lightColors[normalized];
    if (fixed != null) {
      return fixed;
    }

    final palette = brightness == Brightness.dark
        ? _darkFallbackColors
        : _lightFallbackColors;
    final index = _stableHash(normalized) % palette.length;
    return palette[index];
  }

  static int _stableHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((hash & 0x0007ffff) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((hash & 0x03ffffff) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((hash & 0x00003fff) << 15));
    return hash;
  }
}
