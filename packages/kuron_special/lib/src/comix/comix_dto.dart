import 'dart:math';

// Exact port of keiyoushi `src/en/comix` Dto.kt response models.
// Plain Dart classes with manual fromJson (kuron_special has no
// freezed/build_runner; mirrors sibling adapters like HitomiAdapter).

const String mangaIdMemo = 'mangaId';
const String chapterIdMemo = 'chapterId';
const String chapterVotesMemo = 'votes';
const String chapterOfficialMemo = 'official';
const String chapterGroupIdMemo = 'groupId';

class Term {
  const Term(this.title);

  final String title;

  factory Term.fromJson(dynamic json) {
    if (json is String) return Term(json);
    return Term((json as Map)['title'] as String? ?? '');
  }
}

class TagSearchResponse {
  const TagSearchResponse(this.result);

  final List<TagSearchHit> result;

  factory TagSearchResponse.fromJson(Map<String, dynamic> json) =>
      TagSearchResponse(
        ((json['result'] as List?) ?? [])
            .map((e) => TagSearchHit.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TagSearchHit {
  const TagSearchHit(this.id);

  final int id;

  factory TagSearchHit.fromJson(Map<String, dynamic> json) =>
      TagSearchHit((json['id'] as num).toInt());
}

class ComixPoster {
  const ComixPoster({this.small, this.medium, this.large});

  final String? small;
  final String? medium;
  final String? large;

  factory ComixPoster.fromJson(Map<String, dynamic> json) => ComixPoster(
        small: json['small'] as String?,
        medium: json['medium'] as String?,
        large: json['large'] as String?,
      );

  String from(String? quality) {
    switch (quality) {
      case 'large':
        return large ?? medium ?? small ?? '';
      case 'small':
        return small ?? medium ?? large ?? '';
      default:
        return medium ?? large ?? small ?? '';
    }
  }
}

class ComixManga {
  const ComixManga({
    required this.hid,
    required this.title,
    this.altTitles = const [],
    this.synopsis,
    this.type = '',
    this.poster,
    this.status = '',
    this.contentRating = 'safe',
    this.authors,
    this.artists,
    this.genres,
    this.tags,
    this.demographics,
    this.ratedAvg = 0.0,
    this.ratedCount = 0,
    this.followsTotal = 0,
    this.rank = 0,
    this.year,
    this.originalLanguage,
    this.links,
    this.url,
  });

  final String hid;
  final String title;
  final List<String> altTitles;
  final String? synopsis;
  final String type;
  final ComixPoster? poster;
  final String status;
  final String contentRating;
  final List<Term>? authors;
  final List<Term>? artists;
  final List<Term>? genres;
  final List<Term>? tags;
  final List<Term>? demographics;
  final double ratedAvg;
  final int ratedCount;
  final int followsTotal;
  final int rank;
  final int? year;
  final String? originalLanguage;
  final Map<String, String?>? links;
  final String? url;

  static List<Term>? _terms(dynamic v) {
    if (v == null) return null;
    return (v as List).map(Term.fromJson).toList();
  }

  static List<String> _strings(dynamic v) {
    if (v == null) return const [];
    return (v as List).map((e) => e.toString()).toList();
  }

  factory ComixManga.fromJson(Map<String, dynamic> json) {
    List<String> alt(dynamic a, dynamic b) {
      final primary = _strings(a);
      return primary.isNotEmpty ? primary : _strings(b);
    }

    return ComixManga(
      hid: json['hid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      altTitles: alt(json['altTitles'], json['alt_titles']),
      synopsis: json['synopsis'] as String?,
      type: json['type'] as String? ?? '',
      poster: json['poster'] == null
          ? null
          : ComixPoster.fromJson(json['poster'] as Map<String, dynamic>),
      status: json['status'] as String? ?? '',
      contentRating: json['contentRating'] as String? ?? 'safe',
      authors: _terms(json['authors'] ?? json['author']),
      artists: _terms(json['artists'] ?? json['artist']),
      genres: _terms(json['genres'] ?? json['genre']),
      tags: _terms(json['tags'] ?? json['theme']),
      demographics: _terms(json['demographics'] ?? json['demographic']),
      ratedAvg: (json['ratedAvg'] as num?)?.toDouble() ?? 0.0,
      ratedCount: (json['ratedCount'] as num?)?.toInt() ?? 0,
      followsTotal: (json['followsTotal'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt(),
      originalLanguage: json['originalLanguage'] as String?,
      links: (json['links'] as Map?)
          ?.map((k, v) => MapEntry(k.toString(), v?.toString())),
      url: json['url'] as String?,
    );
  }

  /// Detail page slug, e.g. `/n93ny-the-crown-ill-claim`.
  String get detailPath {
    if (url != null && url!.contains('/title')) {
      return url!.substring(url!.indexOf('/title') + '/title'.length);
    }
    return '/$hid';
  }

  String fancyScore() {
    if (ratedAvg == 0.0) return '';
    final stars = (ratedAvg / 2).round().clamp(0, 5);
    final scoreString = ratedAvg.truncateToDouble() == ratedAvg
        ? ratedAvg.toInt().toString()
        : ratedAvg.toString().replaceAll(RegExp(r'0+$'), '');
    return '${'★' * stars}${'☆' * (5 - stars)} $scoreString';
  }

  String genreString({bool showTags = false}) {
    final out = <String>[];
    switch (type) {
      case 'manhwa':
        out.add('Manhwa');
      case 'manhua':
        out.add('Manhua');
      case 'manga':
        out.add('Manga');
      default:
        out.add('Other');
    }
    genres?.map((e) => e.title).forEach(out.add);
    demographics?.map((e) => e.title).forEach(out.add);
    if (showTags) tags?.map((e) => e.title).forEach(out.add);
    if (contentRating == 'erotica' || contentRating == 'pornographic') {
      out.add('NSFW');
    }
    return out.toSet().join(', ');
  }

  String description({
    bool altTitlesInDesc = false,
    String scorePosition = 'top',
    bool showExtraInfo = true,
  }) {
    final buf = StringBuffer();
    final score = fancyScore();
    if (scorePosition == 'top' && score.isNotEmpty) buf.write('$score\n\n');
    if (synopsis != null && synopsis!.isNotEmpty) buf.write(synopsis);
    if (altTitlesInDesc && altTitles.isNotEmpty) {
      buf.write('\n\n**Alternative Names**:\n');
      buf.write(altTitles.map((t) => '- $t').join('\n'));
    }
    if (showExtraInfo) {
      final extras = <String>[];
      if (year != null && year! > 0) extras.add('**Year**: $year');
      if (originalLanguage != null && originalLanguage!.isNotBlank) {
        extras.add('**Language**: ${originalLanguage!.toUpperCase()}');
      }
      if (contentRating.isNotBlank) {
        extras.add(
            '**Content rating**: ${contentRating[0].toUpperCase()}${contentRating.substring(1)}');
      }
      if (rank > 0) extras.add('**Rank**: #$rank');
      if (ratedCount > 0) extras.add('**Rated by**: $ratedCount');
      if (followsTotal > 0) extras.add('**Followed by**: $followsTotal');
      if (extras.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write(extras.join('\n'));
      }
      final trackers = trackerLinks();
      if (trackers.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write('**Trackers**:\n${trackers.join('\n')}');
      }
    }
    if (scorePosition == 'bottom' && score.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write(score);
    }
    return buf.toString();
  }

  List<String> trackerLinks() {
    final linkMap = links;
    if (linkMap == null) return const [];
    const known = [
      MapEntry('al', 'AniList'),
      MapEntry('mal', 'MyAnimeList'),
      MapEntry('mu', 'MangaUpdates'),
      MapEntry('md', 'MangaDex'),
      MapEntry('mb', 'MangaBaka'),
    ];
    final out = <String>[];
    for (final e in known) {
      final u = linkMap[e.key];
      if (u != null && u.isNotBlank) out.add('[${e.value}]($u)');
    }
    linkMap.forEach((key, u) {
      if (known.any((e) => e.key == key)) return;
      if (u != null && u.startsWith('http')) {
        out.add('[${key.toUpperCase()}]($u)');
      }
    });
    return out;
  }
}

class _PagedItems<T> {
  const _PagedItems({required this.items, this.meta, this.pagination});

  final List<T> items;
  final _Meta? meta;
  final _Meta? pagination;

  bool hasNextPage() {
    if (meta != null) return meta!.page < meta!.actualLastPage;
    if (pagination != null) {
      return pagination!.page < pagination!.actualLastPage;
    }
    return false;
  }

  static _Meta? _parseMeta(dynamic v) =>
      v == null ? null : _Meta.fromJson(v as Map<String, dynamic>);
}

class _Meta {
  const _Meta({this.page = 1, this.lastPage = 1});

  final int page;
  final int lastPage;

  int get actualLastPage => lastPage;

  factory _Meta.fromJson(Map<String, dynamic> json) => _Meta(
        page: (json['page'] as num?)?.toInt() ?? 1,
        lastPage: max(
          (json['lastPage'] as num?)?.toInt() ?? 1,
          (json['last_page'] as num?)?.toInt() ?? 1,
        ),
      );
}

class SearchResponse {
  const SearchResponse(this.items, this.hasNext);

  final List<ComixManga> items;
  final bool hasNext;

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    dynamic node = json['result'];
    if (node == null && json['items'] is List) {
      // Mangafire envelope: top-level {items, meta} (live `$.items[*]`).
      node = json;
    }
    if (node is Map<String, dynamic> &&
        node['items'] == null &&
        node['result'] is Map) {
      node = node['result'];
    }
    final map = node as Map<String, dynamic>? ?? {};
    final items = ((map['items'] as List?) ?? [])
        .map((e) => ComixManga.fromJson(e as Map<String, dynamic>))
        .toList();
    final paged = _PagedItems<ComixManga>(
      items: items,
      meta: _PagedItems._parseMeta(map['meta']),
      pagination: _PagedItems._parseMeta(map['pagination']),
    );
    return SearchResponse(items, paged.hasNextPage());
  }
}

class ChapterDetailsResponse {
  const ChapterDetailsResponse(this.items, this.hasNext);

  final List<ComixChapter> items;
  final bool hasNext;

  factory ChapterDetailsResponse.fromJson(Map<String, dynamic> json) {
    final map = json['result'] as Map<String, dynamic>? ?? {};
    final items = ((map['items'] as List?) ?? [])
        .map((e) => ComixChapter.fromJson(e as Map<String, dynamic>))
        .toList();
    final paged = _PagedItems<ComixChapter>(
      items: items,
      meta: _PagedItems._parseMeta(map['meta']),
      pagination: _PagedItems._parseMeta(map['pagination']),
    );
    return ChapterDetailsResponse(items, paged.hasNextPage());
  }
}

class ComixChapter {
  const ComixChapter({
    required this.id,
    this.url = '',
    required this.number,
    this.name = '',
    this.votes = 0,
    this.createdAtFormatted = '',
    this.createdAtEpoch,
    this.language,
    this.groupId,
    this.groupName,
    this.isOfficial = false,
  });

  final int id;
  final String url;
  final double number;
  final String name;
  final int votes;
  final String createdAtFormatted;

  /// Epoch seconds (mangafire `createdAt`) — preferred over
  /// [createdAtFormatted] when present.
  final int? createdAtEpoch;

  /// Chapter language code when provided (mangafire `language`).
  final String? language;
  final int? groupId;
  final String? groupName;
  final bool isOfficial;

  factory ComixChapter.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>?;
    final createdAt = json['createdAt'];
    final epoch = createdAt is num
        ? createdAt.toInt()
        : int.tryParse('${createdAt ?? ''}');
    return ComixChapter(
      id: (json['id'] as num).toInt(),
      url: json['url'] as String? ?? '',
      number: (json['number'] as num).toDouble(),
      name: json['name'] as String? ?? '',
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      createdAtFormatted: json['createdAtFormatted'] as String? ??
          json['created_at_formatted'] as String? ??
          '',
      createdAtEpoch: epoch,
      language: json['language'] as String?,
      groupId: (group?['id'] as num?)?.toInt(),
      groupName: group?['name'] as String?,
      isOfficial: json['isOfficial'] as bool? ?? false,
    );
  }

  /// Reader chapter path, e.g. `title/{slug}/{id}-chapter-{n}`.
  String chapterPath(String mangaSlug) {
    final index = url.indexOf('/title/');
    if (index != -1) return url.substring(index + 1);
    final num = number.truncateToDouble() == number
        ? number.toInt().toString()
        : number.toString();
    return 'title/$mangaSlug/$id-chapter-$num';
  }

  String displayName() {
    final num = number.truncateToDouble() == number
        ? number.toInt().toString()
        : number.toString();
    final base = 'Chapter $num';
    return name.isEmpty ? base : '$base: $name';
  }

  String scanlator() {
    if (groupName != null && groupName!.isNotEmpty) return groupName!;
    if (isOfficial) return 'Official';
    return 'Unknown';
  }

  DateTime? uploadDate() {
    final epoch = createdAtEpoch;
    if (epoch != null && epoch > 0) {
      // Heuristic: seconds (<1e12) vs millis.
      final millis = epoch < 1000000000000 ? epoch * 1000 : epoch;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final parsed = parseRelativeDate(createdAtFormatted);
    return parsed == null ? null : DateTime.fromMillisecondsSinceEpoch(parsed);
  }

  static final _dateRegex = RegExp(
      r'^(\d+)\s*(s|m|h|d|w|mo|mos|y|yr|yrs|min|mins|sec|secs|hr|hrs|day|days|week|weeks|month|months|year|years)$');

  /// Parses keiyoushi relative dates (`3 days ago`) to epoch millis.
  static int? parseRelativeDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    var trimmed = dateStr.trim().toLowerCase();
    if (trimmed.endsWith(' ago')) {
      trimmed = trimmed.substring(0, trimmed.length - 4);
    }
    final match = _dateRegex.firstMatch(trimmed);
    if (match == null) return null;
    final amount = int.tryParse(match.group(1)!) ?? 0;
    final unit = match.group(2)!;
    const minute = 60 * 1000;
    const hour = 60 * minute;
    const day = 24 * hour;
    final delta = switch (unit) {
      's' || 'sec' || 'secs' => 1000 * amount,
      'm' || 'min' || 'mins' => minute * amount,
      'h' || 'hr' || 'hrs' => hour * amount,
      'd' || 'day' || 'days' => day * amount,
      'w' || 'week' || 'weeks' => 7 * day * amount,
      'mo' || 'mos' || 'month' || 'months' => 30 * day * amount,
      _ => 365 * day * amount,
    };
    return DateTime.now().millisecondsSinceEpoch - delta;
  }
}

class ChapterPagesResponse {
  const ChapterPagesResponse(this.baseUrl, this.items);

  final String baseUrl;
  final List<ChapterPageDto> items;

  factory ChapterPagesResponse.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final pages = result['pages'] as Map<String, dynamic>? ?? {};
    return ChapterPagesResponse(
      pages['baseUrl'] as String? ?? pages['base_url'] as String? ?? '',
      ((pages['items'] as List?) ?? [])
          .map((e) => ChapterPageDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChapterPageDto {
  const ChapterPageDto(this.url, {this.s = 0});

  final String url;
  final int s;

  factory ChapterPageDto.fromJson(Map<String, dynamic> json) => ChapterPageDto(
        json['url'] as String? ?? '',
        s: (json['s'] as num?)?.toInt() ?? 0,
      );
}

extension _StringBlank on String {
  bool get isNotBlank => trim().isNotEmpty;
}

/// MangaFire title detail envelope (`/api/titles/{hid}`).
///
/// Field selectors mirror the live `mangafire-config.json` detail mapping
/// (`$.data.hid`, `$.data.synopsisHtml`, `$.data.poster.large`,
/// `$.data.languages[*]`, tagRelations `$.data.genres[*]` /
/// `$.data.authors[*]` with `title`). Accepts both `{data: {...}}` and
/// flat envelopes defensively.
class MangafireDetail {
  const MangafireDetail({
    required this.hid,
    required this.title,
    this.synopsisHtml,
    this.posterLarge,
    this.status = '',
    this.type = '',
    this.languages = const [],
    this.genres = const [],
    this.authors = const [],
    this.year,
  });

  final String hid;
  final String title;
  final String? synopsisHtml;
  final String? posterLarge;
  final String status;
  final String type;
  final List<String> languages;
  final List<String> genres;
  final List<String> authors;
  final int? year;

  static List<String> _titles(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e is Map ? '${e['title'] ?? ''}' : '$e')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  factory MangafireDetail.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final poster = data['poster'];
    return MangafireDetail(
      hid: '${data['hid'] ?? ''}',
      title: '${data['title'] ?? ''}',
      synopsisHtml:
          data['synopsisHtml'] as String? ?? data['synopsis'] as String?,
      posterLarge: poster is Map ? poster['large'] as String? : null,
      status: '${data['status'] ?? ''}',
      type: '${data['type'] ?? ''}',
      languages: _titles(data['languages']),
      genres: _titles(data['genres'] ?? data['genre']),
      authors: _titles(data['authors'] ?? data['author']),
      year: (data['year'] as num?)?.toInt(),
    );
  }

  /// Plain-text description (HTML stripped).
  String description() {
    final raw = synopsisHtml ?? '';
    return raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}
