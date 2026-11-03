import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_native/kuron_native.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/core/di/service_locator.dart';
import 'package:nhasixapp/data/datasources/reader_image_pipeline.dart';
import 'package:nhasixapp/domain/entities/page_image_result.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/domain/repositories/reader_image_repository.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/widgets/extended_image_reader_widget.dart';

final _minimalAnimatedWebP = Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x24, 0x00, 0x00, 0x00, // length
  0x57, 0x45, 0x42, 0x50, // WEBP
  0x56, 0x50, 0x38, 0x58, // VP8X
  0x0A, 0x00, 0x00, 0x00, // chunk size 10
  0x02, 0x00, 0x00, 0x00, // flags: animation bit set
  0x00, 0x00, 0x00, // width - 1 = 0 (1px)
  0x00, 0x00, 0x00, // height - 1 = 0 (1px)
]);

class _ControlledPipeline extends ReaderImagePipeline {
  _ControlledPipeline({required this.repository})
      : super(repository: repository);

  final ReaderImageRepository repository;
  final Map<int, Completer<ProcessedImageResult?>> preCheckCompleters = {};

  @override
  Future<ProcessedImageResult?> preCheckDiskCache({
    required String imageUrl,
    required String contentId,
    required int pageNumber,
  }) {
    final completer = preCheckCompleters.putIfAbsent(
      pageNumber,
      () => Completer<ProcessedImageResult?>(),
    );
    return completer.future;
  }
}

class _PerPageRouteRepository implements ReaderImageRepository {
  _PerPageRouteRepository(this.pathsByPage);

  final Map<int, String> pathsByPage;

  @override
  Future<PageImageResult> resolvePage({
    required String url,
    required String contentId,
    required int pageNumber,
    String? sourceId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final path = pathsByPage[pageNumber] ?? pathsByPage[1]!;
    return ReadyFromDisk(path: path);
  }
}

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
  const MethodChannel systemUiChannel = MethodChannel('flutter/platform_views');

  late Directory tempDir;
  late String page1Path;
  late String page3Path;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemUiChannel, (call) async => null);

    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger(level: Level.off));
    }
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
    ExtendedImageReaderWidget.clearNativeAnimatedCache();

    tempDir = Directory.systemTemp.createTempSync('page_identity_test');
    page1Path = '${tempDir.path}/page_1.webp';
    page3Path = '${tempDir.path}/page_3.webp';
    File(page1Path).writeAsBytesSync(_minimalAnimatedWebP);
    File(page3Path).writeAsBytesSync(_minimalAnimatedWebP);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemUiChannel, null);

    if (getIt.isRegistered<ReaderImageRepository>()) {
      getIt.unregister<ReaderImageRepository>();
    }
    ExtendedImageReaderWidget.clearHeavyUrlsForTesting();
    ExtendedImageReaderWidget.clearNativeAnimatedCache();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    ExtendedImageReaderWidget.nativeViewAvailableOverrideForTesting = null;
  });

  group('Page Identity & Async Isolation (Task 2.1, 2.2, 2.3, 3.1)', () {
    testWidgets(
      'Task 2.1: Late async completion from page 1 is dropped after navigating to page 3',
      (tester) async {
        final repo = _PerPageRouteRepository({1: page1Path, 3: page3Path});
        final pipeline = _ControlledPipeline(repository: repo);

        // 1. Mount widget as page 1
        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              key: const ValueKey('reader_widget'),
              imageUrl: 'https://example.com/page1.webp',
              contentId: 'series_123',
              pageNumber: 1,
              readingMode: ReadingMode.continuousScroll,
              pipeline: pipeline,
            ),
          ),
        );
        await tester.pump();

        // 2. Reuse widget state by updating to page 3
        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              key: const ValueKey('reader_widget'),
              imageUrl: 'https://example.com/page3.png',
              contentId: 'series_123',
              pageNumber: 3,
              readingMode: ReadingMode.continuousScroll,
              pipeline: pipeline,
            ),
          ),
        );
        await tester.pump();

        // 3. Now complete the delayed page 1 pre-check with a heavy/animated result
        pipeline.preCheckCompleters[1]?.complete(
          ProcessedImageResult(
            renderPath: page1Path,
            isHeavy: true,
            isConfirmedAnimatedWebP: true,
            nativeImageSize: const Size(1000, 2000),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 4. Verify: Page 3 must NOT have become heavy or animated native view!
        // It must NOT show AnimatedWebPView with page 1's path or flags.
        expect(find.byType(AnimatedWebPView), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Task 2.2: didUpdateWidget resets derived state completely when pageNumber changes',
      (tester) async {
        // Pre-seed page 1 as heavy in accelerator maps
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          'https://example.com/page1.webp',
          contentId: 'series_123',
          pageNumber: 1,
        );

        // 1. Mount widget on page 1 (heavy)
        await tester.pumpWidget(
          _wrap(
            const ExtendedImageReaderWidget(
              key: ValueKey('reader_widget'),
              imageUrl: 'https://example.com/page1.webp',
              contentId: 'series_123',
              pageNumber: 1,
              readingMode: ReadingMode.continuousScroll,
            ),
          ),
        );
        await tester.pump();

        // Verify page 1 is heavy
        expect(
          ExtendedImageReaderWidget.isHeavyUrlForTesting(
            'https://example.com/page1.webp',
            contentId: 'series_123',
            pageNumber: 1,
          ),
          isTrue,
        );

        // 2. Reuse widget state by updating to page 3 (standard non-heavy image)
        await tester.pumpWidget(
          _wrap(
            const ExtendedImageReaderWidget(
              key: ValueKey('reader_widget'),
              imageUrl: 'https://example.com/page3.jpg',
              contentId: 'series_123',
              pageNumber: 3,
              readingMode: ReadingMode.continuousScroll,
            ),
          ),
        );
        await tester.pump();

        // Verify page 3 is NOT heavy
        expect(
          ExtendedImageReaderWidget.isHeavyUrlForTesting(
            'https://example.com/page3.jpg',
            contentId: 'series_123',
            pageNumber: 3,
          ),
          isFalse,
        );

        // Page 3 must not render native view or reuse page 1's heavy state
        expect(find.byType(AndroidView), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Task 2.3: Same image URL on two pages stays independent (triple-key)',
      (tester) async {
        const sharedUrl = 'https://example.com/shared_cover.webp';

        // Pre-seed page 1 as heavy for sharedUrl
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          sharedUrl,
          contentId: 'series_123',
          pageNumber: 1,
        );

        // Page 1 is heavy
        expect(
          ExtendedImageReaderWidget.isHeavyUrlForTesting(
            sharedUrl,
            contentId: 'series_123',
            pageNumber: 1,
          ),
          isTrue,
        );

        // Page 2 with the EXACT same URL is NOT heavy
        expect(
          ExtendedImageReaderWidget.isHeavyUrlForTesting(
            sharedUrl,
            contentId: 'series_123',
            pageNumber: 2,
          ),
          isFalse,
        );

        // Mount page 2
        await tester.pumpWidget(
          _wrap(
            const ExtendedImageReaderWidget(
              imageUrl: sharedUrl,
              contentId: 'series_123',
              pageNumber: 2,
              readingMode: ReadingMode.continuousScroll,
            ),
          ),
        );
        await tester.pump();

        // Page 2 does not route to native view because page 2 is not heavy
        expect(find.byType(AndroidView), findsNothing);
      },
    );

    testWidgets(
      'Task 3.1: Native view gets current page file (no global page 1 fallback)',
      (tester) async {
        final repo = _PerPageRouteRepository({
          1: page1Path,
          3: page3Path,
        });
        ExtendedImageReaderWidget.nativeViewAvailableOverrideForTesting = true;

        // Pre-seed page 3 as heavy so it routes to native
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          'https://example.com/anim.webp',
          contentId: 'series_123',
          pageNumber: 3,
        );

        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              key: const ValueKey('reader_widget'),
              imageUrl: 'https://example.com/anim.webp',
              contentId: 'series_123',
              pageNumber: 3,
              readingMode: ReadingMode.continuousScroll,
              pipeline: ReaderImagePipeline(repository: repo),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Find AnimatedWebPView and inspect its filePath property
        final animatedViews = tester.widgetList<AnimatedWebPView>(
          find.byType(AnimatedWebPView),
        );
        expect(animatedViews, isNotEmpty);
        final view = animatedViews.first;

        // filePath MUST be page 3's resolved path, never page 1's path!
        expect(view.filePath, equals(page3Path));
        expect(view.filePath, isNot(equals(page1Path)));
        expect(view.pageNumber, equals(3));
      },
    );

    testWidgets(
      'Task 2.1 scenario: Disposed page drops late conversion cleanly',
      (tester) async {
        final repo = _PerPageRouteRepository({1: page1Path});
        final pipeline = _ControlledPipeline(repository: repo);

        // Mount page 1
        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              imageUrl: 'https://example.com/page1.webp',
              contentId: 'series_123',
              pageNumber: 1,
              readingMode: ReadingMode.continuousScroll,
              pipeline: pipeline,
            ),
          ),
        );
        await tester.pump();

        // Dispose the widget by replacing it with a container
        await tester.pumpWidget(_wrap(const SizedBox()));
        await tester.pump();

        // Complete late async after disposal
        pipeline.preCheckCompleters[1]?.complete(
          ProcessedImageResult(
            renderPath: page1Path,
            wasConverted: true,
            convertedPath: '${tempDir.path}/converted.webp',
            isHeavy: true,
            isConfirmedAnimatedWebP: true,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Task 3.1 scenario: page 3 routing native while cached path for page 1 exists never passes page 1 path',
      (tester) async {
        final repo = _PerPageRouteRepository({
          1: page1Path,
          3: page3Path,
        });
        ExtendedImageReaderWidget.nativeViewAvailableOverrideForTesting = true;

        // Simulate page 1 had a cached file
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          'https://example.com/page1.webp',
          contentId: 'series_123',
          pageNumber: 1,
        );
        // Pre-seed page 3 as native heavy as well
        ExtendedImageReaderWidget.addHeavyUrlForTesting(
          'https://example.com/page3.webp',
          contentId: 'series_123',
          pageNumber: 3,
        );

        // Render page 1 first
        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              key: const ValueKey('reader_page'),
              imageUrl: 'https://example.com/page1.webp',
              contentId: 'series_123',
              pageNumber: 1,
              readingMode: ReadingMode.continuousScroll,
              pipeline: ReaderImagePipeline(repository: repo),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        var views =
            tester.widgetList<AnimatedWebPView>(find.byType(AnimatedWebPView));
        expect(views.first.filePath, equals(page1Path));

        // Update to page 3
        await tester.pumpWidget(
          _wrap(
            ExtendedImageReaderWidget(
              key: const ValueKey('reader_page'),
              imageUrl: 'https://example.com/page3.webp',
              contentId: 'series_123',
              pageNumber: 3,
              readingMode: ReadingMode.continuousScroll,
              pipeline: ReaderImagePipeline(repository: repo),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        views =
            tester.widgetList<AnimatedWebPView>(find.byType(AnimatedWebPView));
        expect(views.first.filePath, equals(page3Path));
        expect(views.first.filePath, isNot(equals(page1Path)));
        expect(views.first.pageNumber, equals(3));
      },
    );
  });
}
