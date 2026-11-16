import 'package:kuron_core/kuron_core.dart' show Chapter;

const unknownChapterLanguageKey = 'unknown';

class ChapterLanguageLane {
  const ChapterLanguageLane({
    required this.key,
    required this.label,
    required this.chapters,
  });

  final String key;
  final String label;
  final List<Chapter> chapters;
}

class ChapterLanguagePresentation {
  const ChapterLanguagePresentation({
    required this.lanes,
    required this.selectedKey,
  });

  final List<ChapterLanguageLane> lanes;
  final String? selectedKey;

  bool get hasMultipleLanes => lanes.length > 1;

  List<Chapter> get selectedChapters {
    if (selectedKey == null) {
      return lanes.expand((lane) => lane.chapters).toList();
    }
    return lanes
        .firstWhere(
          (lane) => lane.key == selectedKey,
          orElse: () => lanes.first,
        )
        .chapters;
  }
}

class ChapterLanguagePresenter {
  const ChapterLanguagePresenter._();

  static String normalize(String? value) {
    final raw = value?.trim().toLowerCase().replaceAll('_', '-');
    if (raw == null || raw.isEmpty) return unknownChapterLanguageKey;
    if (raw == 'pt-br' || raw == 'es-la') {
      return raw;
    }
    final base = raw.split('-').first;
    return switch (base) {
      'english' => 'en',
      'eng' => 'en',
      'indonesian' => 'id',
      'indo' => 'id',
      'japanese' => 'ja',
      'jpn' => 'ja',
      'korean' => 'ko',
      'kor' => 'ko',
      'chinese' => 'zh',
      'unknown' => unknownChapterLanguageKey,
      _ => base,
    };
  }

  static ChapterLanguagePresentation build(
    List<Chapter> chapters, {
    String? selectedKey,
    required String Function(String key) labelForKey,
  }) {
    final grouped = <String, List<Chapter>>{};
    for (final chapter in chapters) {
      grouped.putIfAbsent(normalize(chapter.language), () => []).add(chapter);
    }

    final keys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == unknownChapterLanguageKey) return 1;
        if (b == unknownChapterLanguageKey) return -1;
        return a.compareTo(b);
      });

    final lanes = [
      for (final key in keys)
        ChapterLanguageLane(
          key: key,
          label: labelForKey(key),
          chapters: List.unmodifiable(grouped[key]!),
        ),
    ];

    final normalizedSelection =
        selectedKey == null ? null : normalize(selectedKey);
    final effectiveSelection =
        lanes.any((lane) => lane.key == normalizedSelection)
            ? normalizedSelection
            : (lanes.any((lane) => lane.key == 'en')
                ? 'en'
                : (lanes.isEmpty ? null : lanes.first.key));

    return ChapterLanguagePresentation(
      lanes: lanes,
      selectedKey: lanes.length > 1 ? effectiveSelection : null,
    );
  }
}
