import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/pages/settings/ai_model_download_screen.dart';

void main() {
  const MethodChannel channel = MethodChannel('kuron_native');

  Map<String, dynamic> statusResponse = {};
  final startedDownloads = <Map<String, dynamic>>[];
  var cancelCalls = 0;
  var deleteCalls = 0;

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<Logger>(Logger(level: Level.off));
    statusResponse = {};
    startedDownloads.clear();
    cancelCalls = 0;
    deleteCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getModelStatus':
          return statusResponse;
        case 'startModelDownload':
          startedDownloads.add(
            Map<String, dynamic>.from(methodCall.arguments as Map),
          );
          return true;
        case 'cancelModelDownload':
          cancelCalls++;
          return true;
        case 'deleteModel':
          deleteCalls++;
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await GetIt.instance.reset();
  });

  /// Bounded pumps instead of pumpAndSettle: the cubit polls every 1s while
  /// downloading, which would keep pumpAndSettle waiting forever.
  late String pinRaw;

  setUpAll(() async {
    // Real async IO works here (outside the FakeAsync widget zone).
    pinRaw = await File('assets/model.pin.json').readAsString();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // flutter_test does not bundle assets: feed the REAL pin file through a
    // stub bundle so the shape-pinning still covers the true file.
    final raw = pinRaw;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiModelDownloadScreen(assetBundle: _MapBundle(raw)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    // First load round-trips pin + channel; give it up to 2s fake time.
    for (var i = 0;
        i < 20 && find.text('bubble_detector.onnx').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }


  Map<String, dynamic> status(
    String state, {
    int received = 0,
    int? total,
    String? errorCode,
  }) =>
      {
        'state': state,
        'bytesReceived': received,
        'totalBytes': total,
        'version': '1',
        'sizeBytes': state == 'ready' ? 42241751 : null,
        'fileName': 'bubble_detector.onnx',
        'errorCode': errorCode,
        'errorMessage': errorCode != null ? 'boom' : null,
      };

  testWidgets('missing model shows not-downloaded + download button',
      (tester) async {
    statusResponse = status('not_downloaded');
    await pumpScreen(tester);

    expect(find.text('bubble_detector.onnx'), findsOneWidget);
    expect(find.textContaining('Not downloaded'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await pumpFrames(tester);
    expect(startedDownloads.length, 1);
    expect(startedDownloads.first['url'], contains('github.com'));
    expect((startedDownloads.first['sha256'] as String).length, 64);
  });

  testWidgets('downloading shows progress + cancel', (tester) async {
    statusResponse =
        status('downloading', received: 1000000, total: 4000000);
    await pumpScreen(tester);

    expect(find.textContaining('Downloading'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);
    expect(cancelCalls, 1);
  });

  testWidgets('ready model shows version + delete with confirm',
      (tester) async {
    statusResponse = status('ready');
    await pumpScreen(tester);

    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.textContaining('Version 1'), findsOneWidget);
    expect(find.textContaining('MB'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await pumpFrames(tester);
    // Confirm dialog appears; deletion only after confirm.
    expect(deleteCalls, 0);
    await tester.tap(find.text('Confirm'));
    await pumpFrames(tester);
    expect(deleteCalls, 1);
  });

  testWidgets('offline error shows message + retry', (tester) async {
    statusResponse = status('error', errorCode: 'offline');
    await pumpScreen(tester);

    expect(find.textContaining('No network'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);
    expect(startedDownloads.length, 1);
  });
}

/// Minimal in-memory [AssetBundle] serving the real pin content.
class _MapBundle extends AssetBundle {
  _MapBundle(this._raw);

  final String _raw;

  @override
  Future<String> loadString(String key, {bool cache = true}) async => _raw;

  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Not stubbed: $key');
}
