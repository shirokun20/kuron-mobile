import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/data/repositories/ai/fallback_image_handler.dart';
import 'package:nhasixapp/domain/entities/ai_translation.dart';
import 'package:nhasixapp/domain/entities/reader_settings_entity.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_translation_cubit.dart';
import 'package:nhasixapp/presentation/pages/reader/reader_translation_widgets.dart';

import '../unit/presentation/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderTranslationCubit makeCubit({FakeCacheRepository? cacheRepository}) =>
      ReaderTranslationCubit(
        providerRepository: FakeAiProviderRepository()
          ..addOnly(FakeAiProviderRepository.testProvider),
        providerFactory: FakeAiProviderFactory(),
        preferencesRepository: FakeAiPreferencesRepository(),
        cacheRepository: cacheRepository ?? FakeCacheRepository(),
        mosaicBuilder: FakeMosaicBuilder(),
        fallbackHandler: FallbackImageHandler(),
        heavyRunner: syncHeavyRunner,
        logger: Logger(level: Level.off),
      );

  Future<void> seedTranslatedState(
    ReaderTranslationCubit cubit,
    FakeCacheRepository cache,
  ) async {
    const contentId = 'c1';
    const pageIndex = 0;
    const imageUrl = 'u1';
    const cropYTop = 0;
    final cacheKey = ReaderTranslationCubit.buildCacheKey(
      contentId,
      pageIndex,
      '$imageUrl#$cropYTop',
    );

    await cache.put(
      cacheKey,
      PageTranslation(
        bubbles: [
          BubbleTranslation(
            rect: Rect.fromLTWH(10, 12, 24, 16),
            original: 'O',
            translated: 'T',
          ),
        ],
      ),
    );

    await cubit.translatePage(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageWidth: 100,
      imageHeight: 100,
      contentId: contentId,
      pageIndex: pageIndex,
      imageUrl: imageUrl,
      readingMode: ReadingMode.singlePage,
      imageUrlCount: 3,
      cropYTop: cropYTop,
    );
  }

  Future<void> pumpToolbar(
    WidgetTester tester,
    ReaderTranslationCubit cubit, {
    required ReadingMode mode,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: ReaderTranslationToolbar(
              readingMode: mode,
              onTranslate: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('translate enabled in continue scroll (webtoon gate in cubit)', (
    tester,
  ) async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await pumpToolbar(tester, cubit, mode: ReadingMode.continuousScroll);

    final translateIcon = find.byIcon(Icons.auto_awesome_outlined);
    expect(translateIcon, findsOneWidget);
    final button = tester.widget<IconButton>(
      find.ancestor(of: translateIcon, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('translate enabled in singlePage mode', (tester) async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await pumpToolbar(tester, cubit, mode: ReadingMode.singlePage);

    final translateIcon = find.byIcon(Icons.auto_awesome_outlined);
    final button = tester.widget<IconButton>(
      find.ancestor(of: translateIcon, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('draw button enabled in continue scroll (bubble detect)', (
    tester,
  ) async {
    final cubit = makeCubit();
    addTearDown(cubit.close);
    await pumpToolbar(tester, cubit, mode: ReadingMode.continuousScroll);

    final drawIcon = find.byIcon(Icons.draw_outlined);
    expect(drawIcon, findsOneWidget);
    final button = tester.widget<IconButton>(
      find.ancestor(of: drawIcon, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'continue scroll tap translate retriggers onTranslate even when translated',
    (tester) async {
      final cache = FakeCacheRepository();
      final cubit = makeCubit(cacheRepository: cache);
      addTearDown(cubit.close);

      await seedTranslatedState(cubit, cache);

      var called = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: ReaderTranslationToolbar(
                readingMode: ReadingMode.continuousScroll,
                onTranslate: () => called++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pump();

      expect(called, 1);
    },
  );

  testWidgets('single page tap translated toggles overlay, not retranslate', (
    tester,
  ) async {
    final cache = FakeCacheRepository();
    final cubit = makeCubit(cacheRepository: cache);
    addTearDown(cubit.close);

    await seedTranslatedState(cubit, cache);

    var called = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: ReaderTranslationToolbar(
              readingMode: ReadingMode.singlePage,
              onTranslate: () => called++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final before = cubit.overlayVisible;
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pump();

    expect(called, 0);
    expect(cubit.overlayVisible, isNot(before));
  });
}
