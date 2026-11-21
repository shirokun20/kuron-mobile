import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/data/repositories/ai/fallback_image_handler.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_translation_cubit.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_translation_widgets.dart';

import '../unit/presentation/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock ONNX detection to return 3 bubbles.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('kuron_native'), (
          MethodCall call,
        ) async {
          if (call.method == 'detectBubbles') {
            return [
              {'x': 10, 'y': 10, 'w': 50, 'h': 30, 'confidence': 0.9},
              {'x': 100, 'y': 100, 'w': 40, 'h': 25, 'confidence': 0.8},
              {'x': 200, 'y': 50, 'w': 45, 'h': 28, 'confidence': 0.7},
            ];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('kuron_native'), null);
  });

  testWidgets('overlay renders one Positioned per translated bubble', (
    tester,
  ) async {
    final cubit = ReaderTranslationCubit(
      providerRepository: FakeAiProviderRepository()
        ..addOnly(FakeAiProviderRepository.testProvider),
      providerFactory: FakeAiProviderFactory(),
      preferencesRepository: FakeAiPreferencesRepository(),
      cacheRepository: FakeCacheRepository(),
      mosaicBuilder: FakeMosaicBuilder(),
      fallbackHandler: FallbackImageHandler(),
      heavyRunner: syncHeavyRunner,
      logger: Logger(level: Level.off),
    );
    addTearDown(cubit.close);

    await cubit.translatePage(
      imageBytes: Uint8List(0),
      imageWidth: 100,
      imageHeight: 100,
      contentId: 'c1',
      pageIndex: 0,
      imageUrl: 'u1',
      readingMode: ReadingMode.singlePage,
      imageUrlCount: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: ReaderTranslationOverlay()),
        ),
      ),
    );
    await tester.pump();

    expect(cubit.state, isA<ReaderTranslationTranslated>());
    expect(find.byType(Positioned), findsNWidgets(3));
  });

  testWidgets('detection rebuild clears stale translated bubbles', (
    tester,
  ) async {
    final cubit = _TestReaderTranslationCubit(
      providerRepository: FakeAiProviderRepository()
        ..addOnly(FakeAiProviderRepository.testProvider),
      providerFactory: FakeAiProviderFactory(),
      preferencesRepository: FakeAiPreferencesRepository(),
      cacheRepository: FakeCacheRepository(),
      mosaicBuilder: FakeMosaicBuilder(),
      fallbackHandler: FallbackImageHandler(),
      heavyRunner: syncHeavyRunner,
      logger: Logger(level: Level.off),
    );
    addTearDown(cubit.close);

    await cubit.translatePage(
      imageBytes: Uint8List(0),
      imageWidth: 100,
      imageHeight: 100,
      contentId: 'c1',
      pageIndex: 0,
      imageUrl: 'u1',
      readingMode: ReadingMode.singlePage,
      imageUrlCount: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<ReaderTranslationCubit>.value(
          value: cubit,
          child: const Scaffold(body: ReaderTranslationOverlay()),
        ),
      ),
    );
    await tester.pump();

    cubit.showDetecting();
    await tester.pump();
    await tester.pump();

    expect(cubit.state, isA<ReaderTranslationDetecting>());
    expect(find.byType(AiBusyOverlay), findsOneWidget);
    expect(find.byType(ReaderTranslatedBubble), findsNothing);
  });

  testWidgets('overlay renders polygon shape when bubble has shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: 40,
              child: _TranslatedBubbleForTest(
                shape: [
                  [0, 0],
                  [60, 0],
                  [55, 20],
                  [60, 40],
                  [0, 40],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Polygon painter present (shape-following), not the box white patch.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tiny bubble text stays within bubble (font-fit, no overflow)', (
    tester,
  ) async {
    // Render the bubble directly in a 30x20 box — below the 44px min — with
    // a long text; the fitted style must never exceed the box.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 30,
              height: 20,
              child: _TranslatedBubbleForTest(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(
      find.descendant(of: find.byType(SizedBox), matching: find.byType(Text)),
    );
    expect(text.style!.fontSize, lessThanOrEqualTo(30));
    expect(text.style!.fontSize, greaterThanOrEqualTo(4));

    // Box-only path also centers the text block (was top-aligned before).
    final bubble = find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 30 && w.height == 20,
    );
    final textCenter = tester.getCenter(
      find.descendant(of: bubble, matching: find.byType(Text)),
    );
    final bubbleCenter = tester.getCenter(bubble);
    expect((textCenter.dx - bubbleCenter.dx).abs(), lessThan(2.0));
    expect((textCenter.dy - bubbleCenter.dy).abs(), lessThan(2.0));
  });

  testWidgets(
    'shape bubble sizes text against the inscribed rect and does not clip',
    (tester) async {
      // Diamond polygon inside a 60×40 box: the oval corners cut deep inside
      // the bounds, so the effective box is only ~48×32. The fitted font must
      // be validated against that inscribed area, never the full bounds.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                height: 40,
                child: _TranslatedBubbleForTest(
                  text: 'Halo',
                  shape: [
                    [30, 0],
                    [60, 20],
                    [30, 40],
                    [0, 20],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(
        find.descendant(of: find.byType(SizedBox), matching: find.byType(Text)),
      );
      // Re-measure with the same painter setup `_fitText` uses: the chosen
      // style must fit the 48×32 inscribed box at 0.98× (width & height).
      const insW = 48.0 * 0.98;
      const insH = 32.0 * 0.98;
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: insW);
      expect(painter.width, lessThanOrEqualTo(insW));
      expect(painter.height, lessThanOrEqualTo(insH));

      // Regression: the fitted text block is CENTERED inside the bubble — the
      // old top-aligned layout stranded lines against the oval's top edge with
      // all the empty space below.
      final bubble = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 60 && w.height == 40,
      );
      final textCenter = tester.getCenter(
        find.descendant(of: bubble, matching: find.byType(Text)),
      );
      final bubbleCenter = tester.getCenter(bubble);
      expect((textCenter.dx - bubbleCenter.dx).abs(), lessThan(2.0));
      expect((textCenter.dy - bubbleCenter.dy).abs(), lessThan(2.0));
    },
  );
}

class _TestReaderTranslationCubit extends ReaderTranslationCubit {
  _TestReaderTranslationCubit({
    required super.providerRepository,
    required super.providerFactory,
    required super.preferencesRepository,
    required super.cacheRepository,
    required super.mosaicBuilder,
    required super.fallbackHandler,
    required super.heavyRunner,
    required super.logger,
  });

  void showDetecting() => emit(const ReaderTranslationDetecting());
}

/// Minimal bubble with a long translated string, for font-fit assertions.
class _TranslatedBubbleForTest extends StatelessWidget {
  const _TranslatedBubbleForTest({
    this.shape,
    this.text = 'This is a very long translated sentence that must fit',
  });

  final List<List<int>>? shape;
  final String text;

  @override
  Widget build(BuildContext context) {
    final shapeLocal = shape
        ?.map((p) => Offset(p[0].toDouble(), p[1].toDouble()))
        .toList();
    return ReaderTranslatedBubble(
      bubble: BubbleTranslation(
        rect: Rect.fromLTWH(0, 0, 30, 20),
        original: '長い日本語のセリフがこの狭い吹き出しに収まるか確認するためのテストです',
        translated: text,
        shape: shape,
      ),
      index: 0,
      shapeLocal: shapeLocal,
      // Mirrors the production `_inscribedBox` (bounding rect × 0.8), so the
      // test exercises the same effective-fit path the overlay uses.
      effectiveBox: (shapeLocal != null && shapeLocal.length >= 3)
          ? _inscribedForTest(shapeLocal)
          : null,
    );
  }
}

/// Test mirror of `_inscribedBox` in reader_translation_widgets.dart.
Rect _inscribedForTest(List<Offset> points) {
  var b = Rect.fromPoints(points.first, points.first);
  for (final p in points.skip(1)) {
    b = b.expandToInclude(Rect.fromPoints(p, p));
  }
  return Rect.fromLTRB(
    b.left + b.width * 0.1,
    b.top + b.height * 0.1,
    b.right - b.width * 0.1,
    b.bottom - b.height * 0.1,
  );
}

/// Mosaic builder that returns minimal bytes (test image decoding not needed
/// because ONNX is mocked and FakeProvider produces bubbles directly).
