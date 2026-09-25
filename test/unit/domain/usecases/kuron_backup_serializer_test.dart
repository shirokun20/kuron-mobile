import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_parser.dart';
import 'package:nhasixapp/domain/usecases/exports/kuron_backup_serializer.dart';

Uint8List zipWithPayload(String name, List<int> content) {
  final archive = Archive()
    ..addFile(ArchiveFile(name, content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

KuronBackup sample() => KuronBackup(
      favorites: const [
        KuronBackupFavorite(
          id: '123',
          sourceId: 'nhentai',
          title: 'Pretty 123',
          coverUrl: 'https://t.nhentai.net/galleries/456/cover.webp',
        ),
      ],
      collections: const [
        KuronBackupCollection(id: 'c1', name: 'Reading'),
      ],
      collectionMembers: const [
        KuronBackupCollectionMember(
          collectionId: 'c1',
          favoriteId: '123',
          sourceId: 'nhentai',
        ),
      ],
      history: const [
        KuronBackupHistory(
          contentId: '123',
          sourceId: 'nhentai',
          lastViewed: null,
          title: 'Pretty 123',
        ),
      ],
      positions: const [
        KuronBackupPosition(
          contentId: '123',
          currentPage: 6,
          totalPages: 270,
        ),
      ],
      settings: const {'theme_settings': '{"mode":"dark"}'},
    );

void main() {
  final parser = KuronBackupParser();

  group('round trip', () {
    test('serialize → zip → parse yields the same payload', () {
      final bytes = KuronBackupSerializer.toZipBytesFromBackup(sample());
      final parsed = parser.parseBytes(bytes);

      expect(parsed.formatVersion, kuronBackupSupportedVersion);
      expect(parsed.favorites.single.id, '123');
      expect(parsed.favorites.single.coverUrl, contains('cover.webp'));
      expect(parsed.collections.single.name, 'Reading');
      expect(parsed.collectionMembers.single.favoriteId, '123');
      expect(parsed.history.single.title, 'Pretty 123');
      expect(parsed.positions.single.currentPage, 6);
      expect(parsed.positions.single.totalPages, 270);
      expect(parsed.settings['theme_settings'], '{"mode":"dark"}');
      expect(parsed.malformedRows, 0);
    });

    test('file name follows KuronBackup_<epoch>.zip', () {
      final name = KuronBackupSerializer.fileName(
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(name, 'KuronBackup_1700000000000.zip');
    });
  });

  group('parse entry points', () {
    test('raw JSON payload is accepted', () {
      final raw = utf8.encode(jsonEncode(sample().toJson()));
      expect(parser.parseBytes(Uint8List.fromList(raw)).favorites.length, 1);
    });

    test('archive with decoy entries picks kuron-database.json', () {
      final archive = Archive()
        ..addFile(ArchiveFile('ScrapedTags.json', 2, [1, 2]))
        ..addFile(ArchiveFile('__MACOSX/._kuron-database.json', 3, [1, 2, 3]));
      final payload = utf8.encode(jsonEncode(sample().toJson()));
      archive
          .addFile(ArchiveFile('kuron-database.json', payload.length, payload));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(parser.parseBytes(bytes).positions.single.currentPage, 6);
    });

    test('archive without the payload errors before any write', () {
      final bytes = zipWithPayload('other.json', utf8.encode('{}'));
      expect(() => parser.parseBytes(bytes), throwsFormatException);
    });
  });

  group('version gate', () {
    test('newer formatVersion is rejected', () {
      final payload = utf8.encode(jsonEncode({
        'formatVersion': kuronBackupSupportedVersion + 1,
        'favorites': <Object>[],
      }));
      expect(
        () => parser.parseBytes(Uint8List.fromList(payload)),
        throwsA(isA<UnsupportedBackupVersionException>()
            .having((e) => e.found, 'found', kuronBackupSupportedVersion + 1)),
      );
    });

    test('older formatVersion is accepted', () {
      final payload = utf8
          .encode(jsonEncode({'formatVersion': 1, 'favorites': <Object>[]}));
      expect(parser.parseBytes(Uint8List.fromList(payload)).formatVersion, 1);
    });

    test('missing formatVersion defaults to the supported version', () {
      final payload = utf8.encode(jsonEncode({'favorites': <Object>[]}));
      expect(
        parser.parseBytes(Uint8List.fromList(payload)).formatVersion,
        kuronBackupSupportedVersion,
      );
    });
  });

  group('tolerance', () {
    test('missing categories come back empty', () {
      final payload = utf8.encode(jsonEncode({'formatVersion': 1}));
      final parsed = parser.parseBytes(Uint8List.fromList(payload));
      expect(parsed.favorites, isEmpty);
      expect(parsed.collections, isEmpty);
      expect(parsed.collectionMembers, isEmpty);
      expect(parsed.history, isEmpty);
      expect(parsed.positions, isEmpty);
      expect(parsed.settings, isEmpty);
      expect(parsed.malformedRows, 0);
    });

    test('malformed rows are counted, the rest still parses', () {
      final payload = utf8.encode(jsonEncode({
        'formatVersion': 1,
        'favorites': [
          {'id': '1', 'sourceId': 'nhentai'},
          {'broken': true},
        ],
        'positions': [
          {'contentId': '1', 'currentPage': 2},
          {'contentId': '2'},
        ],
        'settings': {'theme_settings': '{"a":1}', 'bad': 5},
      }));
      final parsed = parser.parseBytes(Uint8List.fromList(payload));

      expect(parsed.favorites.length, 1);
      // the position row without currentPage is unreadable, the good one stays
      expect(parsed.positions.length, 1);
      expect(parsed.positions.single.currentPage, 2);
      expect(parsed.settings.keys, ['theme_settings']);
      // broken favorite + broken position + non-string settings value
      expect(parsed.malformedRows, 3);
    });

    test('non-object payload is rejected', () {
      expect(
        () => parser.parseBytes(Uint8List.fromList(utf8.encode('[]'))),
        throwsFormatException,
      );
    });
  });
}
