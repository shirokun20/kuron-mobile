import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'nclient_backup.dart';

// Pure-Dart parser for NClient V2/V3 `Backup_*.zip` / raw `Database.json`.
// Tables Tags/GalleryTags/Bookmark/Downloads/Settings are never mapped to
// model objects (real backup: 85k tag rows) — dropped right after decode.
class NclientBackupParser {
  NclientBackup parseBytes(Uint8List bytes, {String? fileName}) {
    final lower = (fileName ?? '').toLowerCase();
    if (lower.endsWith('.json')) return parseJson(utf8.decode(bytes));
    try {
      return parseJson(utf8.decode(bytes));
    } on FormatException {
      return parseZip(
          bytes); // ponytail: not JSON? must be ZIP. else it throws.
    }
  }

  NclientBackup parseZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      final name = file.name;
      if (name.startsWith('__MACOSX/') || !file.isFile) continue;
      final base = name.split('/').last.toLowerCase();
      if (base == 'database.json') return parseJson(utf8.decode(file.content));
    }
    throw const FormatException('No NClient database found in archive');
  }

  NclientBackup parseJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('NClient database is not a JSON object');
    }
    // ponytail: drop heavy/ignored tables before mapping so 85k tag rows
    // stay raw maps and become garbage ASAP instead of model objects.
    decoded.remove('Tags');
    decoded.remove('GalleryTags');
    decoded.remove('Bookmark');
    decoded.remove('Downloads');

    var malformed = 0;
    List<T> rows<T>(String table, T Function(Map<String, dynamic>) fromJson) {
      final rawRows = decoded[table];
      if (rawRows is! List) return [];
      final out = <T>[];
      for (final row in rawRows) {
        try {
          if (row is! Map) throw const FormatException('row');
          out.add(fromJson(Map<String, dynamic>.from(row)));
        } catch (_) {
          malformed++;
        }
      }
      return out;
    }

    final resumes = <NclientResume>[];
    final rawResumes = decoded['Resume'];
    if (rawResumes is List) {
      for (final row in rawResumes) {
        try {
          if (row is! Map) throw const FormatException('row');
          resumes.add(NclientResume.tryParse(Map<String, dynamic>.from(row)));
        } catch (_) {
          malformed++;
        }
      }
    }

    return NclientBackup(
      galleries: rows('Gallery', NclientGallery.fromJson),
      favorites: rows('Favorite', NclientFavorite.fromJson),
      statuses: rows('Status', NclientStatus.fromJson),
      statusLinks: rows('StatusManga', NclientStatusLink.fromJson),
      history: rows('History', NclientHistory.fromJson),
      resumes: resumes,
      malformedRows: malformed,
    );
  }
}

// Extension of Gallery `pages` ("{n};cover;thumb;...") after the LAST dot:
// "/cover.jpg.webp" -> "webp". Unknown -> "jpg" via getImageExtension.
String coverExtFromPages(String? pages) {
  final parts = (pages ?? '').split(';');
  final cover = parts.length > 1 ? parts[1] : '';
  final dot = cover.lastIndexOf('.');
  if (dot < 0 || dot == cover.length - 1) return 'jpg';
  return cover.substring(dot + 1).toLowerCase();
}

// Page count = first token of `pages`. 0 when absent/unparseable.
int pageCountFromPages(String? pages) {
  final parts = (pages ?? '').split(';');
  return parts.isEmpty ? 0 : int.tryParse(parts.first) ?? 0;
}

// NClient epoch-millis (int or numeric string) -> DateTime. Null when absent.
DateTime? dateFromMillis(dynamic value) {
  final millis = value is int
      ? value
      : value is String
          ? int.tryParse(value)
          : null;
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}
