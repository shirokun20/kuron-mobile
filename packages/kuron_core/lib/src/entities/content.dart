import 'package:equatable/equatable.dart';
import 'tag.dart';
import 'chapter.dart';
import '../enums/content_type.dart';
import '../utils/text_utils.dart';

// Core content entity representing a manga/doujinshi.
///
// This entity is source-agnostic and can represent content from
// any source (nhentai, crotpedia, etc.).
class Content extends Equatable {
  const Content({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    required this.tags,
    required this.artists,
    required this.characters,
    required this.parodies,
    required this.groups,
    required this.language,
    required this.pageCount,
    required this.imageUrls,
    required this.uploadDate,
    this.url,
    this.favorites = 0,
    this.englishTitle,
    this.japaneseTitle,
    this.subTitle,
    this.mediaId,
    this.relatedContent = const [],
    this.chapters,
    // Multi-provider additions (optional — backward compatible)
    this.contentType = ContentType.doujinshi,
    this.status = ContentStatus.unknown,
    this.sourceUrl,
    this.totalChapters,
  });

  // Content ID (format varies by source)
  final String id;

  // Source identifier (e.g., 'nhentai', 'crotpedia')
  final String sourceId;

  // Primary title
  final String title;

  // Cover image URL
  final String coverUrl;

  // Content tags
  final List<Tag> tags;

  // Artist names
  final List<String> artists;

  // Character names
  final List<String> characters;

  // Parody/series names
  final List<String> parodies;

  // Group/circle names
  final List<String> groups;

  // Content language
  final String language;

  // Number of pages
  final int pageCount;

  // List of page image URLs
  final List<String> imageUrls;

  // Upload/publish date
  final DateTime uploadDate;

  // Favorites/popularity count
  final int favorites;

  // English title (if available)
  final String? englishTitle;

  // Japanese title (if available)
  final String? japaneseTitle;

  // Subtitle (if available)
  final String? subTitle;

  // Media ID (used for image URL construction in some sources)
  final String? mediaId;

  // Related content
  final List<Content> relatedContent;

  // List of chapters (for multi-chapter content like manga/webtoon)
  final List<Chapter>? chapters;

  // URL to content page (for navigation and history tracking)
  final String? url;

  // ========== Multi-Provider Additions ==========

  // Content type (doujinshi, manga, manhua, manhwa, artistCG, gameCG)
  final ContentType contentType;

  // Publication status (for chapter-based sources like MangaDex)
  final ContentStatus status;

  // Original URL at source website (e.g. https://nhentai.net/g/123456/)
  final String? sourceUrl;

  // Total number of chapters (for chapter-based sources)
  final int? totalChapters;

  @override
  List<Object?> get props => [
        id,
        sourceId,
        title,
        coverUrl,
        tags,
        artists,
        characters,
        parodies,
        groups,
        language,
        pageCount,
        imageUrls,
        uploadDate,
        url,
        favorites,
        englishTitle,
        japaneseTitle,
        subTitle,
        mediaId,
        relatedContent,
        chapters,
        contentType,
        status,
        sourceUrl,
        totalChapters,
      ];

  Content copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? coverUrl,
    List<Tag>? tags,
    List<String>? artists,
    List<String>? characters,
    List<String>? parodies,
    List<String>? groups,
    String? language,
    int? pageCount,
    List<String>? imageUrls,
    DateTime? uploadDate,
    String? url,
    int? favorites,
    String? englishTitle,
    String? japaneseTitle,
    String? subTitle,
    String? mediaId,
    List<Content>? relatedContent,
    List<Chapter>? chapters,
    ContentType? contentType,
    ContentStatus? status,
    String? sourceUrl,
    int? totalChapters,
  }) {
    return Content(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      tags: tags ?? this.tags,
      artists: artists ?? this.artists,
      characters: characters ?? this.characters,
      parodies: parodies ?? this.parodies,
      groups: groups ?? this.groups,
      language: language ?? this.language,
      pageCount: pageCount ?? this.pageCount,
      imageUrls: imageUrls ?? this.imageUrls,
      uploadDate: uploadDate ?? this.uploadDate,
      url: url ?? this.url,
      favorites: favorites ?? this.favorites,
      englishTitle: englishTitle ?? this.englishTitle,
      japaneseTitle: japaneseTitle ?? this.japaneseTitle,
      subTitle: subTitle ?? this.subTitle,
      mediaId: mediaId ?? this.mediaId,
      relatedContent: relatedContent ?? this.relatedContent,
      chapters: chapters ?? this.chapters,
      contentType: contentType ?? this.contentType,
      status: status ?? this.status,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      totalChapters: totalChapters ?? this.totalChapters,
    );
  }

  // Get display title based on preference.
  //
  // Normalized here as a display-level safety net: cached content produced
  // before the parser fix (or by a non-generic source) may still carry
  // newlines/repeated spaces, which would clip the one-line Reader app bar.
  String getDisplayTitle({bool preferEnglish = true}) {
    if (preferEnglish && englishTitle != null && englishTitle!.isNotEmpty) {
      return normalizeWhitespace(englishTitle!);
    }
    if (japaneseTitle != null && japaneseTitle!.isNotEmpty) {
      return normalizeWhitespace(japaneseTitle!);
    }
    return normalizeWhitespace(title);
  }

  // Check if content has specific tag
  bool hasTag(String tagName) {
    return tags.any((tag) => tag.name.toLowerCase() == tagName.toLowerCase());
  }

  // Check if content has specific artist
  bool hasArtist(String artistName) {
    return artists
        .any((artist) => artist.toLowerCase() == artistName.toLowerCase());
  }

  // Get tags by type
  List<Tag> getTagsByType(String type) {
    return tags.where((tag) => tag.type == type).toList();
  }

  // Get content category
  String get category {
    final categoryTags = getTagsByType('category');
    return categoryTags.isNotEmpty ? categoryTags.first.name : 'doujinshi';
  }
}
