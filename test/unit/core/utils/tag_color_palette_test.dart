import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/core/utils/tag_color_palette.dart';

void main() {
  group('TagColorPalette', () {
    test('returns warm theme colors in light mode', () {
      expect(
        TagColorPalette.resolve('artist', brightness: Brightness.light),
        const Color(0xFFB8655E),
      );
      expect(
        TagColorPalette.resolve('tag', brightness: Brightness.light),
        const Color(0xFFBF6C63),
      );
      expect(
        TagColorPalette.resolve('misc', brightness: Brightness.light),
        const Color(0xFF8B7C57),
      );
    });

    test('returns muted theme colors in dark mode', () {
      expect(
        TagColorPalette.resolve('tag', brightness: Brightness.dark),
        const Color(0xFFB8776D),
      );
      expect(
        TagColorPalette.resolve('other', brightness: Brightness.dark),
        const Color(0xFF7E726D),
      );
    });

    test('maps unknown types deterministically into the fallback palette', () {
      final first = TagColorPalette.resolve(
        'unregistered-type-a',
        brightness: Brightness.light,
      );
      final second = TagColorPalette.resolve(
        'unregistered-type-a',
        brightness: Brightness.light,
      );
      final different = TagColorPalette.resolve(
        'unregistered-type-b',
        brightness: Brightness.light,
      );

      expect(first, second);
      expect(first, isNot(different));
    });
  });
}
