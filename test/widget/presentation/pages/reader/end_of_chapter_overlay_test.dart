import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalCupertinoLocalizations, GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/l10n/app_localizations.dart';
import 'package:nhasixapp/presentation/cubits/reader/reader_cubit.dart';
import 'package:nhasixapp/presentation/pages/reader/end_of_chapter_overlay.dart';

void main() {
  Content buildContent() {
    return Content(
      id: '__ehpart__:3906586:971a6d4051:1',
      sourceId: 'ehentai',
      title: 'Sample Gallery - Part 2',
      coverUrl: 'https://cover.example/1.webp',
      tags: const [],
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: 'english',
      pageCount: 2,
      imageUrls: const [
        'https://img.example/1.webp',
        'https://img.example/2.webp',
      ],
      uploadDate: DateTime.parse('2026-05-20T00:00:00Z'),
    );
  }

  testWidgets('shows part semantics from chapterData labels', (tester) async {
    final state = ReaderState(
      content: buildContent(),
      currentPage: 3,
      chapterData: const ChapterData(
        images: ['https://img.example/1.webp', 'https://img.example/2.webp'],
        prevChapterId: '__ehpart__:3906586:971a6d4051:0',
        nextChapterId: '__ehpart__:3906586:971a6d4051:2',
        prevChapterTitle: 'Part 1',
        nextChapterTitle: 'Part 3',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: EndOfChapterOverlay(
          state: state,
          isChapterMode: true,
          onBackToDetail: () {},
          onPreviousChapter: () {},
          onNextChapter: () {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Part 3'), findsOneWidget);
    expect(find.text('Load more images'), findsNothing);
  });
}
