import 'package:flutter/foundation.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/presentation/cubits/detail/detail_cubit.dart';
import 'package:nhasixapp/presentation/utils/chapter_language_presenter.dart';

class DetailMangaFireCoordinator extends ChangeNotifier {
  DetailMangaFireCoordinator({required this._detailCubit});

  final DetailCubit _detailCubit;

  String _selectedType = 'Chapter';
  String? _selectedLanguageKey;
  bool _isLoadingLane = false;

  String get selectedType => _selectedType;
  String? get selectedLanguageKey => _selectedLanguageKey;
  bool get isLoadingLane => _isLoadingLane;

  List<String> extractAvailableLanguageKeys(Content content) {
    final metadataKeys = content.tags
        .where((tag) => tag.type == '__mangafire_chapter_language')
        .map((tag) => ChapterLanguagePresenter.normalize(tag.name))
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    if (metadataKeys.isNotEmpty) {
      metadataKeys.sort();
      return metadataKeys;
    }

    final chapterKeys = (content.chapters ?? const <Chapter>[])
        .map((chapter) => ChapterLanguagePresenter.normalize(chapter.language))
        .toSet()
        .toList();
    chapterKeys.sort();
    return chapterKeys;
  }

  bool hasGroup(Content content, String group) {
    return content.tags.any(
          (tag) => tag.type == '__mangafire_chapter_group' && tag.name == group,
        ) ||
        (content.chapters?.any((chapter) => chapter.scanGroup == group) ??
            false);
  }

  String? resolveSelectedLanguage(Content content) {
    final availableKeys = extractAvailableLanguageKeys(content);
    if (availableKeys.isEmpty) {
      return null;
    }

    final selected = _selectedLanguageKey == null
        ? null
        : ChapterLanguagePresenter.normalize(_selectedLanguageKey);
    if (selected != null && availableKeys.contains(selected)) {
      return selected;
    }

    final contentLanguage =
        ChapterLanguagePresenter.normalize(content.language);
    if (availableKeys.contains(contentLanguage)) {
      return contentLanguage;
    }
    if (availableKeys.contains('en')) {
      return 'en';
    }
    return availableKeys.first;
  }

  bool hasLoadedLane({
    required Content content,
    required String languageKey,
    required String scanGroup,
  }) {
    return content.chapters?.any(
          (chapter) =>
              chapter.scanGroup == scanGroup &&
              ChapterLanguagePresenter.normalize(chapter.language) ==
                  languageKey,
        ) ??
        false;
  }

  Future<void> loadLaneIfNeeded({
    required Content content,
    required String languageKey,
    required String scanGroup,
  }) async {
    if (_isLoadingLane ||
        hasLoadedLane(
          content: content,
          languageKey: languageKey,
          scanGroup: scanGroup,
        )) {
      return;
    }

    _isLoadingLane = true;
    notifyListeners();
    try {
      await _detailCubit.loadChapterLane(
        language: languageKey,
        scanGroup: scanGroup,
      );
    } finally {
      _isLoadingLane = false;
      notifyListeners();
    }
  }

  Future<void> onLanguageSelected(Content content, String languageKey) async {
    _selectedLanguageKey = languageKey;
    notifyListeners();
    await loadLaneIfNeeded(
      content: content,
      languageKey: ChapterLanguagePresenter.normalize(languageKey),
      scanGroup: _selectedType,
    );
  }

  Future<void> onTypeSelected(Content content, String scanGroup) async {
    _selectedType = scanGroup;
    notifyListeners();
    final languageKey = resolveSelectedLanguage(content);
    if (languageKey == null) {
      return;
    }
    await loadLaneIfNeeded(
      content: content,
      languageKey: languageKey,
      scanGroup: scanGroup,
    );
  }

  Content resolveChapterDisplayContent(Content content) {
    if (content.sourceId != 'mangafire' || content.chapters == null) {
      return content;
    }

    if (!hasGroup(content, 'Chapter') || !hasGroup(content, 'Volume')) {
      return content;
    }

    return content.copyWith(
      chapters:
          content.chapters!.where((c) => c.scanGroup == _selectedType).toList(),
    );
  }
}
