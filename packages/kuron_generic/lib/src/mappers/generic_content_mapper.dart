// Central mapping layer: extracted field maps → kuron_core domain entities.
///
// Both [GenericScraperAdapter] and [GenericRestAdapter] extract raw field
// values from HTML / JSON according to the source config and store them in a
// plain `Map<String, dynamic>`.  This class converts those maps into typed
// [Content] and [Chapter] objects **without knowing anything about the
// extraction mechanism or the source-specific config keys**.
///
// ### Supported field names (keys in the extracted map)
// Scalar strings: `id`, `title`, `coverUrl`, `language`, `pageCount`,
// `uploadDate`, `mediaId`, `englishTitle`, `japaneseTitle`, `favorites`.
///
// String lists: `artists`, `characters`, `parodies`, `groups`.
///
// Tag variants:
// - `tags`       — `List<String>` of tag names → typed as `type: "tag"`.
// - `tagObjects` — `List<Map<String, dynamic>>` of full nhentai tag objects
//                  `{id, name, type, count}`.  Processed by [splitTagObjects].
library;

import 'package:kuron_core/kuron_core.dart';

class GenericContentMapper {
  const GenericContentMapper._();

  // ── Public factory methods ─────────────────────────────────────────────────

  // Build a [Content] entity for **list / search result** items.
  ///
  // [fields] keys should use the canonical field names documented in the
  // library-level doc-comment above.
  static Content toListItem(
    Map<String, dynamic> fields, {
    required String sourceId,
  }) {
    final tagsResolved = _resolveTags(fields);

    return Content(
      id: _str(fields, 'id'),
      sourceId: sourceId,
      title: _extractTitle(fields),
      coverUrl: _str(fields, 'coverUrl'),
      tags: tagsResolved.tags,
      artists: tagsResolved.artists.isNotEmpty
          ? tagsResolved.artists
          : _strListAny(fields, const ['artists', 'artist']),
      characters: tagsResolved.characters.isNotEmpty
          ? tagsResolved.characters
          : _strListAny(fields, const ['characters', 'character']),
      parodies: tagsResolved.parodies.isNotEmpty
          ? tagsResolved.parodies
          : _strListAny(fields, const ['parodies', 'parody']),
      groups: tagsResolved.groups.isNotEmpty
          ? tagsResolved.groups
          : _strListAny(fields, const ['groups', 'group', 'publisher']),
      language: tagsResolved.language.isNotEmpty
          ? tagsResolved.language
          : _resolveLanguage(fields),
      pageCount: _int(fields, 'pageCount'),
      imageUrls: const [],
      uploadDate: _resolveUploadDate(fields),
      favorites: _int(fields, 'favorites'),
      status: _status(fields),
      totalChapters: _intOrNull(fields, 'pageCount'),
      mediaId: _nullableString(fields['mediaId']),
    );
  }

  // Build a [Content] entity for **detail pages** (superset of list fields).
  ///
  // [imageUrls] and [chapters] are passed in separately because they are
  // resolved after the main fields are extracted.
  static Content toDetail(
    String contentId,
    Map<String, dynamic> fields, {
    required String sourceId,
    List<String> imageUrls = const [],
    List<Chapter>? chapters,
  }) {
    final tagsResolved = _resolveTags(fields);
    final coverUrl = _str(fields, 'coverUrl').let(
      (s) => s.isNotEmpty ? s : (imageUrls.isNotEmpty ? imageUrls.first : ''),
    );
    final id = _str(fields, 'id').let((s) => s.isNotEmpty ? s : contentId);
    final rawPageCount = _int(fields, 'pageCount');
    final pageCount = chapters != null
        ? chapters.length
        : (rawPageCount > 0 ? rawPageCount : imageUrls.length);

    // Inject uploader/author/artist/publisher as typed Tags so detail screens
    // can display and navigate to them via tagQueryMapping.
    var resolvedTags = tagsResolved.tags;
    final uploaderName = _str(fields, 'uploader').trim();
    if (uploaderName.isNotEmpty) {
      final alreadyPresent = resolvedTags.any(
        (t) =>
            t.type == 'uploader' &&
            t.name.toLowerCase() == uploaderName.toLowerCase(),
      );
      if (!alreadyPresent) {
        resolvedTags = [
          ...resolvedTags,
          Tag(id: 0, name: uploaderName, type: 'uploader', count: 0),
        ];
      }
    }

    // Author → type: "author"
    final authorName = _str(fields, 'author').trim();
    if (authorName.isNotEmpty) {
      final alreadyPresent = resolvedTags.any(
        (t) =>
            t.type == 'author' &&
            t.name.toLowerCase() == authorName.toLowerCase(),
      );
      if (!alreadyPresent) {
        resolvedTags = [
          ...resolvedTags,
          Tag(id: 0, name: authorName, type: 'author', count: 0),
        ];
      }
    }

    // Artist → type: "artist"
    final allArtistNames = tagsResolved.artists.isNotEmpty
        ? tagsResolved.artists
        : _strListAny(fields, const ['artists', 'artist']);
    for (final an in allArtistNames) {
      if (an.isEmpty) continue;
      final alreadyPresent = resolvedTags.any(
        (t) => t.type == 'artist' && t.name.toLowerCase() == an.toLowerCase(),
      );
      if (!alreadyPresent) {
        resolvedTags = [
          ...resolvedTags,
          Tag(id: 0, name: an, type: 'artist', count: 0),
        ];
      }
    }

    // Publisher → type: "publisher"
    final publisherName = _str(fields, 'publisher').trim();
    if (publisherName.isNotEmpty) {
      final alreadyPresent = resolvedTags.any(
        (t) =>
            t.type == 'publisher' &&
            t.name.toLowerCase() == publisherName.toLowerCase(),
      );
      if (!alreadyPresent) {
        resolvedTags = [
          ...resolvedTags,
          Tag(id: 0, name: publisherName, type: 'publisher', count: 0),
        ];
      }
    }

    // Store availableTranslatedLanguages as typed tags so the detail UI can
    // show language chips even when chapters are filtered to one language.
    final availLangs = _strList(fields, 'availableTranslatedLanguages');
    for (final lang in availLangs) {
      final alreadyPresent = resolvedTags.any(
        (t) =>
            t.type == 'available_language' &&
            t.name.toLowerCase() == lang.toLowerCase(),
      );
      if (!alreadyPresent) {
        resolvedTags = [
          ...resolvedTags,
          Tag(id: 0, name: lang, type: 'available_language', count: 0),
        ];
      }
    }

    return Content(
      id: id,
      sourceId: sourceId,
      title: _extractTitle(fields),
      coverUrl: coverUrl,
      tags: resolvedTags,
      artists: tagsResolved.artists.isNotEmpty
          ? tagsResolved.artists
          : _strListAny(fields, const ['artists', 'artist']),
      characters: tagsResolved.characters.isNotEmpty
          ? tagsResolved.characters
          : _strListAny(fields, const ['characters', 'character']),
      parodies: tagsResolved.parodies.isNotEmpty
          ? tagsResolved.parodies
          : _strListAny(fields, const ['parodies', 'parody']),
      groups: tagsResolved.groups.isNotEmpty
          ? tagsResolved.groups
          : _strListAny(fields, const ['groups', 'group', 'publisher']),
      language: tagsResolved.language.isNotEmpty
          ? tagsResolved.language
          : _resolveLanguage(fields),
      pageCount: pageCount,
      imageUrls: imageUrls,
      chapters: chapters,
      uploadDate: _resolveUploadDate(fields),
      favorites: _int(fields, 'favorites'),
      mediaId: _nullableString(fields['mediaId']),
      englishTitle: _nullableString(fields['englishTitle']),
      japaneseTitle: _nullableString(fields['japaneseTitle']),
      subTitle: _extractDescription(fields),
      status: _status(fields),
      totalChapters: rawPageCount > 0 ? rawPageCount : null,
    );
  }

  // Build a [Chapter] entity from extracted fields.
  ///
  // Supported keys: `id`, `title`, `url`, `date`, `externalUrl`, `pages`,
  // `isUnavailable`. All optional fields are nullable for backward compat
  // with sources that don't expose them.
  static Chapter toChapter(Map<String, dynamic> fields) {
    final id = _str(fields, 'id');
    final url = _str(fields, 'url');
    final language = _str(fields, 'language').trim();
    final scanGroup = _str(fields, 'scanGroup').trim();
    final scanlator = _str(fields, 'scanlator').trim();
    final finalScanGroup = scanGroup.isNotEmpty
        ? scanGroup
        : (scanlator.isNotEmpty ? scanlator : null);

    final externalUrl = _nullableString(fields['externalUrl']);
    final pages = _intOrNull(fields, 'pages');
    final isUnavailable = fields['isUnavailable'] == true;

    return Chapter(
      id: id.isNotEmpty ? id : url,
      title: _buildChapterTitle(fields),
      url: url,
      uploadDate: _dateNullable(fields, 'date'),
      scanGroup: finalScanGroup,
      language: language.isNotEmpty ? language : null,
      externalUrl: externalUrl,
      pages: pages,
      isUnavailable: isUnavailable,
    );
  }

  // ── Tag processing ─────────────────────────────────────────────────────────

  // Split nhentai-style `tagObjects` (unified array with `type` field) into
  // typed lists.  Used by REST sources that return a single `tags[]` array.
  static TagSplit splitTagObjects(List<Map<String, dynamic>> objects) {
    final tags = <Tag>[];
    final artists = <String>[];
    final characters = <String>[];
    final parodies = <String>[];
    final groups = <String>[];
    final languages = <String>[];

    for (final obj in objects) {
      final name = obj['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final type =
          obj['type']?.toString() ?? obj['namespace']?.toString() ?? 'tag';
      final id = (obj['id'] as num?)?.toInt() ?? 0;
      final count = (obj['count'] as num?)?.toInt() ?? 0;
      // Preserve the source href slug so tag clicks hit the real archive
      // instead of a re-slugified display name (CJK/parenthesis names do not
      // round-trip). #69.
      final slug = _slugOf(obj['slug']);
      final urlRaw = obj['url'];
      final url = urlRaw is String ? urlRaw.trim() : '';

      Tag make() => Tag(
            id: id,
            name: name,
            type: type,
            count: count,
            slug: slug,
            url: url,
          );

      switch (type) {
        case 'artist':
          artists.add(name);
          tags.add(make());
        case 'character':
          characters.add(name);
          tags.add(make());
        case 'parody':
          parodies.add(name);
          tags.add(make());
        case 'group':
          groups.add(name);
          tags.add(make());
        case 'language':
          if (name != 'translated') {
            languages.add(name);
            tags.add(make());
          }
        default:
          tags.add(make());
      }
    }

    return TagSplit(
      tags: tags,
      artists: artists,
      characters: characters,
      parodies: parodies,
      groups: groups,
      language: languages.isNotEmpty ? languages.first : '',
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static TagSplit _resolveTags(Map<String, dynamic> fields) {
    // Priority 1: pre-split tagObjects
    final rawTagObjects = fields['tagObjects'];
    if (rawTagObjects is List && rawTagObjects.isNotEmpty) {
      final objects = rawTagObjects.whereType<Map<String, dynamic>>().toList();
      if (objects.isNotEmpty) return splitTagObjects(objects);
    }

    // Priority 2: List<Tag> already resolved — under `tags` or any taxonomy
    // key (`extractTagObjects` on genres/author/artist fields keeps the
    // original href slug + url per item, so taps hit the exact archive
    // instead of a re-slugified guess). Bucketed by type like
    // splitTagObjects so creator rows and fallbacks stay clean.
    final tagged = <Tag>[];
    for (final key in const [
      'tags',
      'tag',
      'genres',
      'genre',
      'authors',
      'author',
      'artists',
      'artist',
    ]) {
      final v = fields[key];
      if (v is List) tagged.addAll(v.whereType<Tag>());
    }
    if (tagged.isNotEmpty) {
      final artists = <String>[];
      final characters = <String>[];
      final parodies = <String>[];
      final groups = <String>[];
      String language = '';
      for (final t in tagged) {
        switch (t.type) {
          case 'artist':
            artists.add(t.name);
          case 'character':
            characters.add(t.name);
          case 'parody':
            parodies.add(t.name);
          case 'group':
          case 'publisher':
            groups.add(t.name);
          case 'language':
            if (t.name != 'translated' && language.isEmpty) {
              language = t.name;
            }
        }
      }
      return TagSplit(
        tags: tagged,
        artists: artists,
        characters: characters,
        parodies: parodies,
        groups: groups,
        language: language,
      );
    }

    // Priority 3: List<String> tag names. `genre`/`genres` keep their own
    // type so tag taps route to genreSearch instead of tagSearch
    // (hentai4free has separate /hentai-genre/ vs /hentai-tag/ archives;
    // previously both flattened to `tag` and every tap hit genreSearch).
    // Also additive: _strListAny used to return only the first non-empty
    // key, silently dropping `genres` whenever `tags` existed.
    final resolved = _strListAny(fields, const ['tags', 'tag'])
        .map((n) => Tag(id: 0, name: n, type: 'tag', count: 0))
        .toList();
    resolved.addAll(
      _strListAny(fields, const ['genre', 'genres']).map(
        (n) => Tag(id: 0, name: n, type: 'genre', count: 0),
      ),
    );
    return TagSplit(
      tags: resolved,
      artists: const [],
      characters: const [],
      parodies: const [],
      groups: const [],
      language: '',
    );
  }

  static String _str(
    Map<String, dynamic> f,
    String key, {
    String fallback = '',
  }) {
    final v = f[key];
    if (v is String) return v.isEmpty ? fallback : v;
    if (v is num || v is bool) {
      final asString = v.toString();
      return asString.isEmpty ? fallback : asString;
    }
    if (v is Map && v.isNotEmpty) {
      final firstVal = v.values.first;
      if (firstVal is String && firstVal.isNotEmpty) return firstVal;
    }
    if (v is List && v.isNotEmpty) {
      final firstVal = v.first;
      if (firstVal is String && firstVal.isNotEmpty) return firstVal;
    }
    return fallback;
  }

  static List<String> _strList(Map<String, dynamic> f, String key) {
    final v = f[key];
    if (v is List<String>) return v;
    if (v is List) {
      return v
          .map((e) => _normalizeEntityName(e.toString()))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is String && v.isNotEmpty) {
      final normalized = _normalizeEntityName(v);
      return normalized.isEmpty ? const [] : [normalized];
    }
    return const [];
  }

  static List<String> _strListAny(Map<String, dynamic> f, List<String> keys) {
    for (final key in keys) {
      final values = _strList(f, key);
      if (values.isNotEmpty) return values;
    }
    return const [];
  }

  // Href-derived slug: trim, and drop anything that is not a usable path
  // segment. Kept verbatim (including percent-escapes) because it is the
  // site's own archive key. Empty means "no usable slug".
  static String? _slugOf(dynamic raw) {
    if (raw is! String) return null;
    final slug = raw.trim();
    return slug.isEmpty ? null : slug;
  }

  static String _normalizeEntityName(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';

    // Drop trailing count labels like "Satou Tomoyuki (6)".
    return cleaned.replaceFirst(RegExp(r'\s*\([0-9,]+\)\s*$'), '').trim();
  }

  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is Map && value.isNotEmpty) {
      final preferred = value['en'] ?? value['value'];
      if (preferred != null) {
        final normalized = preferred.toString().trim();
        if (normalized.isNotEmpty) return normalized;
      }
      for (final candidate in value.values) {
        if (candidate == null) continue;
        final normalized = candidate.toString().trim();
        if (normalized.isNotEmpty) return normalized;
      }
      return null;
    }
    if (value is List && value.isNotEmpty) {
      for (final candidate in value) {
        if (candidate == null) continue;
        final normalized = candidate.toString().trim();
        if (normalized.isNotEmpty) return normalized;
      }
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _extractTitle(Map<String, dynamic> fields) {
    // 1. Try the main title object, prioritize english if available.
    final t = fields['title'];
    if (t is Map && t['en'] != null && t['en'].toString().isNotEmpty) {
      return t['en'].toString();
    }

    // 2. Try to find an English title in altTitles.
    final altTitles = fields['altTitles'];
    if (altTitles is List) {
      for (final alt in altTitles) {
        if (alt is Map &&
            alt['en'] != null &&
            alt['en'].toString().isNotEmpty) {
          return alt['en'].toString();
        }
      }
    }

    // 3. Fallback to generic map/list-aware string extraction.
    return _str(fields, 'title', fallback: 'Unknown');
  }

  static String _extractDescription(Map<String, dynamic> fields) {
    final subtitle = _str(fields, 'subTitle');
    if (subtitle.isNotEmpty) return subtitle;

    final raw = fields['description'];
    if (raw is String) return raw;
    if (raw is Map) {
      final en = raw['en'];
      if (en != null && en.toString().isNotEmpty) {
        return en.toString();
      }
      for (final value in raw.values) {
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
    }
    return '';
  }

  static String _resolveLanguage(Map<String, dynamic> fields) {
    final language = _str(fields, 'language');
    if (language.isNotEmpty) return language;

    final originalLanguage = _str(fields, 'originalLanguage');
    if (originalLanguage.isNotEmpty) return originalLanguage;

    final available = _strList(fields, 'availableTranslatedLanguages');
    if (available.isNotEmpty) return available.first;

    return 'unknown';
  }

  static String _buildChapterTitle(Map<String, dynamic> fields) {
    final chapterNum = _str(fields, 'chapterNum').trim();
    final volume = _str(fields, 'volume').trim();
    final title = _str(fields, 'title').trim();

    if (volume.isNotEmpty && chapterNum.isNotEmpty) {
      return 'Vol.$volume Ch.$chapterNum';
    }
    if (chapterNum.isNotEmpty) {
      return 'Ch.$chapterNum';
    }
    if (volume.isNotEmpty) {
      return 'Vol.$volume';
    }
    if (title.isNotEmpty) {
      return title;
    }
    // Some one-shot sources provide no chapter/volume/title metadata.
    return 'Oneshot';
  }

  static ContentStatus _status(Map<String, dynamic> fields) {
    final raw = _str(fields, 'status').toLowerCase().trim();
    switch (raw) {
      case 'ongoing':
        return ContentStatus.ongoing;
      case 'completed':
        return ContentStatus.completed;
      case 'licensed':
        return ContentStatus.licensed;
      case 'publishing_finished':
      case 'publishingfinished':
      case 'publishing-finished':
        return ContentStatus.publishingFinished;
      case 'cancelled':
      case 'canceled':
        return ContentStatus.cancelled;
      case 'hiatus':
      case 'on_hiatus':
      case 'on-hiatus':
        return ContentStatus.onHiatus;
      default:
        return ContentStatus.unknown;
    }
  }

  static int _int(Map<String, dynamic> f, String key) {
    final v = f[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int? _intOrNull(Map<String, dynamic> f, String key) {
    final value = _int(f, key);
    return value > 0 ? value : null;
  }

  static DateTime _resolveUploadDate(Map<String, dynamic> fields) {
    return _dateNullable(fields, 'uploadDate') ??
        _dateNullable(fields, 'updatedDate') ??
        _dateNullable(fields, 'updatedOn') ??
        _dateNullable(fields, 'publishedDate') ??
        _dateNullable(fields, 'postedOn') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _dateNullable(Map<String, dynamic> f, String key) {
    final v = f[key];
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      final cleaned = v.trim();

      final numeric = int.tryParse(cleaned);
      if (numeric != null) {
        // Year-only values (e.g. "2022") should be treated as calendar years,
        // not Unix seconds (which would incorrectly map to 1970).
        if (RegExp(r'^\d{4}$').hasMatch(cleaned) &&
            numeric >= 1900 &&
            numeric <= 2100) {
          return DateTime(numeric, 1, 1);
        }

        // 13+ digits are likely milliseconds; <=10 digits are likely seconds.
        if (cleaned.length >= 13) {
          return DateTime.fromMillisecondsSinceEpoch(numeric);
        }
        return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      }

      final absolute = DateTime.tryParse(cleaned);
      if (absolute != null) return absolute;

      final monthNamed = _parseNamedMonthDate(cleaned);
      if (monthNamed != null) return monthNamed;

      final relative = _parseRelativeDate(cleaned);
      if (relative != null) return relative;
    }
    return null;
  }

  static DateTime? _parseNamedMonthDate(String raw) {
    if (raw.isEmpty) return null;
    final text = raw.trim();

    // Day-first with month abbreviation: "11 Sep 2026".
    final dmy = RegExp(
      r'^(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{4})$',
      caseSensitive: false,
    ).firstMatch(text);
    if (dmy != null) {
      const shortMonths = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final month = shortMonths[dmy.group(2)!.toLowerCase()];
      final day = int.tryParse(dmy.group(1)!);
      final year = int.tryParse(dmy.group(3)!);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }


    // Compact day-first with two-digit year: "06 Oct 26".
    final compact = RegExp(
      r'^(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{2})$',
      caseSensitive: false,
    ).firstMatch(text);
    if (compact != null) {
      const shortMonths = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final month = shortMonths[compact.group(2)!.toLowerCase()];
      final day = int.tryParse(compact.group(1)!);
      final year = int.tryParse(compact.group(3)!);
      if (month != null && day != null && year != null) {
        final fullYear = year >= 70 ? 1900 + year : 2000 + year;
        return DateTime(fullYear, month, day);
      }
    }
    // Month-first US style: "September 11, 2026".
    final match = RegExp(
      r'^(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s*(\d{4})$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    const months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };

    final month = months[match.group(1)!.toLowerCase()];
    final day = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (month == null || day == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static DateTime? _parseRelativeDate(String raw) {
    if (raw.isEmpty) return null;

    final now = DateTime.now();
    final normalized = raw
        .toLowerCase()
        .replaceFirst(RegExp(r'^(posted|uploaded|upload date|date)\s*:\s*'), '')
        .trim();

    if (normalized == 'just now' ||
        normalized == 'today' ||
        normalized == 'baru saja' ||
        normalized == 'hari ini') {
      return now;
    }
    if (normalized == 'yesterday' || normalized == 'kemarin') {
      return now.subtract(const Duration(days: 1));
    }

    // Indonesian: "7 menit lalu", "2 jam lalu", "3 hari lalu", "1 minggu lalu", "2 bulan lalu", "1 tahun lalu"
    final idMatch = RegExp(
      r'^(\d+|a|an|satu|se)\s+(detik|menit|jam|hari|minggu|bulan|tahun)s?\s+lalu$',
    ).firstMatch(normalized);
    if (idMatch != null) {
      final quantityRaw = idMatch.group(1) ?? '0';
      final unit = idMatch.group(2) ?? '';
      final quantity = (quantityRaw == 'a' ||
              quantityRaw == 'an' ||
              quantityRaw == 'satu' ||
              quantityRaw == 'se')
          ? 1
          : (int.tryParse(quantityRaw) ?? 0);
      if (quantity <= 0) return null;
      switch (unit) {
        case 'detik':
          return now.subtract(Duration(seconds: quantity));
        case 'menit':
          return now.subtract(Duration(minutes: quantity));
        case 'jam':
          return now.subtract(Duration(hours: quantity));
        case 'hari':
          return now.subtract(Duration(days: quantity));
        case 'minggu':
          return now.subtract(Duration(days: quantity * 7));
        case 'bulan':
          return now.subtract(Duration(days: quantity * 30));
        case 'tahun':
          return now.subtract(Duration(days: quantity * 365));
        default:
          return null;
      }
    }

    final match = RegExp(
      r'^(\d+|a|an)\s+(second|minute|hour|day|week|month|year)s?\s+ago$',
    ).firstMatch(normalized);
    if (match == null) return null;

    final quantityRaw = match.group(1) ?? '0';
    final unit = match.group(2) ?? '';
    final quantity = (quantityRaw == 'a' || quantityRaw == 'an')
        ? 1
        : (int.tryParse(quantityRaw) ?? 0);
    if (quantity <= 0) return null;

    switch (unit) {
      case 'second':
        return now.subtract(Duration(seconds: quantity));
      case 'minute':
        return now.subtract(Duration(minutes: quantity));
      case 'hour':
        return now.subtract(Duration(hours: quantity));
      case 'day':
        return now.subtract(Duration(days: quantity));
      case 'week':
        return now.subtract(Duration(days: quantity * 7));
      case 'month':
        return now.subtract(Duration(days: quantity * 30));
      case 'year':
        return now.subtract(Duration(days: quantity * 365));
      default:
        return null;
    }
  }
}

// ── Internal DTOs ─────────────────────────────────────────────────────────────

// Result of splitting a unified nhentai-style tag array by type.
class TagSplit {
  const TagSplit({
    required this.tags,
    required this.artists,
    required this.characters,
    required this.parodies,
    required this.groups,
    required this.language,
  });

  final List<Tag> tags;
  final List<String> artists;
  final List<String> characters;
  final List<String> parodies;
  final List<String> groups;
  final String language;
}

extension _StringX on String {
  // Apply [fn] to this string and return its result.
  T let<T>(T Function(String) fn) => fn(this);
}
