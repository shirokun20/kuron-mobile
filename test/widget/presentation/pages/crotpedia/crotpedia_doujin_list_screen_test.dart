import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/domain/entities/crotpedia/crotpedia_entities.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_cubit.dart';
import 'package:nhasixapp/presentation/cubits/crotpedia_feature/crotpedia_feature_state.dart';
import 'package:nhasixapp/presentation/pages/crotpedia/doujin_list_screen.dart';
import 'package:nhasixapp/presentation/widgets/error_widget.dart';
import 'package:nhasixapp/presentation/widgets/progress_indicator_widget.dart';

class MockCrotpediaFeatureCubit extends MockCubit<CrotpediaFeatureState>
    implements CrotpediaFeatureCubit {}

class MockDownloadBloc extends MockBloc<DownloadEvent, DownloadBlocState>
    implements DownloadBloc {}

void main() {
  late MockCrotpediaFeatureCubit mockCubit;
  late MockDownloadBloc mockDownloadBloc;

  setUp(() {
    mockCubit = MockCrotpediaFeatureCubit();
    mockDownloadBloc = MockDownloadBloc();
    when(() => mockDownloadBloc.state).thenReturn(const DownloadInitial());
    if (GetIt.instance.isRegistered<CrotpediaFeatureCubit>()) {
      GetIt.instance.unregister<CrotpediaFeatureCubit>();
    }
    GetIt.instance.registerFactory<CrotpediaFeatureCubit>(() => mockCubit);
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
        child: const CrotpediaDoujinListScreen(),
      ),
    );
  }

  group('CrotpediaDoujinListScreen', () {
    testWidgets('shows shimmer loading when state is loading', (tester) async {
      when(() => mockCubit.state).thenReturn(CrotpediaFeatureLoading());
      when(() => mockCubit.loadDoujinList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      // It's a private class, so we can't find by type easily unless we export it or find by key/structure
      // But looking at the implementation, it returns a _DoujinListShimmer which contains a ListView
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows syncing indicator when state is syncing', (
      tester,
    ) async {
      const syncMessage = 'Syncing data...';
      when(() => mockCubit.state)
          .thenReturn(const CrotpediaFeatureSyncing(syncMessage));
      when(() => mockCubit.loadDoujinList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text(syncMessage), findsOneWidget);
      expect(find.byType(AppProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error widget when state is error', (tester) async {
      const errorMessage = 'Failed to load doujins';
      when(() => mockCubit.state)
          .thenReturn(const CrotpediaFeatureError(errorMessage));
      when(() => mockCubit.loadDoujinList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text(errorMessage), findsOneWidget);
    });

    testWidgets('shows list of doujins when state is loaded', (tester) async {
      // Set a large enough screen size to avoid overflow in AlphabetNavigator
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final doujins = [
        DoujinListItem(title: 'Doujin A', url: '/doujin/a'),
        DoujinListItem(title: 'Doujin B', url: '/doujin/b'),
      ];
      when(() => mockCubit.state).thenReturn(DoujinListLoaded(doujins));
      when(() => mockCubit.loadDoujinList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      // Should find titles
      expect(find.text('Doujin A'), findsOneWidget);
      expect(find.text('Doujin B'), findsOneWidget);

      // Should find search field
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows empty message when list is empty', (tester) async {
      when(() => mockCubit.state).thenReturn(const DoujinListLoaded([]));
      when(() => mockCubit.loadDoujinList()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(find.text('No Doujins Found'), findsOneWidget);
    });
  });
}
