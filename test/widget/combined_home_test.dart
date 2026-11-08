import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/source_loader.dart';
import 'package:nhasixapp/domain/entities/entities.dart';
import 'package:nhasixapp/domain/usecases/combined_home/get_combined_home_usecase.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_cubit.dart';
import 'package:nhasixapp/presentation/cubits/combined_home/combined_home_state.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/combined_home_list.dart';
import 'package:nhasixapp/presentation/widgets/common/source_selector.dart';
import 'package:nhasixapp/presentation/widgets/progressive_image_widget.dart';

class _MockGetCombinedHomeUseCase extends Mock
    implements GetCombinedHomeUseCase {}

class _MockLogger extends Mock implements Logger {}

class _MockRegistry extends Mock implements ContentSourceRegistry {}

class _MockSource extends Mock implements ContentSource {}

class _MockSourceLoader extends Mock implements SourceLoader {}

class _MockRemoteConfigService extends Mock implements RemoteConfigService {}

Content _content(String sourceId, String id) => Content(
  id: id,
  sourceId: sourceId,
  title: 'title-$id',
  coverUrl: 'https://cdn.example.com/$id.jpg',
  tags: const [],
  artists: const [],
  characters: const [],
  parodies: const [],
  groups: const [],
  language: 'en',
  pageCount: 10,
  imageUrls: const [],
  uploadDate: DateTime(2026, 1, 1),
);

CombinedHomeFeed _feed() => CombinedHomeFeed(
  contents: [_content('a', 'a1'), _content('b', 'b1')],
  sourceIds: const ['a', 'b'],
);

_MockSource _fakeSource(String id, String name) {
  final source = _MockSource();
  when(() => source.id).thenReturn(id);
  when(() => source.displayName).thenReturn(name);
  when(() => source.iconPath).thenReturn('');
  return source;
}

Widget _harness({
  required SourceCubit sourceCubit,
  required CombinedHomeCubit combinedCubit,
  required List<String> tapped,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Column(
        children: [
          const SourceSelector(),
          Expanded(
            child: BlocBuilder<CombinedHomeCubit, CombinedHomeState>(
              buildWhen: (previous, current) =>
                  previous.isCombinedSelected != current.isCombinedSelected,
              builder: (context, combinedState) {
                // Mirrors MainScreenScrollable._buildScrollableBody routing:
                // "Semua" renders the cubit list, otherwise the legacy
                // single-source body.
                if (combinedState.isCombinedSelected) {
                  return CombinedHomeList(
                    onContentTap: (content) => tapped.add(content.id),
                  );
                }
                final activeId = context.select<SourceCubit, String?>(
                  (cubit) => cubit.state.activeSource?.id,
                );
                return Text('single:$activeId');
              },
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const GetCombinedHomeParams());
  });

  late _MockGetCombinedHomeUseCase useCase;
  late _MockRegistry registry;
  late _MockSource srcA;
  late _MockSource srcB;
  late String currentId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    useCase = _MockGetCombinedHomeUseCase();
    when(() => useCase(any())).thenAnswer((_) async => _feed());

    srcA = _fakeSource('a', 'Source A');
    srcB = _fakeSource('b', 'Source B');
    currentId = 'a';
    registry = _MockRegistry();
    when(() => registry.allSources).thenReturn([srcA, srcB]);
    when(() => registry.currentSource)
        .thenAnswer((_) => currentId == 'a' ? srcA : srcB);
    when(() => registry.hasSource(any())).thenReturn(true);
    when(() => registry.switchSource(any())).thenAnswer((invocation) {
      currentId = invocation.positionalArguments.first as String;
      return true;
    });

    final loader = _MockSourceLoader();
    when(() => loader.maintenanceSourceIds).thenReturn(<String>{});
    when(() => loader.isUnderMaintenance(any())).thenReturn(false);
    GetIt.instance.registerSingleton<SourceLoader>(loader);

    final remoteConfig = _MockRemoteConfigService();
    when(() => remoteConfig.getConfig(any())).thenReturn(null);
    when(() => remoteConfig.getRawConfig(any())).thenReturn(null);
    GetIt.instance.registerSingleton<RemoteConfigService>(remoteConfig);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<(SourceCubit, CombinedHomeCubit)> pumpHarness(
    WidgetTester tester, {
    required List<String> tapped,
  }) async {
    // Tall surface so every bottom-sheet row is hittable without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final sourceCubit = SourceCubit(
      registry: registry,
      prefs: prefs,
      logger: _MockLogger(),
    );
    final combinedCubit = CombinedHomeCubit(
      getCombinedHomeUseCase: useCase,
      logger: _MockLogger(),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SourceCubit>.value(value: sourceCubit),
          BlocProvider<CombinedHomeCubit>.value(value: combinedCubit),
        ],
        child: _harness(
          sourceCubit: sourceCubit,
          combinedCubit: combinedCubit,
          tapped: tapped,
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(sourceCubit.close);
    addTearDown(combinedCubit.close);
    return (sourceCubit, combinedCubit);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(SourceSelector));
    await tester.pumpAndSettle();
    // Bottom sheet is open when the "Semua" row is visible.
    expect(find.text('Semua'), findsWidgets);
  }

  group('Home "Semua" source picker', () {
    testWidgets('single-source list shows by default', (tester) async {
      final tapped = <String>[];
      await pumpHarness(tester, tapped: tapped);

      expect(find.text('single:a'), findsOneWidget);
      expect(find.text('title-a1'), findsNothing);
    });

    testWidgets('picking Semua renders the combined list', (tester) async {
      final tapped = <String>[];
      final (_, combinedCubit) = await pumpHarness(tester, tapped: tapped);

      await openSheet(tester);
      await tester.tap(find.text('List kombinasi semua source'));
      await tester.pumpAndSettle();

      expect(combinedCubit.state.isCombinedSelected, isTrue);
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byType(CombinedHomeGridCard), findsNWidgets(2));
      expect(find.text('title-a1'), findsOneWidget);
      expect(find.text('title-b1'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('DOUJIN'), findsNWidgets(2));
      expect(find.byType(ProgressiveImageWidget), findsNWidgets(2));
      expect(find.text('single:a'), findsNothing);
      // Picker header reflects the combined mode.
      expect(find.text('Semua'), findsWidgets);
    });

    testWidgets('picking a source leaves Semua and restores single list', (
      tester,
    ) async {
      final tapped = <String>[];
      final (sourceCubit, combinedCubit) = await pumpHarness(
        tester,
        tapped: tapped,
      );

      await openSheet(tester);
      await tester.tap(find.text('List kombinasi semua source'));
      await tester.pumpAndSettle();
      expect(find.text('title-a1'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.text('Source B'));
      await tester.pumpAndSettle();

      expect(combinedCubit.state.isCombinedSelected, isFalse);
      expect(sourceCubit.state.activeSource?.id, 'b');
      expect(find.text('single:b'), findsOneWidget);
      expect(find.text('title-a1'), findsNothing);
    });

    testWidgets('combined row tap forwards the content', (tester) async {
      final tapped = <String>[];
      await pumpHarness(tester, tapped: tapped);

      await openSheet(tester);
      await tester.tap(find.text('List kombinasi semua source'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('title-a1'));
      expect(tapped, ['a1']);
    });

    testWidgets('drawer on a screen without CombinedHomeCubit does not crash '
        'and switches source', (tester) async {
      // Regression: the shared drawer (settings, downloads, ...) hosts
      // SourceSelector without a CombinedHomeCubit above it. This used to
      // throw ProviderNotFoundError on build.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final sourceCubit = SourceCubit(
        registry: registry,
        prefs: prefs,
        logger: _MockLogger(),
      );
      addTearDown(sourceCubit.close);

      await tester.pumpWidget(
        BlocProvider<SourceCubit>.value(
          value: sourceCubit,
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: Scaffold(body: SourceSelector()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Renders the active source, no "Semua" option offered.
      expect(find.text('Source A'), findsOneWidget);

      await tester.tap(find.byType(SourceSelector));
      await tester.pumpAndSettle();
      expect(find.text('List kombinasi semua source'), findsNothing);

      await tester.tap(find.text('Source B'));
      await tester.pumpAndSettle();
      expect(sourceCubit.state.activeSource?.id, 'b');
    });
  });
}
