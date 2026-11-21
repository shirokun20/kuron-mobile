import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/config/remote_config_service.dart';
import 'package:nhasixapp/domain/entities/crotpedia/crotpedia_entities.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/pages/crotpedia/genre_list_screen.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';
import 'package:nhasixapp/presentation/widgets/shimmer_loading_widgets.dart';

class MockCrotpediaFeatureCubit extends MockCubit<CrotpediaFeatureState>
    implements CrotpediaFeatureCubit {}

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

class MockDownloadBloc extends MockBloc<DownloadEvent, DownloadBlocState>
    implements DownloadBloc {}

void main() {
  late MockCrotpediaFeatureCubit mockCubit;
  late MockRemoteConfigService mockRemoteConfigService;
  late MockDownloadBloc mockDownloadBloc;

  setUp(() {
    mockCubit = MockCrotpediaFeatureCubit();
    mockRemoteConfigService = MockRemoteConfigService();
    mockDownloadBloc = MockDownloadBloc();
    when(() => mockDownloadBloc.state).thenReturn(const DownloadInitial());
    if (GetIt.instance.isRegistered<CrotpediaFeatureCubit>()) {
      GetIt.instance.unregister<CrotpediaFeatureCubit>();
    }
    if (GetIt.instance.isRegistered<RemoteConfigService>()) {
      GetIt.instance.unregister<RemoteConfigService>();
    }

    when(() => mockRemoteConfigService.getRawConfig('crotpedia'))
        .thenReturn(<String, dynamic>{
          'navigation': <String, dynamic>{'genreQueryPrefix': 'genre:'},
        });

    GetIt.instance.registerFactory<CrotpediaFeatureCubit>(() => mockCubit);
    GetIt.instance.registerSingleton<RemoteConfigService>(
      mockRemoteConfigService,
    );
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: BlocProvider<DownloadBloc>.value(
        value: mockDownloadBloc,
        child: const CrotpediaGenreListScreen(),
      ),
    );
  }

  group('CrotpediaGenreListScreen', () {
    testWidgets('shows shimmer loading when state is loading', (tester) async {
      when(() => mockCubit.state).thenReturn(CrotpediaFeatureLoading());
      when(() => mockCubit.loadGenreList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(GenreListShimmer), findsOneWidget);
    });

    testWidgets('shows error widget when state is error', (tester) async {
      const errorMessage = 'Failed to load genres';
      when(() => mockCubit.state)
          .thenReturn(const CrotpediaFeatureError(errorMessage));
      when(() => mockCubit.loadGenreList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text(errorMessage), findsOneWidget);
    });

    testWidgets('shows list of genres when state is loaded', (tester) async {
      final genres = [
        GenreItem(
          name: 'Action',
          count: 10,
          url: '/genre/action',
          slug: 'action',
        ),
        GenreItem(
          name: 'Romance',
          count: 5,
          url: '/genre/romance',
          slug: 'romance',
        ),
      ];
      when(() => mockCubit.state).thenReturn(GenreListLoaded(genres));
      when(() => mockCubit.loadGenreList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Action'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Romance'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows header with genre count when loaded', (tester) async {
      final genres = [
        GenreItem(
          name: 'Action',
          count: 10,
          url: '/genre/action',
          slug: 'action',
        ),
      ];
      when(() => mockCubit.state).thenReturn(GenreListLoaded(genres));
      when(() => mockCubit.loadGenreList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Browse by Genre'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // genre count badge
    });

    testWidgets('shows empty state when genre list is empty', (tester) async {
      when(() => mockCubit.state).thenReturn(const GenreListLoaded([]));
      when(() => mockCubit.loadGenreList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text('No Genres Found'), findsOneWidget);
    });
  });
}
