import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/crotpedia/crotpedia_entities.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/pages/crotpedia/request_list_screen.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';

class MockCrotpediaFeatureCubit extends MockCubit<CrotpediaFeatureState>
    implements CrotpediaFeatureCubit {}

class MockContentSource extends Mock implements ContentSource {}

class MockDownloadBloc extends MockBloc<DownloadEvent, DownloadBlocState>
    implements DownloadBloc {}

void main() {
  late MockCrotpediaFeatureCubit mockCubit;
  late MockContentSource mockContentSource;
  late MockDownloadBloc mockDownloadBloc;

  setUp(() {
    mockCubit = MockCrotpediaFeatureCubit();
    mockContentSource = MockContentSource();
    mockDownloadBloc = MockDownloadBloc();
    when(() => mockDownloadBloc.state).thenReturn(const DownloadInitial());

    if (GetIt.instance.isRegistered<CrotpediaFeatureCubit>()) {
      GetIt.instance.unregister<CrotpediaFeatureCubit>();
    }
    if (GetIt.instance.isRegistered<ContentSourceRegistry>()) {
      GetIt.instance.unregister<ContentSourceRegistry>();
    }

    final registry = ContentSourceRegistry();
    when(() => mockContentSource.id).thenReturn(SourceType.crotpedia.id);
    when(
      () => mockContentSource.getImageDownloadHeaders(
        imageUrl: any(named: 'imageUrl'),
        cookies: null,
      ),
    ).thenReturn(const <String, String>{});
    registry.register(mockContentSource);

    GetIt.instance.registerFactory<CrotpediaFeatureCubit>(() => mockCubit);
    GetIt.instance.registerSingleton<ContentSourceRegistry>(registry);
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
        child: const CrotpediaRequestListScreen(),
      ),
    );
  }

  group('CrotpediaRequestListScreen', () {
    testWidgets('shows loading indicator when state is loading', (
      tester,
    ) async {
      when(() => mockCubit.state).thenReturn(CrotpediaFeatureLoading());
      when(() => mockCubit.loadRequestList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      // Should show shimmer list (ListView)
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows error widget when state is error', (tester) async {
      const errorMessage = 'Failed to load requests';
      when(() => mockCubit.state)
          .thenReturn(const CrotpediaFeatureError(errorMessage));
      when(() => mockCubit.loadRequestList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text(errorMessage), findsOneWidget);
    });

    testWidgets('shows list of requests when state is loaded', (tester) async {
      final requests = [
        RequestItem(
          id: 1,
          title: 'Request A',
          url: '/request/a',
          coverUrl: 'https://example.com/cover1.jpg',
          genres: {'action': 'Action'},
        ),
        RequestItem(
          id: 2,
          title: 'Request B',
          url: '/request/b',
          coverUrl: 'https://example.com/cover2.jpg',
          genres: {'romance': 'Romance'},
        ),
      ];
      when(() => mockCubit.state).thenReturn(RequestListLoaded(requests));
      when(() => mockCubit.loadRequestList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump(); // Pump for image loading if needed

      // Should find titles
      expect(find.text('Request A'), findsOneWidget);
      expect(find.text('Request B'), findsOneWidget);

      // Should find genres
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Romance'), findsOneWidget);
    });

    testWidgets('shows empty message when list is empty', (tester) async {
      when(() => mockCubit.state).thenReturn(const RequestListLoaded([]));
      when(() => mockCubit.loadRequestList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text('No Requests Found'), findsOneWidget);
    });
  });
}
