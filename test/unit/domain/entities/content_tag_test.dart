import 'package:flutter_test/flutter_test.dart';
import 'package:kuron_core/kuron_core.dart';
import 'package:nhasixapp/domain/entities/content_tag.dart';

Content _content({
  List<Tag> tags = const [],
  List<String> artists = const [],
  List<String> characters = const [],
  List<String> parodies = const [],
  List<String> groups = const [],
  String language = 'english',
}) {
  return Content(
    id: 'c1',
    sourceId: 'nhentai',
    title: 'T',
    coverUrl: 'http://cover',
    tags: tags,
    artists: artists,
    characters: characters,
    parodies: parodies,
    groups: groups,
    language: language,
    pageCount: 10,
    imageUrls: const [],
    uploadDate: DateTime(2026, 1, 1),
  );
}

Tag _tag(String name, [String type = 'tag']) =>
    Tag(id: 1, name: name, type: type, count: 1);

void main() {
  group('ContentTag.seedsFromContent', () {
    test('maps tags + artists + language with types', () {
      final seeds = ContentTag.seedsFromContent(
        content: _content(
          tags: [_tag('Action'), _tag('Fantasy')],
          artists: ['Some Artist'],
        ),
        contentId: 'c1',
        sourceId: 'nhentai',
        origin: 'history',
      );

      final byName = {for (final s in seeds) s.name: s};
      expect(byName['action']?.type, 'tag');
      expect(byName['fantasy']?.type, 'tag');
      expect(byName['some artist']?.type, 'artist');
      expect(byName['english']?.type, 'language');
      for (final s in seeds) {
        expect(s.contentId, 'c1');
        expect(s.sourceId, 'nhentai');
        expect(s.origin, 'history');
      }
    });

    test('normalizes case/whitespace and dedups by name', () {
      final seeds = ContentTag.seedsFromContent(
        content: _content(
          tags: [_tag('Action'), _tag('  ACTION  ')],
          artists: ['action'],
        ),
        contentId: 'c1',
        sourceId: 'nhentai',
        origin: 'favorite',
      );

      expect(seeds.where((s) => s.name == 'action').length, 1);
    });

    test('drops empty names and empty language', () {
      final seeds = ContentTag.seedsFromContent(
        content: _content(tags: [_tag('  '), _tag('Solo')], language: ''),
        contentId: 'c1',
        sourceId: 'nhentai',
        origin: 'history',
      );

      expect(seeds.map((s) => s.name), contains('solo'));
      expect(seeds.any((s) => s.name.isEmpty), isFalse);
    });

    test('content without any tags yields empty list', () {
      final seeds = ContentTag.seedsFromContent(
        content: _content(language: ''),
        contentId: 'c1',
        sourceId: 'nhentai',
        origin: 'history',
      );

      expect(seeds, isEmpty);
    });

    test('key may differ from content.id (chapter-mode history)', () {
      final seeds = ContentTag.seedsFromContent(
        content: _content(tags: [_tag('Action')]),
        contentId: 'chapter-9',
        sourceId: 'nhentai',
        origin: 'history',
      );

      expect(seeds.first.contentId, 'chapter-9');
    });
  });
}
