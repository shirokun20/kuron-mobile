import 'dart:io';

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/domain/repositories/reader_image_repository.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/extended_image_reader_widget.dart';

// Regression test for: `setState() called during build` from
// `_postProcessResolvedFile` invoked synchronously inside the
// `_buildResolvedOrNetworkImage` FutureBuilder builder.
// The post-process call must be deferred post-frame, so pumping a resolved
// page must never throw, and the resolved file must render via ExtendedImage.

class _FakeReaderImageRepository implements ReaderImageRepository {
  _FakeReaderImageRepository(this.path);

  final String path;

  @override
  Future<PageImageResult> resolvePage({
    required String url,
    required String contentId,
    required int pageNumber,
    String? sourceId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async =>
      ReadyFromDisk(path: path);
}

// 1x1 transparent PNG (decoded by content, extension-agnostic).
const List<int> _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String pagePath;

  setUp(() {
    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(level: Level.off));
    }
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
    tempDir = Directory.systemTemp.createTempSync('reader_resolve_test');
    pagePath = '${tempDir.path}/page_1.jpg';
    File(pagePath).writeAsBytesSync(_tinyPng);
    getIt.registerSingleton<ReaderImageRepository>(
      _FakeReaderImageRepository(pagePath),
    );
  });

  tearDown(() {
    if (getIt.isRegistered<ReaderImageRepository>()) {
      getIt.unregister<ReaderImageRepository>();
    }
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets(
      'resolved disk file renders without setState() called during build',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ExtendedImageReaderWidget(
          imageUrl: 'https://example.com/page_1.jpg',
          contentId: 'test-content',
          pageNumber: 1,
          readingMode: ReadingMode.continuousScroll,
          sourceId: 'nhentai',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(ExtendedImage), findsWidgets);
  });
}
