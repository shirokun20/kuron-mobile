import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/cubits/detail/detail_cubit.dart';
import 'package:nhasixapp/presentation/pages/detail/services/detail_mangafire_coordinator.dart';

class MockDetailCubit extends Mock implements DetailCubit {}

void main() {
  late MockDetailCubit mockDetailCubit;
  late DetailMangaFireCoordinator coordinator;

  setUp(() {
    mockDetailCubit = MockDetailCubit();
    coordinator = DetailMangaFireCoordinator(detailCubit: mockDetailCubit);
  });

  group('DetailMangaFireCoordinator', () {
    test('initial state is correct', () {
      expect(coordinator.selectedType, 'Chapter');
      expect(coordinator.selectedLanguageKey, isNull);
      expect(coordinator.isLoadingLane, isFalse);
    });

    test('extractAvailableLanguageKeys sorts and removes empty keys', () {
      final content = Content(
        id: '1',
        title: 'Test Content',
        sourceId: 'mangafire',
        url: '',
        coverUrl: '',
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: '',
        pageCount: 0,
        imageUrls: const [],
        uploadDate: DateTime(2020),
        tags: [
          const Tag(
              id: 1,
              count: 0,
              name: 'en',
              type: '__mangafire_chapter_language'),
          const Tag(
              id: 1,
              count: 0,
              name: 'fr',
              type: '__mangafire_chapter_language'),
          const Tag(
              id: 1,
              count: 0,
              name: '',
              type: '__mangafire_chapter_language'), // Should be ignored
        ],
      );

      final keys = coordinator.extractAvailableLanguageKeys(content);
      expect(keys, ['en', 'fr', 'unknown']);
    });

    test('hasGroup returns true if group is present in tags', () {
      final content = Content(
        id: '1',
        title: 'Test Content',
        sourceId: 'mangafire',
        url: '',
        coverUrl: '',
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: '',
        pageCount: 0,
        imageUrls: const [],
        uploadDate: DateTime(2020),
        tags: [
          const Tag(
              id: 1,
              count: 0,
              name: 'Volume',
              type: '__mangafire_chapter_group'),
        ],
      );

      expect(coordinator.hasGroup(content, 'Volume'), isTrue);
      expect(coordinator.hasGroup(content, 'Chapter'), isFalse);
    });

    test('resolveSelectedLanguage falls back to en if available', () {
      final content = Content(
        id: '1',
        title: 'Test',
        sourceId: 'mangafire',
        url: '',
        coverUrl: '',
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: 'it',
        pageCount: 0,
        imageUrls: const [],
        uploadDate: DateTime(2020),
        tags: [
          const Tag(
              id: 1,
              count: 0,
              name: 'en',
              type: '__mangafire_chapter_language'),
          const Tag(
              id: 1,
              count: 0,
              name: 'fr',
              type: '__mangafire_chapter_language'),
        ],
      );

      final lang = coordinator.resolveSelectedLanguage(content);
      expect(lang, 'en');
    });

    test(
        'resolveSelectedLanguage defaults to en even when content.language is another language',
        () {
      final content = Content(
        id: '1',
        title: 'Test',
        sourceId: 'mangafire',
        url: '',
        coverUrl: '',
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: 'es-la',
        pageCount: 0,
        imageUrls: const [],
        uploadDate: DateTime(2020),
        tags: [
          const Tag(
              id: 1,
              count: 0,
              name: 'es-la',
              type: '__mangafire_chapter_language'),
          const Tag(
              id: 1,
              count: 0,
              name: 'en',
              type: '__mangafire_chapter_language'),
        ],
      );

      final lang = coordinator.resolveSelectedLanguage(content);
      expect(lang, 'en');
    });

    test('loadLaneIfNeeded calls loadChapterLane and updates loading state',
        () async {
      when(() => mockDetailCubit.loadChapterLane(
            language: any(named: 'language'),
            scanGroup: any(named: 'scanGroup'),
          )).thenAnswer((_) async {});

      final content = Content(
        id: '1',
        title: 'Test Content',
        sourceId: 'mangafire',
        url: '',
        coverUrl: '',
        artists: const [],
        characters: const [],
        parodies: const [],
        groups: const [],
        language: '',
        pageCount: 0,
        imageUrls: const [],
        uploadDate: DateTime(2020),
        chapters: const [],
        tags: const [],
      );

      // We don't await immediately to check loading state
      final future = coordinator.loadLaneIfNeeded(
        content: content,
        languageKey: 'en',
        scanGroup: 'Chapter',
      );

      expect(coordinator.isLoadingLane, isTrue);
      await future;
      expect(coordinator.isLoadingLane, isFalse);

      verify(() => mockDetailCubit.loadChapterLane(
          language: 'en', scanGroup: 'Chapter')).called(1);
    });
  });
}
