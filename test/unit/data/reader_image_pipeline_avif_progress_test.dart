import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/data/datasources/reader_image_pipeline.dart';

/// Conversion progress plumbing: the native ffmpeg run reports 0.0–1.0 via
/// `onAvifConvertProgress`, the method channel fans out per output path, and
/// every waiter sharing a deduped run receives the ticks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kuron_native');
  late Directory tempDir;

  Uint8List avisBytes() {
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
      0x00, 0x00, 0x0B, 0xA0, // height 2976
    ];
    return Uint8List.fromList(out);
  }

  /// Mock native side: emit progress ticks as incoming channel calls (the
  /// way `AvifConverter` does via `invokeMethod`), then finish the run.
  void mockNativeWithProgress(List<double> ticks) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'convertAvifToWebP') {
        final outputPath = (call.arguments as Map)['outputPath'] as String;
        for (final tick in ticks) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await TestDefaultBinaryMessengerBinding.instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
            'kuron_native',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onAvifConvertProgress', {
                'outputPath': outputPath,
                'progress': tick,
              }),
            ),
            (ByteData? data) {},
          );
        }
        await File(outputPath).writeAsBytes(List.filled(64, 0));
        return <String, dynamic>{'outputPath': outputPath};
      }
      return null;
    });
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avif_progress');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('single conversion delivers ticks in order then completes', () async {
    mockNativeWithProgress(const [0.25, 0.5, 0.75]);
    final page = File('${tempDir.path}/page_10.jpg');
    await page.writeAsBytes(avisBytes());

    final ticks = <double>[];
    final result = await ReaderImagePipeline().processImageFile(
      filePath: page.path,
      contentId: 'motion/content',
      pageNumber: 10,
      onConvertProgress: ticks.add,
    );

    expect(ticks, const [0.25, 0.5, 0.75]);
    expect(result.wasConverted, isTrue);
    expect(result.renderPath, endsWith('page_10.webp'));
  });

  test('concurrent waiters sharing one run each get progress', () async {
    mockNativeWithProgress(const [0.2, 0.4, 0.6, 0.8]);
    final page = File('${tempDir.path}/page_22.jpg');
    await page.writeAsBytes(avisBytes());

    final pipeline = ReaderImagePipeline();
    final ticksA = <double>[];
    final ticksB = <double>[];
    final results = await Future.wait([
      pipeline.processImageFile(
        filePath: page.path,
        contentId: 'motion/content',
        pageNumber: 22,
        onConvertProgress: ticksA.add,
      ),
      pipeline.processImageFile(
        filePath: page.path,
        contentId: 'motion/content',
        pageNumber: 22,
        onConvertProgress: ticksB.add,
      ),
    ]);

    // First waiter observes the full sequence.
    expect(ticksA, const [0.2, 0.4, 0.6, 0.8]);
    // Second waiter joined the shared run: gets ticks, ending complete-ish.
    expect(ticksB, isNotEmpty);
    expect(ticksB.last, 0.8);
    for (var i = 1; i < ticksB.length; i++) {
      expect(ticksB[i], greaterThanOrEqualTo(ticksB[i - 1]));
    }
    for (final result in results) {
      expect(result.wasConverted, isTrue);
      expect(result.renderPath, endsWith('page_22.webp'));
    }
  });
}
