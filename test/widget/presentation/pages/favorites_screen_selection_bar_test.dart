import 'package:bloc_test/bloc_test.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/config_models.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/config/source_loader.dart';
import 'package:nhasixapp/core/services/source_auth_service.dart';
import 'package:nhasixapp/domain/entities/favorite_collection.dart';
import 'package:nhasixapp/domain/value_objects/favorite_key.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/favorite/favorite_cubit.dart';
import 'package:nhasixapp/presentation/cubits/network/network_cubit.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/presentation/cubits/source/source_cubit.dart';
import 'package:nhasixapp/presentation/cubits/source/source_state.dart';
import 'package:nhasixapp/presentation/cubits/streak/streak_cubit.dart';
import 'package:nhasixapp/presentation/pages/favorites/favorites_screen.dart';

class MockFavoriteCubit extends Mock implements FavoriteCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

class MockSourceAuthService extends Mock implements SourceAuthService {}

class MockContentSourceRegistry extends Mock implements ContentSourceRegistry {}

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

class MockSourceCubit extends Mock implements SourceCubit {}

class MockNetworkCubit extends Mock implements NetworkCubit {}

class MockDownloadBloc extends Mock implements DownloadBloc {}

class MockStreakCubit extends Mock implements StreakCubit {}

class MockSourceLoader extends Mock implements SourceLoader {}

void main() {
  late MockFavoriteCubit mockCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockSourceAuthService mockAuthService;
  late MockContentSourceRegistry mockRegistry;
  late MockRemoteConfigService mockRemoteConfig;
  late MockSourceCubit mockSourceCubit;
  late MockNetworkCubit mockNetworkCubit;
  late MockDownloadBloc mockDownloadBloc;
  late MockStreakCubit mockStreakCubit;
  late MockSourceLoader mockSourceLoader;

  final tCollection = FavoriteCollection(
    id: 'c1',
    name: 'Manga',
    createdAt: DateTime(2026, 4, 12),
    updatedAt: DateTime(2026, 4, 12),
    itemCount: 3,
  );

  FavoriteLoaded testLoaded({String? activeCollectionId}) => FavoriteLoaded(
    favorites: const [
      {
        'id': '1',
        'source_id': 'nhentai',
        'title': 'Alpha',
        'cover_url': '',
        'added_at': 1710000000000,
      },
      {
        'id': '2',
        'source_id': 'crotpedia',
        'title': 'Beta',
        'cover_url': '',
        'added_at': 1710000001000,
      },
    ],
    collections: [tCollection],
    currentPage: 1,
    hasMore: false,
    totalCount: 2,
    lastUpdated: DateTime(2026, 4, 12),
    totalAllCount: 5,
    uncategorizedCount: 2,
    activeCollectionId: activeCollectionId,
  );

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String>[]);
    registerFallbackValue((id: '', sourceId: ''));
    registerFallbackValue(<FavoriteKey>[]);
    registerFallbackValue((FeatureConfig _) => false);
  });

  // The drawer + global download header build with the screen, so the test
  // shell provides their blocs. connectivity_plus channels are mocked
  // because the drawer listens for connectivity changes in initState.
  void mockConnectivityChannels(WidgetTester tester) {
    const methodChannel = MethodChannel(
      'dev.fluttercommunity.plus/connectivity',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        if (call.method == 'check') return <String>['none'];
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
  }

  setUp(() {
    mockCubit = MockFavoriteCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockAuthService = MockSourceAuthService();
    mockRegistry = MockContentSourceRegistry();
    mockRemoteConfig = MockRemoteConfigService();
    mockSourceCubit = MockSourceCubit();
    mockNetworkCubit = MockNetworkCubit();
    mockDownloadBloc = MockDownloadBloc();
    mockStreakCubit = MockStreakCubit();
    mockSourceLoader = MockSourceLoader();

    when(() => mockAuthService.getSourcesSupportingOnlineFavorites())
        .thenReturn([]);
    when(() => mockRegistry.getSource(any())).thenReturn(null);
    when(() => mockRemoteConfig.getRawConfig(any())).thenReturn(null);
    when(() => mockRemoteConfig.isFeatureEnabled(any(), any()))
        .thenReturn(false);
    whenListen<SettingsState>(
      mockSettingsCubit,
      Stream<SettingsState>.empty(),
      initialState: const SettingsInitial(),
    );
    whenListen<SourceState>(
      mockSourceCubit,
      Stream<SourceState>.value(const SourceState()),
      initialState: const SourceState(),
    );
    whenListen<NetworkState>(
      mockNetworkCubit,
      Stream<NetworkState>.value(const NetworkInitial()),
      initialState: const NetworkInitial(),
    );
    whenListen<DownloadBlocState>(
      mockDownloadBloc,
      Stream<DownloadBlocState>.value(const DownloadInitial()),
      initialState: const DownloadInitial(),
    );
    when(() => mockSettingsCubit.getColumnsForOrientation(any())).thenReturn(2);
    when(() => mockStreakCubit.loadStreak()).thenAnswer((_) async {});
    when(() => mockStreakCubit.close()).thenAnswer((_) async {});
    when(() => mockCubit.close()).thenAnswer((_) async {});
    whenListen<StreakState>(
      mockStreakCubit,
      Stream<StreakState>.value(
        StreakState(referenceDate: DateTime(2026, 1, 1)),
      ),
      initialState: StreakState(referenceDate: DateTime(2026, 1, 1)),
    );
    when(() => mockCubit.loadFavorites()).thenAnswer((_) async {});
    when(() => mockCubit.selectCollection(any())).thenAnswer((_) async {});
    when(
      () => mockCubit.addBatchToCollections(
        favorites: any(named: 'favorites'),
        collectionIds: any(named: 'collectionIds'),
        removeFromCollectionId: any(named: 'removeFromCollectionId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockCubit.removeBatchFromCollection(
        favorites: any(named: 'favorites'),
        collectionId: any(named: 'collectionId'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockCubit.removeBatchFavorites(any())).thenAnswer((_) async {});

    GetIt.I.registerSingleton<FavoriteCubit>(mockCubit);
    GetIt.I.registerSingleton<SourceAuthService>(mockAuthService);
    GetIt.I.registerSingleton<ContentSourceRegistry>(mockRegistry);
    GetIt.I.registerSingleton<RemoteConfigService>(mockRemoteConfig);
    GetIt.I.registerSingleton<SourceLoader>(mockSourceLoader);
    GetIt.I.registerSingleton<StreakCubit>(mockStreakCubit);
  });

  tearDown(() {
    GetIt.I.reset();
  });

  // Fixed-frame settling: the drawer hosts repeating animations
  // (header pulse, mascot idle), so pumpAndSettle would never finish.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpScreen(WidgetTester tester, FavoriteLoaded loaded) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    mockConnectivityChannels(tester);

    when(() => mockCubit.state).thenReturn(loaded);
    whenListen<FavoriteState>(
      mockCubit,
      Stream<FavoriteState>.value(loaded),
      initialState: loaded,
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const FavoritesScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          BlocProvider<SourceCubit>.value(value: mockSourceCubit),
          BlocProvider<NetworkCubit>.value(value: mockNetworkCubit),
          BlocProvider<DownloadBloc>.value(value: mockDownloadBloc),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('FavoritesScreen selection bar and folder strip', () {
    testWidgets('shows All/Uncategorized/folder chips with counts and New', (
      tester,
    ) async {
      await pumpScreen(tester, testLoaded());

      expect(find.text('All (5)'), findsOneWidget);
      expect(find.text('Uncategorized (2)'), findsOneWidget);
      expect(find.text('Manga (3)'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('tapping chips filters via selectCollection', (tester) async {
      await pumpScreen(tester, testLoaded());

      await tester.tap(find.text('Manga (3)'));
      verify(() => mockCubit.selectCollection('c1')).called(1);

      await tester.tap(find.text('Uncategorized (2)'));
      verify(
        () =>
            mockCubit.selectCollection(FavoriteCubit.uncategorizedCollectionId),
      ).called(1);
    });

    testWidgets('long-press enters selection mode with folder actions', (
      tester,
    ) async {
      await pumpScreen(tester, testLoaded());

      await tester.longPress(find.text('Alpha'));
      await pumpFrames(tester);

      // AppBar shows selection count plus folder + delete actions.
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byTooltip('Add to folder'), findsOneWidget);
      expect(find.byTooltip('Delete selected'), findsOneWidget);

      // Toolbar keeps Select All / Clear / counter and gains Add to Folder.
      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Add to folder'), findsOneWidget);

      // Outside a folder there is no Move / Remove-from-Folder.
      expect(find.text('Move to folder'), findsNothing);
      expect(find.text('Remove from folder'), findsNothing);
    });

    testWidgets('inside a folder shows Move and Remove from Folder', (
      tester,
    ) async {
      await pumpScreen(tester, testLoaded(activeCollectionId: 'c1'));

      await tester.longPress(find.text('Alpha'));
      await pumpFrames(tester);

      expect(find.text('Add to folder'), findsOneWidget);
      expect(find.text('Move to folder'), findsOneWidget);
      expect(find.text('Remove from folder'), findsOneWidget);
    });

    testWidgets('Add to Folder sheet saves checked folders', (tester) async {
      await pumpScreen(tester, testLoaded());

      await tester.longPress(find.text('Alpha'));
      await pumpFrames(tester);
      await tester.tap(find.text('Add to folder'));
      await pumpFrames(tester);

      // Sheet lists folders with counts plus inline creation entry point.
      expect(find.text('Add to folder'), findsNWidgets(2));
      expect(find.widgetWithText(CheckboxListTile, 'Manga'), findsOneWidget);
      expect(find.text('New collection'), findsOneWidget);

      // Save starts disabled until a folder is checked.
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Manga'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpFrames(tester);

      verify(
        () => mockCubit.addBatchToCollections(
          favorites: const [(id: '1', sourceId: 'nhentai')],
          collectionIds: ['c1'],
          removeFromCollectionId: null,
        ),
      ).called(1);

      // Selection is cleared after a successful batch add.
      expect(find.text('Add to folder'), findsNothing);
    });

    testWidgets('Remove from Folder asks confirm then removes', (tester) async {
      await pumpScreen(tester, testLoaded(activeCollectionId: 'c1'));

      await tester.longPress(find.text('Alpha'));
      await pumpFrames(tester);
      await tester.tap(find.text('Remove from folder'));
      await pumpFrames(tester);

      // Confirm dialog names the folder and reassures items stay saved.
      expect(find.text('Remove from folder'), findsNWidgets(2));
      expect(find.textContaining('They stay saved in All'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await pumpFrames(tester);

      verify(
        () => mockCubit.removeBatchFromCollection(
          favorites: const [(id: '1', sourceId: 'nhentai')],
          collectionId: 'c1',
        ),
      ).called(1);
    });
  });
}
