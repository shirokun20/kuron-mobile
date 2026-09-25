import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'kuron_backup.dart';

/// Entry payload name inside `KuronBackup_*.zip`.
const String kuronBackupPayloadName = 'kuron-database.json';

/// Thrown when a payload declares a [KuronBackup.formatVersion] this app cannot
/// restore. Raised before any write happens.
class UnsupportedBackupVersionException implements Exception {
  const UnsupportedBackupVersionException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'Unsupported backup formatVersion $found (this app supports up to $supported)';
}

/// Reads `KuronBackup_*.zip` (or a raw payload) into a [KuronBackup].
///
/// Tolerant by design: a missing category is empty, an unreadable row counts as
/// malformed, and only a too-new [KuronBackup.formatVersion] is fatal.
class KuronBackupParser {
  /// Accepts a backup ZIP or a raw `kuron-database.json` payload. ZIP detection
  /// is content-based so a `.json` picked from a file manager also works.
  KuronBackup parseBytes(Uint8List bytes, {String? fileName}) {
    if (!(fileName ?? '').toLowerCase().endsWith('.json')) {
      try {
        return parseJson(utf8.decode(bytes));
      } on FormatException {
        return parseZip(bytes);
      }
    }
    return parseJson(utf8.decode(bytes));
  }

  KuronBackup parseZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final name = file.name;
      if (name.startsWith('__MACOSX/')) {
        continue;
      }
      final base = name.split('/').last.toLowerCase();
      if (base == kuronBackupPayloadName) {
        return parseJson(utf8.decode(file.content));
      }
    }
    throw const FormatException('No $kuronBackupPayloadName found in archive');
  }

  KuronBackup parseJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Kuron backup is not a JSON object');
    }
    final version = int.tryParse('${decoded['formatVersion']}') ??
        kuronBackupSupportedVersion;
    if (version > kuronBackupSupportedVersion) {
      throw UnsupportedBackupVersionException(
        version,
        kuronBackupSupportedVersion,
      );
    }

    var malformed = 0;
    List<T> rows<T>(
      String key,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final rawRows = decoded[key];
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

    final settings = <String, String>{};
    final rawSettings = decoded['settings'];
    if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        // Settings travel as raw JSON strings per key so a restore can decide
        // per key; a non-string value is a malformed row, not a crash.
        if (entry.value is String) {
          settings['${entry.key}'] = entry.value as String;
        } else {
          malformed++;
        }
      }
    } else if (rawSettings != null) {
      malformed++;
    }

    return KuronBackup(
      formatVersion: version,
      favorites: rows('favorites', KuronBackupFavorite.fromJson),
      collections: rows('collections', KuronBackupCollection.fromJson),
      collectionMembers:
          rows('collectionMembers', KuronBackupCollectionMember.fromJson),
      history: rows('history', KuronBackupHistory.fromJson),
      positions: rows('positions', KuronBackupPosition.fromJson),
      settings: settings,
      malformedRows: malformed,
    );
  }
}
