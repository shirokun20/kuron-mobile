import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kuron_core/kuron_core.dart';

part 'content_tag.freezed.dart';

// One persisted tag row for the local recommendation engine.
// Stored in the `content_tags` child table; never a flat JSON column,
// so tag aggregates stay queryable via SQL.
@freezed
abstract class ContentTag with _$ContentTag {
  const factory ContentTag({
    required String contentId,
    required String sourceId,
    required String name,
    required String type,
    required String origin,
  }) = _ContentTag;

  const ContentTag._();

  /// Builds normalized seed rows from a [Content]: its tags plus the
  /// structured string lists (artists, characters, parodies, groups,
  /// language) as typed synthetic rows.
  ///
  /// [contentId]/[sourceId] may differ from `content.id` (chapter-mode
  /// history rows are keyed by chapter id) — callers pass the key the
  /// sibling history/favorite row uses.
  static List<ContentTag> seedsFromContent({
    required Content content,
    required String contentId,
    required String sourceId,
    required String origin,
  }) {
    final seen = <String>{};
    final seeds = <ContentTag>[];

    void add(String rawName, String type) {
      final name = rawName.trim().toLowerCase();
      if (name.isEmpty || !seen.add(name)) return;
      seeds.add(ContentTag(
        contentId: contentId,
        sourceId: sourceId,
        name: name,
        type: type,
        origin: origin,
      ));
    }

    for (final tag in content.tags) {
      add(tag.name, tag.type.trim().toLowerCase().isEmpty ? TagType.tag : tag.type.trim().toLowerCase());
    }
    for (final v in content.artists) {
      add(v, TagType.artist);
    }
    for (final v in content.characters) {
      add(v, TagType.character);
    }
    for (final v in content.parodies) {
      add(v, TagType.parody);
    }
    for (final v in content.groups) {
      add(v, TagType.group);
    }
    add(content.language, TagType.language);

    return seeds;
  }
}
