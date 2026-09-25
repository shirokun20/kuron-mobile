import 'dart:io';
import 'package:test/test.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as p;

void main() {
  test('mangapill home selectors', () {
    final html = File('test/fixtures/mangapill_home.html').readAsStringSync();
    final doc = p.parse(html);

    // Test container selectors
    for (final sel in [
      '.my-3.grid.justify-end.gap-3',
      '.my-3.grid.justify-end.gap-3 > div',
      '.my-3.grid.justify-end.gap-3 div',
      '.justify-end.gap-3',
    ]) {
      try {
        final el = doc.querySelectorAll(sel);
        debugPrint('"$sel" -> ${el.length} elements');
        if (el.isNotEmpty && el.length < 5) {
          debugPrint('  First child classes: ${el.first.classes.join(" ")}');
        }
      } catch (e) {
        debugPrint('"$sel" -> ERROR: $e');
      }
    }
  });
}
