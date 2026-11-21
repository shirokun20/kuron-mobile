import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:logger/logger.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/core/services/language_service.dart';
import 'package:nhasixapp/presentation/widgets/content_card_widget.dart';

Content _content() {
  return Content(
    id: '1',
    sourceId: 'nhentai',
    title: 'Test Title',
    coverUrl: '',
    tags: const [],
    artists: const [],
    characters: const [],
    parodies: const [],
    groups: const [],
    language: 'en',
    pageCount: 0,
    imageUrls: const [],
    uploadDate: DateTime(2026, 1, 1),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );
}

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<ContentSourceRegistry>(
      ContentSourceRegistry(),
    );
    GetIt.instance.registerSingleton<LanguageService>(
      LanguageService(logger: Logger()),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('shows read badge only for read content', (tester) async {
    await tester.pumpWidget(
      _wrap(ContentCard(content: _content(), readProgress: 1.0)),
    );
    await tester.pumpAndSettle();

    expect(find.text('READ'), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing);
  });

  testWidgets('shows offline badge on the left when offline only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ContentCard(content: _content(), showDownloadBadge: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('READ'), findsNothing);
  });

  testWidgets('keeps read and offline badges separated', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ContentCard(
          content: _content(),
          showDownloadBadge: true,
          readProgress: 1.0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offlineBadge = find.text('OFFLINE');
    final readBadge = find.text('READ');

    expect(offlineBadge, findsOneWidget);
    expect(readBadge, findsOneWidget);
    expect(
      tester.getTopLeft(offlineBadge).dx,
      lessThan(tester.getTopLeft(readBadge).dx),
    );
    expect(
      tester.getTopLeft(offlineBadge).dy,
      equals(tester.getTopLeft(readBadge).dy),
    );
  });
}
