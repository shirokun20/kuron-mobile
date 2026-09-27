import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/blocs/download/download_bloc.dart';
import 'package:nhasixapp/presentation/pages/main/widgets/main_featured_card.dart';

class _MockDownloadBloc extends MockBloc<DownloadEvent, DownloadBlocState>
    implements DownloadBloc {}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<ContentSourceRegistry>(ContentSourceRegistry());
    getIt.registerSingleton<LanguageService>(
      LanguageService(logger: Logger(level: Level.off)),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('renders a featured card with an empty language', (tester) async {
    final downloadBloc = _MockDownloadBloc();
    when(() => downloadBloc.state).thenReturn(const DownloadInitial());

    await tester.pumpWidget(
      BlocProvider<DownloadBloc>.value(
        value: downloadBloc,
        child: MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en')],
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 160,
              child: MainFeaturedCard(
                content: Content(
                  id: 'empty-language',
                  sourceId: 'test',
                  title: 'Empty language',
                  coverUrl: '',
                  tags: const [],
                  artists: const [],
                  characters: const [],
                  parodies: const [],
                  groups: const [],
                  language: '',
                  pageCount: 0,
                  imageUrls: const [],
                  uploadDate: DateTime(2026),
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('-- '), findsOneWidget);

    await downloadBloc.close();
  });
}
