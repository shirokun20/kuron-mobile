import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/presentation/widgets/kuro_mascot.dart';

/// Moods the Android launcher widget renders, with the file names both the
/// Dart side (`HomeWidget.saveWidgetData`) and the Glance widget expect.
///
/// Only moods with a static design land here: `KuroMood.waiting` is the
/// loading placeholder and never reaches the widget.
const Map<KuroMood, String> _exports = {
  KuroMood.happy: 'kuro_happy',
  KuroMood.reader: 'kuro_reader',
  KuroMood.ghost: 'kuro_ghost',
  KuroMood.cry: 'kuro_cry',
  KuroMood.tsundere: 'kuro_tsundere',
  KuroMood.frozenCry: 'kuro_frozen_cry',
};

/// Mirrored into `android/app/src/main/res/drawable-nodpi/` so the Glance
/// widget can show Kuro without shipping bitmaps in Kotlin.
const List<String> _androidCopies = [
  'kuro_happy',
  'kuro_cry',
  'kuro_tsundere',
  'kuro_frozen_cry',
];

const List<int> _pngSignature = [0x89, 0x50, 0x4E, 0x47];

void main() {
  testWidgets('export every launcher-widget mood to PNG', (
    WidgetTester tester,
  ) async {
    final assetDir = Directory('assets/widget');
    final androidDir = Directory('android/app/src/main/res/drawable-nodpi');
    assetDir.createSync(recursive: true);
    androidDir.createSync(recursive: true);

    for (final entry in _exports.entries) {
      final mood = entry.key;
      final name = entry.value;
      final key = ValueKey<String>('export-$name');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: ClipRect(
                  child: SizedBox.square(
                    dimension: 160,
                    child: OverflowBox(
                      maxWidth: 208,
                      maxHeight: 208,
                      child: KuroMascot(mood: mood, size: 208),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Settle the frame so blink/cry poses are painted, not mid-tick.
      await tester.pump(const Duration(milliseconds: 100));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );

      // `toImage()` schedules real raster work that never completes inside the
      // fake-async test zone, so it MUST run under `runAsync`.
      final bytes = await tester.runAsync<Uint8List>(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      });
      expect(bytes, isNotNull);

      expect(
        bytes!.length,
        greaterThan(500),
        reason: '$name.png looks like a blank render',
      );
      expect(
        bytes.take(4).toList(),
        _pngSignature,
        reason: '$name.png is not a PNG',
      );

      File('${assetDir.path}/$name.png').writeAsBytesSync(bytes);
      if (_androidCopies.contains(name)) {
        File('${androidDir.path}/$name.png').writeAsBytesSync(bytes);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    }

    for (final name in _exports.values) {
      final file = File('${assetDir.path}/$name.png');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      expect(
        file.lengthSync(),
        greaterThan(500),
        reason: 'too small: ${file.path}',
      );
      expect(
        file.readAsBytesSync().take(4).toList(),
        _pngSignature,
        reason: 'bad signature: ${file.path}',
      );
    }
    for (final name in _androidCopies) {
      final file = File('${androidDir.path}/$name.png');
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      expect(
        file.lengthSync(),
        greaterThan(500),
        reason: 'too small: ${file.path}',
      );
      expect(
        file.readAsBytesSync().take(4).toList(),
        _pngSignature,
        reason: 'bad signature: ${file.path}',
      );
    }
  });
}
