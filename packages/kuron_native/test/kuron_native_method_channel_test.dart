import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelKuronNative platform = MethodChannelKuronNative();
  const MethodChannel channel = MethodChannel('kuron_native');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  group('PDF Conversion Progress Callback Lifecycle', () {
    test('resets onPdfProgress callback to null on success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'convertImagesToPdf') {
          // Send progress
          await platform.handleMethodCallForTest(
            const MethodCall('onProgress', {'progress': 50, 'message': 'Halfway'}),
          );
          return {'success': true, 'pdfPath': '/out.pdf'};
        }
        return null;
      });

      int progressCount = 0;
      await platform.convertImagesToPdf(
        imagePaths: ['/a.jpg'],
        outputPath: '/out.pdf',
        onProgress: (p, m) => progressCount++,
      );

      expect(progressCount, 1);

      // Trigger another onProgress call after conversion has finished.
      // Since callback is reset to null in finally, progressCount must NOT increase!
      await platform.handleMethodCallForTest(
        const MethodCall('onProgress', {'progress': 100, 'message': 'Done'}),
      );
      expect(progressCount, 1);
    });

    test('resets onPdfProgress callback to null on error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'convertImagesToPdf') {
          throw PlatformException(code: 'PDF_CONVERSION_FAILED', message: 'OOM');
        }
        return null;
      });

      int progressCount = 0;
      await expectLater(
        platform.convertImagesToPdf(
          imagePaths: ['/a.jpg'],
          outputPath: '/out.pdf',
          onProgress: (p, m) => progressCount++,
        ),
        throwsA(isA<PlatformException>()),
      );

      // Trigger onProgress after failure
      await platform.handleMethodCallForTest(
        const MethodCall('onProgress', {'progress': 100, 'message': 'Stale'}),
      );
      expect(progressCount, 0);
    });
  });
}
