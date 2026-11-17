import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/data/datasources/reader_image_pipeline.dart';
/// Regression: two page widgets (visible + precache/translate-capture) used
/// to convert the same AVIF file concurrently — paying ~30s of ffmpeg twice
/// and racing the stale-file deletion (`PathNotFoundException` warning).
/// The pipeline must share one ffmpeg run per output path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kuron_native');
  late Directory tempDir;
  var convertCalls = 0;

  Uint8List avisBytes() {
    // Minimal animated AVIF: ftyp (major 'avif', compat 'avis') + ispe.
    // Mirrors the manga18 "motion" payload that triggered the bug.
    final out = <int>[
      0x00, 0x00, 0x00, 0x14, // ftyp size = 20
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x61, 0x76, 0x69, 0x66, // major 'avif'
      0x00, 0x00, 0x00, 0x00, // minor
      0x61, 0x76, 0x69, 0x73, // compat 'avis'
      0x00, 0x00, 0x00, 0x14, // ispe size = 20
      0x69, 0x73, 0x70, 0x65, // 'ispe'
      0x00, 0x00, 0x00, 0x00, // version/flags
      0x00, 0x00, 0x05, 0xA0, // width 1440 (big-endian)
      0x00, 0x00, 0x0B, 0xA0, // height 2976 (avis routes to native anyway)
    ];
    return Uint8List.fromList(out);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avif_dedupe');
    convertCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'convertAvifToWebP') {
        convertCalls++;
        // Force overlap so both callers observe the in-flight entry.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final outputPath = args['outputPath'] as String;
        await File(outputPath).writeAsBytes(List.filled(64, 0));
        return <String, dynamic>{'outputPath': outputPath};
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('concurrent conversions of the same page share one ffmpeg run',
      () async {
    final page = File('${tempDir.path}/page_22.jpg');
    await page.writeAsBytes(avisBytes());

    final pipeline = ReaderImagePipeline();
    final results = await Future.wait([
      pipeline.processImageFile(
        filePath: page.path,
        contentId: 'motion/content',
        pageNumber: 22,
      ),
      pipeline.processImageFile(
        filePath: page.path,
        contentId: 'motion/content',
        pageNumber: 22,
      ),
    ]);

    expect(convertCalls, 1,
        reason: 'second caller must await the in-flight conversion');
    for (final result in results) {
      expect(result.wasConverted, isTrue);
      expect(result.convertedPath, endsWith('page_22.webp'));
      expect(result.renderPath, endsWith('page_22.webp'));
    }
  });
}
