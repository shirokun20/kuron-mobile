import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/core/utils/offline_content_manager.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/offline_search/offline_search_cubit.dart';
import 'package:nhasixapp/presentation/cubits/settings/settings_cubit.dart';
import 'package:nhasixapp/core/services/tag_blacklist_service.dart';
import 'package:nhasixapp/presentation/widgets/offline_content_body.dart';
import 'package:nhasixapp/presentation/models/content_group.dart';

// Mocks
class MockOfflineSearchCubit extends MockCubit<OfflineSearchState>
    implements OfflineSearchCubit {}

class MockDownloadBloc extends MockBloc<DownloadEvent, DownloadBlocState>
    implements DownloadBloc {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

class MockOfflineContentManager extends Mock implements OfflineContentManager {}

class MockTagBlacklistService extends Mock implements TagBlacklistService {}

class MockContentSource extends Mock implements ContentSource {}

final _fallbackContent = Content(
  id: 'fallback',
  title: 'Fallback',
  coverUrl: '',
  sourceId: 'nhentai',
  tags: [],
  artists: [],
  characters: [],
  parodies: [],
  groups: [],
  language: 'en',
  pageCount: 1,
  imageUrls: [],
  uploadDate: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  late MockOfflineSearchCubit mockOfflineSearchCubit;
  late MockDownloadBloc mockDownloadBloc;
  late MockSettingsCubit mockSettingsCubit;
  late MockRemoteConfigService mockRemoteConfigService;
  late MockOfflineContentManager mockOfflineContentManager;
  late MockTagBlacklistService mockTagBlacklistService;
  late MockContentSource mockContentSource;

  setUpAll(() {
    registerFallbackValue(_fallbackContent);
  });

  setUp(() {
    mockOfflineSearchCubit = MockOfflineSearchCubit();
    mockDownloadBloc = MockDownloadBloc();
    mockSettingsCubit = MockSettingsCubit();
    mockRemoteConfigService = MockRemoteConfigService();
    mockOfflineContentManager = MockOfflineContentManager();
    mockTagBlacklistService = MockTagBlacklistService();
    mockContentSource = MockContentSource();

    // Setup GetIt
    final getIt = GetIt.instance;
    getIt.reset();
    final registry = ContentSourceRegistry();
    final languageService = LanguageService(logger: Logger());

    if (!getIt.isRegistered<Logger>()) {
      getIt.registerSingleton<Logger>(Logger());
    }

    when(() => mockContentSource.id).thenReturn('nhentai');
    when(
      () => mockContentSource.getImageDownloadHeaders(
        imageUrl: any(named: 'imageUrl'),
        cookies: null,
      ),
    ).thenReturn(const <String, String>{});
    registry.register(mockContentSource);

    getIt.registerSingleton<OfflineSearchCubit>(mockOfflineSearchCubit);
    getIt.registerSingleton<ContentSourceRegistry>(registry);
    getIt.registerSingleton<LanguageService>(languageService);
    getIt.registerSingleton<RemoteConfigService>(mockRemoteConfigService);
    getIt.registerSingleton<OfflineContentManager>(mockOfflineContentManager);
    getIt.registerSingleton<TagBlacklistService>(mockTagBlacklistService);

    // Default Stubs
    when(() => mockRemoteConfigService.getAllSourceConfigs()).thenReturn([]);
    when(() => mockTagBlacklistService.syncAllAvailableSources())
        .thenAnswer((_) async {});
    when(
      () => mockTagBlacklistService.isContentBlacklisted(
        any(),
        localEntries: any(named: 'localEntries'),
      ),
    ).thenReturn(false);
    when(() => mockSettingsCubit.state).thenReturn(const SettingsInitial());
    when(() => mockSettingsCubit.getColumnsForOrientation(any())).thenReturn(2);
    when(() => mockDownloadBloc.state).thenReturn(const DownloadInitial());
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  Widget createWidgetUnderTest() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DownloadBloc>.value(value: mockDownloadBloc),
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        BlocProvider<OfflineSearchCubit>.value(value: mockOfflineSearchCubit),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: Scaffold(body: OfflineContentBody()),
      ),
    );
  }

  testWidgets('Infinite scroll triggers loadMoreContent', (
    WidgetTester tester,
  ) async {
    // Arrange
    // Generate enough items to ensure scrolling is possible
    final List<ContentGroup> items = List.generate(
      20,
      (index) => ContentGroup(
        baseTitle: 'Title $index',
        items: [
          Content(
            id: 'id_$index',
            title: 'Title $index',
            coverUrl: '', // Will fail image load but that's okay for this test
            sourceId: 'nhentai',
            tags: [],
            artists: [],
            characters: [],
            parodies: [],
            groups: [],
            language: 'en',
            pageCount: 10,
            imageUrls: [],
            uploadDate: DateTime.now(),
            favorites: 0,
          ),
        ],
        totalSize: 0,
        readProgress: 0.0,
        isRead: false,
        isReading: false,
      ),
    );

    // Initial state: Loaded with more pages available
    when(() => mockOfflineSearchCubit.state).thenReturn(
      OfflineSearchLoaded(
        query: '',
        results: items,
        totalResults: 100,
        currentPage: 1,
        totalPages: 5,
        hasMore: true,
        isLoadingMore: false,
      ),
    );

    // Stub loadMoreContent
    when(() => mockOfflineSearchCubit.loadMoreContent())
        .thenAnswer((_) async {});

    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(); // Frame for initial build

    // Verify initial items are rendered
    expect(find.text('Title 0'), findsOneWidget);

    // Scroll to the bottom
    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);

    await tester.drag(gridFinder, const Offset(0, -5000));
    await tester.pump(); // Trigger scroll notification processing

    // Assert
    // Verify loadMoreContent was called at least once
    verify(() => mockOfflineSearchCubit.loadMoreContent())
        .called(greaterThan(0));
  });
}
